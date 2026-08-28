// The minimap paints, on a first-run document and on a law that has no now.
//
// The point of the second case is the ruling: a frame whose law does not map to
// a clock HAS NO NOW, and a surface must draw nothing there rather than invent
// one -- and it must not throw on the way to not drawing it.

import 'package:chronolog/core/coordinate_law.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/projection.dart';
import 'package:chronolog/lens/law_context.dart';
import 'package:chronolog/lens/minimap/field.dart';
import 'package:chronolog/lens/minimap/labels.dart';
import 'package:chronolog/lens/minimap/painter.dart';
import 'package:chronolog/lens/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/projection_scene.dart';

MinimapPainter painterOver(
  Document document,
  List<String> frames,
  CoordinateLaw law, {
  bool frozen = false,
}) {
  final engine = ProjectionEngine(document);
  final projection = Projection.of(frames);
  final focus = Rational(daysFromCivil(BigInt.from(2026), 8, 18));
  final range = slideRange(null, focus, Rational.fromInt(14), null);
  return MinimapPainter(
    field: accumulate(engine, projection, range, null),
    law: LawContext(law),
    theme: shipped['paper']!,
    focusDays: focus,
    spanDays: Rational.fromInt(14),
    nowDays: focus,
    granularity: granularityFor('intimate'),
    frozen: frozen,
  );
}

Future<void> pump(WidgetTester tester, MinimapPainter painter) => tester.pumpWidget(
  Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: SizedBox(width: 640, height: 120, child: CustomPaint(painter: painter)),
    ),
  ),
);

void main() {
  testWidgets('paints a first-run document without drawing a phantom frame', (tester) async {
    final document = createEmptyWorkspaceDocument(now: DateTime.utc(2026, 8, 27));
    final engine = ProjectionEngine(document);
    final frames = document.frames.keys.toList();
    await pump(tester, painterOver(document, frames, engine.lawOf(frames.first)));
    expect(tester.takeException(), isNull);
  });

  testWidgets('paints an ordinary document, and scrubs back to the day under the pointer', (
    tester,
  ) async {
    final world = Scene();
    world.calendar('calendar:a');
    for (var day = 10; day < 24; day += 1) {
      world.place('calendar:a', civil(2026, 8, day, day % 12), title: 'Day $day');
    }
    final engine = ProjectionEngine(world.document);
    final painter = painterOver(world.document, ['calendar:a'], engine.lawOf('calendar:a'));
    await pump(tester, painter);
    expect(tester.takeException(), isNull);

    final left = painter.unproject(Offset.zero);
    final right = painter.unproject(const Offset(640, 0));
    expect(left, painter.field.range.start);
    expect(right > left, isTrue);
    // The scrub and the projection are the same derivation read in two
    // directions, so they cannot disagree about where a day is.
    final middle = painter.unproject(const Offset(320, 0));
    expect(painter.project(middle)!, closeTo(320, 1));
  });

  testWidgets('a law with no clock mapping paints no now line and does not throw', (tester) async {
    final world = Scene();
    world.frame('frame:strokes', const ['set', 'calendar'], const {'coordinate': inventedLaw});
    world.place('frame:strokes', stroke(4, 2), title: 'A stroke');
    final engine = ProjectionEngine(world.document);
    final law = engine.lawOf('frame:strokes');
    expect(law.mapsToClock(), isFalse);
    final painter = painterOver(world.document, ['frame:strokes'], law);
    await pump(tester, painter);
    expect(tester.takeException(), isNull);
    expect(LawContext(law).mapsToClock, isFalse);
  });

  testWidgets('the field is frozen during a scrub and drifts at rest', (tester) async {
    final world = Scene();
    world.calendar('calendar:a');
    world.place('calendar:a', civil(2026, 8, 18, 9), title: 'One');
    final engine = ProjectionEngine(world.document);
    final law = engine.lawOf('calendar:a');
    final resting = painterOver(world.document, ['calendar:a'], law);
    final frozen = painterOver(world.document, ['calendar:a'], law, frozen: true);
    await pump(tester, resting);
    expect(tester.takeException(), isNull);
    await pump(tester, frozen);
    expect(tester.takeException(), isNull);
    expect(frozen.shouldRepaint(resting), isTrue);
    expect(frozen.shouldRepaint(frozen), isFalse);
  });
}
