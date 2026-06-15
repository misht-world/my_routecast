using Toybox.Application;
using Toybox.Communications;
using Toybox.Position;
using Toybox.WatchUi;
using Toybox.ActivityRecording;
using Toybox.Activity;

// Точка входа виджета. Регистрирует mailbox-listener, держит RouteReceiver и навигацию.
class RoutecastApp extends Application.AppBase {

    var receiver;
    var navState;
    var session; // ActivityRecording — нужна, чтобы поднять GPS-антенну на железе
    var posEvents; // сколько раз сработал колбэк onPosition (диагностика)

    function initialize() {
        AppBase.initialize();
        receiver = new RouteReceiver();
        navState = null;
        session = null;
        posEvents = 0;
    }

    function onStart(state) {
        Communications.registerForPhoneAppMessages(method(:onPhone));
        if (Cfg.DEMO_AUTOLOAD) { MockFeeder.feed(receiver); } // без телефона — сразу обзор
        // на железе — поднимаем GPS заранее (прогрев), движение берём из реального приёмника
        if (!Cfg.DEMO_MOVE) {
            Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
        }
    }

    function onStop(state) {
        endSession();
    }

    // Старт сессии записи — именно это включает GPS-приёмник для CIQ-аппа.
    // Сессию НЕ сохраняем (discard при выходе) — никаких лишних активностей.
    function startSession() {
        if (session != null || Cfg.DEMO_MOVE) { return; }
        try {
            session = ActivityRecording.createSession({
                :name => "RouteCast",
                :sport => Activity.SPORT_HIKING
            });
            session.start();
        } catch (e) {
            session = null;
        }
    }

    function endSession() {
        if (session != null) {
            try {
                if (session.isRecording()) { session.stop(); }
                session.discard();
            } catch (e) {
            }
            session = null;
        }
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
        startSession(); // поднять GPS-антенну
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

    // Завершение: выключаем GPS, отбрасываем сессию и ОЧИЩАЕМ маршрут -> IDLE.
    function finishNavigation() {
        endSession();
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
        receiver.reset();
        receiver.state = :idle;
        navState = null;
    }

    function onPosition(info as Position.Info) as Void {
        posEvents += 1;
        if (navState != null) {
            navState.gpsAcc = (info.accuracy != null) ? info.accuracy : 0;
            navState.gpsHasPos = (info.position != null);
            if (info.position != null) {
                var d = info.position.toDegrees();
                navState.demo = false; // пришёл реальный GPS — демо больше не нужно
                navState.setFix((d[0] * 1000000).toNumber(), (d[1] * 1000000).toNumber(), info.heading);
            }
        }
        WatchUi.requestUpdate();
    }

    function isRecording() {
        if (session == null) { return false; }
        try { return session.isRecording(); } catch (e) { return false; }
    }

    function getInitialView() {
        var view = new MainView(receiver);
        return [view, new MainDelegate(receiver)];
    }
}
