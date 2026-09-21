import { randomUUID } from "node:crypto";
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { calibrateFuel } from "./calibrator.mjs";
import { loadConnection, saveConnection } from "./connection-store.mjs";
import { createAuthorizationUrl, exchangeAuthorizationCode, fetchCompleteActivityHistory, refreshAccessToken } from "./garmin-connect.mjs";
import { loadProfile, saveProfile } from "./profile-store.mjs";
import { clearLiveSession, coachLive } from "./live-coach.mjs";
import { loadJson, saveJson } from "./json-store.mjs";
import { createPlan } from "./planner.mjs";

const port = Number(process.env.PORT ?? 8787);
const host = process.env.HOST ?? "127.0.0.1";
const token = process.env.COMPANION_TOKEN;
const pendingAuthorizations = new Map();
const dashboardPath = fileURLToPath(new URL("../public/index.html", import.meta.url));
const phonePath = fileURLToPath(new URL("../public/phone.html", import.meta.url));
const bleRidePath = fileURLToPath(new URL("../public/ble-ride.mjs", import.meta.url));
const manifestPath = fileURLToPath(new URL("../public/manifest.webmanifest", import.meta.url));
const iconPath = fileURLToPath(new URL("../public/icon.svg", import.meta.url));

function send(response, status, body) {
  response.writeHead(status, { "Content-Type": "application/json", "Cache-Control": "no-store" });
  response.end(JSON.stringify(body));
}

function isAuthorized(request) {
  return Boolean(token && request.headers.authorization === `Bearer ${token}`);
}

async function readJson(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > 2 * 1024 * 1024) throw new Error("Request body is too large");
    chunks.push(chunk);
  }
  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
}

async function learnFromGarmin(riderId, connection, targetRideMinutes = 120, ftpHintWatts = null) {
  const rideHistory = await fetchCompleteActivityHistory({ accessToken: connection.access_token });
  const previousProfile = await loadProfile(riderId);
  const profile = await calibrateFuel({
    ride_history: rideHistory,
    target_ride_minutes: targetRideMinutes,
    ftp_hint_watts: ftpHintWatts,
    previous_profile: previousProfile
  });
  await saveProfile(riderId, profile);
  return profile;
}

