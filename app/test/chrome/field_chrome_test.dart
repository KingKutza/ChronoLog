// A FIELD LOOKS LIKE A FIELD, AND IT IS NOT WRITTEN UNDER THE HAND (ISSUES 9.2).
//
// Two reports, one class each. "It is a blank text box with a background the
// same as the window and no border, that is why I did not see it": the one-math
// entry box draws no border anywhere. "Editing the anchor's timestamp by one
// digit replaces the whole timestamp with the digit": the coordinate field
// commits a transaction on every keystroke and then assigns the canonical
// spelling back into its own controller while focused -- Don opened Notepad to
// avoid typing in it, and the journal shows six edits for one timestamp. The
// rules:
//
//   ONE field chrome: every text-entry class draws a visible boundary at rest.
//   A field owns its text while focused: it commits on Enter or blur, once.

import 'package:chronolog/cards/coordinate_field.dart';
import 'package:chronolog/chrome/controls.dart';
import 'package:chronolog/core/coordinate_law.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../cards/harness.dart';
import '../cards/object_harness.dart';

Map<String, Object?> at(int day, int hour) => {
  'levels': [
    {'level': 'year', 'value': '2026'},
    {'level': 'month', 'value': '9'},
    {'level': 'day', 'value': '$day'},
    {'level': 'hour', 'value': '$hour'},
    {'level': 'minute', 'value': '0'},
  ],
};

void main() {
  testWidgets('the one-math expression field draws a visible boundary', (tester) async {
    await pumpCard(
      tester,
      cardChrome(null),
      ExpressionField(label: 'Members weigh', source: 'w * 1.5', onChanged: (_) {}),
    );
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(
      field.decoration?.border,
      isNot(equals(InputBorder.none)),
      reason:
          'ISSUES 9.2: `ExpressionField` builds its TextField with `InputBorder.none` and no '
          'fill -- an invisible box on six surfaces. One field decoration for every entry class.',
    );
  });

  testWidgets('a coordinate field commits once, on Enter -- never per keystroke', (tester) async {
    var writes = 0;
    await pumpCard(
      tester,
      cardChrome(null),
      CoordinateField(
        law: lawsUnderTest().first,
        value: Coordinate.fromJson(at(2, 9)),
        onChanged: (_, _) => writes += 1,
      ),
    );
    final finder = find.byType(TextField).first;
    final before = tester.widget<TextField>(finder).controller!.text;
    final last = before.lastIndexOf(RegExp(r'\d'));
    expect(last, greaterThanOrEqualTo(0), reason: 'the field shows a coordinate with digits');
    final digit = (int.parse(before[last]) + 1) % 10;
    final typed = '${before.substring(0, last)}$digit${before.substring(last + 1)}';
    await tester.tap(finder);
    await tester.pump();
    await tester.enterText(finder, typed);
    await tester.pump();
    expect(
      writes,
      equals(0),
      reason:
          'ISSUES 9.2: the field wrote a transaction while the hand was still typing (one '
          'journal entry and one undo step per keystroke). Commit on Enter or blur.',
    );
    expect(
      tester.widget<TextField>(finder).controller!.text,
      equals(typed),
      reason: 'ISSUES 9.2: nothing may rewrite a focused field\'s text underneath the hand',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(writes, equals(1), reason: 'Enter commits exactly once');
  });
}
