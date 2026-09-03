// PICK IS A CLICK ON THE PICTURE (ISSUES 9.2, Don).
//
// "When I click Pick I should be able to click a point on an open lens or the
// minimap." Today Pick is the ladder picker alone: `coordinate_field.dart`'s
// `ChronoMenu(label: 'Pick', glyph: '⌖', ...)` opens `_ladder` and nothing else,
// while the lens on screen is already showing the very coordinate space the
// field is asking about, and the minimap shows all of it at once.
//
// The rules:
//
//   Pick ARMS a point-capture mode across every open surface -- lens tiles and
//   the minimap alike. The mode lives on the session (`ViewBook.pick`), the one
//   object a card and a tile both hold, so there is one mode and not one per
//   surface. A mode shows itself and takes Escape (butter navigation): the
//   pointer wears the ⌖ with a live readout, and Escape or a second Pick disarms.
//   Hover reads out the coordinate under the pointer at THAT SURFACE'S OWN
//   precision; a click commits it into the field and disarms.
//   The precision that lands is the surface's: a click on Strategic yields a day
//   because a Strategic cell IS a day; a click on Intimate yields the instant it
//   can resolve; a minimap click yields whatever coarse level that zoom can
//   honestly name. The entry model carries partial depth already -- "precision
//   typed is coordinate depth ... depth is never fuzziness" -- so a coarse pick
//   stores as it was said and is NEVER zero-filled to a false instant.
//   The ladder stays as the keyboard-and-precision path, unchanged.
//   It is implemented once: `LensPainter.pickAt` on the base, from `unproject`
//   and the painter's declared `precision`, so a surface that says which level
//   it can name gets the whole of picking for free.

import 'dart:io';
import 'dart:math';
import 'dart:ui' show PictureRecorder;

import 'package:chronolog/app.dart';
import 'package:chronolog/cards/coordinate_field.dart';
import 'package:chronolog/chrome/controls.dart';
import 'package:chronolog/chrome/keyboard.dart';
import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/core/coordinate_entry.dart';
import 'package:chronolog/core/coordinate_law.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/projection.dart';
import 'package:chronolog/edit/editor.dart';
import 'package:chronolog/lens/law_context.dart';
import 'package:chronolog/lens/lens_painter.dart';
import 'package:chronolog/lens/minimap/field.dart';
import 'package:chronolog/lens/minimap/labels.dart';
import 'package:chronolog/lens/minimap/painter.dart';
import 'package:chronolog/lens/theme.dart';
import 'package:chronolog/lens/view_tile.dart';
import 'package:chronolog/session/lens_catalog.dart';
import 'package:chronolog/session/view_state.dart';
import 'package:chronolog/stage/tile.dart';
import 'package:chronolog/store/document_store.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/corpus.dart';
import '../helpers/projection_scene.dart';
import '../lens/painters/grid_scene.dart';
import '../store/harness.dart';
import 'harness.dart';
import 'object_harness.dart';

const String frameId = 'calendar:a';
const String tileId = 'view:1';
const String wallTime = 'frame:wall-time';
const Size tileSize = Size(1000, 640);

/// The run's seed: `CHRONOLOG_SEED` when set, else the clock; every reason
/// that varies with it names it.
final int runSeed =
    int.tryParse(Platform.environment['CHRONOLOG_SEED'] ?? '') ??
    DateTime.now().microsecondsSinceEpoch;

/// The key the `keys.escape` SETTING names right now -- never a literal key.
LogicalKeyboardKey escapeKeyOf(Chrome chrome) =>
    activatorFor(chrome.settings.binding('keys.escape'))!.trigger;

/// A world with something on it, so the surfaces have a window worth picking in.
Scene busyWorld() {
  final random = Random(specSeed);
  final world = Scene()..calendar(frameId);
  for (var day = 10; day < 26; day += 1) {
    for (var index = 0; index < 1 + random.nextInt(3); index += 1) {
      world.place(frameId, civil(2026, 8, day, 7 + random.nextInt(12)), title: 'Aug $day #$index');
    }
  }
  return world;
}

