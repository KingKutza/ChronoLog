// THE DERIVATION IS THE ONE TRUTH (Don, ruled 2026-09-01).
//
// "Stop writing templateRelation: new patterns omit it; old records load
// byte-identical and are simply not believed."
//
// A pattern already names its template EVENT, and an event's placement is
// derivable from the event -- so storing the placement's relation id a second
// time was what made "minted without it" a reachable silent state at all
// (ISSUES 9.1, the starved series). The field is retired from the WRITE side
// only: every record that carries one still loads, still saves back exactly as
// it arrived, and is simply not consulted.
//
// Generative by ruling: the shapes quantify over seeded intervals and days, and
// nothing here counts occurrences.

import 'dart:math';

import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/ics.dart';
import 'package:chronolog/core/projection.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/core/staples.dart';
import 'package:chronolog/core/validate.dart';
import 'package:test/test.dart';

import '../helpers/projection_scene.dart';
import 'corpus.dart';

String icsWith(int day, int interval) =>
    'BEGIN:VCALENDAR\r\n'
    'VERSION:2.0\r\n'
    'PRODID:-//spec//EN\r\n'
    'BEGIN:VEVENT\r\n'
    'UID:standing-1\r\n'
    'DTSTART:202609${day.toString().padLeft(2, '0')}T090000Z\r\n'
    'DTEND:202609${day.toString().padLeft(2, '0')}T094500Z\r\n'
    'SUMMARY:Standing\r\n'
    'RRULE:FREQ=DAILY;INTERVAL=$interval\r\n'
    'END:VEVENT\r\n'
    'END:VCALENDAR\r\n';

void main() {
  for (final seed in seeds(5)) {
    final random = Random(seed);
    final day = 2 + random.nextInt(20);
    final interval = 1 + random.nextInt(3);

    test('an imported series stores no templateRelation and still projects (seed $seed)', () {
      final result = importIcs(
        icsWith(day, interval),
        createEmptyWorkspaceDocument(now: DateTime.utc(2026, 8, 27)),
        label: 'Spec',
      );
      final pattern = result.document.patterns[result.patterns.single]!;
      expect(
        pattern.extra.containsKey('templateRelation'),
        isFalse,
        reason:
            'ISSUES (9.1, ruled): the placement is derived from the template '
            'event, and storing it twice is what made a starved pattern '
            'authorable in the first place.',
      );
      final staples = Staples(result.document);
      expect(
        staples.templatePlacement(pattern)?.event,
        pattern.templateEvent,
        reason: 'the derivation finds it, which is the whole point of not storing it',
      );

      final engine = ProjectionEngine(result.document);
      final frame = str(pattern.extra['frame'])!;
      final start = Rational(daysFromCivil(BigInt.from(2026), 9, day));
      final projected = engine.queryFacts(
        Projection.of([frame]),
        start: start,
        end: start + Rational.fromInt(30),
      );
      expect(projected.facts.length, greaterThan(1));
      expect(projected.errors, isEmpty);
      expect(validateDocument(result.document).errors, isEmpty);
    });

    test('a record that carries one still loads and is not believed (seed $seed)', () {
      // The old spelling, and a stored id that points at another object's
      // placement: it loads, it round-trips, and the derivation overrules it.
      final scene = Scene()..calendar('calendar:a');
      final template = scene.object(title: 'Standing', duration: '45');
      scene.place('calendar:a', civil(2026, 9, day, 9), event: template);
      final other = scene.object(title: 'Someone else');
      final wrong = scene.place('calendar:a', civil(2026, 9, day, 14), event: other);
      final id = scene.mint('pattern');
      scene.document = scene.document.put(
        'patterns',
        id,
        Pattern(
          id: id,
          language: 'chronolog-ics/1',
          extra: {
            'kind': 'ics-rrule',
            'templateEvent': template,
            'templateRelation': wrong,
            'frame': 'calendar:a',
            'appliesTo': const ['calendar:a'],
            'rrule': {'FREQ': 'DAILY', 'INTERVAL': '$interval'},
          },
        ),
      );
      final before = scene.document.toJson();

      final staples = Staples(scene.document);
      expect(
        staples.templatePlacement(scene.document.patterns[id]!)?.event,
        template,
        reason: 'ruled: old records load and are simply not believed',
      );
      expect(scene.document.toJson(), before, reason: 'byte for byte, nothing rewritten');
    });
  }
}
