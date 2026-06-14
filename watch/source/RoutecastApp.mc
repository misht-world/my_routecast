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
        if (Cfg.DEMO_AUTOLOAD) { MockFeeder.feed(receiver); } // без телефона — сразу обзор
    }

    function onStop(state) {
    }

    // Сообщение с телефона: msg.data — Dictionary протокола (см. docs/protocol.md).
    function onPhone(msg as Communications.PhoneAppMessage) as Void {
        receiver.replyEnabled = true; // приём от телефона — шлём ack
        receiver.handle(msg.data);
        WatchUi.requestUpdate();
    }

    // Старт навигации из READY: строим модель, включаем GPS, открываем NavView.
    function startNavigation() {
        if (receiver.state != :ready) { return; }
        navState = new NavState(new RouteModel(receiver.points, receiver.maneuvers));
        navState.demo = Cfg.DEMO_MOVE; // в симуляторе едем сами; реальный GPS перебьёт
        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
        WatchUi.pushView(new NavView(navState), new NavDelegate(navState), WatchUi.SLIDE_LEFT);
    }

    // Пауза/возобновление навигации (подменю BACK).
    function pauseNavigation() {
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
    }

    function resumeNavigation() {
        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
    }

    // Завершение: выключаем GPS и ОЧИЩАЕМ маршрут (минимум следов) -> IDLE.
    function finishNavigation() {
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
        receiver.reset();
        receiver.state = :idle;
        navState = null;
    }

    function onPosition(info as Position.Info) as Void {
        if (navState == null) { return; }
        if (info.position != null) {
            var d = info.position.toDegrees();
            var hdg = info.heading;
            navState.demo = false; // пришёл реальный GPS — демо больше не нужно
            navState.setFix((d[0] * 1000000).toNumber(), (d[1] * 1000000).toNumber(), hdg);
            WatchUi.requestUpdate();
        }
    }

    function getInitialView() {
        var view = new MainView(receiver);
        return [view, new MainDelegate(receiver)];
    }
}
