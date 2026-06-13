package com.routecast.proto

import com.routecast.geo.Maneuver
import com.routecast.model.Pt
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class EncoderTest {

    @Test
    fun microRoundTrip() {
        val deg = 50.123456
        val micro = Encoder.toMicro(deg)
        assertEquals(50123456, micro)
        assertEquals(deg, Encoder.fromMicro(micro), 1e-6)
    }

    @Test
    fun lineDeltaRoundTrip() {
        val pts = (0 until 95).map { Pt(50.0 + it * 1e-4, 30.0 - it * 2e-4) }
        val chunks = Encoder.encodeLine(pts, pointsPerChunk = 40)

        // 95 точек / 40 = 3 чанка
        assertEquals(3, chunks.size)
        assertEquals(listOf(0, 1, 2), chunks.map { it.s })

        val decoded = Encoder.decodeLine(chunks)
        assertEquals(pts.size, decoded.size)
        for (i in pts.indices) {
            assertEquals(Encoder.toMicro(pts[i].lat), decoded[i][0])
            assertEquals(Encoder.toMicro(pts[i].lon), decoded[i][1])
        }
    }

    @Test
    fun deltasAreSmallComparedToAbsolute() {
        val pts = (0 until 50).map { Pt(50.0 + it * 1e-4, 30.0 + it * 1e-4) }
        val chunks = Encoder.encodeLine(pts, pointsPerChunk = 40)
        // первый элемент чанка 0 — абсолютный (большой), остальные дельты — маленькие
        val first = chunks[0].p[0]
        val second = chunks[0].p[1]
        assertTrue(kotlin.math.abs(first[0]) > 1_000_000)
        assertTrue("дельта должна быть маленькой", kotlin.math.abs(second[0]) < 1000)
    }

    @Test
    fun headerCountsMatch() {
        val pts = (0 until 90).map { Pt(50.0 + it * 1e-4, 30.0) }
        val maneuvers = listOf(
            Maneuver(idx = 10, type = -2, distM = 100, bendDeg = -90.0),
            Maneuver(idx = 89, type = 9, distM = 1000, bendDeg = 0.0)
        )
        val enc = Encoder.encode(pts, maneuvers, name = "test", pointsPerChunk = 40)
        assertEquals(90, enc.header.np)
        assertEquals(3, enc.header.nc)
        assertEquals(2, enc.header.nm)
        assertEquals(1, enc.header.v)
        assertEquals(enc.header.nc, enc.chunks.size)
        // манёвр в виде [idx,type,dist]
        assertEquals(intArrayOf(10, -2, 100).toList(), enc.maneuvers.m[0].toList())
    }
}
