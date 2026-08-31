// GROUP COLOUR IS UNAUTHORABLE (ISSUES 8.31, evening, Don live).
//
// "On creating a group I have no clear way to set the color, clicking the gray
// box did not launch a color picker and typing Blue into the text field did
// nothing either." Two dead controls on one property, and the ruling: "the swatch
// opens a picker, and the text field parses what a person writes — a named
// colour, a hex — with a refusal in words when it parses to nothing. A control
// that accepts input and does nothing is worse than no control."
//
// `colorField` is THE one colour control -- a frame's ink and a theme's role are
// the same widget -- so these cases are about every colour field in the program,
// asked through the group card where Don met them.

import 'package:chronolog/cards/card_chrome.dart';
import 'package:chronolog/cards/frame_card.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/lens/color.dart';
import 'package:chronolog/lens/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';
import 'object_harness.dart';

/// The colours a person writes. Not a table of expected values -- what is
/// asserted is only that each one PARSES, because "Blue" is a colour and the
/// field's job is to read what was written.
const List<String> writtenColours = ['Blue', 'blue', 'red', 'Dark Green', 'rebeccapurple'];

/// The group card, before the group exists: where Don was standing.
Future<void> pumpNewGroup(WidgetTester tester, CardBench bench) =>
    pumpCard(tester, cardChrome(bench.editor), const FrameCard(kind: 'group'));

Frame? lastFrame(CardBench bench) => bench.editor.document.frames.values.isEmpty
    ? null
    : bench.editor.document.frames.values.last;

void main() {
  test('a colour a person writes by name parses', () {
    for (final written in writtenColours) {
      expect(
        parseColor(written),
        isNotNull,
        reason:
            'ISSUES (8.31, evening): "typing Blue into the text field did nothing '
            'either" — the one colour reader takes hex and nothing else, so "$written" '
            'reads as no colour at all.',
      );
    }
    // The hex road already works, and must keep working.
    expect(parseColor('#3f6ea3'), isNotNull);
    expect(parseColor('3f6ea3'), isNotNull);
  });

  testWidgets('typing a named colour on the group card sets the group\'s colour', (tester) async {
    final bench = await openCards(createEmptyWorkspaceDocument());
    await pumpNewGroup(tester, bench);
    await tester.enterText(fieldHinted('What this frame is called'), 'Errands');
    await tester.enterText(fieldHinted('inherited'), 'Blue');
    await tester.pump();
    await tapText(tester, 'Save');
    final frame = lastFrame(bench);
    expect(frame?.title, 'Errands', reason: 'the group was made');
    expect(
      authoredColorOf(frame?.extra),
      isNotNull,
      reason:
          'ISSUES (8.31, evening): "I have no clear way to set the color ... typing '
          'Blue into the text field did nothing" — the card stored the text and the '
          'colour cascade reads nothing from it.',
    );
  });

  testWidgets('input that parses to nothing is refused in words, never stored as a colour', (
    tester,
  ) async {
    final bench = await openCards(createEmptyWorkspaceDocument());
    await pumpNewGroup(tester, bench);
    await tester.enterText(fieldHinted('What this frame is called'), 'Errands');
    await tester.enterText(fieldHinted('inherited'), 'not a colour at all');
    await tester.pump();
    await tapText(tester, 'Save');
    final frame = lastFrame(bench);
    final stored = obj(frame?.extra['display'])?['color'] ?? frame?.extra['color'];
    expect(
      stored,
      isNull,
      reason:
          'ISSUES (8.31, evening): "A control that accepts input and does nothing is '
          'worse than no control" — unparseable text was accepted and written to the '
          'frame as if it were a colour (stored: $stored).',
    );
  });

  testWidgets('the swatch opens a picker', (tester) async {
    final bench = await openCards(createEmptyWorkspaceDocument());
    await pumpNewGroup(tester, bench);
    // The swatch sits at the leading end of the one colour control, a gap before
    // the field: its place is the control's own construction, not a guess.
    final field = tester.getRect(fieldHinted('inherited'));
    final gap = cardTunable(bench.settings, 'card.gap').toDouble();
    final size = cardTunable(bench.settings, 'card.swatch').toDouble();
    final swatch = Offset(field.left - gap - size / 2, field.center.dy);
    final before = tester.allWidgets.length;
    await tester.tapAt(swatch);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.allWidgets.length,
      greaterThan(before),
      reason:
          'ISSUES (8.31, evening): "clicking the gray box did not launch a color '
          'picker" — the swatch is a bare Container with no gesture, so the tap '
          'changed nothing on the card.',
    );
  });

  testWidgets('a colour the field accepts is what the swatch shows', (tester) async {
    final bench = await openCards(createEmptyWorkspaceDocument());
    await pumpNewGroup(tester, bench);
    await tester.enterText(fieldHinted('inherited'), '#3f6ea3');
    await tester.pump();
    // The one control shows what it holds: the hex road, which already works, is
    // the control case that proves the swatch reads the field at all.
    final shown = tester
        .widgetList<Container>(find.byType(Container))
        .where((box) => box.color != null && hexOf(box.color!) == '#3f6ea3');
    expect(shown, isNotEmpty, reason: 'the swatch wears the colour the field names');
  });
}
