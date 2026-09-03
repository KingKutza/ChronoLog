// A SPAN IS A UNIT AND A NUMBER, AND ZOOM IS MOVING THAT NUMBER (ISSUES 9.2, Don).
//
// "Also probably just move to a days counter." Intimate's bar carried two
// stepper chips -- `Days behind` and `Days ahead` -- so thirty days was thirty
// clicks and the two numbers were one span said twice; and every other lens's
// window was a bare stepper of its own. This file was first authored to a single
// `span` control. Don's ruling settled the SHAPE and took the broad class:
//
// "Duration/span: pick a unit (in future, cycles too) and a number. Zooming is
// moving that number. For lenses like Intimate that zoom on two axes, one is
// primary and one secondary; secondary is on a modifier key plus zoom. Both can
// be accessed and edited in a zoom dropdown, both can handle floats, both can be
// typed or incremented, snapping back to int."
//
// Four things follow, and they are the four groups below:
//
//   (1) A SPAN IS A UNIT AND A NUMBER, not a count of columns -- `intimate.back`
//       /`forward`, `tactical.rows`/`columns`, `strategic.months`, `wall.months`,
//       `lines.days`, `spiral.*`, `radial.cycleDays` and the roster `span` all
//       become one control of that shape. "Thirty months was also thirty clicks;
//       it is one defect on every lens."
//   (2) ZOOM IS MOVING THAT NUMBER -- one definition for every surface, which
//       retires `scaleKey`; the number holds FLOATS, so nothing rounds.
//   (3) TWO AXES, PRIMARY AND SECONDARY: a lens may declare two spans; plain zoom
//       moves the primary, a modifier plus zoom the secondary; both visible and
//       editable in a zoom dropdown. Which modifier is a BINDING, not a literal.
//   (4) TYPED OR INCREMENTED, SNAPPING BACK TO INT -- a typed value may be
//       fractional, an increment lands on a whole number.
//
// THE CONTRACT this file names: a span control is `ControlSpec('span', key,
// label, setting, unit, ...)` -- the kind is the word `span`, and it carries the
// unit it counts in. The FIRST declared span is the primary, the second (where a
// lens declares one) the secondary -- positional, exactly as "the first declared
// option is the default -- no shipped ordinal". `LensSpec.scaleKey` is retired
// (null everywhere). The modifier for the secondary is the text setting
// `pointer.zoomSecondary`. The bar wears ONE drop whose label says "Zoom", in
// which every declared span is a one-math field with its own `+` and `-`.
// Intimate's primary span is its `span` view key in days; its secondary is the
// rail's own axis.

import 'dart:math';

import 'package:chronolog/app.dart';
import 'package:chronolog/chrome/context_bar.dart';
import 'package:chronolog/chrome/controls.dart';
import 'package:chronolog/chrome/menus.dart';
import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/math.dart';
import 'package:chronolog/edit/editor.dart';
import 'package:chronolog/lens/painters/intimate.dart';
import 'package:chronolog/lens/theme.dart';
import 'package:chronolog/lens/view_tile.dart';
import 'package:chronolog/session/lens_catalog.dart';
import 'package:chronolog/session/settings.dart';
import 'package:chronolog/session/view_state.dart';
import 'package:chronolog/stage/tile.dart';
import 'package:chronolog/store/document_store.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../cards/harness.dart';
import '../core/corpus.dart';
import '../helpers/projection_scene.dart';
import '../lens/painters/grid_scene.dart';
import '../store/harness.dart';

const String frameId = 'calendar:a';
const String wallTime = 'frame:wall-time';
const String tileId = 'view:1';

/// The one span control kind. A kind is a string, not an enum; this is the word.
const String spanKind = 'span';

List<ControlSpec> spanControls(LensSpec spec) => [
  for (final control in spec.controls)
    if (control.kind == spanKind) control,
];

ControlSpec? primarySpan(LensSpec spec) => spanControls(spec).firstOrNull;

ControlSpec? secondarySpan(LensSpec spec) => spanControls(spec).elementAtOrNull(1);

/// The keys a chord names, by the words a person writes them with.
List<LogicalKeyboardKey> keysOf(String chord) => [
  for (final word in chord.toLowerCase().split(RegExp(r'[+\s|]+')))
    if (word == 'ctrl' || word == 'control') LogicalKeyboardKey.controlLeft
    else if (word == 'shift') LogicalKeyboardKey.shiftLeft
    else if (word == 'alt') LogicalKeyboardKey.altLeft
    else if (word == 'meta' || word == 'cmd' || word == 'win') LogicalKeyboardKey.metaLeft,
];

typedef Bed = ({ViewBook views, Settings settings, Editor editor});

