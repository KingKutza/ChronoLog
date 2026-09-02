// THE IN-APP COLOUR PICKER (ISSUES 9.2, Don).
//
// "Plus still no picker for specific colours. I appreciate easy options and hex
// codes, but I still need an in-app picker." `card_chrome.dart`'s `ColorField`
// is the whole of colour choosing today: a named-swatch menu titled "Pick a
// colour", a clear, and hex accepted as text. Named options and hex are the two
// ends; the middle -- where a person actually chooses a colour -- is missing.
//
// The rules:
//
//   A real picker: a two-dimensional field ("Shade") plus a hue track ("Hue"),
//   with the hex box ("Hex") live-bound both ways. Dragging and typing are THE
//   SAME ACT: a drag updates the text, typing moves the handle, and a round trip
//   through either loses nothing.
//   The named swatches survive as the fast path.
//   ONE widget, `ColorPicker`, that every colour field in the app opens -- melt
//   means centralize -- so a second hue track anywhere is a failure here.
//   Colour remains AUTHORED: opening the picker on an object suggests nothing,
//   pre-fills nothing, infers nothing from the object's data.
//
// Semantics labels are the contract the hand and the spec share: 'Hue', 'Shade',
// 'Hex', 'Hue handle', 'Shade handle'.

import 'dart:math';

import 'package:chronolog/cards/card_chrome.dart';
import 'package:chronolog/cards/color_picker.dart';
import 'package:chronolog/cards/frame_card.dart';
import 'package:chronolog/cards/theme_card.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/lens/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/corpus.dart';
import 'harness.dart';
import 'object_harness.dart';

String randomHex(Random random) =>
    '#${random.nextInt(0x1000000).toRadixString(16).padLeft(6, '0')}';

Finder get hue => find.bySemanticsLabel('Hue');
Finder get shade => find.bySemanticsLabel('Shade');
Finder get hex => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == 'Hex',
);
Finder get shadeHandle => find.bySemanticsLabel('Shade handle');
Finder get hueHandle => find.bySemanticsLabel('Hue handle');

String hexShown(WidgetTester tester) => tester.widget<TextField>(hex).controller!.text;

