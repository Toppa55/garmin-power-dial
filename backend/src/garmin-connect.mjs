function required(name, env = process.env) {
  if (!env[name]) throw new Error(`${name} is not configured; Garmin Developer Program approval is required`);
  return env[name];
}

export function createAuthorizationUrl({ state, redirectUri, env = process.env }) {
  const url = new URL(required("GARMIN_AUTHORIZE_URL", env));
  url.searchParams.set("response_type", "code");
  url.searchParams.set("client_id", required("GARMIN_CLIENT_ID", env));
  url.searchParams.set("redirect_uri", redirectUri);
  url.searchParams.set("state", state);
  url.searchParams.set("scope", required("GARMIN_SCOPES", env));
  return url.toString();
}

export async function exchangeAuthorizationCode({ code, redirectUri, env = process.env, fetchImpl = fetch }) {
  const body = new URLSearchParams({
    grant_type: "authorization_code",
    code,
    redirect_uri: redirectUri,
    client_id: required("GARMIN_CLIENT_ID", env),
    client_secret: required("GARMIN_CLIENT_SECRET", env)
  });
  const response = await fetchImpl(required("GARMIN_TOKEN_URL", env), {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body
  });
  const data = await response.json();
  if (!response.ok) throw new Error(data.error_description ?? data.error ?? `Garmin token request failed (${response.status})`);
  return { ...data, obtained_at: Date.now() };
}

export async function refreshAccessToken({ refreshToken, env = process.env, fetchImpl = fetch }) {
  const body = new URLSearchParams({
    grant_type: "refresh_token",
    refresh_token: refreshToken,
    client_id: required("GARMIN_CLIENT_ID", env),
    client_secret: required("GARMIN_CLIENT_SECRET", env)
  });
  const response = await fetchImpl(required("GARMIN_TOKEN_URL", env), {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body
  });
  const data = await response.json();
  if (!response.ok) throw new Error(data.error_description ?? data.error ?? `Garmin token refresh failed (${response.status})`);
  return { ...data, refresh_token: data.refresh_token ?? refreshToken, obtained_at: Date.now() };
}

export function normalizeGarminActivity(activity) {
  const durationSeconds = Number(activity.durationInSeconds ?? activity.duration_seconds ?? activity.duration ?? 0);
  const averagePower = Number(activity.averagePowerInWatts ?? activity.average_power_watts ?? activity.averagePower ?? 0);
  if (!(durationSeconds > 0 && averagePower > 0)) return null;
  return {
    started_at: activity.startTimeInSeconds ? new Date(Number(activity.startTimeInSeconds) * 1000).toISOString() : (activity.started_at ?? activity.startTimeLocal ?? null),
    duration_minutes: durationSeconds / 60,
    average_power_watts: averagePower,
    normalized_power_watts: Number(activity.normalizedPowerInWatts ?? activity.normalized_power_watts ?? activity.normalizedPower ?? averagePower),
    average_heart_rate_bpm: activity.averageHeartRateInBeatsPerMinute ?? activity.average_heart_rate_bpm ?? activity.averageHeartRate ?? null,
    max_heart_rate_bpm: activity.maxHeartRateInBeatsPerMinute ?? activity.max_heart_rate_bpm ?? activity.maxHeartRate ?? null,
    work_kj: Number(activity.workInKilojoules ?? activity.work_kj ?? ((averagePower * durationSeconds) / 1000))
  };
}

export async function fetchCompleteActivityHistory({ accessToken, env = process.env, fetchImpl = fetch }) {
  let url = required("GARMIN_ACTIVITY_BACKFILL_URL", env);
  const rides = [];
  const visited = new Set();
  while (url) {
    if (visited.has(url)) throw new Error("Garmin activity pagination returned a cycle");
    visited.add(url);
    const response = await fetchImpl(url, { headers: { "Authorization": `Bearer ${accessToken}`, "Accept": "application/json" } });
    const data = await response.json();
    if (!response.ok) throw new Error(data.error ?? `Garmin activity request failed (${response.status})`);
    const activities = Array.isArray(data) ? data : (data.activities ?? data.items ?? []);
    for (const activity of activities) {
      const normalized = normalizeGarminActivity(activity);
      if (normalized) rides.push(normalized);
    }
    url = Array.isArray(data) ? null : (data.next ?? data.next_page_url ?? null);
  }
  if (!rides.length) throw new Error("Garmin Connect returned no cycling activities with power data");
  return rides;
}
