#!/usr/bin/env node

import { createServer } from "node:http";
import { readFile, stat } from "node:fs/promises";
import { extname, join, normalize, resolve, sep } from "node:path";

const root = resolve(process.cwd());
const port = Number(process.env.CHRONOLOG_PORT || 4173);
const types = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".webp": "image/webp"
};

createServer(async (request, response) => {
  try {
    const url = new URL(request.url || "/", "http://localhost");
    const requested = decodeURIComponent(url.pathname === "/" ? "/pocket-instrument.html" : url.pathname);
    const relative = normalize(requested).replace(/^([/\\])+/, "");
    const target = resolve(join(root, relative));
    if (target !== root && !target.startsWith(root + sep)) {
      response.writeHead(403).end("Forbidden");
      return;
    }
    const info = await stat(target);
    const file = info.isDirectory() ? join(target, "index.html") : target;
    const body = await readFile(file);
    response.writeHead(200, {
      "content-type": types[extname(file).toLowerCase()] || "application/octet-stream",
      "cache-control": "no-store"
    });
    response.end(body);
  } catch (error) {
    response.writeHead(error?.code === "ENOENT" ? 404 : 500).end(error?.message || "Request failed");
  }
}).listen(port, "127.0.0.1", () => {
  process.stdout.write(`Chronolog: http://127.0.0.1:${port}/\n`);
});