void main() {
  testWidgets('dragging the shade field writes the hex live, and the hex parses', (tester) async {
    final heard = <String>[];
    await pumpCard(
      tester,
      cardChrome(null),
      ColorPicker(value: '#3f6ea3', onChanged: heard.add),
    );
    expect(hue, findsOneWidget, reason: 'ISSUES 9.2: a hue track');
    expect(shade, findsOneWidget, reason: 'ISSUES 9.2: a two-dimensional field');
    expect(hex, findsOneWidget, reason: 'ISSUES 9.2: the hex box, live-bound');
    final box = tester.getRect(shade);
    final random = Random(specSeed);
    for (var iteration = 0; iteration < 8; iteration += 1) {
      final at = Offset(
        box.left + box.width * (0.1 + random.nextDouble() * 0.8),
        box.top + box.height * (0.1 + random.nextDouble() * 0.8),
      );
      final gesture = await tester.startGesture(box.center);
      await gesture.moveTo(at);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(heard, isNotEmpty, reason: 'a drag chooses a colour');
      expect(parseColor(heard.last), isNotNull, reason: 'what it chooses reads as a colour');
      expect(
        hexShown(tester).toLowerCase(),
        equals(heard.last.toLowerCase()),
        reason: 'ISSUES 9.2: "the hex box live-bound both ways" -- the drag updates the text',
      );
    }
  });

  testWidgets('typing a hex moves the handles, and a typed round trip is exact', (tester) async {
    final heard = <String>[];
    await pumpCard(tester, cardChrome(null), ColorPicker(value: '#808080', onChanged: heard.add));
    final random = Random(specSeed + 1);
    for (var iteration = 0; iteration < 12; iteration += 1) {
      final first = randomHex(random), second = randomHex(random);
      await tester.enterText(hex, first);
      await tester.pumpAndSettle();
      final atFirst = (tester.getCenter(shadeHandle), tester.getCenter(hueHandle));
      expect(heard.last.toLowerCase(), equals(first), reason: 'typing IS choosing: the same act');
      await tester.enterText(hex, second);
      await tester.pumpAndSettle();
      final atSecond = (tester.getCenter(shadeHandle), tester.getCenter(hueHandle));
      expect(
        atSecond,
        isNot(equals(atFirst)),
        reason: 'ISSUES 9.2: "typing moves the handle" -- $first to $second moved nothing',
      );
      await tester.enterText(hex, first);
      await tester.pumpAndSettle();
      final again = (tester.getCenter(shadeHandle), tester.getCenter(hueHandle));
      expect((again.$1 - atFirst.$1).distance, lessThan(1), reason: 'the shade handle returns exactly');
      expect((again.$2 - atFirst.$2).distance, lessThan(1), reason: 'the hue handle returns exactly');
      expect(hexShown(tester).toLowerCase(), equals(first), reason: 'and the hex is the hex');
    }
  });

  testWidgets('a drag, its hex read back and typed again, lands the handle where the drag left it', (
    tester,
  ) async {
    final heard = <String>[];
    await pumpCard(tester, cardChrome(null), ColorPicker(value: '#3f6ea3', onChanged: heard.add));
    final box = tester.getRect(shade);
    final random = Random(specSeed + 2);
    for (var iteration = 0; iteration < 6; iteration += 1) {
      final at = Offset(
        box.left + box.width * (0.15 + random.nextDouble() * 0.7),
        box.top + box.height * (0.15 + random.nextDouble() * 0.7),
      );
      final gesture = await tester.startGesture(box.center);
      await gesture.moveTo(at);
      await gesture.up();
      await tester.pumpAndSettle();
      final left = tester.getCenter(shadeHandle);
      final said = hexShown(tester);
      await tester.enterText(hex, '#000000');
      await tester.pumpAndSettle();
      await tester.enterText(hex, said);
      await tester.pumpAndSettle();
      expect(
        (tester.getCenter(shadeHandle) - left).distance,
        lessThan(1.5),
        reason:
            'ISSUES 9.2: "a round trip through either loses nothing" -- dragging to $said and '
            'typing $said back are two spellings of one colour',
      );
    }
  });

  testWidgets('the named swatches survive as the fast path, beside the picker', (tester) async {
    final chrome = cardChrome(null);
    await pumpCard(tester, chrome, ColorField(value: '', onChanged: (_) {}));
    await tester.tap(find.byTooltip('Pick a colour'));
    await tester.pumpAndSettle();
    expect(find.byType(ColorPicker), findsOneWidget, reason: 'ISSUES 9.2: the swatch opens the picker');
    final names = chrome.settings.text('card.palette').split(RegExp(r'\s+'))..removeWhere((w) => w.isEmpty);
    expect(names, isNotEmpty);
    for (final name in names) {
      expect(find.byTooltip(name), findsWidgets, reason: '"$name" is still one click away');
    }
  });

  testWidgets('one picker for every colour field: every hue track is inside a ColorPicker', (
    tester,
  ) async {
    final bench = await openCards(createEmptyWorkspaceDocument());
    // The group card, where Don met the swatch first.
    await pumpCard(tester, cardChrome(bench.editor), const FrameCard(kind: 'group'));
    await tester.tap(find.byTooltip('Pick a colour').first);
    await tester.pumpAndSettle();
    _expectOnePickerClass(tester, 'the group card');
    // The palette card: a theme's role is the same control as a frame's ink.
    await pumpCard(tester, cardChrome(null), const ThemeCard());
    await tester.tap(find.byTooltip('Pick a colour').first);
    await tester.pumpAndSettle();
    _expectOnePickerClass(tester, 'the theme card');
  });

  testWidgets('colour is authored: an unauthored value opens an empty picker and chooses nothing', (
    tester,
  ) async {
    final heard = <String>[];
    await pumpCard(tester, cardChrome(null), ColorPicker(value: '', onChanged: heard.add));
    expect(hexShown(tester), isEmpty, reason: 'nothing is pre-filled from anywhere');
    expect(
      heard,
      isEmpty,
      reason: 'ISSUES 9.2: opening a picker is not choosing; no colour is inferred or suggested',
    );
  });
}

void _expectOnePickerClass(WidgetTester tester, String where) {
  final tracks = hue.evaluate().length;
  expect(tracks, greaterThan(0), reason: 'ISSUES 9.2: $where opens a picker with a hue track');
  final inside = find.descendant(of: find.byType(ColorPicker), matching: hue).evaluate().length;
  expect(
    inside,
    equals(tracks),
    reason:
        'ISSUES 9.2: $where draws a hue track outside `ColorPicker` -- a second implementation. '
        'Melt means centralize: one widget every colour field uses.',
  );
}
