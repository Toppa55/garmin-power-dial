import { openAiJson } from "./openai-json.mjs";

const clamp = (value, min, max) => Math.min(max, Math.max(min, value));
const sessions = new Map();

const cueSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    cue: { type: "string", minLength: 2, maxLength: 12 },
    reason: { type: "string", minLength: 1, maxLength: 160 }
  },
  required: ["cue", "reason"]
};

export function validateLiveState(input) {
  if (!input || typeof input !== "object" || !input.rider_id) throw new Error("rider_id is required");
  const number = (key, fallback = 0) => {
    const value = Number(input[key] ?? fallback);
    if (!Number.isFinite(value)) throw new Error(`${key} must be numeric`);
    return value;
  };
  const state = {
    rider_id: String(input.rider_id), session_id: String(input.session_id ?? "ride"),
    timestamp: String(input.timestamp ?? new Date().toISOString()),
    elapsed_seconds: clamp(number("elapsed_seconds"), 0, 86400),
    power_watts: clamp(number("power_watts"), 0, 2000),
    heart_rate_bpm: clamp(number("heart_rate_bpm"), 0, 250),
    cadence_rpm: clamp(number("cadence_rpm"), 0, 250),
    temperature_c: clamp(number("temperature_c", 20), -20, 60),
    reserve_percent: clamp(number("reserve_percent", 100), 0, 100),
    fuel_percent: clamp(number("fuel_percent", 100), 0, 100),
    carbs_grams: clamp(number("carbs_grams"), 0, 500),
    sleep_hours: clamp(number("sleep_hours", 8), 0, 24),
    night_shift: Boolean(input.night_shift),
    perceived_effort: input.perceived_effort == null ? null : clamp(number("perceived_effort"), 1, 10)
  };
  return state;
}

export function predictLive(state, profile = {}) {
  const ftp = clamp(Number(profile.ftp_watts ?? 250), 50, 600);
  const resting = clamp(Number(profile.resting_hr_bpm ?? 60), 30, 120);
  const threshold = clamp(Number(profile.threshold_hr_bpm ?? 170), resting + 10, 220);
  const powerRatio = state.power_watts / ftp;
  const expectedHr = Math.round(resting + (threshold - resting) * clamp(powerRatio, 0, 1));
  const hrDelta = state.heart_rate_bpm > 0 ? state.heart_rate_bpm - expectedHr : 0;
  const thermalStrain = clamp((state.temperature_c - 22) * 1.6, 0, 30);
  const sleepPenalty = clamp((7 - state.sleep_hours) * 6 + (state.night_shift ? 10 : 0), 0, 35);
  const fatigue = clamp((100 - state.reserve_percent) * 0.55 + Math.max(0, hrDelta) * 1.2 + thermalStrain + sleepPenalty, 0, 100);
  let targetRatio = fatigue > 75 ? 0.55 : fatigue > 50 ? 0.70 : 0.88;
  if (state.elapsed_seconds < 600) targetRatio = Math.min(targetRatio, 0.72);
  const target = Math.round(ftp * targetRatio);
  const targetLow = Math.round(target * 0.94);
  const targetHigh = Math.round(target * 1.06);
  const risk = state.fuel_percent < 10 || state.reserve_percent < 12 || hrDelta > 18 || fatigue > 85 ? "HIGH" : fatigue > 60 || hrDelta > 10 ? "MED" : "LOW";
  const confidence = Math.round(clamp(Number(profile.confidence ?? 0.45) * 100 - (state.heart_rate_bpm ? 0 : 20) - (state.cadence_rpm ? 0 : 5), 20, 98));
  const minutes = state.elapsed_seconds / 60;
  const carbRate = state.power_watts > ftp * 0.75 ? 70 : 45;
  const carbsExpected = carbRate * minutes / 60;
  const carbsDue = Math.max(0, Math.round(carbsExpected - state.carbs_grams));
  const drinkMinutes = Math.max(0, 15 - (Math.floor(minutes) % 15));
  let cue = "HOLD";
  if (risk === "HIGH") cue = "EASE OFF";
  else if (carbsDue >= 20) cue = "TAKE CARBS";
  else if (drinkMinutes <= 1) cue = "DRINK";
  else if (state.power_watts < targetLow) cue = "PUSH";
  else if (state.power_watts > targetHigh) cue = "EASE";
  const reserveKj = Math.round(clamp(Number(profile.hard_effort_reserve_kj ?? ftp * 0.09), 10, 45));
  return { cue, targetLow, targetHigh, risk, confidence, expectedHr, hrDelta, fatigue: Math.round(fatigue), carbsDue, drinkMinutes, ftp, reserveKj };
}

export async function coachLive(input, profile, options = {}) {
  const state = validateLiveState(input);
  const prediction = predictLive(state, profile);
  const key = `${state.rider_id}:${state.session_id}`;
  const prior = sessions.get(key);
  const now = Date.now();
  const meaningful = !prior || prior.prediction.risk !== prediction.risk ||
    Math.abs(prior.prediction.hrDelta - prediction.hrDelta) >= 8 ||
    now - prior.attemptAt >= 60000;
  let reason = "Local prediction updated from live power, heart rate, reserve, heat, sleep, and shift context.";
  let aiUsed = false;
  let attempted = false;
  if (meaningful && options.useAi !== false && (options.apiKey ?? process.env.OPENAI_API_KEY)) {
    attempted = true;
    try {
      const ai = await openAiJson({
        instructions: "You are a conservative live cycling coach. Return one glanceable cue of at most 12 characters and a short reason. Use the numerical prediction and learned history. Never diagnose illness. Prefer HOLD, PUSH, EASE, DRINK, TAKE CARBS, COOL DOWN, or STOP SAFE.",
        input: { state, prediction, learned_profile: profile, previous: prior?.prediction ?? null },
        schema: cueSchema, name: "live_cycling_cue", apiKey: options.apiKey, fetchImpl: options.fetchImpl
      });
      prediction.cue = String(ai.cue).toUpperCase().slice(0, 12);
      reason = String(ai.reason).slice(0, 160);
      aiUsed = true;
    } catch (error) {
      reason = `Offline fallback: ${error.message}`.slice(0, 160);
    }
  } else if (prior?.aiUsed) {
    prediction.cue = prior.prediction.cue;
    reason = prior.reason;
    aiUsed = true;
  }
  sessions.set(key, { prediction, reason, aiUsed, attemptAt: attempted ? now : (prior?.attemptAt ?? now) });
  return { ...prediction, reason, aiUsed, at: state.timestamp };
}

export function clearLiveSession(riderId, sessionId) {
  sessions.delete(`${riderId}:${sessionId}`);
}
