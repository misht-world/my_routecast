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
                override fun onApplicationInfoReceived(app: IQApp) {
                    log("watch app INSTALLED on ${d.friendlyName}")
                }
                override fun onApplicationNotInstalled(applicationId: String) {
                    log("watch app NOT installed on ${d.friendlyName}")
                }
            })
        } catch (e: Exception) {
            log("appInfo err: ${e.message}")
        }
    }

    private fun safeList(block: () -> List<IQDevice>?): List<IQDevice> =
        try { block() ?: emptyList() } catch (e: Exception) { log("list err: ${e.message}"); emptyList() }

    fun stop() {
        handler.removeCallbacksAndMessages(null)
        try { ciq?.shutdown(ctx) } catch (_: Exception) {}
    }
}
