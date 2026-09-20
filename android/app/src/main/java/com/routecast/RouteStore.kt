package com.routecast

import com.google.gson.Gson
import com.google.gson.JsonParser
import com.routecast.geo.Maneuver
import com.routecast.model.Pt
import com.routecast.proto.Encoder
import java.io.File
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/** One compact, atomically replaced snapshot, written only after the watch's final ACK. */
class RouteStore(private val directory: File) {
    data class Saved(val encoded: Encoder.Encoded, val meters: Int)
    private val file get() = File(directory, "last-route.json")

    @Synchronized fun save(route: Saved) {
        directory.mkdirs()
        val text = encode(route)
        decode(text) // Validate before replacing any previous snapshot.
        val temp = File.createTempFile("route-", ".tmp", directory)
        try {
            FileOutputStream(temp).use { stream ->
                stream.write(text.toByteArray(Charsets.UTF_8)); stream.fd.sync()
            }
            Files.move(temp.toPath(), file.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
        } finally { temp.delete() }
    }

    @Synchronized fun load(): Saved? {
        if (!file.exists()) return null
        require(file.length() <= 64_000) { "Saved route is invalid." }
        return decode(file.readText(Charsets.UTF_8))
    }

    companion object {
        fun encode(route: Saved): String = Gson().toJson(mapOf(
            "format" to 1, "name" to route.encoded.header.name, "meters" to route.meters,
            "points" to Encoder.decodeLine(route.encoded.chunks), "maneuvers" to route.encoded.maneuvers.m))

        fun decode(text: String): Saved {
            require(text.length <= 64_000)
            val root = JsonParser.parseString(text).asJsonObject
            require(root["format"].asInt == 1)
            val name = root["name"].asString
            require(name.length <= Config.MAX_ROUTE_NAME)
            val points = root.getAsJsonArray("points")
            require(points.size() in 2..Config.MAX_LINE_POINTS)
            fun integer(value: com.google.gson.JsonElement): Int {
                val n = value.asDouble
                require(n.isFinite() && n == n.toInt().toDouble())
                return n.toInt()
            }
            val pts = points.map {
                val pair = it.asJsonArray
                require(pair.size() == 2)
                val lat = integer(pair[0]); val lon = integer(pair[1])
                require(lat in -90_000_000..90_000_000 && lon in -180_000_000..180_000_000)
                Pt(lat / 1_000_000.0, lon / 1_000_000.0)
            }
            require(pts.any { it != pts.first() })
            val rows = root.getAsJsonArray("maneuvers")
            require(rows.size() <= Config.MAX_MANEUVERS)
            val mans = rows.map {
                val row = it.asJsonArray
                require(row.size() == 3)
                val idx = integer(row[0]); val type = integer(row[1]); val meters = integer(row[2])
                require(idx in pts.indices && (type in -3..3 || type == 9) && meters >= 0)
                Maneuver(idx, type, meters, 0.0)
            }
            val meters = integer(root["meters"])
            require(meters >= 0)
            return Saved(Encoder.encode(pts, mans, name), meters)
        }
    }
}
