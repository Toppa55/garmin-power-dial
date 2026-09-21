import assert from "node:assert/strict";
import test from "node:test";
import { parseGarminConnectCsv } from "../src/garmin-csv.mjs";

test("imports Garmin Connect cycling summaries and counts excluded activities", () => {
  const csv = `Activity Type,Date,Title,Time,Avg HR,Max HR,Avg Power,Normalized Power\n` +
    `Road Cycling,2026-09-20,"Ride, long",02:00:00,145,180,200 W,225 W\n` +
    `Running,2026-09-19,Run,00:30:00,155,185,,\n` +
    `Indoor Cycling,2026-09-18,Trainer,01:15:00,138,172,180 W,\n`;
  const result = parseGarminConnectCsv(csv);
  assert.equal(result.total, 3);
  assert.equal(result.skipped, 1);
  assert.equal(result.rides.length, 2);
  assert.equal(result.rides[0].duration_minutes, 120);
  assert.equal(result.rides[0].work_kj, 1440);
  assert.equal(result.rides[1].normalized_power_watts, 180);
});

test("rejects non-Garmin exports and rides without power", () => {
  assert.throws(() => parseGarminConnectCsv("foo,bar\na,b"), /Garmin Connect/);
  assert.throws(() => parseGarminConnectCsv("Activity Type,Time,Avg Power\nCycling,1:00:00,"), /No cycling rides/);
});
