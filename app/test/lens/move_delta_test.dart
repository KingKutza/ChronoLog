// THE PREVIEW AND THE COMMIT ARE ONE ARITHMETIC (ISSUES 9.2, three reports).
//
// "Dragging the start of a multi-day event is inaccurate to the preview";
// "scrolling while dragging across midnight shifts the whole event"; "trying to
// drag lunch up today, the preview is not lining up with where it lands". The
// ghost is the block SHIFTED by the pointer's travel; the commit set the START
// to the pointer's absolute instant. And no lens has edge grabs: every grab is a
// whole-body move. The rules:
//
//   A move by travel T moves the start by exactly T from any grab point in any
//   segment; a scroll of S during the drag changes the result by 0. A grab band
//   at each end re-says that one point (the ghost grows, not slides).
//
// Asked of the real Intimate tile over an in-memory store, with the grain at
// zero so nothing snaps and the arithmetic has an exact answer to meet. The
// pixel travel is turned into days by the painter's OWN `unproject`, on the
// painter that is on screen at release -- the eye and the drop read one
// derivation, so the spec does too.
//
// THE ONE CONTRACT this file names (a band, not a symbol): a press within
// `intimate.grab` px of a block's END edge is an EDGE grab that re-says the end
// -- the duration, or the end staple where one exists -- and leaves the start
// where it was. A press anywhere else in the body is the whole-body move.

import 'dart:math';

import 'package:chronolog/app.dart';
import 'package:chronolog/chrome/controls.dart';
import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/edit/editor.dart';
import 'package:chronolog/lens/lens_painter.dart';
import 'package:chronolog/lens/painters/intimate.dart';
import 'package:chronolog/lens/theme.dart';
import 'package:chronolog/lens/view_tile.dart';
import 'package:chronolog/session/view_state.dart';
import 'package:chronolog/stage/tile.dart';
import 'package:chronolog/store/document_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/corpus.dart';
import '../store/harness.dart';

const String tileId = 'view:1';
const String wallTime = 'frame:wall-time';
const Size tileSize = Size(1100, 640);

typedef Bed = ({Editor editor, ViewBook views, Stage stage});

IntimatePainter livePainter(WidgetTester tester) {
  final paints = tester.widgetList<CustomPaint>(
    find.byWidgetPredicate((widget) => widget is CustomPaint && widget.painter is BledPainter),
  );
  expect(paints, isNotEmpty, reason: 'the view tile hosts its lens through one bled painter');
  return (paints.first.painter! as BledPainter).lens as IntimatePainter;
}

Offset onScreen(WidgetTester tester, Offset local) =>
    tester.getTopLeft(find.byType(ViewTile)) + local;

