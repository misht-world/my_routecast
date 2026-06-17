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

    // Передача (stop-and-wait, docs/protocol.md)
    const val ACK_TIMEOUT_MS = 4000L // TODO: verify on device
    const val MAX_RETRY = 3

    // Детект манёвров (SPEC §4.3). Кластеризация: суммируем знаковый угол поворотных
    // вершин подряд; событие закрывается прямым участком >= MERGE_DIST; манёвр выдаём,
    // только если |нетто-угол| >= TURN_MIN. Так виляния на переходах (лево+право≈0) гаснут.
    const val MIN_VERTEX_DEG = 10.0 // порог включения вершины в поворотное событие
    const val TURN_MIN_DEG = 28.0   // порог нетто-угла для выдачи манёвра
    const val MERGE_DIST_M = 18.0   // прямой участок, закрывающий событие

    // Следование (используется и на часах; здесь — для справки/тестов).
    // Активный порог навигации — на часах: NavView.OFFROUTE_M.
    const val OFFROUTE_M = 15.0

    // UUID watch-аппа — единый источник истины: watch/manifest.xml (там без дефисов).
    const val WATCH_APP_UUID = "ff29cc6f-bfa1-4e06-8ac3-04f39e8aa45b"
    // Тот же UUID без дефисов — для IQApp/getApplicationInfo (как в manifest.xml).
    const val WATCH_APP_ID_HEX = "ff29cc6fbfa14e068ac304f39e8aa45b"
}
