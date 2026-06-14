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

    function onBack() {
        (Application.getApp() as RoutecastApp).stopNavigation();
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
