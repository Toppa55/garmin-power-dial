import assert from "node:assert/strict";
import test from "node:test";
import { calibrateFuel, validateRequest } from "../src/calibrator.mjs";

const sample = {
  target_ride_minutes: 150,
  ftp_hint_watts: 250,
  recent_rides: [
    { duration_minutes: 90, average_power_watts: 185, normalized_power_watts: 215 },
    { duration_minutes: 150, average_power_watts: 165, normalized_power_watts: 198 }
  ]
};

test("validates and normalizes ride metrics", () => {
  assert.deepEqual(validateRequest(sample), sample);
});

test("rejects impossible ride metrics", () => {
  assert.throws(() => validateRequest({ recent_rides: [{ duration_minutes: -1, average_power_watts: 200 }] }), /invalid ride metrics/);
});

test("requests structured calibration and clamps the response", async () => {
  let sent;
  const fetchImpl = async (_url, init) => {
    sent = JSON.parse(init.body);
    return {
      ok: true,
      json: async () => ({
        output: [{ content: [{ type: "output_text", text: JSON.stringify({
          ftp_watts: 248,
          ride_energy_budget_kj: 1520,
          confidence: 0.82,
          rationale: "Recent sustained power supports this conservative target."
        }) }] }]
      })
    };
  };

  const result = await calibrateFuel(sample, { apiKey: "test-key", model: "test-model", fetchImpl });
  assert.equal(sent.store, false);
  assert.equal(sent.text.format.type, "json_schema");
  assert.equal(result.ftp_watts, 248);
  assert.equal(result.ride_energy_budget_kj, 1520);
  assert.equal(result.model, "test-model");
});
