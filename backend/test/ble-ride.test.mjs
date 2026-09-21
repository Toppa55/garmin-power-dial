import assert from "node:assert/strict";
import test from "node:test";
import { advanceRide, parseHeartRateMeasurement, parsePowerMeasurement, quickCue } from "../public/ble-ride.mjs";

test("decodes standard cycling power and heart-rate notifications", () => {
  assert.equal(parsePowerMeasurement(new DataView(Uint8Array.from([0, 0, 250, 0]).buffer)), 250);
  assert.equal(parseHeartRateMeasurement(new DataView(Uint8Array.from([0, 148]).buffer)), 148);
  assert.equal(parseHeartRateMeasurement(new DataView(Uint8Array.from([1, 44, 1]).buffer)), 300);
  assert.throws(() => parsePowerMeasurement(new DataView(new ArrayBuffer(2))), /Invalid/);
});

test("fuel drains slowly while effort reserve recovers after a hard effort", () => {
  const start = { power_watts: 400, heart_rate_bpm: 170, fuel_percent: 100, reserve_percent: 100, elapsed_seconds: 0 };
  let state = start;
  for (let i = 0; i < 60; i++) state = advanceRide(state, 1, 250, 1600, 23);
  assert.ok(state.fuel_percent > 98);
  assert.ok(state.reserve_percent < 70);
  const drained = state.reserve_percent;
  state.power_watts = 50;
  for (let i = 0; i < 120; i++) state = advanceRide(state, 1, 250, 1600, 23);
  assert.ok(state.reserve_percent > drained);
  assert.equal(quickCue({ ...state, fuel_percent: 5 }, {}).cue, "EASE OFF");
});
