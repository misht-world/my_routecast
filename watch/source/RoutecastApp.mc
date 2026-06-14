using Toybox.Application;
using Toybox.Communications;
using Toybox.Position;
using Toybox.WatchUi;

// Точка входа виджета. Регистрирует mailbox-listener, держит RouteReceiver и навигацию.
class RoutecastApp extends Application.AppBase {

    var receiver;
    var navState;

    function initialize() {
        AppBase.initialize();
        receiver = new RouteReceiver();
        navState = null;
    }

    function onStart(state) {
        Communications.registerForPhoneAppMessages(method(:onPhone));
    }

    function onStop(state) {
    }

    // Сообщение с телефона: msg.data — Dictionary протокола (см. docs/protocol.md).
    function onPhone(msg as Communications.PhoneAppMessage) as Void {
        receiver.handle(msg.data);
        WatchUi.requestUpdate();
    }

    // Старт навигации из READY: строим модель, включаем GPS, открываем NavView.
    function startNavigation() {
        if (receiver.state != :ready) { return; }
        navState = new NavState(new RouteModel(receiver.points, receiver.maneuvers));
        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
        WatchUi.pushView(new NavView(navState), new NavDelegate(navState), WatchUi.SLIDE_LEFT);
    }

    function onPosition(info as Position.Info) as Void {
        if (navState == null) { return; }
        if (info.position != null) {
            var d = info.position.toDegrees();
            var hdg = info.heading;
            navState.setFix((d[0] * 1000000).toNumber(), (d[1] * 1000000).toNumber(), hdg);
            WatchUi.requestUpdate();
        }
    }

    function getInitialView() {
        var view = new MainView(receiver);
        return [view, new MainDelegate(receiver)];
    }
}
