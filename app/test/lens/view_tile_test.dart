// The pointer vocabulary, proven at the surface.
//
// Three field reports (ISSUES 8.26) are one defect -- the buttons were unowned
// -- so the cases here are those three stated as properties: middle-drag pans
// and mints nothing, the secondary button is always the app's own menu (marks
// included), and a drop lands EXACTLY where `unproject` puts the pointer while
// the ghost names that same coordinate during the drag.
//
// The lens under test is a fake painter of this spec's own -- a plain rail, one
// day every [dayPixels] -- so every case tests the pointer table and never a
// painter's geometry.

import 'dart:io';
import 'dart:math';

import 'package:chronolog/chrome/controls.dart';
import 'package:chronolog/core/coordinate_entry.dart';
import 'package:chronolog/core/coordinate_law.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/staples.dart';
import 'package:chronolog/edit/editor.dart';
import 'package:chronolog/lens/drag_ghost.dart';
import 'package:chronolog/lens/gestures.dart';
import 'package:chronolog/lens/lens_painter.dart';
import 'package:chronolog/lens/theme.dart';
import 'package:chronolog/lens/tunables.dart';
import 'package:chronolog/lens/view_tile.dart';
import 'package:chronolog/session/lens_catalog.dart';
import 'package:chronolog/session/settings.dart';
import 'package:chronolog/session/view_state.dart';
import 'package:chronolog/stage/tile.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/corpus.dart';
import '../edit/harness.dart';

const double dayPixels = 60;
const Size surface = Size(600, 400);
const String tileId = 'view:1';
const String wallTime = 'frame:wall-time';

/// A rail: x is days from the focus at the centre, y carries nothing. Every fact
/// in the visible window becomes a hit DURING paint, which is the contract every
/// real painter keeps.
///
/// It keeps the other two contracts as well, because the specs below are about
/// them: a mark records its BODY as the shape a click means AND as the region a
/// drag grabs -- one region, every verb (ISSUES 9.1) -- and the surface bleeds
/// one day past its own edge so a pan of less than that is previewed by the
/// transform instead of committed.
class RailPainter extends LensPainter {
  RailPainter(super.scene);

  @override
  Offset get bleed => const Offset(dayPixels, 0);

  @override
  PanLanding panLanding(Offset shift) => (
    days: days(surface.width / 2 - shift.dx) - days(surface.width / 2),
    shown: Offset(shift.dx, 0),
    taken: shift,
  );

  Rational days(double dx) =>
      scene.focusDays + Rational.parse(((dx - surface.width / 2) / dayPixels).toStringAsFixed(9));

  @override
  Rational? unproject(Offset at) => days(at.dx);

  @override
  Offset? project(Rational value) => Offset(
    surface.width / 2 + ((value - scene.focusDays) * Rational.fromInt(60)).toDouble(),
    surface.height / 2,
  );

  @override
  void paint(Canvas canvas, Size size) {
    hits.clear();
    final found = scene.engine.queryFacts(
      scene.projection,
      start: days(0),
      end: days(surface.width),
    );
    for (final fact in found.facts) {
      final at = project(fact.day);
      if (at == null) continue;
      final bounds = Rect.fromCenter(center: at, width: dayPixels / 2, height: dayPixels / 2);
      hits.add((
        bounds: bounds,
        shape: Path()..addRect(bounds),
        grab: null,
        fact: fact,
        identity: fact.identity,
      ));
      canvas.drawRect(bounds, Paint()..color = scene.theme.ink);
    }
  }
}

typedef Bed = ({Editor editor, Settings settings, ViewBook views, Stage stage, Directory root});

final List<Directory> roots = [];

/// The store's load is real file I/O, and a `testWidgets` body runs in a fake
/// async zone where a real future never completes -- so every widget case takes
/// its bed through [WidgetTester.runAsync].
Future<Bed> layOut(WidgetTester tester, String lens) =>
    tester.runAsync(() => _layOut(lens)).then((bed) => bed!);

