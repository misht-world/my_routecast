package com.routecast

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import android.util.Log
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import com.routecast.parse.RouteParseException
import com.routecast.proto.MessageBuilder
import java.util.concurrent.Executors

/** English status UI; import work is bounded and the last confirmed route survives restarts. */
class MainActivity : Activity() {
    private lateinit var status: TextView
    private lateinit var summary: TextView
    private lateinit var diagnostics: TextView
    private lateinit var progress: ProgressBar
    private lateinit var sendButton: Button
    private lateinit var connectButton: Button
    private lateinit var store: RouteStore
    private val logLines = ArrayDeque<String>()
    private val imports = LatestTaskRunner()
    private val saves = Executors.newSingleThreadExecutor()
    private var generation = 0
    private var link: CiqLink? = null
    private var transfer: Transfer? = null
    private var route: RouteStore.Saved? = null
    private var ready = false
    private var sending = false
    private var loading = false
    private var autoSend = false
    private var retry = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        store = RouteStore(filesDir)
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val pad = (20 * resources.displayMetrics.density).toInt()
            setPadding(pad, pad, pad, pad)
        }
        val title = TextView(this).apply { text = "RouteCast ${BuildConfig.VERSION_NAME}"; textSize = 24f }
        status = TextView(this).apply { textSize = 18f }
        summary = TextView(this).apply { textSize = 16f }
        progress = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = 100; visibility = View.GONE
        }
        sendButton = Button(this).apply { text = "Send to watch"; setOnClickListener { sendRoute() } }
        connectButton = Button(this).apply { text = "Reconnect watch"; setOnClickListener { connect() } }
        val sampleButton = Button(this).apply { text = "Load sample route"; setOnClickListener { importSample() } }
        diagnostics = TextView(this).apply { textSize = 12f; visibility = View.GONE }
        val details = Button(this).apply {
            text = "Show diagnostics"
            setOnClickListener {
                val show = diagnostics.visibility != View.VISIBLE
                diagnostics.visibility = if (show) View.VISIBLE else View.GONE
                text = if (show) "Hide diagnostics" else "Show diagnostics"
            }
        }
        for (view in listOf(title, status, summary, progress, sendButton, connectButton, sampleButton, details, diagnostics)) {
            root.addView(view)
        }
        setContentView(ScrollView(this).apply { addView(root) })
        val retained = lastNonConfigurationInstance as? RouteStore.Saved
        if (retained != null && savedInstanceState != null) {
            route = retained; renderRoute(); setStatus("Route ready. Open RouteCast on your watch, then tap Send.")
        } else if (savedInstanceState != null || !handleIntent(intent)) {
            restoreRoute()
        }
        connect()
    }

    override fun onRetainNonConfigurationInstance(): Any? = route

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    @Suppress("DEPRECATION")
    private fun handleIntent(intent: Intent?): Boolean {
        val uri = try {
            when (intent?.action) {
                Intent.ACTION_SEND -> intent.getParcelableExtra<android.os.Parcelable>(Intent.EXTRA_STREAM) as? Uri
                Intent.ACTION_VIEW -> intent.data
                else -> null
            }
        } catch (_: Exception) { null }
        if (uri == null) return false
        importRoute(true) {
            val name = try {
                contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                    if (it.moveToFirst()) it.getString(0) else null
                }
            } catch (_: Exception) { null }
            val text = contentResolver.openInputStream(uri)?.bufferedReader()?.use { RouteInput.read(it) }
                ?: throw RouteParseException("Could not read the route file.")
            RouteProcessor.process(name ?: "Shared route", text)
        }
        return true
    }

    private fun importSample() = importRoute(false) {
        val text = assets.open("short_city.gpx").bufferedReader().use { RouteInput.read(it) }
        RouteProcessor.process("Sample route", text)
    }

    private fun importRoute(sendWhenReady: Boolean, read: () -> RouteProcessor.Result) {
        val token = beginLoad()
        imports.submit {
            try {
                val result = read()
                val saved = RouteStore.Saved(result.encoded, result.totalMeters)
                runOnUiThread {
                    if (!current(token)) return@runOnUiThread
                    loading = false; route = saved; autoSend = sendWhenReady
                    renderRoute()
                    setStatus(if (ready) "Route ready. Open RouteCast on your watch." else "Route ready. Waiting for watch connection.")
                    maybeSend()
                }
            } catch (_: InterruptedException) {
                // Replaced imports never update UI.
            } catch (e: Exception) {
                runOnUiThread {
                    if (!current(token)) return@runOnUiThread
                    loading = false
                    val message = if (e is RouteParseException) e.message ?: "Invalid route file." else "Could not load this route. Try another GPX or GeoJSON file."
                    setStatus(message)
                    note("Import failed: ${e.javaClass.simpleName}")
                }
            }
        }
    }

    private fun beginLoad(): Int {
        generation++
        transfer?.cancel(); transfer = null
        sending = false; autoSend = false; retry = false; route = null; loading = true
        summary.text = ""; progress.visibility = View.GONE
        setStatus("Loading route...")
        return generation
    }

    private fun restoreRoute() {
        val token = beginLoad()
        imports.submit {
            try {
                val saved = store.load()
                runOnUiThread {
                    if (!current(token)) return@runOnUiThread
                    loading = false; route = saved; renderRoute()
                    setStatus(if (saved == null) "Share a GPX or GeoJSON route from Organic Maps to get started."
                        else "Last sent route restored. Open RouteCast on your watch to start.")
                }
            } catch (e: Exception) {
                runOnUiThread {
                    if (current(token)) {
                        loading = false; setStatus("Saved route could not be restored. Share the route again.")
                        note("Restore failed: ${e.javaClass.simpleName}")
                    }
                }
            }
        }
    }

    private fun connect() {
        transfer?.cancel(); transfer = null; sending = false; ready = false
        progress.visibility = View.GONE
        link?.stop()
        connectButton.text = "Reconnect watch"
        updateButtons()
        val connection = CiqLink(this, Config.WATCH_APP_ID_HEX) { line -> runOnUiThread { if (!isDestroyed) note(line) } }
        link = connection
        connection.onReady = {
            runOnUiThread {
                if (link !== connection || isDestroyed) return@runOnUiThread
                ready = true; updateButtons()
                if (!loading && route != null && !sending) setStatus("Watch connected. Open RouteCast on your watch, then tap Send.")
                maybeSend()
            }
        }
        connection.onDisconnected = {
            runOnUiThread {
                if (link !== connection || isDestroyed) return@runOnUiThread
                val wasSending = sending
                ready = false; transfer?.cancel(); sending = false; autoSend = false
                if (wasSending) retry = true
                progress.visibility = View.GONE
                setStatus("Watch disconnected. Reconnect, then tap Retry or Send.")
            }
        }
        connection.onUnavailable = { message ->
            runOnUiThread {
                if (link === connection && !isDestroyed && !sending) {
                    ready = false; setStatus(message)
                }
            }
        }
        try { connection.start() }
        catch (e: Exception) { setStatus("Could not connect. Open Garmin Connect, then tap Reconnect watch."); note("Connection failed: ${e.javaClass.simpleName}") }
    }

    private fun maybeSend() {
        if (autoSend && ready && !sending && !loading && route != null) {
            autoSend = false; sendRoute()
        }
    }

    private fun sendRoute() {
        val saved = route ?: return
        val connection = link ?: return
        if (!ready || sending || loading) return
        val token = generation
        sending = true; retry = false
        progress.progress = 0; progress.visibility = View.VISIBLE
        setStatus("Sending route — 0%. Keep RouteCast open on your watch.")
        transfer = Transfer(connection, MessageBuilder.build(saved.encoded),
            onProgress = { sent, total ->
                if (current(token)) {
                    val percent = sent * 100 / total
                    progress.progress = percent; status.text = "Sending route — $percent%"
                }
            },
            onDone = {
                // Persist once after durable watch confirmation, never on every GPS update.
                saves.execute {
                    var savedOnPhone = true
                    try { store.save(saved) } catch (_: Exception) { savedOnPhone = false }
                    runOnUiThread {
                        if (!current(token)) return@runOnUiThread
                        sending = false; retry = false; progress.visibility = View.GONE
                        setStatus(if (savedOnPhone) "Route saved on watch. Press START on your watch to navigate."
                            else "Route saved on watch. Phone backup failed; share again after restarting the phone app.")
                    }
                }
            },
            onError = { message ->
                if (current(token)) {
                    sending = false; retry = true; progress.visibility = View.GONE
                    setStatus(message)
                }
            }).also { it.start() }
    }

    private fun current(token: Int) = !isDestroyed && token == generation
    private fun setStatus(message: String) { status.text = message; updateButtons() }
    private fun updateButtons() {
        sendButton.text = if (retry) "Retry" else "Send to watch"
        sendButton.isEnabled = ready && route != null && !sending && !loading
        connectButton.isEnabled = !sending
    }
    private fun renderRoute() {
        val saved = route
        summary.text = if (saved == null) "" else "${saved.encoded.header.name}\n${saved.meters} m · ${saved.encoded.header.nm} navigation cues"
        updateButtons()
    }
    private fun note(line: String) {
        if (logLines.size == 40) logLines.removeFirst()
        logLines.addLast(line.take(240))
        diagnostics.text = logLines.joinToString("\n")
        Log.i("routecast", line.take(240))
    }
    override fun onDestroy() {
        generation++; imports.close(); transfer?.cancel(); link?.stop()
        saves.shutdown() // Allow an already confirmed route's single atomic write to finish.
        super.onDestroy()
    }
}
