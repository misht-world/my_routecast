package com.routecast.proto

import com.routecast.geo.Maneuver
import com.routecast.model.Pt
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SenderTest {

    @Test
    fun staleRepliesCannotAdvanceOrFailNewTransfer() {
        val t = FakeTransport()
        var error: String? = null
        val s = Sender(samplePackets(), t, onError = { error = it })
        s.start()
        s.onAck(-1, "ffffffffffffffffffffffffffffffff")
        s.onNack(-1, "ffffffffffffffffffffffffffffffff", "restart")
        s.onAck(-1) // Legacy replies without identity are ignored.
        assertEquals(-1, s.currentAckSeq)
        assertNull(error)
        s.onAck(-1, s.transferId)
        assertEquals(0, s.currentAckSeq)
    }

    @Test
    fun fatalWatchFailureStopsWithoutRetryLoop() {
        val t = FakeTransport()
        var error: String? = null
        val s = Sender(samplePackets(), t, onError = { error = it })
        s.start()
        s.onNack(-1, s.transferId, "storage")
        s.onTimeout()
        assertTrue(s.isFinished)
        assertNotNull(error)
        assertEquals(1, t.sent.size)
    }

    @Test
    fun maneuverChunksHaveUniqueSequencesAndTransferIdentity() {
        val pts = (0 until 90).map { Pt(50.0 + it * 1e-4, 30.0) }
        val mans = (0 until 45).map { Maneuver(it, 2, it * 10, 90.0) }
        val packets = MessageBuilder.build(Encoder.encode(pts, mans, "chunks"))
        val id = packets.first().payload["id"]
        assertTrue(packets.all { it.payload["id"] == id })
        val m = packets.filter { it.payload["t"] == "M" }
        assertEquals(listOf(3, 4, 5), m.map { it.ackSeq })
        assertEquals(listOf(20, 20, 5), m.map { (it.payload["m"] as List<*>).size })
        assertEquals(3, packets.first().payload["mc"])
        assertTrue(MessageBuilder.build(Encoder.encode(pts, mans, "chunks")).first().payload["id"] != id)
    }

    @Test
    fun cancelledSenderIgnoresLateEvents() {
        val t = FakeTransport()
        var callbacks = 0
        val s = Sender(samplePackets(), t, onDone = { callbacks++ }, onError = { callbacks++ })
        s.start()
        s.cancel()
        s.onAck(-1, s.transferId)
        s.onNack(-1, s.transferId)
        s.onTimeout()
        assertEquals(1, t.sent.size)
        assertEquals(0, callbacks)
    }

    @Test
    fun emptyTransferCompletesWithoutSending() {
        val t = FakeTransport()
        var done = 0
        val s = Sender(emptyList(), t, onDone = { done++ })
        s.start()
        s.onAck(-1, s.transferId)
        assertEquals(1, done)
        assertTrue(t.sent.isEmpty())
    }

    @Test
    fun synchronousAckDoesNotArmTimerAfterCompletion() {
        val events = ArrayList<String>()
        lateinit var s: Sender
        val t = object : Transport {
            override fun send(payload: Map<String, Any?>) { s.onAck(s.currentAckSeq, s.transferId) }
        }
        s = Sender(samplePackets(), t, onArm = { events.add("arm") }, onDone = { events.add("done") })
        s.start()
        assertEquals("done", events.last())
        assertTrue(s.isFinished)
    }

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
            s.onAck(s.currentAckSeq, s.transferId)
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
        s.onAck(pk[0].ackSeq, s.transferId)           // -> L0
        val beforeRetry = t.sent.size
        s.onTimeout()                   // потеря ack L0 -> повтор L0
        assertEquals("L0 переслан", beforeRetry + 1, t.sent.size)
        // дальше подтверждаем всё по порядку
        var guard = 0
        while (!done && guard++ < 50) {
            s.onAck(s.currentAckSeq, s.transferId)
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
        s.onNack(-1, s.transferId)
        assertEquals("nack -> повтор текущего", before + 1, t.sent.size)
    }
}

