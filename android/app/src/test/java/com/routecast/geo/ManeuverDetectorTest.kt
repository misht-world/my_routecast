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
    fun separatedTurnsAreNotMerged() {
        // 4 «ноги» с поворотами ~90° на расстоянии >> MERGE_DIST друг от друга
        // (как разреженный трек из Organic Maps). Ожидаем 3 поворота + финиш, а не слияние в 0.
        val pts = ArrayList<Pt>()
        var lat = 50.0; var lon = 30.0
        pts.add(Pt(lat, lon))
        repeat(4) { lon += 1e-4; pts.add(Pt(lat, lon)) } // на восток ~29 м
        repeat(4) { lat += 1e-4; pts.add(Pt(lat, lon)) } // поворот -> на север ~44 м
        repeat(4) { lon += 1e-4; pts.add(Pt(lat, lon)) } // поворот -> на восток
        repeat(4) { lat += 1e-4; pts.add(Pt(lat, lon)) } // поворот -> на север
        val man = ManeuverDetector.detect(pts, pts)
        assertEquals("ожидали 3 поворота (не слиплись)", 3, man.count { it.type != 9 })
        assertEquals(9, man.last().type)
    }

    @Test
    fun zigzagCrossingIsCancelled() {
        // прямо на восток, короткий зигзаг (переход через дорогу: влево+вправо), снова прямо
        val pts = ArrayList<Pt>()
        var lon = 30.0
        for (i in 0..9) { pts.add(Pt(50.0, lon)); lon += 1e-4 }   // ~7 м шаг
        pts.add(Pt(50.00006, lon)); lon += 1e-4                    // вильнул вверх
        pts.add(Pt(50.0, lon)); lon += 1e-4                        // вернулся
        for (i in 0..9) { pts.add(Pt(50.0, lon)); lon += 1e-4 }
        val man = ManeuverDetector.detect(pts, pts)
        // нетто-угол виляния ≈ 0 -> манёвр НЕ выдаётся, остаётся только финиш
        assertEquals(0, man.count { it.type != 9 })
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
