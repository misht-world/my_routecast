using Toybox.WatchUi;
using Toybox.Application;

// START: если маршрут не собран — прогнать мок (Gate 2); если READY — старт навигации.
class MainDelegate extends WatchUi.BehaviorDelegate {

    var r;

    function initialize(receiver) {
        BehaviorDelegate.initialize();
        r = receiver;
    }

    function onSelect() {
        if (r.state == :ready) {
            (Application.getApp() as RoutecastApp).startNavigation();
        } else {
            MockFeeder.feed(r);
        }
        WatchUi.requestUpdate();
        return true;
    }
}