const server = createServer(async (request, response) => {
  const url = new URL(request.url, `http://${request.headers.host ?? "127.0.0.1"}`);
  if (request.method === "GET" && url.pathname === "/health") return send(response, 200, { ok: true });
  if (request.method === "GET" && url.pathname === "/") {
    response.writeHead(200, { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" });
    response.end(await readFile(dashboardPath));
    return;
  }
  if (request.method === "GET" && url.pathname === "/phone") {
    response.writeHead(200, { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" });
    response.end(await readFile(phonePath));
    return;
  }
  if (request.method === "GET" && url.pathname === "/ble-ride.mjs") {
    response.writeHead(200, { "Content-Type": "text/javascript; charset=utf-8", "Cache-Control": "no-store" });
    response.end(await readFile(bleRidePath));
    return;
  }
  if (request.method === "GET" && url.pathname === "/manifest.webmanifest") {
    response.writeHead(200, { "Content-Type": "application/manifest+json", "Cache-Control": "no-store" });
    response.end(await readFile(manifestPath));
    return;
  }
  if (request.method === "GET" && url.pathname === "/icon.svg") {
    response.writeHead(200, { "Content-Type": "image/svg+xml", "Cache-Control": "public, max-age=86400" });
    response.end(await readFile(iconPath));
    return;
  }

  try {
    if (request.method === "GET" && url.pathname === "/v1/garmin/callback") {
      const pending = pendingAuthorizations.get(url.searchParams.get("state"));
      if (!pending) return send(response, 400, { error: "Garmin authorization state is invalid or expired" });
      pendingAuthorizations.delete(url.searchParams.get("state"));
      if (Date.now() - pending.created_at > 10 * 60 * 1000) return send(response, 400, { error: "Garmin authorization state is invalid or expired" });
      const connection = await exchangeAuthorizationCode({ code: url.searchParams.get("code"), redirectUri: pending.redirect_uri });
      await saveConnection(pending.rider_id, connection);
      const profile = await learnFromGarmin(pending.rider_id, connection, pending.target_ride_minutes, pending.ftp_hint_watts);
      return send(response, 200, { connected: true, profile });
    }

    if (!isAuthorized(request)) return send(response, 401, { error: "Unauthorized" });

    if (request.method === "POST" && url.pathname === "/v1/garmin/connect") {
      const input = await readJson(request);
      if (!input.rider_id || !input.redirect_uri) throw new Error("rider_id and redirect_uri are required");
      const state = randomUUID();
      pendingAuthorizations.set(state, {
        rider_id: String(input.rider_id),
        redirect_uri: String(input.redirect_uri),
        target_ride_minutes: Number(input.target_ride_minutes ?? 120),
        ftp_hint_watts: input.ftp_hint_watts ?? null,
        created_at: Date.now()
      });
      return send(response, 200, { authorization_url: createAuthorizationUrl({ state, redirectUri: input.redirect_uri }) });
    }

    if (request.method === "POST" && url.pathname === "/v1/garmin/sync") {
      const input = await readJson(request);
      let connection = await loadConnection(String(input.rider_id));
      if (!connection) return send(response, 404, { error: "Garmin Connect is not linked for this rider" });
      const expiresAt = connection.obtained_at + (Number(connection.expires_in ?? 3600) * 1000);
      if (Date.now() >= expiresAt - 60000 && connection.refresh_token) {
        connection = await refreshAccessToken({ refreshToken: connection.refresh_token });
        await saveConnection(String(input.rider_id), connection);
      }
      const profile = await learnFromGarmin(String(input.rider_id), connection, Number(input.target_ride_minutes ?? 120), input.ftp_hint_watts ?? null);
      return send(response, 200, profile);
    }

    if (request.method === "GET" && url.pathname === "/v1/profile") {
      const profile = await loadProfile(url.searchParams.get("rider_id"));
      return profile ? send(response, 200, profile) : send(response, 404, { error: "No learned profile" });
    }

    if (request.method === "POST" && url.pathname === "/v1/calibrate") {
      const input = await readJson(request);
      const profile = await calibrateFuel(input);
      if (input.rider_id) await saveProfile(String(input.rider_id), profile);
      return send(response, 200, profile);
    }

    if (request.method === "POST" && url.pathname === "/v1/context") {
      const input = await readJson(request);
      if (!input.rider_id) throw new Error("rider_id is required");
      const context = {
        sleep_hours: Math.max(0, Math.min(24, Number(input.sleep_hours ?? 8))),
        night_shift: Boolean(input.night_shift),
        available_minutes: Math.max(0, Math.min(1440, Number(input.available_minutes ?? 0))),
        schedule: String(input.schedule ?? "").slice(0, 4000),
        recovery_coaching: input.recovery_coaching !== false
      };
      await saveJson("contexts", String(input.rider_id), context);
      return send(response, 200, context);
    }

    if (request.method === "GET" && url.pathname === "/v1/context") {
      const context = await loadJson("contexts", url.searchParams.get("rider_id"));
      return send(response, 200, context ?? {});
    }

    if (request.method === "POST" && url.pathname === "/v1/plan") {
      const input = await readJson(request);
      if (!input.rider_id) throw new Error("rider_id is required");
      const [profile, context] = await Promise.all([
        loadProfile(String(input.rider_id)), loadJson("contexts", String(input.rider_id))
      ]);
      if (!profile) return send(response, 404, { error: "Sync or calibrate Garmin history before requesting a plan" });
      return send(response, 200, await createPlan({ profile, context: context ?? {}, question: String(input.question ?? "What should I do today?") }));
    }

    if (request.method === "POST" && url.pathname === "/v1/live/state") {
      const input = await readJson(request);
      const profile = await loadProfile(String(input.rider_id));
      const result = await coachLive(input, profile ?? {});
      await saveJson("live", `${input.rider_id}:${input.session_id ?? "ride"}`, { state: input, prediction: result });
      await saveJson("latest", String(input.rider_id), { state: input, prediction: result });
      return send(response, 200, result);
    }

    if (request.method === "POST" && url.pathname === "/v1/edge/poll") {
      const input = await readJson(request);
      const profile = await loadProfile(String(input.rider_id));
      const result = await coachLive(input, profile ?? {});
      await saveJson("latest", String(input.rider_id), { state: input, prediction: result, source: "edge" });
      return send(response, 200, {
        cue: result.cue, targetLow: result.targetLow, targetHigh: result.targetHigh,
        risk: result.risk, confidence: result.confidence, ftp: result.ftp,
        reserveKj: result.reserveKj,
        totalFuelKj: Number(profile?.ride_energy_budget_kj ?? 1600),
        ttlSeconds: 360
      });
    }

    if (request.method === "GET" && url.pathname === "/v1/live/latest") {
      const riderId = url.searchParams.get("rider_id");
      if (!riderId) throw new Error("rider_id is required");
      const latest = await loadJson("latest", riderId);
      return latest ? send(response, 200, latest) : send(response, 404, { error: "No live ride state yet" });
    }

    if (request.method === "POST" && url.pathname === "/v1/live/complete") {
      const input = await readJson(request);
      if (!input.rider_id || !input.session_id) throw new Error("rider_id and session_id are required");
      const live = await loadJson("live", `${input.rider_id}:${input.session_id}`);
      const actual = {
        actual_effort: input.actual_effort == null ? null : Number(input.actual_effort),
        completed: input.completed !== false,
        notes: String(input.notes ?? "").slice(0, 1000)
      };
      const predictedEffort = Number(live?.prediction?.fatigue ?? 0);
      const predictionError = actual.actual_effort == null ? null : actual.actual_effort * 10 - predictedEffort;
      await saveJson("outcomes", `${input.rider_id}:${input.session_id}`, { prediction: live?.prediction ?? null, actual, prediction_error: predictionError });
      clearLiveSession(String(input.rider_id), String(input.session_id));
      return send(response, 200, { saved: true, prediction_error: predictionError });
    }

    return send(response, 404, { error: "Not found" });
  } catch (error) {
    const status = error instanceof SyntaxError ? 400 : 422;
    return send(response, status, { error: error.message });
  }
});

server.listen(port, host, () => {
  console.log(`Companion calibration service listening on http://${host}:${port}`);
});
