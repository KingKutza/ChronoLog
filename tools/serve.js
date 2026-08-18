#!/usr/bin/env node

import { createServer } from "node:http";
import { fstatSync } from "node:fs";
import { readFile, realpath, stat } from "node:fs/promises";
import { basename, dirname, extname, join, normalize, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { createCalendarFeedService } from "./calendar-feed-service.js";
import { createJournalStore } from "./journal.js";

const toolRoot = dirname(dirname(fileURLToPath(import.meta.url)));
// tools/serve.js always lives at <app root>/tools/serve.js, in every
// deployment shape including the portable bundle (app/tools/serve.js), so the
// app root is simply toolRoot's parent. CHRONOLOG_APP_ROOT remains as a test
// hook: it lets tests point the static-file root at an isolated temp
// directory (distinct from the real checkout) while still exercising the
// "data lives beside the app root" default via CHRONOLOG_DATA_DIR.
const root = resolve(process.env.CHRONOLOG_APP_ROOT || toolRoot);
const realRoot = await realpath(root);
const port = Number(process.env.CHRONOLOG_PORT || 4173);
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
const journalFile = join(dataRoot, "chronolog.journal");
// The ceiling applies wherever a whole document can cross the wire. That is
// both the snapshot upload and a journal batch: a full calendar re-sync emits
// one put per touched event, so a single batch legitimately approaches the
// size of the document it rewrites.
const MAX_DOCUMENT_BYTES = 512 * 1024 * 1024;
const handleCalendarFeed = createCalendarFeedService({ dataRoot });

function warn(message) {
  process.stderr.write(`Chronolog journal: ${message}\n`);
}

const journal = createJournalStore({ dataRoot, warn });

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

async function jsonBody(request) {
  const body = await requestBody(request);
  return JSON.parse(body.toString("utf8"));
}

function sendJSON(response, status, value) {
  const body = Buffer.from(JSON.stringify(value));
  response.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "content-length": body.length,
    "cache-control": "no-store"
  });
  response.end(body);
}

