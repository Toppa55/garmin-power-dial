import { Decoder, Stream } from "@garmin/fitsdk";

const inRange = (value, min, max) => Number.isFinite(value) && value >= min && value <= max;

export function normalizedPower(records) {
  const powers = records.map((record) => Number(record.power)).filter((value) => inRange(value, 0, 2000));
  if (powers.length < 30) return null;
  let window = powers.slice(0, 30).reduce((sum, value) => sum + value, 0);
  let fourthPowers = (window / 30) ** 4;
  for (let i = 30; i < powers.length; i++) {
    window += powers[i] - powers[i - 30];
    fourthPowers += (window / 30) ** 4;
  }
  return Math.round((fourthPowers / (powers.length - 29)) ** 0.25);
}

export function normalizeFitSession(session, records = []) {
  const duration = Number(session.totalTimerTime) / 60;
  const averagePower = Number(session.avgPower);
  if (session.sport !== "cycling" || !inRange(duration, 0.1, 1440) || !inRange(averagePower, 1, 1000)) return null;
  const calculatedNp = normalizedPower(records);
  const averageHr = Number(session.avgHeartRate);
  const maxHr = Number(session.maxHeartRate);
  const work = Number(session.totalWork) / 1000;
  return {
    started_at: session.startTime instanceof Date ? session.startTime.toISOString() : null,
    duration_minutes: duration,
    average_power_watts: averagePower,
    normalized_power_watts: inRange(calculatedNp, averagePower, 1200) ? calculatedNp : averagePower,
    average_heart_rate_bpm: inRange(averageHr, 30, 240) ? averageHr : null,
    max_heart_rate_bpm: inRange(maxHr, 30, 250) ? maxHr : null,
    work_kj: inRange(work, 1, 100000) ? work : averagePower * duration * 60 / 1000
  };
}

export function parseFitRide(bytes) {
  const decoder = new Decoder(Stream.fromByteArray(bytes));
  if (!decoder.isFIT() || !decoder.checkIntegrity()) throw new Error("Invalid or damaged FIT file");
  const { messages, errors } = decoder.read();
  if (errors.length) throw new Error("FIT file could not be fully decoded");
  const records = messages.recordMesgs ?? [];
  return (messages.sessionMesgs ?? []).map((session) => normalizeFitSession(session, records)).filter(Boolean);
}
