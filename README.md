# ChronoLog

ChronoLog is a local-first timeline instrument. Its first supported end-user packaging target is a **locally served web application**: the application runs only on `127.0.0.1` and opens in the system browser. No cloud service, account, or network connection is required.

## Install and launch

Install a release archive with the supported Node.js LTS runtime (Node 20 or newer):

```sh
npm install --global ./chronolog-pocket-instrument-0.1.0.tgz
chronolog
```

Create the archive from the exact tagged source checkout with `npm pack`; the package contains the launcher and runtime files only. The checked-in `package.json` contains no runtime dependencies or install scripts, so repeating `npm pack` for that same commit produces the same application contents. `chronolog --help` lists options, including `--data-dir` and `--no-open`.

The launcher uses an available local port by default, opens the browser, and writes startup diagnostics to the `logs/launch.log` file in the data directory. A failed startup prints that diagnostic path in the terminal.

## Data, upgrades, and removal

The installed application is separate from user data. By default data lives in:

- Linux: `$XDG_DATA_HOME/chronolog` (or `~/.local/share/chronolog`)
- macOS: `~/Library/Application Support/ChronoLog`
- Windows: `%APPDATA%\\ChronoLog`

`chronolog.chronolog` is saved through a temporary file and rename, retaining ChronoLog's existing atomic-save behavior where the filesystem supports it. Upgrades replace only the installed package; they preserve this data. To roll back, install the previous `.tgz` archive—the same data directory is retained. Uninstalling the package also leaves data untouched. Remove the data directory yourself only after exporting or backing up the document you intend to discard.

## Development

For a source checkout, use the separate development command:

```sh
npm run dev
```

It serves the checkout at `http://127.0.0.1:4173` and retains the historic behavior of storing its workspace document in the checkout. Its startup line identifies the mode as `development`; the installed launcher identifies the mode as `installed`. Run `npm test`, `npm run check`, and `npm run package:check` before making a release archive.
