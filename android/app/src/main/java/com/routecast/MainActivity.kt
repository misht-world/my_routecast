package com.routecast

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Log
import android.view.Gravity
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/**
 * Share-target: ловит расшаренный/открытый GPX/GeoJSON, прогоняет через RouteProcessor,
 * показывает сводку маршрута. Кнопка Load sample парсит встроенный образец (без шаринга).
 * Передача на часы — следующий инкремент Gate 3.
 */
class MainActivity : Activity() {

    private lateinit var out: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(32, 32, 32, 32)
        }
        val sampleBtn = Button(this).apply {
            text = "Load sample"
            setOnClickListener { loadSample() }
        }
        out = TextView(this).apply {
            textSize = 14f
            setLineSpacing(0f, 1.2f)
        }
        val scroll = ScrollView(this).apply { addView(out) }

        root.addView(sampleBtn)
        root.addView(scroll, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.MATCH_PARENT
        ))
        root.gravity = Gravity.TOP
        setContentView(root)

        // если открыли без файла — показать встроенный образец (удобно для теста)
        if (!handleIntent(intent)) loadSample()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    /** @return true если из интента пришёл файл и он обработан. */
    private fun handleIntent(intent: Intent?): Boolean {
        if (intent == null) return false
        val uri: Uri? = when (intent.action) {
            Intent.ACTION_SEND -> intent.getParcelableExtra(Intent.EXTRA_STREAM)
            Intent.ACTION_VIEW -> intent.data
            else -> null
        }
        if (uri != null) { process(uri); return true }
        return false
    }

    private fun process(uri: Uri) {
        try {
            val content = contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
                ?: throw IllegalStateException("не удалось прочитать файл")
            val name = uri.lastPathSegment ?: "route"
            show(RouteProcessor.process(name, content))
        } catch (e: Exception) {
            out.text = "Ошибка: ${e.message}"
            Log.e("routecast", "parse failed", e)
        }
    }

    private fun loadSample() {
        try {
            val content = assets.open("short_city.gpx").bufferedReader().use { it.readText() }
            show(RouteProcessor.process("short_city.gpx", content))
        } catch (e: Exception) {
            out.text = "Ошибка: ${e.message}"
            Log.e("routecast", "parse failed", e)
        }
    }

    private fun show(r: RouteProcessor.Result) {
        val sb = StringBuilder()
        sb.appendLine("Маршрут: ${r.encoded.header.name}")
        sb.appendLine("Исходных точек: ${r.rawPoints}")
        sb.appendLine("После децимации: ${r.decimatedPoints} (лимит ${Config.MAX_LINE_POINTS})")
        sb.appendLine("Манёвров: ${r.maneuvers}")
        sb.appendLine("Дистанция: ${r.totalMeters} м")
        sb.appendLine("Чанков (по ${Config.POINTS_PER_CHUNK}): ${r.chunks}")
        sb.appendLine()
        sb.appendLine("Протокол готов к отправке:")
        sb.appendLine("  H v${r.encoded.header.v} np=${r.encoded.header.np} nc=${r.encoded.header.nc} nm=${r.encoded.header.nm}")
        for (c in r.encoded.chunks) sb.appendLine("  L s=${c.s} pts=${c.p.size}")
        sb.appendLine("  M (${r.encoded.maneuvers.m.size}) -> E")
        out.text = sb.toString()
        Log.i("routecast", "\n" + sb.toString())
    }
}
