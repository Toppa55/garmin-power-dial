# Garmin Connect learning and live feedback

The OpenAI API runs only in the companion backend. Its key stays in `.env.local` or a deployment secret store and is never compiled into the Connect IQ app.

## Data flow

1. The companion calls `POST /v1/garmin/connect` and opens the returned Garmin Connect OAuth 2.0 authorization URL.
2. After the rider consents, Garmin Connect redirects to `/v1/garmin/callback`.
3. The service securely stores the Garmin token, requests the complete cycling activity backfill, and normalizes every ride containing power data.
4. Every ride contributes to cumulative duration, work, power, heart-rate, peak, and trend features. The service sends that complete-history summary plus the previous learned profile to the OpenAI Responses API using strict structured output and `store: false`.
5. The new versioned profile contains FTP, ride work budget, resting/threshold/max HR, and HR-drift sensitivity. It is stored under a hashed rider identifier.
6. The profile values are entered in the data field settings through Garmin Connect Mobile. During a ride, the Edge applies them locally once per second, so feedback continues without a phone or network connection.
7. `POST /v1/garmin/sync` backfills Garmin Connect again and increments the learning revision after later rides.

Garmin Connect is the only historical-data source in this flow. USB files and direct Edge history are not imported.

## Live screen

The Edge shows:

- live watts on a 0–200% FTP rev counter;
- current HR and its difference from the learned HR expected at that power;
- live power as a percentage of FTP;
- a 0–100 exertion score combining 60% power load and 40% heart-rate load;
- one short cue: `PAIR HR`, `PUSH`, `STEADY`, `HOLD`, `HARD`, `EASE OFF`, `HR DRIFT`, or `FUEL LOW`;
- exact fuel percentage and remaining kJ over a 20-segment bar.

The cues are coaching estimates, not medical advice. The HR-drift cue waits 20 minutes and requires meaningful power before it can appear.

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
