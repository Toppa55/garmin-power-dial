using Toybox.Background;
using Toybox.Communications;
using Toybox.Application;
using Toybox.Lang;
using Toybox.System;
using Toybox.Time;

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

    function onTemporalEvent() {
        var telemetry = Application.Storage.getValue("rideTelemetry");
        var now = Time.now().value();
        if (!(telemetry instanceof Lang.Dictionary) || !telemetry.hasKey("at") ||
            now - telemetry["at"] > 90 || now < telemetry["at"]) {
            Background.exit(null);
            return;
        }
        var url = Application.Properties.getValue("bridgeUrl");
        var token = Application.Properties.getValue("bridgeToken");
        if (!(url instanceof Lang.String) || url.length() < 9 ||
            url.substring(0, 8) != "https://" ||
            !(token instanceof Lang.String) || token.length() < 16) {
            Background.exit(null);
            return;
        }
        try {
            Communications.makeWebRequest(url, telemetry as Lang.Dictionary, {
                :method => Communications.HTTP_REQUEST_METHOD_POST,
                :headers => {
                    "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON,
                    "Authorization" => "Bearer " + token
                },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            }, method(:onReply));
        } catch (error) {
            Background.exit(null);
        }
    }

    function onReply(code as Lang.Number,
                     data as Lang.Dictionary or Lang.String or Toybox.PersistedContent.Iterator or Null) as Void {
        if (code == 200 && data instanceof Lang.Dictionary) {
            Background.exit(data);
        } else {
            Background.exit(null);
        }
    }
}
