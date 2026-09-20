import { openAiJson } from "./openai-json.mjs";

const planSchema = {
  type: "object", additionalProperties: false,
  properties: {
    recommendation: { type: "string", minLength: 1, maxLength: 500 },
    session_type: { type: "string", enum: ["REST", "RECOVERY", "ENDURANCE", "TEMPO", "INTERVALS", "RACE"] },
    duration_minutes: { type: "integer", minimum: 0, maximum: 600 },
    target_power_low: { type: "integer", minimum: 0, maximum: 1000 },
    target_power_high: { type: "integer", minimum: 0, maximum: 1200 },
    confidence: { type: "integer", minimum: 0, maximum: 100 }
  },
  required: ["recommendation", "session_type", "duration_minutes", "target_power_low", "target_power_high", "confidence"]
};

export async function createPlan({ profile, context, question = "What should I do today?" }, options = {}) {
  return openAiJson({
    instructions: "Act as a practical cycling training and recovery planner. Maximize performance within the rider's actual calendar. Account for sleep, work, night shifts, available training windows, recent Garmin history summary, preferences, and the rider's question. Give one safe concrete recommendation. A post-night-shift session should only be hard when recovery evidence supports it. Do not diagnose medical conditions.",
    input: { learned_profile: profile, rider_context: context, question }, schema: planSchema,
    name: "cycling_daily_plan", apiKey: options.apiKey, fetchImpl: options.fetchImpl
  });
}
