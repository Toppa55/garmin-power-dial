import assert from "node:assert/strict";
import test from "node:test";
import { coachLive, predictLive, validateLiveState } from "../src/live-coach.mjs";

const profile = { ftp_watts: 250, resting_hr_bpm: 55, threshold_hr_bpm: 170, confidence: 0.9 };

test("compares live heart rate with the expected response to current power", () => {
  const state = validateLiveState({ rider_id: "r", power_watts: 200, heart_rate_bpm: 170, cadence_rpm: 90, temperature_c: 30, reserve_percent: 60 });
  const result = predictLive(state, profile);
  assert.ok(result.hrDelta > 15);
  assert.equal(result.risk, "HIGH");
  assert.ok(result.targetHigh < profile.ftp_watts);
});

test("keeps useful deterministic feedback when AI is unavailable", async () => {
  const result = await coachLive({ rider_id: "r", session_id: "offline", power_watts: 100, heart_rate_bpm: 110, reserve_percent: 80 }, profile, { useAi: false });
  assert.equal(result.aiUsed, false);
  assert.ok(["PUSH", "HOLD", "EASE", "DRINK", "TAKE CARBS", "EASE OFF"].includes(result.cue));
  assert.equal(typeof result.confidence, "number");
});
