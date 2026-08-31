// The one sigil vocabulary, with its PAINT folded in.
//
// The web build split this in two: a JavaScript module chose the sigil and sixty
// CSS selectors drew it, and the only test that checked they agreed grepped both
// files as text. Here the glyph path, the stroke, the dash, the cap and the
// opacity are the same object that names the sigil, so there is nothing for two
// sources to disagree about.
//
// SHAPE CARRIES STRUCTURAL ROLE, so a grayscale display loses nothing: color
// identifies an authored frame or group and is never the sole carrier of what a
// mark IS. A lens may omit a mark it cannot render at scale; it must never
// repurpose one to mean something else.
//
// ToDo STATE IS A MODIFIER AXIS over the task glyph, never a new glyph -- there
// is no done sigil, there is a task drawn done.
//
// SELECTION BY AUTHORING, never by sniffing. The sigil comes from the authored
// object kind, an authored staple, the presence of a pattern, the duration under
// the governing law, and the composed weight. An authored `display.sigil` names
// one outright. No substring of a title or a trait decides anything here.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../core/exact.dart';
import '../core/object_kinds.dart';
import '../core/projection.dart';
import '../core/records.dart';
import 'theme.dart';
import 'tunables.dart';

/// One painted mark, recorded during paint so identity, selection and the drag
/// source live in the same object the pointer hits.
///
/// TWO REGIONS, TWO QUESTIONS. [shape] is the mark's real geometry -- what a
/// click, a menu and the cursor mean -- and [grab] is the part of it a DRAG
/// takes hold of, which Intimate narrows to a leading strip so a create-drag
/// passes through an occupied span. A null grab is grabbed wherever it is hit.
typedef MarkHit = ({Rect bounds, Path? shape, Path? grab, Fact fact, String identity});

/// The vocabulary. `span` is last because it is the only one chosen by size
/// rather than by role.
const Map<String, String> sigilGlyphs = {
  'point': '●',
  'milestone': '◆',
  'repeat': '↻',
  'task': '○',
  'note': '□',
  'terminator': '⟐',
  'celestial': '✦',
  'span': '▬',
};

const Map<String, String> sigilLabels = {
  'point': 'Scheduled event',
  'milestone': 'Milestone',
  'repeat': 'Recurring occurrence',
  'task': 'Task or float',
  'note': 'Note',
  'terminator': 'Timeline terminator',
  'celestial': 'Celestial event',
  'span': 'Time span or zone',
};

/// The overflow sigil: a LOWER BOUND, drawn as its own mark rather than as a
/// truncated list. "48+" is what the field has to say when the budget ran out.
const String overflowSigil = 'overflow';

/// The sigil an object shows, derived from what its author actually wrote.
///
/// [authored] is `display.sigil` -- read through [authoredSigilOf], so a FRAME
/// may name it as well as an object -- which names one outright: the path by
/// which a celestial frame's phases, or a line's terminator, get their own glyph
/// without any predicate reading a trait string. Otherwise: a mark that covers a
/// whole day under THIS law is a span; a succession end is a terminator; the
/// object's authored kind gives task and note; a generated occurrence or a
/// pattern's template repeats; a promoted weight is a milestone; everything else
/// is a point.
String sigilFor({
  Object? authored,
  required Event? event,
  required bool virtual,
  required bool succession,
  required Rational durationDays,
  required Rational dayDays,
  required bool promoted,
}) {
  final named = '${authored ?? ''}'.trim();
  if (sigilGlyphs.containsKey(named)) return named;
  if (dayDays > Rational.zero && durationDays >= dayDays) return 'span';
  if (succession) return 'terminator';
  final kind = objectKindForEvent(event);
  if (kind == 'todo') return 'task';
  if (kind == 'note') return 'note';
  if (virtual) return 'repeat';
  if (promoted) return 'milestone';
  return 'point';
}

/// The object whose HANDLING a fact answers to: itself, or -- for a fact a
/// series generated -- the template it is an occurrence of.
///
/// AN OCCURRENCE IS ITS TEMPLATE APPEARING AGAIN (ruled 2026-08-31, with the day
/// object). A generated fact carries a stable virtual id that is in no document,
/// so asking the document about that id finds nothing authored and no frames
/// bearing on it: handling authored on a daily object -- draw as a zone, this
/// sigil, this half-distance -- would reach the template and none of the days it
/// makes. The template is the authored object, so the template is what is asked.
String handlingSubject(ProjectionEngine engine, Fact fact) {
  final pattern = fact.pattern;
  if (pattern == null) return fact.event.id;
  return engine.document.patterns[pattern]?.templateEvent ?? fact.event.id;
}

