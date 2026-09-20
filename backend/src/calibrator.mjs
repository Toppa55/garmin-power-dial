const OPENAI_URL = "https://api.openai.com/v1/responses";

const schema = {
  type: "object",
  additionalProperties: false,
  properties: {
    ftp_watts: { type: "integer", minimum: 50, maximum: 600 },
    ride_energy_budget_kj: { type: "integer", minimum: 100, maximum: 10000 },
    resting_hr_bpm: { type: "integer", minimum: 30, maximum: 120 },
    threshold_hr_bpm: { type: "integer", minimum: 80, maximum: 220 },
    max_hr_bpm: { type: "integer", minimum: 100, maximum: 240 },
    decoupling_warning_percent: { type: "integer", minimum: 3, maximum: 30 },
    confidence: { type: "number", minimum: 0, maximum: 1 },
    rationale: { type: "string", minLength: 1, maxLength: 300 }
  },
  required: ["ftp_watts", "ride_energy_budget_kj", "resting_hr_bpm", "threshold_hr_bpm", "max_hr_bpm", "decoupling_warning_percent", "confidence", "rationale"]
};

const clamp = (value, min, max) => Math.min(max, Math.max(min, value));

export function validateRequest(input) {
  if (!input || typeof input !== "object") throw new Error("A JSON request body is required");
  const source = input.ride_history ?? input.recent_rides;
  if (!Array.isArray(source) || source.length < 1 || source.length > 5000) {
    throw new Error("ride_history must contain between 1 and 5000 Garmin Connect rides");
  }

  const rideHistory = source.map((ride, index) => {
    const duration = Number(ride.duration_minutes);
    const average = Number(ride.average_power_watts);
    const normalized = Number(ride.normalized_power_watts ?? average);
    const averageHr = ride.average_heart_rate_bpm == null ? null : Number(ride.average_heart_rate_bpm);
    const maxHr = ride.max_heart_rate_bpm == null ? null : Number(ride.max_heart_rate_bpm);
    if (!(duration > 0 && duration <= 1440 && average > 0 && average <= 1000 && normalized > 0 && normalized <= 1200)) {
      throw new Error(`ride_history[${index}] contains invalid power or duration metrics`);
    }
    if (averageHr != null && !(averageHr >= 30 && averageHr <= 240)) throw new Error(`ride_history[${index}] contains invalid heart-rate metrics`);
    if (maxHr != null && !(maxHr >= 30 && maxHr <= 250)) throw new Error(`ride_history[${index}] contains invalid heart-rate metrics`);
    return {
      started_at: ride.started_at == null ? null : String(ride.started_at),
      duration_minutes: duration,
      average_power_watts: average,
      normalized_power_watts: normalized,
      average_heart_rate_bpm: averageHr,
      max_heart_rate_bpm: maxHr,
      work_kj: Number(ride.work_kj ?? ((average * duration * 60) / 1000))
    };
  });

  const targetMinutes = Number(input.target_ride_minutes ?? 120);
  const ftpHint = input.ftp_hint_watts == null ? null : Number(input.ftp_hint_watts);
  if (!(targetMinutes >= 15 && targetMinutes <= 1440)) throw new Error("target_ride_minutes must be 15-1440");
  if (ftpHint != null && !(ftpHint >= 50 && ftpHint <= 600)) throw new Error("ftp_hint_watts must be 50-600");
  return { ride_history: rideHistory, target_ride_minutes: targetMinutes, ftp_hint_watts: ftpHint, previous_profile: input.previous_profile ?? null };
}

function weightedAverage(rides, field) {
  let weighted = 0;
  let duration = 0;
  for (const ride of rides) {
    if (ride[field] != null) {
      weighted += ride[field] * ride.duration_minutes;
      duration += ride.duration_minutes;
    }
  }
  return duration > 0 ? weighted / duration : null;
}

