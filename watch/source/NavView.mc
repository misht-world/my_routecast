using Toybox.WatchUi;
using Toybox.Graphics;
using Toybox.Math;
using Toybox.Attention;
using Toybox.System;
using Toybox.Timer;
using Toybox.Position;
using Toybox.Application;
using Toybox.Sensor;

// Отрисовка навигации heading-up (SPEC §5.4–5.5), монохром, один тон.
class NavView extends WatchUi.View {

    const LOOKAHEAD = 40.0;
    const ARRIVE_M = 8.0;
    const TURN_NOW_M = 8.0;  // вибро В МОМЕНТ поворота (в пределах стольки метров до вершины)
    const OFFROUTE_M = 15.0;
    const OFFROUTE_T_MS = 5000; // выдержка off-route, мс
    const DEMO_STEP = 5.0;  // м за тик демо
    const MOVING_SPD = 1.0; // м/с — выше этого считаем «в движении» -> курс из GPS, не компас
    const HEAD_SMOOTH = 0.2; // сглаживание курса (0..1): меньше — плавнее, но ленивее
    const CULL_MULT = 1.6;  // рисуем только точки в пределах viewMeters*CULL_MULT от позиции

    var ns;
    var timer;

    function initialize(navState) {
        View.initialize();
        ns = navState;
    }

    function onShow() {
        timer = new Timer.Timer();
        timer.start(method(:onTick), 200, true);
    }

    function onHide() {
        if (timer != null) { timer.stop(); }
    }

