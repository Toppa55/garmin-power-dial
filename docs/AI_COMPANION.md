# Garmin Connect learning and live feedback

The OpenAI API runs only in the companion backend. Its key stays in `.env.local` or a deployment secret store and is never compiled into the Connect IQ app.

## Data flow

1. The companion calls `POST /v1/garmin/connect` and opens the returned Garmin Connect OAuth 2.0 authorization URL.
2. After the rider consents, Garmin Connect redirects to `/v1/garmin/callback`.
3. The service securely stores the Garmin token, requests the complete cycling activity backfill, and normalizes every ride containing power data.
4. Every ride contributes to cumulative duration, work, power, heart-rate, peak, and trend features. The service sends that complete-history summary plus the previous learned profile to the OpenAI Responses API using strict structured output and `store: false`.
5. The new versioned profile contains FTP, hard-effort reserve, resting/threshold/max HR, and HR-drift sensitivity. It is stored under a hashed rider identifier.
6. During a ride, the Edge applies the learned values locally once per second, so the power graph, total-fuel estimate, fast reserve, HR comparison, and fallback feedback continue without a phone or network connection.
7. `POST /v1/garmin/sync` backfills Garmin Connect again and increments the learning revision after later rides.
8. A phone companion can send live sensor state to `POST /v1/live/state`. The deterministic model always responds immediately; OpenAI is consulted only after a meaningful state change or cooldown.
9. The Edge can make a background HTTPS request roughly every five minutes with its latest compact telemetry and receive a cue and updated profile, or a native iOS companion can forward compact responses through its supported phone-message event.
10. `POST /v1/live/complete` stores predicted-versus-reported effort for future model refinement.

Garmin Connect is the only historical-data source in this flow. USB files and direct Edge history are not imported.

## Live screen

The Edge shows:

- a horizontal watt graph marked 1–5 for 100–500 W;
- current HR and its difference from the learned HR expected at that power;
- an FTP marker and current target range when the bridge is connected;
- a 0–100 exertion score combining 60% power load and 40% heart-rate load;
- one short cue: `PAIR HR`, `PUSH`, `STEADY`, `HOLD`, `HARD`, `EASE OFF`, `HR DRIFT`, or `FUEL LOW`;
- a slow total-fuel work estimate, and a separate fast hard-effort reserve that recovers below FTP;
- GO AGAIN, RECOVER, or EASE OFF based on reserve, power, and HR;
- bridge-delivered target watts, risk, and a short AI cue when connected.

The cues are coaching estimates, not medical advice. The HR-drift cue waits 20 minutes and requires meaningful power before it can appear.

The fuel estimate is mechanical-work-equivalent energy, not a measurement of glycogen. Its default budget is editable in Garmin settings and can be updated from a learned profile. Food intake is not automatically measured by the Edge.

## iPhone web app and bridge limits

START_PHONE_WEB.cmd makes the phone dashboard available on the same Wi-Fi as the PC. The iPhone opens /phone, enters its pairing token, and shows the latest Edge state or a manual AI check-in. It can be added to the Home Screen in Safari. A remote ride requires an HTTPS-hosted backend or a Cloudflare Tunnel from a running PC; a LAN-only PC URL is not reachable on the road. The pairing token is required for all API calls, including loopback calls.

The phone page also offers Web Bluetooth sensor pairing in a compatible iPhone browser such as Bluefy. It subscribes to standard Cycling Power (0x1818/0x2A63) and Heart Rate (0x180D/0x2A37) notifications, updates power, HR comparison, fuel, and reserve locally, and posts live state about every five seconds when both sensors are fresh. The Edge can stay paired over ANT+. Safari lacks Web Bluetooth, and the browser path should be kept in the foreground and tested with the actual pedals and strap before relying on it during a ride. This direct-sensor path is independent of Garmin's five-minute background polling; it speeds up feedback on the phone, not on the Edge.

Set bridgeUrl in Garmin Connect IQ settings to the reachable https://.../v1/edge/poll endpoint, set bridgeToken to the companion token, and use the same bridgeRiderId as the phone dashboard. The Edge sends a small snapshot about every five minutes and receives a cue, target, FTP, and fuel calibration. Power, HR, and both bars remain second-by-second local calculations. Garmin enforces a minimum five-minute background interval; a web-only iPhone page cannot bypass it. The optional phone-message receiver remains ready for a future native iOS companion if faster AI cue delivery is needed.

