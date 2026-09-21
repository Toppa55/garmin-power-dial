using Toybox.Application;
using Toybox.Background;
using Toybox.Time;

(:background)
class AnalogPowerApp extends Application.AppBase {
    hidden var _view;

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        _view = new AnalogPowerView();
        try { Background.registerForPhoneAppMessageEvent(); } catch (error) {}
        configureBridge();
        return [ _view ];
    }

    function onSettingsChanged() {
        if (_view != null) { _view.loadCalibration(); }
        configureBridge();
    }

    function configureBridge() {
        var url = Application.Properties.getValue("bridgeUrl");
        var token = Application.Properties.getValue("bridgeToken");
        try {
            if (url != null && token != null && url.length() > 8 &&
                url.substring(0, 8) == "https://" && token.length() > 15) {
                Background.registerForTemporalEvent(new Time.Duration(300));
            } else {
                Background.deleteTemporalEvent();
            }
        } catch (error) {}
    }

    function onBackgroundData(data) {
        if (_view != null) { _view.receiveCoach(data); }
    }

    function getServiceDelegate() {
        return [ new RideCoachService() ];
    }
}
