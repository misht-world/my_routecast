package com.routecast.proto

/** Транспорт сообщения на часы (реальный — через Connect IQ; в тестах — фейковый). */
interface Transport {
    fun send(payload: Map<String, Any?>)
}

/** Пакет протокола + ожидаемый seq подтверждения (H=-1, L=s, M=-2, E=-3). */
data class Packet(val ackSeq: Int, val payload: Map<String, Any?>)
