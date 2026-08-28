// ONE now-marker derivation, for every lens and the minimap.
//
// The web build had four, and all four independently re-asked whether the law
// maps to a clock. It is one question with one answer: a frame whose law does
// not map to a clock HAS NO NOW, and drawing a line on it would invent one. That
// is why this returns null rather than a flag -- a caller that forgets to check
// gets nothing to draw instead of a wrong mark.
//
// The running clock is absolute, so Now lands where the atom arithmetic puts it
// and drifts across a shortened frame's days. That drift is the ruling, not a
// defect.

import 'package:flutter/widgets.dart';

import '../core/exact.dart';
import 'law_context.dart';
import 'theme.dart';
import 'tunables.dart';

/// Where now falls, or null when this law has no now at all.
Rational? nowIn(LawContext law, Rational nowDays) => law.mapsToClock ? nowDays : null;

/// The now marker inside a window, as a fraction of it. Null when the law has no
/// now, or when now is outside the window -- a marker clamped to an edge claims
/// the present is there, which is exactly the lie a minimap must not tell.
double? nowFraction(LawContext law, Rational nowDays, Rational from, Rational to) {
  final at = nowIn(law, nowDays);
  if (at == null || to <= from || at < from || at > to) return null;
  return ((at - from) / (to - from)).toDouble();
}

/// The one now paint: the primary ink at its own weight, with a paper halo so it
/// stays readable over whatever it crosses.
({Paint line, Paint halo}) nowPaint(ChronoTheme theme, Tunable? read) => (
  line: Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = pixels(read, 'now.width')
    ..color = theme.primary,
  halo: Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = pixels(read, 'now.width') + pixels(read, 'now.halo') * 2
    ..color = theme.paper.withValues(alpha: pixels(read, 'falloff.opacity2')),
);

/// Draws the marker halo-first, so the halo never covers the line it protects.
void paintNow(Canvas canvas, Offset from, Offset to, ChronoTheme theme, Tunable? read) {
  final paints = nowPaint(theme, read);
  canvas.drawLine(from, to, paints.halo);
  canvas.drawLine(from, to, paints.line);
}
