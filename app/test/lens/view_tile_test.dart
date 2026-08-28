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
class RailPainter extends LensPainter {
  RailPainter(super.scene);

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
      hits.add((bounds: bounds, shape: null, fact: fact, identity: fact.identity));
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

Future<void> pump(WidgetTester tester, Bed bed) async {
  final tile = ViewTile(
    tileId: tileId,
    surface: (
      editor: bed.editor,
      settings: bed.settings,
      views: bed.views,
      stage: bed.stage,
      objectCard: null,
      frameCard: null,
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

RailPainter railOf(WidgetTester tester) =>
    tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .firstWhere((paint) => paint.painter is RailPainter)
            .painter
        as RailPainter;

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
    (candidate) => candidate.type == 'attachment' && !before.contains(candidate.id),
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

Future<void> markAt(Bed bed, WidgetTester tester) async {
  final where = bed.views.focusOf(tileId);
  bed.editor.createAt(wallTime, where, where + Rational.fromInt(1, 24));
  await tester.pump();
}

void main() {
  setUp(() {
    lensPainters.clear();
    lensWidgets.clear();
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
    await pump(tester, bed);
    await markAt(bed, tester);
    final mark = railOf(tester).hits.single.bounds.center;
    final identity = railOf(tester).hits.single.identity;
    await clickAt(tester, mark, Duration.zero);
    await clickAt(tester, mark, const Duration(milliseconds: 40));
    // The second click opened the object rather than clearing it. With no card
    // surface wired the open is a no-op, and the selection is what it proves.
    expect(railOf(tester).scene.selection, {identity});
  });

  testWidgets('a lens with no painter refuses in words rather than drawing nothing', (
    tester,
  ) async {
    lensPainters.clear();
    final bed = await layOut(tester, 'intimate');
    await pump(tester, bed);
    expect(find.textContaining('No painter is registered'), findsOneWidget);
  });
}
