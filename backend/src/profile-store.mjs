import { createHash } from "node:crypto";
import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { join } from "node:path";

function fileName(riderId) {
  if (!riderId || typeof riderId !== "string") throw new Error("rider_id is required");
  return `${createHash("sha256").update(riderId).digest("hex")}.json`;
}

export async function loadProfile(riderId, dataDir = process.env.MODEL_DATA_DIR ?? "./data/models") {
  try {
    return JSON.parse(await readFile(join(dataDir, fileName(riderId)), "utf8"));
  } catch (error) {
    if (error.code === "ENOENT") return null;
    throw error;
  }
}

export async function saveProfile(riderId, profile, dataDir = process.env.MODEL_DATA_DIR ?? "./data/models") {
  await mkdir(dataDir, { recursive: true });
  const target = join(dataDir, fileName(riderId));
  const temporary = `${target}.tmp`;
  await writeFile(temporary, JSON.stringify({ ...profile, updated_at: new Date().toISOString() }, null, 2), { mode: 0o600 });
  await rename(temporary, target);
  return target;
}
