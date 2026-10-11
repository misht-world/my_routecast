using Toybox.Application;
using Toybox.Communications;
using Toybox.Position;
using Toybox.WatchUi;
using Toybox.ActivityRecording;
using Toybox.Activity;
using Toybox.Time;

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
        receiver.store = new RouteStore();
        receiver.restore();
        Communications.registerForPhoneAppMessages(method(:onPhone));
        if (Cfg.DEMO_AUTOLOAD) { DemoRoute.feed(receiver); }
        // на железе — поднимаем GPS заранее (прогрев), движение берём из реального приёмника
        if (!Cfg.DEMO_MOVE) {
            Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
            startSession(); // антенну реально греет сессия — стартуем с открытия аппа, не ждём маршрута
        }
    }

    function onStop(state) {
        saveNavPrefs();
        endSession();
    }

    // Поправка компаса и выбор «Compass» живут между запусками: в начале маршрута вид
    // не опирается на «сырой» компас этих часов.
    function loadNavPrefs(ns) {
        try {
            var b = Application.Storage.getValue("headingBias");
            if (b instanceof Toybox.Lang.Float || b instanceof Toybox.Lang.Double) {
                ns.headingBias = ns.normRad(b.toFloat());
            }
            var c = Application.Storage.getValue("useCompass");
            if (c instanceof Toybox.Lang.Boolean) { ns.useCompass = c; }
        } catch (e) {
        }
    }

    function saveNavPrefs() {
        if (navState == null) { return; }
        try {
            Application.Storage.setValue("useCompass", navState.useCompass);
            if (navState.biasLearned) {
                Application.Storage.setValue("headingBias", navState.headingBias.toFloat());
            }
        } catch (e) {
        }
    }

    // Старт сессии записи — именно это включает GPS-приёмник для CIQ-аппа.
    // Сессию НЕ сохраняем (discard при выходе) — никаких лишних активностей.
    function startSession() {
        if (session != null || Cfg.DEMO_MOVE || !Cfg.USE_SESSION) { return; }
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
        var d = msg.data;
        if (navState != null && d instanceof Toybox.Lang.Dictionary && d["t"] != null &&
            d["t"].equals("H") && RouteData.validId(d["id"])) {
            receiver.reply("N", d["id"], -1, "busy"); return;
        }
        receiver.handle(msg.data);
        WatchUi.requestUpdate();
    }

    // Старт навигации из READY: строим модель, включаем GPS, открываем NavView.
    function startNavigation() {
        if (receiver.state != :ready) { return; }
        navState = new NavState(new RouteModel(receiver.points, receiver.maneuvers));
        navState.demo = Cfg.DEMO_MOVE; // в симуляторе едем сами; реальный GPS перебьёт
        loadNavPrefs(navState);
        startSession(); // поднять GPS-антенну (enableLocationEvents уже сделан в onStart — НЕ повторяем)
        WatchUi.pushView(new NavView(navState), new NavDelegate(navState), WatchUi.SLIDE_LEFT);
    }

    // Пауза/возобновление — только UI-флаг (ns.paused). GPS НЕ трогаем
    // (повторный enable/disable ломает доставку колбэка — см. forum).
    function pauseNavigation() {
        if (navState != null) { navState.offSince = 0; navState.offBuzzed = false; }
    }

    function resumeNavigation() {
        if (navState != null) { navState.offSince = 0; navState.offBuzzed = false; }
    }

    // Завершение: отбрасываем сессию и ОЧИЩАЕМ маршрут -> IDLE.
    // Регистрацию позиции НЕ снимаем (она одна, на весь жизненный цикл аппа).
    function finishNavigation() {
        saveNavPrefs();
        endSession();
        receiver.reset();
        receiver.savedOnly = true; // после завершения — экран ожидания; прошлый маршрут по START
        navState = null;
    }

    function onPosition(info as Position.Info) as Void {
        posEvents += 1;
        updatePosition(info);
        WatchUi.requestUpdate();
    }

    function updatePosition(info) {
        if (navState != null) {
            if (info == null) { navState.hasFix = false; return; }
            navState.gpsAcc = (info.accuracy != null) ? info.accuracy : 0;
            navState.gpsHasPos = (info.position != null);
            if (info.position != null) {
                var d = info.position.toDegrees();
                navState.acceptFix((d[0] * 1000000).toNumber(), (d[1] * 1000000).toNumber(),
                    navState.gpsAcc, info.when == null ? null : info.when.value(), Time.now().value());
                // курс ставит NavView из Sensor (компас стоя / GPS в движении)
            } else { navState.hasFix = false; }
        }
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
