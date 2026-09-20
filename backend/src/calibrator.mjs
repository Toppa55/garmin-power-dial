const OPENAI_URL = "https://api.openai.com/v1/responses";

const schema = {
  type: "object",
  additionalProperties: false,
  properties: {
    ftp_watts: { type: "integer", minimum: 50, maximum: 600 },
    ride_energy_budget_kj: { type: "integer", minimum: 100, maximum: 10000 },
    confidence: { type: "number", minimum: 0, maximum: 1 },
    rationale: { type: "string", minLength: 1, maxLength: 240 }
  },
  required: ["ftp_watts", "ride_energy_budget_kj", "confidence", "rationale"]
};

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

export function validateRequest(input) {
  if (!input || typeof input !== "object") throw new Error("A JSON request body is required");
  const rides = input.recent_rides;
  if (!Array.isArray(rides) || rides.length < 1 || rides.length > 20) {
    throw new Error("recent_rides must contain between 1 and 20 rides");
  }

  const recentRides = rides.map((ride, index) => {
    const duration = Number(ride.duration_minutes);
    const average = Number(ride.average_power_watts);
    const normalized = Number(ride.normalized_power_watts ?? average);
    if (!(duration > 0 && duration <= 1440 && average > 0 && average <= 1000 && normalized > 0 && normalized <= 1200)) {
      throw new Error(`recent_rides[${index}] contains invalid ride metrics`);
    }
    return {
      duration_minutes: duration,
      average_power_watts: average,
      normalized_power_watts: normalized
    };
  });

  const targetMinutes = Number(input.target_ride_minutes ?? 120);
  const ftpHint = input.ftp_hint_watts == null ? null : Number(input.ftp_hint_watts);
  if (!(targetMinutes >= 15 && targetMinutes <= 1440)) throw new Error("target_ride_minutes must be 15-1440");
  if (ftpHint != null && !(ftpHint >= 50 && ftpHint <= 600)) throw new Error("ftp_hint_watts must be 50-600");
  return { recent_rides: recentRides, target_ride_minutes: targetMinutes, ftp_hint_watts: ftpHint };
}

function extractText(response) {
  for (const item of response.output ?? []) {
    for (const content of item.content ?? []) {
      if (content.type === "output_text" && content.text) return content.text;
    }
  }
  throw new Error("OpenAI returned no structured calibration");
}

export async function calibrateFuel(input, options = {}) {
  const payload = validateRequest(input);
  const apiKey = options.apiKey ?? process.env.OPENAI_API_KEY;
  const model = options.model ?? process.env.OPENAI_MODEL ?? "gpt-5.6-luna";
  const fetchImpl = options.fetchImpl ?? fetch;
  if (!apiKey) throw new Error("OPENAI_API_KEY is not configured");

  const response = await fetchImpl(OPENAI_URL, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model,
      store: false,
      instructions: "Estimate a conservative cycling FTP and mechanical work budget for the target ride from the supplied recent ride summaries. Prefer observed sustained power. The work budget is the realistic total pedal work in kilojoules before the rider's dashboard fuel reaches empty. Do not give medical advice.",
      input: JSON.stringify(payload),
      text: {
        format: {
          type: "json_schema",
          name: "cycling_fuel_calibration",
          strict: true,
          schema
        }
      }
    })
  });

  const data = await response.json();
  if (!response.ok) throw new Error(data?.error?.message ?? `OpenAI request failed (${response.status})`);
  const result = JSON.parse(extractText(data));
  return {
    ftp_watts: Math.round(clamp(Number(result.ftp_watts), 50, 600)),
    ride_energy_budget_kj: Math.round(clamp(Number(result.ride_energy_budget_kj), 100, 10000)),
    confidence: clamp(Number(result.confidence), 0, 1),
    rationale: String(result.rationale).slice(0, 240),
    model
  };
}
