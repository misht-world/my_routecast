using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Math;
using Toybox.Attention;
using Toybox.System;

// Отрисовка навигации heading-up (SPEC §5.4–5.5), монохром, один тон.
class NavView extends WatchUi.View {

    const LOOKAHEAD = 40.0;
    const ARRIVE_M = 20.0;
    const TURN_WARN_M = 50.0;
    const TURN_NOW_M = 10.0;
    const OFFROUTE_M = 40.0;
    const WARN_HOLD = 2000; // мс

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
        var near = route.nearest(ns.meLatMicro, ns.meLonMicro);
        var segIdx = near[0];
        var crossM = near[2];
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

        var offRoute = crossM > OFFROUTE_M;
        if (offRoute) {
            if (!ns.offBuzzed) { ns.offBuzzed = true; vibeOnce(); }
        } else {
            ns.offBuzzed = false;
        }

        var h = ns.effHeading();
        var sinH = Math.sin(h);
        var cosH = Math.cos(h);
        var meXY = route.toXY(ns.meLatMicro, ns.meLonMicro);
        var pxPerM = meY.toFloat() / ns.viewMeters();

        // точка-проекция «я» на маршрут (граница пройдено/осталось)
        var pp = route.pointAtDist(trav);

        var ppS = projectPt(pp, meXY, sinH, cosH, pxPerM, cx, meY);

        // пройденное — тонкое
        dc.setPenWidth(1);
        var pHave = false;
        var pX = 0.0;
        var pY = 0.0;
        for (var i = 0; i <= segIdx; i++) {
            var s = projectPt(route.pts[i], meXY, sinH, cosH, pxPerM, cx, meY);
            if (pHave) { dc.drawLine(pX, pY, s[0], s[1]); }
            pX = s[0]; pY = s[1]; pHave = true;
        }
        if (pHave) { dc.drawLine(pX, pY, ppS[0], ppS[1]); }

        // оставшееся — толстое (тусклее при off-route)
        dc.setPenWidth(offRoute ? 2 : 4);
        var rX = ppS[0];
        var rY = ppS[1];
        var n = route.size();
        for (var j = segIdx + 1; j < n; j++) {
            var s2 = projectPt(route.pts[j], meXY, sinH, cosH, pxPerM, cx, meY);
            dc.drawLine(rX, rY, s2[0], s2[1]);
            rX = s2[0]; rY = s2[1];
        }

        // финиш-кольцо
        var fp = projectPt(route.pts[n - 1], meXY, sinH, cosH, pxPerM, cx, meY);
        dc.setPenWidth(2);
        dc.drawCircle(fp[0], fp[1], 6);

        // «я»
        dc.fillPolygon([[cx, meY - 11], [cx - 8, meY + 9], [cx + 8, meY + 9]]);
        if (ns.paused) {
            dc.drawText(cx, 2, Graphics.FONT_XTINY, "ПАУЗА", Graphics.TEXT_JUSTIFY_CENTER);
        }

        // следующий манёвр + вибро-логика
        var nm = route.nextManeuver(trav);
        var dTo = (nm != null) ? (nm[2] - trav) : 1.0e9;
        if (dTo < 0.0) { dTo = 0.0; }
        var isFinish = (nm != null) && (nm[1] == 9);
        var manIdx = (nm != null) ? nm[0] : -1;

        if (!offRoute && nm != null && dTo <= TURN_WARN_M) {
            if (ns.warnIdx != manIdx) {
                ns.warnIdx = manIdx;
                ns.warnStart = System.getTimer();
                vibeOnce(); // анонс
            }
        }
        if (!offRoute && !isFinish && nm != null && dTo <= TURN_NOW_M && ns.nowIdx != manIdx) {
            ns.nowIdx = manIdx;
            vibeNow(); // двойное на самом повороте
        }

        // нижнее поле NNN/YY
        dc.drawText(cx, H - 30, Graphics.FONT_MEDIUM,
            fmtDist(dTo) + "/" + (rem / 1000.0).format("%.1f"),
            Graphics.TEXT_JUSTIFY_CENTER);

        // субэкран-пеленг (без рамки): off-route -> на ближайшую точку маршрута
        var bearingTrav = offRoute ? trav : (trav + LOOKAHEAD);
        drawSubBearing(dc, route, meXY, sinH, cosH, pxPerM, cx, meY, bearingTrav, offRoute);

