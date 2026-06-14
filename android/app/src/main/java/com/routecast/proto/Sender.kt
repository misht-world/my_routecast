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
    private var finished = false

    fun start() {
        idx = 0
        retries = 0
        finished = false
        sendCurrent()
    }

    private fun sendCurrent() {
        transport.send(packets[idx].payload)
        onArm()
    }

    /** Подтверждение принятого пакета. */
    fun onAck(seq: Int) {
        if (finished) return
        if (seq != packets[idx].ackSeq) return // дубль/чужой ack — игнор
        idx++
        retries = 0
        onProgress(idx, packets.size)
        if (idx >= packets.size) {
            finished = true
            onDone()
        } else {
            sendCurrent()
        }
    }

    /** Часы просят повтор (nack) — пересылаем текущий пакет. */
    fun onNack(@Suppress("UNUSED_PARAMETER") seq: Int) {
        if (finished) return
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
            onError("$cause: пакет $idx, ретраи исчерпаны")
        } else {
            sendCurrent()
        }
    }

    val isFinished: Boolean get() = finished

    /** Ожидаемый сейчас seq подтверждения (для UI/тестов). */
    val currentAckSeq: Int get() = if (idx < packets.size) packets[idx].ackSeq else Int.MIN_VALUE
}
