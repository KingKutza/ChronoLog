// INTIMATE IS A SMOOTH CANVAS, AND ITS DAYS ARE THE DAYS ASKED FOR (ISSUES 9.2, Don).
//
// Two reports on one surface, and a ruling that reverses a 9.1 position.
//
// "On Intimate, days ahead/behind seems to cap out for some reason." The cap is
// measured in PIXELS, not days: `_plan` takes the smaller of the span asked for
// and what `intimate.minColumnPixels` says fits -- "WHAT FITS, NEVER FEWER THAN
// ONE" -- so a tile about 1,400 px wide shows seven columns however high the
// control counts, and nothing marks it or says why. The one wrong answer to
// "show me thirty days" is to silently show seven.
//
// "Intimate does not allow small drags, I feel like it should just be a smooth
// canvas, who cares if a day is cut in half on the edge, and then forward/back
// day/week buttons to realign." `panLanding` TRUNCATES a sideways shift to whole
// columns -- the 9.1 position that "across this surface a column is the step",
// "the WINDOW can only move in whole columns". Don has now ruled that the
// half-day at the edge is not a lie: it is the canvas. The honesty argument that
// produced whole-column stepping no longer applies.
//
// The rules:
//
//   A day column is exactly (area / span) wide. No pixel floor drops a day; if a
//   law ever forbids the span, the surface SAYS SO in prose.
//   A sideways pan of ANY distance moves the window by exactly the days those
//   pixels span, with no truncation and no rounding anywhere in the commit.
//   The first and last columns may be partial, and a partial day still paints.
//   Nothing snaps on its own. Realignment is an explicit step, in the law's own
//   units -- its day, one turn of its weekday cycle -- never a hardcoded seven.
//   Every continuous surface in the catalog reads a pan this one way.
//
// The span is ONE number said once (ISSUES 9.2 (b)): the view key `span`, whose
// shipped default is the setting `intimate.span`. `intimate.bleed*` is what is
// painted PAST the window and is under test elsewhere; nothing here touches it.

import 'dart:math';

import 'package:chronolog/app.dart';
import 'package:chronolog/chrome/controls.dart';
import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/projection.dart';
import 'package:chronolog/edit/editor.dart';
import 'package:chronolog/lens/lens_painter.dart';
import 'package:chronolog/lens/painters/intimate.dart';
import 'package:chronolog/lens/theme.dart';
import 'package:chronolog/lens/view_tile.dart';
import 'package:chronolog/session/lens_catalog.dart';
import 'package:chronolog/session/view_state.dart';
import 'package:chronolog/stage/tile.dart';
import 'package:chronolog/store/document_store.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/corpus.dart';
import '../helpers/projection_scene.dart';
import '../store/harness.dart';
import 'painters/grid_scene.dart';

const String frameId = 'calendar:a';
const String tileId = 'view:1';
const String wallTime = 'frame:wall-time';
const Size tileSize = Size(1100, 640);

/// A scene asking for [span] days, at [size], optionally with one setting read
/// differently -- the way a person authors a setting, not a literal in a lens.
LensScene spanScene(
  Scene world,
  int span, {
  Size size = const Size(960, 720),
  Map<String, Rational> settings = const {},
}) {
  final engine = ProjectionEngine(world.document);
  return LensScene(
    engine: engine,
    projection: Projection.of(const [frameId]),
    law: engine.lawOf(frameId),
    focusDays: civilDays(2026, 8, 18),
    view: {'span': '$span'},
    theme: shipped['paper']!,
    nowDays: civilDays(2026, 8, 18),
    size: size,
    tunable: (key) => settings[key] ?? allTunables(key),
  );
}

/// How wide one day is on this painter, measured the way the eye measures it:
/// the distance between where two consecutive midnights project.
double dayWidth(IntimatePainter painter) {
  final day = painter.law.dayOf(painter.scene.focusDays);
  final start = Rational(day) * painter.law.dayDays;
  final left = painter.project(start), right = painter.project(start + painter.law.dayDays);
  expect(left, isNotNull, reason: 'the focus day is on screen by construction');
  expect(right, isNotNull);
  return right!.dx - left!.dx;
}

double areaOf(LensScene scene) => scene.size.width - scene.px('intimate.rail');

/// Widths a tile really takes -- a phone's worth to a wall's -- and spans a
/// person really asks for, seeded so a failure names its case.
List<(Size, int)> cases(Random random, int count) => [
  for (var index = 0; index < count; index += 1)
    (Size(320 + random.nextDouble() * 2600, 400 + random.nextDouble() * 800), 1 + random.nextInt(60)),
];

