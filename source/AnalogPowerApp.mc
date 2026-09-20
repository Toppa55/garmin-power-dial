using Toybox.Application;
using Toybox.Background;

(:background)
class AnalogPowerApp extends Application.AppBase {
    hidden var _view;

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        _view = new AnalogPowerView();
        try { Background.registerForPhoneAppMessageEvent(); } catch (error) {}
        return [ _view ];
    }

    function onSettingsChanged() {
        if (_view != null) { _view.loadCalibration(); }
    }

    function onBackgroundData(data) {
        if (_view != null) { _view.receiveCoach(data); }
    }

    function getServiceDelegate() {
        return [ new RideCoachService() ];
    }
}