        // оверлеи
        if (offRoute) {
            dc.drawText(cx, 16, Graphics.FONT_SMALL, "OFF ROUTE", Graphics.TEXT_JUSTIFY_CENTER);
        } else if (nm != null) {
            var lowBound = isFinish ? ARRIVE_M : TURN_NOW_M;
            var holding = (ns.warnIdx == manIdx) && ((System.getTimer() - ns.warnStart) < WARN_HOLD);
            if (holding && dTo > lowBound) {
                drawTurnWarning(dc, cx, W, H, isFinish, route.bendRadAt(manIdx));
            }
        }
    }

    function drawArrival(dc, cx, H) {
        if (!ns.vibedArrival) {
            ns.vibedArrival = true;
            vibeOnce();
        }
        dc.drawText(cx, H / 2 - 14, Graphics.FONT_MEDIUM, "Прибытие", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, H / 2 + 16, Graphics.FONT_TINY, "BACK — выход", Graphics.TEXT_JUSTIFY_CENTER);
    }

    function projectPt(pt, meXY, sinH, cosH, pxPerM, cx, meY) {
        var q = ns.route.toXY(pt[0], pt[1]);
        var ex = q[0] - meXY[0];
        var ny = q[1] - meXY[1];
        var along = ex * sinH + ny * cosH;
        var cross = ex * cosH - ny * sinH;
        return [cx + cross * pxPerM, meY - along * pxPerM];
    }

    // субэкран: маска карты (без рамки — она физическая) + стрелка-пеленг
    function drawSubBearing(dc, route, meXY, sinH, cosH, pxPerM, cx, meY, atDist, off) {
        var scx = 144;
        var scy = 31;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillCircle(scx, scy, 31);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);

        var tgt = route.pointAtDist(atDist);
        var ts = projectPt(tgt, meXY, sinH, cosH, pxPerM, cx, meY);
        var ang = Math.atan2(ts[1] - meY, ts[0] - cx);
        var ca = Math.cos(ang);
        var sa = Math.sin(ang);
        var len = 17;
        var tipX = scx + ca * len;
        var tipY = scy + sa * len;
        dc.setPenWidth(3);
        dc.drawLine(scx - ca * len, scy - sa * len, tipX, tipY);
        var px = -sa;
        var py = ca;
        var hl = 9;
        var hw = 6;
        var bx = tipX - ca * hl;
        var by = tipY - sa * hl;
        dc.fillPolygon([[tipX, tipY], [bx + px * hw, by + py * hw], [bx - px * hw, by - py * hw]]);
    }

    // полноэкранный анонс поворота/финиша (статичный, без метража — SPEC §5.4)
    function drawTurnWarning(dc, cx, W, H, isFinish, bendRad) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillRectangle(0, 0, W, H);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var cy = (H * 0.5).toNumber();
        if (isFinish) {
            dc.drawText(cx, cy - 58, Graphics.FONT_SMALL, "финиш", Graphics.TEXT_JUSTIFY_CENTER);
            dc.setPenWidth(5);
            dc.drawCircle(cx, cy + 6, 22);
            dc.fillCircle(cx, cy + 6, 8);
        } else {
            dc.drawText(cx, cy - 64, Graphics.FONT_SMALL, turnWord(bendRad), Graphics.TEXT_JUSTIFY_CENTER);
            drawTurnArrow(dc, cx, cy + 6, bendRad, 1.5);
        }
    }

    function drawTurnArrow(dc, cx, cy, bendRad, scale) {
        var armAngle = -Math.PI / 2 - bendRad; // + влево / − вправо, экран y вниз
        var sh = (26 * scale).toNumber();
        var arm = 30 * scale;
        var ex = cx + Math.cos(armAngle) * arm;
        var ey = cy + Math.sin(armAngle) * arm;
        dc.setPenWidth((6 * scale).toNumber());
        dc.drawLine(cx, cy + sh, cx, cy);
        dc.drawLine(cx, cy, ex, ey);
        var ca = Math.cos(armAngle);
        var sa = Math.sin(armAngle);
        var hl = 11 * scale;
        var hw = 8 * scale;
        var bx = ex - ca * hl;
        var by = ey - sa * hl;
        var px = -sa;
        var py = ca;
        dc.fillPolygon([[ex, ey], [bx + px * hw, by + py * hw], [bx - px * hw, by - py * hw]]);
    }

    function turnWord(bendRad) {
        var deg = bendRad * 180.0 / Math.PI;
        var a = deg < 0 ? -deg : deg;
        var side = (bendRad > 0) ? "влево" : "вправо";
        if (a < 70.0) { return "плавно " + side; }
        if (a < 120.0) { return side; }
        return "резко " + side;
    }

    function fmtDist(m) {
        if (m >= 500.0) {
            return (m / 1000.0).format("%.1f");
        }
        return m.toNumber().toString();
    }

    function vibeOnce() {
        if (Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(60, 250)]);
        }
    }

    function vibeNow() {
        if (Attention has :vibrate) {
            Attention.vibrate([
                new Attention.VibeProfile(75, 180),
                new Attention.VibeProfile(0, 100),
                new Attention.VibeProfile(75, 180)
            ]);
        }
    }
}
