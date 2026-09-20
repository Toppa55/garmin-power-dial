using Toybox.Application;
using Toybox.Graphics;
using Toybox.Math;
using Toybox.WatchUi;

class AnalogPowerView extends WatchUi.DataField {
    const START_ANGLE = 210.0;
    const SWEEP_ANGLE = 240.0;
    const MAX_FTP_PERCENT = 200;
    const DEFAULT_FTP = 250;
    const DEFAULT_FUEL_KJ = 1200;

    hidden var _power;
    hidden var _needlePower;
    hidden var _averagePower;
    hidden var _timerTime;
    hidden var _hasPower;
    hidden var _ftp;
    hidden var _fuelBudgetKj;

    function initialize() {
        DataField.initialize();
        _power = 0;
        _needlePower = 0.0;
        _averagePower = 0;
        _timerTime = 0;
        _hasPower = false;
        loadCalibration();
    }

    function loadCalibration() {
        var configuredFtp = Application.Properties.getValue("ftpWatts");
        var configuredFuel = Application.Properties.getValue("fuelBudgetKj");
        _ftp = (configuredFtp != null && configuredFtp > 0) ? configuredFtp : DEFAULT_FTP;
        _fuelBudgetKj = (configuredFuel != null && configuredFuel > 0) ? configuredFuel : DEFAULT_FUEL_KJ;
    }

    function compute(info) {
        loadCalibration();
        if (info.currentPower != null) {
            _power = info.currentPower;
            _needlePower = _hasPower
                ? ((_needlePower * 0.58) + (_power * 0.42))
                : _power.toFloat();
            _hasPower = true;
        } else {
            _power = 0;
            _needlePower = _needlePower * 0.72;
            _hasPower = false;
        }

        _averagePower = (info.averagePower != null) ? info.averagePower : 0;
        _timerTime = (info.timerTime != null) ? info.timerTime : 0;
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        dc.clear();
        if (dc has :setAntiAlias) { dc.setAntiAlias(true); }

        if (dc.getHeight() >= 220) {
            drawDashboard(dc);
        } else {
            drawCompactGauge(dc);
        }
    }

