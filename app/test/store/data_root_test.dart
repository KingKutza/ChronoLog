// THE DATA NEVER LIVES IN A BUILD FOLDER (ISSUES 9.2, hazard found live).
//
// Don's live document sat in `app/build/windows/x64/runner/Debug/` -- beside
// the Debug executable, exactly as the portable ruling says -- and that folder
// is what `flutter clean` deletes and `flutter build` rewrites. The rule:
//
//   A data root resolved from an executable that lives under a `build`
//   directory is not inside that build tree. (The explicit path and the
//   environment variable still win, as today.)

import 'dart:io';

import 'package:chronolog/store/data_dir.dart';
import 'package:test/test.dart';

void main() {
  test('an executable under build/ does not put the data beside itself', () {
    final sep = Platform.pathSeparator;
    final exe = [
      'C:',
      'Users',
      'someone',
      'ChronoLog',
      'app',
      'build',
      'windows',
      'x64',
      'runner',
      'Debug',
      'chronolog.exe',
    ].join(sep);
    final root = resolveDataRoot(executablePath: exe, environment: const {});
    expect(
      root.split(sep),
      isNot(contains('build')),
      reason:
          'ISSUES 9.2: the live chronolog, journal, layout and settings were in the Debug '
          'output folder. A build tree is not a home; resolve outside it (found $root).',
    );
  });
}
