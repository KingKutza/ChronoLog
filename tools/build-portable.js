#!/usr/bin/env node

import { chmod, copyFile, cp, mkdir, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const sourceRoot = dirname(dirname(fileURLToPath(import.meta.url)));
const APP_DIRECTORIES = Object.freeze(["bin", "src", "tools"]);
const APP_FILES = Object.freeze(["package.json", "pocket-instrument.html", "README.md"]);

export function portableArguments(argv) {
  const options = { platform: process.platform, runtime: process.execPath, output: null };
  for (let index = 0; index < argv.length; index += 1) {
    const value = argv[index];
    if (!["--platform", "--runtime", "--output"].includes(value)) throw new Error(`Unknown option: ${value}`);
    const next = argv[++index];
    if (!next) throw new Error(`${value} requires a value`);
    if (value === "--platform") options.platform = next;
    else if (value === "--runtime") options.runtime = resolve(next);
    else options.output = resolve(next);
  }
  if (!["linux", "win32"].includes(options.platform)) throw new Error("--platform must be linux or win32");
  options.output ||= resolve(sourceRoot, "dist", `chronolog-${options.platform === "win32" ? "windows" : "linux"}-${process.arch}`);
  return options;
}

function launcherFor(platform) {
  if (platform === "win32") {
    return {
      name: "ChronoLog.cmd",
      body: "@echo off\r\nsetlocal\r\n\"%~dp0runtime\\node.exe\" \"%~dp0app\\bin\\chronolog.js\" %*\r\n"
    };
  }
  return {
    name: "chronolog",
    body: "#!/bin/sh\nset -eu\nCHRONOLOG_BUNDLE_DIR=$(CDPATH= cd -- \"$(dirname -- \"$0\")\" && pwd)\nexec \"$CHRONOLOG_BUNDLE_DIR/runtime/node\" \"$CHRONOLOG_BUNDLE_DIR/app/bin/chronolog.js\" \"$@\"\n"
  };
}

export async function buildPortable({
  root = sourceRoot,
  output,
  runtime = process.execPath,
  platform = process.platform
}) {
  if (!["linux", "win32"].includes(platform)) throw new Error("Portable builds support linux and win32");
  if (!output) throw new Error("Portable build output is required");
  await mkdir(dirname(output), { recursive: true });
  await mkdir(output);
  const appRoot = join(output, "app");
  const runtimeRoot = join(output, "runtime");
  await Promise.all([mkdir(appRoot), mkdir(runtimeRoot)]);
  for (const directory of APP_DIRECTORIES) {
    await cp(join(root, directory), join(appRoot, directory), { recursive: true });
  }
  for (const file of APP_FILES) await copyFile(join(root, file), join(appRoot, file));

  const runtimeName = platform === "win32" ? "node.exe" : "node";
  const runtimeTarget = join(runtimeRoot, runtimeName);
  await copyFile(runtime, runtimeTarget);
  if (platform === "linux") await chmod(runtimeTarget, 0o755);

  const launcher = launcherFor(platform);
  const launcherPath = join(output, launcher.name);
  await writeFile(launcherPath, launcher.body, "utf8");
  if (platform === "linux") await chmod(launcherPath, 0o755);
  await writeFile(join(output, "README.txt"), [
    "ChronoLog portable launcher",
    "",
    platform === "win32" ? "Double-click ChronoLog.cmd." : "Run ./chronolog from this directory.",
    "The embedded runtime and app directory must remain beside the launcher.",
    "User data is stored inside this folder, in the app directory, by default.",
    "Deleting this bundle deletes your data too; keep the folder to keep your data,",
    "or pass --data-dir to relocate it elsewhere.",
    "See app/README.md for options, data locations, upgrades, and removal.",
    ""
  ].join("\n"), "utf8");
  return { output, launcher: launcherPath, runtime: runtimeTarget };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const options = portableArguments(process.argv.slice(2));
  buildPortable({ root: sourceRoot, ...options }).then(({ output }) => {
    process.stdout.write(`Built portable ChronoLog at ${output}\n`);
  }).catch((error) => {
    process.stderr.write(`Portable build failed: ${error.message}\n`);
    process.exitCode = 1;
  });
}
