using Toybox.Graphics;
using Toybox.Math;
using Toybox.WatchUi;

class AnalogPowerView extends WatchUi.DataField {
    // Easy to change later if you want a different scale.
    const MAX_POWER = 800;
    const START_ANGLE = 210.0;
    const SWEEP_ANGLE = 240.0;

    hidden var _power;
    hidden var _needlePower;
    hidden var _hasPower;

    function initialize() {
        DataField.initialize();
        _power = 0;
        _needlePower = 0.0;
        _hasPower = false;
    }

    // Garmin supplies Activity.Info to a Data Field once per second.
    function compute(info) {
        if (info.currentPower != null) {
            _power = info.currentPower;

            // A little damping makes the dial feel mechanical instead of twitchy.
            if (!_hasPower) {
                _needlePower = _power;
            } else {
                _needlePower = (_needlePower * 0.58) + (_power * 0.42);
            }
            _hasPower = true;
        } else {
            _power = 0;
            _needlePower = _needlePower * 0.72;
            _hasPower = false;
        }
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        dc.clear();

        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }

        // Full analogue gauge when it has enough vertical room.
        if (dc.getHeight() >= 220) {
            drawFullGauge(dc);
        } else {
            drawCompactGauge(dc);
        }
    }

    function drawFullGauge(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = (h * 45) / 100;
        var r = (w * 43) / 100;

        // Outer bezel and inner dial ring.
        dc.setPenWidth(3);
        dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, 210, 330);
        dc.setPenWidth(1);
        dc.drawArc(cx, cy, r - 7, Graphics.ARC_CLOCKWISE, 210, 330);

        drawTicksAndLabels(dc, cx, cy, r);
        drawNeedle(dc, cx, cy, r);

        // Pivot: white center inside black hub = tiny mechanical detail that reads well in 1-bit.
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        dc.fillCircle(cx, cy, 8);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_WHITE);
        dc.fillCircle(cx, cy, 3);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);

        // Big digital readout beneath the dial.
        var wattsY = (h * 65) / 100;
        var powerText = _hasPower ? _power.format("%d") : "--";
        dc.drawText(cx, wattsY, Graphics.FONT_NUMBER_HOT, powerText, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, wattsY + dc.getFontHeight(Graphics.FONT_NUMBER_HOT) - 2,
                    Graphics.FONT_SMALL, "WATTS", Graphics.TEXT_JUSTIFY_CENTER);

        // Tiny scale legend at the bottom; enough context without clutter.
        dc.setPenWidth(1);
        dc.drawLine((w * 27) / 100, h - 24, (w * 73) / 100, h - 24);
        dc.drawText(cx, h - 21, Graphics.FONT_XTINY,
                    "0  -  " + MAX_POWER.format("%d"), Graphics.TEXT_JUSTIFY_CENTER);
    }

    function drawTicksAndLabels(dc, cx, cy, r) {
        // 40 subdivisions = 20 W/tick on the default 0-800 W scale.
        for (var i = 0; i <= 40; i += 1) {
            var fraction = i / 40.0;
            var angle = START_ANGLE - (SWEEP_ANGLE * fraction);

            var isMajor = ((i % 5) == 0);
            var tickLen = isMajor ? 13 : (((i % 5) == 0) ? 10 : 6);
            var pen = isMajor ? 3 : 1;

            var p1 = polarPoint(cx, cy, r - 3, angle);
            var p2 = polarPoint(cx, cy, r - 3 - tickLen, angle);
            dc.setPenWidth(pen);
            dc.drawLine(p1[0], p1[1], p2[0], p2[1]);

            if (isMajor) {
                var labelValue = ((MAX_POWER * i) / 40);
                var lp = polarPoint(cx, cy, r - 30, angle);
                dc.drawText(lp[0], lp[1] - 6, Graphics.FONT_XTINY,
                            labelValue.format("%d"), Graphics.TEXT_JUSTIFY_CENTER);
            }
        }
    }

    function drawNeedle(dc, cx, cy, r) {
        var shown = _needlePower;
        if (shown < 0) { shown = 0; }
        if (shown > MAX_POWER) { shown = MAX_POWER; }

        var fraction = shown / MAX_POWER.toFloat();
        var angle = START_ANGLE - (SWEEP_ANGLE * fraction);
        var tip = polarPoint(cx, cy, r - 25, angle);

        // Build a tapered needle perpendicular to its direction.
        var sideAngleA = angle + 90.0;
        var sideAngleB = angle - 90.0;
        var baseA = polarPoint(cx, cy, 5, sideAngleA);
        var baseB = polarPoint(cx, cy, 5, sideAngleB);
        var tail = polarPoint(cx, cy, 13, angle + 180.0);

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        dc.fillPolygon([
            [tip[0], tip[1]],
            [baseA[0], baseA[1]],
            [tail[0], tail[1]],
            [baseB[0], baseB[1]]
        ]);
    }

    function drawCompactGauge(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;
        var r = (w * 38) / 100;

        dc.setPenWidth(2);
        dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, 210, 330);

        var shown = _needlePower;
        if (shown < 0) { shown = 0; }
        if (shown > MAX_POWER) { shown = MAX_POWER; }
        var fraction = shown / MAX_POWER.toFloat();
        var angle = START_ANGLE - (SWEEP_ANGLE * fraction);
        var tip = polarPoint(cx, cy, r - 8, angle);
        dc.setPenWidth(3);
        dc.drawLine(cx, cy, tip[0], tip[1]);
        dc.fillCircle(cx, cy, 4);

        var powerText = _hasPower ? _power.format("%d") : "--";
        dc.drawText(cx, cy + 10, Graphics.FONT_NUMBER_MILD,
                    powerText, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function polarPoint(cx, cy, radius, degrees) {
        var rad = Math.toRadians(degrees);
        var x = cx + (Math.cos(rad) * radius);
        var y = cy - (Math.sin(rad) * radius);
        return [x, y];
    }
}
