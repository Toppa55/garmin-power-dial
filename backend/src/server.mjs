import { createServer } from "node:http";
import { calibrateFuel } from "./calibrator.mjs";

const port = Number(process.env.PORT ?? 8787);
const token = process.env.COMPANION_TOKEN;

function send(response, status, body) {
  response.writeHead(status, { "Content-Type": "application/json", "Cache-Control": "no-store" });
  response.end(JSON.stringify(body));
}

const server = createServer(async (request, response) => {
  if (request.method === "GET" && request.url === "/health") {
    return send(response, 200, { ok: true });
  }
  if (request.method !== "POST" || request.url !== "/v1/calibrate") {
    return send(response, 404, { error: "Not found" });
  }
  if (!token || request.headers.authorization !== `Bearer ${token}`) {
    return send(response, 401, { error: "Unauthorized" });
  }

  try {
    const chunks = [];
    let size = 0;
    for await (const chunk of request) {
      size += chunk.length;
      if (size > 64 * 1024) throw new Error("Request body is too large");
      chunks.push(chunk);
    }
    const input = JSON.parse(Buffer.concat(chunks).toString("utf8"));
    const calibration = await calibrateFuel(input);
    return send(response, 200, calibration);
  } catch (error) {
    const status = error instanceof SyntaxError ? 400 : 422;
    return send(response, status, { error: error.message });
  }
});

server.listen(port, "127.0.0.1", () => {
  console.log(`Companion calibration service listening on http://127.0.0.1:${port}`);
});
