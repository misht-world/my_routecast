using Toybox.WatchUi;
using Toybox.Graphics;

// Экран до навигации: обзор всего маршрута + дистанция + ▶ (готов к старту),
// либо приём, либо ожидание маршрута. Без отладочного текста. Монохром.
class MainView extends WatchUi.View {

    var r;

    function initialize(receiver) {
        View.initialize();
        r = receiver;
    }

    function onUpdate(dc) {
        var W = dc.getWidth();
        var H = dc.getHeight();
        var cx = W / 2;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);

        // Версия — сверху по центру (видно во всех состояниях, что переустановилось)
        dc.drawText(cx, 4, Graphics.FONT_XTINY, Cfg.VERSION, Graphics.TEXT_JUSTIFY_CENTER);

        if (r.state == :ready) {
            drawOverview(dc, W, H, cx);
            drawPlay(dc); // ▶ в субэкране
        } else if (r.state == :receiving) {
            dc.drawText(cx, H / 2 - 26, Graphics.FONT_SMALL, "Receiving", Graphics.TEXT_JUSTIFY_CENTER);
            var bw = 150;
            var x = cx - bw / 2;
            var y = H / 2 + 6;
            dc.setPenWidth(1);
            dc.drawRectangle(x, y, bw, 10);
            var frac = (r.np > 0) ? (r.points.size().toFloat() / r.np) : 0.0;
            dc.fillRectangle(x, y, (bw * frac).toNumber(), 10);
        } else {
            dc.drawText(cx, H / 2 - 16, Graphics.FONT_SMALL, "Waiting for route", Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(cx, H / 2 + 12, Graphics.FONT_TINY, "from phone", Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    function drawOverview(dc, W, H, cx) {
        var model = new RouteModel(r.points, r.maneuvers);
        var n = model.size();
        if (n < 2) { return; }

        var minX = 1.0e30; var minY = 1.0e30;
        var maxX = -1.0e30; var maxY = -1.0e30;
        for (var i = 0; i < n; i++) {
            var q = model.toXY(r.points[i][0], r.points[i][1]);
            if (q[0] < minX) { minX = q[0]; }
            if (q[0] > maxX) { maxX = q[0]; }
            if (q[1] < minY) { minY = q[1]; }
            if (q[1] > maxY) { maxY = q[1]; }
        }
        var spanX = maxX - minX; if (spanX < 1.0) { spanX = 1.0; }
        var spanY = maxY - minY; if (spanY < 1.0) { spanY = 1.0; }
        var ocx = (minX + maxX) / 2.0;
        var ocy = (minY + maxY) / 2.0;
        var mcx = cx;
        var mcy = (H * 0.46).toNumber();
        var scX = (W * 0.72) / spanX;
        var scY = (H * 0.52) / spanY;
        var sc = scX < scY ? scX : scY;

        // полилиния
        dc.setPenWidth(3);
        var pHave = false; var pX = 0.0; var pY = 0.0;
        for (var k = 0; k < n; k++) {
            var q2 = model.toXY(r.points[k][0], r.points[k][1]);
            var sx = mcx + (q2[0] - ocx) * sc;
            var sy = mcy - (q2[1] - ocy) * sc;
            if (pHave) { dc.drawLine(pX, pY, sx, sy); }
            pX = sx; pY = sy; pHave = true;
        }
        // старт (точка) и финиш (кольцо)
        var qs = model.toXY(r.points[0][0], r.points[0][1]);
        dc.fillCircle(mcx + (qs[0] - ocx) * sc, mcy - (qs[1] - ocy) * sc, 5);
        var qf = model.toXY(r.points[n - 1][0], r.points[n - 1][1]);
        dc.setPenWidth(2);
        dc.drawCircle(mcx + (qf[0] - ocx) * sc, mcy - (qf[1] - ocy) * sc, 7);

        // общая дистанция
        dc.drawText(cx, H - 32, Graphics.FONT_MEDIUM, fmtDist(model.totalM()), Graphics.TEXT_JUSTIFY_CENTER);
    }

    // ▶ в субэкране (правый-верхний)
    function drawPlay(dc) {
        var scx = 144;
        var scy = 31;
        dc.fillPolygon([[scx - 9, scy - 12], [scx + 13, scy], [scx - 9, scy + 12]]);
    }

    function fmtDist(m) {
        if (m >= 1000.0) {
            return (m / 1000.0).format("%.1f") + " km";
        }
        return m.toNumber().toString() + " m";
    }
}
