package com.routecast.geo

import com.routecast.model.Pt
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ManeuverDetectorTest {

    @Test
    fun straightRouteHasOnlyFinish() {
        val pts = (0..50).map { Pt(50.0, 30.0 + it * 1e-4) }
        val man = ManeuverDetector.detect(pts, pts)
        assertEquals(1, man.size)
        assertEquals(9, man[0].type)
    }

    @Test
    fun rightAngleIsDetectedAsLeftTurn() {
        // едем на восток, затем поворачиваем на север → поворот налево ~90°
        val east = (0..10).map { Pt(50.0, 30.0 + it * 1e-3) }
        val north = (1..10).map { Pt(50.0 + it * 1e-3, 30.0 + 10e-3) }
        val pts = east + north
        val man = ManeuverDetector.detect(pts, pts)

        assertEquals(2, man.size) // поворот + финиш
        val turn = man[0]
        assertEquals("ожидали обычный левый поворот (type -2)", -2, turn.type)
        assertTrue("угол должен быть ~ -90°, получили ${turn.bendDeg}", turn.bendDeg in -100.0..-80.0)
        assertEquals(9, man.last().type)
    }

    @Test
    fun distancesAreMonotonicAndIdxValid() {
        val east = (0..10).map { Pt(50.0, 30.0 + it * 1e-3) }
        val north = (1..10).map { Pt(50.0 + it * 1e-3, 30.0 + 10e-3) }
        val pts = east + north
        val decimated = Decimator.decimateToMax(pts, 50)
        val man = ManeuverDetector.detect(pts, decimated)

        var prev = -1
        for (m in man) {
            assertTrue("dist не убывает", m.distM >= prev)
            prev = m.distM
            assertTrue("idx в пределах децимированной линии", m.idx in decimated.indices)
        }
    }

    @Test
    fun hairpinIsSharp() {
        // разворот ~180°
        val out = (0..10).map { Pt(50.0, 30.0 + it * 1e-3) }
        val back = (1..10).map { Pt(50.0 + 1e-5, 30.0 + 10e-3 - it * 1e-3) }
        val pts = out + back
        val man = ManeuverDetector.detect(pts, pts)
        assertTrue("ожидали резкий поворот", man.any { kotlin.math.abs(it.type) == 3 })
    }
}
