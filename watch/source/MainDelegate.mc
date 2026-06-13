using Toybox.WatchUi;

// START прогоняет мок-последовательность H/L/M/E — проверка сборки в симуляторе без телефона.
class MainDelegate extends WatchUi.BehaviorDelegate {

    var r;

    function initialize(receiver) {
        BehaviorDelegate.initialize();
        r = receiver;
    }

    function onSelect() {
        MockFeeder.feed(r);
        WatchUi.requestUpdate();
        return true;
    }
}