/// A picked coordinate is exactly as deep as the surface said, and it CONTAINS
/// the instant under the pointer -- the honest coarse answer, never a zero-filled
/// false instant and never a finer level than the surface can name.
void expectHonestPick(CoordinateEntry entry, Rational under, CoordinateLaw law, String precision, String where) {
  expect(entry.depth, equals(precision), reason: '$where: the depth that lands is the surface\'s own');
  expect(
    authoredDepth(entry.coordinate, law),
    equals(precision),
    reason: '$where: the coordinate stops at the surface\'s precision and no deeper',
  );
  expect(
    entry.coordinate.levels.last.level,
    equals(precision),
    reason: '$where: a coarse pick is stored coarse -- no level below $precision is filled in',
  );
  final start = law.toDays(entry.coordinate);
  expect(start <= under, isTrue, reason: '$where: the picked unit begins at or before the pointer');
  final length = law.unitDays(precision);
  if (length != null) {
    expect(under < start + length, isTrue, reason: '$where: and ends after it');
  } else {
    final mean = law.meanUnitDays(precision)!;
    expect(under < start + mean * Rational.fromInt(2), isTrue, reason: '$where: within the unit');
  }
}

void main() {
  group('every surface picks at its own precision, from one implementation', () {
    test('a pick on any time surface in the catalog is coarse-honest and contains the pointer', () {
      registerShippedLenses();
      final random = Random(specSeed + 1);
      final world = busyWorld();
      const size = Size(1200, 800);
      var picked = 0;
      for (final spec in lensCatalog.values) {
        if (!spec.isTimeSurface) continue;
        final build = lensPainters[spec.id];
        if (build == null) continue;
        final painter = build(sceneOf(world.document, const [frameId], size: size));
        render(painter, size);
        final law = painter.scene.law;
        expect(
          law.has(painter.precision),
          isTrue,
          reason: '${spec.id}: `precision` names a level of the law it draws in, got "${painter.precision}"',
        );
        for (var iteration = 0; iteration < 40; iteration += 1) {
          final at = Offset(random.nextDouble() * size.width, random.nextDouble() * size.height);
          final under = painter.unproject(at);
          final entry = painter.pickAt(at);
          if (under == null) {
            expect(entry, isNull, reason: '${spec.id}: nothing under the pointer picks nothing');
            continue;
          }
          expect(entry, isNotNull, reason: '${spec.id}: a point with time under it can be picked');
          expectHonestPick(entry!, under, law, painter.precision, spec.id);
          picked += 1;
        }
      }
      expect(picked, greaterThan(0));
    });

    test('a Strategic cell IS a day, and Intimate resolves finer than a day', () {
      registerShippedLenses();
      final world = busyWorld();
      const size = Size(1200, 800);
      final strategic = lensPainters['strategic']!(sceneOf(world.document, const [frameId], size: size));
      final intimate = lensPainters['intimate']!(sceneOf(world.document, const [frameId], size: size));
      final law = strategic.scene.law;
      expect(
        strategic.precision,
        equals(law.baseLevel),
        reason: 'ISSUES 9.2: "a click on Strategic gives a day because a Strategic cell IS a day"',
      );
      final names = law.levelNames();
      expect(
        names.indexOf(intimate.precision),
        greaterThan(names.indexOf(law.baseLevel)),
        reason: 'ISSUES 9.2: "a click on Intimate gives the instant it can resolve" -- deeper than a day',
      );
    });

    test('the minimap picks the coarse level its zoom can honestly name', () {
      final random = Random(specSeed + 2);
      final world = busyWorld();
      final engine = ProjectionEngine(world.document);
      final august = civilDays(2026, 8, 18);
      for (final lens in const ['tactical', 'strategic', 'intimate']) {
        final span = Rational.fromInt(14);
        final range = slideRange(null, august, span, null);
        final painter = MinimapPainter(
          field: accumulate(engine, Projection.of(const [frameId]), range, null),
          law: LawContext(engine.lawOf(frameId)),
          theme: shipped['paper']!,
          focusDays: august,
          spanDays: span,
          nowDays: august,
          granularity: granularityFor(lens),
        );
        const size = Size(1280, 140);
        painter.paint(Canvas(PictureRecorder()), size);
        final law = engine.lawOf(frameId);
        expect(law.has(painter.precision), isTrue, reason: 'the minimap names a level of the law');
        for (var iteration = 0; iteration < 30; iteration += 1) {
          final at = Offset(random.nextDouble() * size.width, random.nextDouble() * size.height);
          final entry = painter.pickAt(at);
          expect(entry, isNotNull, reason: 'the whole band is time');
          expectHonestPick(entry!, painter.unproject(at), law, painter.precision, 'minimap over $lens');
        }
      }
    });

    test('a painter that only declares its precision gets picking from the base', () {
      // A plain rail: a day every sixty pixels, nothing else overridden.
      final world = busyWorld();
      const size = Size(600, 400);
      final painter = _Rail(sceneOf(world.document, const [frameId], size: size));
      render(painter, size);
      final random = Random(specSeed + 3);
      for (var iteration = 0; iteration < 30; iteration += 1) {
        final at = Offset(random.nextDouble() * size.width, random.nextDouble() * size.height);
        final entry = painter.pickAt(at);
        expect(
          entry,
          isNotNull,
          reason:
              'ISSUES 9.2: picking is implemented once, on `LensPainter`, from `unproject` and '
              '`precision`; a surface should not have to spell it',
        );
        expectHonestPick(entry!, painter.unproject(at)!, painter.scene.law, painter.precision, 'rail');
      }
    });
  });

  group('the mode', () {
    testWidgets('Pick arms the session\'s pick; Escape or a second Pick disarms; the ladder stays', (
      tester,
    ) async {
      final chrome = cardChrome(null);
      final law = lawsUnderTest().first;
      // UNDER THE ONE KEYBOARD. Escape is not a handler a field installs; it is
      // the surface-wide `ChromeKeyboard` reading the `keys.escape` SETTING, so
      // the field is pumped under that scope exactly as the surface hosts it --
      // the least tree that walks the real binding path, and nothing beside it.
      await pumpCard(
        tester,
        chrome,
        ChromeKeyboard(child: CoordinateField(law: law, value: null, onChanged: (_, _) {})),
      );
      expect(chrome.views.pick.armed, isFalse, reason: 'nothing is armed at rest');
      await tapText(tester, 'Pick');
      expect(
        chrome.views.pick.armed,
        isTrue,
        reason: 'ISSUES 9.2: "When I click Pick I should be able to click a point on an open lens"',
      );
      // The keyboard-and-precision path is untouched: the ladder's first rung is
      // still offered.
      final root = coordinatePickerLadder(law, Coordinate.empty).first;
      expect(find.text(root.label), findsWidgets, reason: 'the ladder stays as the keyboard path');
      final shipped = escapeKeyOf(chrome);
      await tester.sendKeyEvent(shipped);
      await tester.pumpAndSettle();
      expect(chrome.views.pick.armed, isFalse, reason: 'a mode takes Escape (butter navigation)');
      await tapText(tester, 'Pick');
      expect(chrome.views.pick.armed, isTrue);
      await tapText(tester, 'Pick');
      expect(chrome.views.pick.armed, isFalse, reason: 'a second Pick disarms');
      // AND THE SETTING GOVERNS IT. Rebound to a seeded letter no shipped chord
      // claims (a contested chord binds neither, by the keyboard page's own
      // law), the shipped key no longer speaks for the mode and the new one does.
      final taken = chromeKeyDefaults.values.toSet();
      final letters = [
        for (var code = 'a'.codeUnitAt(0); code <= 'z'.codeUnitAt(0); code += 1)
          if (!taken.contains(String.fromCharCode(code))) String.fromCharCode(code),
      ];
      final letter = letters[Random(runSeed).nextInt(letters.length)];
      chrome.settings.setText('keys.escape', letter);
      await tester.pumpAndSettle();
      await tapText(tester, 'Pick');
      expect(chrome.views.pick.armed, isTrue);
      await tester.sendKeyEvent(shipped);
      await tester.pumpAndSettle();
      expect(
        chrome.views.pick.armed,
        isTrue,
        reason: 'seed $runSeed: `keys.escape` now says "$letter"; the shipped key is not the binding',
      );
      await tester.sendKeyEvent(escapeKeyOf(chrome));
      await tester.pumpAndSettle();
      expect(
        chrome.views.pick.armed,
        isFalse,
        reason: 'seed $runSeed: the key the SETTING names ("$letter") is what disarms the mode',
      );
    });

    testWidgets('an armed surface wears the ⌖ with a live readout, and a click commits then disarms', (
      tester,
    ) async {
      final bed = await _layOut(tester, 'strategic');
      CoordinateEntry? landed;
      bed.views.pick.arm(onPicked: (entry) => landed = entry);
      await tester.pumpAndSettle();
      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: Offset.zero);
      addTearDown(pointer.removePointer);
      final tile = tester.getRect(find.byType(ViewTile));
      final at = Offset(tile.left + tile.width * 0.6, tile.top + tile.height * 0.55);
      await pointer.moveTo(at);
      await tester.pumpAndSettle();
      final painter = _livePainter(tester);
      final expected = painter.pickAt(at - tile.topLeft);
      expect(expected, isNotNull, reason: 'the point chosen has a day under it');
      expect(
        find.textContaining('⌖'),
        findsWidgets,
        reason: 'ISSUES 9.2: "the cursor takes the ⌖" -- a mode must show itself',
      );
      expect(
        find.textContaining(formatCoordinateEntry(expected!.coordinate, painter.scene.law)),
        findsWidgets,
        reason: 'ISSUES 9.2: hover reads out the coordinate under the pointer at THIS surface\'s precision',
      );
      await tester.tapAt(at);
      await tester.pumpAndSettle();
      expect(landed, isNotNull, reason: 'a click commits into the field');
      expect(landed!.depth, equals(painter.precision), reason: 'at the surface\'s own depth');
      expect(landed!.coordinate, equals(expected.coordinate), reason: 'exactly what the readout said');
      expect(bed.views.pick.armed, isFalse, reason: 'and disarms');
      expect(find.textContaining('⌖'), findsNothing, reason: 'the readout goes with the mode');
      expect(
        bed.editor.document.events,
        isEmpty,
        reason: 'ISSUES 9.2: an armed click picks a point; it never creates or selects',
      );
    });
  });
}

/// A rail: x is days from the focus at the centre. It declares which level it
/// can name and NOTHING about picking.
class _Rail extends LensPainter {
  _Rail(super.scene);

  static const double dayPixels = 60;

  @override
  String get precision => scene.law.baseLevel;

  @override
  Rational? unproject(Offset at) =>
      scene.focusDays +
      Rational.parse(((at.dx - scene.size.width / 2) / dayPixels).toStringAsFixed(9));

  @override
  Offset? project(Rational days) =>
      Offset(((days - scene.focusDays).toDouble() * dayPixels) + scene.size.width / 2, 0);

  @override
  void paint(Canvas canvas, Size size) {}

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

LensPainter _livePainter(WidgetTester tester) {
  final paints = tester.widgetList<CustomPaint>(
    find.byWidgetPredicate((widget) => widget is CustomPaint && widget.painter is BledPainter),
  );
  expect(paints, isNotEmpty, reason: 'the view tile hosts its lens through one bled painter');
  return (paints.first.painter! as BledPainter).lens;
}

typedef _Bed = ({Editor editor, ViewBook views, Stage stage});

Future<_Bed> _layOut(WidgetTester tester, String lens) async {
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
