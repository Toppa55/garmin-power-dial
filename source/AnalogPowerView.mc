using Toybox.Application;
using Toybox.Graphics;
using Toybox.Math;
using Toybox.Lang;
using Toybox.WatchUi;

class AnalogPowerView extends WatchUi.DataField {
    const START_ANGLE = 210.0;
    const SWEEP_ANGLE = 240.0;
    const DEFAULT_FTP = 250;
    const DEFAULT_RESERVE_KJ = 25;
    const DEFAULT_RECOVERY_SECONDS = 300;
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
    hidden var _reserveJoules;
    hidden var _lastTimerTime;
    hidden var _rideMath;
    hidden var _restingHeartRate;
    hidden var _thresholdHeartRate;
    hidden var _maxHeartRate;
    hidden var _decouplingPercent;
    hidden var _effortScore;
    hidden var _feedback;
    hidden var _remoteCue;
    hidden var _remoteTargetLow;
    hidden var _remoteTargetHigh;
    hidden var _remoteRisk;
    hidden var _remoteConfidence;

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
        _remoteCue = null;
        _remoteTargetLow = 0;
        _remoteTargetHigh = 0;
        _remoteRisk = "";
        _remoteConfidence = 0;
        _lastTimerTime = 0;
        _rideMath = new RideMath();
        loadCalibration();
        _reserveJoules = _fuelBudgetKj * 1000.0;
    }

    function loadCalibration() {
        var configuredFtp = Application.Properties.getValue("ftpWatts");
        var configuredFuel = Application.Properties.getValue("fuelBudgetKj");
        var configuredRestingHr = Application.Properties.getValue("restingHeartRate");
        var configuredThresholdHr = Application.Properties.getValue("thresholdHeartRate");
        var configuredMaxHr = Application.Properties.getValue("maxHeartRate");
        var configuredDecoupling = Application.Properties.getValue("decouplingPercent");
        _ftp = (configuredFtp != null && configuredFtp > 0) ? configuredFtp : DEFAULT_FTP;
        // Values above 200 kJ came from the previous total-work fuel model.
        // Migrate those installs to a realistic hard-effort reserve.
        _fuelBudgetKj = (configuredFuel != null && configuredFuel > 0 && configuredFuel <= 200) ? configuredFuel : DEFAULT_RESERVE_KJ;
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
        var nextTimer = (info.timerTime != null) ? info.timerTime : 0;
        if (nextTimer < _lastTimerTime) {
            _reserveJoules = _fuelBudgetKj * 1000.0;
        }
        var dt = (nextTimer - _lastTimerTime) / 1000.0;
        _reserveJoules = _rideMath.reserve(_reserveJoules, _power, _ftp,
                                          _fuelBudgetKj * 1000, DEFAULT_RECOVERY_SECONDS, dt);
        _lastTimerTime = nextTimer;
        _timerTime = nextTimer;
        updateEffortFeedback();
    }

    function receiveCoach(data) {
        if (!(data instanceof Lang.Dictionary)) { return; }
        if (data.hasKey("cue")) { _remoteCue = data["cue"].toString(); }
        if (data.hasKey("targetLow")) { _remoteTargetLow = data["targetLow"].toNumber(); }
        if (data.hasKey("targetHigh")) { _remoteTargetHigh = data["targetHigh"].toNumber(); }
        if (data.hasKey("risk")) { _remoteRisk = data["risk"].toString(); }
        if (data.hasKey("confidence")) { _remoteConfidence = data["confidence"].toNumber(); }
        if (data.hasKey("ftp") && data["ftp"].toNumber() > 0) {
            _ftp = data["ftp"].toNumber();
            Application.Properties.setValue("ftpWatts", _ftp);
        }
        if (data.hasKey("reserveKj") && data["reserveKj"].toNumber() > 0) {
            var oldCapacity = _fuelBudgetKj * 1000.0;
            var oldFraction = (oldCapacity > 0) ? (_reserveJoules / oldCapacity) : 1.0;
            _fuelBudgetKj = data["reserveKj"].toNumber();
            _reserveJoules = _fuelBudgetKj * 1000.0 * oldFraction;
            Application.Properties.setValue("fuelBudgetKj", _fuelBudgetKj);
        }
        WatchUi.requestUpdate();
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
        var cy = (h * 40) / 100;
        var r = (w * 35) / 100;
        var tinyHeight = dc.getFontHeight(Graphics.FONT_XTINY);
        var barY = h - 20;
        var reserveY = barY - tinyHeight - 6;
        var remoteY = reserveY - tinyHeight - 5;
        var metricsY = remoteY - tinyHeight - 5;
        var subtitleY = metricsY - tinyHeight - 4;
        var powerY = subtitleY - dc.getFontHeight(Graphics.FONT_NUMBER_MILD) + 3;

        drawCheckEngine(dc, cx, 3);
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
        dc.drawText(cx, powerY, Graphics.FONT_NUMBER_MILD,
                    powerText, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, subtitleY, Graphics.FONT_XTINY,
                    "W     FTP " + _ftp.format("%d"),
                    Graphics.TEXT_JUSTIFY_CENTER);

        drawLiveMetrics(dc, cx, metricsY, remoteY);
        drawFuelGauge(dc, 14, reserveY, w - 28, barY);
    }

    function drawCheckEngine(dc, cx, y) {
        var isHot = _hasPower && (_power > _ftp);
        var x = cx - 50;
        var label = isHot ? "FTP!" : ((_remoteCue != null) ? _remoteCue : _feedback);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        dc.setPenWidth(1);
        if (isHot) {
            dc.fillRectangle(x, y, 100, 21);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        } else {
            dc.drawRectangle(x, y, 100, 21);
        }
        dc.drawText(cx, y + 2, Graphics.FONT_XTINY,
                    label, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
    }

    function drawTicksAndLabels(dc, cx, cy, r) {
        var labelValues = [0, 80, 100, 150, 400];
        for (var i = 0; i <= 21; i += 1) {
            var percent = (i == 21) ? 150 : (i * 20);
            var fraction = _rideMath.fraction(percent);
            var angle = START_ANGLE - (SWEEP_ANGLE * fraction);
            var isMajor = (labelValues.indexOf(percent) >= 0);
            var tickLen = isMajor ? 11 : 5;
            var p1 = polarPoint(cx, cy, r - 3, angle);
            var p2 = polarPoint(cx, cy, r - 3 - tickLen, angle);
            dc.setPenWidth(isMajor ? 3 : 1);
            dc.drawLine(p1[0], p1[1], p2[0], p2[1]);

            if (isMajor) {
                var label = percent;
                var lp = polarPoint(cx, cy, r - 28, angle);
                dc.drawText(lp[0], lp[1] - 7, Graphics.FONT_XTINY,
                            label.format("%d"), Graphics.TEXT_JUSTIFY_CENTER);
            }
        }

        var ftpAngle = START_ANGLE - (SWEEP_ANGLE * _rideMath.fraction(100));
        var ftpA = polarPoint(cx, cy, r + 1, ftpAngle);
        var ftpB = polarPoint(cx, cy, r - 19, ftpAngle);
        dc.setPenWidth(5);
        dc.drawLine(ftpA[0], ftpA[1], ftpB[0], ftpB[1]);
    }

    function drawNeedle(dc, cx, cy, r) {
        var shown = _needlePower;
        if (shown < 0) { shown = 0; }
        var percent = (shown * 100.0) / _ftp.toFloat();
        var fraction = _rideMath.fraction(percent);
        var angle = START_ANGLE - (SWEEP_ANGLE * fraction);
        var tip = polarPoint(cx, cy, r - 24, angle);
        var baseA = polarPoint(cx, cy, 5, angle + 90.0);
        var baseB = polarPoint(cx, cy, 5, angle - 90.0);
        var tail = polarPoint(cx, cy, 13, angle + 180.0);
        dc.fillPolygon([[tip[0], tip[1]], [baseA[0], baseA[1]],
                        [tail[0], tail[1]], [baseB[0], baseB[1]]]);
    }

    function fuelPercent() {
        if (_fuelBudgetKj <= 0) { return 0.0; }
        var remaining = (_reserveJoules / (_fuelBudgetKj * 1000.0)) * 100.0;
        if (remaining < 0) { remaining = 0; }
        if (remaining > 100) { remaining = 100; }
        return remaining;
    }

    function fuelRemainingKj() {
        return Math.floor(_reserveJoules / 1000.0);
    }

    function expectedHeartRate() {
        if (_ftp <= 0) { return _restingHeartRate; }
        var powerLoad = (_power.toFloat() / _ftp.toFloat()) * 100.0;
        if (powerLoad < 0) { powerLoad = 0; }
        if (powerLoad > 100) { powerLoad = 100; }
        return Math.floor(_restingHeartRate + (((_thresholdHeartRate - _restingHeartRate) * powerLoad) / 100.0));
    }

    function drawLiveMetrics(dc, cx, y, remoteY) {
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
        if (_remoteTargetHigh > 0) {
            dc.drawText(cx, remoteY, Graphics.FONT_XTINY,
                        "T " + _remoteTargetLow.format("%d") + "-" + _remoteTargetHigh.format("%d") + "  " + _remoteRisk + " " + _remoteConfidence.format("%d") + "%",
                        Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    function drawFuelGauge(dc, x, y, width, barY) {
        var percent = fuelPercent();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        dc.drawText(x + (width / 2), y, Graphics.FONT_XTINY,
                    "RES " + percent.format("%d") + "%  " + fuelRemainingKj().format("%d") + "kJ",
                    Graphics.TEXT_JUSTIFY_CENTER);
        var segments = 20;
        var filled = Math.floor(percent / 5.0);
        for (var i = 0; i < segments; i += 1) {
            var segmentX = x + ((width * i) / segments);
            var segmentRight = x + ((width * (i + 1)) / segments) - 2;
            var segmentWidth = segmentRight - segmentX;
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
            dc.drawRectangle(segmentX, barY, segmentWidth, 12);
            if (i < filled) {
                dc.fillRectangle(segmentX + 2, barY + 2, segmentWidth - 3, 8);
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
                    ((_remoteCue != null) ? _remoteCue : _feedback) + "  " + fuelPercent().format("%d") + "%",
                    Graphics.TEXT_JUSTIFY_CENTER);
    }

    function polarPoint(cx, cy, radius, degrees) {
        var rad = Math.toRadians(degrees);
        return [cx + (Math.cos(rad) * radius),
                cy - (Math.sin(rad) * radius)];
    }
}
