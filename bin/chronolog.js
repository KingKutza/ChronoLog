#!/usr/bin/env node

import { mkdir, open } from "node:fs/promises";
import { spawn } from "node:child_process";
import { dirname, join, resolve, win32 } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const appRoot = dirname(dirname(fileURLToPath(import.meta.url)));

export function defaultDataDirectory(environment = process.env, platform = process.platform) {
  if (environment.CHRONOLOG_DATA_DIR) return resolve(environment.CHRONOLOG_DATA_DIR);
  if (platform === "win32") return win32.resolve(environment.APPDATA || win32.join(environment.USERPROFILE || ".", "AppData", "Roaming"), "ChronoLog");
  if (platform === "darwin") return resolve(environment.HOME || ".", "Library", "Application Support", "ChronoLog");
  return resolve(environment.XDG_DATA_HOME || join(environment.HOME || ".", ".local", "share"), "chronolog");
}

export function parseArguments(argv) {
  const options = { open: true, port: 0, dataDirectory: null, lan: false, lanToken: null };
  for (let index = 0; index < argv.length; index += 1) {
    const value = argv[index];
    if (value === "--no-open") options.open = false;
    else if (value === "--lan") options.lan = true;
    else if (value === "--port" || value === "--data-dir" || value === "--lan-token") {
      const next = argv[++index];
      if (!next) throw new Error(`${value} requires a value`);
      if (value === "--port") {
        options.port = Number(next);
        if (!Number.isInteger(options.port) || options.port < 0 || options.port > 65535) throw new Error("--port must be an integer from 0 to 65535");
      } else if (value === "--data-dir") options.dataDirectory = resolve(next);
      else {
        if (next.length < 16) throw new Error("--lan-token must be at least 16 characters");
        options.lanToken = next;
      }
    } else if (value === "--help" || value === "-h") options.help = true;
    else throw new Error(`Unknown option: ${value}`);
  }
  return options;
}

function usage() {
  return `Usage: chronolog [--port PORT] [--data-dir DIRECTORY] [--no-open] [--lan] [--lan-token TOKEN]\n\nStarts ChronoLog locally and opens it in your default browser.\n--lan explicitly exposes it on the local network and prints a bearer-token link.\nData is stored separately from the installed application.\n`;
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
      CHRONOLOG_APP_ROOT: appRoot,
      CHRONOLOG_DATA_DIR: dataDirectory,
      CHRONOLOG_PORT: String(options.port),
      ...(options.lan ? { CHRONOLOG_LAN: "1" } : {}),
      ...(options.lanToken ? { CHRONOLOG_LAN_TOKEN: options.lanToken } : {})
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
    const match = chunk.toString().match(/Chronolog \(installed\): (http:\/\/127\.0\.0\.1:\d+\/)/);
    if (!match) return;
    process.stdout.write(`${chunk}Diagnostics: ${logPath}\n`);
    if (options.open && !options.lan) {
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
