package com.routecast.geo

import com.routecast.Config
import com.routecast.model.Pt
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Манёвр маршрута (SPEC §3, §4.3). `bendDeg` — реальный знаковый угол поворота
 * (для рисования гнутой стрелки на часах); `type` — его классификация.
 */
data class Maneuver(
    val idx: Int,       // индекс в ДЕЦИМИРОВАННОЙ линии
    val type: Int,      // 0 прямо, ±1 плавно, ±2 обычный, ±3 резкий (знак: + право, − лево), 9 финиш
    val distM: Int,     // накопленная дистанция от старта, метры
    val bendDeg: Double // знаковый угол поворота в градусах (+ право, − лево)
)

/**
 * Детект манёвров по НЕразреженной линии (чтобы не терять острые углы),
 * с привязкой idx к ближайшей точке децимированной линии.
 */
object ManeuverDetector {
    private const val EARTH_R = 6_371_000.0

    fun detect(full: List<Pt>, decimated: List<Pt>): List<Maneuver> {
        if (full.size < 2) return emptyList()

        // накопленная дистанция до каждой вершины
        val cum = DoubleArray(full.size)
        for (i in 1 until full.size) cum[i] = cum[i - 1] + haversine(full[i - 1], full[i])

        // пеленги сегментов
        val brg = DoubleArray(full.size - 1)
        for (i in 0 until full.size - 1) brg[i] = bearing(full[i], full[i + 1])

        data class Raw(val fullIdx: Int, val turn: Double)
        val raw = ArrayList<Raw>()
        for (i in 1 until full.size - 1) {
            val turn = normalize180(brg[i] - brg[i - 1])
            if (abs(turn) >= Config.TURN_MIN_DEG) raw.add(Raw(i, turn))
        }

        // схлопывание близких манёвров (< MERGE_DIST_M): оставляем самый острый
        val merged = ArrayList<Raw>()
        var i = 0
        while (i < raw.size) {
            var j = i
            var best = raw[i]
            while (j + 1 < raw.size &&
                cum[raw[j + 1].fullIdx] - cum[raw[j].fullIdx] < Config.MERGE_DIST_M
            ) {
                j++
                if (abs(raw[j].turn) > abs(best.turn)) best = raw[j]
            }
            merged.add(best)
            i = j + 1
        }

        val out = ArrayList<Maneuver>(merged.size + 1)
        for (m in merged) {
            out.add(
                Maneuver(
                    idx = nearestDecimated(full[m.fullIdx], decimated),
                    type = classify(m.turn),
                    distM = cum[m.fullIdx].roundToInt(),
                    bendDeg = m.turn
                )
            )
        }
        // финиш
        out.add(
            Maneuver(
                idx = decimated.size - 1,
                type = 9,
                distM = cum[full.size - 1].roundToInt(),
                bendDeg = 0.0
            )
        )
        return out
    }

    private fun classify(turn: Double): Int {
        val a = abs(turn)
        val sharp = when {
            a < 70 -> 1
            a < 120 -> 2
            else -> 3
        }
        return if (turn >= 0) sharp else -sharp
    }

    private fun nearestDecimated(p: Pt, decimated: List<Pt>): Int {
        var best = 0
        var bestD = Double.MAX_VALUE
        for (k in decimated.indices) {
            val d = haversine(p, decimated[k])
            if (d < bestD) { bestD = d; best = k }
        }
        return best
    }

    private fun haversine(a: Pt, b: Pt): Double {
        val dLat = Math.toRadians(b.lat - a.lat)
        val dLon = Math.toRadians(b.lon - a.lon)
        val la1 = Math.toRadians(a.lat)
        val la2 = Math.toRadians(b.lat)
        val h = sin(dLat / 2) * sin(dLat / 2) +
            cos(la1) * cos(la2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * EARTH_R * atan2(sqrt(h), sqrt(1 - h))
    }

    /** Пеленг сегмента a→b в градусах [0,360). */
    private fun bearing(a: Pt, b: Pt): Double {
        val la1 = Math.toRadians(a.lat)
        val la2 = Math.toRadians(b.lat)
        val dLon = Math.toRadians(b.lon - a.lon)
        val y = sin(dLon) * cos(la2)
        val x = cos(la1) * sin(la2) - sin(la1) * cos(la2) * cos(dLon)
        return (Math.toDegrees(atan2(y, x)) + 360) % 360
    }

    private fun normalize180(deg: Double): Double {
        var d = (deg + 180) % 360
        if (d < 0) d += 360
        return d - 180
    }
}
