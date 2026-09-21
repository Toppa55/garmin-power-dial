import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import { calibrateFuel } from "../src/calibrator.mjs";
import { parseFitRide } from "../src/fit-history.mjs";
import { loadProfile, saveProfile } from "../src/profile-store.mjs";

const [directory, riderId] = process.argv.slice(2);
if (!directory || !riderId) throw new Error("Usage: node scripts/import-edge-rides.mjs <Edge Activity directory> <rider ID>");

const files = (await readdir(directory)).filter((name) => name.toLowerCase().endsWith(".fit")).sort();
if (!files.length) throw new Error("No FIT ride files found in that directory");
const rides = [];
let skipped = 0;
for (const file of files) {
  try {
    const decoded = parseFitRide(await readFile(join(directory, file)));
    if (!decoded.length) skipped++;
    rides.push(...decoded);
  } catch (error) {
    skipped++;
    console.warn(`Skipped ${file}: ${error.message}`);
  }
}
if (!rides.length) throw new Error("No powered cycling sessions found in the Edge FIT files");
if (rides.length > 5000) throw new Error("Too many rides for one import");

const previous = await loadProfile(riderId);
const learned = await calibrateFuel({ ride_history: rides, previous_profile: previous });
const profile = {
  ...learned,
  source: "edge_fit_usb",
  rides_imported: rides.length,
  files_found: files.length,
  files_skipped: skipped,
  imported_at: new Date().toISOString()
};
await saveProfile(riderId, profile);
console.log(`Updated ${riderId}'s Ride Brain profile from ${rides.length} powered cycling rides in ${files.length} Edge files; ${skipped} files skipped.`);
