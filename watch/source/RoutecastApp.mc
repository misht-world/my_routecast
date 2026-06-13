using Toybox.Application;
using Toybox.Communications;
using Toybox.WatchUi;

// Точка входа виджета. Регистрирует mailbox-listener и держит RouteReceiver.
class RoutecastApp extends Application.AppBase {

    var receiver;

    function initialize() {
        AppBase.initialize();
        receiver = new RouteReceiver();
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

    function getInitialView() {
        var view = new MainView(receiver);
        return [view, new MainDelegate(receiver)];
    }
}
