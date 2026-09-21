import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { createServer } from "node:net";
import { fileURLToPath } from "node:url";
import test from "node:test";

const serverPath = fileURLToPath(new URL("../src/server.mjs", import.meta.url));

async function freePort() {
  const socket = createServer();
  socket.listen(0, "127.0.0.1");
  await once(socket, "listening");
  const port = socket.address().port;
  socket.close();
  await once(socket, "close");
  return port;
}

test("local-looking headers cannot bypass the pairing token", async () => {
  const port = await freePort();
  const token = "test-companion-token";
  const child = spawn(process.execPath, [serverPath], {
    env: { ...process.env, HOST: "127.0.0.1", PORT: String(port), COMPANION_TOKEN: token },
    stdio: "ignore"
  });
  try {
    const base = `http://127.0.0.1:${port}`;
    let ready = false;
    for (let attempt = 0; attempt < 40; attempt++) {
      if (child.exitCode !== null) throw new Error("Companion server exited during test");
      try {
        ready = (await fetch(`${base}/health`)).ok;
        if (ready) break;
      } catch {}
      await new Promise((resolve) => setTimeout(resolve, 50));
    }
    assert.equal(ready, true);
    const path = `${base}/v1/context?rider_id=test`;
    const spoofed = await fetch(path, { headers: { "X-Companion-Local": "1" } });
    assert.equal(spoofed.status, 401);
    const paired = await fetch(path, { headers: { Authorization: `Bearer ${token}` } });
    assert.equal(paired.status, 200);
  } finally {
    child.kill();
    if (child.exitCode === null) await once(child, "exit");
  }
});
