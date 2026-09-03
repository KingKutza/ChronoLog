// A JUMP TAKES A COORDINATE (ISSUES 9.2, Don).
//
// "We have no clear jump-to-date option." Correct -- there is no way to say
// WHERE, only how far. The context bar offers `«` back a window, `‹` back one
// span unit, `›` forward, `»` forward a window, and Today; so the vocabulary is
// relative steps plus one absolute destination, now, and reaching February 2200
// means holding an arrow -- which is exactly how Don got there.
//
// THE CONTRACT this file names, from the ISSUES entry's own fix direction:
//
//   ONE DOOR on the context bar beside the steps, on EVERY time lens, whose
//   words say jump ("Jump to…", "Go to a date…" -- matched by /jump|go to/i,
//   the wording is the implementer's). It opens the same variable-precision
//   coordinate field every other coordinate uses (`coordinate_entry.dart`:
//   "Feb 2200", "2200", a full instant), and needs no new parser.
//
//   THE JUMP LANDS AT THE DEPTH GIVEN: a year lands on the year, a month on the
//   month, an instant on the instant -- `law.toDays(parseCoordinateEntry(text,
//   law).coordinate)` of the lens's primary frame's own law. It rides the
//   existing glide (motion.duration, the ratified curve) rather than snapping;
//   this file asserts the landing after the glide settles.
//
//   ONE DERIVATION: `ViewTileController.jumpTo(Rational days)` glides the focus
//   to a day ordinal, and `jumpToNow()` becomes `jumpTo(nowDays())` -- the
//   special case where the coordinate is now, not a second mechanism. Named
//   here as the signature; not referenced in code so the file still compiles
//   and every red below is an assertion, never a missing symbol.
//
// The destination is drawn from the seed -- a year, and a depth of one to three
// levels -- so no date here is a golden. Set CHRONOLOG_SEED to reproduce.
//
// A minimap click as the same act said with the hand is the pick-on-a-surface
// work already authored elsewhere and is not asserted here.

import 'dart:io';
import 'dart:math';

import 'package:chronolog/app.dart';
import 'package:chronolog/chrome/context_bar.dart';
import 'package:chronolog/chrome/controls.dart';
import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/core/coordinate_entry.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/edit/editor.dart';
import 'package:chronolog/lens/theme.dart';
import 'package:chronolog/lens/view_tile.dart';
import 'package:chronolog/session/lens_catalog.dart';
import 'package:chronolog/session/settings.dart';
import 'package:chronolog/session/view_state.dart';
import 'package:chronolog/stage/tile.dart';
import 'package:chronolog/store/document_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../store/harness.dart';

const String wallTime = 'frame:wall-time';
const String tileId = 'view:1';

/// The run's seed: `CHRONOLOG_SEED` when set, else the clock; every reason
/// below names it.
final int runSeed =
    int.tryParse(Platform.environment['CHRONOLOG_SEED'] ?? '') ??
    DateTime.now().microsecondsSinceEpoch;

/// The words a jump door wears, however the implementer phrases them.
final RegExp jumpWords = RegExp(r'jump|go to', caseSensitive: false);

/// A door whose tooltip or spoken label says jump. Bars name their glyph
/// controls through `namedAction`, which gives the chip a Tooltip and a
/// Semantics label -- either one is the words a person gets.
Finder jumpDoor() => find.byWidgetPredicate(
  (widget) =>
      (widget is Tooltip && jumpWords.hasMatch(widget.message ?? '')) ||
      (widget is Semantics && jumpWords.hasMatch(widget.properties.label ?? '')),
);

typedef Bed = ({ViewBook views, Settings settings, Editor editor});

/// The shipped lenses that draw time: the surfaces a jump is a verb on.
List<LensSpec> timeLenses() {
  registerShippedLenses();
  return [
    for (final spec in lensCatalog.values)
      if (spec.isTimeSurface && lensPainters.containsKey(spec.id)) spec,
  ];
}

