import { randomUUID } from "node:crypto";
import { createServer } from "node:http";
import { calibrateFuel } from "./calibrator.mjs";
import { loadConnection, saveConnection } from "./connection-store.mjs";
import { createAuthorizationUrl, exchangeAuthorizationCode, fetchCompleteActivityHistory, refreshAccessToken } from "./garmin-connect.mjs";
import { loadProfile, saveProfile } from "./profile-store.mjs";

const port = Number(process.env.PORT ?? 8787);
const token = process.env.COMPANION_TOKEN;
const pendingAuthorizations = new Map();

function send(response, status, body) {
  response.writeHead(status, { "Content-Type": "application/json", "Cache-Control": "no-store" });
  response.end(JSON.stringify(body));
}

function isAuthorized(request) {
  return token && request.headers.authorization === `Bearer ${token}`;
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

    return send(response, 404, { error: "Not found" });
  } catch (error) {
    const status = error instanceof SyntaxError ? 400 : 422;
    return send(response, status, { error: error.message });
  }
});

server.listen(port, "127.0.0.1", () => {
  console.log(`Companion calibration service listening on http://127.0.0.1:${port}`);
});
