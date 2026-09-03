// A SETTINGS EDIT RIDES THE ONE HISTORY (ISSUES 9.2, Don: "Settings edits like
// theme changes should be subject to undo").
//
// Don's words: "Settings edits like theme changes should be subject to undo."
// Today they are not, and the cause is two stores with one of them journalled.
// Undo is the Editor's -- "the ops list IS the undo entry", a transaction that
// mutates, settles, diffs, journals and pushes an entry -- and Settings is a
// different store, written through `set`/`setText` with no ops, no journal line
// and no history, so re-authoring a palette is unrecoverable except from memory,
// which is what Don hit while playing with the colours.
//
// The fix direction in the entry is a MELT, not a second mechanism: a settings
// write is an authored change like any other and rides the SAME journal, so one
// history holds both and ctrl+z crosses the boundary without the person knowing
// there was one. Two undo stacks would be the enum in another costume.
//
// RULED ENOUGH TO STATE: a write a PERSON said through a card or a field -- a
// colour, a theme, a lens number -- is an edit and belongs in the history. Don's
// own example is a theme change. OPEN, and not asserted here: whether a write a
// GESTURE produced (pan, zoom, focus) journals at all, and if so whether per
// notch or per gesture. Nothing below pans or zooms.
//
// THE CONTRACT, as the signatures it should have (none exist yet):
//
//   Editor(store, {settings: Tunable?, settingsStore: Settings?})
//       // the Editor is handed the settings STORE, not only its reader
//   String? Editor.setSetting(String key, String written);
//       // the card's door for both families (tunable expressions and text
//       // keys -- Settings already knows which a key is). Accepted: the value
//       // takes effect, one undo entry is pushed, one journal line is written.
//       // Refused (an expression that will not read): the reason comes back,
//       // nothing changes, no entry.
//   Editor.undo() / redo() walk settings entries and record entries in ONE order.
//       // What undo restores is the OVERRIDE SET: undoing the first write of a
//       // key restores the ABSENCE of an override (the file records only
//       // overrides, so a changed shipped default still reaches an install),
//       // never the shipped value written back as an override.
//
// Generative: a seeded interleaving of record edits, tunable writes and text
// writes, unwound in reverse and compared state for state.

import 'dart:io';
import 'dart:math';

import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/edit/editor.dart';
import 'package:chronolog/session/settings.dart';
import 'package:chronolog/store/document_store.dart';
import 'package:test/test.dart';

import '../core/corpus.dart';
import '../store/harness.dart';
import 'harness.dart' show recordsOf;

final int runSeed =
    int.tryParse(Platform.environment['CHRONOLOG_SEED'] ?? '') ??
    DateTime.now().microsecondsSinceEpoch;

String seeded(String message) => '$message  (set CHRONOLOG_SEED=$runSeed to reproduce)';

typedef Bench = ({Editor editor, Settings settings, Directory root});

Future<Bench> openWithSettings(Document document, String label) async {
  final root = await tempRoot(label);
  final store = DocumentStore(dataRoot: root.path, scheduler: ManualScheduler(), establish: () => document);
  await store.load();
  final settings = chronologSettings();
  return (
    editor: Editor(store, settings: settings.tunable, settingsStore: settings),
    settings: settings,
    root: root,
  );
}

/// Everything a person authored, in one string: the records and the settings
/// overrides. What undo must give back, step for step.
String stateOf(Bench bench) {
  final overrides = bench.settings.toJson();
  final keys = overrides.keys.toList()..sort();
  return '${recordsOf(bench.editor.document)}|${[for (final key in keys) '$key=${overrides[key]}']}';
}