/// A real view tile showing [lens] under a real context bar, the bar's actions
/// dispatched to the tile's controller exactly as the app wires them.
Future<Bed> layOut(WidgetTester tester, String lens) async {
  registerShippedLenses();
  final store = DocumentStore(
    dataRoot: 'memory',
    files: MemoryFiles(),
    scheduler: ManualScheduler(),
    establish: createEmptyWorkspaceDocument,
  );
  await store.load();
  final settings = chronologSettings();
  final editor = Editor(store, settings: settings.tunable);
  final views = ViewBook()..defaultFrames = [wallTime];
  views.of(tileId).lensId = lens;
  final stage = Stage(tunable: settings.tunable, onLens: views.setLens);
  final tile = ViewTile(
    tileId: tileId,
    surface: (
      editor: editor,
      settings: settings,
      views: views,
      stage: stage,
      objectCard: null,
      frameCard: null,
      settingsCard: null,
    ),
  );
  stage.open(TileSpec(id: tileId, type: 'view', klass: 'lens', title: 'View', build: (_) => tile));
  final chrome = Chrome(
    settings: settings,
    stage: stage,
    views: views,
    editor: editor,
    onAction: (id, action) => viewTileControllers[id]?.runAction(action),
  );
  tester.view.physicalSize = const Size(1800, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: themeDataFor(shipped['paper']!),
      home: Scaffold(
        body: ChromeScope(
          chrome: chrome,
          child: Column(
            children: [
              // The bar at its own content thickness, as the stage would give it.
              SizedBox(
                height: settings.value('chrome.barHeight').toDouble(),
                child: const ContextBar(),
              ),
              Expanded(child: tile),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (views: views, settings: settings, editor: editor);
}

void main() {
  testWidgets('every time lens\'s bar wears one door that takes a coordinate', (tester) async {
    // "It is one derivation for every lens, since every lens already has a
    // focus and a law." So the door is on every bar, not on one lens's.
    for (final spec in timeLenses()) {
      await layOut(tester, spec.id);
      expect(
        jumpDoor(),
        findsWidgets,
        reason:
            'seed $runSeed: ISSUES 9.2 "We have no clear jump-to-date option" -- ${spec.title}\'s '
            'bar offers relative steps and Today, and no door that takes a coordinate. One door '
            'beside the steps, whose words say jump.',
      );
    }
  });

  testWidgets('the jump lands at the coordinate typed, at the depth typed', (tester) async {
    final random = Random(runSeed);
    final lenses = timeLenses();
    final spec = lenses[random.nextInt(lenses.length)];
    final bed = await layOut(tester, spec.id);
    final law = bed.editor.engine.lawOf(wallTime);
    // A destination far enough from now that the landing cannot be mistaken
    // for standing still, at a depth of one, two or three levels.
    final year = 1200 + random.nextInt(1800);
    final month = 1 + random.nextInt(12);
    final day = 1 + random.nextInt(28);
    final depth = 1 + random.nextInt(3);
    final typed = [year, month, day].take(depth).join(' ');
    // A harness fact, proven before the door is touched: the field every other
    // coordinate uses reads this text at this depth, and the law places it.
    final read = parseCoordinateEntry(typed, law);
    expect(read.coordinate.levels, hasLength(depth), reason: 'seed $runSeed: "$typed" reads at depth $depth');
    final expected = law.toDays(read.coordinate);
    final before = bed.views.focusOf(tileId);
    expect(expected, isNot(equals(before)), reason: 'seed $runSeed: the destination is elsewhere');

    final door = jumpDoor();
    expect(
      door,
      findsWidgets,
      reason:
          'seed $runSeed: ISSUES 9.2 -- ${spec.title}\'s bar has no jump door; there is no way to '
          'say WHERE, only how far.',
    );
    await tester.tap(door.first);
    await tester.pumpAndSettle();
    final field = find.byType(TextField);
    expect(
      field,
      findsWidgets,
      reason:
          'seed $runSeed: the door opens the variable-precision coordinate field every other '
          'coordinate uses -- no new parser, no picker of three boxes.',
    );
    await tester.enterText(field.last, typed);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(
      bed.views.focusOf(tileId),
      equals(expected),
      reason:
          'seed $runSeed: a jump to "$typed" on ${spec.title} landed at ${bed.views.focusOf(tileId)}, '
          'not at $expected -- the coordinate at the depth typed, through the frame\'s own law.',
    );
  });
}
