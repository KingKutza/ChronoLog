// EVERY SEGMENT OF A ZONE IS THE ZONE (ISSUES 9.2, two reports).
//
// "Double-click on the body of a spanning zone event in Intimate does nothing;
// I have to click the head on the first day." And: "if I can't see the start I
// have no way to know what it is." One early `return` -- written to skip the
// title on continuation days -- sat before the hit registration. The rule:
//
//   For every painted segment of a multi-day fact, a hit test inside that
//   segment finds the fact, and the segment names itself (the title is sticky
//   on every visible segment).
//
// The sticky title is asked through a recording canvas: a `ui.Paragraph`
// carries no text back, but on a scene with ONE object every paragraph drawn
// inside a block's rect is that object's title -- the rail's clock readings and
// the column headings lie outside every block. So the claim is by position:
// every visible segment's rect holds a paragraph origin.
//
// Generative: a random span of days and a random start hour.

import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:chronolog/core/exact.dart';
import 'package:chronolog/lens/painters/intimate.dart';
import 'package:chronolog/lens/theme.dart';
import 'package:chronolog/lens/zones.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/corpus.dart';
import '../helpers/projection_scene.dart';
import 'painters/grid_scene.dart';

final int runSeed =
    int.tryParse(Platform.environment['CHRONOLOG_SEED'] ?? '') ??
    DateTime.now().microsecondsSinceEpoch;

const String frameId = 'calendar:a';

Map<String, Object?> at(int day, int hour) => civil(2026, 9, day, hour, 0);

/// Where every paragraph was put. Nothing else is recorded: the claim is about
/// where text landed, not what it was.
class Paragraphs implements Canvas {
  final List<Offset> origins = [];
  final List<Offset> _stack = [Offset.zero];

  Offset get _shift => _stack.last;

  @override
  void save() => _stack.add(_shift);

  @override
  void restore() {
    if (_stack.length > 1) _stack.removeLast();
  }

  @override
  void translate(double dx, double dy) => _stack[_stack.length - 1] = _shift + Offset(dx, dy);

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) => origins.add(offset + _shift);

  @override
  void noSuchMethod(Invocation invocation) {}
}

/// Every paint laid down, IN ORDER, with whether it filled. Order is the claim:
/// a ground paints beneath everything, a figure above.
class Paints implements Canvas {
  final List<({Color color, bool fill})> laid = [];

  void _note(Paint paint) => laid.add((color: paint.color, fill: paint.style == PaintingStyle.fill));

  @override
  void drawRect(Rect rect, Paint paint) => _note(paint);

  @override
  void drawRRect(RRect rrect, Paint paint) => _note(paint);

  @override
  void drawPath(Path path, Paint paint) => _note(paint);

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) => _note(paint);

  @override
  void noSuchMethod(Invocation invocation) {}
}

/// The same hue, whatever its alpha.
bool sameHue(Color a, Color b) => hexOf(a) == hexOf(b);

({IntimatePainter painter, String id, Size size}) zoneScene(Random random) {
  final scene = Scene()..calendar(frameId);
  final spanDays = 3 + random.nextInt(3), startHour = 6 + random.nextInt(6);
  final id = scene.object(title: 'Conference', duration: '${spanDays * 24 * 60}');
  scene.document = scene.document.put(
    'events',
    id,
    scene.document.events[id]!.withField('display', const {'zone': true}),
  );
  scene.place(frameId, at(2, startHour), event: id);
  const size = Size(1400, 900);
  // Focus on the middle of the span, so the start day is a column to the left.
  final middle = civilDays(2026, 9, 3) + Rational.fromInt(1, 2);
  final lens = sceneOf(scene.document, const [frameId], size: size, focus: middle, now: middle);
  final painter = IntimatePainter(lens);
  render(painter, size);
  return (painter: painter, id: id, size: size);
}

