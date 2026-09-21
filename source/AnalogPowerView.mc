using Toybox.Application;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Math;
using Toybox.Time;
using Toybox.WatchUi;

class AnalogPowerView extends WatchUi.DataField {
    const DEFAULT_FTP = 250;
    const DEFAULT_TOTAL_FUEL_KJ = 1600;
    const DEFAULT_RESERVE_KJ = 25;
    const DEFAULT_RECOVERY_SECONDS = 300;
    const DEFAULT_RESTING_HR = 60;
    const DEFAULT_THRESHOLD_HR = 170;
    const DEFAULT_MAX_HR = 190;
    const DEFAULT_DECOUPLING = 10;

    hidden var _power;
    hidden var _hasPower;
    hidden var _heartRate;
    hidden var _timerTime;
    hidden var _lastTimerTime;
    hidden var _lastStoredTimer;
    hidden var _rideStartId;
    hidden var _ftp;
    hidden var _totalFuelBudgetKj;
    hidden var _fuelKj;
    hidden var _reserveCapacityKj;
    hidden var _reserveJoules;
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
    hidden var _remoteUntil;
    hidden var _rideMath;

    function initialize() {
        DataField.initialize();
        _power = 0;
        _hasPower = false;
        _heartRate = 0;
        _timerTime = 0;
        _lastTimerTime = 0;
        _lastStoredTimer = -30000;
        _rideStartId = Time.now().value();
        _effortScore = 0;
        _feedback = "NO POWER";
        _remoteCue = null;
        _remoteTargetLow = 0;
        _remoteTargetHigh = 0;
        _remoteRisk = "";
        _remoteConfidence = 0;
        _remoteUntil = 0;
        _rideMath = new RideMath();
        loadCalibration();
        _fuelKj = _totalFuelBudgetKj.toFloat();
        _reserveJoules = _reserveCapacityKj * 1000.0;
        var saved = Application.Storage.getValue("rideTelemetry");
        if (saved instanceof Lang.Dictionary && saved.hasKey("at") &&
            saved.hasKey("fuel_kj") && saved.hasKey("reserve_joules") &&
            saved.hasKey("elapsed_seconds") &&
            Time.now().value() >= saved["at"] &&
            Time.now().value() - saved["at"] < 43200) {
            _fuelKj = saved["fuel_kj"].toFloat();
            _reserveJoules = saved["reserve_joules"].toFloat();
            _lastTimerTime = saved["elapsed_seconds"].toNumber() * 1000;
            _lastStoredTimer = _lastTimerTime;
            if (saved.hasKey("ride_start")) { _rideStartId = saved["ride_start"].toNumber(); }
        }
    }

    function loadCalibration() {
        var ftp = Application.Properties.getValue("ftpWatts");
        var totalFuel = Application.Properties.getValue("totalFuelKj");
        var reserve = Application.Properties.getValue("fuelBudgetKj");
        var resting = Application.Properties.getValue("restingHeartRate");
        var threshold = Application.Properties.getValue("thresholdHeartRate");
        var maximum = Application.Properties.getValue("maxHeartRate");
        var decoupling = Application.Properties.getValue("decouplingPercent");
        _ftp = (ftp != null && ftp > 0) ? ftp : DEFAULT_FTP;
        _totalFuelBudgetKj = (totalFuel != null && totalFuel >= 100) ? totalFuel : DEFAULT_TOTAL_FUEL_KJ;
        // Earlier versions used this setting for total ride work. Ignore those
        // old values rather than creating a months-long fast reserve.
        _reserveCapacityKj = (reserve != null && reserve > 0 && reserve <= 200) ? reserve : DEFAULT_RESERVE_KJ;
        _restingHeartRate = (resting != null && resting > 0) ? resting : DEFAULT_RESTING_HR;
        _thresholdHeartRate = (threshold != null && threshold > _restingHeartRate) ? threshold : DEFAULT_THRESHOLD_HR;
        _maxHeartRate = (maximum != null && maximum > _thresholdHeartRate) ? maximum : DEFAULT_MAX_HR;
        _decouplingPercent = (decoupling != null && decoupling > 0) ? decoupling : DEFAULT_DECOUPLING;
    }

