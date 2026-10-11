using Toybox.Test;
using Toybox.Math;

(:test)
function gpsFreshnessAndDuplicateFix(logger) {
    var ns = new NavState(new RouteModel(eastRoute(), []));
    Test.assert(!ns.canNavigate(100));
    Test.assert(!ns.acceptFix(50000000, 30000000, 2, 100, 100));
    Test.assert(!ns.acceptFix(50000000, 30000000, 3, null, 100));
    Test.assert(!ns.acceptFix(50000000, 30000000, 3, 80, 100));
    Test.assert(ns.acceptFix(50000000, 30000000, 3, 100, 100));
    Test.assert(ns.canNavigate(105));
    Test.assert(!ns.acceptFix(50000000, 30001000, 3, 100, 105));
    Test.assertEqual(ns.meLonMicro, 30000000);
    Test.assert(!ns.canNavigate(111));
    ns.paused = true;
    Test.assert(!ns.canNavigate(105));
    return true;
}

(:test)
function arrivalRequiresGpsEndpointAndUnpaused(logger) {
    var ns = new NavState(new RouteModel(eastRoute(), []));
    Test.assert(!ns.checkArrival(0, 0, 100));
    ns.acceptFix(50000200, 30004000, 3, 100, 100);
    Test.assert(!ns.checkArrival(0, 22, 100));
    ns.hasFix = false;
    ns.acceptFix(50000000, 30004000, 3, 101, 101);
    Test.assert(ns.checkArrival(0, 0, 101));
    ns.paused = true;
    Test.assert(!ns.checkArrival(0, 0, 101));
    ns.paused = false;
    Test.assert(!ns.checkArrival(0, 0, 112));
    return true;
}

function angleErr(a, b) {
    var e = a - b;
    if (e < 0) { e = -e; }
    return e;
}

(:test)
function headingIgnoresCompassWhileWalking(logger) {
    var ns = new NavState(new RouteModel(eastRoute(), []));
    var east = Math.PI / 2;
    ns.updateHeading(east, 1.3, true, 0.0, 1000); // идём на восток, компас врёт (север)
    Test.assert(ns.moving);
    // скорость проседает ниже порога входа, но выше порога выхода — компас не подмешиваем
    for (var t = 1200; t <= 3000; t += 200) { ns.updateHeading(east, 0.8, true, 0.0, t); }
    Test.assert(ns.moving);
    Test.assert(angleErr(ns.headingRad, east) < 0.01);
    // краткий провал GPS — курс держим, а не уходим на компас
    for (var u = 3200; u <= 4400; u += 200) { ns.updateHeading(null, 0.0, false, 0.0, u); }
    Test.assert(ns.moving);
    Test.assert(angleErr(ns.headingRad, east) < 0.01);
    return true;
}

(:test)
function stationaryUsesCompassPlusLearnedBias(logger) {
    var ns = new NavState(new RouteModel(eastRoute(), []));
    var east = Math.PI / 2;
    var off = 30.0 * Math.PI / 180.0; // компас показывает на 30° меньше истинного
    var t = 0;
    for (var i = 0; i < 40; i++) { t += 200; ns.updateHeading(east, 1.4, true, east - off, t); }
    Test.assert(ns.biasLearned);
    for (var j = 0; j < 30; j++) { t += 200; ns.updateHeading(null, 0.0, true, east - off, t); }
    Test.assert(!ns.moving);
    Test.assert(angleErr(ns.headingRad, east) < 0.05);
    return true;
}

(:test)
function compassOffHoldsLastGpsHeading(logger) {
    var ns = new NavState(new RouteModel(eastRoute(), []));
    ns.useCompass = false;
    var east = Math.PI / 2;
    var t = 0;
    for (var i = 0; i < 10; i++) { t += 200; ns.updateHeading(east, 1.4, true, 0.0, t); }
    for (var j = 0; j < 30; j++) { t += 200; ns.updateHeading(null, 0.0, true, 0.0, t); }
    Test.assert(!ns.moving);
    Test.assert(angleErr(ns.headingRad, east) < 0.01);
    return true;
}

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
