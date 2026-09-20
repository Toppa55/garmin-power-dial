# Garmin Connect learning and live feedback

The OpenAI API runs only in the companion backend. Its key stays in `.env.local` or a deployment secret store and is never compiled into the Connect IQ app.

## Data flow

1. The companion calls `POST /v1/garmin/connect` and opens the returned Garmin Connect OAuth 2.0 authorization URL.
2. After the rider consents, Garmin Connect redirects to `/v1/garmin/callback`.
3. The service securely stores the Garmin token, requests the complete cycling activity backfill, and normalizes every ride containing power data.
4. Every ride contributes to cumulative duration, work, power, heart-rate, peak, and trend features. The service sends that complete-history summary plus the previous learned profile to the OpenAI Responses API using strict structured output and `store: false`.
5. The new versioned profile contains FTP, hard-effort reserve, resting/threshold/max HR, and HR-drift sensitivity. It is stored under a hashed rider identifier.
6. During a ride, the Edge applies the learned values locally once per second, so the dial, reserve, HR comparison, and fallback feedback continue without a phone or network connection.
7. `POST /v1/garmin/sync` backfills Garmin Connect again and increments the learning revision after later rides.
8. A phone companion can send live sensor state to `POST /v1/live/state`. The deterministic model always responds immediately; OpenAI is consulted only after a meaningful state change or cooldown.
9. The phone forwards the compact response to the Connect IQ app. The Edge 130 Plus receives it through its supported background phone-message event.
10. `POST /v1/live/complete` stores predicted-versus-reported effort so later profile revisions can learn prediction error.

Garmin Connect is the only historical-data source in this flow. USB files and direct Edge history are not imported.

## Live screen

The Edge shows:

- live watts on a nonlinear 0–400% FTP rev counter;
- current HR and its difference from the learned HR expected at that power;
- live power as a percentage of FTP;
- a 0–100 exertion score combining 60% power load and 40% heart-rate load;
- one short cue: `PAIR HR`, `PUSH`, `STEADY`, `HOLD`, `HARD`, `EASE OFF`, `HR DRIFT`, or `FUEL LOW`;
- exact hard-effort reserve percentage and remaining kJ over a 20-segment bar;
- phone-delivered target watts, risk, confidence, drink/carbohydrate prompts, and a short AI cue when the live bridge is connected.

The cues are coaching estimates, not medical advice. The HR-drift cue waits 20 minutes and requires meaningful power before it can appear.

## Live phone protocol

The phone samples independently paired BLE power, HR, cadence, and temperature sensors every few seconds and posts a compact packet:

```json
{"rider_id":"thomas","session_id":"ride-123","elapsed_seconds":900,"power_watts":245,"heart_rate_bpm":158,"cadence_rpm":91,"temperature_c":29,"reserve_percent":72,"carbs_grams":30,"sleep_hours":6.5,"night_shift":false}
```

The response contains `cue`, `targetLow`, `targetHigh`, `risk`, `confidence`, HR prediction, fatigue, carbohydrate deficit, drink timer, and FTP. The native phone companion forwards the small camel-case fields to Garmin using the Connect IQ Mobile SDK. The backend never contacts the Edge directly.

The repository implements the server protocol and Garmin receiver. Packaging a native Android/iOS sensor bridge still requires the mobile platform SDKs, Connect IQ Mobile SDK registration, and app-store signing identities.

## Planning and chat

Open `http://127.0.0.1:8787` after starting the backend. The dashboard saves sleep, night-shift, work schedule, training availability, and recovery-coaching preferences. `POST /v1/plan` combines that context with the learned Garmin profile to recommend rest, recovery, endurance, tempo, intervals, or race work. The same endpoint accepts natural-language coaching questions.

## Garmin Connect access

Garmin's Activity API requires an approved Garmin Connect Developer Program application. The public documentation confirms OAuth 2.0, user consent, activity backfill, FIT details, and push or pull integration, but the assigned authorization, token, and activity URLs are provided through the approved developer portal.

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
