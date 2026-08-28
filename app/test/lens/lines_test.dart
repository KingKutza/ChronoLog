// Lines: the weave, the fan, and what the lens refuses to invent.

import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/projection.dart';
import 'package:chronolog/lens/lines/plan.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/projection_scene.dart';

void main() {
  group('progress', () {
    test('a day maps to its fraction of the window; a zero span refuses', () {
      final zero = Rational.zero, twenty = Rational.fromInt(20);
      expect(lineProgress(Rational.fromInt(10), zero, twenty), 1 / 2);
      expect(lineProgress(Rational.fromInt(15), zero, twenty), 3 / 4);
      expect(
        lineProgress(Rational.fromInt(10), Rational.fromInt(10), Rational.fromInt(10)),
        isNull,
      );
      expect(lineProgress(zero, twenty, zero), isNull);
    });
  });

  group('the apex ladder', () {
    test('companions alternate sides and never share an apex', () {
      final seen = <double>{};
      for (var index = 0; index < 9; index += 1) {
        final apex = apexOffset(index, first: 75, step: 52);
        expect(seen.add(apex), isTrue, reason: 'apex repeated at $index');
        if (index > 0) expect(apex.sign, index.isOdd ? -1 : 1);
      }
      expect(apexOffset(0, first: 75, step: 52), 0);
    });

    test('a weave leaves and rejoins its staple points exactly', () {
      expect(weaveAt(0, 100, 60), closeTo(100, 1e-9));
      expect(weaveAt(1, 100, 60), closeTo(100, 1e-9));
      expect(weaveAt(1 / 2, 100, 60), closeTo(160, 1e-9));
    });
  });

  group('the cluster fan', () {
    test('coincident points fan symmetrically in stable id order', () {
      final fanned = fanPoints([
        (id: 'z', eventId: 'event:z', x: 0.5, line: 0),
        (id: 'a', eventId: 'event:a', x: 0.5, line: 0),
        (id: 'near', eventId: 'event:near', x: 0.504, line: 0),
      ], pixelSpan: 995);
      expect(fanned.map((point) => point.id), ['a', 'near', 'z']);
      expect(fanned.map((point) => point.offset), [-8.0, 0.0, 8.0]);
      expect(fanned.every((point) => point.cluster == 3), isTrue);
    });

    test('a lone point does not move, and a crowd never runs off its line', () {
      final alone = fanPoints([(id: 'a', eventId: 'e', x: 0.5, line: 0)], pixelSpan: 995);
      expect(alone.single.offset, 0);
      final crowd = fanPoints([
        for (var index = 0; index < 40; index += 1)
          (id: 'p$index', eventId: 'e$index', x: 0.5, line: 0),
      ], pixelSpan: 995);
      expect(crowd.length, 40);
      for (final point in crowd) {
        expect(point.offset.abs(), lessThanOrEqualTo(18));
      }
    });

    test('far-apart points are their own clusters', () {
      final spread = fanPoints([
        (id: 'a', eventId: 'e1', x: 0.1, line: 0),
        (id: 'b', eventId: 'e2', x: 0.9, line: 0),
      ], pixelSpan: 995);
      expect(spread.every((point) => point.cluster == 1 && point.offset == 0), isTrue);
    });
  });

  group('the frame plan', () {
    test('a frame with no axis is refused by name, never drawn as a flat line', () {
      final world = Scene();
      world.calendar('calendar:a');
      world.frame('frame:state-done', const ['set', 'group', 'state']);
      final engine = ProjectionEngine(world.document);
      final plan = framePlan(engine, Projection.of(['calendar:a', 'frame:state-done']));
      expect(plan.supported, isTrue);
      expect(plan.lines.map((line) => line.frame), ['calendar:a']);
      expect(plan.lines.single.prime, isTrue);
      expect(plan.refused.single.frame, 'frame:state-done');
      expect(plan.refused.single.message, contains('coordinate axis'));
    });

    test('a projection naming nothing is unsupported rather than empty', () {
      final world = Scene();
      final engine = ProjectionEngine(world.document);
      expect(framePlan(engine, Projection.of(const [])).supported, isFalse);
    });
  });

  group('authored topology', () {
    test('two frames are adjacent only where somebody authored the incidence', () {
      final world = Scene();
      world.calendar('calendar:a');
      world.calendar('calendar:b');
      world.calendar('calendar:lonely');
      final shared = world.object(title: 'Shared');
      world.place('calendar:a', civil(2026, 8, 10), event: shared);
      world.place('calendar:b', civil(2026, 8, 10), event: shared);
      final engine = ProjectionEngine(world.document);
      final frames = topologyFrames(engine, 'calendar:a');
      expect(frames.first, 'calendar:a');
      expect(frames, contains('calendar:b'));
      expect(frames, isNot(contains('calendar:lonely')));
    });

    test('a shared object is the staple mark that pins two lines together', () {
      final world = Scene();
      world.calendar('calendar:a');
      world.calendar('calendar:b');
      final shared = world.object(title: 'Shared');
      world.place('calendar:a', civil(2026, 8, 10), event: shared);
      world.place('calendar:b', civil(2026, 8, 10), event: shared);
      world.place('calendar:a', civil(2026, 8, 12), title: 'Alone');
      final engine = ProjectionEngine(world.document);
      final projection = Projection.of(['calendar:a', 'calendar:b']);
      final plan = framePlan(engine, projection);
      final start = Rational(daysFromCivil(BigInt.from(2026), 8, 1));
      final result = engine.queryFacts(
        projection,
        start: start,
        end: start + Rational.fromInt(30),
        limit: 100,
      );
      final marks = sharedMarks(
        engine,
        result.facts,
        plan.lines,
        start,
        start + Rational.fromInt(30),
      );
      expect(marks.length, 1);
      expect(marks.single.eventId, shared);
      expect(marks.single.frames, ['calendar:a', 'calendar:b']);
      expect(marks.single.progress.toSet().length, 1);
    });
  });
}
