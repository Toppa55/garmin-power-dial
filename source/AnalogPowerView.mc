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
    const DEFAULT_RESTING_HR = 60;
    const DEFAULT_THRESHOLD_HR = 170;
    const DEFAULT_MAX_HR = 190;
    const DEFAULT_DECOUPLING = 10;

    hidden var _power;
    hidden var _needlePower;
    hidden var _averagePower;
    hidden var _heartRate;
    hidden var _averageHeartRate;
    hidden var _timerTime;
    hidden var _hasPower;
    hidden var _ftp;
    hidden var _fuelBudgetKj;
    hidden var _restingHeartRate;
    hidden var _thresholdHeartRate;
    hidden var _maxHeartRate;
    hidden var _decouplingPercent;
    hidden var _effortScore;
    hidden var _feedback;

    function initialize() {
        DataField.initialize();
        _power = 0;
        _needlePower = 0.0;
        _averagePower = 0;
        _heartRate = 0;
        _averageHeartRate = 0;
        _timerTime = 0;
        _hasPower = false;
        _effortScore = 0;
        _feedback = "PAIR HR";
        loadCalibration();
    }

    function loadCalibration() {
        var configuredFtp = Application.Properties.getValue("ftpWatts");
        var configuredFuel = Application.Properties.getValue("fuelBudgetKj");
        var configuredRestingHr = Application.Properties.getValue("restingHeartRate");
        var configuredThresholdHr = Application.Properties.getValue("thresholdHeartRate");
        var configuredMaxHr = Application.Properties.getValue("maxHeartRate");
        var configuredDecoupling = Application.Properties.getValue("decouplingPercent");
        _ftp = (configuredFtp != null && configuredFtp > 0) ? configuredFtp : DEFAULT_FTP;
        _fuelBudgetKj = (configuredFuel != null && configuredFuel > 0) ? configuredFuel : DEFAULT_FUEL_KJ;
        _restingHeartRate = (configuredRestingHr != null && configuredRestingHr > 0) ? configuredRestingHr : DEFAULT_RESTING_HR;
        _thresholdHeartRate = (configuredThresholdHr != null && configuredThresholdHr > _restingHeartRate) ? configuredThresholdHr : DEFAULT_THRESHOLD_HR;
        _maxHeartRate = (configuredMaxHr != null && configuredMaxHr > _thresholdHeartRate) ? configuredMaxHr : DEFAULT_MAX_HR;
        _decouplingPercent = (configuredDecoupling != null && configuredDecoupling > 0) ? configuredDecoupling : DEFAULT_DECOUPLING;
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
        _heartRate = (info.currentHeartRate != null) ? info.currentHeartRate : 0;
        _averageHeartRate = (info.averageHeartRate != null) ? info.averageHeartRate : 0;
        _timerTime = (info.timerTime != null) ? info.timerTime : 0;
        updateEffortFeedback();
    }

    function updateEffortFeedback() {
        var powerLoad = (_ftp > 0) ? ((_power.toFloat() / _ftp.toFloat()) * 100.0) : 0.0;
        var hrRange = _thresholdHeartRate - _restingHeartRate;
        var heartLoad = 0.0;
        if (_heartRate > 0 && hrRange > 0) {
            heartLoad = ((_heartRate - _restingHeartRate).toFloat() / hrRange.toFloat()) * 100.0;
        }
        if (powerLoad < 0) { powerLoad = 0; }
        if (powerLoad > 150) { powerLoad = 150; }
        if (heartLoad < 0) { heartLoad = 0; }
        if (heartLoad > 150) { heartLoad = 150; }
        _effortScore = Math.floor((powerLoad * 0.6) + (heartLoad * 0.4));
        if (_effortScore > 100) { _effortScore = 100; }

        if (!_hasPower) {
            _feedback = "NO POWER";
            return;
        }
        if (_heartRate <= 0) {
            _feedback = "PAIR HR";
            return;
        }
        if (fuelPercent() <= 15) {
            _feedback = "FUEL LOW";
            return;
        }
        if (_power > _ftp && _heartRate >= _thresholdHeartRate) {
            _feedback = "EASE OFF";
            return;
        }

        var cappedPower = powerLoad;
        if (cappedPower > 100) { cappedPower = 100; }
        var expectedHr = _restingHeartRate + (((_thresholdHeartRate - _restingHeartRate) * cappedPower) / 100.0);
        var driftLimit = expectedHr * (1.0 + (_decouplingPercent.toFloat() / 100.0));
        if (_timerTime > 1200000 && powerLoad > 50 && _heartRate > driftLimit) {
            _feedback = "HR DRIFT";
        } else if (_effortScore >= 88) {
            _feedback = "HARD";
        } else if (powerLoad >= 78 && powerLoad <= 102 && heartLoad <= 105) {
            _feedback = "HOLD";
        } else if (_effortScore < 55 && fuelPercent() > 35) {
            _feedback = "PUSH";
        } else {
            _feedback = "STEADY";
        }
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
        var cy = (h * 39) / 100;
        var r = (w * 41) / 100;

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

        drawLiveMetrics(dc, cx, h - 91);
        drawFuelGauge(dc, 14, h - 59, w - 28, 45);
    }

    function drawCheckEngine(dc, cx, y) {
        var isHot = _hasPower && (_power > _ftp);
        var x = cx - 42;
        var label = isHot ? "FTP!" : _feedback;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        dc.setPenWidth(2);
        if (isHot) {
            dc.fillRectangle(x, y + 4, 84, 22);
            dc.fillRectangle(x + 8, y, 20, 4);
            dc.fillRectangle(x + 84, y + 10, 5, 9);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        } else {
            dc.drawRectangle(x, y + 4, 84, 22);
            dc.drawLine(x + 8, y + 4, x + 8, y);
            dc.drawLine(x + 8, y, x + 28, y);
            dc.drawLine(x + 84, y + 10, x + 89, y + 10);
            dc.drawLine(x + 89, y + 10, x + 89, y + 19);
            dc.drawLine(x + 89, y + 19, x + 84, y + 19);
        }
        dc.drawText(cx, y + 6, Graphics.FONT_XTINY,
                    label, Graphics.TEXT_JUSTIFY_CENTER);
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

    function fuelRemainingKj() {
        var remaining = (_fuelBudgetKj.toFloat() * fuelPercent()) / 100.0;
        if (remaining < 0) { remaining = 0; }
        return Math.floor(remaining);
    }

    function expectedHeartRate() {
        if (_ftp <= 0) { return _restingHeartRate; }
        var powerLoad = (_power.toFloat() / _ftp.toFloat()) * 100.0;
        if (powerLoad < 0) { powerLoad = 0; }
        if (powerLoad > 100) { powerLoad = 100; }
        return Math.floor(_restingHeartRate + (((_thresholdHeartRate - _restingHeartRate) * powerLoad) / 100.0));
    }

    function drawLiveMetrics(dc, cx, y) {
        var powerPercent = (_ftp > 0) ? ((_power * 100) / _ftp) : 0;
        var hrText = (_heartRate > 0) ? _heartRate.format("%d") : "--";
        var deltaText = "";
        if (_heartRate > 0 && _power > 0) {
            var delta = _heartRate - expectedHeartRate();
            deltaText = (delta >= 0 ? "+" : "") + delta.format("%d");
        }
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        dc.drawText(cx, y, Graphics.FONT_XTINY,
                    "HR " + hrText + " " + deltaText + "   P " + powerPercent.format("%d") + "%   E " + _effortScore.format("%d"),
                    Graphics.TEXT_JUSTIFY_CENTER);
    }

    function drawFuelGauge(dc, x, y, width, height) {
        var percent = fuelPercent();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        dc.drawText(x + (width / 2), y - 1, Graphics.FONT_XTINY,
                    "FUEL " + percent.format("%d") + "%  " + fuelRemainingKj().format("%d") + "kJ",
                    Graphics.TEXT_JUSTIFY_CENTER);
        var barY = y + 15;
        var segments = 20;
        var gap = 1;
        var filled = Math.ceil(percent / 5.0);
        for (var i = 0; i < segments; i += 1) {
            var segmentX = x + ((width * i) / segments);
            var segmentRight = x + ((width * (i + 1)) / segments) - gap;
            var segmentWidth = segmentRight - segmentX;
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
            dc.drawRectangle(segmentX, barY, segmentWidth, 16);
            if (i < filled) {
                dc.fillRectangle(segmentX + 2, barY + 2, segmentWidth - 3, 12);
            }
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
                    _feedback + "  " + fuelPercent().format("%d") + "%",
                    Graphics.TEXT_JUSTIFY_CENTER);
    }

    function polarPoint(cx, cy, radius, degrees) {
        var rad = Math.toRadians(degrees);
        return [cx + (Math.cos(rad) * radius),
                cy - (Math.sin(rad) * radius)];
    }
}
