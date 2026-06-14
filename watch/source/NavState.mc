// Состояние навигации: маршрут + текущая позиция/курс + зум.
class NavState {

    // 3 уровня зума — охват впереди в метрах (SPEC §5.4): ближе/средний/дальше
    const VIEW = [320.0, 150.0, 60.0];

    var route;        // RouteModel
    var meLatMicro;
    var meLonMicro;
    var headingRad;   // Float или null (нет курса с GPS)
    var hasFix;
    var zoom;         // 0..2, по умолчанию средний
    var arrived;      // достигнут финиш
    var vibedArrival; // вибро прибытия уже дано
    var paused;       // навигация на паузе

    function initialize(routeModel) {
        route = routeModel;
        hasFix = false;
        zoom = 1;
        headingRad = null;
        arrived = false;
        vibedArrival = false;
        paused = false;
        // до GPS-фикса «я» — старт маршрута (чтобы линия была видна сразу)
        meLatMicro = route.pts[0][0];
        meLonMicro = route.pts[0][1];
    }

    function setFix(latMicro, lonMicro, hdg) {
        meLatMicro = latMicro;
        meLonMicro = lonMicro;
        headingRad = hdg;
        hasFix = true;
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