void main() {
  group('the span is the span', () {
    test('a day column is the area over the span, at any window width and any span', () {
      final random = Random(specSeed);
      for (final (size, span) in cases(random, 40)) {
        final world = Scene()..calendar(frameId);
        final painter = IntimatePainter(spanScene(world, span, size: size));
        render(painter, size);
        expect(
          dayWidth(painter),
          closeTo(areaOf(painter.scene) / span, 1e-6),
          reason:
              'ISSUES 9.2: asked for $span days in ${size.width.toStringAsFixed(0)} px and the '
              'surface ruled its columns at another width -- `intimate.minColumnPixels` floors '
              'the count at what fits. The floor coarsens the surface; it never drops a day.',
        );
      }
    });

    test('raising the pixel floor coarsens nothing about the count: the width is unchanged', () {
      // A person authors `intimate.minColumnPixels` as wide as the whole tile.
      // The setting still exists -- it is the width at which the rule ladder
      // steps a rung -- but the number of days is not its business.
      final random = Random(specSeed + 1);
      for (final (size, span) in cases(random, 20)) {
        final world = Scene()..calendar(frameId);
        final shipped = IntimatePainter(spanScene(world, span, size: size));
        final floored = IntimatePainter(
          spanScene(
            world,
            span,
            size: size,
            settings: {'intimate.minColumnPixels': Rational.fromInt(size.width.ceil() * 2)},
          ),
        );
        render(shipped, size);
        render(floored, size);
        expect(
          dayWidth(floored),
          closeTo(dayWidth(shipped), 1e-6),
          reason:
              'ISSUES 9.2: `intimate.minColumnPixels` governs how many days are shown. It may '
              'govern only how coarsely a narrow column is ruled.',
        );
      }
    });

    test('a surface that cannot honour the span says so in prose -- it never just shows fewer', () {
      final random = Random(specSeed + 2);
      for (final (size, span) in cases(random, 40)) {
        final world = Scene()..calendar(frameId);
        final painter = IntimatePainter(spanScene(world, span, size: size));
        render(painter, size);
        final honoured = (dayWidth(painter) - areaOf(painter.scene) / span).abs() < 1e-6;
        if (honoured) continue;
        expect(
          painter.refusals.map((refusal) => refusal.message.toLowerCase()),
          anyElement(contains('day')),
          reason:
              'ISSUES 9.2: $span days were asked for in ${size.width.toStringAsFixed(0)} px, '
              'fewer were drawn, and no refusal named it. "Nothing clamps the number, nothing '
              'marks it, nothing says why the picture stopped changing."',
        );
      }
    });
  });

  group('a pan is the canvas sliding', () {
    test('a sideways pan of any distance moves the window by exactly the days it spans', () {
      final random = Random(specSeed + 3);
      final world = Scene()..calendar(frameId);
      const size = Size(1400, 720);
      final painter = IntimatePainter(spanScene(world, 7, size: size));
      render(painter, size);
      final column = dayWidth(painter);
      final dayDays = painter.law.dayDays;
      for (var iteration = 0; iteration < 60; iteration += 1) {
        // Pixel halves, so the arithmetic below has an exact answer to meet --
        // and most of them well under one column, which is where the hand feels
        // the ratchet.
        final dx = (random.nextInt(4 * column.round()) - 2 * column.round()) / 2;
        if (dx == 0) continue;
        final shift = Offset(dx, 0);
        final landing = painter.panLanding(shift);
        expect(
          landing.taken,
          equals(shift),
          reason:
              'ISSUES 9.2: a pan of $dx px (column ${column.toStringAsFixed(1)} px) was not taken '
              'whole -- `panLanding` truncates to whole columns. "It should just be a smooth canvas."',
        );
        expect(
          (landing.days / dayDays).toDouble() * column,
          closeTo(-dx, 1e-6),
          reason: 'ISSUES 9.2: $dx px sideways is exactly ${-dx / column} days of this law, no more, no less',
        );
      }
    });

    test('no truncation and no rounding: a chain of pans and its reverse return exactly home', () {
      final random = Random(specSeed + 4);
      final world = Scene()..calendar(frameId);
      const size = Size(1400, 720);
      final painter = IntimatePainter(spanScene(world, 5, size: size));
      render(painter, size);
      for (var iteration = 0; iteration < 30; iteration += 1) {
        // Each step under a column, the chain often over one: exactly where a
        // per-step truncate and a truncate of the sum part ways.
        final reach = (dayWidth(painter) * 0.9).floor();
        final steps = [
          for (var index = 0; index < 2 + random.nextInt(6); index += 1)
            Offset((random.nextInt(8 * reach) - 4 * reach) / 4, (random.nextInt(600) - 300) / 4),
        ];
        var travelled = Rational.zero;
        var total = Offset.zero;
        for (final step in steps) {
          travelled += painter.panLanding(step).days;
          total += step;
        }
        final back = painter.panLanding(-total).days;
        expect(
          travelled + back,
          equals(Rational.zero),
          reason:
              'ISSUES 9.2: panning by $steps and then by ${-total} did not return to the exact '
              'starting coordinate (off by ${travelled + back} days). A truncate hides here.',
        );
      }
    });

    test('every continuous surface in the catalog takes a pan whole -- not an Intimate special case', () {
      registerShippedLenses();
      final random = Random(specSeed + 5);
      final world = Scene()..calendar(frameId);
      const size = Size(1200, 800);
      var surfaces = 0;
      for (final spec in lensCatalog.values) {
        if (!spec.isTimeSurface) continue;
        final build = lensPainters[spec.id];
        if (build == null) continue;
        surfaces += 1;
        final painter = build(sceneOf(world.document, const [frameId], size: size));
        render(painter, size);
        for (var iteration = 0; iteration < 12; iteration += 1) {
          final shift = Offset((random.nextInt(400) - 200) / 4, (random.nextInt(400) - 200) / 4);
          final landing = painter.panLanding(shift);
          if (landing.taken == Offset.zero && landing.days == Rational.zero) {
            // A surface with no time under any probe has nothing to take; that
            // is a different property (the ring's hole) and not this one.
            continue;
          }
          expect(
            landing.taken,
            equals(shift),
            reason:
                'ISSUES 9.2: ${spec.id} took ${landing.taken} of a $shift pan. Don\'s word is '
                '"canvas": a continuous surface commits the whole gesture, once, the same way.',
          );
        }
      }
      expect(surfaces, greaterThan(0), reason: 'the catalog registers its painters');
    });
  });

  group('the canvas, at the surface', () {
    testWidgets('a committed sub-column drag leaves every instant exactly where the hand left it', (
      tester,
    ) async {
      final bed = await _layOut(tester);
      final before = _livePainter(tester);
      final focus = bed.views.focusOf(tileId);
      final at = before.project(focus);
      expect(at, isNotNull, reason: 'the focus is on screen by construction');
      // Well under one column: exactly the drag that commits nothing today.
      final dx = -dayWidth(before) * 0.4;
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ViewTile)),
        buttons: kMiddleMouseButton,
      );
      await gesture.moveBy(Offset(dx, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      final after = _livePainter(tester).project(focus);
      expect(after, isNotNull);
      expect(
        (after! - at!).dx,
        closeTo(dx, 0.5),
        reason:
            'ISSUES 9.2: a drag of ${dx.toStringAsFixed(1)} px moved the committed window by '
            '${(after - at).dx.toStringAsFixed(1)} px. "Intimate does not allow small drags."',
      );
      expect((after - at).dy, closeTo(0, 0.5), reason: 'a sideways pan moves nothing down the rail');
    });

    testWidgets('a day cut by the edge still paints its mark: partial is not skipped', (tester) async {
      final bed = await _layOut(tester);
      final focus = bed.views.focusOf(tileId);
      final law = _livePainter(tester).law;
      // An event inside the focus day, at an hour the window shows, then a drag
      // that leaves that day half off the left edge.
      final day = law.dayOf(focus);
      final start = Rational(day) * law.dayDays + (focus - Rational(day) * law.dayDays);
      final id = bed.editor.createAt(wallTime, start, start + law.daysOfMinute(Rational.fromInt(30)));
      await tester.pumpAndSettle();
      final before = _livePainter(tester);
      expect(before.hits.map((hit) => hit.fact.event.id), contains(id), reason: 'it is drawn at rest');
      final column = dayWidth(before);
      final x = before.project(start)!.dx;
      // Slide the day so that its column straddles the rail's edge by half.
      final dx = -(x - before.scene.px('intimate.rail')) - column / 2;
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ViewTile)),
        buttons: kMiddleMouseButton,
      );
      await gesture.moveBy(Offset(dx, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      final after = _livePainter(tester);
      final moved = after.project(start)!.dx;
      expect(
        moved,
        closeTo(x + dx, 0.5),
        reason: 'ISSUES 9.2: the committed window is not where the drag left it',
      );
      expect(
        dayWidth(after),
        closeTo(column, 0.5),
        reason:
            'ISSUES 9.2: a day cut by the edge keeps its full width -- it is not drawn as a whole '
            'day squeezed to fit',
      );
      expect(
        after.hits.map((hit) => hit.fact.event.id),
        contains(id),
        reason:
            'ISSUES 9.2: "who cares if a day is cut in half on the edge" -- the half that is '
            'showing still carries its marks. A partial day is a day, not a skipped one.',
      );
    });

    testWidgets('realignment is an explicit step in the law\'s own units, and nothing snaps alone', (
      tester,
    ) async {
      final spec = lensCatalog['intimate']!;
      final actions = {
        for (final control in spec.controls)
          if (control.kind == 'action') control.key,
      };
      for (final step in const ['dayBack', 'dayForward', 'weekBack', 'weekForward']) {
        expect(
          actions,
          contains(step),
          reason:
              'ISSUES 9.2: "forward/back day/week buttons to realign" -- Intimate declares no '
              '`$step` action. Realignment is authored, so it is a control, not a side effect.',
        );
      }
      final bed = await _layOut(tester);
      final controller = viewTileControllers[tileId]!;
      final before = _livePainter(tester);
      final rail = before.scene.px('intimate.rail');
      final column = dayWidth(before);
      // A sub-column pan first, so there is a phase to realign.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ViewTile)),
        buttons: kMiddleMouseButton,
      );
      await gesture.moveBy(Offset(-column * 0.37, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      final panned = _livePainter(tester);
      expect(
        _phase(panned, rail, column),
        isNot(closeTo(0, 1e-3)),
        reason: 'ISSUES 9.2: a pan never rounds itself to a column after the fact',
      );
      final focusBefore = bed.views.focusOf(tileId);
      controller.runAction('dayForward');
      await tester.pumpAndSettle();
      final law = panned.law;
      final stepped = bed.views.focusOf(tileId) - focusBefore;
      expect(stepped > Rational.zero, isTrue, reason: 'a day forward moves forward');
      expect(stepped <= law.dayDays, isTrue, reason: 'by at most one day of THIS law');
      expect(
        _phase(_livePainter(tester), rail, column),
        closeTo(0, 1e-3),
        reason: 'ISSUES 9.2: after a day step a midnight sits exactly on the rail\'s edge',
      );
      // The week is the law's own cycle, however long it declares it.
      final week = panned.scene.law.weekdayNames()?.length;
      expect(week, isNotNull, reason: 'wall time declares a weekday cycle');
      final weekBefore = bed.views.focusOf(tileId);
      controller.runAction('weekForward');
      await tester.pumpAndSettle();
      final weekStep = bed.views.focusOf(tileId) - weekBefore;
      expect(weekStep > Rational.zero, isTrue);
      expect(
        weekStep <= law.dayDays * Rational.fromInt(week!),
        isTrue,
        reason: 'a week step is one turn of the declared cycle, never a hardcoded seven',
      );
      final days = weekStep / law.dayDays;
      expect(Rational(days.floor()), equals(days), reason: 'and lands on a day boundary');
    });
  });
}

