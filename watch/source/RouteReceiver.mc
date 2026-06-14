using Toybox.Communications;
using Toybox.System;

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
        if (d == null) { return; }
        var t = d["t"];
        if (t == null) { return; }
        if (t.equals("H")) { onHeader(d); }
        else if (t.equals("L")) { onLine(d); }
        else if (t.equals("M")) { onManeuvers(d); }
        else if (t.equals("E")) { onEnd(d); }
    }

    function onHeader(d) {
        reset();
        np = d["np"]; nc = d["nc"]; nm = d["nm"]; name = d["name"];
        state = :receiving;
        log("H np=" + np + " nc=" + nc + " nm=" + nm);
        ack(-1);
    }

    function onLine(d) {
        var s = d["s"];
        chunks.put(s, d["p"]);
        log("L s=" + s + " pts=" + d["p"].size());
        ack(s);
    }

    function onManeuvers(d) {
        maneuvers = d["m"];
        log("M count=" + maneuvers.size());
        ack(-2);
    }

    function onEnd(d) {
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
