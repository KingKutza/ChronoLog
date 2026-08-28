// Properties of the lens substrate, over seeded random worlds.
//
// Nothing here pins an arbitrary fact -- no count of lenses, no count of
// settings, no shipped pixel size. Every assertion is a property that has to
// hold for whatever the generators produce, which is what makes it survive a
// vocabulary that is open by ruling.

import 'dart:math';

import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/math.dart';
import 'package:chronolog/core/projection.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/lens/capacity.dart';
import 'package:chronolog/lens/color.dart';
import 'package:chronolog/lens/display_weight.dart';
import 'package:chronolog/lens/facts.dart';
import 'package:chronolog/lens/lanes.dart';
import 'package:chronolog/lens/law_context.dart';
import 'package:chronolog/lens/lens_painter.dart';
import 'package:chronolog/lens/marks.dart';
import 'package:chronolog/lens/theme.dart';
import 'package:chronolog/lens/tunables.dart';
import 'package:chronolog/lens/zones.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/corpus.dart';
import '../helpers/projection_scene.dart';

LensScene sceneOver(Scene world, List<String> frames, {Rational? focus, Rational? now}) {
  final engine = ProjectionEngine(world.document);
  final projection = Projection.of(frames);
  return LensScene(
    engine: engine,
    projection: projection,
    law: engine.lawOf(frames.first),
    focusDays: focus ?? Rational.zero,
    view: const {},
    theme: shipped['paper']!,
    nowDays: now ?? Rational.zero,
    size: const Size(800, 600),
  );
}

