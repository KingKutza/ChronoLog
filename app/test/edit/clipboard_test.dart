// COPY, CUT, PASTE, DUPLICATE (ISSUES 9.2, Don: "Copy/paste duplicates of
// events"; and Don's answer on what a copy carries).
//
// Verified in the entry: none exists. The lens context menu carries a permanent
// stub row `Paste -- nothing copied` with no Copy beside it, and the keyboard
// map has no copy, cut, paste or duplicate chord.
//
// Don's ruling on what a copy carries, whole: "ALL of the object's own settings
// -- properties, traits, magnitudes, colour, kind, everything on the record --
// and NO staples." His ground: "I cannot think of a clean way to drop staples
// for linear calendar frames and keep the rest that would generalize well to
// edge cases" -- so no partition of staples into positional and affiliative is
// attempted; the copy arrives connected to nothing and the paste says the one
// sentence it can, the placement at the drop. Anything else the person re-says
// on the card. The proposed affiliation-carrying default is withdrawn.
//
// THE CONTRACT, as the signatures it should have (none exist yet):
//
//   // lib/edit/gestures.dart, the extension on Editor beside createAt/moveFact
//   List<Event> get clipboard;                 // what the last copy carried; empty when nothing copied
//   void copyObjects(Iterable<String> ids);    // snapshots the records; writes nothing, no undo entry
//   void cutObjects(Iterable<String> ids);     // copy, then delete -- ONE undo entry
//   List<String> pasteObjects(String frameId, Rational atDays);
//       // new ids. Each carries every own field of its source -- traits,
//       // magnitudes, payload, extra (colour, kind, handling) -- and exactly one
//       // staple: its placement at [atDays] on [frameId]. The pointer's
//       // coordinate from the menu; ONE undo entry for the whole paste.
//   List<String> duplicateObjects(Iterable<String> ids);
//       // copy + paste at the source's own coordinate, on its own frame, moved
//       // by `edit.pasteStepDays` -- the keyboard's landing. One undo entry.
//
//   // settings, like every other chord and number
//   chromeKeyDefaults: 'keys.copy', 'keys.cut', 'keys.paste', 'keys.duplicate'
//   editTunableDefaults: 'edit.pasteStepDays'   (a one-math formula, not a literal)
//
// Not asserted here, and why: the context-menu rows (Copy / Cut beside an
// enabled Paste) live on `viewMenuRows`, whose `ViewTileController` is under
// concurrent edit; and where a MULTI-object paste lands its second object
// (relative spacing kept, or all at the drop) is unruled -- the tests below
// assert only the per-object contract for a paste of several.
//
// Generative: a seeded source record with random traits, payload, magnitudes
// and colour, in a group, stapled to another object, placed on a calendar; a
// seeded drop coordinate on a second calendar.

import 'dart:io';
import 'dart:math';

import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/core/staples.dart';
import 'package:chronolog/edit/editor.dart';
// The doors this file spells belong to the gesture extension (see the header); the
// import is unused only until they exist.
// ignore: unused_import
import 'package:chronolog/edit/gestures.dart';
import 'package:test/test.dart';

import '../helpers/projection_scene.dart';
import 'harness.dart';

final int runSeed =
    int.tryParse(Platform.environment['CHRONOLOG_SEED'] ?? '') ??
    DateTime.now().microsecondsSinceEpoch;

String seeded(String message) => '$message  (set CHRONOLOG_SEED=$runSeed to reproduce)';

const String home = 'calendar:a', away = 'calendar:b';

/// Whole days on the shared axis for a civil date, the unit every fact's `day` counts in.
Rational civilDays(int year, int month, int day) => Rational(daysFromCivil(BigInt.from(year), month, day));

