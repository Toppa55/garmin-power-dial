import assert from "node:assert/strict";
import test from "node:test";
import { calibrateFuel, summarizeHistory, validateRequest } from "../src/calibrator.mjs";

const rides = Array.from({ length: 100 }, (_, index) => ({
  started_at: `2026-01-${String((index % 28) + 1).padStart(2, "0")}T08:00:00Z`,
  duration_minutes: 60 + index,
  average_power_watts: 160 + (index % 30),
  normalized_power_watts: 190 + (index % 35),
  average_heart_rate_bpm: 135 + (index % 15),
  max_heart_rate_bpm: 170 + (index % 10)
}));

test("validates a complete Garmin Connect ride history", () => {
  assert.equal(validateRequest({ ride_history: rides }).ride_history.length, 100);
});

test("every ride contributes to the longitudinal summary", () => {
  const summary = summarizeHistory(validateRequest({ ride_history: rides }).ride_history);
  assert.equal(summary.rides_analyzed, 100);
  assert.ok(summary.total_duration_hours > 100);
  assert.ok(summary.total_work_kj > 0);
  assert.equal(summary.rides_with_heart_rate, 100);
});

test("rejects impossible ride metrics", () => {
  assert.throws(() => validateRequest({ ride_history: [{ duration_minutes: -1, average_power_watts: 200 }] }), /invalid power or duration/);
});

test("requests a structured learned profile and increments its revision", async () => {
  let sent;
  const fetchImpl = async (_url, init) => {
    sent = JSON.parse(init.body);
    return {
      ok: true,
      json: async () => ({ output: [{ content: [{ type: "output_text", text: JSON.stringify({
        ftp_watts: 248,
        ride_energy_budget_kj: 1520,
        resting_hr_bpm: 57,
        threshold_hr_bpm: 168,
        max_hr_bpm: 188,
        decoupling_warning_percent: 8,
        confidence: 0.88,
        rationale: "The complete history supports a stable aerobic profile."
      }) }] }] })
    };
  };

  const result = await calibrateFuel({ ride_history: rides, previous_profile: { learning_revision: 4 } }, { apiKey: "test-key", model: "test-model", fetchImpl });
  const modelInput = JSON.parse(sent.input);
  assert.equal(sent.store, false);
  assert.equal(sent.text.format.type, "json_schema");
  assert.equal(modelInput.complete_history_summary.rides_analyzed, 100);
  assert.equal(result.learning_revision, 5);
  assert.equal(result.threshold_hr_bpm, 168);
});
