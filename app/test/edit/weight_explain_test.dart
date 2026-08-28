// The weight explainer's spec: the answer to "no clarity into how or what the
// display weight is". It shows every ring, and the arithmetic has to add up
// exactly, or the card would be explaining a weight nothing was drawn at.

import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/projection.dart';
import 'package:chronolog/core/weight.dart';
import 'package:chronolog/edit/editor.dart';
import 'package:test/test.dart';

import '../helpers/projection_scene.dart';
import 'harness.dart';

const String calendarId = 'calendar:work';

void main() {
  late Bench bench;
  late Editor editor;

  tearDown(() async => closeEditor(bench));

  Future<Fact> place({Object? own}) async {
    final scene = Scene()..calendar(calendarId);
    final objectId = scene.object(title: 'Standup');
    if (own != null) {
      scene.document = scene.document.put(
        'events',
        objectId,
        scene.document.events[objectId]!.withField('display', {'weight': own}),
      );
    }
    scene.place(calendarId, civil(2026, 8, 3), event: objectId);
    scene.group('frame:important', [objectId], weight: 'w * 3');
    bench = await openEditor(scene.document, label: 'weight');
    editor = bench.editor;
    return editor.engine
        .queryFacts(
          Projection.of([calendarId, 'frame:important']),
          start: civil(2026, 7, 1),
          end: civil(2026, 9, 1),
        )
        .facts
        .firstWhere((fact) => fact.event.id == objectId);
  }

  test('every ring is shown, in fold order, and the arithmetic chains exactly', () async {
    final fact = await place(own: '2');
    final projection = Projection.of([calendarId, 'frame:important']);
    final explained = editor.explainWeight(fact, projection);
    expect(explained.rows, isNotEmpty);
    var carried = explained.base;
    for (final row in explained.rows) {
      expect(row.from, carried, reason: 'ring ${row.id} starts where the last one ended');
      carried = row.to;
    }
    expect(carried, explained.weight, reason: 'the last ring IS the final weight');
    expect(
      explained.weight,
      editor.engine.weightOf(fact, projection).weight,
      reason: 'the explainer explains what was drawn, never a second derivation',
    );
  });

  test('the rings are named, never left as bare record ids', () async {
    final fact = await place(own: '2');
    final explained = editor.explainWeight(fact, Projection.of([calendarId, 'frame:important']));
    final own = explained.rows.first;
    expect(own.id, ownWeightRing);
    expect(own.title, 'Standup', reason: 'the object answers with its own title');
    expect(own.formula, 'w * (2)', reason: 'a plain number is sugar for multiply');
    final group = explained.rows.firstWhere((row) => row.id == 'frame:important');
    expect(group.title, 'frame:important');
    expect(group.formula, 'w * 3');
  });

  test('falloff is the projector\'s closing step, and only when a now is given', () async {
    final fact = await place();
    final projection = Projection.of([calendarId, 'frame:important']);
    expect(
      editor.explainWeight(fact, projection).rows.map((row) => row.id),
      isNot(contains(falloffWeightRing)),
    );
    final faded = editor.explainWeight(fact, projection, at: fact.day + Rational.fromInt(400));
    expect(faded.rows.last.id, falloffWeightRing, reason: 'it closes the chain');
    expect(faded.rows.last.title, 'Apparent magnitude');
    expect(faded.weight < editor.explainWeight(fact, projection).weight, isTrue);
  });

  test('a NOT term gates visibility and never modifies weight', () async {
    final fact = await place();
    final plain = editor.explainWeight(fact, Projection.of([calendarId]));
    final negated = editor.explainWeight(
      fact,
      Projection.parse('a or not b', bindings: {'a': calendarId, 'b': 'frame:important'}),
    );
    expect(
      plain.rows.map((row) => row.id),
      contains('frame:important'),
      reason: 'the frame modifies the object however it is projected',
    );
    expect(
      negated.rows.map((row) => row.id),
      isNot(contains('frame:important')),
      reason: 'a purely negative term stays out of the chain',
    );
    // The chain is exactly the rings shown, so the withheld ring is the whole
    // difference: a NOT gates, it does not scale.
    expect(negated.weight, negated.rows.last.to);
    expect(negated.weight, isNot(plain.weight));
  });
}
