// A TALL BLOCK WRAPS ITS TITLE (ISSUES 9.2, Don).
//
// "Where an event has a lot of vertical space it should wrap text rather than
// cut it off." The one shared label painter laid out `maxLines: 1` with an
// ellipsis unconditionally, and Intimate handed it a one-line box whatever the
// block's height. The rule:
//
//   The caller passes the real box; the painter lays out as many lines as fit
//   with the ellipsis on the last line only. And the shared painter lives with
//   the other shared marks, not in one painter's file.
//
// Asked of `paintLabel` through a recording canvas: a `ui.Paragraph` carries no
// text back, but it carries its line metrics and its size, which is exactly the
// claim -- how many lines were laid, and that none of them left the box.
// Generative over seeded titles and seeded box heights.

import 'dart:math';
import 'dart:ui' as ui;

import 'package:chronolog/lens/lens_painter.dart';
import 'package:chronolog/lens/theme.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/corpus.dart';

/// Every paragraph drawn, with where it was put.
class Paragraphs implements Canvas {
  final List<({ui.Paragraph paragraph, Offset at})> drawn = [];

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) =>
      drawn.add((paragraph: paragraph, at: offset));

  @override
  void noSuchMethod(Invocation invocation) {}
}

const List<String> _words = [
  'quarterly', 'review', 'with', 'the', 'whole', 'platform', 'team', 'about', 'grading',
  'rubrics', 'and', 'what', 'Reggie', 'promised', 'by', 'Friday',
];

String title(Random random) => [
  for (var index = 0; index < 2 + random.nextInt(14); index += 1) _words[random.nextInt(_words.length)],
].join(' ');

void main() {
  test('the painted line count is min(lines that fit, lines the text needs), inside the box', () {
    final theme = shipped['paper']!;
    for (final seed in seeds(6)) {
      final random = Random(seed);
      final text = title(random);
      const size = 12.0;
      final box = Rect.fromLTWH(10, 10, 90 + random.nextDouble() * 120, 8 + random.nextDouble() * 140);
      final style = theme.ui.copyWith(color: theme.ink, fontSize: size);
      final probe = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)
        ..layout(maxWidth: box.width);
      final lineHeight = probe.preferredLineHeight;
      final needs = probe.computeLineMetrics().length;
      final fits = max(1, (box.height / lineHeight).floor());
      final canvas = Paragraphs();
      paintLabel(canvas, theme, text, box, theme.ink, size);
      expect(canvas.drawn, hasLength(1), reason: 'one label is one paragraph');
      final (paragraph: paragraph, at: at) = canvas.drawn.single;
      expect(
        paragraph.computeLineMetrics().length,
        equals(min(fits, needs)),
        reason:
            'ISSUES 9.2 (seed $seed): "$text" in a ${box.height.toStringAsFixed(0)}px box that holds '
            '$fits line(s) and needs $needs was laid out as ${paragraph.computeLineMetrics().length}. '
            'As many lines as fit, the ellipsis on the last alone.',
      );
      expect(at.dy, greaterThanOrEqualTo(box.top - 1e-6), reason: 'no glyph above the block');
      expect(at.dx, greaterThanOrEqualTo(box.left - 1e-6), reason: 'no glyph left of the block');
      expect(
        at.dy + paragraph.height,
        lessThanOrEqualTo(box.bottom + lineHeight * 0.5),
        reason: 'no whole line lands outside the block',
      );
      expect(paragraph.width, lessThanOrEqualTo(box.width + 0.01), reason: 'and none past its right edge');
    }
  });
}