Future<Bed> _layOut(String lens) async {
  final bench = await openEditor(createEmptyWorkspaceDocument());
  roots.add(bench.root);
  final settings = Settings(
    defaults: const [
      lensTunableDefaults,
      sessionTunableDefaults,
      pointerTunableDefaults,
      chromeTunableDefaults,
      editTunableDefaults,
    ],
  );
  // The wall-time frame the empty document ships with: a law that maps to a
  // clock, which is what a time surface needs to have a now at all.
  final views = ViewBook()..defaultFrames = [wallTime];
  views.of(tileId).lensId = lens;
  return (editor: bench.editor, settings: settings, views: views, stage: Stage(), root: bench.root);
}

/// Every card this surface was asked to open, in order. A card opener is all
/// the lens layer knows about cards, so recording the calls proves the PATH
/// without dragging the card layer into a pointer spec.
final List<String> opened = [];

/// Every settings area this surface was asked to open. The settings family is
/// reached through one opener, so recording it proves the door without dragging
/// the card layer in.
final List<String?> settingsOpened = [];

TileSpec _recordingSettings({String? area}) {
  settingsOpened.add(area);
  return TileSpec(
    id: 'card:settings:${area ?? 'one'}',
    type: 'card',
    klass: 'settings',
    title: 'Settings',
    build: (_) => const SizedBox.shrink(),
  );
}

TileSpec _recordingCard(String id) {
  opened.add(id);
  return TileSpec(
    id: 'card:$id',
    type: 'card',
    klass: 'card',
    title: 'Card',
    build: (_) => const SizedBox.shrink(),
  );
}

Future<void> pump(WidgetTester tester, Bed bed, {bool cards = false}) async {
  final tile = ViewTile(
    tileId: tileId,
    surface: (
      editor: bed.editor,
      settings: bed.settings,
      views: bed.views,
      stage: bed.stage,
      objectCard: cards ? _recordingCard : null,
      frameCard: null,
      settingsCard: cards ? _recordingSettings : null,
    ),
  );
  bed.stage.open(
    TileSpec(id: tileId, type: 'view', klass: 'lens', title: 'View', build: (_) => tile),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: [shipped['paper']!]),
      home: Scaffold(
        body: ChromeScope(
          chrome: Chrome(
            settings: bed.settings,
            stage: bed.stage,
            views: bed.views,
            editor: bed.editor,
          ),
          child: Center(
            child: SizedBox(width: surface.width, height: surface.height, child: tile),
          ),
        ),
      ),
    ),
  );
}

