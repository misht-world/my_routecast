package com.routecast.parse

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class ParsersTest {

    private val gpx = """
        <gpx version="1.1">
          <trk><trkseg>
            <trkpt lat="50.001" lon="30.001"><ele>120</ele></trkpt>
            <trkpt lat="50.002" lon="30.0015"/>
            <trkpt lat="50.003" lon="30.002"/>
          </trkseg></trk>
        </gpx>
    """.trimIndent()

    private val gpxRouteOnly = """
        <gpx><rte>
            <rtept lat="1.0" lon="2.0"/>
            <rtept lat="1.1" lon="2.1"/>
        </rte></gpx>
    """.trimIndent()

    private val geojson = """
        { "type":"Feature", "geometry":
          { "type":"LineString", "coordinates": [[30.001,50.001],[30.0015,50.002],[30.002,50.003]] } }
    """.trimIndent()

    @Test
    fun gpxTrackpoints() {
        val pts = GpxParser.parse(gpx)
        assertEquals(3, pts.size)
        assertEquals(50.001, pts[0].lat, 1e-9)
        assertEquals(30.001, pts[0].lon, 1e-9)
    }

    @Test
    fun gpxRouteFallback() {
        val pts = GpxParser.parse(gpxRouteOnly)
        assertEquals(2, pts.size)
        assertEquals(1.1, pts[1].lat, 1e-9)
    }

    @Test
    fun geoJsonLineStringLonLatOrder() {
        val pts = GeoJsonParser.parse(geojson)
        assertEquals(3, pts.size)
        // GeoJSON хранит [lon,lat] — проверяем, что разложили правильно
        assertEquals(50.001, pts[0].lat, 1e-9)
        assertEquals(30.001, pts[0].lon, 1e-9)
    }

    @Test
    fun emptyAndBrokenInputsThrowFriendly() {
        assertThrows(RouteParseException::class.java) { GpxParser.parse("") }
        assertThrows(RouteParseException::class.java) { GpxParser.parse("<gpx></gpx>") }
        assertThrows(RouteParseException::class.java) { GpxParser.parse("<<not xml") }
        assertThrows(RouteParseException::class.java) { GeoJsonParser.parse("") }
        assertThrows(RouteParseException::class.java) { GeoJsonParser.parse("{not json") }
        assertThrows(RouteParseException::class.java) { GeoJsonParser.parse("""{"type":"Point","coordinates":[1,2]}""") }
    }

    @Test
    fun gpxIgnoresElevationButKeepsAll() {
        val pts = GpxParser.parse(gpx)
        assertTrue(pts.all { it.lat in 49.0..51.0 && it.lon in 29.0..31.0 })
    }
}
