import assert from "node:assert/strict";
import test from "node:test";
import { normalizeFitSession, normalizedPower } from "../src/fit-history.mjs";

test("hard efforts increase normalized power above steady riding", () => {
  const steady = normalizedPower(Array.from({ length: 120 }, () => ({ power: 200 })));
  const surges = normalizedPower(Array.from({ length: 120 }, (_, i) => ({ power: i < 60 ? 100 : 300 })));
  assert.equal(steady, 200);
  assert.ok(surges > 200);
});

test("Edge FIT sessions retain power, heart rate and work without location", () => {
  const ride = normalizeFitSession({
    sport: "cycling", startTime: new Date("2026-09-20T06:00:00Z"),
    totalTimerTime: 3600, avgPower: 200, totalWork: 720000,
    avgHeartRate: 145, maxHeartRate: 180,
    startPositionLat: 123, startPositionLong: 456
  });
  assert.equal(ride.work_kj, 720);
  assert.equal(ride.average_heart_rate_bpm, 145);
  assert.equal(ride.duration_minutes, 60);
  assert.ok(!("startPositionLat" in ride));
});
