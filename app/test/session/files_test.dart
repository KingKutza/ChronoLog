// The plaintext side: the three files load, hot-reload, and are written back on
// a debounce rather than once per frame. A refusal costs the edit, never the
// last good state.

import 'dart:convert';

import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/session/files.dart';
import 'package:chronolog/session/view_state.dart';
import 'package:chronolog/stage/tile.dart';
import 'package:flutter_test/flutter_test.dart';

import '../store/harness.dart' show ManualScheduler, MemoryFiles;

typedef Bound = ({
  MemoryFiles disk,
  ManualScheduler clock,
  SessionFiles files,
  ViewBook views,
  Stage stage,
  List<String> refusals,
});

Future<Bound> _bind() async {
  final disk = MemoryFiles();
  final clock = ManualScheduler();
  final refusals = <String>[];
  final files = SessionFiles('data', files: disk, scheduler: clock, onRefusal: refusals.add);
  final settings = chronologSettings();
  final views = ViewBook();
  final stage = Stage(tunable: settings.tunable);
  await bindSession(files, settings, views, stage);
  return (disk: disk, clock: clock, files: files, views: views, stage: stage, refusals: refusals);
}

void main() {
  test('a burst of edits writes once, after the debounce', () async {
    final bound = await _bind();
    for (var index = 0; index < 5; index++) {
      bound.views.setFocus('view:1', Rational.fromInt(index));
    }
    expect(bound.disk.find('chronolog.view'), isNull, reason: 'no write per change');
    await bound.clock.advance(const Duration(milliseconds: 400));
    final written = jsonDecode(bound.disk.find('chronolog.view')!) as Map;
    expect(written['sharedFocus'], '4');
    bound.files.dispose();
  });

  test('an external edit to the file hot-reloads', () async {
    final bound = await _bind();
    bound.disk.put(
      bound.files.views,
      jsonEncode({
        'lensOrder': ['board', 'list'],
      }),
    );
    await bound.clock.advance(const Duration(seconds: 2));
    expect(bound.views.visibleLenses.take(2), ['board', 'list']);
    bound.files.dispose();
  });

  test('a file that will not parse is reported and the last good state stays', () async {
    final bound = await _bind();
    bound.disk.put(
      bound.files.views,
      jsonEncode({
        'hidden': ['board'],
      }),
    );
    await bound.files.views.checkForChange();
    expect(bound.views.hidden, contains('board'));
    bound.disk.put(bound.files.views, '{ not json');
    await bound.files.views.checkForChange();
    expect(bound.refusals, isNotEmpty);
    expect(bound.views.hidden, contains('board'), reason: 'the last good state survives');
    bound.files.dispose();
  });

  test('the layout tree round-trips through its file', () async {
    final bound = await _bind();
    bound.stage.open(
      TileSpec(
        id: 'view:1',
        type: 'view',
        klass: 'lens',
        title: 'View',
        build: (context) => throw StateError('not built in this test'),
      ),
    );
    await bound.clock.advance(const Duration(milliseconds: 400));
    final written = bound.disk.find('chronolog.layout');
    expect(written, isNotNull);
    final other = Stage()..applyJson(Map<String, Object?>.from(jsonDecode(written!) as Map));
    expect(other.toJson()['root'], bound.stage.toJson()['root']);
    bound.files.dispose();
  });

  test('a theme file that will not read falls back to the shipped preset', () async {
    final bound = await _bind();
    expect((await bound.files.loadTheme('paper'))?.name, 'paper');
    bound.disk.put(bound.files.theme('paper'), '{ broken');
    expect((await bound.files.loadTheme('paper'))?.name, 'paper');
    expect(bound.refusals, isNotEmpty);
    bound.files.dispose();
  });
}
