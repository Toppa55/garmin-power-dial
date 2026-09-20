# AI fuel calibration

The OpenAI API runs only in the companion service under `backend/`. The API key stays in the ignored repository `.env.local` file or in the deployment platform's secret store. It is never compiled into the Connect IQ app.

## Data flow

1. A companion client sends up to 20 recent ride summaries plus the next ride's expected duration to `POST /v1/calibrate`.
2. The service validates and bounds every metric, then asks the OpenAI Responses API for a strict JSON calibration.
3. The service clamps the returned FTP and mechanical-work budget to safe display ranges.
4. The rider copies `ftp_watts` and `ride_energy_budget_kj` into the data field's Connect IQ settings in Garmin Connect Mobile.
5. During the ride, the Edge computes spent mechanical work from average power and timer time. This works offline and keeps updating if the phone is absent.

The Edge 130 Plus targets Connect IQ 3.2.0. Garmin exposes web communication to foreground data fields only from API 5.0.0, so this design uses the supported settings bridge instead of making network calls from the data field. A future phone companion can automate step 4 while keeping the same backend contract.

## Run locally

The root `.env.local` must contain `OPENAI_API_KEY`. Add a long random `COMPANION_TOKEN`, and optionally set `OPENAI_MODEL` and `PORT`. See `backend/.env.example` for the variable names.

```powershell
cd backend
npm test
npm start
```

Example request:

```json
{
  "target_ride_minutes": 150,
  "ftp_hint_watts": 250,
  "recent_rides": [
    { "duration_minutes": 90, "average_power_watts": 185, "normalized_power_watts": 215 },
    { "duration_minutes": 150, "average_power_watts": 165, "normalized_power_watts": 198 }
  ]
}
```

Send it with `Authorization: Bearer <COMPANION_TOKEN>` to `http://127.0.0.1:8787/v1/calibrate`. The response provides the two values to enter in Garmin Connect Mobile, plus confidence, rationale, and the model name used.

The service binds to localhost by default. Before hosting it, add authenticated user accounts, HTTPS, rate limits, per-user data retention rules, and a managed secret store.