void main() {
  // ignore: avoid_print
  print('ZONE SEGMENTS RUN SEED: $runSeed  (set CHRONOLOG_SEED=$runSeed to reproduce)');
  final random = Random(runSeed);

  test('a hit inside any day of a spanning zone finds the zone', () {
    final (painter: painter, id: id, size: size) = zoneScene(random);
    final middle = painter.scene.focusDays;
    final columns = painter
        .projectAll(middle)
        .where((point) => point.dx >= 0 && point.dx < size.width)
        .toList();
    expect(columns, isNotEmpty, reason: 'the middle of the span is on screen');
    for (final column in columns) {
      final probe = column + const Offset(24, 6);
      final hit = painter.markAt(probe);
      expect(
        hit?.fact.event.id,
        equals(id),
        reason:
            'ISSUES 9.2: the continuation segment at $probe registered no hit -- the title guard '
            'returned before `hits.add`. Every segment of a fact is the fact.',
      );
    }
  });

  test('every visible segment of a band names itself', () {
    // "The title is STICKY -- every segment of a band carries the title, drawn at
    // the top of the segment's VISIBLE portion ... what is on screen is named on
    // screen." The scene holds one object, so a paragraph inside a segment's
    // rect is its title.
    final (painter: painter, id: id, size: size) = zoneScene(random);
    final canvas = Paragraphs();
    painter.paint(canvas, size);
    final visible = [
      for (final hit in painter.hits)
        if (hit.fact.event.id == id)
          if (hit.bounds.right > 0 && hit.bounds.left < size.width) hit.bounds,
    ];
    expect(visible.length, greaterThan(1), reason: 'the band spans more than one visible column');
    for (final segment in visible) {
      final named = canvas.origins.any((origin) => segment.inflate(1).contains(origin));
      expect(
        named,
        isTrue,
        reason:
            'ISSUES 9.2: the segment at $segment carries no title -- `zoneTitled` names the START '
            'segment alone, so a band whose head is off-screen is an anonymous wash.',
      );
    }
  });

  group('FILL IS GROUND, A MARK IS FIGURE (Don, ruled)', () {
    // Don: "the Code Freeze event is now covering the Labor Day event ... the
    // Code Freeze is set to fill, so it should be automatically treated as
    // background." The band fill was `Color.lerp(paper, colour, zone.fill)` -- a
    // lerp of two opaque colours is OPAQUE, so a zone erased whatever it covered.
    // The law: an object whose authored handling says fill is a GROUND and paints
    // beneath everything; a mark is FIGURE and paints above. Draw order is
    // derived from the authored handling -- never a layer field, a z-number or a
    // lens knob. The wash carries REAL ALPHA, so two grounds over one span read
    // as two. NOTHING DISAPPEARS SILENTLY.
    test('a ground washes in its own hue with real alpha, and a figure over it is drawn after', () {
      const groundHue = '#aa5500', figureHue = '#112233';
      final scene = Scene()..calendar(frameId);
      final ground = scene.object(title: 'Code Freeze', duration: '${3 * 24 * 60}');
      scene.document = scene.document.put(
        'events',
        ground,
        scene.document.events[ground]!
            .withField('display', const {'zone': true})
            .withField('color', groundHue),
      );
      scene.place(frameId, at(2, 0), event: ground);
      final figure = scene.object(title: 'Labor Day', duration: '60');
      scene.document = scene.document.put(
        'events',
        figure,
        scene.document.events[figure]!.withField('color', figureHue),
      );
      scene.place(frameId, at(3, 10), event: figure);
      const size = Size(1400, 900);
      final middle = civilDays(2026, 9, 3) + Rational.fromInt(1, 2);
      final painter = IntimatePainter(
        sceneOf(scene.document, const [frameId], size: size, focus: middle, now: middle),
      );
      render(painter, size);
      expect(
        painter.hits.map((hit) => hit.fact.event.id),
        contains(figure),
        reason: 'NOTHING DISAPPEARS SILENTLY: the figure under the ground is still a mark',
      );
      final canvas = Paints();
      painter.paint(canvas, size);
      final groundAt = canvas.laid.indexWhere(
        (paint) => paint.fill && sameHue(paint.color, parseColor(groundHue)!),
      );
      expect(
        groundAt,
        greaterThanOrEqualTo(0),
        reason:
            'Don: the wash is the OBJECT\'S OWN hue at some alpha. A lerp against paper is a third '
            'colour nobody authored, and it is opaque.',
      );
      expect(
        canvas.laid[groundAt].color.a,
        lessThan(1),
        reason: 'the ground\'s wash carries real alpha, so what is under it shows through',
      );
      final figureAt = canvas.laid.indexWhere((paint) => sameHue(paint.color, parseColor(figureHue)!));
      expect(figureAt, greaterThanOrEqualTo(0), reason: 'the figure is painted at all');
      expect(
        figureAt,
        greaterThan(groundAt),
        reason: 'FILL IS GROUND, A MARK IS FIGURE: the ground paints first, the figure above it',
      );
    });

    test('two grounds over one span both read: with honest alpha they stack', () {
      // "For the case Don has not hit: two grounds over one span. With honest
      // alpha they stack and read as two; opaque, the lower one vanishes."
      final hues = ['#aa5500', '#0055aa'];
      final scene = Scene()..calendar(frameId);
      for (final (index, hue) in hues.indexed) {
        final ground = scene.object(title: 'Ground $index', duration: '${3 * 24 * 60}');
        scene.document = scene.document.put(
          'events',
          ground,
          scene.document.events[ground]!
              .withField('display', const {'zone': true})
              .withField('color', hue),
        );
        scene.place(frameId, at(2 + index, 6), event: ground);
      }
      const size = Size(1400, 900);
      final middle = civilDays(2026, 9, 3) + Rational.fromInt(1, 2);
      final painter = IntimatePainter(
        sceneOf(scene.document, const [frameId], size: size, focus: middle, now: middle),
      );
      render(painter, size);
      final canvas = Paints();
      painter.paint(canvas, size);
      for (final hue in hues) {
        final washes = canvas.laid.where(
          (paint) => paint.fill && sameHue(paint.color, parseColor(hue)!),
        );
        expect(washes, isNotEmpty, reason: 'the ground in $hue is washed in its own hue');
        expect(
          washes.every((paint) => paint.color.a < 1),
          isTrue,
          reason: 'and every wash of it is translucent, so the other ground reads through it',
        );
      }
    });

    test('the band fill is the authored hue at the setting\'s alpha, never a lerp against paper', () {
      // The one derivation every zone wash goes through, asked directly: for any
      // authored colour, the fill keeps the hue and takes its alpha from
      // `zone.fill` -- a setting, and less than one.
      final random = Random(specSeed);
      final theme = shipped['paper']!;
      for (var index = 0; index < 20; index += 1) {
        final authored = Color(0xff000000 | random.nextInt(1 << 24));
        final fill = zoneBand(
          const Rect.fromLTWH(0, 0, 10, 10),
          authored,
          zoneWhole,
          theme,
          allTunables,
        ).fill.color;
        expect(hexOf(fill), equals(hexOf(authored)), reason: 'the wash keeps the authored hue');
        expect(fill.a, lessThan(1), reason: 'and is translucent');
        expect(
          fill.a,
          closeTo(allTunables('zone.fill').toDouble(), 1e-6),
          reason: 'at the alpha the setting says',
        );
      }
    });
  });
}