    function compute(info) {
        loadCalibration();
        _hasPower = info.currentPower != null;
        _power = _hasPower ? info.currentPower : 0;
        _heartRate = (info.currentHeartRate != null) ? info.currentHeartRate : 0;
        var nextTimer = (info.timerTime != null) ? info.timerTime : 0;
        if (nextTimer < _lastTimerTime) {
            _fuelKj = _totalFuelBudgetKj.toFloat();
            _reserveJoules = _reserveCapacityKj * 1000.0;
            _lastStoredTimer = -30000;
            _rideStartId = Time.now().value();
        }
        var dt = (nextTimer - _lastTimerTime) / 1000.0;
        if (dt > 0 && dt <= 3600) {
            var fuelPower = _power;
            if (dt > 5 && info.averagePower != null) { fuelPower = info.averagePower; }
            _fuelKj = _rideMath.totalFuel(_fuelKj, fuelPower, _ftp, dt);
        }
        if (dt > 0 && dt <= 5) {
            _reserveJoules = _rideMath.reserve(_reserveJoules, _power, _ftp,
                                              _reserveCapacityKj * 1000, DEFAULT_RECOVERY_SECONDS, dt);
        }
        _lastTimerTime = nextTimer;
        _timerTime = nextTimer;
        updateEffortFeedback();
        if (nextTimer > 0 && nextTimer - _lastStoredTimer >= 30000) {
            saveBridgeTelemetry();
            _lastStoredTimer = nextTimer;
        }
    }

    function saveBridgeTelemetry() {
        var riderId = Application.Properties.getValue("bridgeRiderId");
        if (riderId == null || riderId.length() == 0) { riderId = "thomas"; }
        Application.Storage.setValue("rideTelemetry", {
            "at" => Time.now().value(),
            "rider_id" => riderId,
            "session_id" => "edge-" + _rideStartId.format("%d"),
            "elapsed_seconds" => Math.floor(_timerTime / 1000),
            "power_watts" => _power,
            "heart_rate_bpm" => _heartRate,
            "reserve_percent" => reservePercent(),
            "fuel_percent" => fuelPercent(),
            "fuel_kj" => _fuelKj,
            "reserve_joules" => _reserveJoules,
            "ride_start" => _rideStartId
        });
    }

    function receiveCoach(data) {
        if (!(data instanceof Lang.Dictionary)) { return; }
        if (data.hasKey("cue") && data["cue"] != null) {
            _remoteCue = data["cue"].toString();
            var ttl = data.hasKey("ttlSeconds") ? data["ttlSeconds"].toNumber() : 90;
            if (ttl > 360) { ttl = 360; }
            if (ttl < 1) { ttl = 1; }
            _remoteUntil = Time.now().value() + ttl;
        }
        if (data.hasKey("targetLow")) { _remoteTargetLow = data["targetLow"].toNumber(); }
        if (data.hasKey("targetHigh")) { _remoteTargetHigh = data["targetHigh"].toNumber(); }
        if (data.hasKey("risk")) { _remoteRisk = data["risk"].toString(); }
        if (data.hasKey("confidence")) { _remoteConfidence = data["confidence"].toNumber(); }
        if (data.hasKey("ftp") && data["ftp"].toNumber() > 0) {
            _ftp = data["ftp"].toNumber();
            Application.Properties.setValue("ftpWatts", _ftp);
        }
        if (data.hasKey("totalFuelKj") && data["totalFuelKj"].toNumber() >= 100) {
            var oldFuelFraction = fuelPercent() / 100.0;
            _totalFuelBudgetKj = data["totalFuelKj"].toNumber();
            _fuelKj = _totalFuelBudgetKj * oldFuelFraction;
            Application.Properties.setValue("totalFuelKj", _totalFuelBudgetKj);
        }
        if (data.hasKey("reserveKj") && data["reserveKj"].toNumber() > 0) {
            var oldReserveFraction = reservePercent() / 100.0;
            _reserveCapacityKj = data["reserveKj"].toNumber();
            _reserveJoules = _reserveCapacityKj * 1000.0 * oldReserveFraction;
            Application.Properties.setValue("fuelBudgetKj", _reserveCapacityKj);
        }
        WatchUi.requestUpdate();
    }

