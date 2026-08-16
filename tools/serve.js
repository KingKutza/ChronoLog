#!/usr/bin/env node

import { createServer } from "node:http";
import { copyFile, open, readFile, realpath, rename, stat, unlink } from "node:fs/promises";
import { createHash, randomBytes, timingSafeEqual } from "node:crypto";
import { networkInterfaces } from "node:os";
import { dirname, extname, join, normalize, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const toolRoot = dirname(dirname(fileURLToPath(import.meta.url)));
const root = resolve(process.env.CHRONOLOG_APP_ROOT || toolRoot);
const realRoot = await realpath(root);
const port = Number(process.env.CHRONOLOG_PORT || 4173);
const mode = process.env.CHRONOLOG_APP_ROOT ? "installed" : "development";
const lanEnabled = process.env.CHRONOLOG_LAN === "1";
const lanToken = lanEnabled ? (process.env.CHRONOLOG_LAN_TOKEN || randomBytes(24).toString("base64url")) : null;
const types = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".chronolog": "application/x-chronolog; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".webp": "image/webp"
};

const dataRoot = resolve(process.env.CHRONOLOG_DATA_DIR || root);
const documentFile = join(dataRoot, "chronolog.chronolog");
const legacyDocumentFile = join(dataRoot, "chronolog.json");
const recoveryDocumentFile = join(dataRoot, ".chronolog-recovery.chronolog");
const MAX_DOCUMENT_BYTES = 512 * 1024 * 1024;

function tokenMatches(value) {
  const supplied = String(value || "").replace(/^Bearer\s+/i, "");
  if (!lanToken || !supplied) return false;
  const left = Buffer.from(supplied);
  const right = Buffer.from(lanToken);
  return left.length === right.length && timingSafeEqual(left, right);
}

function permittedApiRequest(request) {
  if (!lanEnabled) return true;
  if (!tokenMatches(request.headers.authorization)) return false;
  // We intentionally emit no CORS headers. A browser page served by this
  // instance is same-origin; a different web origin cannot read or write this
  // workspace just because it knows a LAN address and token.
  const origin = request.headers.origin;
  if (!origin) return true; // CLI/diagnostic client with the bearer token.
  return origin === `http://${request.headers.host}`;
}

function localLanAddresses() {
  return Object.values(networkInterfaces()).flat()
    .filter((entry) => entry && entry.family === "IPv4" && !entry.internal)
    .map((entry) => entry.address);
}

function requestBody(request) {
  return new Promise((resolveBody, rejectBody) => {
    const chunks = [];
    let size = 0;
    request.on("data", (chunk) => {
      size += chunk.length;
      if (size > MAX_DOCUMENT_BYTES) {
        rejectBody(new RangeError("Chronolog document exceeds the 512 MiB local-save limit"));
        request.destroy();
        return;
      }
      chunks.push(chunk);
    });
    request.on("end", () => resolveBody(Buffer.concat(chunks)));
    request.on("error", rejectBody);
  });
}

async function workspaceDocument() {
  for (const file of [documentFile, legacyDocumentFile]) {
    try {
      await stat(file);
      return file;
    } catch (error) {
      if (error?.code !== "ENOENT") throw error;
    }
  }
  return null;
}

function revisionFor(body) {
  return `\"${createHash("sha256").update(body).digest("hex")}\"`;
}

async function atomicWrite(file, body) {
  const temporary = join(dataRoot, `.chronolog-save-${process.pid}-${Date.now()}-${Math.random().toString(16).slice(2)}.tmp`);
  const descriptor = await open(temporary, "wx", 0o600);
  try {
    await descriptor.writeFile(body);
    await descriptor.sync();
  } finally {
    await descriptor.close();
  }
  try {
    await rename(temporary, file);
  } finally {
    await unlink(temporary).catch(() => {});
  }
}

