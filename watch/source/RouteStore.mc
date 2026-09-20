using Toybox.Application;
using Toybox.Lang;

class RouteStore {
    var key;
    function initialize() { key = "lastRoute"; }
    function load() { return Application.Storage.getValue(key); }
    function save(data) { Application.Storage.setValue(key, data); }
}

class RouteData {
    static function validId(id) {
        if (!(id instanceof Lang.String)) { return false; }
        if (id.length() != 32) { return false; }
        for (var i = 0; i < id.length(); i++) {
            if ("0123456789abcdef".find(id.substring(i, i + 1)) == null) { return false; }
        }
        return true;
    }
    static function numberRow(row, size) {
        if (!(row instanceof Lang.Array)) { return false; }
        if (row.size() != size) { return false; }
        for (var i = 0; i < size; i++) { if (!(row[i] instanceof Lang.Number)) { return false; } }
        return true;
    }
    static function validPoint(p) {
        return numberRow(p, 2) && p[0] >= -90000000 && p[0] <= 90000000 &&
            p[1] >= -180000000 && p[1] <= 180000000;
    }
    static function validManeuver(m, count) {
        return numberRow(m, 3) && m[0] >= 0 && m[0] < count && m[2] >= 0 &&
            (m[1] == 9 || (m[1] >= -3 && m[1] <= 3));
    }
    static function valid(data) {
        if (!(data instanceof Lang.Dictionary) || data["format"] != 1 || !validId(data["id"]) ||
            !(data["name"] instanceof Lang.String) || !(data["p"] instanceof Lang.Array) ||
            !(data["m"] instanceof Lang.Array)) { return false; }
        var p = data["p"]; var m = data["m"];
        if (data["name"].length() > Cfg.MAX_ROUTE_NAME || p.size() < 2 ||
            p.size() > Cfg.MAX_LINE_POINTS || m.size() > Cfg.MAX_MANEUVERS) { return false; }
        var distinct = false;
        for (var i = 0; i < p.size(); i++) {
            if (!validPoint(p[i])) { return false; }
            if (p[i][0] != p[0][0] || p[i][1] != p[0][1]) { distinct = true; }
        }
        for (var j = 0; j < m.size(); j++) { if (!validManeuver(m[j], p.size())) { return false; } }
        return distinct;
    }
}
