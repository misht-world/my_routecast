package com.routecast.parse

import com.google.gson.JsonArray
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import com.routecast.model.Pt

/**
 * Разбор GeoJSON (SPEC §4.2): первый `LineString` (как самостоятельная geometry,
 * как Feature, или внутри FeatureCollection). Координаты GeoJSON — [lon, lat].
 */
object GeoJsonParser {

    fun parse(json: String): List<Pt> {
        try {
            return parseInternal(json)
        } catch (e: RouteParseException) {
            throw e
        } catch (e: Exception) {
            throw RouteParseException("битый GeoJSON: ${e.message}")
        }
    }

    private fun parseInternal(json: String): List<Pt> {
        if (json.isBlank()) throw RouteParseException("пустой GeoJSON")
        val root = try {
            JsonParser.parseString(json).asJsonObject
        } catch (e: Exception) {
            throw RouteParseException("битый GeoJSON: ${e.message}")
        }

        val line = findLineString(root)
            ?: throw RouteParseException("в GeoJSON нет LineString")
        if (line.size() < 1) throw RouteParseException("пустой LineString")

        val pts = ArrayList<Pt>(line.size())
        for (c in line) {
            val pair = c.asJsonArray
            val lon = pair[0].asDouble
            val lat = pair[1].asDouble
            if (!lat.isFinite() || !lon.isFinite() || lat !in -90.0..90.0 || lon !in -180.0..180.0) {
                throw RouteParseException("некорректные координаты GeoJSON")
            }
            pts.add(Pt(lat, lon))
        }
        return pts
    }

    /** Возвращает массив координат первого встреченного LineString. */
    private fun findLineString(obj: JsonObject): JsonArray? {
        when (obj.get("type")?.asString) {
            "LineString" -> return obj.getAsJsonArray("coordinates")
            "Feature" -> obj.getAsJsonObject("geometry")?.let { return findLineString(it) }
            "FeatureCollection" -> {
                for (f in obj.getAsJsonArray("features")) {
                    findLineString(f.asJsonObject)?.let { return it }
                }
            }
        }
        return null
    }
}