const server = createServer(async (request, response) => {
  try {
    const url = new URL(request.url || "/", "http://localhost");
    if (url.pathname.startsWith("/api/") && !permittedApiRequest(request)) {
      response.writeHead(403, { "cache-control": "no-store" }).end("LAN workspace access requires its launch token from the same Chronolog origin");
      return;
    }
    if (url.pathname === "/api/document" && ["GET", "HEAD"].includes(request.method)) {
      const file = await workspaceDocument();
      if (!file) {
        response.writeHead(404).end("No workspace document yet");
        return;
      }
      const info = await stat(file);
      const body = request.method === "HEAD" ? null : await readFile(file);
      response.writeHead(200, {
        "content-type": "application/x-chronolog; charset=utf-8",
        "content-length": info.size,
        "cache-control": "no-store",
        "x-chronolog-file": file === documentFile ? "chronolog.chronolog" : "chronolog.json",
        etag: revisionFor(body || await readFile(file))
      });
      response.end(body);
      return;
    }
    if (url.pathname === "/api/document" && request.method === "PUT") {
      const body = await requestBody(request);
      JSON.parse(body.toString("utf8"));
      try {
        const current = await readFile(documentFile);
        const currentRevision = revisionFor(current);
        const expected = request.headers["if-match"];
        const expectedAbsent = request.headers["if-none-match"] === "*";
        if (expectedAbsent || (expected && expected !== currentRevision)) {
          response.writeHead(409, { etag: currentRevision }).end("Workspace changed in another window; local edits were not written");
          return;
        }
        await copyFile(documentFile, recoveryDocumentFile);
      } catch (error) {
        if (error?.code !== "ENOENT") throw error;
      }
      await atomicWrite(documentFile, body);
      response.writeHead(204, {
        "x-chronolog-file": "chronolog.chronolog",
        etag: revisionFor(body)
      }).end();
      return;
    }
    if (url.pathname === "/api/document/recovery" && ["GET", "HEAD"].includes(request.method)) {
      const body = request.method === "HEAD" ? null : await readFile(recoveryDocumentFile);
      const content = body || await readFile(recoveryDocumentFile);
      response.writeHead(200, {
        "content-type": "application/x-chronolog; charset=utf-8",
        "cache-control": "no-store",
        etag: revisionFor(content)
      }).end(body);
      return;
    }
    if (url.pathname === "/api/document") {
      response.writeHead(405, { allow: "GET, HEAD, PUT" }).end("Method not allowed");
      return;
    }
    const requested = decodeURIComponent(url.pathname === "/" ? "/pocket-instrument.html" : url.pathname);
    const relative = normalize(requested).replace(/^([/\\])+/, "");
    const target = resolve(join(root, relative));
    if (target !== root && !target.startsWith(root + sep)) {
      response.writeHead(403).end("Forbidden");
      return;
    }
    // Development mode can deliberately keep data beside the checkout. Never
    // let its ordinary static-file route bypass LAN API authentication.
    if (target === documentFile || target === legacyDocumentFile || target === recoveryDocumentFile
      || (dirname(target) === dataRoot && target.startsWith(join(dataRoot, ".chronolog-save-")))) {
      response.writeHead(403).end("Workspace files are available only through the authenticated API");
      return;
    }
    const info = await stat(target);
    const file = await realpath(info.isDirectory() ? join(target, "index.html") : target);
    if (file !== realRoot && !file.startsWith(realRoot + sep)) {
      response.writeHead(403).end("Forbidden");
      return;
    }
    const body = await readFile(file);
    response.writeHead(200, {
      "content-type": types[extname(file).toLowerCase()] || "application/octet-stream",
      "cache-control": "no-store"
    });
    response.end(body);
  } catch (error) {
    response.writeHead(error?.code === "ENOENT" ? 404 : 500).end(error?.message || "Request failed");
  }
});

server.on("error", (error) => {
  process.stderr.write(`Chronolog could not start: ${error.message}\n`);
  process.stderr.write(`App files: ${root}\nUser data: ${dataRoot}\n`);
  process.exitCode = 1;
});

server.listen(port, lanEnabled ? "0.0.0.0" : "127.0.0.1", () => {
  const address = server.address();
  const activePort = typeof address === "object" && address ? address.port : port;
  process.stdout.write(`Chronolog (${mode}): http://127.0.0.1:${activePort}/\nUser data: ${dataRoot}\n`);
  if (lanEnabled) {
    const addresses = localLanAddresses();
    const targets = addresses.length
      ? addresses.map((host) => `http://${host}:${activePort}/#chronolog-token=${lanToken}`)
      : [`http://<LAN-address>:${activePort}/#chronolog-token=${lanToken}`];
    process.stdout.write("LAN mode is enabled. Anyone with this link can edit this workspace:\n");
    for (const target of targets) process.stdout.write(`${target}\n`);
    process.stdout.write("The token is a bearer secret; do not paste this URL into chat, email, or issue trackers.\n");
  }
});
