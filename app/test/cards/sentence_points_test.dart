// THE + ROW SAYS THE WHOLE SENTENCE, POINTS INCLUDED (ISSUES 9.2, the horde).
//
// "I have just stapled a horde of todos to a meeting and I see no sigils, no
// items, no zones, no nothing." Every one of the thirteen staples had
// `point: all` on BOTH ends, because the + row writes `defaultPoint` (the whole)
// on each end and offers no point terms -- so the only sentence it can say
// between two objects is "connected to". Don's rulings: staple is our word
// ("anchor" leaves the shipped list); the point vocabulary is never narrowed by
// the extent's current size and includes the whole; object->object defaults to
// point<->point from two settings keys (`start`/`start`; Don's `start`/`end`
// a setting away).
//
// "Whole to whole says THIS IS CONNECTED TO THAT. Points: this point IS that
// point. Whole to point: THIS IS AT THAT POINT." Three shapes, three readings,
// no verb involved -- the ends say it all. So the + row shows every term from
// the first keystroke, its two point terms wearing the settings' defaults, and
// what it WRITES is what it showed.

import 'package:chronolog/cards/object_card.dart';
import 'package:chronolog/cards/sentence_rows.dart';
import 'package:chronolog/cards/staple_editor.dart';
import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/core/staples.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/projection_scene.dart';
import 'object_harness.dart';

void main() {
  test('the point vocabulary offers the whole, and is not a written list', () {
    expect(
      extentPoints,
      contains(wholePoint),
      reason:
          'ISSUES 9.2: `extentPoints` is `[start, end, midpoint]` -- a closed list in a card '
          'that omits the ruled default point (the whole). Points are read from the object.',
    );
  });

  test('the shipped verb reads "stapled", never "anchor"', () {
    expect(
      stapleKinds.values.any((kind) => kind.label.toLowerCase().contains('stapled')),
      isTrue,
      reason:
          'ISSUES 9.2 (Don: "Staple is our chosen word"): the shipped default verb reads '
          '"is stapled to"; "Anchors a point" is the code\'s word leaking into the hand.',
    );
  });

  test('the default points of a new object-to-object sentence are settings', () {
    final settings = chronologSettings();
    expect(settings.text('edit.newPointNear'), isNotEmpty, reason: 'ISSUES 9.2: the new object\'s point is a settings key');
    expect(settings.text('edit.newPointFar'), isNotEmpty, reason: 'ISSUES 9.2: the far object\'s point is a settings key');
  });

  testWidgets('the + row says the whole sentence from the first keystroke, and writes the points '
      'it showed', (tester) async {
    // "The + row should offer the whole sentence at once -- 'the [start] of this
    // [is] the [end] of [that]' -- every term visible and editable from the first
    // keystroke, and typing a name in the far slot enough to write it." The
    // default points come from the two settings keys; the written ends carry
    // exactly those points.
    final scene = Scene()..calendar('calendar:a');
    final host = scene.object(title: 'Chase the rubric', duration: '0');
    scene.place('calendar:a', civil(2026, 9, 3, 9), event: host);
    const farTitle = 'AI Team meeting with Reggie';
    final far = scene.object(title: farTitle, duration: '60');
    scene.place('calendar:a', civil(2026, 9, 3, 14), event: far);
    final bench = (await tester.runAsync(() => openCards(scene.document)))!;
    final near = bench.settings.text('edit.newPointNear');
    final farPoint = bench.settings.text('edit.newPointFar');
    expect(near, isNotEmpty, reason: 'the near default point is a settings key, so the row has a word to show');
    expect(farPoint, isNotEmpty, reason: 'and the far one');
    await pumpHosted(
      tester,
      bench,
      ObjectCard(
        request: (klass: 'object', id: host, kind: null, frameId: null, startDays: null, endDays: null),
      ),
      id: host,
      shell: true,
    );
    final row = find.byType(NewSentence);
    expect(row, findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.textContaining(near)),
      findsWidgets,
      reason:
          'ISSUES 9.2: the + row shows "This [verb] [far end]" and no point term; the point of '
          'THIS object ($near, from the settings) is a term from the first keystroke.',
    );
    final before = bench.editor.document.relations.keys.toSet();
    // The FAR term's field, by the hint it wears -- once the row shows every
    // term from the first keystroke, the first field may be the near point.
    final field = find.descendant(
      of: row,
      matching: find.byWidgetPredicate(
        (widget) => widget is TextField && (widget.decoration?.hintText ?? '').contains('frame or an object'),
      ),
    );
    expect(field, findsWidgets, reason: 'the far term is a field a name is typed into');
    await tester.enterText(field.first, 'Reggie');
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: row, matching: find.textContaining(farTitle)).first);
    await tester.pumpAndSettle();
    final written = bench.editor.document.relations.values
        .where((relation) => !before.contains(relation.id))
        .toList();
    expect(written, hasLength(1), reason: 'saying the far end writes one sentence');
    final ends = written.single.ends.whereType<ObjectEnd>().toList();
    expect(ends, hasLength(2), reason: 'object to object');
    final nearEnd = ends.firstWhere((end) => end.object == host);
    final farEnd = ends.firstWhere((end) => end.object == far);
    expect(
      endPoint(nearEnd),
      equals(near),
      reason:
          'ISSUES 9.2: the + row wrote the WHOLE on this end ("${endPoint(nearEnd)}"), so the todo '
          'had no position and drew nowhere. The near point is the settings\' default.',
    );
    expect(endPoint(farEnd), equals(farPoint), reason: 'and the far point is the settings\' other default');
  });
}
