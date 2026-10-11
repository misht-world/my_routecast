using Toybox.Communications;
using Toybox.System;
using Toybox.Lang;

// Active route and bounded staging are separate. Only E can commit a route.
class RouteReceiver {
    var state, points, maneuvers, name, committedId;
    var id, np, nc, nm, mc, pendingName, pendingPoints, pendingManeuvers, nextSeq;
    var lastMessage, logLine, replyEnabled, store, lastReply;
    // Маршрут лишь сохранён с прошлого раза (или навигация завершена): стартовый экран
    // показывает ожидание нового трека, прошлый — по START/MENU. Свежий приём сбрасывает.
    var savedOnly;

    function initialize() {
        points = []; maneuvers = []; name = ""; committedId = null;
        store = null; replyEnabled = false; logLine = ""; lastReply = null; savedOnly = false;
        cancelPending();
    }

    function hasRoute() { return points.size() >= 2; }

    function cancelPending() {
        id = null; np = 0; nc = 0; nm = 0; mc = 0; nextSeq = 0;
        pendingPoints = []; pendingManeuvers = []; pendingName = "";
        lastMessage = 0;
        state = hasRoute() ? :ready : :idle;
    }

    function reset() { cancelPending(); }

    function restore() {
        if (store == null) { return; }
        try {
            var data = store.load();
            if (RouteData.valid(data)) {
                points = data["p"]; maneuvers = data["m"]; name = data["name"];
                committedId = data["id"]; state = :ready; savedOnly = true;
            }
        } catch (e) { logLine = "Saved route unavailable"; }
    }

    function expire(now) {
        if (state == :receiving && now - lastMessage >= Cfg.TRANSFER_IDLE_MS) {
            cancelPending(); logLine = "Transfer interrupted. Retry on phone.";
        }
    }

    function handle(d) {
        if (!(d instanceof Lang.Dictionary) || !(d["t"] instanceof Lang.String) ||
            !RouteData.validId(d["id"])) { return; }
        var t = d["t"];
        var incoming = d["id"];
        if (t.equals("H")) { onHeader(d); return; }
        if (t.equals("E") && committedId != null && incoming.equals(committedId)) {
            reply("A", incoming, -3, null); return;
        }
        if (id == null || !incoming.equals(id) || state != :receiving) { return; }
        lastMessage = System.getTimer();
        if (t.equals("L")) { onChunk(d, false); }
        else if (t.equals("M")) { onChunk(d, true); }
        else if (t.equals("E")) { onEnd(); }
    }

    function onHeader(d) {
        var incoming = d["id"];
        if (d["v"] != Cfg.PROTOCOL_VERSION) {
            reply("N", incoming, -1, "version"); logLine = "Update both apps"; return;
        }
        if (!(d["np"] instanceof Lang.Number) || !(d["nc"] instanceof Lang.Number) ||
            !(d["nm"] instanceof Lang.Number) || !(d["mc"] instanceof Lang.Number) ||
            !(d["name"] instanceof Lang.String)) { reply("N", incoming, -1, "invalid"); return; }
        var expectedMc = (d["nm"] + Cfg.MANEUVERS_PER_CHUNK - 1) / Cfg.MANEUVERS_PER_CHUNK;
        if (expectedMc < 1) { expectedMc = 1; }
        if (d["np"] < 2 || d["np"] > Cfg.MAX_LINE_POINTS || d["nm"] < 0 ||
            d["nm"] > Cfg.MAX_MANEUVERS || d["name"].length() > Cfg.MAX_ROUTE_NAME ||
            d["nc"] != (d["np"] + Cfg.POINTS_PER_CHUNK - 1) / Cfg.POINTS_PER_CHUNK ||
            d["mc"] != expectedMc) { reply("N", incoming, -1, "invalid"); return; }
        if ((id != null && incoming.equals(id)) ||
            (committedId != null && incoming.equals(committedId))) {
            lastMessage = System.getTimer(); reply("A", incoming, -1, null); return;
        }
        cancelPending();
        id = incoming; np = d["np"]; nc = d["nc"]; nm = d["nm"]; mc = d["mc"];
        pendingName = d["name"]; state = :receiving; lastMessage = System.getTimer();
        logLine = "Receiving route";
        reply("A", id, -1, null);
    }

