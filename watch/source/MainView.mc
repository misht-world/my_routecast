using Toybox.WatchUi;
using Toybox.Graphics;

// Экран статуса сборки (Gate 2 шаг 1): состояние + счётчики + последняя строка лога.
// Рендер линии добавим на шаге «Рендер на часах».
class MainView extends WatchUi.View {

    var r;

    function initialize(receiver) {
        View.initialize();
        r = receiver;
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);

        var cx = dc.getWidth() / 2;
        dc.drawText(cx, 18, Graphics.FONT_SMALL, stateText(), Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, 58, Graphics.FONT_NUMBER_MEDIUM, r.points.size() + "/" + r.np,
            Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, 100, Graphics.FONT_TINY, "man " + r.maneuvers.size() + "/" + r.nm,
            Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, 130, Graphics.FONT_XTINY, r.logLine, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, 156, Graphics.FONT_XTINY, "START = mock", Graphics.TEXT_JUSTIFY_CENTER);
    }

    function stateText() {
        var s = r.state;
        if (s == :idle) { return "IDLE"; }
        if (s == :receiving) { return "RECEIVING"; }
        if (s == :ready) { return "READY"; }
        return "ERROR";
    }
}