    // Демо-движение, либо опрос реального GPS (надёжнее, чем только колбэк событий).
    function onTick() as Void {
        if (ns.demo) {
            if (!ns.paused && !ns.arrived) {
                ns.demoDist += DEMO_STEP;
                var p = ns.route.pointAtDist(ns.demoDist);
                var hdg = ns.route.headingAtDist(ns.demoDist);
                ns.setFix(p[0], p[1], hdg);
                WatchUi.requestUpdate();
            }
            return;
        }
        var app = Application.getApp() as RoutecastApp;
        ns.rec = app.isRecording();
        ns.events = app.posEvents;

        var info = Position.getInfo();
        if (info != null) {
            ns.gpsAcc = (info.accuracy != null) ? info.accuracy : 0;
            ns.gpsHasPos = (info.position != null);
            // Курс. В движении — course-over-ground из GPS (истинный, не зависит от наклона руки);
            // заодно копим поправку bias = GPS−компас. Стоя — компас+bias: живое вращение
            // от компаса, но абсолютный «север» подтянут к GPS (компас на этом корпусе абс. врёт).
            var spd = (info.speed != null) ? info.speed : 0.0;
            var sInfo = Sensor.getInfo();
            var ch = (sInfo != null) ? sInfo.heading : null;
            var target = null;
            if (spd >= MOVING_SPD && info.heading != null) {
                target = info.heading;
                if (ch != null) {
                    var d = normRad(info.heading - ch);
                    ns.headingBias = ns.headingBias + 0.25 * normRad(d - ns.headingBias);
                }
            } else if (ch != null) {
                target = ch + ns.headingBias;
            }
            // Сглаживаем курс по кратчайшей дуге — гасим дрожь GPS/компаса (карта не качается).
            if (target != null) {
                if (ns.headingRad == null) {
                    ns.headingRad = target;
                } else {
                    ns.headingRad = ns.headingRad + HEAD_SMOOTH * normRad(target - ns.headingRad);
                }
            }
            if (info.position != null && ns.gpsAcc >= 2) { // POOR и лучше
                var d2 = info.position.toDegrees();
                ns.setFix((d2[0] * 1000000).toNumber(), (d2[1] * 1000000).toNumber(), null);
            }
        }
        WatchUi.requestUpdate();
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
        // оконный поиск ближайшего сегмента — не «прилипаем» к возвратной ветке у старта
        var near = route.nearestWindowed(ns.meLatMicro, ns.meLonMicro,
            ns.lastTraveled - 30.0, ns.lastTraveled + 60.0);
        var segIdx = near[0];
        var crossM = near[2];
        var trav = near[3];
        ns.lastTraveled = trav;
        var rem = route.totalM() - trav;
        if (rem < 0.0) { rem = 0.0; }

        if (!ns.arrived && route.totalM() > ARRIVE_M && rem <= ARRIVE_M) {
            ns.arrived = true;
        }
        if (ns.arrived) {
            drawArrival(dc, cx, H);
            return;
        }

        // off-route с выдержкой по времени (OFFROUTE_T) — гасим шумовые срабатывания
        var rawOff = crossM > OFFROUTE_M;
        if (rawOff) {
            if (ns.offSince == 0) { ns.offSince = System.getTimer(); }
        } else {
            ns.offSince = 0;
        }
        var offRoute = rawOff && (System.getTimer() - ns.offSince) >= OFFROUTE_T_MS;
        if (offRoute) {
            if (!ns.offBuzzed) { ns.offBuzzed = true; if (ns.signalsOn) { vibeOnce(); } }
        } else {
            ns.offBuzzed = false;
        }

        var h = ns.effHeading();
        var sinH = Math.sin(h);
        var cosH = Math.cos(h);
        var meXY = route.toXY(ns.meLatMicro, ns.meLonMicro);
        var pxPerM = meY.toFloat() / ns.viewMeters();

        var pp = route.pointAtDist(trav);
        var ppS = projectPt(pp, meXY, sinH, cosH, pxPerM, cx, meY);

        // Рисуем ТОЛЬКО точки в окне вокруг позиции (остальные всё равно за экраном).
        // Это ограничивает работу/аллокации на кадр вне зависимости от длины маршрута.
        var cull = ns.viewMeters() * CULL_MULT;
        var n = route.size();

        // пройденное — тонкое
        dc.setPenWidth(1);
        var pHave = false;
        var pX = 0.0;
        var pY = 0.0;
        for (var i = 0; i <= segIdx; i++) {
            if (route.cum[i] < trav - cull) { continue; } // далеко позади — пропускаем
            var s = projectPt(route.pts[i], meXY, sinH, cosH, pxPerM, cx, meY);
            if (pHave) { dc.drawLine(pX, pY, s[0], s[1]); }
            pX = s[0]; pY = s[1]; pHave = true;
        }
        if (pHave) { dc.drawLine(pX, pY, ppS[0], ppS[1]); }

        // оставшееся — толстое (тусклее при off-route)
        dc.setPenWidth(offRoute ? 2 : 4);
        var rX = ppS[0];
        var rY = ppS[1];
        for (var j = segIdx + 1; j < n; j++) {
            if (route.cum[j] > trav + cull) { break; } // дальше окна впереди — стоп
            var s2 = projectPt(route.pts[j], meXY, sinH, cosH, pxPerM, cx, meY);
            dc.drawLine(rX, rY, s2[0], s2[1]);
            rX = s2[0]; rY = s2[1];
        }

        // финиш-кольцо — только если конец близко (иначе за экраном)
        if (route.cum[n - 1] <= trav + cull) {
            var fp = projectPt(route.pts[n - 1], meXY, sinH, cosH, pxPerM, cx, meY);
            dc.setPenWidth(2);
            dc.drawCircle(fp[0], fp[1], 6);
        }

        // «я»
        dc.fillPolygon([[cx, meY - 11], [cx - 8, meY + 9], [cx + 8, meY + 9]]);
        if (ns.paused) {
            dc.drawText(cx, 2, Graphics.FONT_XTINY, "PAUSE", Graphics.TEXT_JUSTIFY_CENTER);
        }

        // следующий манёвр: вибро В МОМЕНТ поворота (не заранее), один раз на манёвр.
        var nm = route.nextManeuver(trav);
        var manDist = (nm != null) ? route.maneuverDistM(nm) : 1.0e9;
        var dTo = manDist - trav;
        if (dTo < 0.0) { dTo = 0.0; }
        var isFinish = (nm != null) && (nm[1] == 9);
        var manIdx = (nm != null) ? nm[0] : -1;

        if (ns.signalsOn && !offRoute && !isFinish && nm != null
                && dTo <= TURN_NOW_M && ns.nowIdx != manIdx) {
            ns.nowIdx = manIdx;
            vibeOnce();
        }

        // нижнее поле NNN/YY
        dc.drawText(cx, H - 34, Graphics.FONT_MEDIUM,
            fmtDist(dTo) + "/" + (rem / 1000.0).format("%.1f"),
            Graphics.TEXT_JUSTIFY_CENTER);

        // Субэкран: всегда пеленг направления (глиф поворота убран — не мешает при ходьбе).
        if (offRoute) {
            drawNeedle(dc, route, meXY, sinH, cosH, pxPerM, cx, meY, trav);
            dc.drawText(cx, H - 58, Graphics.FONT_TINY, "OFF ROUTE", Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            drawNeedle(dc, route, meXY, sinH, cosH, pxPerM, cx, meY, trav + LOOKAHEAD);
        }
    }

    function drawArrival(dc, cx, H) {
        if (!ns.vibedArrival) {
            ns.vibedArrival = true;
            if (ns.signalsOn) { vibeOnce(); }
        }
        dc.drawText(cx, H / 2 - 14, Graphics.FONT_MEDIUM, "Arrived", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, H / 2 + 16, Graphics.FONT_TINY, "BACK to exit", Graphics.TEXT_JUSTIFY_CENTER);
    }

    function projectPt(pt, meXY, sinH, cosH, pxPerM, cx, meY) {
        var q = ns.route.toXY(pt[0], pt[1]);
        var ex = q[0] - meXY[0];
        var ny = q[1] - meXY[1];
        var along = ex * sinH + ny * cosH;
        var cross = ex * cosH - ny * sinH;
        return [cx + cross * pxPerM, meY - along * pxPerM];
    }

    // субэкран: маска карты (рамка физическая) + игла-пеленг в виде компасной стрелки (ромб)
    function drawNeedle(dc, route, meXY, sinH, cosH, pxPerM, cx, meY, atDist) {
        var scx = 144;
        var scy = 31;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillCircle(scx, scy, 31);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);

        var tgt = route.pointAtDist(atDist);
        var ts = projectPt(tgt, meXY, sinH, cosH, pxPerM, cx, meY);
        var ang = Math.atan2(ts[1] - meY, ts[0] - cx);
        drawNavArrow(dc, scx, scy, ang, 17);
    }

