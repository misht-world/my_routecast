using Toybox.Test;

(:test)
function ignoresMalformedMessages(logger) {
    var r = new RouteReceiver();
    r.handle(42);
    r.handle({ "t" => 7 });
    r.handle({ "t" => "E" });
    r.handle({ "t" => "H", "v" => 99, "np" => 2, "nc" => 1, "nm" => 0, "name" => "bad" });
    Test.assertEqual(r.state, :idle);
    r.handle({ "t" => "H", "v" => 1, "np" => 2, "nc" => 1, "nm" => 0, "name" => "ok" });
    r.handle({ "t" => "L", "s" => 0, "p" => [[1]] });
    r.handle({ "t" => "L", "s" => 4, "p" => [[1, 2]] });
    Test.assertEqual(r.chunks.size(), 0);
    r.handle({ "t" => "L", "s" => 0, "p" => [[50000000, 30000000], [100, 100]] });
    r.handle({ "t" => "E" });
    r.handle({ "t" => "E" });
    Test.assertEqual(r.state, :ready);
    return true;
}

(:test)
function smoothingKeepsEasternLongitude(logger) {
    var model = new RouteModel([[50000000, 170000000], [50000100, 170000100]], []);
    var ns = new NavState(model);
    ns.setFix(50000000, 170000000, null);
    ns.setFix(50000100, 170000100, null);
    Test.assertEqual(ns.meLonMicro, 170000030);
    Test.assertEqual(ns.meLatMicro, 50000030);
    return true;
}

// CIQ unit-тесты сборки маршрута (Gate 2). Запуск: monkeyc --unit-test + monkeydo -t.

(:test)
function assemblesMockRoute(logger) {
    // Фиксированная последовательность (не зависит от MockFeeder/демо-мока).
    var r = new RouteReceiver();
    r.handle({ "t" => "H", "v" => 1, "np" => 5, "nc" => 2, "nm" => 2, "name" => "t" });
    r.handle({ "t" => "L", "s" => 0, "p" => [[50000000, 30000000], [100, 100], [100, 100]] });
    r.handle({ "t" => "L", "s" => 1, "p" => [[100, 100], [100, 100]] });
    r.handle({ "t" => "M", "m" => [[2, -2, 40], [4, 9, 80]] });
    r.handle({ "t" => "E" });

    Test.assertEqual(r.state, :ready);
    Test.assertEqual(r.points.size(), 5);
    Test.assertEqual(r.maneuvers.size(), 2);

    // делта-декод: первая точка абсолютная, далее +100 микроградусов на шаг
    Test.assertEqual(r.points[0][0], 50000000);
    Test.assertEqual(r.points[0][1], 30000000);
    Test.assertEqual(r.points[4][0], 50000400);
    Test.assertEqual(r.points[4][1], 30000400);
    return true;
}

(:test)
function detectsMissingChunk(logger) {
    var r = new RouteReceiver();
    r.handle({ "t" => "H", "v" => 1, "np" => 5, "nc" => 2, "nm" => 0, "name" => "x" });
    r.handle({ "t" => "L", "s" => 1, "p" => [[100, 100], [100, 100]] }); // пропущен s=0
    r.handle({ "t" => "E" });

    // assemble вернул null -> в READY не перешли
    Test.assert(r.state != :ready);
    return true;
}

(:test)
function rejectsCountMismatch(logger) {
    var r = new RouteReceiver();
    // заявили np=9, а пришло 5 точек
    r.handle({ "t" => "H", "v" => 1, "np" => 9, "nc" => 1, "nm" => 0, "name" => "x" });
    r.handle({ "t" => "L", "s" => 0, "p" => [[50000000, 30000000], [100, 100], [100, 100]] });
    r.handle({ "t" => "E" });

    Test.assertEqual(r.state, :error);
    return true;
}
