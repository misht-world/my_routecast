using Toybox.Test;
using Toybox.Math;

// Тесты математики следования RouteModel (Gate 2). Маршрут в микроградусах.

// прямой маршрут на восток: 5 точек по 0.001° долготы на широте 50°
function eastRoute() {
    var p = [];
    for (var i = 0; i < 5; i++) {
        p.add([50000000, 30000000 + i * 1000]);
    }
    return p;
}

(:test)
function totalDistanceIsSane(logger) {
    var m = new RouteModel(eastRoute(), []);
    // 4 сегмента * ~71.6 м (0.001° долготы на 50°) ≈ 286 м
    var total = m.totalM();
    Test.assert(total > 270.0 && total < 300.0);
    return true;
}

(:test)
function traveledAtVertex(logger) {
    var m = new RouteModel(eastRoute(), []);
    var r = m.nearest(50000000, 30002000); // ровно точка с индексом 2
    // crossM ~ 0, traveledM ~ cum[2] ~ 143 м
    Test.assert(r[2] < 1.0);
    Test.assert(r[3] > 135.0 && r[3] < 152.0);
    return true;
}

(:test)
function crossTrackForOffsetPoint(logger) {
    var m = new RouteModel(eastRoute(), []);
    // смещение на север на 0.0002° (~22 м) над точкой 2
    var r = m.nearest(50000200, 30002000);
    Test.assert(r[2] > 18.0 && r[2] < 26.0); // crossM ~ 22
    return true;
}

(:test)
function nextManeuverSelection(logger) {
    var mans = [[1, -2, 70], [4, 9, 286]];
    var m = new RouteModel(eastRoute(), mans);
    Test.assertEqual(m.nextManeuver(0.0)[1], -2);   // первый поворот
    Test.assertEqual(m.nextManeuver(100.0)[1], 9);  // уже после поворота -> финиш
    return true;
}

(:test)
function pointAtDistInterpolates(logger) {
    var m = new RouteModel(eastRoute(), []);
    var half = m.totalM() / 2.0;
    var p = m.pointAtDist(half);
    // на середине прямого маршрута долгота ~ 30.002°, широта ~ 50°
    var dLon = p[1] - 30002000;
    if (dLon < 0) { dLon = -dLon; }
    Test.assert(dLon < 2000);
    Test.assertEqual(p[0], 50000000);
    return true;
}