/// A source worth copying: every own field authored, and connected three ways
/// -- placed, grouped, stapled to another object -- so "no staples" is a claim
/// with teeth.
({Document document, String source, String other, Rational placedAt}) world(Random random) {
  final scene = Scene()
    ..calendar(home)
    ..calendar(away);
  final day = 1 + random.nextInt(28), hour = random.nextInt(24);
  final source = scene.object(
    title: 'Source ${random.nextInt(1 << 16)}',
    duration: '${15 + random.nextInt(600)}',
  );
  scene.document = scene.document.put(
    'events',
    source,
    scene.document.events[source]!.copyWith(
      traits: random.nextBool() ? const ['event', 'task', 'todo'] : const ['event'],
      payload: {
        ...?scene.document.events[source]!.payload,
        'description': 'said once, seed $runSeed',
      },
      extra: {
        'color': '#${random.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
        'display': {'sigil': 'milestone'},
      },
    ),
  );
  scene.place(home, civil(2026, 9, day, hour), event: source);
  scene.group('frame:club', [source]);
  final otherPlacement = scene.place(home, civil(2026, 9, day, (hour + 1) % 24), title: 'Other');
  final other = scene.document.relations[otherPlacement]!.event!;
  // A silent staple to another object: all of this is all of that.
  scene.staple(ends: [ObjectEnd(source), ObjectEnd(other)]);
  return (
    document: scene.document,
    source: source,
    other: other,
    placedAt: civilDays(2026, 9, day) + Rational.fromInt(hour, 24),
  );
}

/// The record without its identity: what a copy is a copy OF.
Map<String, Object?> ownFields(Event event) => event.toJson()..remove('id');

