// THE REPEAT ROW HAS ITS MATH BOX, AND NO "SUGAR" (ISSUES 9.2, Don).
//
// "The tooltip says we have to author complex patterns in one math but does not
// provide a link to or box for typing it. Also it says 'A pattern this sugar
// cannot say', which is very awkward." The note pointed at ROADMAP #5, never
// built. Under fix-to-target-design the box comes now: the one-math entry as
// the row's third input mode, reading and writing the SAME rule as the choices.

import 'package:chronolog/cards/staple_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  testWidgets('the repeat row offers a one-math box and never says "sugar"', (tester) async {
    await pumpCard(
      tester,
      cardChrome(null),
      RepeatSugar(rrule: const {'FREQ': 'WEEKLY'}, onChanged: (_) {}, lawOf: (_) => null),
    );
    expect(
      find.textContaining('sugar'),
      findsNothing,
      reason: 'ISSUES 9.2: "sugar" is our word, not a person\'s -- it never faces the hand',
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            (widget.decoration?.hintText ?? '').toLowerCase().contains('rule'),
      ),
      findsOneWidget,
      reason:
          'ISSUES 9.2: "For a pattern these choices can\'t express ... write the rule here:" '
          'followed by the box. The box is the third input mode; it round-trips the same rule.',
    );
  });
}
