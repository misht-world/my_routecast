package com.routecast

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.garmin.android.connectiq.ConnectIQ
import com.garmin.android.connectiq.IQApp
import com.garmin.android.connectiq.IQDevice

/**
 * Обёртка над Connect IQ Mobile SDK (Gate 3). TETHERED — связь с симулятором через
 * adb forward tcp:7381. Устройство появляется асинхронно, поэтому опрашиваем несколько раз
 * и подписываемся на события статуса.
 */
class CiqLink(
    private val ctx: Context,
    private val appIdHex: String,
    private val log: (String) -> Unit
) {
    private var ciq: ConnectIQ? = null
    private val handler = Handler(Looper.getMainLooper())
    private var polls = 0
    private val seen = HashSet<Long>()

    private var device: IQDevice? = null
    private var app: IQApp? = null

    /** Готовность к передаче (устройство подключено, watch-апп найден). */
    var onReady: (() -> Unit)? = null
    /** Подтверждения от часов. */
    var onAck: ((Int) -> Unit)? = null
    var onNack: ((Int) -> Unit)? = null

    fun start() {
        val c = ConnectIQ.getInstance(ctx, ConnectIQ.IQConnectType.TETHERED)
        ciq = c
        log("init SDK (TETHERED)…")
        c.initialize(ctx, true, object : ConnectIQ.ConnectIQListener {
            override fun onSdkReady() {
                log("SDK ready")
                polls = 0
                poll()
            }
            override fun onInitializeError(s: ConnectIQ.IQSdkErrorStatus) {
                log("init error: ${s.name}")
            }
            override fun onSdkShutDown() {
                log("SDK shutdown")
            }
        })
    }

    private fun poll() {
        val c = ciq ?: return
        val known = safeList { c.knownDevices }
        val conn = safeList { c.connectedDevices }
        log("poll #$polls: known=${known.size} connected=${conn.size}")

        for (d in known) {
            if (seen.add(d.deviceIdentifier)) {
                try {
                    c.registerForDeviceEvents(d) { dev, status ->
                        log("status: ${dev.friendlyName} = $status")
                        if (status == IQDevice.IQDeviceStatus.CONNECTED) checkApp(dev)
                    }
                } catch (_: Exception) {}
            }
        }
        for (d in conn) checkApp(d)

        polls++
        if (conn.isEmpty() && polls < 8) {
            handler.postDelayed({ poll() }, 2000)
        }
    }

    private fun checkApp(d: IQDevice) {
        val c = ciq ?: return
        try {
            c.getApplicationInfo(appIdHex, d, object : ConnectIQ.IQApplicationInfoListener {
                override fun onApplicationInfoReceived(foundApp: IQApp) {
                    log("watch app INSTALLED on ${d.friendlyName}")
                    device = d
                    app = foundApp
                    registerAck(d, foundApp)
                    onReady?.invoke()
                }
                override fun onApplicationNotInstalled(applicationId: String) {
                    log("watch app NOT installed on ${d.friendlyName}")
                }
            })
        } catch (e: Exception) {
            log("appInfo err: ${e.message}")
        }
    }

    private fun registerAck(d: IQDevice, a: IQApp) {
        val c = ciq ?: return
        try {
            c.registerForAppEvents(d, a) { _, _, message, _ ->
                for (e in message) {
                    val map = e as? Map<*, *> ?: continue
                    val t = map["t"] as? String ?: continue
                    val s = (map["s"] as? Number)?.toInt() ?: continue
                    when (t) {
                        "A" -> onAck?.invoke(s)
                        "N" -> onNack?.invoke(s)
                    }
                }
            }
        } catch (e: Exception) {
            log("appEvents err: ${e.message}")
        }
    }

    /** Открыть watch-апп на устройстве (на симуляторе уже запущен). */
    fun openApp() {
        val c = ciq ?: return
        val d = device ?: return
        val a = app ?: return
        try {
            c.openApplication(d, a) { _, _, status -> log("openApp: ${status.name}") }
        } catch (e: Exception) {
            log("openApp err: ${e.message}")
        }
    }

    /** Отправить один пакет протокола. */
    fun sendMessage(payload: Map<String, Any?>, onStatus: (Boolean) -> Unit) {
        val c = ciq
        val d = device
        val a = app
        if (c == null || d == null || a == null) { onStatus(false); return }
        try {
            c.sendMessage(d, a, HashMap(payload)) { _, _, status ->
                onStatus(status == ConnectIQ.IQMessageStatus.SUCCESS)
            }
        } catch (e: Exception) {
            log("send err: ${e.message}")
            onStatus(false)
        }
    }

    private fun safeList(block: () -> List<IQDevice>?): List<IQDevice> =
        try { block() ?: emptyList() } catch (e: Exception) { log("list err: ${e.message}"); emptyList() }

    fun stop() {
        handler.removeCallbacksAndMessages(null)
        try { ciq?.shutdown(ctx) } catch (_: Exception) {}
    }
}
