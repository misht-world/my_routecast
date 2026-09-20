// Состояние навигации: маршрут + текущая позиция/курс + зум.
class NavState {

    // 3 уровня зума — охват впереди в метрах (SPEC §5.4): ближе/средний/дальше
    const VIEW = [320.0, 150.0, 60.0];

    var route;        // RouteModel
    var meLatMicro;
    var meLonMicro;
    var headingRad;   // Float или null (нет курса с GPS)
    var headingBias;  // поправка «компас -> истинный север», набирается по GPS-курсу в движении
    var hasFix;
    var fixTime;
    var zoom;         // 0..2, по умолчанию средний
    var arrived;      // достигнут финиш
    var vibedArrival; // вибро прибытия уже дано
    var paused;       // навигация на паузе
    var warnIdx;      // idx манёвра в активном предупреждении (-1 нет)
    var warnStart;    // System.getTimer() начала предупреждения, мс
    var nowIdx;       // idx манёвра, на котором уже дано вибро «сейчас»
    var offBuzzed;    // вибро схода с маршрута уже дано
    var offSince;     // System.getTimer() начала схода (0 — на маршруте); выдержка по времени
    var lastTraveled; // текущий прогресс по маршруту, м (для оконного поиска ближайшего)
    var signalsOn;    // вибро-оповещения вкл/выкл (тумблер в меню навигации)
    var demo;         // встроенный демо-прогон (движение по таймеру)
    var demoDist;     // пройдено в демо, метры
    var gpsAcc;       // качество GPS (Position.Quality: 0 нет .. 4 отлично)
    var gpsHasPos;    // есть ли объект позиции от приёмника
    var rec;          // идёт ли запись активности (диагностика)
    var events;       // число колбэков onPosition (диагностика)

    function initialize(routeModel) {
        route = routeModel;
        hasFix = false;
        fixTime = null;
        zoom = 1;
        headingRad = null;
        headingBias = 0.0;
        arrived = false;
        vibedArrival = false;
        paused = false;
        warnIdx = -1;
        warnStart = 0;
        nowIdx = -1;
        offBuzzed = false;
        offSince = 0;
        lastTraveled = 0.0;
        signalsOn = true;
        demo = false;
        demoDist = 0.0;
        gpsAcc = 0;
        gpsHasPos = false;
        rec = false;
        events = 0;
        // до GPS-фикса «я» — старт маршрута (чтобы линия была видна сразу)
        meLatMicro = route.pts[0][0];
        meLonMicro = route.pts[0][1];
    }

    // Позицию сглаживаем (низкочастотный фильтр) — гасим дрожь слабого GPS.
    // Курс обновляем только если передан (hdg != null) — вызывающий даёт его лишь в движении.
    function setFix(latMicro, lonMicro, hdg) {
        if (hasFix && !demo) {
            // Difference first: weighted absolute longitude can overflow Number.
            meLatMicro += ((latMicro - meLatMicro) * 0.3).toNumber();
            meLonMicro += ((lonMicro - meLonMicro) * 0.3).toNumber();
        } else {
            meLatMicro = latMicro;
            meLonMicro = lonMicro;
        }
        if (hdg != null) { headingRad = hdg; }
        hasFix = true;
    }

    // Called by both GPS event delivery and polling; duplicates do not re-smooth.
    function acceptFix(lat, lon, quality, sampleTime, now) {
        if (quality < Cfg.GPS_MIN_QUALITY || sampleTime == null ||
            now - sampleTime > Cfg.GPS_MAX_AGE_SEC || sampleTime > now ||
            lat < -90000000 || lat > 90000000 || lon < -180000000 || lon > 180000000) {
            hasFix = false;
            return false;
        }
        if (fixTime != null && sampleTime <= fixTime) { return false; }
        demo = false;
        setFix(lat, lon, null);
        fixTime = sampleTime;
        return true;
    }

    function freshFix(now) {
        return demo || (hasFix && fixTime != null && now >= fixTime &&
            now - fixTime <= Cfg.GPS_MAX_AGE_SEC);
    }

    function canNavigate(now) { return !paused && freshFix(now); }

    function checkArrival(remaining, cross, now) {
        if (!canNavigate(now)) { return false; }
        var total = route.totalM();
        var threshold = total * 0.2;
        if (threshold > Cfg.ARRIVE_M) { threshold = Cfg.ARRIVE_M; }
        var endDistance = route.segMeters([meLatMicro, meLonMicro], route.pts[route.size() - 1]);
        return total > 0 && remaining <= threshold && cross <= Cfg.ARRIVE_M &&
            endDistance <= Cfg.ARRIVE_M;
    }

    // Эффективный курс: GPS, иначе начальный пеленг маршрута.
    function effHeading() {
        if (headingRad != null) {
            return headingRad;
        }
        return route.initialBearing();
    }

    function viewMeters() {
        return VIEW[zoom];
    }
}