    function drawDashboard(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = (h * 42) / 100;
        var r = (w * 43) / 100;

        drawCheckEngine(dc, cx, 5);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        dc.setPenWidth(3);
        dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, 210, 330);
        dc.setPenWidth(1);
        dc.drawArc(cx, cy, r - 7, Graphics.ARC_CLOCKWISE, 210, 330);
        drawTicksAndLabels(dc, cx, cy, r);
        drawNeedle(dc, cx, cy, r);

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        dc.fillCircle(cx, cy, 8);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_WHITE);
        dc.fillCircle(cx, cy, 3);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);

        var powerText = _hasPower ? _power.format("%d") : "--";
        dc.drawText(cx, cy + 17, Graphics.FONT_NUMBER_HOT,
                    powerText, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, cy + 17 + dc.getFontHeight(Graphics.FONT_NUMBER_HOT) - 2,
                    Graphics.FONT_XTINY, "W  /  FTP " + _ftp.format("%d"),
                    Graphics.TEXT_JUSTIFY_CENTER);

        drawFuelGauge(dc, 14, h - 49, w - 28, 35);
    }

    function drawCheckEngine(dc, cx, y) {
        var isHot = _hasPower && (_power > _ftp);
        var x = cx - 28;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        dc.setPenWidth(2);
        if (isHot) {
            dc.fillRectangle(x, y + 4, 56, 22);
            dc.fillRectangle(x + 8, y, 20, 4);
            dc.fillRectangle(x + 56, y + 10, 5, 9);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        } else {
            dc.drawRectangle(x, y + 4, 56, 22);
            dc.drawLine(x + 8, y + 4, x + 8, y);
            dc.drawLine(x + 8, y, x + 28, y);
            dc.drawLine(x + 56, y + 10, x + 61, y + 10);
            dc.drawLine(x + 61, y + 10, x + 61, y + 19);
            dc.drawLine(x + 61, y + 19, x + 56, y + 19);
        }
        dc.drawText(cx, y + 6, Graphics.FONT_XTINY,
                    isHot ? "FTP!" : "ENGINE", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
    }

    function drawTicksAndLabels(dc, cx, cy, r) {
        for (var i = 0; i <= 20; i += 1) {
            var fraction = i / 20.0;
            var angle = START_ANGLE - (SWEEP_ANGLE * fraction);
            var isMajor = ((i % 5) == 0);
            var tickLen = isMajor ? 14 : ((i % 2) == 0 ? 9 : 6);
            var p1 = polarPoint(cx, cy, r - 3, angle);
            var p2 = polarPoint(cx, cy, r - 3 - tickLen, angle);
            dc.setPenWidth(isMajor ? 3 : 1);
            dc.drawLine(p1[0], p1[1], p2[0], p2[1]);

            if (isMajor) {
                var label = ((MAX_FTP_PERCENT * i) / 20);
                var lp = polarPoint(cx, cy, r - 31, angle);
                dc.drawText(lp[0], lp[1] - 6, Graphics.FONT_XTINY,
                            label.format("%d"), Graphics.TEXT_JUSTIFY_CENTER);
            }
        }

        var ftpAngle = START_ANGLE - (SWEEP_ANGLE * 0.5);
        var ftpA = polarPoint(cx, cy, r + 1, ftpAngle);
        var ftpB = polarPoint(cx, cy, r - 19, ftpAngle);
        dc.setPenWidth(5);
        dc.drawLine(ftpA[0], ftpA[1], ftpB[0], ftpB[1]);
        dc.drawText(cx, cy - r + 18, Graphics.FONT_XTINY,
                    "% FTP", Graphics.TEXT_JUSTIFY_CENTER);
    }

    function drawNeedle(dc, cx, cy, r) {
        var maxPower = _ftp * 2;
        var shown = _needlePower;
        if (shown < 0) { shown = 0; }
        if (shown > maxPower) { shown = maxPower; }
        var fraction = shown / maxPower.toFloat();
        var angle = START_ANGLE - (SWEEP_ANGLE * fraction);
        var tip = polarPoint(cx, cy, r - 24, angle);
        var baseA = polarPoint(cx, cy, 5, angle + 90.0);
        var baseB = polarPoint(cx, cy, 5, angle - 90.0);
        var tail = polarPoint(cx, cy, 13, angle + 180.0);
        dc.fillPolygon([[tip[0], tip[1]], [baseA[0], baseA[1]],
                        [tail[0], tail[1]], [baseB[0], baseB[1]]]);
    }

    function fuelPercent() {
        if (_fuelBudgetKj <= 0) { return 0; }
        var usedKj = (_averagePower.toFloat() * _timerTime.toFloat()) / 1000000.0;
        var remaining = 100.0 - ((usedKj / _fuelBudgetKj.toFloat()) * 100.0);
        if (remaining < 0) { remaining = 0; }
        if (remaining > 100) { remaining = 100; }
        return remaining;
    }

    function drawFuelGauge(dc, x, y, width, height) {
        var percent = fuelPercent();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        dc.drawText(x, y - 1, Graphics.FONT_XTINY, "E", Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(x + width, y - 1, Graphics.FONT_XTINY, "F", Graphics.TEXT_JUSTIFY_RIGHT);
        dc.drawText(x + (width / 2), y - 1, Graphics.FONT_XTINY,
                    "FUEL " + percent.format("%d") + "%", Graphics.TEXT_JUSTIFY_CENTER);
        var barY = y + 15;
        dc.setPenWidth(2);
        dc.drawRectangle(x, barY, width, 16);
        var innerWidth = ((width - 4) * Math.floor(percent)) / 100;
        if (innerWidth > 0) { dc.fillRectangle(x + 2, barY + 2, innerWidth, 12); }
        for (var i = 1; i < 4; i += 1) {
            var markX = x + ((width * i) / 4);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            dc.drawLine(markX, barY + 2, markX, barY + 13);
        }
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
    }

    function drawCompactGauge(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var powerText = _hasPower ? _power.format("%d") : "--";
        dc.drawText(cx, 2, Graphics.FONT_NUMBER_MILD,
                    powerText, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, h - 18, Graphics.FONT_XTINY,
                    fuelPercent().format("%d") + "% FUEL",
                    Graphics.TEXT_JUSTIFY_CENTER);
    }

    function polarPoint(cx, cy, radius, degrees) {
        var rad = Math.toRadians(degrees);
        return [cx + (Math.cos(rad) * radius),
                cy - (Math.sin(rad) * radius)];
    }
}
