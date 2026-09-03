# app/tool

Uncounted tooling. Nothing under `lib/` imports anything here, and nothing here
ships in a build.

## screenshot.ps1

Captures the ChronoLog window -- or, if no matching window is running, the
whole primary screen -- to a PNG.

```
powershell -ExecutionPolicy Bypass -File app/tool/screenshot.ps1 -Out out/shot.png -Title chronolog
```

`-Out` is the PNG path to write (default `out/shot.png`); its directory is
created if it doesn't exist. `-Title` is the process name or window-title
substring to match (default `chronolog`); when nothing matches, it shoots the
primary screen instead.

**Known gotcha:** the script captures via `Graphics.CopyFromScreen`, which
reads the physical screen buffer. When the workstation is locked, that buffer
holds the lock screen, not the app underneath it, so a capture taken while
locked silently saves a picture of the lock screen instead of the app. A
capture that must survive a locked session needs `PrintWindow` with
`PW_RENDERFULLCONTENT` against the process whose executable path is under
`app\build` -- this script does not do that yet.
