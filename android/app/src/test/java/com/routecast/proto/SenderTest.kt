package com.routecast.proto

import com.routecast.geo.Maneuver
import com.routecast.model.Pt
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SenderTest {

    private class FakeTransport : Transport {
        val sent = ArrayList<Map<String, Any?>>()
        override fun send(payload: Map<String, Any?>) { sent.add(payload) }
    }

    private fun samplePackets(): List<Packet> {
        // 90 точек -> 3 чанка по 40 -> пакеты H, L0, L1, L2, M, E (6)
        val pts = (0 until 90).map { Pt(50.0 + it * 1e-4, 30.0) }
        val mans = listOf(Maneuver(10, -2, 100, -90.0), Maneuver(89, 9, 500, 0.0))
        return MessageBuilder.build(Encoder.encode(pts, mans, "t", 40))
    }

    @Test
    fun buildsHLMEorder() {
        val pk = samplePackets()
        assertEquals(6, pk.size)
        assertEquals("H", pk.first().payload["t"])
        assertEquals(-1, pk.first().ackSeq)
        assertEquals("E", pk.last().payload["t"])
        assertEquals(-3, pk.last().ackSeq)
    }

    @Test
    fun happyPathSendsEachOnceAndCompletes() {
        val pk = samplePackets()
        val t = FakeTransport()
        var done = false
        var err: String? = null
        val s = Sender(pk, t, onDone = { done = true }, onError = { err = it })
        s.start()
        var guard = 0
        while (!done && err == null && guard++ < 50) {
            s.onAck(s.currentAckSeq)
        }
        assertTrue("ожидали done", done)
        assertNull(err)
        assertEquals("каждый пакет отправлен ровно раз", pk.size, t.sent.size)
    }

    @Test
    fun ackLossThenTimeoutRetrySucceeds() {
        val pk = samplePackets()
        val t = FakeTransport()
        var done = false
        val s = Sender(pk, t, onDone = { done = true })
        s.start()                       // H
        s.onAck(pk[0].ackSeq)           // -> L0
        val beforeRetry = t.sent.size
        s.onTimeout()                   // потеря ack L0 -> повтор L0
        assertEquals("L0 переслан", beforeRetry + 1, t.sent.size)
        // дальше подтверждаем всё по порядку
        var guard = 0
        while (!done && guard++ < 50) {
            s.onAck(s.currentAckSeq)
        }
        assertTrue(done)
    }

    @Test
    fun retryExhaustionRaisesError() {
        val pk = samplePackets()
        val t = FakeTransport()
        var err: String? = null
        val s = Sender(pk, t, maxRetry = 3, onError = { err = it })
        s.start()                       // H (отправлен)
        s.onTimeout(); s.onTimeout(); s.onTimeout() // ретраи 1..3
        assertNull("после 3 ретраев ещё держимся", err)
        s.onTimeout()                   // 4-й -> ошибка
        assertNotNull(err)
        assertTrue(s.isFinished)
    }

    @Test
    fun nackResendsCurrent() {
        val pk = samplePackets()
        val t = FakeTransport()
        val s = Sender(pk, t)
        s.start()                       // H
        val before = t.sent.size
        s.onNack(-1)
        assertEquals("nack -> повтор текущего", before + 1, t.sent.size)
    }
}