/// The sigil an author named for this fact: the object's own `display.sigil`,
/// then the frame the fact sits on, then the frames bearing on it nearest
/// first. A FRAME IS A GROUP, so naming a sigil is a group display property
/// like any other (ruled 2026-08-28) -- a celestial frame gives its objects the
/// celestial glyph, and nothing reads a trait string to get there.
Object? authoredSigilOf(ProjectionEngine engine, Fact fact) => engine.authoredHandling(
  handlingSubject(engine, fact),
  'sigil',
  nearest: fact.relation.frame,
);

String sigilLabel(String sigil, String state, String? title) {
  final name = sigilLabels[sigil] ?? sigilLabels['point']!;
  final suffix = state == 'open' ? '' : ', $state';
  return '$name$suffix: ${title == null || title.isEmpty ? 'untitled' : title}';
}

/// The falloff bucket an apparent-magnitude ratio lands in, or null for a mark
/// at full presence. BUCKET THREE IS THE FLOOR: a lapsed object fades to it and
/// no further, because it lapses from prominence, never from truth.
int? falloffBucket(Rational? ratio, Tunable? read) {
  if (ratio == null) return null;
  for (var bucket = 1; bucket <= 3; bucket += 1) {
    if (ratio > tunable(read, 'falloff.bucket$bucket')) return bucket == 1 ? null : bucket - 1;
  }
  return 3;
}

double falloffOpacity(int? bucket, Tunable? read) =>
    bucket == null ? 1 : pixels(read, 'falloff.opacity$bucket');

/// Everything needed to draw one mark, resolved once. A lens asks for the spec
/// and then draws; it never re-decides a stroke or an opacity of its own.
class MarkSpec {
  MarkSpec({
    required this.sigil,
    required this.state,
    required this.color,
    required this.theme,
    this.bucket,
    this.read,
  });

  final String sigil, state;
  final Color color;
  final ChronoTheme theme;
  final int? bucket;
  final Tunable? read;

  String get glyph => sigilGlyphs[sigil] ?? sigilGlyphs['point']!;

  /// Hollow shapes carry their meaning in the outline: a task ring and a note
  /// square must read as open at pip size, which a fill destroys.
  bool get filled => sigil != 'task' && sigil != 'note' && sigil != 'overflow';

  bool get strike => state == 'done' || state == 'closed';

  /// The closed slash: a state that is not Done still resolved the object, and
  /// the slash is what distinguishes it at a glance from a completion.
  bool get slashed => state == 'closed';

  double get strokeWidth =>
      pixels(read, sigil == 'terminator' ? 'mark.strokeStrong' : 'mark.stroke');

  double get opacity {
    final faded = falloffOpacity(bucket, read);
    if (state == 'done') return faded * pixels(read, 'mark.doneOpacity');
    if (state == 'sparse') return faded * pixels(read, 'mark.sparseOpacity');
    return faded;
  }

  /// The dash vocabulary, per sigil. A repeat is dashed because it recurs; a
  /// task is dotted with BUTT caps, because a round cap would render the dots
  /// circular and the vocabulary's are square; a terminator's long-short-short
  /// pattern reads as a stop.
  List<double> get dash => switch (sigil) {
    'repeat' => [pixels(read, 'mark.dashOn'), pixels(read, 'mark.dashOff')],
    'task' => [pixels(read, 'mark.dotOn'), pixels(read, 'mark.dotOff')],
    'terminator' => [
      pixels(read, 'mark.strokeStrong') * 2,
      pixels(read, 'mark.dashOff'),
      pixels(read, 'mark.dotOn'),
      pixels(read, 'mark.dashOff'),
    ],
    _ => const [],
  };

  StrokeCap get cap => sigil == 'task' ? StrokeCap.butt : StrokeCap.round;

  Paint fill() => Paint()
    ..color = color.withValues(alpha: opacity)
    ..style = PaintingStyle.fill;

  Paint stroke() => Paint()
    ..color = color.withValues(alpha: opacity)
    ..style = PaintingStyle.stroke
    ..strokeWidth = strokeWidth
    ..strokeCap = cap;

