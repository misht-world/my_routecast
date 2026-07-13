using Toybox.WatchUi;
using Toybox.Application;

// Подменю навигации: «Пауза/Продолжить» и «Завершить» (SPEC §5.1).
class NavMenuDelegate extends WatchUi.Menu2InputDelegate {

    var ns;

    function initialize(navState) {
        Menu2InputDelegate.initialize();
        ns = navState;
    }

    function onSelect(item) {
        var app = Application.getApp() as RoutecastApp;
        var id = item.getId();
        if (id == :finish) {
            app.finishNavigation();
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE); // закрыть меню
            WatchUi.popView(WatchUi.SLIDE_RIGHT);     // закрыть навигацию -> IDLE
        } else if (id == :signals) {
            ns.signalsOn = !ns.signalsOn;
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE); // вернуться к навигации
        } else {
            if (ns.paused) {
                ns.paused = false;
                app.resumeNavigation();
            } else {
                ns.paused = true;
                app.pauseNavigation();
            }
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE); // вернуться к навигации
        }
    }

    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
    }
}
