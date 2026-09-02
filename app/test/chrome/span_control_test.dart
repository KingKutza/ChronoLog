// ONE DAYS COUNTER, READ AS ONE MATH (ISSUES 9.2, Don).
//
// "Also probably just move to a days counter." Intimate's bar carries two
// stepper chips -- `ControlSpec('number', 'back', 'Days behind', ...)` and
// `('number', 'forward', 'Days ahead', ...)` -- and `namedNumber` steps plus or
// minus one per click, so thirty days is thirty clicks and the two numbers are
// one span said twice.
//
// It must NOT become a raw number field: `chrome/controls.dart` rules that out
// ("no raw number field, no comma string") and `namedNumber` is deliberately
// "never a bare spinner". The instrument is the one already in the same switch:
// the one-math `ExpressionField`, where a person types `30` or `2*7` and the
// lens reads it the way every other lens number is read -- which is also the
// standing ruling that lens numbers are settings whose value is a formula.
//
// The rules:
//
//   A span is ONE control of kind `span`: a one-math field with the steppers'
//   quick adjustment riding the same chip. Never two numbers, never a spinner.
//   A typed expression governs what the lens draws.
//   Every lens that declares a span reads it this one way -- every identifier
//   its `spanFormula` names is a `span` control -- rather than each lens spelling
//   its own. This flags every lens whose window is still a bare number stepper
//   (Tactical, Strategic, Wall, Lines, Radial, the roster `_span`), and that is
//   the class, not collateral: thirty months is also thirty clicks.

import 'dart:math';

import 'package:chronolog/chrome/context_bar.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/math.dart';
import 'package:chronolog/lens/painters/intimate.dart';
import 'package:chronolog/session/lens_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../cards/harness.dart';
import '../core/corpus.dart';
import '../helpers/projection_scene.dart';
import '../lens/painters/grid_scene.dart';

const String frameId = 'calendar:a';

/// The one span control kind. A kind is a string, not an enum; this is the word.
const String spanKind = 'span';

List<ControlSpec> spanControls(LensSpec spec) => [
  for (final control in spec.controls)
    if (control.kind == spanKind) control,
];

void main() {
  test('Intimate declares one span, and no pair of day steppers', () {
    final spec = lensCatalog['intimate']!;
    expect(
      spanControls(spec),
      hasLength(1),
      reason:
          'ISSUES 9.2: "one days counter" -- Intimate declares ${spanControls(spec).length} '
          'controls of kind `$spanKind`. The span is said once.',
    );
    final daySteppers = [
      for (final control in spec.controls)
        if (control.kind == 'number' && control.unit == spec.spanUnit) control.label,
    ];
    expect(
      daySteppers,
      isEmpty,
      reason:
          'ISSUES 9.2: $daySteppers are one span said twice, each a ±1 stepper -- thirty days '
          'is thirty clicks.',
    );
  });

  test('every lens that declares a span reads it through the span control -- the class check', () {
    final wrong = <String>[];
    for (final spec in lensCatalog.values) {
      final named = identifiersOf(parse(spec.spanFormula));
      for (final key in named) {
        final control = spec.controls.where((entry) => entry.key == key).firstOrNull;
        if (control == null) continue; // a name the law supplies, not a control
        if (control.kind != spanKind) wrong.add('${spec.id}.${control.key} (${control.kind})');
      }
    }
    expect(
      wrong,
      isEmpty,
      reason:
          'ISSUES 9.2: these span inputs are still spelled per lens as bare steppers: $wrong. '
          'One instrument reads every span, so no lens decides its own.',
    );
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

  testWidgets('the bar shows one span field with its steppers, and nothing behind or ahead', (
    tester,
  ) async {
    final chrome = cardChrome(null);
    chrome.views.of('view:1').lensId = 'intimate';
    await pumpCard(tester, chrome, const ContextBar());
    // Intimate's own controls may sit under the one fold.
    if (find.textContaining('Options').evaluate().isNotEmpty) {
      await tapPart(tester, 'Options');
    }
    for (final said in const ['Days behind', 'Days ahead']) {
      expect(
        find.textContaining(said),
        findsNothing,
        reason: 'ISSUES 9.2: "$said" is half a span. The span is one control.',
      );
    }
    final spanField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          ((widget.decoration?.labelText ?? '').toLowerCase().contains('day') ||
              (widget.decoration?.hintText ?? '').toLowerCase().contains('day')),
    );
    final labelled = find.textContaining('Days');
    expect(
      labelled.evaluate().isNotEmpty || spanField.evaluate().isNotEmpty,
      isTrue,
      reason: 'ISSUES 9.2: the bar names the span in days, once',
    );
    expect(
      find.byType(TextField),
      findsWidgets,
      reason:
          'ISSUES 9.2: the span is a one-math field a person TYPES into -- `30`, `2*7` -- never '
          'a spinner alone. No text field is on the bar.',
    );
    // The steppers ride the same chip, so a quick nudge survives: the `+` on the
    // span field's own row steps the span by exactly one, read through the one
    // math. (`grain` and `hourPixels` wear the same glyphs on the same bar, so a
    // glyph anywhere proves nothing -- it has to be THIS row's, and it has to move
    // THIS number.)
    final field = tester.getRect(find.byType(TextField).first);
    Rational current() {
      final source = '${chrome.views.of('view:1').read('span', chrome.settings) ?? ''}';
      final value = evaluateSource(source, const Env());
      expect(value, isA<Rational>(), reason: 'the span reads as a number in the one math: "$source"');
      return value as Rational;
    }
    final before = current();
    final plus = find.text('+').evaluate().where((element) {
      final at = tester.getCenter(find.byWidget(element.widget));
      return at.dx > field.left && (at.dy - field.center.dy).abs() < field.height;
    });
    expect(
      plus,
      isNotEmpty,
      reason: 'ISSUES 9.2: no `+` rides the span field\'s own row -- the quick nudge did not survive',
    );
    await tester.tap(find.byWidget(plus.first.widget));
    await tester.pumpAndSettle();
    expect(
      current() - before,
      equals(Rational.one),
      reason: 'ISSUES 9.2: a step on the span chip is one more day, and the field still reads as math',
    );
  });
}