    function fuelPercent() {
        if (_totalFuelBudgetKj <= 0) { return 0; }
        var percent = Math.floor(100.0 * _fuelKj / _totalFuelBudgetKj);
        if (percent < 0) { return 0; }
        return percent > 100 ? 100 : percent;
    }

    function reservePercent() {
        if (_reserveCapacityKj <= 0) { return 0; }
        var percent = Math.floor(100.0 * _reserveJoules / (_reserveCapacityKj * 1000.0));
        if (percent < 0) { return 0; }
        return percent > 100 ? 100 : percent;
    }

    function expectedHeartRate() {
        var powerLoad = _power.toFloat() / _ftp.toFloat();
        if (powerLoad > 1) { powerLoad = 1.0; }
        if (powerLoad < 0) { powerLoad = 0.0; }
        return Math.floor(_restingHeartRate + ((_thresholdHeartRate - _restingHeartRate) * powerLoad));
    }

    function readiness() {
        if (!_hasPower) { return "WAIT"; }
        if (reservePercent() < 25 || (_heartRate > 0 && _heartRate >= _thresholdHeartRate)) { return "EASE OFF"; }
        if (reservePercent() >= 75 && _power < _ftp && (_heartRate == 0 || _heartRate < _thresholdHeartRate)) { return "GO AGAIN"; }
        if (_power >= _ftp) { return "EFFORT ON"; }
        return "RECOVER";
    }

    function updateEffortFeedback() {
        var powerLoad = (_power.toFloat() / _ftp.toFloat()) * 100.0;
        var heartLoad = 0.0;
        if (_heartRate > 0) {
            heartLoad = ((_heartRate - _restingHeartRate).toFloat() /
                         (_thresholdHeartRate - _restingHeartRate).toFloat()) * 100.0;
        }
        if (powerLoad > 150) { powerLoad = 150; }
        if (heartLoad > 150) { heartLoad = 150; }
        if (heartLoad < 0) { heartLoad = 0; }
        _effortScore = Math.floor((powerLoad * 0.6) + (heartLoad * 0.4));
        if (_effortScore > 100) { _effortScore = 100; }

        if (!_hasPower) { _feedback = "NO POWER"; return; }
        if (_heartRate <= 0) { _feedback = "PAIR HR"; return; }
        if (fuelPercent() <= 15) { _feedback = "FUEL LOW"; return; }
        if (reservePercent() <= 25 && _power >= _ftp) { _feedback = "EASE OFF"; return; }
        var driftLimit = expectedHeartRate() * (1.0 + (_decouplingPercent / 100.0));
        if (_timerTime > 1200000 && powerLoad > 50 && _heartRate > driftLimit) {
            _feedback = "HR DRIFT";
        } else if (_power > _ftp && _heartRate >= _thresholdHeartRate) {
            _feedback = "EASE OFF";
        } else if (_effortScore >= 88) {
            _feedback = "HARD";
        } else if (powerLoad >= 78 && powerLoad <= 102) {
            _feedback = "HOLD";
        } else {
            _feedback = "STEADY";
        }
    }

    function currentCue() {
        if (_remoteCue != null && Time.now().value() < _remoteUntil) { return _remoteCue; }
        return _feedback;
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        dc.clear();
        if (dc.getHeight() >= 290) { drawDashboard(dc); }
        else { drawCompact(dc); }
    }