const server = createServer(async (request, response) => {
  try {
    const url = new URL(request.url || "/", "http://localhost");
    if (url.pathname.startsWith("/api/sync/") && await handleCalendarFeed(request, response, url)) return;

    // The current materialized document: the snapshot with every journal entry
    // replayed over it. The client never sees the snapshot/journal split.
    if (url.pathname === "/api/document" && ["GET", "HEAD"].includes(request.method)) {
      const body = journal.body();
      if (!body) {
        response.writeHead(404).end("No workspace document yet");
        return;
      }
      response.writeHead(200, {
        "content-type": "application/x-chronolog; charset=utf-8",
        "content-length": body.length,
        "cache-control": "no-store",
        "x-chronolog-file": "chronolog.chronolog",
        "x-chronolog-seq": String(journal.seq)
      });
      response.end(request.method === "HEAD" ? null : body);
      return;
    }
    if (url.pathname === "/api/document") {
      response.writeHead(405, { allow: "GET, HEAD" }).end("Method not allowed");
      return;
    }

    // One committed edit per entry. The server assigns sequence numbers, so
    // baseSeq is the client's claim about what it last saw; a mismatch means
    // another window committed first and the client must rebase.
    if (url.pathname === "/api/journal" && request.method === "POST") {
      const payload = await jsonBody(request);
      if (!Number.isInteger(payload?.baseSeq) || !Array.isArray(payload?.entries)) {
        response.writeHead(400).end("Expected {baseSeq, entries}");
        return;
      }
      if (!journal.present) {
        response.writeHead(409).end("No workspace document yet; upload a snapshot first");
        return;
      }
      try {
        sendJSON(response, 200, await journal.append(payload.baseSeq, payload.entries));
      } catch (error) {
        if (error?.name === "JournalConflict") {
          sendJSON(response, 409, {
            currentSeq: error.currentSeq,
            missed: error.missed,
            truncated: error.truncated
          });
          return;
        }
        response.writeHead(400).end(error?.message || "Journal append failed");
      }
      return;
    }
    if (url.pathname === "/api/journal" && ["GET", "HEAD"].includes(request.method)) {
      const since = Number(url.searchParams.get("since") || 0);
      if (!Number.isInteger(since) || since < 0) {
        response.writeHead(400).end("since must be a non-negative integer");
        return;
      }
      sendJSON(response, 200, journal.since(since));
      return;
    }
    if (url.pathname === "/api/journal") {
      response.writeHead(405, { allow: "GET, HEAD, POST" }).end("Method not allowed");
      return;
    }

    // Whole-document replacement. Two uses: establishing the first snapshot on
    // a fresh data directory, and the owner deliberately opening a different
    // file. Never an autosave path, so it carries no compare-and-swap.
    if (url.pathname === "/api/snapshot" && request.method === "PUT") {
      const next = await jsonBody(request);
      if (!next || typeof next !== "object" || Array.isArray(next)) {
        response.writeHead(400).end("A snapshot must be a JSON object");
        return;
      }
      sendJSON(response, 200, await journal.replaceSnapshot(next));
      return;
    }
    if (url.pathname === "/api/snapshot") {
      response.writeHead(405, { allow: "PUT" }).end("Method not allowed");
      return;
    }

    if (url.pathname === "/api/settings" && ["GET", "HEAD"].includes(request.method)) {
      sendJSON(response, 200, await journal.readSettings());
      return;
    }
    if (url.pathname === "/api/settings" && request.method === "PUT") {
      try {
        sendJSON(response, 200, await journal.writeSettings(await jsonBody(request)));
      } catch (error) {
        response.writeHead(400).end(error?.message || "Invalid settings");
      }
      return;
    }
    if (url.pathname === "/api/settings") {
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
    // let its ordinary static-file route bypass the document API's atomic
    // writes and sequence guards. The check is on the name, not the resolved
    // path: with --data-dir pointed elsewhere, the app root can still hold a
    // document of its own, and serving that one as a static asset would hand
    // out the whole file with no guard at all.
    const name = basename(target);
    if (name === "chronolog.chronolog" || name === "chronolog.journal" || name.startsWith(".chronolog-")
      || target === documentFile || target === journalFile) {
      response.writeHead(403).end("Workspace files are available only through the document API");
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

const boot = await journal.load();
// A journal left behind by the previous run means that run did not shut down
// cleanly. Folding it in now keeps the replay cost at the next boot bounded.
if (boot.present && boot.replayed) {
  const result = await journal.compact();
  if (result.compacted) {
    process.stdout.write(`Chronolog: replayed and compacted ${result.folded} journal entr${result.folded === 1 ? "y" : "ies"}\n`);
  }
}
const periodMinutes = await journal.schedule();

let closing = false;
// A clean shutdown always leaves a current snapshot and an empty journal.
// Nothing is lost without it — boot replay covers an outright kill — but
// folding on the way out keeps the next start's replay cost at zero.
function shutdown() {
  if (closing) return;
  closing = true;
  journal.stop();
  journal.compact()
    .catch((error) => warn(`shutdown compaction failed: ${error.message}`))
    .finally(() => {
      server.close(() => process.exit(0));
      setTimeout(() => process.exit(0), 2000).unref();
    });
}

for (const signal of ["SIGINT", "SIGTERM", "SIGHUP", "SIGBREAK"]) {
  try {
    process.on(signal, shutdown);
  } catch {
    // Not every signal name exists on every platform.
  }
}
// Windows cannot deliver SIGTERM to a child process at all — `kill` there is
// TerminateProcess, so no handler runs. A closed stdin pipe is the one
// shutdown request that behaves identically on Windows and Linux, so the
// launcher holds stdin open for exactly as long as the server should live.
// Only a real pipe counts: an "ignore" stdio slot is the null device, which
// reports end-of-input immediately and would stop the server on startup.
function stdinIsPipe() {
  // A console keeps running until Ctrl+C, which arrives as SIGINT instead.
  if (process.stdin.isTTY) return false;
  try {
    const info = fstatSync(0);
    if (info.isFIFO() || info.isSocket()) return true;
    // Windows reports a piped stdin as none of the known types, while an
    // ignored one is the NUL character device — and NUL signals end-of-input
    // at once. So anything that is not a device or a real file is the pipe.
    return !info.isCharacterDevice() && !info.isFile() && !info.isDirectory();
  } catch {
    return false;
  }
}
if (stdinIsPipe()) {
  process.stdin.on("end", shutdown);
  process.stdin.on("close", shutdown);
  process.stdin.resume();
}

server.listen(port, "127.0.0.1", () => {
  const address = server.address();
  const activePort = typeof address === "object" && address ? address.port : port;
  process.stdout.write(`Chronolog: http://127.0.0.1:${activePort}/\nUser data: ${dataRoot}\n`);
  process.stdout.write(`Journal: seq ${journal.seq}, snapshot every ${periodMinutes} min\n`);
});