/// A real Intimate view tile over an in-memory store, no disk and no clock, the
/// grain at zero so a move is exact.
Future<Bed> layOut(WidgetTester tester) async {
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
  views.of(tileId).write('grain', Rational.zero);
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

/// The event's start on the wall-time axis, read from the document -- what a
/// move actually WROTE, not what any painter shows.
Rational startOf(Bed bed, String id) {
  final placement = bed.editor.document.relations.values.firstWhere(
    (relation) => relation.event == id && relation.coordinate != null,
  );
  return bed.editor.engine.coordinateDays(wallTime, placement.coordinate);
}

/// One day column's width, from the view's own count -- never from `project`,
/// which on a surface that shows an instant in several columns answers with
/// whichever it finds first.
double columnWidth(Bed bed, WidgetTester tester) {
  final state = bed.views.of(tileId);
  final settings = livePainter(tester).scene;
  final count = state.number('back', (viewTileControllers[tileId]!).settings) +
      state.number('forward', (viewTileControllers[tileId]!).settings) +
      Rational.one;
  return (tileSize.width - settings.px('intimate.rail')) / count.toDouble();
}

/// Every painted segment of one event that is ON SCREEN. Intimate paints a
/// viewport of bleed above and below the window, so the same block is drawn
/// again in the neighbouring columns where it falls outside the tile; a hand
/// cannot take hold of those, and the spec does not try.
Rect tileArea(WidgetTester tester) {
  final rail = livePainter(tester).scene.px('intimate.rail');
  return Rect.fromLTWH(rail, 0, tileSize.width - rail, tileSize.height);
}

List<MarkHit> segmentsOf(WidgetTester tester, String id) {
  final tile = tileArea(tester);
  return livePainter(tester)
      .hits
      .where((hit) => hit.fact.event.id == id)
      .where((hit) => hit.bounds.intersect(tile).height > 2 && hit.bounds.intersect(tile).width > 2)
      .toList();
}

/// The part of a segment the hand can reach.
Rect visiblePart(WidgetTester tester, Rect bounds) => bounds.intersect(tileArea(tester));

/// A point inside [bounds] that is NOT in an edge band -- a body grab.
Offset bodyPoint(Random random, Rect bounds, double band) {
  final inset = bounds.deflate(band + 1);
  final box = inset.isEmpty ? bounds : inset;
  return Offset(
    box.left + random.nextDouble() * box.width,
    box.top + random.nextDouble() * box.height,
  );
}

/// Exact to a billionth of a day: the pointer's position reaches the tile as a
/// double and comes back through `unproject` as a decimal of six places, so the
/// last bits of a mirror computed beside it may differ. The arithmetic under
/// test is in days, not in those bits.
Matcher nearDays(Rational expected) => predicate<Rational>(
  (actual) => (actual - expected).abs() < Rational(BigInt.one, BigInt.from(10).pow(9)),
  'within a billionth of a day of $expected',
);

Future<void> dragFromTo(WidgetTester tester, Offset from, Offset to, {Future<void> Function()? midway}) async {
  final gesture = await tester.startGesture(onScreen(tester, from));
  await gesture.moveTo(onScreen(tester, (from + to) / 2));
  await tester.pump();
  if (midway != null) await midway();
  await gesture.moveTo(onScreen(tester, to));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a whole-body move by travel T moves the start by exactly T, from any grab point', (
    tester,
  ) async {
    // Don: "grabbing lunch a half-hour into its body lands it a half-hour
    // earlier than the ghost showed, by exactly the grab offset"; "grab the
    // second day's segment of a multi-day event and the start jumps to the
    // pointer on day two". The property: the new start is the old start plus
    // the travel in days, wherever in whichever segment the hand took hold.
    final random = Random(specSeed);
    final bed = await layOut(tester);
    final focus = bed.views.focusOf(tileId);
    final law = livePainter(tester).law;
    final band = bed.editor.setting('intimate.grab').toDouble();
    final cases = <({String id, Rational hours})>[];
    // One-day and multi-day facts alike, starting at the focus so they are on
    // screen: lunch, and a thirty-hour conference crossing midnight.
    for (final hours in [1, 2, 30, 26]) {
      final start = focus + law.daysOfMinute(Rational.fromInt(60 * (hours % 3)));
      final id = bed.editor.createAt(
        wallTime,
        start,
        start + law.daysOfMinute(Rational.fromInt(60 * hours)),
      );
      cases.add((id: id, hours: Rational.fromInt(hours)));
    }
    await tester.pumpAndSettle();
    for (var iteration = 0; iteration < 8; iteration += 1) {
      final subject = cases[random.nextInt(cases.length)];
      final segments = segmentsOf(tester, subject.id);
      expect(segments, isNotEmpty, reason: 'the fact is drawn');
      final segment = segments[random.nextInt(segments.length)];
      final from = bodyPoint(random, visiblePart(tester, segment.bounds), band);
      // Up to two hours either way, and up to one column sideways.
      final painter = livePainter(tester);
      final to = from +
          Offset(
            (random.nextInt(3) - 1) * columnWidth(bed, tester),
            (random.nextDouble() * 4 - 2) * painter.dayPixels.toDouble() / law.hoursPerDay.toDouble(),
          );
      if (to.dy < 0 || to.dy > tileSize.height || to.dx < 0 || to.dx > tileSize.width) continue;
      final before = startOf(bed, subject.id);
      await dragFromTo(tester, from, to);
      final after = livePainter(tester);
      final travel = after.unproject(to)! - after.unproject(from)!;
      expect(
        startOf(bed, subject.id),
        nearDays(before + travel),
        reason:
            'ISSUES 9.2: grabbed ${subject.hours}h fact at $from in segment ${segments.indexOf(segment)} '
            'and travelled $travel days; the start moved by ${startOf(bed, subject.id) - before}. '
            'The commit used the pointer\'s absolute instant, adding the grab offset.',
      );
    }
  });

  testWidgets('a scroll during a drag changes the result by zero', (tester) async {
    // "The wheel is not gated during a drag and the release reads the pointer on
    // the NEW painter, so the scroll distance is added to the move." With a
    // delta commit a mid-drag scroll is HONOURED, not added: the same pixel
    // travel lands the same start whether or not the surface moved under the
    // hand halfway through.
    final random = Random(specSeed + 1);
    final bed = await layOut(tester);
    final focus = bed.views.focusOf(tileId);
    final law = livePainter(tester).law;
    final band = bed.editor.setting('intimate.grab').toDouble();
    final id = bed.editor.createAt(
      wallTime,
      focus,
      focus + law.daysOfMinute(Rational.fromInt(60 * 30)),
    );
    await tester.pumpAndSettle();
    final before = startOf(bed, id);
    final segment = segmentsOf(tester, id).first;
    final from = bodyPoint(random, visiblePart(tester, segment.bounds), band);
    final to = from + Offset(0, -livePainter(tester).dayPixels.toDouble() / law.hoursPerDay.toDouble());
    // The control run: no scroll.
    await dragFromTo(tester, from, to);
    final plain = startOf(bed, id);
    expect(plain, isNot(equals(before)), reason: 'the drag moved it at all');
    expect(bed.editor.undo(), isTrue);
    await tester.pumpAndSettle();
    expect(startOf(bed, id), equals(before), reason: 'back where it started');
    // The same gesture, with the surface scrolled two hours under the hand halfway.
    final controller = viewTileControllers[tileId]!;
    await dragFromTo(
      tester,
      from,
      to,
      midway: () async {
        controller.pan(law.daysOfMinute(Rational.fromInt(120)));
        await tester.pumpAndSettle();
      },
    );
    expect(
      startOf(bed, id),
      equals(plain),
      reason:
          'ISSUES 9.2: the same pixel travel landed ${startOf(bed, id) - plain} days away from the '
          'un-scrolled result -- the scroll distance was added to the move.',
    );
  });

  testWidgets('an edge grab re-says one point: the end across midnight changes only the end', (
    tester,
  ) async {
    // "A grab band at each end of a block (`intimate.grab` px) is an EDGE grab
    // that re-says THAT point -- the start staple's instant or the end -- with
    // the ghost showing the block growing, not sliding; across a midnight
    // boundary the end lands in the other column exactly as the pointer says."
    final bed = await layOut(tester);
    // A known hour, so the block and the next column are both on screen whatever
    // the clock says when the case runs.
    bed.views.setFocus(tileId, Rational(daysFromCivil(BigInt.from(2026), 8, 18)) + Rational.fromInt(9, 24));
    await tester.pumpAndSettle();
    final focus = bed.views.focusOf(tileId);
    final painter = livePainter(tester);
    final law = painter.law;
    final band = bed.editor.setting('intimate.grab').toDouble();
    expect(band, greaterThan(0), reason: 'the grab band is a setting with a width');
    // Six hours starting at the focus: its end sits inside the focus column,
    // and the next column is one day to the right.
    final id = bed.editor.createAt(wallTime, focus, focus + law.daysOfMinute(Rational.fromInt(360)));
    await tester.pumpAndSettle();
    final before = bed.editor.engine.staples.resolveObjectExtent(id);
    // The segment whose END edge is on screen -- the block may be drawn again
    // in a neighbouring column where its bottom runs off the tile.
    final segment = segmentsOf(tester, id).firstWhere(
      (hit) => hit.bounds.bottom <= tileSize.height && hit.bounds.bottom > band,
    );
    // Just inside the block's bottom edge: the END band.
    final from = Offset(segment.bounds.center.dx, segment.bounds.bottom - band / 2);
    // Into the NEXT column, a little down: the end crosses midnight.
    final column = columnWidth(bed, tester);
    expect(column, greaterThan(0));
    final to = from + Offset(column, painter.dayPixels.toDouble() / law.hoursPerDay.toDouble());
    await dragFromTo(tester, from, to);
    final after = livePainter(tester);
    final travel = after.unproject(to)! - after.unproject(from)!;
    final extent = bed.editor.engine.staples.resolveObjectExtent(id);
    expect(
      extent.startDays,
      equals(before.startDays),
      reason:
          'ISSUES 9.2: a grab on the end edge moved the START by ${extent.startDays! - before.startDays!} '
          'days -- every hit carries `grab: null` and no resize verb exists, so the edge is a '
          'whole-body move.',
    );
    expect(
      extent.endDays,
      nearDays(before.endDays! + travel),
      reason: 'the end lands in the other column exactly as the pointer says',
    );
  });
}
