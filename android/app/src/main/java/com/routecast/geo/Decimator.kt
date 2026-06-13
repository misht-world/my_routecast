package com.routecast.geo

import com.routecast.model.Pt
import kotlin.math.cos
import kotlin.math.hypot

/**
 * Прореживание линии алгоритмом Douglas–Peucker (SPEC §4.3, шаг 1).
 *
 * Дистанции считаем в локальной плоскости (equirectangular-приближение относительно
 * первой точки) — на масштабах маршрута погрешность пренебрежима, зато без тяжёлых формул.
 */
object Decimator {
    private const val EARTH_R = 6_371_000.0

    private fun toX(p: Pt, lat0: Double): Double =
        Math.toRadians(p.lon) * cos(Math.toRadians(lat0)) * EARTH_R

    private fun toY(p: Pt): Double =
        Math.toRadians(p.lat) * EARTH_R

    /** Перпендикулярная дистанция (в метрах) от точки p до отрезка a→b. */
    private fun perpDistMeters(p: Pt, a: Pt, b: Pt, lat0: Double): Double {
        val px = toX(p, lat0); val py = toY(p)
        val ax = toX(a, lat0); val ay = toY(a)
        val bx = toX(b, lat0); val by = toY(b)
        val dx = bx - ax; val dy = by - ay
        val len2 = dx * dx + dy * dy
        if (len2 == 0.0) return hypot(px - ax, py - ay)
        var t = ((px - ax) * dx + (py - ay) * dy) / len2
        t = t.coerceIn(0.0, 1.0)
        val cx = ax + t * dx; val cy = ay + t * dy
        return hypot(px - cx, py - cy)
    }

    /** Прореживание с фиксированным эпсилоном (метры). Сохраняет первую и последнюю точки. */
    fun douglasPeucker(points: List<Pt>, epsilonMeters: Double): List<Pt> {
        if (points.size < 3) return points.toList()
        val lat0 = points[0].lat
        val keep = BooleanArray(points.size)
        keep[0] = true
        keep[points.size - 1] = true

        val stack = ArrayDeque<Pair<Int, Int>>()
        stack.addLast(0 to points.size - 1)
        while (stack.isNotEmpty()) {
            val (s, e) = stack.removeLast()
            var maxD = 0.0
            var idx = -1
            for (i in s + 1 until e) {
                val d = perpDistMeters(points[i], points[s], points[e], lat0)
                if (d > maxD) { maxD = d; idx = i }
            }
            if (maxD > epsilonMeters && idx >= 0) {
                keep[idx] = true
                stack.addLast(s to idx)
                stack.addLast(idx to e)
            }
        }
        return points.filterIndexed { i, _ -> keep[i] }
    }

    /**
     * Подобрать эпсилон так, чтобы точек стало ≤ maxPoints, сохранив максимум формы
     * (бинарный поиск наименьшего эпсилона, удовлетворяющего ограничению).
     */
    fun decimateToMax(points: List<Pt>, maxPoints: Int): List<Pt> {
        require(maxPoints >= 2) { "maxPoints must be >= 2" }
        if (points.size <= maxPoints) return points.toList()

        var lo = 0.0
        var hi = 1.0
        var result = douglasPeucker(points, hi)
        while (result.size > maxPoints) {
            hi *= 2
            result = douglasPeucker(points, hi)
            if (hi > 1e7) break
        }
        repeat(40) {
            val mid = (lo + hi) / 2
            val r = douglasPeucker(points, mid)
            if (r.size > maxPoints) lo = mid else { hi = mid; result = r }
        }
        return result
    }
}
