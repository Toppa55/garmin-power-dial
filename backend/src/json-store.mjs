import { createHash } from "node:crypto";
import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { join } from "node:path";

const safeName = (id) => `${createHash("sha256").update(String(id)).digest("hex")}.json`;

export async function loadJson(kind, id, dataDir = process.env.MODEL_DATA_DIR ?? "./data") {
  try {
    return JSON.parse(await readFile(join(dataDir, kind, safeName(id)), "utf8"));
  } catch (error) {
    if (error.code === "ENOENT") return null;
    throw error;
  }
}

export async function saveJson(kind, id, value, dataDir = process.env.MODEL_DATA_DIR ?? "./data") {
  const directory = join(dataDir, kind);
  await mkdir(directory, { recursive: true });
  const target = join(directory, safeName(id));
  const temporary = `${target}.tmp`;
  await writeFile(temporary, JSON.stringify({ ...value, updated_at: new Date().toISOString() }, null, 2), { mode: 0o600 });
  await rename(temporary, target);
  return target;
}
