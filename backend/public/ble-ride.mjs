export function parsePowerMeasurement(value) {
  if (!(value instanceof DataView) || value.byteLength < 4) throw new Error("Invalid cycling power packet");
  return value.getInt16(2, true);
}

export function parseHeartRateMeasurement(value) {
  if (!(value instanceof DataView) || value.byteLength < 2) throw new Error("Invalid heart-rate packet");
  const wide = (value.getUint8(0) & 1) !== 0;
  if (wide && value.byteLength < 3) throw new Error("Incomplete heart-rate packet");
  return wide ? value.getUint16(1, true) : value.getUint8(1);
}

export function advanceRide(state, seconds, ftp = 250, fuelBudgetKj = 1600, reserveKj = 23) {
  const dt = Math.max(0, Math.min(10, Number(seconds) || 0));
  const watts = Math.max(0, Number(state.power_watts) || 0);
  const reserve = Math.max(0, Math.min(100, Number(state.reserve_percent) || 0));
  const fuel = Math.max(0, Math.min(100, Number(state.fuel_percent) || 0));
  const nextFuel = Math.max(0, fuel - watts * dt / (Math.max(1, fuelBudgetKj) * 10));
  const nextReserve = watts > ftp
    ? Math.max(0, reserve - (watts - ftp) * dt / (Math.max(1, reserveKj) * 10))
    : Math.min(100, reserve + (100 - reserve) * (1 - Math.exp(-dt * Math.max(0.15, 1 - watts / Math.max(1, ftp)) / 180)));
  return { ...state, fuel_percent: nextFuel, reserve_percent: nextReserve,
    elapsed_seconds: (Number(state.elapsed_seconds) || 0) + dt };
}

export function quickCue(state, profile = {}) {
  const ftp = Math.max(50, Number(profile.ftp_watts) || 250);
  const resting = Math.max(30, Number(profile.resting_hr_bpm) || 60);
  const threshold = Math.max(resting + 10, Number(profile.threshold_hr_bpm) || 170);
  const expectedHr = Math.round(resting + (threshold - resting) * Math.min(1, Math.max(0, state.power_watts / ftp)));
  const hrDelta = state.heart_rate_bpm > 0 ? state.heart_rate_bpm - expectedHr : 0;
  let cue = "HOLD";
  if (state.fuel_percent < 10 || state.reserve_percent < 12 || hrDelta > 18) cue = "EASE OFF";
  else if (state.reserve_percent < 30) cue = "RECOVER";
  else if (state.power_watts > ftp * 1.2) cue = "HARD";
  return { cue, expectedHr, hrDelta, ftp, risk: cue === "EASE OFF" ? "HIGH" : "LOW",
    reason: "Live sensor estimate; coaching is refined when the server responds." };
}
