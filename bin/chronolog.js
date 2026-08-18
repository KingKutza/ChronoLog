#!/usr/bin/env node

import { mkdir, open } from "node:fs/promises";
import { spawn } from "node:child_process";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const appRoot = dirname(dirname(fileURLToPath(import.meta.url)));

// ChronoLog is a portable app: its data directory defaults to the app's own
// root (where package.json lives), not any per-OS profile location. The only
// overrides are CHRONOLOG_DATA_DIR and the --data-dir CLI flag.
export function defaultDataDirectory(environment = process.env) {
  if (environment.CHRONOLOG_DATA_DIR) return resolve(environment.CHRONOLOG_DATA_DIR);
  return appRoot;
}

// Default to the same port `npm run dev` binds so the URL stays predictable
// across both entry points. `--port 0` still asks the OS for an ephemeral
// port, which is what tests use to run concurrent servers.
export const DEFAULT_PORT = 4173;

export function parseArguments(argv) {
  const options = { open: true, port: DEFAULT_PORT, dataDirectory: null };
  for (let index = 0; index < argv.length; index += 1) {
    const value = argv[index];
    if (value === "--no-open") options.open = false;
    else if (value === "--port" || value === "--data-dir") {
      const next = argv[++index];
      if (!next) throw new Error(`${value} requires a value`);
      if (value === "--port") {
        options.port = Number(next);
        if (!Number.isInteger(options.port) || options.port < 0 || options.port > 65535) throw new Error("--port must be an integer from 0 to 65535");
      } else options.dataDirectory = resolve(next);
    } else if (value === "--help" || value === "-h") options.help = true;
    else throw new Error(`Unknown option: ${value}`);
  }
  return options;
}

function usage() {
  return `Usage: chronolog [--port PORT] [--data-dir DIRECTORY] [--no-open]\n\nStarts ChronoLog locally and opens it in your default browser.\nData is stored inside the app's own directory by default; use --data-dir or CHRONOLOG_DATA_DIR to relocate it.\n`;
}

function browserCommand(url) {
  if (process.platform === "win32") return ["cmd", ["/c", "start", "", url]];
  if (process.platform === "darwin") return ["open", [url]];
  return ["xdg-open", [url]];
}

export async function launch(argv = process.argv.slice(2), environment = process.env) {
  const options = parseArguments(argv);
  if (options.help) {
    process.stdout.write(usage());
    return 0;
  }
  const dataDirectory = options.dataDirectory || defaultDataDirectory(environment);
  const logsDirectory = join(dataDirectory, "logs");
  await mkdir(logsDirectory, { recursive: true });
  const logPath = join(logsDirectory, "launch.log");
  const log = await open(logPath, "a");
  const now = new Date().toISOString();
  await log.appendFile(`\n${now} starting ChronoLog\napp=${appRoot}\ndata=${dataDirectory}\n`);
  const child = spawn(process.execPath, [join(appRoot, "tools", "serve.js")], {
    env: {
      ...environment,
      CHRONOLOG_DATA_DIR: dataDirectory,
      CHRONOLOG_PORT: String(options.port)
    },
    stdio: ["ignore", "pipe", "pipe"]
  });
  const copy = (chunk) => { log.appendFile(chunk).catch(() => {}); };
  child.stdout.on("data", copy);
  child.stderr.on("data", copy);
  child.once("error", async (error) => {
    await log.appendFile(`launcher error: ${error.stack || error.message}\n`);
    await log.close();
    process.stderr.write(`ChronoLog could not start: ${error.message}\nDiagnostics: ${logPath}\n`);
    process.exitCode = 1;
  });
  child.stdout.on("data", (chunk) => {
    const match = chunk.toString().match(/Chronolog: (http:\/\/127\.0\.0\.1:\d+\/)/);
    if (!match) return;
    process.stdout.write(`${chunk}Diagnostics: ${logPath}\n`);
    if (options.open) {
      const [command, args] = browserCommand(match[1]);
      spawn(command, args, { detached: true, stdio: "ignore" }).unref();
    }
  });
  child.once("exit", async (code, signal) => {
    await log.appendFile(`server stopped: code=${code} signal=${signal}\n`);
    await log.close();
    if (code && !process.exitCode) {
      process.stderr.write(`ChronoLog stopped unexpectedly. Diagnostics: ${logPath}\n`);
      process.exitCode = code;
    }
  });
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  launch().catch((error) => {
    process.stderr.write(`ChronoLog could not start: ${error.message}\n`);
    process.exitCode = 1;
  });
}
