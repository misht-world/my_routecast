// Демо-настройки. На ЖЕЛЕЗЕ — false (маршрут с телефона, движение из реального GPS часов).
// Для проверки в симуляторе без телефона — поставить оба в true и пересобрать.
module Cfg {
    const DEMO_AUTOLOAD = false; // авто-загрузка мок-маршрута при старте (без телефона)
    const DEMO_MOVE = false;     // авто-движение по маршруту (нет GPS-плеера в симуляторе)
    const VERSION = "v0.5.1";
    const PROTOCOL_VERSION = 2;
    const MAX_MANEUVERS = 250;
    const MANEUVERS_PER_CHUNK = 20;
    const MAX_ROUTE_NAME = 60;
    const TRANSFER_IDLE_MS = 30000;
    const GPS_MAX_AGE_SEC = 10;
    const GPS_MIN_QUALITY = 3;
    const ARRIVE_M = 8.0;
    const MAX_LINE_POINTS = 250;
    const POINTS_PER_CHUNK = 40;
    // Сессия ActivityRecording: раньше добавлялась ради GPS, но реально GPS починил ОДИН
    // вызов enableLocationEvents. Сессия даёт системный писк/подсветку/алерты и ест память.
    // false — проверяем, что GPS живёт без неё. Если GPS пропадёт — вернуть true.
    const USE_SESSION = false;
}
