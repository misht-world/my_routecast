// Канон сообщений протокола для проверки в симуляторе (Gate 2).
// Маршрут с реальным поворотом налево (восток -> север), чтобы баннер/угол были осмысленны.
class MockFeeder {

    static function feed(r) {
        var lat = 50000000; // 50.0°
        var lon = 30000000; // 30.0°
        var prevLat = 0;
        var prevLon = 0;
        var first = true;
        var p = [];
        var i;

        // 8 точек на восток
        for (i = 0; i < 8; i++) {
            if (first) { p.add([lat, lon]); first = false; }
            else { p.add([lat - prevLat, lon - prevLon]); }
            prevLat = lat; prevLon = lon;
            lon += 250;
        }
        // 8 точек на север (поворот налево)
        for (i = 0; i < 8; i++) {
            lat += 250;
            p.add([lat - prevLat, lon - prevLon]);
            prevLat = lat; prevLon = lon;
        }

        // 16 точек, 1 чанк, 2 манёвра (dist в M игнорируется — модель берёт cum[idx]).
        r.handle({ "t" => "H", "v" => 1, "np" => 16, "nc" => 1, "nm" => 2, "name" => "mock" });
        r.handle({ "t" => "L", "s" => 0, "p" => p });
        r.handle({ "t" => "M", "m" => [[8, -2, 0], [15, 9, 0]] });
        r.handle({ "t" => "E" });
    }
}