void main() {
  group('tunables', () {
    test('every shipped default is an expression the one math evaluates to a number', () {
      for (final entry in lensTunableDefaults.entries) {
        final value = evaluateSource(entry.value, const Env());
        expect(value, isA<Rational>(), reason: '${entry.key} = ${entry.value}');
      }
    });

    test('a session read wins over the shipped default, and an unknown key refuses', () {
      final overridden = tunable((key) => Rational.fromInt(99), 'lane.gap');
      expect(overridden, Rational.fromInt(99));
      expect(() => tunable(null, 'nothing.named.this'), throwsA(isA<MathRefusal>()));
    });
  });

  group('theme', () {
    test('every shipped preset round-trips through JSON unchanged', () {
      for (final preset in shipped.values) {
        expect(ChronoTheme.fromJson(preset.toJson()).toJson(), preset.toJson());
      }
    });

    test('the derived tones are one rule: hair is palest, faint is darkest', () {
      for (final theme in shipped.values) {
        double toPaper(Color tone) =>
            (tone.r - theme.paper.r).abs() +
            (tone.g - theme.paper.g).abs() +
            (tone.b - theme.paper.b).abs();
        expect(toPaper(theme.hair), lessThan(toPaper(theme.strong)));
        expect(toPaper(theme.strong), lessThan(toPaper(theme.faint)));
      }
    });

    test('an unreadable field falls back rather than refusing the whole theme', () {
      final theme = ChronoTheme.fromJson({'name': 'broken', 'ink': 'not a colour'});
      expect(theme.name, 'broken');
      expect(hexOf(theme.ink), paperPreset['ink']);
    });
  });

  group('lanes', () {
    test('two spans in one lane never overlap in time', () {
      final random = Random(specSeed);
      for (var iteration = 0; iteration < 40; iteration += 1) {
        final spans = [
          for (var index = 0; index < random.nextInt(30); index += 1)
            () {
              final start = Rational.fromInt(random.nextInt(200));
              return (start: start, end: start + Rational.fromInt(random.nextInt(20)));
            }(),
        ];
        final packing = packLanes(spans);
        for (var lane = 0; lane < packing.count; lane += 1) {
          final inLane = [
            for (final (index, span) in spans.indexed)
              if (packing.lanes[index] == lane) span,
          ]..sort((a, b) => a.start.compareTo(b.start));
          for (var index = 1; index < inLane.length; index += 1) {
            expect(
              inLane[index - 1].end <= inLane[index].start,
              isTrue,
              reason: 'lane $lane overlaps at $index',
            );
          }
        }
      }
    });

    test('lane count never exceeds the deepest simultaneous stack', () {
      final spans = [
        (start: Rational.zero, end: Rational.fromInt(10)),
        (start: Rational.fromInt(1), end: Rational.fromInt(2)),
        (start: Rational.fromInt(3), end: Rational.fromInt(4)),
      ];
      expect(packLanes(spans).count, 2);
    });
  });

  group('capacity', () {
    test('capacity never exceeds the area divided by the mark footprint', () {
      final random = Random(specSeed);
      for (var iteration = 0; iteration < 60; iteration += 1) {
        final width = random.nextDouble() * 2000, height = random.nextDouble() * 1500;
        final capacity = capacityOf(width, height, null);
        final fits =
            (width / pixels(null, 'capacity.markWidth')) *
            (height / pixels(null, 'capacity.markHeight')) *
            pixels(null, 'capacity.stackDepth');
        final floor = pixels(null, 'capacity.floor');
        expect(capacity.marks, lessThanOrEqualTo(max(fits, floor).ceil()));
        expect(capacity.queryBudget, greaterThanOrEqualTo(capacity.marks));
      }
    });

    test('what does not fit is a lower bound, never a silent drop', () {
      final ranked = List.generate(50, (index) => index);
      final admitted = admit(ranked, (marks: 12, queryBudget: 24));
      expect(admitted.drawn.length + admitted.hidden, ranked.length);
      expect(admitted.truncated, isTrue);
      expect(overflowLabel(admitted), endsWith('+'));
      expect(overflowLabel(admit(ranked, (marks: 80, queryBudget: 160))), isEmpty);
    });
  });

  group('marks', () {
    test('falloff is monotone and bucket three is the floor', () {
      int? bucketAt(String ratio) => falloffBucket(Rational.parse(ratio), null);
      final buckets = [
        for (final ratio in ['1', '0.8', '0.6', '0.4', '0.2', '0.01']) bucketAt(ratio) ?? 0,
      ];
      for (var index = 1; index < buckets.length; index += 1) {
        expect(buckets[index], greaterThanOrEqualTo(buckets[index - 1]));
      }
      expect(buckets.last, 3);
      expect(bucketAt('0.000001'), 3);
      expect(falloffBucket(null, null), isNull);
    });

    test('opacity falls with the bucket and never reaches nothing', () {
      var previous = 1.0;
      for (final bucket in [null, 1, 2, 3]) {
        final opacity = falloffOpacity(bucket, null);
        expect(opacity, lessThanOrEqualTo(previous));
        expect(opacity, greaterThan(0));
        previous = opacity;
      }
    });

    test('an authored sigil names one outright; nothing else reads a trait string', () {
      final task = Event(id: 'e', traits: const ['event', 'task']);
      String pick(Event event, {Object? authored, bool virtual = false, bool promoted = false}) =>
          sigilFor(
            authored: authored,
            event: event,
            virtual: virtual,
            succession: false,
            durationDays: Rational.zero,
            dayDays: Rational.one,
            promoted: promoted,
          );
      expect(pick(task), 'task');
      expect(pick(task, authored: 'celestial'), 'celestial');
      expect(pick(task, authored: 'not a sigil'), 'task');
      expect(pick(Event(id: 'n', traits: const ['event', 'note'])), 'note');
      expect(pick(Event(id: 'p', traits: const ['event'])), 'point');
      expect(pick(Event(id: 'p', traits: const ['event']), virtual: true), 'repeat');
      expect(pick(Event(id: 'p', traits: const ['event']), promoted: true), 'milestone');
    });

    test('a span is decided by the governing law, not by a fixed day', () {
      final event = Event(id: 'e', traits: const ['event']);
      String pick(String duration, String day) => sigilFor(
        event: event,
        virtual: false,
        succession: false,
        durationDays: Rational.parse(duration),
        dayDays: Rational.parse(day),
        promoted: false,
      );
      expect(pick('23/24', '1'), 'point');
      expect(pick('23/24', '23/24'), 'span');
    });

    test('every sigil has a glyph, a label, and a path inside its own bounds', () {
      const bounds = Rect.fromLTWH(10, 20, 8, 8);
      for (final sigil in sigilGlyphs.keys) {
        expect(sigilLabels[sigil], isNotNull);
        final path = sigilPath(sigil, bounds);
        expect(path.getBounds().isEmpty, isFalse, reason: sigil);
        expect(bounds.inflate(1 / 100).contains(path.getBounds().topLeft), isTrue, reason: sigil);
        expect(
          bounds.inflate(1 / 100).contains(path.getBounds().bottomRight),
          isTrue,
          reason: sigil,
        );
      }
    });

    test('state is a modifier, never a new glyph', () {
      final theme = shipped['paper']!;
      for (final state in ['open', 'done', 'closed', 'sparse']) {
        final spec = MarkSpec(sigil: 'task', state: state, color: theme.ink, theme: theme);
        expect(spec.glyph, sigilGlyphs['task']);
        expect(spec.strike, state == 'done' || state == 'closed');
        expect(spec.slashed, state == 'closed');
      }
    });
  });

  group('segmentation', () {
    test('a span covers its own extent exactly, with no gap and no overlap', () {
      final random = Random(specSeed);
      for (var iteration = 0; iteration < 25; iteration += 1) {
        final world = Scene();
        world.calendar('calendar:a', hoursPerDay: random.nextBool() ? null : 23);
        for (var index = 0; index < 6; index += 1) {
          world.place(
            'calendar:a',
            civil(2026, 8, 1 + random.nextInt(20), random.nextInt(12)),
            event: world.object(duration: '${1 + random.nextInt(4000)}'),
          );
        }
        final engine = ProjectionEngine(world.document);
        final law = LawContext(engine.lawOf('calendar:a'));
        final facts = engine.explicitFacts('calendar:a');
        final byDay = segmentByDay(engine, facts, law);
        for (final fact in facts) {
          final mine = [
            for (final segments in byDay.values)
              for (final segment in segments)
                if (segment.fact.identity == fact.identity) segment,
          ]..sort((a, b) => a.day.compareTo(b.day));
          expect(mine, isNotEmpty);
          var covered = Rational.zero;
          for (final (index, segment) in mine.indexed) {
            expect(segment.continuation, index > 0);
            expect(segment.continuesAfter, index < mine.length - 1);
            if (index > 0) expect(segment.day, mine[index - 1].day + BigInt.one);
            covered += segment.endMinute - segment.startMinute;
          }
          // The law's OWN minutes: a duration in standard days becomes minutes of
          // a 23-hour day by dividing by that day's length first.
          final duration = engine.eventDurationDays(fact.event) / law.dayDays * law.minutesPerDay;
          expect(covered, duration, reason: 'fact ${fact.identity}');
        }
      }
    });

    test('a window with nothing in it and nothing to say is never silent', () {
      final world = Scene();
      world.calendar('calendar:a');
      world.frame('measure:strokes', const ['set', 'measure'], const {'coordinate': inventedLaw});
      final scene = sceneOver(world, ['calendar:a', 'measure:strokes']);
      final window = queryWindow(
        scene,
        start: Rational.zero,
        end: Rational.fromInt(30),
        budget: 40,
      );
      expect(window.facts, isEmpty);
      expect(window.refusals, isNotEmpty);
      expect(window.silent, isFalse);
      expect(window.refusals.first.message, contains('correspondence'));
    });
  });

  group('color cascade', () {
    test('an object colour beats a group, a group beats a frame, nothing is neutral', () {
      final world = Scene();
      world.calendar('calendar:a');
      world.document = world.document.put(
        'frames',
        'calendar:a',
        world.document.frames['calendar:a']!.withField('color', '#111111'),
      );
      final plain = world.object(title: 'Plain');
      world.place('calendar:a', civil(2026, 8, 10), event: plain);
      final grouped = world.object(title: 'Grouped');
      world.place('calendar:a', civil(2026, 8, 11), event: grouped);
      world.group('group:g', [grouped], extra: const {'color': '#222222'});
      final own = world.object(title: 'Own');
      world.place('calendar:a', civil(2026, 8, 12), event: own);
      world.group('group:h', [own], extra: const {'color': '#333333'});
      world.document = world.document.put(
        'events',
        own,
        world.document.events[own]!.withField('display', const {'color': '#abcdef'}),
      );

      final scene = sceneOver(world, ['calendar:a']);
      final cascade = ColorCascade(scene.engine, scene.projection, scene.theme);
      Color colorOf(String id) => cascade.colorOf(
        scene.engine.explicitFacts('calendar:a').firstWhere((fact) => fact.event.id == id),
      );
      expect(hexOf(colorOf(plain)), '#111111');
      expect(hexOf(colorOf(grouped)), '#222222');
      expect(hexOf(colorOf(own)), '#abcdef');
    });

    test('nothing authored anywhere is neutral ink, never an inferred colour', () {
      final world = Scene();
      world.calendar('calendar:a');
      final celestial = world.object(title: 'New moon');
      world.document = world.document.put(
        'events',
        celestial,
        world.document.events[celestial]!.copyWith(traits: const ['event', 'celestial']),
      );
      world.place('calendar:a', civil(2026, 8, 10), event: celestial);
      final scene = sceneOver(world, ['calendar:a']);
      final cascade = ColorCascade(scene.engine, scene.projection, scene.theme);
      expect(cascade.colorOf(scene.engine.explicitFacts('calendar:a').first), scene.theme.neutral);
    });
  });

  group('display weight', () {
    test('a resolved object never fades, an unresolved one does', () {
      final world = Scene();
      world.calendar('calendar:a');
      final open = world.object(title: 'Open', duration: '0');
      final done = world.object(title: 'Done', duration: '0');
      for (final id in [open, done]) {
        world.document = world.document.put(
          'events',
          id,
          world.document.events[id]!.copyWith(traits: const ['event', 'task', 'todo']),
        );
        world.place('calendar:a', civil(2026, 1, 1), event: id);
      }
      world.frame('frame:state-done', const ['set', 'group', 'state']);
      world.join('frame:state-done', done);

      final scene = sceneOver(world, [
        'calendar:a',
      ], now: Rational(daysFromCivil(BigInt.from(2026), 12, 1)));
      final facts = {
        for (final fact in scene.engine.explicitFacts('calendar:a')) fact.event.id: fact,
      };
      final openWeight = factDisplayWeight(scene, facts[open]!);
      final doneWeight = factDisplayWeight(scene, facts[done]!);
      expect(openWeight.state, 'sparse');
      expect(doneWeight.state, 'done');
      expect(doneWeight.bucket, isNull);
      expect(openWeight.bucket, 3);
      expect(openWeight.weight < doneWeight.weight, isTrue);
    });

    test('promotion is a threshold read from settings, not a hardcoded pair', () {
      expect(promotionOf(Rational.one, null), standardWeight);
      expect(promotionOf(Rational.fromInt(2), null), importantWeight);
      expect(promotionOf(Rational.fromInt(4), null), landmarkWeight);
      expect(
        promotionOf(
          Rational.fromInt(3),
          (key) => Rational.fromInt(key.endsWith('landmarkAt') ? 3 : 1),
        ),
        landmarkWeight,
      );
    });
  });

  group('zones', () {
    test('the continuity grammar names each day of a band exactly once', () {
      Segment at({required bool continuation, required bool after}) => (
        fact: Fact(
          kind: 'explicit',
          event: Event(id: 'e'),
          relation: Relation(id: 'r', type: 'attachment'),
          day: Rational.zero,
          coordinate: const {},
        ),
        day: BigInt.zero,
        startMinute: Rational.zero,
        endMinute: Rational.zero,
        continuation: continuation,
        continuesAfter: after,
      );
      expect(zoneSegment(at(continuation: false, after: false)), zoneWhole);
      expect(zoneSegment(at(continuation: false, after: true)), zoneStart);
      expect(zoneSegment(at(continuation: true, after: true)), zoneMiddle);
      expect(zoneSegment(at(continuation: true, after: false)), zoneEnd);
      expect(zoneTitled(zoneStart) && zoneTitled(zoneWhole), isTrue);
      expect(zoneTitled(zoneMiddle) || zoneTitled(zoneEnd), isFalse);
    });

    test('zone fill is a group property, read off the frame, never a lens knob', () {
      final world = Scene();
      world.calendar('calendar:a');
      final id = world.object(duration: '2', unit: 'day');
      world.place('calendar:a', civil(2026, 8, 10), event: id);
      world.group(
        'group:banded',
        [id],
        extra: const {
          'display': {'zone': true},
        },
      );
      final engine = ProjectionEngine(world.document);
      final fact = engine.explicitFacts('calendar:a').first;
      expect(zoneFill(engine, fact, null), isTrue);
    });
  });
}
