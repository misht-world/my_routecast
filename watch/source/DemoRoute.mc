// Synthetic public fixture; does not depend on a developer's private GPX track.
class DemoRoute {
    static function feed(r) {
        var id = "000000000000000000000000000000dd";
        var p = [[50000000, 30000000]];
        for (var i = 1; i < 8; i++) { p.add([0, 250]); }
        for (var j = 0; j < 8; j++) { p.add([250, 0]); }
        r.handle({ "t" => "H", "id" => id, "v" => 2, "np" => 16, "nc" => 1,
            "nm" => 2, "mc" => 1, "name" => "Sample route" });
        r.handle({ "t" => "L", "id" => id, "s" => 0, "p" => p });
        r.handle({ "t" => "M", "id" => id, "s" => 1, "m" => [[7, -2, 120], [15, 9, 300]] });
        r.handle({ "t" => "E", "id" => id });
    }
}
