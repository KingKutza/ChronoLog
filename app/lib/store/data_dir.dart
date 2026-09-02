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
// ONE EXCEPTION, AND IT IS NOT A PROFILE DIRECTORY (ISSUES 9.2, hazard found
// live): Don's whole document -- snapshot, journal, layout, view and settings --
// sat in `app/build/windows/x64/runner/Debug/`, beside the Debug executable
// exactly as the portable ruling says, and that folder is what `flutter clean`
// deletes outright and `flutter build` rewrites. A BUILD TREE IS NOT A HOME. So
// a data root resolved from an executable under a `build` directory resolves to
// the parent of that build tree instead of beside the executable. It is still
// the app's own directory in the only sense that matters -- the checkout the
// build came out of -- and it survives the commands that rebuild the exe.
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
  return outsideBuildTree(parentDirectory(executablePath ?? Platform.resolvedExecutable));
}

/// The name a build tree wears. One word, and it is a SETTING of the resolver
/// rather than a literal buried in a branch, so a toolchain that calls its
/// output something else is one line here.
const String buildTreeName = 'build';

/// [directory], unless it lies inside a build tree -- in which case the parent
/// of that tree, which is the checkout the executable was built out of.
///
/// The build segment NEAREST the executable is the one that wins: a person whose
/// home directory is called `build` would otherwise have their data hoisted to
/// the drive root. Both separators are honoured, because a Windows path may
/// carry either and the segment must be recognised in both spellings.
String outsideBuildTree(String directory) {
  final segments = directory.split(RegExp(r'[/\\]'));
  for (var index = segments.length - 1; index > 0; index -= 1) {
    if (segments[index].toLowerCase() != buildTreeName) continue;
    final above = segments.take(index).join(Platform.pathSeparator);
    return above.isEmpty || above.endsWith(':') ? '$above${Platform.pathSeparator}' : above;
  }
  return directory;
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

/// An AUTHORED path, or [fallback] when the author has written none.
///
/// THE ONE RESOLVER. The document's own save location and every ICS location
/// read the same way, because "where a thing lives" has one meaning in this
/// program: a path the user wrote, and beside-the-app when they wrote nothing.
/// There is no blessed directory at either end -- the fallback is the portable
/// default, not a home the app insists on.
String authoredPath(String? authored, String fallback) {
  final trimmed = (authored ?? '').trim();
  return trimmed.isEmpty ? fallback : trimmed;
}

/// Authored paths, ONE PER LINE -- a LIST, never a single location (Don, 8.31:
/// "only a location to look for .ics file and even then only one such
/// location"). Blank lines are not locations, and an empty setting answers with
/// the fallback so the list is never a hole.
///
/// A list of TEXT settings is packed into one key the way `keys.lensDigits`
/// packs a list of keys: the one math has no lists, and a path is not
/// arithmetic, so the newline is the separator and the field is multi-line.
/// One line break, however the host spells it: a path list a person typed on
/// Windows and a path list an editor rewrote are the same list.
final RegExp lineBreak = RegExp(r'\r\n|\r|\n');

List<String> authoredPaths(String? authored, String fallback) {
  final lines = [
    for (final line in (authored ?? '').split(lineBreak))
      if (line.trim().isNotEmpty) line.trim(),
  ];
  return lines.isEmpty ? [fallback] : lines;
}

/// A named file inside a data root. One join, so the journal, the snapshot and
/// every plaintext sidecar spell a path the same way.
String storePath(String root, String name) =>
    root.endsWith('/') || root.endsWith(Platform.pathSeparator)
    ? '$root$name'
    : '$root${Platform.pathSeparator}$name';
