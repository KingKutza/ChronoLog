// Where the data lives, and the plaintext sidecar seam.
//
// The data-dir property is a NEGATIVE one and that is the point: over randomly
// simulated profile environments -- APPDATA, HOME, USERPROFILE, XDG_DATA_HOME,
// LOCALAPPDATA all set and all plausible -- the resolved root never lands under
// any of them unless the owner named it. The AppData-killed ruling, asserted.

import 'dart:io';
import 'dart:math';

import 'package:chronolog/store/data_dir.dart';
import 'package:chronolog/store/plaintext_file.dart';
import 'package:test/test.dart';

import '../core/corpus.dart';
import 'harness.dart';

const List<String> profileVariables = [
  'APPDATA',
  'LOCALAPPDATA',
  'USERPROFILE',
  'HOME',
  'XDG_DATA_HOME',
  'XDG_CONFIG_HOME',
];

String separator(String path) => path.replaceAll('/', Platform.pathSeparator);

bool under(String path, String root) =>
    path.toLowerCase().startsWith(root.toLowerCase().replaceAll(RegExp(r'[\\/]+$'), ''));

void main() {
  test('the default root is the app\'s own directory and never a profile one', () {
    for (final seed in seeds(150)) {
      final random = Random(seed);
      final home = separator('/simulated/profile-$seed/user');
      final environment = <String, String>{
        for (final variable in profileVariables) variable: '$home${separator('/$variable')}',
        // Noise the resolver must not read either.
        'CHRONOLOG_PORT': '${random.nextInt(65535)}',
        'TMPDIR': '$home${separator('/tmp')}',
      };
      final executable = separator('/opt/chronolog-$seed/bin/chronolog.exe');
      final resolved = resolveDataRoot(environment: environment, executablePath: executable);
      expect(resolved, separator('/opt/chronolog-$seed/bin'), reason: 'seed $seed');
      for (final variable in profileVariables) {
        expect(under(resolved, environment[variable]!), isFalse, reason: 'seed $seed: $variable');
        expect(under(resolved, home), isFalse, reason: 'seed $seed: the profile root itself');
      }
    }
  });

  test('the variable and an explicit path are the only overrides, in that order', () {
    // Real absolute paths, because an override is resolved against the working
    // directory and a POSIX-looking string is not absolute on Windows.
    final byVariable = storePath(Directory.systemTemp.absolute.path, 'named-by-variable');
    final explicitly = storePath(Directory.systemTemp.absolute.path, 'named-explicitly');
    final environment = {
      dataDirectoryVariable: byVariable,
      'APPDATA': separator('/profile/AppData'),
    };
    expect(
      resolveDataRoot(environment: environment, executablePath: separator('/opt/app/bin/app')),
      byVariable,
    );
    expect(
      resolveDataRoot(
        explicit: explicitly,
        environment: environment,
        executablePath: separator('/opt/app/bin/app'),
      ),
      explicitly,
      reason: 'an explicit path outranks the variable',
    );
    expect(
      resolveDataRoot(
        explicit: '   ',
        environment: {'APPDATA': separator('/profile/AppData')},
        executablePath: separator('/opt/app/bin/app'),
      ),
      separator('/opt/app/bin'),
      reason: 'a blank override is not an override',
    );
  });

  test('a relative override becomes absolute, and a root executable keeps its separator', () {
    final relative = resolveDataRoot(
      explicit: 'data',
      environment: const {},
      executablePath: separator('/opt/app/bin/app'),
    );
    expect(relative, Directory('data').absolute.path);
    expect(
      parentDirectory('${separator('C:/')}chronolog.exe'),
      anyOf(equals(separator('C:/')), equals('C:${Platform.pathSeparator}')),
    );
  });

  test('storePath joins one way, whether the root carries a separator or not', () {
    expect(
      storePath(separator('/data'), 'chronolog.chronolog'),
      separator('/data/chronolog.chronolog'),
    );
    expect(
      storePath(separator('/data/'), 'chronolog.chronolog'),
      separator('/data/chronolog.chronolog'),
    );
  });

  group('the plaintext sidecar', () {
    late Directory root;
    late ManualScheduler scheduler;

    setUp(() async {
      root = await tempRoot('sidecar');
      scheduler = ManualScheduler();
    });
    tearDown(() async => removeRoot(root));

    PlaintextFile sidecar(String name) =>
        PlaintextFile(storePath(root.path, name), scheduler: scheduler);

    /// One poll, fired on the spec's clock and waited on properly.
    Future<void> poll(PlaintextFile file) async {
      await scheduler.advance(file.interval);
      await file.polling;
    }

    test('an absent file reads as null, and a written one reads back verbatim', () async {
      final file = sidecar('theme.txt');
      expect(await file.read(), isNull);
      const text = 'accent: "#c0ffee"\nzone-fill: true\n';
      await file.write(text);
      expect(await file.read(), text);
      expect(File(storePath(root.path, 'theme.txt')).readAsStringSync(), text);
      expect(
        File(storePath(root.path, 'theme.txt.tmp')).existsSync(),
        isFalse,
        reason: 'the atomic write leaves no temporary behind',
      );
    });

    test('a hot reload fires on an external change and never on our own write', () async {
      for (final seed in seeds(60)) {
        final random = Random(seed);
        final file = sidecar('settings-$seed.txt');
        final seen = <String>[];
        await file.write('generation 0');
        file.watch(seen.add);

        // Our own writes, interleaved with polls: silence.
        for (var index = 1; index <= 1 + random.nextInt(3); index += 1) {
          await file.write('generation $index');
          await poll(file);
        }
        expect(seen, isEmpty, reason: 'seed $seed: our own write is not a change');

        // Somebody edits the file in their editor.
        final edited = 'edited by hand ${random.nextInt(1 << 20)}';
        File(storePath(root.path, 'settings-$seed.txt')).writeAsStringSync(edited);
        await poll(file);
        expect(seen, [edited], reason: 'seed $seed');

        // And an unchanged file, polled again, says nothing more.
        await poll(file);
        expect(seen, [edited], reason: 'seed $seed');
        file.stop();
        await poll(file);
        expect(scheduler.armed, 0, reason: 'seed $seed: stop really stops');
      }
    });

    test('watching twice replaces the callback rather than stacking a second poll', () async {
      final file = sidecar('layout.txt');
      await file.write('one pane');
      final first = <String>[];
      final second = <String>[];
      file.watch(first.add);
      file.watch(second.add);
      File(storePath(root.path, 'layout.txt')).writeAsStringSync('two panes');
      await poll(file);
      expect(first, isEmpty);
      expect(second, ['two panes']);
      file.stop();
    });
  });
}
