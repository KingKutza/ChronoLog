// The frame card and its law editor, as the field reports pose them.

import 'package:chronolog/cards/frame_card.dart';
import 'package:chronolog/cards/law_editor.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/edit/cascades.dart';
import 'package:flutter_test/flutter_test.dart';

import 'object_harness.dart';
import 'harness.dart';

const String _batman = 'Mon, Tue, Batman, Thu, Fri, Sat, Sun';

void main() {
  testWidgets('a new frame states the basis gap and writes nothing until Save', (tester) async {
    final bench = await openCards(createEmptyWorkspaceDocument());
    final before = bench.editor.document.frames.length;
    await pumpCard(tester, cardChrome(bench.editor), const FrameCard(kind: 'calendar'));

    expect(find.textContaining('No basis yet'), findsOneWidget);
    expect(find.textContaining('projects nothing'), findsNothing);
    await tester.enterText(fieldHinted('What this frame is called'), 'work');
    await tester.pump();
    expect(bench.editor.document.frames.length, before, reason: 'nothing is written before Save');

    await tapText(tester, 'Save');
    expect(bench.editor.document.frames.length, before + 1);
    final made = bench.editor.document.frames.values.last;
    expect(made.title, 'work');
    expect(made.basis, isNull, reason: 'a basis is offered, never wired silently');
    expect(bench.editor.canUndo, isTrue);
  });

  testWidgets('the basis choice offers the standard frame by name', (tester) async {
    final bench = await openCards(createEmptyWorkspaceDocument());
    await pumpCard(tester, cardChrome(bench.editor), const FrameCard(kind: 'calendar'));
    await tapText(tester, 'None chosen');
    expect(find.text('Wall time'), findsOneWidget);
    await tapText(tester, 'Wall time');
    expect(find.textContaining('No basis yet'), findsNothing);
  });

  testWidgets('seven names for a seven-long cycle are accepted; six are refused by name', (
    tester,
  ) async {
    final bench = await openCards(createEmptyWorkspaceDocument());
    Json? built;
    await pumpCard(
      tester,
      cardChrome(bench.editor),
      LawEditor(
        law: bench.editor.engine.lawOf('frame:wall-time'),
        own: null,
        onChanged: (declaration) => built = declaration,
      ),
    );
    await tapText(tester, 'Own structure');
    await tester.enterText(fieldHinted('names, one per unit'), _batman);
    await tester.pumpAndSettle();

    expect(find.textContaining('needs 7 names'), findsNothing);
    final cycles = (built?['cycles'] as List?)?.first as Map?;
    expect(cycles?['names'], contains('Batman'));

    // The same list against a six-long cycle is refused, and the refusal names
    // the cycle rather than a neighbouring count.
    await tester.enterText(fieldHolding('7'), '6');
    await tester.pumpAndSettle();
    expect(find.textContaining('weekday'), findsWidgets);
    expect(find.textContaining('needs 6 names'), findsOneWidget);
  });

  testWidgets('a 23-hour day on the basis frame is a 23-hour day on what derives from it', (
    tester,
  ) async {
    const derived = 'frame:derived';
    final document = createEmptyWorkspaceDocument().put(
      'frames',
      derived,
      const Frame(
        id: derived,
        title: 'Personal',
        traits: ['set', 'calendar'],
        extra: {'basis': 'frame:wall-time'},
      ),
    );
    final bench = await openCards(document);
    expect(bench.editor.engine.lawOf(derived).unitsPer('hour'), Rational.fromInt(24));

    await pumpCard(
      tester,
      cardChrome(bench.editor),
      const FrameCard(frameId: 'frame:wall-time', kind: 'line'),
    );
    await tapPart(tester, 'Structure, handling and boundaries');
    await tester.enterText(fieldHolding('24'), '23');
    await tester.pumpAndSettle();
    await tapText(tester, 'Save');

    expect(bench.editor.engine.lawOf(derived).unitsPer('hour'), Rational.fromInt(23));
  });

  test('a duplicate names itself everywhere the original was named', () {
    const source = 'frame:source';
    var document = createEmptyWorkspaceDocument().put(
      'frames',
      source,
      const Frame(id: source, title: 'Source', traits: ['set', 'calendar']),
    );
    document = document.put(
      'relations',
      'relation:1',
      const Relation(id: 'relation:1', type: 'placement', extra: {'frame': source, 'event': 'e'}),
    );
    final next = duplicateFrame(document, source);
    final copy = next.frames.keys.firstWhere(
      (id) => id != source && !document.frames.containsKey(id),
    );

    expect(next.frames[source], document.frames[source], reason: 'the original is untouched');
    expect(next.relations.length, 2);
    final made = next.relations.values.firstWhere((relation) => relation.id != 'relation:1');
    expect(made.frame, copy);
    expect(next.relations['relation:1']!.frame, source);
  });

  test('an identity weight is stored as an absence', () {
    const frame = Frame(id: 'f', extra: {'display': 1});
    expect(writeField(frame, 'display', null).extra.containsKey('display'), isFalse);
    expect(writeField(frame, 'display', 2).extra['display'], 2);
  });
}
