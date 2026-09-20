import assert from "node:assert/strict";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { loadConnection, saveConnection } from "../src/connection-store.mjs";
import { createAuthorizationUrl, normalizeGarminActivity } from "../src/garmin-connect.mjs";

const env = {
  GARMIN_AUTHORIZE_URL: "https://garmin.example/authorize",
  GARMIN_CLIENT_ID: "client-id",
  GARMIN_SCOPES: "activity.read"
};

test("builds Garmin OAuth authorization URL with state", () => {
  const url = new URL(createAuthorizationUrl({ state: "state-123", redirectUri: "https://app.example/callback", env }));
  assert.equal(url.searchParams.get("client_id"), "client-id");
  assert.equal(url.searchParams.get("state"), "state-123");
  assert.equal(url.searchParams.get("redirect_uri"), "https://app.example/callback");
});

test("normalizes Garmin cycling metrics for learning", () => {
  const ride = normalizeGarminActivity({
    startTimeInSeconds: 1750000000,
    durationInSeconds: 7200,
    averagePowerInWatts: 180,
    normalizedPowerInWatts: 210,
    averageHeartRateInBeatsPerMinute: 145,
    maxHeartRateInBeatsPerMinute: 178
  });
  assert.equal(ride.duration_minutes, 120);
  assert.equal(ride.work_kj, 1296);
  assert.equal(ride.average_heart_rate_bpm, 145);
});

test("persists Garmin tokens encrypted", async () => {
  const directory = await mkdtemp(join(tmpdir(), "garmin-token-test-"));
  const previousKey = process.env.GARMIN_TOKEN_ENCRYPTION_KEY;
  process.env.GARMIN_TOKEN_ENCRYPTION_KEY = Buffer.alloc(32, 7).toString("base64");
  try {
    const connection = { access_token: "private-access-token", refresh_token: "private-refresh-token" };
    await saveConnection("rider-1", connection, directory);
    const files = await import("node:fs/promises").then((fs) => fs.readdir(directory));
    const stored = await readFile(join(directory, files[0]), "utf8");
    assert.equal(stored.includes("private-access-token"), false);
    assert.deepEqual(await loadConnection("rider-1", directory), connection);
  } finally {
    if (previousKey == null) delete process.env.GARMIN_TOKEN_ENCRYPTION_KEY;
    else process.env.GARMIN_TOKEN_ENCRYPTION_KEY = previousKey;
    await rm(directory, { recursive: true, force: true });
  }
});
