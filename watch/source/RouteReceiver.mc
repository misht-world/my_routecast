using Toybox.Communications;
using Toybox.System;
using Toybox.Lang;

// Приём и сборка маршрута по протоколу H/L/M/E (SPEC §5.2, docs/protocol.md).
// Gate 2, шаг 1: собираем и логируем, без рендера линии.
class RouteReceiver {

    // состояние: :idle :receiving :ready :error
    var state;
    var np, nc, nm, name;
    var chunks;     // Dictionary: seq -> массив [dlat, dlon]
    var points;     // массив [mlat, mlon] (абсолютные микроградусы)
    var maneuvers;  // массив [idx, type, dist]
    var logLine;
    var replyEnabled; // слать ack только при приёме от реального телефона (не из мока/тестов)

    function initialize() {
        logLine = "";
        replyEnabled = false;
        reset();
        state = :idle;
    }

    function reset() {
        np = 0; nc = 0; nm = 0; name = "";
        chunks = {};
        points = [];
        maneuvers = [];
    }

    function handle(d) {
        if (!(d instanceof Lang.Dictionary)) { return; }
        var t = d["t"];
        if (!(t instanceof Lang.String)) { return; }
        if (t.equals("H")) { onHeader(d); }
        else if (t.equals("L")) { onLine(d); }
        else if (t.equals("M")) { onManeuvers(d); }
        else if (t.equals("E")) { onEnd(d); }
    }

    function onHeader(d) {
        if (d["v"] != 1 || !(d["np"] instanceof Lang.Number) ||
            !(d["nc"] instanceof Lang.Number) || !(d["nm"] instanceof Lang.Number) ||
            !(d["name"] instanceof Lang.String)) { nack(-1); return; }
        if (d["np"] < 2 || d["np"] > Cfg.MAX_LINE_POINTS ||
            d["nc"] < 1 || d["nc"] > d["np"] || d["nm"] < 0) { nack(-1); return; }
        reset();
        np = d["np"]; nc = d["nc"]; nm = d["nm"]; name = d["name"];
        state = :receiving;
        log("H np=" + np + " nc=" + nc + " nm=" + nm);
        ack(-1);
    }

    function onLine(d) {
        var s = d["s"];
        if (state != :receiving || !(s instanceof Lang.Number)) { return; }
        var p = d["p"];
        if (s < 0 || s >= nc || !(p instanceof Lang.Array)) { nack(s); return; }
        if (p.size() < 1 || p.size() > Cfg.POINTS_PER_CHUNK) { nack(s); return; }
        for (var i = 0; i < p.size(); i++) {
            var pair = p[i];
            if (!(pair instanceof Lang.Array)) { nack(s); return; }
            if (pair.size() != 2 || !(pair[0] instanceof Lang.Number) ||
                !(pair[1] instanceof Lang.Number)) { nack(s); return; }
            if (pair[0] < -180000000 || pair[0] > 180000000 ||
                pair[1] < -360000000 || pair[1] > 360000000) { nack(s); return; }
        }
        var count = p.size();
        for (var seq = 0; seq < nc; seq++) {
            var previous = chunks.get(seq);
            if (seq != s && previous != null) { count += previous.size(); }
        }
        if (count > np) { nack(s); return; }
        chunks.put(s, d["p"]);
        log("L s=" + s + " pts=" + d["p"].size());
        ack(s);
    }

    function onManeuvers(d) {
        if (state != :receiving) { return; }
        var m = d["m"];
        if (!(m instanceof Lang.Array)) { nack(-2); return; }
        if (m.size() != nm) { nack(-2); return; }
        for (var i = 0; i < m.size(); i++) {
            var row = m[i];
            if (!(row instanceof Lang.Array)) { nack(-2); return; }
            if (row.size() != 3 || !(row[0] instanceof Lang.Number) ||
                !(row[1] instanceof Lang.Number) || !(row[2] instanceof Lang.Number)) { nack(-2); return; }
            if (row[0] < 0 || row[0] >= np || row[2] < 0 ||
                (row[1] != 9 && (row[1] < -3 || row[1] > 3))) { nack(-2); return; }
        }
        maneuvers = d["m"];
        log("M count=" + maneuvers.size());
        ack(-2);
    }

    function onEnd(d) {
        if (state == :ready) { ack(-3); return; }
        if (state != :receiving) { return; }
        points = assemble();
        if (points == null) {
            log("E: пропущен чанк " + firstMissing());
            nack(firstMissing());
            return;
        }
        if (points.size() == np && maneuvers.size() == nm) {
            state = :ready;
            log("E ok: " + points.size() + " pts -> READY");
            ack(-3);
        } else {
            state = :error;
            log("E mismatch pts=" + points.size() + "/" + np + " man=" + maneuvers.size() + "/" + nm);
            nack(firstMissing());
        }
    }

    // Дельты -> абсолютные микроградусы (накопительная сумма), чанки по порядку seq.
    function assemble() {
        var out = [];
        var lat = 0; var lon = 0; var first = true;
        for (var s = 0; s < nc; s++) {
            var p = chunks.get(s);
            if (p == null) { return null; }
            for (var i = 0; i < p.size(); i++) {
                var dd = p[i];
                if (first) { lat = dd[0]; lon = dd[1]; first = false; }
                else { lat += dd[0]; lon += dd[1]; }
                if (lat < -90000000 || lat > 90000000 ||
                    lon < -180000000 || lon > 180000000 || out.size() >= np) { return []; }
                out.add([lat, lon]);
            }
        }
        return out;
    }

    function firstMissing() {
        for (var s = 0; s < nc; s++) {
            if (chunks.get(s) == null) { return s; }
        }
        return 0;
    }

    function ack(s) {
        log("-> A(" + s + ")");
        send({ "t" => "A", "s" => s });
    }

    function nack(s) {
        log("-> N(" + s + ")");
        send({ "t" => "N", "s" => s });
    }

    function send(dict) {
        // Реальный ack шлём только когда приём идёт от телефона (replyEnabled).
        // Из мока/юнит-тестов transmit не зовём — он зависает в симуляторе без моста.
        if (replyEnabled) {
            try {
                Communications.transmit(dict, null, new AckListener());
            } catch (e) {
            }
        }
    }

    function log(s) {
        logLine = s;
        System.println(s);
    }
}

class AckListener extends Communications.ConnectionListener {
    function initialize() { ConnectionListener.initialize(); }
    function onComplete() {}
    function onError() {}
}
