using Toybox.Application;

class AnalogPowerApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        return [ new AnalogPowerView() ];
    }
}
