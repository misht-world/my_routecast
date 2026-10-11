using Toybox.WatchUi;
using Toybox.Application;

// Стартовый экран. START: на ожидании — показать прошлый маршрут; на обзоре — навигация.
// MENU — тоже прошлый маршрут. BACK: отмена приёма / спрятать обзор / выход.
class MainDelegate extends WatchUi.BehaviorDelegate {

    var r;

    function initialize(receiver) {
        BehaviorDelegate.initialize();
        r = receiver;
    }

    function onSelect() {
        if (r.state == :ready) {
            if (r.savedOnly) { r.savedOnly = false; } // показать прошлый маршрут
            else { (Application.getApp() as RoutecastApp).startNavigation(); }
        } else if (Cfg.DEMO_AUTOLOAD) {
            DemoRoute.feed(r);
        }
        WatchUi.requestUpdate();
        return true;
    }

    function onMenu() {
        if (r.state == :ready && r.savedOnly) {
            r.savedOnly = false; WatchUi.requestUpdate(); return true;
        }
        return false;
    }

    function onBack() {
        if (r.state == :receiving) { r.cancelPending(); WatchUi.requestUpdate(); return true; }
        if (r.state == :ready && !r.savedOnly) {
            r.savedOnly = true; WatchUi.requestUpdate(); return true; // назад к ожиданию
        }
        return false; // выход из приложения
    }
}