    // Стрелка навигации в стиле Garmin: остриё по angle + срезанный (V) низ.
    // Концав делаем чёрной «выемкой» поверх белого треугольника (fillPolygon не любит вогнутость).
    function drawNavArrow(dc, cx, cy, angle, size) {
        var ca = Math.cos(angle);
        var sa = Math.sin(angle);
        var px = -sa;
        var py = ca;
        var tipX = cx + ca * size;
        var tipY = cy + sa * size;
        var bcx = cx - ca * size * 0.55;
        var bcy = cy - sa * size * 0.55;
        var hw = size * 0.66;
        var blX = bcx + px * hw; var blY = bcy + py * hw;
        var brX = bcx - px * hw; var brY = bcy - py * hw;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[tipX, tipY], [blX, blY], [brX, brY]]);
        // выемка снизу
        var nX = bcx + ca * size * 0.5;
        var nY = bcy + sa * size * 0.5;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillPolygon([[nX, nY], [blX, blY], [brX, brY]]);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
    }

    // Нормировка угла (рад) в [−π, π] — для корректной разности курсов.
    function normRad(a) {
        var x = a;
        while (x > Math.PI) { x -= 2.0 * Math.PI; }
        while (x < -Math.PI) { x += 2.0 * Math.PI; }
        return x;
    }

    function fmtDist(m) {
        if (m >= 500.0) {
            return (m / 1000.0).format("%.1f");
        }
        return m.toNumber().toString();
    }

    // Одна короткая вибрация — все оповещения (экономия батареи).
    function vibeOnce() {
        if (Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(50, 200)]);
        }
    }
}
