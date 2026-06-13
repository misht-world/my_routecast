package com.routecast.proto

import com.routecast.Config
import com.routecast.geo.Maneuver
import com.routecast.model.Pt
import kotlin.math.roundToInt

/**
 * Кодирование маршрута в сообщения протокола (docs/protocol.md):
 * координаты — целые микроградусы, в чанках линии — дельты от предыдущей точки
 * (первая точка чанка 0 — абсолютная).
 *
 * Сообщения здесь — типизированные модели; превращение в Monkey C `Dictionary`
 * происходит на слое передачи (Срез 3).
 */
object Encoder {

    data class Header(val v: Int, val np: Int, val nc: Int, val nm: Int, val name: String)
    data class LineChunk(val s: Int, val p: List<IntArray>) // каждый элемент: [dlat, dlon] в микроградусах
    // Манёвр пока кодируем как [idx, type, dist] по текущему protocol.md.
    // TODO(protocol): добавить угол bendDeg для точной отрисовки стрелки — синхронно обе стороны.
    data class ManeuversMsg(val m: List<IntArray>)

    data class Encoded(val header: Header, val chunks: List<LineChunk>, val maneuvers: ManeuversMsg)

    fun toMicro(deg: Double): Int = (deg * 1_000_000).roundToInt()
    fun fromMicro(micro: Int): Double = micro / 1_000_000.0

    fun encode(
        decimated: List<Pt>,
        maneuvers: List<Maneuver>,
        name: String,
        pointsPerChunk: Int = Config.POINTS_PER_CHUNK
    ): Encoded {
        require(pointsPerChunk >= 1)
        val chunks = encodeLine(decimated, pointsPerChunk)
        val man = ManeuversMsg(maneuvers.map { intArrayOf(it.idx, it.type, it.distM) })
        val header = Header(
            v = Config.PROTOCOL_VERSION,
            np = decimated.size,
            nc = chunks.size,
            nm = maneuvers.size,
            name = name
        )
        return Encoded(header, chunks, man)
    }

    /** Линия → чанки дельт. Элемент 0 всего потока — абсолютные микроградусы, остальные — дельты. */
    fun encodeLine(points: List<Pt>, pointsPerChunk: Int): List<LineChunk> {
        if (points.isEmpty()) return emptyList()
        val stream = ArrayList<IntArray>(points.size)
        var prevLat = 0
        var prevLon = 0
        for ((i, p) in points.withIndex()) {
            val mlat = toMicro(p.lat)
            val mlon = toMicro(p.lon)
            if (i == 0) stream.add(intArrayOf(mlat, mlon))
            else stream.add(intArrayOf(mlat - prevLat, mlon - prevLon))
            prevLat = mlat
            prevLon = mlon
        }
        val chunks = ArrayList<LineChunk>()
        var seq = 0
        var idx = 0
        while (idx < stream.size) {
            val end = minOf(idx + pointsPerChunk, stream.size)
            chunks.add(LineChunk(seq, stream.subList(idx, end).toList()))
            idx = end
            seq++
        }
        return chunks
    }

    /** Обратная сборка линии из чанков (для тестов и валидации на часах). */
    fun decodeLine(chunks: List<LineChunk>): List<IntArray> {
        val out = ArrayList<IntArray>()
        var lat = 0
        var lon = 0
        var first = true
        for (chunk in chunks.sortedBy { it.s }) {
            for (delta in chunk.p) {
                if (first) { lat = delta[0]; lon = delta[1]; first = false }
                else { lat += delta[0]; lon += delta[1] }
                out.add(intArrayOf(lat, lon))
            }
        }
        return out
    }
}
