using Toybox.Background;
using Toybox.Communications;
using Toybox.System;

(:background)
class RideCoachService extends System.ServiceDelegate {
    function initialize() {
        ServiceDelegate.initialize();
    }

    function onPhoneAppMessage(message as Communications.PhoneAppMessage) as Void {
        // The phone sends a compact dictionary containing cue, target, risk,
        // confidence, and optional learned calibration values.
        Background.exit(message.data);
    }
}
