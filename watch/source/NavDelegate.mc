using Toybox.WatchUi;
using Toybox.Application;

// Управление в навигации: UP/DOWN — зум, BACK — выход (SPEC §5.1).
class NavDelegate extends WatchUi.BehaviorDelegate {

    var ns;

    function initialize(navState) {
        BehaviorDelegate.initialize();
        ns = navState;
    }

    // UP — ближе (детальнее)
    function onPreviousPage() {
        if (ns.zoom < 2) { ns.zoom++; }
        WatchUi.requestUpdate();
        return true;
    }

    // DOWN — дальше (обзорнее)
    function onNextPage() {
        if (ns.zoom > 0) { ns.zoom--; }
        WatchUi.requestUpdate();
        return true;
    }

    // MENU — пауза/продолжение демо-движения (тест без GPS-плеера)
    function onMenu() {
        toggleDemo();
        return true;
    }

    function toggleDemo() {
        ns.demo = !ns.demo;
        if (ns.demo) {
            ns.demoDist = 0.0;
            ns.arrived = false;
            ns.vibedArrival = false;
            ns.warnIdx = -1;
            ns.nowIdx = -1;
        }
        WatchUi.requestUpdate();
    }

    function onBack() {
        // На экране «Прибытие» — сразу выход с очисткой.
        if (ns.arrived) {
            (Application.getApp() as RoutecastApp).finishNavigation();
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
            return true;
        }
        // Иначе — подменю «Пауза/Продолжить» + «Завершить».
        var menu = new WatchUi.Menu2({ :title => "Navigation" });
        menu.addItem(new WatchUi.MenuItem(ns.paused ? "Resume" : "Pause", null, :pause, null));
        menu.addItem(new WatchUi.MenuItem("Signals", ns.signalsOn ? "On" : "Off", :signals, null));
        menu.addItem(new WatchUi.MenuItem("Finish", null, :finish, null));
        WatchUi.pushView(menu, new NavMenuDelegate(ns), WatchUi.SLIDE_UP);
        return true;
    }
}