    function onChunk(d, isManeuver) {
        var s = d["s"];
        if (!(s instanceof Lang.Number)) { return; }
        if (s == nextSeq - 1 && s >= 0) { reply("A", id, s, null); return; }
        if (s != nextSeq || (isManeuver && (s < nc || s >= nc + mc)) ||
            (!isManeuver && (s < 0 || s >= nc))) { reply("N", id, s, "restart"); return; }
        var rows = isManeuver ? d["m"] : d["p"];
        var remaining = isManeuver ? nm - pendingManeuvers.size() : np - pendingPoints.size();
        var limit = isManeuver ? Cfg.MANEUVERS_PER_CHUNK : Cfg.POINTS_PER_CHUNK;
        if (remaining < limit) { limit = remaining; }
        if (!(rows instanceof Lang.Array)) { reply("N", id, s, "invalid"); return; }
        if (rows.size() != limit) { reply("N", id, s, "invalid"); return; }
        // Validate the whole chunk before changing staging (including cumulative deltas).
        var decoded = [];
        var lat = pendingPoints.size() == 0 ? 0 : pendingPoints[pendingPoints.size() - 1][0];
        var lon = pendingPoints.size() == 0 ? 0 : pendingPoints[pendingPoints.size() - 1][1];
        for (var i = 0; i < rows.size(); i++) {
            var row = rows[i];
            if (isManeuver) {
                if (!RouteData.validManeuver(row, np)) { reply("N", id, s, "invalid"); return; }
            } else {
                if (!RouteData.numberRow(row, 2)) { reply("N", id, s, "invalid"); return; }
                if (row[0] < -180000000 || row[0] > 180000000 ||
                    row[1] < -360000000 || row[1] > 360000000) { reply("N", id, s, "invalid"); return; }
                lat += row[0]; lon += row[1];
                if (!RouteData.validPoint([lat, lon])) { reply("N", id, s, "invalid"); return; }
                decoded.add([lat, lon]);
            }
        }
        for (var k = 0; k < rows.size(); k++) {
            if (isManeuver) { pendingManeuvers.add(rows[k]); }
            else { pendingPoints.add(decoded[k]); }
        }
        nextSeq++;
        reply("A", id, s, null);
    }

    function onEnd() {
        if (nextSeq != nc + mc || pendingPoints.size() != np || pendingManeuvers.size() != nm) {
            reply("N", id, -3, "restart"); return;
        }
        var data = { "format" => 1, "id" => id, "name" => pendingName,
            "p" => pendingPoints, "m" => pendingManeuvers };
        if (!RouteData.valid(data)) { reply("N", id, -3, "invalid"); return; }
        if (store != null) {
            try { store.save(data); }
            catch (e) { reply("N", id, -3, "storage"); cancelPending(); logLine = "Could not save route"; return; }
        }
        points = pendingPoints; maneuvers = pendingManeuvers; name = pendingName; committedId = id;
        savedOnly = false;
        cancelPending(); logLine = "Route ready";
        reply("A", committedId, -3, null);
    }

    function reply(type, transferId, seq, reason) {
        var data = { "t" => type, "id" => transferId, "s" => seq };
        if (reason != null) { data.put("reason", reason); }
        lastReply = data;
        if (replyEnabled) {
            try { Communications.transmit(data, null, new AckListener()); } catch (e) {}
        }
    }
}

class AckListener extends Communications.ConnectionListener {
    function initialize() { ConnectionListener.initialize(); }
    function onComplete() {}
    function onError() {}
}