    function drawDashboard(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var left = 13;
        var width = w - 26;
        var center = w / 2;
        var small = Graphics.FONT_XTINY;
        var smallHeight = dc.getFontHeight(small);

        drawTextBand(dc, center, 3, currentCue());

        var powerText = _hasPower ? _power.format("%d") : "--";
        dc.drawText(center, 28, Graphics.FONT_MEDIUM,
                    powerText + " W", Graphics.TEXT_JUSTIFY_CENTER);
        drawPowerBar(dc, left, 59, width, 18);
        for (var n = 1; n <= 5; n += 1) {
            dc.drawText(left + ((width * n) / 5), 81, small,
                        n.format("%d"), Graphics.TEXT_JUSTIFY_CENTER);
        }

        var hrText = (_heartRate > 0) ? _heartRate.format("%d") : "--";
        var delta = (_heartRate > 0 && _hasPower) ? _heartRate - expectedHeartRate() : 0;
        var deltaText = (_heartRate > 0 && _hasPower) ? ((delta >= 0 ? "+" : "") + delta.format("%d")) : "--";
        dc.drawText(center, 108, small,
                    "HR " + hrText + "  vs P " + deltaText + "   E " + _effortScore.format("%d"),
                    Graphics.TEXT_JUSTIFY_CENTER);
        var targetText = "FTP " + _ftp.format("%d") + " W";
        if (_remoteTargetHigh > 0 && Time.now().value() < _remoteUntil) {
            targetText = "T " + _remoteTargetLow.format("%d") + "-" +
                         _remoteTargetHigh.format("%d") + "  " + _remoteRisk +
                         " " + _remoteConfidence.format("%d") + "%";
        }
        dc.drawText(center, 108 + smallHeight + 3, small,
                    targetText, Graphics.TEXT_JUSTIFY_CENTER);

        dc.drawText(center, 160, small,
                    "FUEL EST  " + fuelPercent().format("%d") + "%  " +
                    Math.floor(_fuelKj).format("%d") + "kJ",
                    Graphics.TEXT_JUSTIFY_CENTER);
        drawSegmentBar(dc, left, 185, width, 18, fuelPercent(), 20, 0);

        dc.drawText(center, 213, small,
                    "EFFORT RESERVE  " + reservePercent().format("%d") + "%",
                    Graphics.TEXT_JUSTIFY_CENTER);
        drawSegmentBar(dc, left, 239, width, 18, reservePercent(), 20, 75);

        dc.drawLine(left, 268, left + width, 268);
        dc.drawText(center, 273, small,
                    readiness() + "  " + Math.floor(_reserveJoules / 1000.0).format("%d") + "kJ",
                    Graphics.TEXT_JUSTIFY_CENTER);
    }

    function drawTextBand(dc, center, y, label) {
        dc.drawRectangle(center - 53, y, 106, 21);
        dc.drawText(center, y + 2, Graphics.FONT_XTINY,
                    label, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function drawPowerBar(dc, x, y, width, height) {
        var fill = (_power * width) / 500;
        if (fill > width) { fill = width; }
        if (fill < 0) { fill = 0; }
        dc.drawRectangle(x, y, width, height);
        if (_hasPower && fill > 2) { dc.fillRectangle(x + 2, y + 2, fill - 3, height - 4); }
        for (var n = 1; n < 5; n += 1) {
            var tickX = x + ((width * n) / 5);
            dc.setColor((tickX - x < fill) ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK,
                        Graphics.COLOR_WHITE);
            dc.drawLine(tickX, y + 2, tickX, y + height - 3);
        }
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        var ftpX = x + ((_ftp * width) / 500);
        if (ftpX > x && ftpX < x + width) {
            dc.drawLine(ftpX, y - 4, ftpX, y - 1);
        }
    }

    function drawSegmentBar(dc, x, y, width, height, percent, segments, markerPercent) {
        var filled = Math.floor(percent * segments / 100);
        if (filled > segments) { filled = segments; }
        if (filled < 0) { filled = 0; }
        for (var n = 0; n < segments; n += 1) {
            var left = x + ((width * n) / segments);
            var right = x + ((width * (n + 1)) / segments) - 2;
            var blockWidth = right - left;
            dc.drawRectangle(left, y, blockWidth, height);
            if (n < filled && blockWidth > 3) {
                dc.fillRectangle(left + 2, y + 2, blockWidth - 3, height - 4);
            }
        }
        if (markerPercent > 0) {
            var markerX = x + ((width * markerPercent) / 100);
            dc.drawLine(markerX, y - 4, markerX, y - 1);
        }
    }

    function drawCompact(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var center = w / 2;
        dc.drawText(center, 2, Graphics.FONT_NUMBER_MILD,
                    (_hasPower ? _power.format("%d") : "--") + " W",
                    Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(center, h - 35, Graphics.FONT_XTINY,
                    "F " + fuelPercent().format("%d") + "%  R " +
                    reservePercent().format("%d") + "%",
                    Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(center, h - 17, Graphics.FONT_XTINY,
                    currentCue(), Graphics.TEXT_JUSTIFY_CENTER);
    }
}