export function summarizeHistory(rides) {
  const ordered = [...rides].sort((a, b) => String(a.started_at ?? "").localeCompare(String(b.started_at ?? "")));
  const quarter = Math.max(1, Math.floor(ordered.length / 4));
  const earliest = ordered.slice(0, quarter);
  const latest = ordered.slice(-quarter);
  const heartRides = ordered.filter((ride) => ride.average_heart_rate_bpm != null);
  const totalMinutes = ordered.reduce((sum, ride) => sum + ride.duration_minutes, 0);
  const totalWork = ordered.reduce((sum, ride) => sum + ride.work_kj, 0);
  const firstNp = weightedAverage(earliest, "normalized_power_watts");
  const latestNp = weightedAverage(latest, "normalized_power_watts");
  return {
    rides_analyzed: ordered.length,
    rides_with_heart_rate: heartRides.length,
    total_duration_hours: Math.round((totalMinutes / 60) * 10) / 10,
    total_work_kj: Math.round(totalWork),
    duration_weighted_average_power_watts: Math.round(weightedAverage(ordered, "average_power_watts")),
    duration_weighted_normalized_power_watts: Math.round(weightedAverage(ordered, "normalized_power_watts")),
    duration_weighted_average_hr_bpm: heartRides.length ? Math.round(weightedAverage(heartRides, "average_heart_rate_bpm")) : null,
    peak_observed_normalized_power_watts: Math.round(Math.max(...ordered.map((ride) => ride.normalized_power_watts))),
    peak_observed_hr_bpm: heartRides.length ? Math.round(Math.max(...heartRides.map((ride) => ride.max_heart_rate_bpm ?? ride.average_heart_rate_bpm))) : null,
    normalized_power_trend_watts: Math.round((latestNp ?? 0) - (firstNp ?? 0)),
    latest_quarter_average_power_watts: Math.round(weightedAverage(latest, "average_power_watts")),
    latest_quarter_average_hr_bpm: latest.some((ride) => ride.average_heart_rate_bpm != null) ? Math.round(weightedAverage(latest, "average_heart_rate_bpm")) : null
  };
}

function extractText(response) {
  for (const item of response.output ?? []) {
    for (const content of item.content ?? []) {
      if (content.type === "output_text" && content.text) return content.text;
    }
  }
  throw new Error("OpenAI returned no structured rider profile");
}

export async function calibrateFuel(input, options = {}) {
  const payload = validateRequest(input);
  const historySummary = summarizeHistory(payload.ride_history);
  const apiKey = options.apiKey ?? process.env.OPENAI_API_KEY;
  const model = options.model ?? process.env.OPENAI_MODEL ?? "gpt-5.6-luna";
  const fetchImpl = options.fetchImpl ?? fetch;
  if (!apiKey) throw new Error("OPENAI_API_KEY is not configured");

  const response = await fetchImpl(OPENAI_URL, {
    method: "POST",
    headers: { "Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model,
      store: false,
      instructions: "Create a conservative cycling rider profile from the complete Garmin Connect history summary. Infer sustainable FTP, target-ride mechanical work budget, and heart-rate thresholds for live power-versus-HR feedback. Use the previous profile as a prior when present, but update it when the complete history supports a change. Missing HR history must reduce confidence. Do not give medical advice.",
      input: JSON.stringify({
        complete_history_summary: historySummary,
        target_ride_minutes: payload.target_ride_minutes,
        ftp_hint_watts: payload.ftp_hint_watts,
        previous_profile: payload.previous_profile
      }),
      text: { format: { type: "json_schema", name: "cycling_rider_profile", strict: true, schema } }
    })
  });

  const data = await response.json();
  if (!response.ok) throw new Error(data?.error?.message ?? `OpenAI request failed (${response.status})`);
  const result = JSON.parse(extractText(data));
  const resting = Math.round(clamp(Number(result.resting_hr_bpm), 30, 120));
  const maximum = Math.round(clamp(Number(result.max_hr_bpm), Math.max(resting + 20, 100), 240));
  const threshold = Math.round(clamp(Number(result.threshold_hr_bpm), resting + 10, maximum - 1));
  return {
    ftp_watts: Math.round(clamp(Number(result.ftp_watts), 50, 600)),
    ride_energy_budget_kj: Math.round(clamp(Number(result.ride_energy_budget_kj), 100, 10000)),
    hard_effort_reserve_kj: Math.round(clamp(Number(result.ftp_watts) * 0.09, 10, 45)),
    resting_hr_bpm: resting,
    threshold_hr_bpm: threshold,
    max_hr_bpm: maximum,
    decoupling_warning_percent: Math.round(clamp(Number(result.decoupling_warning_percent), 3, 30)),
    confidence: clamp(Number(result.confidence), 0, 1),
    rationale: String(result.rationale).slice(0, 300),
    rides_analyzed: historySummary.rides_analyzed,
    learning_revision: Number(payload.previous_profile?.learning_revision ?? 0) + 1,
    model
  };
}