/// A real view tile over an in-memory store, showing [lens].
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
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: themeDataFor(shipped['paper']!),
      home: Scaffold(
        body: ChromeScope(
          chrome: Chrome(settings: settings, stage: stage, views: views, editor: editor),
          child: Center(child: SizedBox(width: 1100, height: 640, child: tile)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (views: views, settings: settings, editor: editor);
}

void main() {
  group('(1) a span is a unit and a number', () {
    test('every identifier a span formula reads is a span control carrying its unit -- the class '
        'check', () {
      // "Thirty months was also thirty clicks; it is one defect on every lens."
      // Every lens that declares a span reads it through the one instrument,
      // rather than each lens spelling its own stepper.
      final wrong = <String>[];
      final unitless = <String>[];
      for (final spec in lensCatalog.values) {
        for (final key in identifiersOf(parse(spec.spanFormula))) {
          final control = spec.controls.where((entry) => entry.key == key).firstOrNull;
          if (control == null) continue; // a name the law supplies, not a control
          if (control.kind != spanKind) wrong.add('${spec.id}.${control.key} (${control.kind})');
          if (control.unit == null) unitless.add('${spec.id}.${control.key}');
        }
        expect(
          primarySpan(spec),
          isNotNull,
          reason: 'ISSUES 9.2: ${spec.id} declares no span at all; a span is a unit and a number',
        );
      }
      expect(
        wrong,
        isEmpty,
        reason: 'ISSUES 9.2: these span inputs are still bare steppers spelled per lens: $wrong',
      );
      expect(unitless, isEmpty, reason: 'ISSUES 9.2: a span without a unit is a count: $unitless');
    });

    test('Intimate declares two spans, no pair of day steppers, and no scale key', () {
      final spec = lensCatalog['intimate']!;
      expect(
        spanControls(spec),
        hasLength(2),
        reason:
            'ISSUES 9.2: "for lenses like Intimate that zoom on two axes, one is primary and one '
            'secondary" -- Intimate declares ${spanControls(spec).length} span(s).',
      );
      final daySteppers = [
        for (final control in spec.controls)
          if (control.kind == 'number' && control.unit == spec.spanUnit) control.label,
      ];
      expect(
        daySteppers,
        isEmpty,
        reason: 'ISSUES 9.2: $daySteppers are one span said twice, each a ±1 stepper',
      );
      for (final lens in lensCatalog.values) {
        expect(
          lens.scaleKey,
          isNull,
          reason:
              'ISSUES 9.2: zoom is moving the span number -- one definition for every surface -- '
              'which retires the split where ${lens.id} scales `${lens.scaleKey}` instead.',
        );
      }
    });

    test('a typed expression governs the count: `2*7` is fourteen days, read by the one math', () {
      final random = Random(specSeed);
      for (var iteration = 0; iteration < 20; iteration += 1) {
        final a = 1 + random.nextInt(6), b = 1 + random.nextInt(9);
        final source = '$a*$b';
        final expected = a * b;
        final world = Scene()..calendar(frameId);
        const size = Size(1600, 720);
        final painter = IntimatePainter(
          sceneOf(world.document, const [frameId], size: size, view: {'span': source}),
        );
        render(painter, size);
        final day = painter.law.dayOf(painter.scene.focusDays);
        final start = Rational(day) * painter.law.dayDays;
        final width = painter.project(start + painter.law.dayDays)!.dx - painter.project(start)!.dx;
        final area = size.width - painter.scene.px('intimate.rail');
        expect(
          width,
          closeTo(area / expected, 1e-6),
          reason:
              'ISSUES 9.2: the span "$source" was not read as the one math (expected $expected '
              'columns). A lens number is an expression, the same way every other lens number is.',
        );
      }
    });
  });

  group('(2) zoom is moving that number, and it holds floats', () {
    testWidgets('on every timed lens a notch multiplies the primary span by exactly the step', (
      tester,
    ) async {
      // "It also kills the rounding that made Spiral's zoom a no-op, because the
      // number holds FLOATS: `radial.inward` at 1 times a wheel notch is 1.1 and
      // stays 1.1." One definition for every surface; no lens by name.
      registerShippedLenses();
      for (final spec in lensCatalog.values) {
        if (!spec.isTimeSurface || !lensPainters.containsKey(spec.id)) continue;
        final primary = primarySpan(spec);
        expect(primary, isNotNull, reason: '${spec.id} declares a primary span');
        final bed = await layOut(tester, spec.id);
        final controller = viewTileControllers[tileId]!;
        final step = bed.settings.value('pointer.zoomStep');
        final state = bed.views.of(tileId);
        final before = state.number(primary!.key, bed.settings);
        expect(before, greaterThan(Rational.zero), reason: '${spec.id} has a span to move');
        controller.zoom(step);
        expect(
          state.number(primary.key, bed.settings),
          equals(before * step),
          reason:
              'ISSUES 9.2: a notch on ${spec.id} took `${primary.key}` from $before to '
              '${state.number(primary.key, bed.settings)}; zoom is that number times the step, '
              'exactly, floats kept.',
        );
        controller.zoom(Rational.one / step);
        expect(state.number(primary.key, bed.settings), equals(before), reason: 'and back, exactly');
      }
    });
  });

  group('(3) two axes: primary and secondary, the modifier a binding', () {
    testWidgets('a modifier plus zoom moves the secondary span and leaves the primary alone', (
      tester,
    ) async {
      final spec = lensCatalog['intimate']!;
      final primary = primarySpan(spec), secondary = secondarySpan(spec);
      expect(secondary, isNotNull, reason: 'Intimate declares a secondary span');
      final bed = await layOut(tester, 'intimate');
      final chord = bed.settings.text('pointer.zoomSecondary');
      expect(
        chord,
        isNotEmpty,
        reason: 'ISSUES 9.2: which modifier moves the secondary is a binding, never a literal',
      );
      final state = bed.views.of(tileId);
      final step = bed.settings.value('pointer.zoomStep');
      final primaryBefore = state.number(primary!.key, bed.settings);
      final secondaryBefore = state.number(secondary!.key, bed.settings);
      // The zoom gesture (ctrl+wheel) with the secondary's modifier held too.
      final held = {LogicalKeyboardKey.controlLeft, ...keysOf(chord)};
      for (final key in held) {
        await tester.sendKeyDownEvent(key);
      }
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      final centre = tester.getCenter(find.byType(ViewTile));
      await tester.sendEventToBinding(pointer.hover(centre));
      await tester.sendEventToBinding(
        pointer.scroll(Offset(0, bed.settings.value('pointer.wheelNotch').toDouble())),
      );
      await tester.pumpAndSettle();
      for (final key in held) {
        await tester.sendKeyUpEvent(key);
      }
      final secondaryAfter = state.number(secondary.key, bed.settings);
      expect(
        {secondaryBefore * step, secondaryBefore / step},
        contains(secondaryAfter),
        reason:
            'ISSUES 9.2: "$chord" plus zoom moved `${secondary.key}` from $secondaryBefore to '
            '$secondaryAfter; one notch on the secondary is one step, either way round.',
      );
      expect(
        state.number(primary.key, bed.settings),
        equals(primaryBefore),
        reason: 'and the primary did not move',
      );
    });
  });

  group('(4) both spans in one drop: typed or incremented, snapping back to int', () {
    testWidgets('the zoom drop shows every span as a one-math field with steppers; a typed '
        'fraction stays, a step lands whole; and nothing behind or ahead', (tester) async {
      final spec = lensCatalog['intimate']!;
      final spans = spanControls(spec);
      expect(spans, hasLength(2), reason: 'Intimate declares two spans');
      final chrome = cardChrome(null);
      chrome.views.of('view:1').lensId = 'intimate';
      await pumpCard(tester, chrome, const ContextBar());
      for (final said in const ['Days behind', 'Days ahead']) {
        expect(
          find.textContaining(said),
          findsNothing,
          reason: 'ISSUES 9.2: "$said" is half a span. The span is one control.',
        );
      }
      final drop = find.byWidgetPredicate(
        (widget) =>
            widget is ChronoMenu &&
            ('${widget.label} ${widget.glyph ?? ''} ${widget.name ?? ''}').toLowerCase().contains('zoom'),
      );
      expect(
        drop,
        findsOneWidget,
        reason: 'ISSUES 9.2: "both can be accessed and edited in a zoom dropdown" -- the bar wears one',
      );
      await tester.tap(drop);
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      expect(
        fields,
        findsAtLeastNWidgets(spans.length),
        reason: 'every declared span is a field a person TYPES into -- `30`, `2*7`, `2.3`',
      );
      final view = chrome.views.of('view:1');
      Rational read(String key) {
        final value = evaluateSource('${view.read(key, chrome.settings) ?? ''}', const Env());
        expect(value, isA<Rational>(), reason: 'the span reads as a number in the one math');
        return value as Rational;
      }

      for (final span in spans) {
        expect(find.textContaining(span.label), findsWidgets, reason: 'the drop names ${span.label}');
      }
      final primary = spans.first;
      final field = fields.first;
      await tester.enterText(field, '2.3');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        read(primary.key),
        equals(Rational.fromInt(23, 10)),
        reason: 'ISSUES 9.2: "both can handle floats" -- a typed 2.3 is 2.3',
      );
      final box = tester.getRect(field);
      final plus = find.text('+').evaluate().where((element) {
        final at = tester.getCenter(find.byWidget(element.widget));
        return (at.dy - box.center.dy).abs() < box.height;
      });
      expect(plus, isNotEmpty, reason: 'a `+` rides the span field\'s own row');
      await tester.tap(find.byWidget(plus.first.widget));
      await tester.pumpAndSettle();
      expect(
        read(primary.key),
        equals(Rational.fromInt(3)),
        reason: 'ISSUES 9.2: "typed or incremented, snapping back to int" -- a step from 2.3 lands on 3',
      );
    });
  });
}
