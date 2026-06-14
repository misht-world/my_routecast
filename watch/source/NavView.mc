using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Math;
using Toybox.Attention;

// Отрисовка маршрута heading-up (SPEC §5.4): линия + «я» (ниже центра) + финиш-кольцо +
// нижнее поле NNN/YY + субэкран-пеленг. Плюс экран «Прибытие». Один тон (монохром).
class NavView extends WatchUi.View {

    const LOOKAHEAD = 40.0;
    const ARRIVE_M = 20.0;

    var ns;

    function initialize(navState) {
        View.initialize();
        ns = navState;
    }

    function onUpdate(dc) {
        var W = dc.getWidth();
        var H = dc.getHeight();
        var cx = W / 2;
        var meY = (H * 0.62).toNumber();

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);

        var route = ns.route;

        // следование: ближайший сегмент -> traveled -> остаток
        var near = route.nearest(ns.meLatMicro, ns.meLonMicro);
        var trav = near[3];
        var rem = route.totalM() - trav;
        if (rem < 0.0) { rem = 0.0; }

        // прибытие
        if (!ns.arrived && route.totalM() > ARRIVE_M && rem <= ARRIVE_M) {
            ns.arrived = true;
        }
        if (ns.arrived) {
            drawArrival(dc, cx, H);
            return;
        }

        var h = ns.effHeading();
        var sinH = Math.sin(h);
        var cosH = Math.cos(h);
        var meXY = route.toXY(ns.meLatMicro, ns.meLonMicro);
        var pxPerM = meY.toFloat() / ns.viewMeters();

        // полилиния маршрута
        dc.setPenWidth(3);
        var n = route.size();
        var havePrev = false;
        var prevX = 0.0;
        var prevY = 0.0;
        for (var i = 0; i < n; i++) {
            var s = projectPt(route.pts[i], meXY, sinH, cosH, pxPerM, cx, meY);
            if (havePrev) {
                dc.drawLine(prevX, prevY, s[0], s[1]);
            }
            prevX = s[0];
            prevY = s[1];
            havePrev = true;
        }

        // финиш-кольцо
        var fp = projectPt(route.pts[n - 1], meXY, sinH, cosH, pxPerM, cx, meY);
        dc.setPenWidth(2);
        dc.drawCircle(fp[0], fp[1], 6);

        // «я» — выпуклый треугольник курса (смотрит вверх)
        dc.fillPolygon([[cx, meY - 11], [cx - 8, meY + 9], [cx + 8, meY + 9]]);

        if (ns.paused) {
            dc.drawText(cx, 2, Graphics.FONT_XTINY, "ПАУЗА", Graphics.TEXT_JUSTIFY_CENTER);
        }

        // нижнее поле NNN/YY
        var nm = route.nextManeuver(trav);
        var dM = (nm != null) ? (nm[2] - trav) : 0.0;
        if (dM < 0.0) { dM = 0.0; }
        dc.drawText(cx, H - 30, Graphics.FONT_MEDIUM,
            fmtDist(dM) + "/" + (rem / 1000.0).format("%.1f"),
            Graphics.TEXT_JUSTIFY_CENTER);

        drawSubBearing(dc, route, meXY, sinH, cosH, pxPerM, cx, meY, trav);
    }

    function drawArrival(dc, cx, H) {
        if (!ns.vibedArrival) {
            ns.vibedArrival = true;
            if (Attention has :vibrate) {
                Attention.vibrate([new Attention.VibeProfile(75, 400)]);
            }
        }
        dc.drawText(cx, H / 2 - 14, Graphics.FONT_MEDIUM, "Прибытие", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, H / 2 + 16, Graphics.FONT_TINY, "BACK — выход", Graphics.TEXT_JUSTIFY_CENTER);
    }

    // проекция [latMicro,lonMicro] в экран (heading-up: вперёд = вверх, право = вправо)
    function projectPt(pt, meXY, sinH, cosH, pxPerM, cx, meY) {
        var q = ns.route.toXY(pt[0], pt[1]);
        var ex = q[0] - meXY[0];
        var ny = q[1] - meXY[1];
        var along = ex * sinH + ny * cosH;
        var cross = ex * cosH - ny * sinH;
        return [cx + cross * pxPerM, meY - along * pxPerM];
    }

    function drawSubBearing(dc, route, meXY, sinH, cosH, pxPerM, cx, meY, trav) {
        var scx = 144;
        var scy = 31;
        var sr = 27;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillCircle(scx, scy, sr + 4);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawCircle(scx, scy, sr);

        var tgt = route.pointAtDist(trav + LOOKAHEAD);
        var ts = projectPt(tgt, meXY, sinH, cosH, pxPerM, cx, meY);
        var ang = Math.atan2(ts[1] - meY, ts[0] - cx);
        var ca = Math.cos(ang);
        var sa = Math.sin(ang);

        // древко
        var len = 17;
        var tipX = scx + ca * len;
        var tipY = scy + sa * len;
        dc.setPenWidth(3);
        dc.drawLine(scx - ca * len, scy - sa * len, tipX, tipY);
        // наконечник-треугольник
        var px = -sa; // перпендикуляр
        var py = ca;
        var hl = 9;   // длина наконечника
        var hw = 6;   // полуширина
        var bx = tipX - ca * hl;
        var by = tipY - sa * hl;
        dc.fillPolygon([
            [tipX, tipY],
            [bx + px * hw, by + py * hw],
            [bx - px * hw, by - py * hw]
        ]);
    }

    function fmtDist(m) {
        if (m >= 500.0) {
            return (m / 1000.0).format("%.1f");
        }
        return m.toNumber().toString();
    }
}
