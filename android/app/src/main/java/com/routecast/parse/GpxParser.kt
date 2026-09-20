package com.routecast.parse

import com.routecast.model.Pt
import org.w3c.dom.Element
import java.io.ByteArrayInputStream
import javax.xml.parsers.DocumentBuilderFactory

/**
 * Разбор GPX (SPEC §4.2): берём `<trkpt lat lon>`; если трека нет — fallback на `<rtept>`.
 * Высоту/время игнорируем.
 */
object GpxParser {

    fun parse(xml: String): List<Pt> {
        if (xml.isBlank()) throw RouteParseException("пустой GPX")
        // GPX needs no DTD. Reject before parsing, including on Android parsers
        // that do not support the optional XML security features below.
        if (xml.contains("<!DOCTYPE", ignoreCase = true) || xml.contains("<!ENTITY", ignoreCase = true)) {
            throw RouteParseException("DTD и XML entities в GPX не поддерживаются")
        }
        val doc = try {
            val f = DocumentBuilderFactory.newInstance().apply {
                isNamespaceAware = false
                // не все парсеры (в т.ч. на Android) знают этот feature — не падаем
                try {
                    setFeature("http://apache.org/xml/features/nonvalidating/load-external-dtd", false)
                } catch (ignored: Exception) {
                }
            }
            f.newDocumentBuilder().parse(ByteArrayInputStream(xml.toByteArray(Charsets.UTF_8)))
        } catch (e: Exception) {
            throw RouteParseException("битый GPX: ${e.message}")
        }

        val trkpts = doc.getElementsByTagName("trkpt")
        val pts = collect(trkpts)
        if (pts.isNotEmpty()) return pts

        val rtepts = doc.getElementsByTagName("rtept")
        val rt = collect(rtepts)
        if (rt.isNotEmpty()) return rt

        throw RouteParseException("в GPX нет точек (trkpt/rtept)")
    }

    private fun collect(nodes: org.w3c.dom.NodeList): List<Pt> {
        val out = ArrayList<Pt>(nodes.length)
        for (i in 0 until nodes.length) {
            val el = nodes.item(i) as? Element ?: continue
            val lat = el.getAttribute("lat").toDoubleOrNull()
            val lon = el.getAttribute("lon").toDoubleOrNull()
            if (lat == null || lon == null || !lat.isFinite() || !lon.isFinite() ||
                lat !in -90.0..90.0 || lon !in -180.0..180.0) {
                throw RouteParseException("некорректные координаты GPX")
            }
            out.add(Pt(lat, lon))
        }
        return out
    }
}