void main() {
  // ignore: avoid_print
  print('CLIPBOARD RUN SEED: $runSeed  (set CHRONOLOG_SEED=$runSeed to reproduce)');
  final random = Random(runSeed);

  late Bench bench;
  late Editor editor;
  tearDown(() => closeEditor(bench));

  test('a paste carries every own field of the record and exactly one staple: its placement', () async {
    final made = world(random);
    bench = await openEditor(made.document, label: 'clipboard-fields');
    editor = bench.editor;
    final before = editor.document.events[made.source]!;
    final stapledBefore = editor.engine.indexes.staplesOf(made.source).length;
    expect(stapledBefore, greaterThanOrEqualTo(3), reason: seeded('the premise: placed, grouped, stapled'));

    editor.copyObjects([made.source]);
    expect(editor.clipboard.map((event) => event.id), equals([made.source]));

    final at = civilDays(2026, 10, 1 + random.nextInt(28)) + Rational.fromInt(random.nextInt(24), 24);
    final pasted = editor.pasteObjects(away, at);
    expect(pasted, hasLength(1), reason: seeded('one copied, one pasted'));
    final copy = editor.document.events[pasted.single];
    expect(copy, isNotNull, reason: seeded('the paste is a real record in the document'));
    expect(copy!.id, isNot(before.id));
    expect(
      ownFields(copy),
      equals(ownFields(before)),
      reason: seeded(
        'ISSUES 9.2 (Don): ALL of the object\'s own settings -- properties, traits, '
        'magnitudes, colour, kind, everything on the record -- carry.',
      ),
    );

    final staples = editor.engine.indexes.staplesOf(copy.id);
    expect(
      staples,
      hasLength(1),
      reason: seeded(
        'ISSUES 9.2 (Don): NO staples carry. The copy arrives connected to nothing and the '
        'paste says the one sentence it can -- the placement at the drop. Found '
        '${staples.length}.',
      ),
    );
    expect(isPlacement(staples.single, copy.id), isTrue, reason: seeded('the one staple is a placement'));
    expect(staples.single.frame, away, reason: seeded('placed on the frame the pointer was over'));
    expect(editor.engine.indexes.directGroupsOf(copy.id), isEmpty, reason: seeded('no affiliation carries'));
    final fact = editor.engine.explicitFacts(away).where((fact) => fact.event.id == copy.id).toList();
    expect(fact.map((fact) => fact.day), equals([at]), reason: seeded('the paste lands AT the drop'));

    expect(
      editor.engine.indexes.staplesOf(made.source).length,
      stapledBefore,
      reason: seeded('the source is untouched by a copy and a paste'),
    );
    expect(ownFields(editor.document.events[made.source]!), equals(ownFields(before)));
  });

  test('copy writes nothing; paste and cut are one undo entry each; undo of a cut restores every staple', () async {
    final made = world(random);
    bench = await openEditor(made.document, label: 'clipboard-history');
    editor = bench.editor;
    final depth = editor.history.length;
    final untouched = recordsOf(editor.document);

    editor.copyObjects([made.source]);
    expect(editor.history.length, depth, reason: seeded('a copy is not an edit: no entry, no journal line'));
    expect(recordsOf(editor.document), untouched);

    final at = civilDays(2026, 10, 1 + random.nextInt(28));
    final pasted = editor.pasteObjects(home, at);
    expect(editor.history.length, depth + 1, reason: seeded('a paste is ONE entry'));
    expect(editor.undo(), isTrue);
    expect(editor.document.events.containsKey(pasted.single), isFalse, reason: seeded('undo unmakes the paste'));
    expect(recordsOf(editor.document), untouched, reason: seeded('and nothing else moved'));
    expect(editor.redo(), isTrue);

    final beforeCut = recordsOf(editor.document);
    final stapledBefore = editor.engine.indexes.staplesOf(made.source).length;
    editor.cutObjects([made.source]);
    expect(editor.history.length, depth + 2, reason: seeded('a cut is ONE entry: copy, then delete, together'));
    expect(editor.document.events.containsKey(made.source), isFalse, reason: seeded('cut removes the source'));
    expect(editor.clipboard.map((event) => event.id), equals([made.source]), reason: seeded('and holds it'));
    expect(editor.undo(), isTrue);
    expect(
      recordsOf(editor.document),
      beforeCut,
      reason: seeded('one undo puts the source back with every one of its $stapledBefore staples'),
    );
  });

  test('duplicate lands at the source coordinate moved by the settings-fed step, on its own frame', () async {
    final made = world(random);
    bench = await openEditor(made.document, label: 'clipboard-duplicate');
    editor = bench.editor;
    final step = editor.setting('edit.pasteStepDays');
    expect(step, isNot(Rational.zero), reason: seeded('the keyboard landing is a step, said as a setting'));

    final depth = editor.history.length;
    final twins = editor.duplicateObjects([made.source, made.other]);
    expect(twins, hasLength(2), reason: seeded('one duplicate per object selected'));
    expect(editor.history.length, depth + 1, reason: seeded('a duplicate of a selection is ONE entry'));
    for (final (index, id) in twins.indexed) {
      final original = [made.source, made.other][index];
      final staples = editor.engine.indexes.staplesOf(id);
      expect(staples, hasLength(1), reason: seeded('a duplicate carries exactly its placement'));
      expect(staples.single.frame, home, reason: seeded('on the frame the source was placed on'));
      final was = editor.engine.explicitFacts(home).where((fact) => fact.event.id == original).single.day;
      final now = editor.engine.explicitFacts(home).where((fact) => fact.event.id == id).single.day;
      expect(now, was + step, reason: seeded('ISSUES 9.2: the keyboard paste lands one step from its source'));
      expect(ownFields(editor.document.events[id]!), equals(ownFields(editor.document.events[original]!)));
    }
  });

  test('the chords are settings keys like every other keys.*, and the step is a tunable', () async {
    bench = await openEditor(world(random).document, label: 'clipboard-keys');
    editor = bench.editor;
    final settings = chronologSettings();
    for (final key in const ['keys.copy', 'keys.cut', 'keys.paste', 'keys.duplicate']) {
      expect(
        settings.text(key),
        isNotEmpty,
        reason: seeded('ISSUES 9.2: "$key" is a chord in the one keyboard map, shipped with a default'),
      );
      expect(settings.contested(key), isFalse, reason: seeded('"$key" collides with another binding'));
    }
    expect(
      settings.keys,
      contains('edit.pasteStepDays'),
      reason: seeded('the keyboard landing offset is a settings key with a formula value, never a literal'),
    );
  });
}
