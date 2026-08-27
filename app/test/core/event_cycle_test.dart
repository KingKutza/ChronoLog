// Event-defined cycles: the finite authored series is the authority.
//
// The properties are the two halves of "no extrapolation": inside the window,
// stepping forward and back is the identity and every interval is the exact
// subtraction of two observations; at the edges, every question refuses. Both are
// checked over random series with random irregular gaps, because a regular one
// could not tell an authored interval from a mean.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/eras.dart';
import 'package:chronolog/core/event_cycle.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/core/validate.dart';
import 'package:test/test.dart';

import 'corpus.dart';

/// A series of [count] boundaries whose gaps are random exact rationals -- never
/// equal, so no mean can stand in for any one of them.
({Json period, List<Rational> at}) _series(Random random, int count) {
  final at = <Rational>[Rational(BigInt.from(random.nextInt(20)))];
  for (var index = 1; index < count; index++) {
    // A gap with a real denominator: an observation is not a whole number of
    // days, and rounding one would be inventing it.
    at.add(
      at.last +
          Rational(BigInt.from(1 + random.nextInt(4000)), BigInt.from(1 + random.nextInt(97))),
    );
  }
  return (
    period: {
      'kind': 'event-defined',
      'frame': 'measure:earth-days',
      'boundaries': [
        for (final (index, value) in at.indexed)
          {
            'id': 'boundary-$index',
            'at': value.toJson(),
            if (random.nextBool()) 'event': 'event:observed-$index',
          },
      ],
    },
    at: at,
  );
}

Json _fixturePeriod() {
  final json =
      jsonDecode(File('../fixtures/irregular-event-cycle.json').readAsStringSync()) as Json;
  return json['period'] as Json;
}

