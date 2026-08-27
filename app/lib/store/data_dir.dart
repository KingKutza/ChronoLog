// Where the data lives, and where it never lives.
//
// ChronoLog is a PORTABLE app. Its data directory defaults to the app's own
// directory -- beside the executable -- and the only ways to move it are an
// explicit path or the CHRONOLOG_DATA_DIR variable. There is no branch below
// that reads APPDATA, HOME, XDG_DATA_HOME, USERPROFILE or any other profile
// location, and that absence IS the ruling: an OS profile directory was killed
// as a data home, so the resolver cannot land in one by accident because it
// cannot name one at all.
//
// Pure resolution. Nothing here touches the disk; the store creates the
// directory when it first writes.

import 'dart:io';

/// The one override variable.
const String dataDirectoryVariable = 'CHRONOLOG_DATA_DIR';

/// The data root, in priority order: an explicit path, then the variable, then
/// the app's own directory.
///
/// [executablePath] is injected so a spec can resolve without depending on where
/// the test runner's binary happens to live. A platform whose executable
/// directory is not writable (Android's app bundle) passes [explicit] -- its
/// app-private directory, which is still not a profile directory.
String resolveDataRoot({
  String? explicit,
  Map<String, String>? environment,
  String? executablePath,
}) {
  final named =
      _named(explicit) ?? _named((environment ?? Platform.environment)[dataDirectoryVariable]);
  if (named != null) return Directory(named).absolute.path;
  return parentDirectory(executablePath ?? Platform.resolvedExecutable);
}

String? _named(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

/// The directory holding [path]. Both separators are honoured because a Windows
/// path may carry either, and a drive root keeps its separator so `C:\app.exe`
/// resolves to `C:\` rather than to the drive-relative `C:`.
String parentDirectory(String path) {
  final cut = [path.lastIndexOf('/'), path.lastIndexOf(Platform.pathSeparator)].reduce(_larger);
  if (cut < 0) return Directory(path).absolute.parent.path;
  final parent = path.substring(0, cut);
  return parent.isEmpty || parent.endsWith(':') ? '$parent${Platform.pathSeparator}' : parent;
}

int _larger(int a, int b) => a > b ? a : b;

/// A named file inside a data root. One join, so the journal, the snapshot and
/// every plaintext sidecar spell a path the same way.
String storePath(String root, String name) =>
    root.endsWith('/') || root.endsWith(Platform.pathSeparator)
    ? '$root$name'
    : '$root${Platform.pathSeparator}$name';
