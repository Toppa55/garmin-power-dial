import { createCipheriv, createDecipheriv, createHash, randomBytes } from "node:crypto";
import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { join } from "node:path";

const nameFor = (riderId) => `${createHash("sha256").update(riderId).digest("hex")}.json`;

function encryptionKey() {
  const encoded = process.env.GARMIN_TOKEN_ENCRYPTION_KEY;
  if (!encoded) throw new Error("GARMIN_TOKEN_ENCRYPTION_KEY is not configured");
  const key = Buffer.from(encoded, "base64");
  if (key.length !== 32) throw new Error("GARMIN_TOKEN_ENCRYPTION_KEY must be a base64-encoded 32-byte key");
  return key;
}

export async function saveConnection(riderId, connection, dataDir = process.env.CONNECTION_DATA_DIR ?? "./data/connections") {
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", encryptionKey(), iv);
  const encrypted = Buffer.concat([cipher.update(JSON.stringify(connection), "utf8"), cipher.final()]);
  const payload = { iv: iv.toString("base64"), tag: cipher.getAuthTag().toString("base64"), ciphertext: encrypted.toString("base64") };
  await mkdir(dataDir, { recursive: true });
  const target = join(dataDir, nameFor(riderId));
  const temporary = `${target}.tmp`;
  await writeFile(temporary, JSON.stringify(payload), { mode: 0o600 });
  await rename(temporary, target);
}

export async function loadConnection(riderId, dataDir = process.env.CONNECTION_DATA_DIR ?? "./data/connections") {
  try {
    const payload = JSON.parse(await readFile(join(dataDir, nameFor(riderId)), "utf8"));
    const decipher = createDecipheriv("aes-256-gcm", encryptionKey(), Buffer.from(payload.iv, "base64"));
    decipher.setAuthTag(Buffer.from(payload.tag, "base64"));
    return JSON.parse(Buffer.concat([decipher.update(Buffer.from(payload.ciphertext, "base64")), decipher.final()]).toString("utf8"));
  } catch (error) {
    if (error.code === "ENOENT") return null;
    throw error;
  }
}