/// Where the nearest midnight sits relative to the rail's edge, as a fraction of
/// a column: zero when a day boundary is exactly on the edge.
double _phase(IntimatePainter painter, double rail, double column) {
  final law = painter.law;
  final day = law.dayOf(painter.scene.focusDays);
  final x = painter.project(Rational(day) * law.dayDays)!.dx - rail;
  final fraction = (x / column) - (x / column).floorToDouble();
  return min(fraction, 1 - fraction);
}

IntimatePainter _livePainter(WidgetTester tester) {
  final paints = tester.widgetList<CustomPaint>(
    find.byWidgetPredicate((widget) => widget is CustomPaint && widget.painter is BledPainter),
  );
  expect(paints, isNotEmpty, reason: 'the view tile hosts its lens through one bled painter');
  return (paints.first.painter! as BledPainter).lens as IntimatePainter;
}

typedef _Bed = ({Editor editor, ViewBook views, Stage stage});

/// A real Intimate view tile over an in-memory store, no disk and no clock.
Future<_Bed> _layOut(WidgetTester tester) async {
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
  views.of(tileId).lensId = 'intimate';
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
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: themeDataFor(shipped['paper']!),
      home: Scaffold(
        body: ChromeScope(
          chrome: Chrome(settings: settings, stage: stage, views: views, editor: editor),
          child: Center(
            child: SizedBox(width: tileSize.width, height: tileSize.height, child: tile),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (editor: editor, views: views, stage: stage);
}
