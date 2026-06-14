package com.routecast

import com.routecast.geo.Decimator
import com.routecast.geo.ManeuverDetector
import com.routecast.model.Pt
import com.routecast.parse.GeoJsonParser
import com.routecast.parse.GpxParser
import com.routecast.proto.Encoder
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Полный Android-пайплайн (SPEC §4): парс -> децимация -> манёвры -> кодирование.
 * Использует уже протестированные модули Gate 1.
 */
object RouteProcessor {

    private const val EARTH_R = 6_371_000.0

    data class Result(
        val name: String,
        val rawPoints: Int,
        val decimatedPoints: Int,
        val maneuvers: Int,
        val chunks: Int,
        val totalMeters: Int,
        val encoded: Encoder.Encoded
    )

    /** content — текст файла (GPX или GeoJSON, авто-детект по первому символу). */
    fun process(name: String, content: String): Result {
        val pts = parse(content)
        val dec = Decimator.decimateToMax(pts, Config.MAX_LINE_POINTS)
        val mans = ManeuverDetector.detect(pts, dec)
        val enc = Encoder.encode(dec, mans, name)
        return Result(
            name = name,
            rawPoints = pts.size,
            decimatedPoints = dec.size,
            maneuvers = mans.size,
            chunks = enc.chunks.size,
            totalMeters = totalMeters(pts),
            encoded = enc
        )
    }

    private fun parse(content: String): List<Pt> {
        val t = content.trimStart()
        return if (t.startsWith("<")) GpxParser.parse(content) else GeoJsonParser.parse(content)
    }

    private fun totalMeters(pts: List<Pt>): Int {
        var d = 0.0
        for (i in 1 until pts.size) d += haversine(pts[i - 1], pts[i])
        return d.toInt()
    }

    private fun haversine(a: Pt, b: Pt): Double {
        val dLat = Math.toRadians(b.lat - a.lat)
        val dLon = Math.toRadians(b.lon - a.lon)
        val la1 = Math.toRadians(a.lat)
        val la2 = Math.toRadians(b.lat)
        val h = sin(dLat / 2) * sin(dLat / 2) + cos(la1) * cos(la2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * EARTH_R * atan2(sqrt(h), sqrt(1 - h))
    }
}
