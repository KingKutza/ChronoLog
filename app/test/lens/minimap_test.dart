// The minimap's field and its label ladder.
//
// The properties here are the ones that make the field readable rather than
// decorative: labels on real boundaries, a scale that does not reshuffle when
// you pan, and a range that holds still while the focus is inside its band.

import 'dart:math';

import 'package:chronolog/core/coordinate_law.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/projection.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/lens/law_context.dart';
import 'package:chronolog/lens/minimap/field.dart';
import 'package:chronolog/lens/minimap/labels.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/corpus.dart';
import '../helpers/projection_scene.dart';

final LawContext gregorian = LawContext(gregorianLaw);
final Rational august = Rational(daysFromCivil(BigInt.from(2026), 8, 18));

CoordinateLaw lawFrom(Json declaration) =>
    CoordinateLaw.parse(declaration, frameId: 'frame:invented');

void main() {
  group('sliding range', () {
    test('a focus inside the band leaves the range alone; outside it re-anchors', () {
      final span = Rational.fromInt(14);
      final first = slideRange(null, august, span, null);
      expect(first.end - first.start, span * Rational.fromInt(5));
      final nudged = slideRange(first, august + Rational.one, span, null);
      expect(nudged, first);
      final far = slideRange(first, first.end + Rational.fromInt(20), span, null);
      expect(far, isNot(first));
      expect(far.end - far.start, first.end - first.start);
    });

    test('the focus is always inside the range it produced', () {
      final random = Random(specSeed);
      MinimapRange? range;
      var focus = august;
      for (var step = 0; step < 200; step += 1) {
        focus += Rational.fromInt(random.nextInt(21) - 10);
        range = slideRange(range, focus, Rational.fromInt(9), null);
        expect(focus >= range.start && focus <= range.end, isTrue);
      }
    });
  });

  group('the scale ladder', () {
    test('the ceiling is a rung, is at least the busy end, and holds between rungs', () {
      final ladder = magnitudeLadder(null);
      expect(ladder, ladder.toList()..sort());
      for (final busy in [1.0, 2.4, 5.0, 9.0, 30.0, 200.0]) {
        final ceiling = ceilingFor(List.filled(8, busy), null);
        expect(ladder, contains(ceiling));
        expect(ceiling, greaterThanOrEqualTo(busy));
      }
      expect(ceilingFor(List.filled(8, 9), null), ceilingFor(List.filled(8, 11), null));
      expect(ceilingFor(List.filled(8, 0), null), ladder.first);
    });

    test('one exceptional bin does not flatten the field', () {
      final quiet = List.filled(100, 2.0)..[0] = 10000;
      expect(ceilingFor(quiet, null), lessThan(10000));
    });

    test('equal activity reads identically wherever it sits', () {
      final left = List.filled(288, 0.0)..[12] = 4;
      final right = List.filled(288, 0.0)..[240] = 4;
      final ceiling = ceilingFor(left, null);
      expect(ceiling, ceilingFor(right, null));
      expect(
        MinimapField(left, List.filled(288, 1), ceiling, (
          start: Rational.zero,
          end: Rational.one,
        )).level(12),
        MinimapField(right, List.filled(288, 1), ceiling, (
          start: Rational.zero,
          end: Rational.one,
        )).level(240),
      );
    });
  });

  group('accumulation', () {
    test('a span counts everywhere it is present without inflating the total', () {
      final world = Scene();
      world.calendar('calendar:a');
      final long = world.object(title: 'Long', duration: '10', unit: 'day');
      world.place('calendar:a', civil(2026, 8, 1), event: long);
      final engine = ProjectionEngine(world.document);
      final projection = Projection.of(['calendar:a']);
      final range = (start: august - Rational.fromInt(30), end: august + Rational.fromInt(30));
      final field = accumulate(engine, projection, range, null);
      final total = field.magnitudes.fold(0.0, (sum, value) => sum + value);
      final one = magnitudeOf(engine, projection, engine.explicitFacts('calendar:a').first);
      expect(total, closeTo(one, one / 1000));
      expect(field.counts.where((value) => value > 0).length, greaterThan(1));
    });

    test('a bin holding objects never reads as empty', () {
      final world = Scene();
      world.calendar('calendar:a');
      world.place('calendar:a', civil(2026, 8, 18), event: world.object(duration: '1'));
      final engine = ProjectionEngine(world.document);
      final field = accumulate(engine, Projection.of(['calendar:a']), (
        start: august - Rational.fromInt(30),
        end: august + Rational.fromInt(30),
      ), null);
      for (var bin = 0; bin < field.bins; bin += 1) {
        if (field.counts[bin] > 0) expect(field.heightAt(bin), greaterThan(0));
      }
    });
  });

  group('the label ladder', () {
    test('every tick lands on a real boundary, in order, inside the range', () {
      for (final (level, span) in [('hour', 50), ('day', 175), ('month', 456), ('quarter', 2740)]) {
        final end = august + Rational.fromInt(span);
        final ticks = labelTicks(august, end, level, gregorian);
        expect(ticks.length, greaterThanOrEqualTo(2), reason: level);
        Rational? previous;
        for (final tick in ticks) {
          expect(tick.days >= august && tick.days <= end, isTrue);
          if (previous != null) expect(tick.days > previous, isTrue);
          previous = tick.days;
          if (tick.format == 'day' || tick.format == 'month' || tick.format == 'quarter') {
            expect(tick.days.floor(), tick.days.ceil(), reason: 'not a whole day: ${tick.text}');
          }
          if (tick.format == 'month' || tick.format == 'quarter') {
            expect(civilFromDays(tick.days.floor()).day, 1, reason: tick.text);
          }
          if (tick.format == 'quarter') {
            expect((civilFromDays(tick.days.floor()).month - 1) % 3, 0, reason: tick.text);
          }
        }
      }
    });

    test('a degenerate range produces nothing rather than a division', () {
      expect(labelTicks(august, august, 'day', gregorian), isEmpty);
      expect(labelTicks(august, august - Rational.one, 'day', gregorian), isEmpty);
    });

    test('Intimate granularity never shows a year, at any span', () {
      final year = RegExp(r"\d{4}|'\d\d");
      for (final span in [2, 5, 12, 50, 90]) {
        final ticks = labelTicks(
          august,
          august + Rational.fromInt(span),
          granularityFor('intimate'),
          gregorian,
        );
        expect(ticks.length, greaterThan(1));
        for (final tick in ticks) {
          expect(tick.format, anyOf('hour', 'day'));
          expect(year.hasMatch(tick.text), isFalse, reason: tick.text);
        }
      }
    });

    test('every declared granularity is one the ladder knows', () {
      for (final level in labelGranularity.values) {
        expect(labelLadders.containsKey(level), isTrue, reason: level);
      }
      expect(granularityFor('a lens nobody registered'), 'day');
    });

    test('a law with no months places no month label rather than guessing one', () {
      final tamriel = LawContext(lawFrom(inventedLaw));
      expect(tamriel.hasMonths, isFalse);
      final from = Rational.zero, to = Rational.fromInt(3000);
      expect(labelTicks(from, to, 'month', tamriel), isEmpty);
      expect(labelTicks(from, to, 'quarter', tamriel), isEmpty);
      final days = labelTicks(from, Rational.fromInt(1000), 'day', tamriel);
      for (final tick in days) {
        expect(tick.format, isNot('month'));
      }
      expect(
        labelTicks(from, Rational.fromInt(1000), 'day', gregorian).any((t) => t.format == 'month'),
        isTrue,
      );
    });

    test('a label the law cannot place is omitted, never invented', () {
      final ticks = labelTicks(august, august + Rational.fromInt(90), 'day', gregorian);
      for (final tick in ticks) {
        expect(tick.text, isNotEmpty);
      }
      expect(labelText(august, 'day', gregorian), matches(RegExp(r'^\w{3} \d+$')));
      expect(labelText(august, 'month', gregorian), matches(RegExp(r"^\w{3} '\d\d$")));
      expect(labelText(august, 'quarter', gregorian), matches(RegExp(r'^Q[1-4]-\d\d$')));
      expect(
        labelText(august + Rational.fromInt(1, 2), 'hour', gregorian),
        matches(RegExp(r'^\w{3} \d+ \d\d:\d\d$')),
      );
    });

    test('a per-format budget is never exceeded', () {
      for (final (level, span) in [('hour', 50), ('day', 175), ('month', 456), ('quarter', 2740)]) {
        final ticks = labelTicks(august, august + Rational.fromInt(span), level, gregorian);
        final budget = ticks.isEmpty ? 0 : 18;
        expect(ticks.length, lessThanOrEqualTo(budget));
      }
    });
  });
}