void main() {
  // ignore: avoid_print
  print('SETTINGS UNDO RUN SEED: $runSeed  (set CHRONOLOG_SEED=$runSeed to reproduce)');
  final random = Random(runSeed);

  late Bench bench;
  tearDown(() => removeRoot(bench.root));

  test('a theme change is one undo entry, and undo gives the palette back', () async {
    bench = await openWithSettings(createEmptyWorkspaceDocument(), 'settings-undo-theme');
    final (:editor, :settings, root: _) = bench;
    final shipped = settings.text('theme.name');
    final chosen = 'palette-${random.nextInt(1 << 16)}';
    final depth = editor.history.length;

    expect(editor.setSetting('theme.name', chosen), isNull, reason: seeded('a theme name is accepted'));
    expect(settings.text('theme.name'), chosen, reason: seeded('the write took effect'));
    expect(
      editor.history.length,
      depth + 1,
      reason: seeded('ISSUES 9.2: a theme change is an authored edit and pushes ONE undo entry'),
    );
    expect(editor.undo(), isTrue);
    expect(
      settings.text('theme.name'),
      shipped,
      reason: seeded('ISSUES 9.2: undo gives back the palette Don was on before he re-authored it'),
    );
    expect(editor.redo(), isTrue);
    expect(settings.text('theme.name'), chosen, reason: seeded('redo puts it back'));
  });

  test('one history holds record edits and settings edits and unwinds them in order', () async {
    bench = await openWithSettings(Corpus(runSeed).document(), 'settings-undo-history');
    final (:editor, :settings, root: _) = bench;
    final ids = editor.document.events.keys.toList();
    expect(ids, isNotEmpty, reason: seeded('the corpus has objects to retitle'));

    // Every act writes something DIFFERENT from what stands: a write equal to
    // the current value is a no-op, and a no-op is rightly no entry.
    var stamp = 0;
    final acts = <String Function()>[
      () {
        final id = ids[random.nextInt(ids.length)];
        final event = editor.document.events[id]!;
        final title = 'retitled ${stamp++} ${random.nextInt(1 << 16)}';
        editor.commit('Retitle', editor.document.put('events', id, event.copyWith(payload: {'title': title})));
        return 'retitle $id';
      },
      () {
        final gap = '${1 + random.nextInt(24)} * 2 + ${stamp++}';
        expect(editor.setSetting('chrome.gap', gap), isNull, reason: seeded('a lens number is accepted'));
        return 'chrome.gap = $gap';
      },
      () {
        final name = 'palette-${stamp++}-${random.nextInt(1 << 16)}';
        expect(editor.setSetting('theme.name', name), isNull);
        return 'theme.name = $name';
      },
    ];

    final states = <String>[stateOf(bench)];
    final said = <String>[];
    final steps = 6 + random.nextInt(6);
    for (var step = 0; step < steps; step += 1) {
      said.add(acts[random.nextInt(acts.length)]());
      states.add(stateOf(bench));
    }
    expect(states.toSet().length, states.length, reason: seeded('every act changed something'));

    for (var index = states.length - 1; index > 0; index -= 1) {
      expect(editor.undo(), isTrue, reason: seeded('undo ${states.length - index} of ${states.length - 1}'));
      expect(
        stateOf(bench),
        states[index - 1],
        reason: seeded(
          'ISSUES 9.2: undoing "${said[index - 1]}" did not restore the state before it. One history, '
          'one ctrl+z, whatever was last touched. Acts, in order: $said',
        ),
      );
    }
    expect(editor.undo(), isFalse, reason: seeded('nothing left to undo'));
    for (var index = 1; index < states.length; index += 1) {
      expect(editor.redo(), isTrue);
      expect(stateOf(bench), states[index], reason: seeded('redo ${said[index - 1]}'));
    }
    // A theme value in settings' own reader agrees with the history's account.
    expect(settings.text('theme.name'), isNotEmpty);
  });

  test('a refused expression writes no entry and changes nothing', () async {
    bench = await openWithSettings(createEmptyWorkspaceDocument(), 'settings-undo-refusal');
    final (:editor, :settings, root: _) = bench;
    final was = settings.value('chrome.gap');
    final depth = editor.history.length;
    final refusal = editor.setSetting('chrome.gap', '1 +');
    expect(refusal, isNotNull, reason: seeded('an expression that will not read is refused with its reason'));
    expect(settings.value('chrome.gap'), was, reason: seeded('the last good value stays'));
    expect(editor.history.length, depth, reason: seeded('a refusal is not an edit: no entry to undo'));
  });
}
