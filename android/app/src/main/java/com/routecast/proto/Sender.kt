package com.routecast.proto

import com.routecast.Config

/**
 * Stop-and-wait отправитель (docs/protocol.md): шлёт пакет, ждёт ack нужного seq,
 * только тогда шлёт следующий. Таймаут/ретраи — снаружи (onArm вооружает таймер,
 * который при срабатывании зовёт onTimeout). Чистая логика — тестируется на JVM.
 */
class Sender(
    private val packets: List<Packet>,
    private val transport: Transport,
    private val maxRetry: Int = Config.MAX_RETRY,
    private val onArm: () -> Unit = {},
    private val onProgress: (sent: Int, total: Int) -> Unit = { _, _ -> },
    private val onDone: () -> Unit = {},
    private val onError: (String) -> Unit = {}
) {
    private var idx = 0
    private var retries = 0
    private var finished = true
    val transferId: String? = packets.firstOrNull()?.payload?.get("id") as? String

    fun start() {
        if (!finished) return
        idx = 0
        retries = 0
        finished = false
        if (packets.isEmpty()) {
            finished = true
            onDone()
            return
        }
        sendCurrent()
    }

    private fun sendCurrent() {
        onArm()
        transport.send(packets[idx].payload)
    }

    /** Подтверждение принятого пакета. */
    fun onAck(seq: Int, id: String? = null) {
        if (id == null || id != transferId) return
        if (finished) return
        if (seq != packets[idx].ackSeq) return // дубль/чужой ack — игнор
        idx++
        retries = 0
        onProgress(idx, packets.size)
        if (finished) return
        if (idx >= packets.size) {
            finished = true
            onDone()
        } else {
            sendCurrent()
        }
    }

    /** Часы просят повтор (nack) — пересылаем текущий пакет. */
    fun onNack(seq: Int, id: String? = null, reason: String = "invalid") {
        if (finished || id == null || id != transferId) return
        if (reason in setOf("restart", "version", "storage", "busy")) {
            finished = true
            onError(when (reason) {
                "version" -> "Update RouteCast on both your phone and watch."
                "storage" -> "The watch could not save the route. Free space and retry."
                "busy" -> "Finish navigation on the watch before sending a new route."
                else -> "Transfer interrupted. Open RouteCast on the watch and retry."
            })
            return
        }
        if (seq != packets[idx].ackSeq) return
        retry("nack")
    }

    /** Таймаут ожидания ack. */
    fun onTimeout() {
        if (finished) return
        retry("timeout")
    }

    private fun retry(cause: String) {
        retries++
        if (retries > maxRetry) {
            finished = true
            onError("No confirmation. Open RouteCast on the watch, check that both apps are up to date, and retry.")
        } else {
            sendCurrent()
        }
    }

    val isFinished: Boolean get() = finished

    fun cancel() { finished = true }

    /** Ожидаемый сейчас seq подтверждения (для UI/тестов). */
    val currentAckSeq: Int get() = if (idx < packets.size) packets[idx].ackSeq else Int.MIN_VALUE
}