  /// The strike-through a resolved object carries, in ink rather than in the
  /// object's own color: a completion is not another authored meaning.
  Paint strikePaint() => Paint()
    ..color = theme.ink.withValues(alpha: opacity)
    ..style = PaintingStyle.stroke
    ..strokeWidth = strokeWidth;

  Path path(Rect bounds) => sigilPath(sigil, bounds);

  /// Draws the mark and hands back the hit record, so identity and geometry are
  /// produced by one call and cannot describe different pixels.
  MarkHit paint(Canvas canvas, Rect bounds, Fact fact) {
    final shape = path(bounds);
    if (filled) canvas.drawPath(shape, fill());
    canvas.drawPath(dash.isEmpty ? shape : _dashed(shape, dash), stroke());
    if (strike) {
      canvas.drawLine(
        Offset(bounds.left, bounds.center.dy),
        Offset(bounds.right, bounds.center.dy),
        strikePaint(),
      );
    }
    if (slashed) canvas.drawLine(bounds.bottomLeft, bounds.topRight, strikePaint());
    return (bounds: bounds, shape: shape, grab: null, fact: fact, identity: fact.identity);
  }
}

/// The glyph geometry, in a unit square scaled to [bounds]. Straight from the
/// stylesheet's own shapes: milestone is a square on its corner, terminator the
/// same diamond SPLIT so the two never collide in grayscale, celestial the
/// ten-pointed star with its authored vertices, span a bar.
Path sigilPath(String sigil, Rect bounds) {
  Offset at(double x, double y) =>
      Offset(bounds.left + bounds.width * x, bounds.top + bounds.height * y);
  Path polygon(List<double> points) {
    final path = Path()..moveTo(at(points[0], points[1]).dx, at(points[0], points[1]).dy);
    for (var index = 2; index < points.length; index += 2) {
      final point = at(points[index], points[index + 1]);
      path.lineTo(point.dx, point.dy);
    }
    return path..close();
  }

  final radius = Radius.circular(bounds.shortestSide / 4);
  switch (sigil) {
    case 'point':
    case 'task':
      return Path()..addOval(bounds);
    case 'milestone':
      return polygon([1 / 2, 0, 1, 1 / 2, 1 / 2, 1, 0, 1 / 2]);
    case 'terminator':
      // One diamond, cut down the middle: the two halves stand apart so a
      // terminator can never be misread as a milestone at pip size.
      return Path()
        ..addPath(polygon([1 / 2, 0, 0.42, 1 / 2, 1 / 2, 1, 0, 1 / 2]), Offset.zero)
        ..addPath(polygon([1 / 2, 0, 1, 1 / 2, 1 / 2, 1, 0.58, 1 / 2]), Offset.zero);
    case 'note':
      return Path()..addRRect(RRect.fromRectAndRadius(bounds, radius / 2));
    case 'repeat':
      return Path()..addRRect(RRect.fromRectAndRadius(bounds, radius / 2));
    case 'celestial':
      return polygon([
        ...[1 / 2, 0, 0.61, 0.35, 0.98, 0.35, 0.68, 0.57, 0.79, 0.94],
        ...[1 / 2, 0.72, 0.21, 0.94, 0.32, 0.57, 0.02, 0.35, 0.39, 0.35],
      ]);
    case 'span':
      final bar = Rect.fromLTWH(
        bounds.left,
        bounds.center.dy - bounds.height / 6,
        bounds.width,
        bounds.height / 3,
      );
      return Path()..addRRect(RRect.fromRectAndRadius(bar, Radius.circular(bar.height / 2)));
    default:
      return Path()..addRRect(RRect.fromRectAndRadius(bounds, radius));
  }
}

/// Flattens a path into its dashed counterpart. Flutter has no dash phase of its
/// own, so the vocabulary's dashes are metric work done once here rather than
/// approximated per lens.
Path _dashed(Path source, List<double> pattern) {
  final dashed = Path();
  for (final metric in source.computeMetrics()) {
    var distance = 0.0;
    var index = 0;
    while (distance < metric.length) {
      final step = math.max(pattern[index % pattern.length], 1 / 100);
      final next = math.min(distance + step, metric.length);
      if (index.isEven) dashed.addPath(metric.extractPath(distance, next), Offset.zero);
      distance = next;
      index += 1;
    }
  }
  return dashed;
}
