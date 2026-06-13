package com.routecast.model

/** Точка маршрута в градусах. Высоту/время сознательно игнорируем (см. SPEC §4.2). */
data class Pt(val lat: Double, val lon: Double)
