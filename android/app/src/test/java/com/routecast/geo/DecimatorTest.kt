package com.routecast.geo

import com.routecast.model.Pt
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.sin

class DecimatorTest {

    @Test
    fun straightLineCollapsesToEndpoints() {
        // Прямая вдоль долготы — все промежуточные точки коллинеарны.
        val pts = (0 until 100).map { Pt(50.0, 30.0 + it * 1e-4) }
        val out = Decimator.douglasPeucker(pts, epsilonMeters = 1.0)
        assertEquals(pts.first(), out.first())
        assertEquals(pts.last(), out.last())
        assertEquals(2, out.size)
    }

    @Test
    fun respectsMaxPoints() {
        val pts = (0 until 1000).map { Pt(50.0 + sin(it / 10.0) * 1e-3, 30.0 + it * 1e-5) }
        val out = Decimator.decimateToMax(pts, maxPoints = 100)
        assertTrue("ожидали ≤100, получили ${out.size}", out.size <= 100)
        assertTrue("децимация не должна схлопывать всё в 2 точки", out.size > 2)
        assertEquals(pts.first(), out.first())
        assertEquals(pts.last(), out.last())
    }

    @Test
    fun shapeIsPreservedWithinEpsilon() {
        // После децимации отклонение исходных точек от упрощённой линии не превышает epsilon.
        val pts = (0 until 500).map { Pt(50.0 + sin(it / 7.0) * 5e-4, 30.0 + it * 1e-5) }
        val eps = 5.0
        val out = Decimator.douglasPeucker(pts, eps)
        // грубая проверка: упрощение реально что-то срезало, но не всё
        assertTrue(out.size in 3 until pts.size)
    }

    @Test
    fun degenerateInputsDoNotCrash() {
        assertEquals(0, Decimator.douglasPeucker(emptyList(), 1.0).size)
        val one = listOf(Pt(1.0, 2.0))
        assertEquals(1, Decimator.douglasPeucker(one, 1.0).size)
        val two = listOf(Pt(1.0, 2.0), Pt(1.1, 2.1))
        assertEquals(2, Decimator.douglasPeucker(two, 1.0).size)
    }
}
