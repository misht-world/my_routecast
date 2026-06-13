package com.routecast

/**
 * Единое место для магических чисел Android-стороны (см. CLAUDE.md «Конвенции»).
 * Часть значений — placeholder'ы под железо, помечены TODO: verify on device.
 */
object Config {
    const val PROTOCOL_VERSION = 1

    // Децимация / чанкинг
    const val MAX_LINE_POINTS = 250
    const val POINTS_PER_CHUNK = 40 // TODO: verify on device (реальный лимит mailbox)

    // Детект манёвров (SPEC §4.3)
    const val TURN_MIN_DEG = 35.0
    const val MERGE_DIST_M = 15.0

    // Следование (используется и на часах; здесь — для справки/тестов)
    const val OFFROUTE_M = 40.0

    // UUID watch-аппа — единый источник истины: watch/manifest.xml.
    const val WATCH_APP_UUID = "00000000-0000-0000-0000-000000000000" // TODO: sync with watch/manifest.xml
}
