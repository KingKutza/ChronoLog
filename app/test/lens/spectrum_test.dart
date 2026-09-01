// THE TO-DO LINE, NOT A WASH (ISSUES 9.1, Don's ruling on todo zones).
//
// "The todo spectrum — today a calculated FILL: the month grid washes every cell
// between now and the todo's stapled day, one wash per unresolved todo, so a
// dozen todos is a dozen overlapping tints and a hundred is mud. Ruled instead:
// a SIGIL at the stapled point and a dotted line to another sigil, the line
// running forward or back UNTIL NOW."
//
// The claims are geometric and are read off the DRAW CALLS the painter makes,
// so nothing here inspects pixels and nothing re-implements the painter: a
// recording canvas answers what was drawn and where. Generative over seeded
// distances on both sides of now, because "which side of now the line leaves the
// sigil on IS overdue-or-upcoming" is the whole reading.

import 'dart:math';
import 'dart:ui';

import 'package:chronolog/lens/painters/tactical.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/corpus.dart';
import '../helpers/projection_scene.dart';
import 'painters/grid_scene.dart';

const String frameId = 'calendar:a';

/// Every stroke and every glyph the painter drew, with nothing interpreted. A
/// class with its own `noSuchMethod` forwards the rest of the canvas away.
class Strokes implements Canvas {
  final List<({Offset from, Offset to})> lines = [];
  final List<Rect> glyphs = [];

  @override
  void drawLine(Offset from, Offset to, Paint paint) => lines.add((from: from, to: to));

  @override
  void drawPath(Path path, Paint paint) => glyphs.add(path.getBounds());

  @override
  void noSuchMethod(Invocation invocation) {}
}

/// Is [point] on the segment [from]-[to], within a pixel?
bool onSegment(Offset from, Offset to, Offset point) {
  final run = to - from;
  final length = run.distance;
  if (length <= 0) return (point - from).distance <= 1;
  final along = ((point - from).dx * run.dx + (point - from).dy * run.dy) / (length * length);
  if (along < -0.01 || along > 1.01) return false;
  return (point - (from + run * along)).distance <= 1;
}

/// One unresolved to-do, [days] from now, on a Tactical sheet centred on now.
({Strokes drawn, Offset from, Offset to}) drawnFor(int days) {
  final world = Scene()..calendar(frameId);
  final todo = world.object(title: 'Chase it', duration: '0');
  world.document = world.document.put(
    'events',
    todo,
    world.document.events[todo]!.copyWith(traits: const ['event', 'task', 'todo']),
  );
  world.place(frameId, civil(2026, 9, 15 + days, 9), event: todo);
  final now = civilDays(2026, 9, 15);
  final scene = sceneOf(world.document, const [frameId], focus: now, now: now);
  final painter = TacticalPainter(scene);
  // Painted once for the geometry it lays out, then again onto the recorder, so
  // the cells the claim names are the cells the strokes were drawn into.
  render(painter, scene.size);
  final from = painter.cellOf(civilDays(2026, 9, 15 + days).floor())?.center;
  final to = painter.cellOf(now.floor())?.center;
  final drawn = Strokes();
  painter.paint(drawn, scene.size);
  return (drawn: drawn, from: from!, to: to!);
}

void main() {
  for (final seed in seeds(5)) {
    final random = Random(seed);
    // Both sides of now: an overdue to-do and an upcoming one are the same
    // drawing, and the direction it leaves the sigil in is the only difference.
    final near = 1 + random.nextInt(2);
    final far = near + 3 + random.nextInt(4);

    test('a to-do draws a dotted line to now, not a wash over the days between (seed $seed)', () {
      for (final days in [near, -near, far, -far]) {
        final drawn = drawnFor(days);
        final dots = [
          for (final line in drawn.drawn.lines)
            if (onSegment(drawn.from, drawn.to, line.from) &&
                onSegment(drawn.from, drawn.to, line.to))
              line,
        ];
        expect(
          dots.length,
          greaterThan(1),
          reason:
              'ISSUES (9.1, ruled): a to-do $days day(s) from now owes a DOTTED LINE '
              'from its stapled point to now, and the surface drew ${dots.length} '
              'segment(s) along it.',
        );
        final drawnLength = dots.fold<double>(0, (sum, dot) => sum + (dot.to - dot.from).distance);
        expect(
          drawnLength,
          lessThan((drawn.to - drawn.from).distance),
          reason: 'dotted, not solid: the ink is less than the run it covers',
        );
        // A sigil at each end, in the one mark vocabulary.
        for (final end in [drawn.from, drawn.to]) {
          expect(
            drawn.drawn.glyphs.any((box) => (box.center - end).distance <= 1),
            isTrue,
            reason: 'ISSUES (9.1): a sigil stands at $end, at both ends of the line',
          );
        }
      }
    });

    test('the line runs UNTIL NOW: a farther to-do draws a longer one (seed $seed)', () {
      double reach(int days) {
        final drawn = drawnFor(days);
        return [
          for (final line in drawn.drawn.lines)
            if (onSegment(drawn.from, drawn.to, line.from) &&
                onSegment(drawn.from, drawn.to, line.to))
              (line.to - line.from).distance,
        ].fold<double>(0, (sum, length) => sum + length);
      }

      expect(
        reach(far),
        greaterThan(reach(near)),
        reason:
            'ISSUES (9.1): the line runs forward or back UNTIL NOW, so $far days out '
            'is a longer run of dots than $near.',
      );
    });
  }
}