## Optional native phone protocol

A future native iOS companion can sample independently paired BLE power, HR, cadence, and temperature sensors every few seconds and post a compact packet:

```json
{"rider_id":"thomas","session_id":"ride-123","elapsed_seconds":900,"power_watts":245,"heart_rate_bpm":158,"cadence_rpm":91,"temperature_c":29,"reserve_percent":72,"carbs_grams":30,"sleep_hours":6.5,"night_shift":false}
```

The response contains `cue`, `targetLow`, `targetHigh`, `risk`, `confidence`, HR prediction, fatigue, carbohydrate deficit, drink timer, and FTP. A native phone companion could forward the small camel-case fields to Garmin using the Connect IQ Mobile SDK. The web-only path instead uses the Edge's five-minute background HTTPS polling.

The repository implements the server protocol and Garmin receiver. Packaging a native Android/iOS sensor bridge still requires the mobile platform SDKs, Connect IQ Mobile SDK registration, and app-store signing identities.

## Planning and chat

Open `http://127.0.0.1:8787` after starting the backend. The dashboard saves sleep, night-shift, work schedule, training availability, and recovery-coaching preferences. `POST /v1/plan` combines that context with the learned Garmin profile to recommend rest, recovery, endurance, tempo, intervals, or race work. The same endpoint accepts natural-language coaching questions.

## Garmin Connect access

Garmin's Activity API requires an approved Garmin Connect Developer Program application. The public documentation confirms OAuth 2.0, user consent, activity backfill, FIT details, and push or pull integration, but the assigned authorization, token, and activity URLs are provided through the approved developer portal.

For a personal rider without that approval, Garmin Connect's **Activities → All Activities → Export CSV** supplies a manual history route. Load the complete activity list before exporting, then choose the CSV file in the phone page's **Learn from Garmin Connect rides** section. `POST /v1/garmin/import-csv` reads all powered cycling summaries in the file, reports skipped rows, and updates the learned profile. The file comes from Garmin Connect, not the Edge's USB storage. Re-export and import after later rides to refresh the profile. This summary export does not include the full second-by-second ride trace, and it is not automatic syncing.

Alternatively, for a connected Edge 130 Plus, run `node --env-file=../.env.local scripts/import-edge-rides.mjs E:/GARMIN/Activity <rider-id>` from `backend`, using the actual drive letter. The script uses Garmin's FIT SDK to read cycling power and heart-rate sessions, computes normalized power from recorded power samples, and updates the same rider profile without modifying the device. It never forwards GPS coordinates to the AI service. Only rides currently stored on the Edge are included; use the Garmin Connect export for a longer history.

Strava's 2026 API Policy prohibits using ordinary Strava API data or derived summaries to operate an AI application, so the app must not feed Strava API activities into the learning service. Strava exempts its own personal-use MCP connector, but Ride Brain has no access to that connector today.

Configure these values from that portal:

```dotenv
GARMIN_CLIENT_ID=
GARMIN_CLIENT_SECRET=
GARMIN_AUTHORIZE_URL=
GARMIN_TOKEN_URL=
GARMIN_ACTIVITY_BACKFILL_URL=
GARMIN_SCOPES=
GARMIN_TOKEN_ENCRYPTION_KEY=
```

`GARMIN_TOKEN_ENCRYPTION_KEY` must be a base64-encoded 32-byte value. Garmin refresh tokens are encrypted with AES-256-GCM before local persistence. Raw ride history is processed in memory; the service persists only the compact learned profile.

## Run locally

The root `.env.local` must contain `OPENAI_API_KEY`. Add a long random `COMPANION_TOKEN`, the Garmin values above, and optionally `OPENAI_MODEL`, `PORT`, `MODEL_DATA_DIR`, and `CONNECTION_DATA_DIR`.

```powershell
cd backend
npm test
npm start
```

The service binds to localhost by default. A hosted version also needs HTTPS, user accounts, rate limits, a managed secret store, and the exact Garmin payload mapping issued with Developer Program access.