/// The lens under the tile, through whatever the bleed wrapped it in: a surface
/// that draws past its own edge is handed to the render box inside a [BledPainter],
/// and the specs are about the lens either way.
RailPainter railOf(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((paint) => paint.painter)
    .map((painter) => painter is BledPainter ? painter.lens : painter)
    .whereType<RailPainter>()
    .first;

DragGhost? ghostOf(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((paint) => paint.painter)
    .whereType<GhostPainter>()
    .first
    .ghost;

Offset at(double dx) => Offset(dx, surface.height / 2);

Offset onScreen(WidgetTester tester, Offset local) =>
    tester.getTopLeft(find.byType(ViewTile)) + local;

/// The placement the drag just wrote, told apart from whatever the document
/// already held.
Rational placedDays(Editor editor, Set<String> before) {
  final relation = editor.document.relations.values.firstWhere(
    // RULED 2026-09-01: a placement is a staple, told by the sentence it says.
    (candidate) => isPlacement(candidate) && !before.contains(candidate.id),
  );
  return editor.engine.coordinateDays(wallTime, relation.coordinate);
}

/// One click at a stated instant. The framework stamps a synthesized tap at
/// zero, and the double-click window is measured on the pointer's own clock, so
/// a spec that wants two separate clicks has to say when each one happened.
Future<void> clickAt(WidgetTester tester, Offset local, Duration when) async {
  final gesture = await tester.createGesture();
  await gesture.down(onScreen(tester, local), timeStamp: when);
  await gesture.up(timeStamp: when);
  await tester.pump();
}

double notchOf(Bed bed) => bed.settings.value('pointer.wheelNotch').toDouble();

/// One wheel gesture at a point, with a modifier where the verb wants one. The
/// wheel is a pointer SIGNAL, not a drag, so it goes to the binding directly.
Future<void> scrollAt(
  WidgetTester tester,
  Offset local,
  double dy, {
  bool control = false,
}) async {
  if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  final pointer = TestPointer(1, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(pointer.hover(onScreen(tester, local)));
  await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
  await tester.pump();
  if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
}

Future<void> markAt(Bed bed, WidgetTester tester) async {
  final where = bed.views.focusOf(tileId);
  bed.editor.createAt(wallTime, where, where + Rational.fromInt(1, 24));
  await tester.pump();
}

/// The offset the pan transform is holding right now: what the eye is being
/// shown over and above what the painter drew.
Offset panOf(WidgetTester tester) {
  final transform = tester
      .widgetList<Transform>(find.descendant(of: find.byType(ViewTile), matching: find.byType(Transform)))
      .first
      .transform
      .getTranslation();
  return Offset(transform.x, transform.y);
}

void main() {
  setUp(() {
    lensPainters.clear();
    lensWidgets.clear();
    opened.clear();
    registerLensPainter('intimate', RailPainter.new);
  });

  tearDownAll(() async {
    for (final root in roots) {
      if (root.existsSync()) await root.delete(recursive: true);
    }
  });

  test('the one pointer table: buttons and modifiers, never a lens accident', () {
    String verb(int buttons, {bool shift = false, bool alt = false, bool onMark = false}) =>
        pointerVerb(buttons: buttons, shift: shift, alt: alt, onMark: onMark, timeSurface: true);
    expect(verb(kMiddleMouseButton), 'pan');
    expect(verb(kMiddleMouseButton, onMark: true), 'pan');
    expect(verb(kSecondaryMouseButton), 'menu');
    expect(verb(kSecondaryMouseButton, onMark: true), 'menu');
    expect(verb(kPrimaryMouseButton, shift: true), 'pan');
    expect(verb(kPrimaryMouseButton), 'create');
    expect(verb(kPrimaryMouseButton, onMark: true), 'move');
    // ROADMAP #7: creation works THROUGH an occupied span.
    expect(verb(kPrimaryMouseButton, onMark: true, alt: true), 'create');
    // A roster lens only ever selects: a drag there mints nothing, ever.
    expect(
      pointerVerb(
        buttons: kPrimaryMouseButton,
        shift: false,
        alt: false,
        onMark: false,
        timeSurface: false,
      ),
      'select',
    );
  });

  test('a notch accumulator carries its remainder', () {
    final notches = Notches();
    var carried = 0;
    for (var index = 0; index < 90; index += 1) {
      carried += notches.take(10, 90);
    }
    // Ninety tenth-notches are exactly ten notches: nothing is discarded.
    expect(carried, 10);
    expect(notches.take(Random(specSeed).nextDouble(), 0), 0);
  });

  test('a grain of zero snaps to nothing; any other grain snaps within a half', () {
    final random = Random(specSeed);
    final grain = Rational.fromInt(1, 96);
    for (var index = 0; index < 64; index += 1) {
      final days = Rational.parse((random.nextDouble() * 1000).toStringAsFixed(9));
      expect(snapDays(days, Rational.zero), days);
      final snapped = snapDays(days, grain);
      expect((snapped - days).abs() <= grain / Rational.fromInt(2), isTrue);
      expect(snapped % grain, Rational.zero);
    }
  });

  testWidgets('middle-drag pans the focus and mints nothing', (tester) async {
    final bed = await layOut(tester, 'intimate');
    await pump(tester, bed);
    final before = bed.views.focusOf(tileId);
    final gesture = await tester.startGesture(
      onScreen(tester, at(100)),
      buttons: kMiddleMouseButton,
    );
    await gesture.moveBy(const Offset(-dayPixels * 3, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(bed.views.focusOf(tileId) - before, Rational.fromInt(3));
    expect(bed.editor.document.events, isEmpty);
  });

  testWidgets('the secondary button raises the app menu on empty surface', (tester) async {
    final bed = await layOut(tester, 'intimate');
    await pump(tester, bed);
    final gesture = await tester.startGesture(
      onScreen(tester, at(120)),
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('New event here'), findsOneWidget);
    expect(find.text('Close tile'), findsOneWidget);
    // Open belongs to a mark, and there is none under this point.
    expect(find.text('Open'), findsNothing);
    expect(bed.editor.document.events, isEmpty);
  });

  testWidgets('the secondary button raises it on a mark too, with the mark rows', (tester) async {
    final bed = await layOut(tester, 'intimate');
    await pump(tester, bed);
    await markAt(bed, tester);
    final gesture = await tester.startGesture(
      onScreen(tester, railOf(tester).hits.single.bounds.center),
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('the ghost names the coordinate the drop will commit', (tester) async {
    final bed = await layOut(tester, 'intimate');
    bed.views.of(tileId).write('grain', Rational.zero);
    await pump(tester, bed);
    final rail = railOf(tester);
    final gesture = await tester.startGesture(onScreen(tester, at(150)));
    await gesture.moveTo(onScreen(tester, at(260)));
    await tester.pump();
    final ghost = ghostOf(tester);
    expect(ghost, isNotNull);
    expect(ghost!.creating, isTrue);
    expect(
      ghost.label,
      formatCoordinateEntry(
        Coordinate.fromJson(bed.editor.engine.daysCoordinate(wallTime, rail.unproject(at(260))!)),
        bed.editor.engine.lawOf(wallTime),
      ),
    );
    await gesture.up();
    await tester.pump();
  });

  testWidgets('a drag-create lands exactly where unproject puts the pointer', (tester) async {
    final random = Random(specSeed);
    for (var index = 0; index < 6; index += 1) {
      final bed = await layOut(tester, 'intimate');
      bed.views.of(tileId).write('grain', Rational.zero);
      await pump(tester, bed);
      final rail = railOf(tester);
      final placements = bed.editor.document.relations.keys.toSet();
      final from = 40 + random.nextDouble() * 200, to = from + 40 + random.nextDouble() * 200;
      final gesture = await tester.startGesture(onScreen(tester, at(from)));
      await gesture.moveTo(onScreen(tester, at(to)));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(placedDays(bed.editor, placements), rail.unproject(at(from)));
    }
  });

  testWidgets('a drag on a roster lens mints nothing', (tester) async {
    registerLensWidget('list', (context, tile) => const SizedBox.expand());
    final bed = await layOut(tester, 'list');
    await pump(tester, bed);
    final gesture = await tester.startGesture(onScreen(tester, at(100)));
    await gesture.moveTo(onScreen(tester, at(300)));
    await gesture.up();
    await tester.pump();
    expect(bed.editor.document.events, isEmpty);
  });

  testWidgets('re-clicking the selected clears it: a click is its own undo', (tester) async {
    final bed = await layOut(tester, 'intimate');
    await pump(tester, bed);
    await markAt(bed, tester);
    final mark = railOf(tester).hits.single.bounds.center;
    final identity = railOf(tester).hits.single.identity;
    await clickAt(tester, mark, Duration.zero);
    expect(railOf(tester).scene.selection, {identity});
    // Well outside the double-click window: this is a second click, not a
    // second half of one.
    await clickAt(tester, mark, const Duration(seconds: 1));
    expect(railOf(tester).scene.selection, isEmpty);
  });

  testWidgets('two clicks inside the window are one double-click, not a clear', (tester) async {
    final bed = await layOut(tester, 'intimate');
    await pump(tester, bed, cards: true);
    await markAt(bed, tester);
    final mark = railOf(tester).hits.single.bounds.center;
    final hit = railOf(tester).hits.single;
    await clickAt(tester, mark, Duration.zero);
    await clickAt(tester, mark, const Duration(milliseconds: 40));
    // The second click OPENED THE OBJECT'S CARD rather than clearing it (ISSUES
    // 8.31: "I see no clear way to open an events card back up").
    expect(railOf(tester).scene.selection, {hit.identity});
    expect(opened, [hit.fact.event.id]);
  });

  testWidgets('a click anywhere in a mark selects it, not only where a drag grabs it', (
    tester,
  ) async {
    // ISSUES 8.31. One shape was answering two questions: the narrow strip a
    // drag takes hold of was also gating selection, so a click in the body of an
    // event found no mark at all -- no ring, no card, no Open row.
    final bed = await layOut(tester, 'intimate');
    await pump(tester, bed, cards: true);
    await markAt(bed, tester);
    final hit = railOf(tester).hits.single;
    final random = Random(specSeed);
    for (var index = 0; index < 8; index += 1) {
      final inside = Offset(
        hit.bounds.left + random.nextDouble() * hit.bounds.width,
        hit.bounds.top + random.nextDouble() * hit.bounds.height,
      );
      await clickAt(tester, inside, Duration(seconds: index * 2));
      expect(
        railOf(tester).scene.selection,
        {hit.identity},
        reason: 'a click at $inside found no mark',
      );
      // A click is its own undo, so clear it before the next one.
      await clickAt(tester, inside, Duration(seconds: index * 2 + 1));
    }
  });

  testWidgets('the menu on a mark opens that object, wherever on the mark it was raised', (
    tester,
  ) async {
    final bed = await layOut(tester, 'intimate');
    await pump(tester, bed, cards: true);
    await markAt(bed, tester);
    final hit = railOf(tester).hits.single;
    final gesture = await tester.startGesture(
      onScreen(tester, hit.bounds.center),
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(opened, [hit.fact.event.id]);
  });

  testWidgets('a drag from the body of a mark MOVES it, and alt creates through it', (
    tester,
  ) async {
    // ISSUES 9.1, Don: "click on an event or todo and drag it, the event does
    // not move -- it drags to create a new event." The common gesture gets the
    // common verb; the rare one -- minting through an occupied span -- wears the
    // modifier the one pointer table already carries.
    final bed = await layOut(tester, 'intimate');
    bed.views.of(tileId).write('grain', Rational.zero);
    await pump(tester, bed);
    await markAt(bed, tester);
    final hit = railOf(tester).hits.single;
    final was = bed.editor.document.relations.keys.toSet();
    final from = hit.bounds.center;
    final to = from + const Offset(dayPixels * 2, 0);
    final drag = await tester.startGesture(onScreen(tester, from));
    await drag.moveTo(onScreen(tester, to));
    await tester.pump();
    await drag.up();
    await tester.pump();
    // Nothing was minted, and the mark itself is where the drag left it.
    expect(bed.editor.document.relations.keys.toSet(), was, reason: 'a body drag mints nothing');
    expect(railOf(tester).hits.single.fact.day, railOf(tester).unproject(to));

    // Alt, over the very same body, is what still creates through it.
    final moved = railOf(tester).hits.single.bounds.center;
    final placements = bed.editor.document.relations.keys.toSet();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    final mint = await tester.startGesture(onScreen(tester, moved));
    await mint.moveTo(onScreen(tester, moved + const Offset(dayPixels * 2, 0)));
    await tester.pump();
    await mint.up();
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    expect(placedDays(bed.editor, placements), railOf(tester).unproject(moved));
  });

  testWidgets('release commits exactly where the drag left it: nothing snaps back', (tester) async {
    // Don, 2026-08-31: "I drag up and right, and then it snaps back to basically
    // the same position when I release." The property, on any lens: the place a
    // time sits at the last moment of the drag -- what the painter drew plus
    // what the transform is holding -- is where it sits after the release. The
    // settle repaint may change fidelity; it may never change position.
    final random = Random(specSeed);
    final bed = await layOut(tester, 'intimate');
    await pump(tester, bed);
    for (var index = 0; index < 8; index += 1) {
      final watched = bed.views.focusOf(tileId);
      final travel = Offset(random.nextDouble() * 300 - 150, random.nextDouble() * 200 - 100);
      final gesture = await tester.startGesture(
        onScreen(tester, at(surface.width / 2)),
        buttons: kMiddleMouseButton,
      );
      await gesture.moveBy(travel);
      await tester.pump();
      final live = railOf(tester).project(watched)! + panOf(tester);
      await gesture.up();
      await tester.pump();
      final settled = railOf(tester).project(watched)! + panOf(tester);
      expect(
        (settled - live).distance < 1,
        isTrue,
        reason: 'a drag of $travel showed $live and settled at $settled',
      );
      // And it moved AT ALL: a pan that commits nothing tells no lie and does
      // no work either.
      expect((live - Offset(surface.width / 2, surface.height / 2)).dx, isNot(0));
    }
  });

  testWidgets('a lens with no painter refuses in words rather than drawing nothing', (
    tester,
  ) async {
    lensPainters.clear();
    final bed = await layOut(tester, 'intimate');
    await pump(tester, bed);
    expect(find.textContaining('No painter is registered'), findsOneWidget);
  });

  testWidgets('ctrl+wheel UP zooms in, and the direction is a setting', (tester) async {
    // ISSUES 9.1: "scroll-wheel zoom is reversed: wheel up zooms out", against
    // every map and browser the hand has learned (butter). The property is
    // stated in the surface's own terms -- Intimate scales its hour rail, and
    // zooming IN is a TALLER hour, which is less time on screen -- and the
    // direction is `pointer.zoomDirection`, so authoring it negative gives the
    // old way back rather than needing a different build.
    for (final direction in [1, -1]) {
      final bed = await layOut(tester, 'intimate');
      bed.settings.set('pointer.zoomDirection', '$direction');
      await pump(tester, bed);
      final was = bed.views.of(tileId).number('hourPixels', bed.settings);
      await scrollAt(tester, at(surface.width / 2), -notchOf(bed) * 3, control: true);
      final now = bed.views.of(tileId).number('hourPixels', bed.settings);
      expect(
        direction > 0 ? now > was : now < was,
        isTrue,
        reason: 'at zoomDirection $direction a wheel-up notch took the hour rail '
            'from $was to $now',
      );
    }
  });

  testWidgets('the lens menu opens this lens own settings card, and the main one', (
    tester,
  ) async {
    // ISSUES 9.1, Don's settings ruling: "sub-cards are also launched from
    // right-click context menus at the relevant parts of the app -- the lens's
    // own menu opens that lens's settings card".
    final bed = await layOut(tester, 'intimate');
    await pump(tester, bed, cards: true);
    settingsOpened.clear();
    final gesture = await tester.startGesture(
      onScreen(tester, at(120)),
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings for this lens\u2026'));
    await tester.pumpAndSettle();
    expect(settingsOpened, [bed.views.of(tileId).lensId]);
  });

  testWidgets('"New todo on this" staples the todo to the object under the pointer', (
    tester,
  ) async {
    // ISSUES 9.1: right-clicking an event and choosing "New todo here" authored
    // an anchor to Wall Time rather than to the event under the pointer. A menu
    // that knows what is under the pointer owes that knowledge to every verb it
    // offers, not just the readers.
    final bed = await layOut(tester, 'intimate');
    await pump(tester, bed, cards: true);
    await markAt(bed, tester);
    final event = railOf(tester).hits.single.fact.event.id;
    final gesture = await tester.startGesture(
      onScreen(tester, railOf(tester).hits.single.bounds.center),
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('New todo on this'));
    await tester.pumpAndSettle();
    final staples = bed.editor.document.relations.values.where((row) => row.type == 'staple');
    expect(staples, isNotEmpty, reason: 'the create said nothing about the object it was said on');
    expect(
      staples.any(
        (staple) => bed.editor.engine.indexes
            .endsOf(staple)
            .any((end) => end.id == event),
      ),
      isTrue,
      reason: 'ISSUES (9.1): "here" on an object means THE OBJECT -- the new '
          'to-do must be stapled to $event, not to the frame coordinate.',
    );
  });
}
