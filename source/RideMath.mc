using Toybox.Math;

class RideMath {
    hidden var _knots = [0, 50, 80, 100, 120, 150, 200, 300, 400];
    hidden var _positions = [0.0, 0.07, 0.20, 0.38, 0.58, 0.79, 0.90, 0.97, 1.0];

    function fraction(percent) {
        if (percent <= 0) { return 0.0; }
        for (var i = 1; i < _knots.size(); i += 1) {
            if (percent <= _knots[i]) {
                var t = (percent - _knots[i - 1]) / (_knots[i] - _knots[i - 1]).toFloat();
                return _positions[i - 1] + (t * (_positions[i] - _positions[i - 1]));
            }
        }
        return 1.0;
    }

    // FTP is used as a practical critical-power proxy. Work above FTP drains
    // reserve; riding below FTP refills it, increasingly slowly near FTP.
    function reserve(remaining, power, ftp, capacity, recoverySeconds, dt) {
        if (ftp <= 0 || dt <= 0 || dt > 5) { return remaining; }
        var next = remaining;
        if (power > ftp) {
            next -= (power - ftp) * dt;
        } else {
            var recoveryRate = (ftp - power) / ftp.toFloat();
            next += (capacity - next) * (1.0 - Math.pow(2.718281828, -dt * recoveryRate / recoverySeconds));
        }
        if (next < 0) { return 0.0; }
        if (next > capacity) { return capacity.toFloat(); }
        return next;
    }

    // Mechanical-work-equivalent fuel estimate. Extra cost above FTP makes
    // the slow tank sensitive to hard riding without treating it as glycogen.
    function totalFuel(remainingKj, power, ftp, dt) {
        if (dt <= 0 || dt > 3600 || ftp <= 0 || power <= 0) { return remainingKj; }
        var excess = (power / ftp.toFloat()) - 0.8;
        if (excess < 0) { excess = 0.0; }
        var costKj = (power * dt / 1000.0) * (1.0 + (0.2 * excess));
        var next = remainingKj - costKj;
        return next > 0 ? next : 0.0;
    }
}
