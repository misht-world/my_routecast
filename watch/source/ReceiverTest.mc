using Toybox.Test;

function transferIdA() { return "00000000000000000000000000000001"; }
function transferIdB() { return "00000000000000000000000000000002"; }
function testHeader(r, id) {
    r.handle({ "t" => "H", "id" => id, "v" => 2, "np" => 2, "nc" => 1,
        "nm" => 1, "mc" => 1, "name" => "Test route" });
}
function testLine(r, id) {
    r.handle({ "t" => "L", "id" => id, "s" => 0, "p" => [[50000000, 30000000], [100, 100]] });
}
function testManeuvers(r, id) {
    r.handle({ "t" => "M", "id" => id, "s" => 1, "m" => [[1, 9, 15]] });
}
function testEnd(r, id) { r.handle({ "t" => "E", "id" => id }); }
function completeTestRoute(r, id) {
    testHeader(r, id); testLine(r, id); testManeuvers(r, id); testEnd(r, id);
}

class MemoryRouteStore {
    var data, writes, fail;
    function initialize() { data = null; writes = 0; fail = false; }
    function save(value) {
        if (fail) { throw new Toybox.Lang.InvalidValueException("Storage unavailable"); }
        data = value; writes++;
    }
    function load() { return data; }
}

(:test)
function transferCommitsAndRestoresOnce(logger) {
    var r = new RouteReceiver(); var memory = new MemoryRouteStore(); r.store = memory;
    completeTestRoute(r, transferIdA());
    Test.assertEqual(r.state, :ready);
    Test.assertEqual(r.points[1][0], 50000100);
    Test.assertEqual(memory.writes, 1);
    testEnd(r, transferIdA());
    Test.assertEqual(memory.writes, 1);
    Test.assertEqual(r.lastReply["s"], -3);
    var restored = new RouteReceiver(); restored.store = memory; restored.restore();
    Test.assertEqual(restored.state, :ready);
    Test.assertEqual(restored.points[1][1], 30000100);
    return true;
}

(:test)
function oldRouteSurvivesFailedReplacement(logger) {
    var r = new RouteReceiver(); var memory = new MemoryRouteStore(); r.store = memory;
    completeTestRoute(r, transferIdA());
    memory.fail = true;
    completeTestRoute(r, transferIdB());
    Test.assertEqual(r.committedId, transferIdA());
    Test.assertEqual(r.state, :ready);
    Test.assertEqual(r.lastReply["reason"], "storage");
    Test.assertEqual(memory.writes, 1);
    return true;
}

(:test)
function ignoresForeignAndMalformedPackets(logger) {
    var r = new RouteReceiver();
    r.handle(42); r.handle({ "t" => 7 });
    testHeader(r, transferIdA());
    testLine(r, transferIdB());
    Test.assertEqual(r.nextSeq, 0);
    r.handle({ "t" => "L", "id" => transferIdA(), "s" => 0, "p" => [[1]] });
    Test.assertEqual(r.nextSeq, 0);
    Test.assertEqual(r.lastReply["reason"], "invalid");
    testLine(r, transferIdA());
    testHeader(r, transferIdA()); // Duplicate H must not reset staging.
    testLine(r, transferIdA()); // Duplicate chunk must not append twice.
    Test.assertEqual(r.nextSeq, 1);
    Test.assertEqual(r.pendingPoints.size(), 2);
    testManeuvers(r, transferIdA()); testEnd(r, transferIdA());
    Test.assertEqual(r.state, :ready);
    return true;
}

(:test)
function rejectsMissingChunksAndExpiresStaging(logger) {
    var r = new RouteReceiver();
    completeTestRoute(r, transferIdA());
    testHeader(r, transferIdB());
    testEnd(r, transferIdB());
    Test.assertEqual(r.lastReply["reason"], "restart");
    Test.assertEqual(r.committedId, transferIdA());
    r.expire(r.lastMessage + Cfg.TRANSFER_IDLE_MS);
    Test.assertEqual(r.state, :ready);
    Test.assert(r.id == null);
    return true;
}

(:test)
function rejectsBadCoordinatesAndManeuverIndices(logger) {
    var r = new RouteReceiver();
    testHeader(r, transferIdA());
    r.handle({ "t" => "L", "id" => transferIdA(), "s" => 0,
        "p" => [[90000000, 0], [1, 0]] });
    Test.assertEqual(r.pendingPoints.size(), 0); // Atomic chunk validation.
    testLine(r, transferIdA());
    r.handle({ "t" => "M", "id" => transferIdA(), "s" => 1, "m" => [[2, 9, 15]] });
    Test.assertEqual(r.pendingManeuvers.size(), 0);
    Test.assertEqual(r.lastReply["reason"], "invalid");
    return true;
}

(:test)
function rejectsBadVersionAndCorruptSnapshot(logger) {
    var r = new RouteReceiver();
    r.handle({ "t" => "H", "id" => transferIdA(), "v" => 1 });
    Test.assertEqual(r.lastReply["reason"], "version");
    var memory = new MemoryRouteStore(); memory.data = { "format" => 9 };
    r.store = memory; r.restore();
    Test.assertEqual(r.state, :idle);
    return true;
}

(:test)
function smoothingKeepsEasternLongitude(logger) {
    var ns = new NavState(new RouteModel([[50000000, 170000000], [50000100, 170000100]], []));
    ns.setFix(50000000, 170000000, null); ns.setFix(50000100, 170000100, null);
    Test.assertEqual(ns.meLonMicro, 170000030);
    Test.assertEqual(ns.meLatMicro, 50000030);
    return true;
}

(:test)
function maximumRouteFitsStorageAndRestores(logger) {
    var r = new RouteReceiver();
    var disk = new RouteStore(); disk.key = "testRouteSnapshot"; r.store = disk;
    var id = transferIdA();
    r.handle({ "t" => "H", "id" => id, "v" => 2, "np" => 250, "nc" => 7,
        "nm" => 250, "mc" => 13, "name" => "Maximum route" });
    for (var s = 0; s < 7; s++) {
        var p = [];
        var size = s == 6 ? 10 : 40;
        for (var i = 0; i < size; i++) {
            p.add(s == 0 && i == 0 ? [50000000, 30000000] : [10, 10]);
        }
        r.handle({ "t" => "L", "id" => id, "s" => s, "p" => p });
    }
    for (var j = 0; j < 13; j++) {
        var m = [];
        var count = j == 12 ? 10 : 20;
        for (var k = 0; k < count; k++) { m.add([j * 20 + k, 2, (j * 20 + k) * 2]); }
        r.handle({ "t" => "M", "id" => id, "s" => 7 + j, "m" => m });
    }
    testEnd(r, id);
    Test.assertEqual(r.state, :ready);
    var restored = new RouteReceiver(); restored.store = disk; restored.restore();
    Test.assertEqual(restored.points.size(), 250);
    Test.assertEqual(restored.maneuvers.size(), 250);
    Toybox.Application.Storage.deleteValue("testRouteSnapshot");
    return true;
}