void main() {
  test('random series: an interval is the exact subtraction of two boundaries', () {
    for (final seed in seeds(60)) {
      final random = Random(seed);
      final count = 2 + random.nextInt(8);
      final (period: period, at: at) = _series(random, count);
      final series = eventBoundarySeries(period).resolved;
      expect(series, isNotNull, reason: 'seed $seed');
      expect(series!.frame, 'measure:earth-days');
      expect([for (final b in series.boundaries) b.at], at, reason: 'seed $seed');

      for (var index = 0; index < count - 1; index++) {
        // [start, end): the left boundary is IN its own interval.
        final resolved = resolveEventCycle(period, at[index]);
        final cycle = resolved.resolved;
        expect(cycle, isNotNull, reason: 'seed $seed index $index');
        expect(cycle!.index, index, reason: 'seed $seed');
        expect(cycle.start, at[index]);
        expect(cycle.end, at[index + 1]);
        expect(
          cycle.period,
          at[index + 1] - at[index],
          reason: 'seed $seed: the observed gap, never a mean',
        );
        // A point strictly inside resolves to the same interval.
        final inside = at[index] + cycle.period * Rational.fromInt(1, 3);
        expect(resolveEventCycle(period, inside).resolved!.index, index);
      }
    }
  });

  test('random series: forward then back is the identity, and the ends refuse', () {
    for (final seed in seeds(60)) {
      final random = Random(seed);
      final count = 2 + random.nextInt(8);
      final (period: period, at: at) = _series(random, count);
      final intervals = count - 1;
      for (var index = 0; index < intervals; index++) {
        final here = resolveEventCycle(period, at[index]).resolved!;
        for (final step in [1, 2, 3, -1, -2]) {
          final moved = stepCycle(here, step);
          final landed = index + step;
          if (landed < 0 || landed >= intervals) {
            // NO EXTRAPOLATION, in either direction.
            expect(moved.resolved, isNull, reason: 'seed $seed $index$step');
            expect(moved.refusal, contains('outside the authored'));
            continue;
          }
          expect(moved.resolved!.index, landed, reason: 'seed $seed');
          // There and back again.
          final back = stepCycle(moved.resolved!, -step);
          expect(back.resolved!.index, index, reason: 'seed $seed');
          expect(back.resolved!.start, here.start);
          expect(back.resolved!.period, here.period);
        }
        // A zero step is not a direction.
        expect(stepCycle(here, 0).refusal, contains('non-zero'));
      }
      // Before the first boundary and at or after the last: nothing is authored
      // there, so nothing is answered.
      expect(resolveEventCycle(period, at.first - Rational.one).resolved, isNull);
      expect(resolveEventCycle(period, at.last).resolved, isNull);
      expect(
        resolveEventCycle(period, at.last + Rational.one).refusal,
        contains('outside the authored boundary window'),
      );
    }
  });

  test('random series: a window is made only of authored adjacent intervals', () {
    for (final seed in seeds(40)) {
      final random = Random(seed);
      final count = 3 + random.nextInt(7);
      final (period: period, at: at) = _series(random, count);
      final intervals = count - 1;
      for (var index = 0; index < intervals; index++) {
        final past = random.nextInt(4);
        final future = random.nextInt(4);
        final window = eventCycleWindow(period, at[index], past: past, future: future);
        final first = index - past;
        final last = index + future + 1;
        if (first < 0 || last >= count) {
          expect(window.resolved, isNull, reason: 'seed $seed $index');
          expect(window.refusal, contains('exceeds authored boundaries'));
          continue;
        }
        final resolved = window.resolved!;
        expect(resolved.start, at[first], reason: 'seed $seed');
        expect(resolved.end, at[last], reason: 'seed $seed');
        expect(resolved.firstIndex, first);
        expect(resolved.lastIndex, last - 1);
      }
      // A negative request is a zero request, never a reversed window.
      final zero = eventCycleWindow(period, at[0], past: -5, future: 0);
      expect(zero.resolved!.start, at[0]);
      expect(zero.resolved!.end, at[1]);
    }
  });

  group('malformed series refuse, and say why', () {
    test('random mutilations each earn their own sentence', () {
      for (final seed in seeds(30)) {
        final random = Random(seed);
        final (period: period, at: _) = _series(random, 4);
        Json mutate(void Function(List<Json> rows) change) {
          final rows = [for (final row in period['boundaries'] as List) Json.from(row as Map)];
          change(rows);
          return {...period, 'boundaries': rows};
        }

        expect(
          eventBoundarySeries({...period, 'kind': 'declared'}).refusal,
          'not an event-defined period',
        );
        expect(
          eventBoundarySeries({...period, 'frame': ''}).refusal,
          contains('needs a boundary frame'),
        );
        expect(
          eventBoundarySeries(mutate((rows) => rows.removeRange(1, rows.length))).refusal,
          contains('at least two explicit boundaries'),
        );
        expect(
          eventBoundarySeries(mutate((rows) => rows[1]['id'] = '  ')).refusal,
          contains('boundary 2 needs an id'),
        );
        expect(
          eventBoundarySeries(mutate((rows) => rows[2]['id'] = rows[0]['id'])).refusal,
          contains('boundary ids must be unique'),
        );
        expect(
          eventBoundarySeries(mutate((rows) => rows[2]['at'] = rows[1]['at'])).refusal,
          contains('strictly ordered'),
        );
        expect(
          eventBoundarySeries(mutate((rows) => rows[2]['at'] = rows[0]['at'])).refusal,
          contains('strictly ordered'),
        );
        expect(
          eventBoundarySeries(mutate((rows) => rows[1]['at'] = 'the third tuesday')).refusal,
          contains('needs an exact finite coordinate'),
        );
        expect(
          eventBoundarySeries(mutate((rows) => rows[1].remove('at'))).refusal,
          contains('needs an exact finite coordinate'),
        );
        // A malformed series never resolves and never throws.
        expect(resolveEventCycle({...period, 'boundaries': const []}, '0').resolved, isNull);
        expect(resolveEventCycle(null, '0').resolved, isNull);
        expect(
          resolveEventCycle(period, 'not a coordinate').refusal,
          'focus must be an exact coordinate',
        );
      }
    });
  });

  group('ruled anchors', () {
    test('RULED ANCHOR: the observed lunar fixture, never averaged', () {
      final period = _fixturePeriod();
      final resolved = resolveEventCycle(period, '30').resolved!;
      expect(resolved.start.toDecimal(2), '29.31');
      expect(resolved.end.toDecimal(2), '58.92');
      expect(resolved.period.toDecimal(2), '29.61');
      // Not the mean synodic month, which is the whole point.
      expect(resolved.period.toDecimal(9), isNot('29.530588853'));
    });

    test('RULED ANCHOR: reverse traversal inside the window, refusal outside', () {
      final period = _fixturePeriod();
      final back = stepEventCycle(period, '60', -1).resolved!;
      expect(back.start.toDecimal(2), '29.31');
      expect(stepEventCycle(period, '1', -1).resolved, isNull);
      final window = eventCycleWindow(period, '60', past: 1, future: 1);
      expect(window.resolved!.start.toDecimal(2), '29.31');
      expect(window.resolved!.end.toDecimal(2), '117.87');
    });

    test('an exact Rational focus is accepted as itself', () {
      final period = _fixturePeriod();
      expect(
        resolveEventCycle(period, Rational.parse('30')).resolved!.index,
        resolveEventCycle(period, '30').resolved!.index,
      );
    });
  });

  // --- Refuse before store --------------------------------------------------
  //
  // A document whose boundaries only fail at query time is not a valid document,
  // and reporting it as one defers a certain failure to the worst possible
  // moment. The validator reads THE SAME parser the resolver reads, so the two
  // can never disagree about what a well-formed series is.
  group('the document validator', () {
    Document withPeriod(Json period, {bool events = true}) {
      var document = createEmptyWorkspaceDocument().put(
        'frames',
        'measure:earth-days',
        const Frame(id: 'measure:earth-days', traits: ['measure']),
      );
      document = document.put(
        'frames',
        'cycle:moon',
        Frame(id: 'cycle:moon', traits: const ['circle', 'cycle'], extra: {'period': period}),
      );
      if (!events) return document;
      for (final row in asList(period['boundaries'])) {
        final id = str(asMap(row)?['event']);
        if (id == null) continue;
        document = document.put(
          'events',
          id,
          Event(id: id, traits: const ['event'], magnitudes: {'duration': durationMagnitude()}),
        );
      }
      return document;
    }

    test('a well-formed event-defined period validates clean', () {
      for (final seed in seeds(30)) {
        final random = Random(seed);
        final (period: period, at: _) = _series(random, 2 + random.nextInt(6));
        final document = withPeriod(period);
        expect(validateDocument(document).errors, isEmpty, reason: 'seed $seed');
      }
      expect(validateDocument(withPeriod(_fixturePeriod())).errors, isEmpty);
    });

    test('RULED ANCHOR: unordered, duplicate, and inexact boundaries refuse', () {
      final period = _fixturePeriod();
      Json mutate(void Function(List<Json> rows) change) {
        final rows = [for (final row in period['boundaries'] as List) Json.from(row as Map)];
        change(rows);
        return {...period, 'boundaries': rows};
      }

      for (final (label, broken) in <(String, Json)>[
        ('strictly ordered', mutate((rows) => rows[1]['at'] = '0')),
        ('at least two', mutate((rows) => rows.removeRange(1, rows.length))),
        ('unique', mutate((rows) => rows[2]['id'] = rows[0]['id'])),
        ('exact finite', mutate((rows) => rows[1]['at'] = 'whenever')),
        ('needs an id', mutate((rows) => rows[1]['id'] = '')),
        ('boundary frame', {...period, 'frame': ''}),
      ]) {
        final result = validateDocument(withPeriod(broken));
        expect(result.errors, hasLength(1), reason: label);
        expect(result.errors.single, contains('Frame cycle:moon'), reason: label);
        expect(result.errors.single, contains(label), reason: label);
      }
    });

    test('a boundary frame or event that does not exist is refused', () {
      final period = _fixturePeriod();
      expect(validateDocument(withPeriod({...period, 'frame': 'measure:nowhere'})).errors, [
        'Frame cycle:moon references a missing boundary frame',
      ]);
      // Every boundary that names an event must be able to keep the claim.
      final orphaned = validateDocument(withPeriod(period, events: false));
      expect(orphaned.errors, hasLength((period['boundaries'] as List).length));
      expect(orphaned.errors.first, 'Frame cycle:moon references a missing boundary event');
    });

    test('a boundary that names no event makes no claim', () {
      final period = _fixturePeriod();
      final anonymous = {
        ...period,
        'boundaries': [
          for (final row in period['boundaries'] as List) Json.from(row as Map)..remove('event'),
        ],
      };
      expect(validateDocument(withPeriod(anonymous, events: false)).errors, isEmpty);
    });

    test('a period of another kind is not checked against this shape', () {
      // An open vocabulary: a period this build has never heard of is data, and
      // an event-defined check would be inventing a claim about it.
      for (final kind in ['declared', 'observed', 'ᚱᚢᚾᛖ-defined']) {
        expect(
          validateDocument(withPeriod({'kind': kind, 'boundaries': const []}, events: false))
              .errors,
          isEmpty,
          reason: kind,
        );
      }
    });
  });
}
