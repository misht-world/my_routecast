package com.routecast

import android.os.Handler
import android.os.Looper
import com.routecast.proto.Packet
import com.routecast.proto.Sender
import com.routecast.proto.Transport

/**
 * Связывает stop-and-wait Sender с живым CIQ-транспортом и таймаутами (Handler).
 * Ack/Nack приходят из CiqLink -> Sender; таймаут вооружается на каждый отправленный пакет.
 */
class Transfer(
    private val link: CiqLink,
    private val packets: List<Packet>,
    private val onProgress: (sent: Int, total: Int) -> Unit,
    private val onDone: () -> Unit,
    private val onError: (String) -> Unit
) {
    private val handler = Handler(Looper.getMainLooper())
    private var sender: Sender? = null
    private val timeout = Runnable { sender?.onTimeout() }

    fun start() {
        val transport = object : Transport {
            override fun send(payload: Map<String, Any?>) {
                link.sendMessage(payload) { /* статус отправки; ack ждём отдельно */ }
            }
        }
        val s = Sender(
            packets = packets,
            transport = transport,
            onArm = {
                handler.removeCallbacks(timeout)
                handler.postDelayed(timeout, Config.ACK_TIMEOUT_MS)
            },
            onProgress = onProgress,
            onDone = { handler.removeCallbacks(timeout); onDone() },
            onError = { handler.removeCallbacks(timeout); onError(it) }
        )
        sender = s
        link.onAck = { seq -> handler.post { s.onAck(seq) } }
        link.onNack = { seq -> handler.post { s.onNack(seq) } }
        s.start()
    }

    fun cancel() {
        handler.removeCallbacks(timeout)
    }
}
