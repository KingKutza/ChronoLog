#!/usr/bin/env node

import { createServer } from "node:http";
import { readFile, realpath, rename, stat, unlink, writeFile } from "node:fs/promises";
import { extname, join, normalize, resolve, sep } from "node:path";

const root = resolve(process.cwd());
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

const documentFile = join(root, "chronolog.chronolog");
const legacyDocumentFile = join(root, "chronolog.json");
const temporaryDocumentFile = join(root, ".chronolog-save.tmp");
const MAX_DOCUMENT_BYTES = 512 * 1024 * 1024;

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

createServer(async (request, response) => {
  try {
    const url = new URL(request.url || "/", "http://localhost");
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
        "x-chronolog-file": file === documentFile ? "chronolog.chronolog" : "chronolog.json"
      });
      response.end(body);
      return;
    }
    if (url.pathname === "/api/document" && request.method === "PUT") {
      const body = await requestBody(request);
      JSON.parse(body.toString("utf8"));
      await writeFile(temporaryDocumentFile, body);
      try {
        await rename(temporaryDocumentFile, documentFile);
      } catch {
        await writeFile(documentFile, body);
        await unlink(temporaryDocumentFile).catch(() => {});
      }
      response.writeHead(204, { "x-chronolog-file": "chronolog.chronolog" }).end();
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
}).listen(port, "127.0.0.1", () => {
  process.stdout.write(`Chronolog: http://127.0.0.1:${port}/\n`);
});
