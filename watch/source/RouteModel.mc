using Toybox.Math;

// Модель собранного маршрута + математика следования (SPEC §5.4–5.5).
// Точки — [latMicro, lonMicro] (целые микроградусы). Проекция — equirectangular
// в локальные метры относительно старта (погрешность на дистанциях навигации пренебрежима).
class RouteModel {

    const EARTH_R = 6371000.0;

    var pts;          // массив [latMicro, lonMicro]
    var cum;          // накопленная дистанция, метры (Float)
    var maneuvers;    // массив [idx, type, distM]
    var mPerDegLat;
    var mPerDegLon;

    function initialize(points, mans) {
        pts = points;
        maneuvers = mans;
        var n = pts.size();
        cum = new [n];
        if (n == 0) { return; }
        var lat0Rad = deg(pts[0][0]) * Math.PI / 180.0;
        mPerDegLat = EARTH_R * Math.PI / 180.0;
        mPerDegLon = mPerDegLat * Math.cos(lat0Rad);
        cum[0] = 0.0;
        for (var i = 1; i < n; i++) {
            cum[i] = cum[i - 1] + segMeters(pts[i - 1], pts[i]);
        }
    }

    function deg(micro) { return micro / 1000000.0; }

    function segMeters(a, b) {
        var dLat = deg(b[0] - a[0]) * mPerDegLat;
        var dLon = deg(b[1] - a[1]) * mPerDegLon;
        return Math.sqrt(dLat * dLat + dLon * dLon);
    }

    function size() { return pts.size(); }

    function totalM() {
        var n = cum.size();
        return n > 0 ? cum[n - 1] : 0.0;
    }

    // Локальные метры точки относительно старта маршрута (x — восток, y — север).
    function toXY(latMicro, lonMicro) {
        var x = deg(lonMicro - pts[0][1]) * mPerDegLon;
        var y = deg(latMicro - pts[0][0]) * mPerDegLat;
        return [x, y];
    }

    // Ближайшая точка полилинии к (latMicro, lonMicro).
    // Возврат: [segIdx, t, crossM, traveledM].
    function nearest(latMicro, lonMicro) {
        var p = toXY(latMicro, lonMicro);
        var bestD = 1.0e30;
        var bestSeg = 0;
        var bestT = 0.0;
        var bestTrav = 0.0;
        for (var i = 0; i < pts.size() - 1; i++) {
            var a = toXY(pts[i][0], pts[i][1]);
            var b = toXY(pts[i + 1][0], pts[i + 1][1]);
            var dx = b[0] - a[0];
            var dy = b[1] - a[1];
            var len2 = dx * dx + dy * dy;
            var t = 0.0;
            if (len2 > 0.0) {
                t = ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / len2;
                if (t < 0.0) { t = 0.0; }
                if (t > 1.0) { t = 1.0; }
            }
            var cx = a[0] + t * dx;
            var cy = a[1] + t * dy;
            var ddx = p[0] - cx;
            var ddy = p[1] - cy;
            var d = Math.sqrt(ddx * ddx + ddy * ddy);
            if (d < bestD) {
                bestD = d;
                bestSeg = i;
                bestT = t;
                bestTrav = cum[i] + t * (cum[i + 1] - cum[i]);
            }
        }
        return [bestSeg, bestT, bestD, bestTrav];
    }

    // Первый манёвр с distM > traveledM (с небольшим допуском).
    function nextManeuver(traveledM) {
        for (var i = 0; i < maneuvers.size(); i++) {
            if (maneuvers[i][2] > traveledM - 2.0) {
                return maneuvers[i];
            }
        }
        return maneuvers.size() > 0 ? maneuvers[maneuvers.size() - 1] : null;
    }

    // Начальный пеленг маршрута (рад, от севера по часовой) — fallback курса без GPS.
    function initialBearing() {
        if (pts.size() < 2) { return 0.0; }
        var a = toXY(pts[0][0], pts[0][1]);
        var b = toXY(pts[1][0], pts[1][1]);
        return Math.atan2(b[0] - a[0], b[1] - a[1]); // atan2(east, north)
    }

    // Знаковый угол поворота (рад) в вершине idx — из геометрии принятой линии
    // (часам не нужен угол в протоколе). + влево (ccw в east/north), − вправо.
    function bendRadAt(idx) {
        var k = 2;
        var i0 = idx - k; if (i0 < 0) { i0 = 0; }
        var i1 = idx + k; if (i1 > pts.size() - 1) { i1 = pts.size() - 1; }
        var a = toXY(pts[i0][0], pts[i0][1]);
        var b = toXY(pts[idx][0], pts[idx][1]);
        var c = toXY(pts[i1][0], pts[i1][1]);
        var ix = b[0] - a[0]; var iy = b[1] - a[1];
        var ox = c[0] - b[0]; var oy = c[1] - b[1];
        return Math.atan2(ix * oy - iy * ox, ix * ox + iy * oy);
    }

    // Точка на маршруте на дистанции distM от старта (для look-ahead цели пеленга).
    function pointAtDist(distM) {
        if (distM <= 0.0 || pts.size() == 0) { return pts[0]; }
        for (var i = 1; i < pts.size(); i++) {
            if (cum[i] >= distM) {
                var segLen = cum[i] - cum[i - 1];
                var f = segLen > 0.0 ? (distM - cum[i - 1]) / segLen : 0.0;
                var lat = pts[i - 1][0] + ((pts[i][0] - pts[i - 1][0]) * f).toNumber();
                var lon = pts[i - 1][1] + ((pts[i][1] - pts[i - 1][1]) * f).toNumber();
                return [lat, lon];
            }
        }
        return pts[pts.size() - 1];
    }
}
