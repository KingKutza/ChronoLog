// Zone fill: a multi-day span drawn as ONE continuous band across the days it
// covers, rather than as a repeated chip that looks like several events.
//
// A GROUP PROPERTY, NOT A LENS KNOB (ruled 2026-08-27, ruling 11). The web build
// kept a stringly-built per-lens boolean, `session[lens + "ZoneFill"]`, which
// meant the same span read as a zone in one surface and as chips in another for
// no authored reason. Frames are groups, handling is a group property, so
// `display.zone` on a contributing frame is what says this. "Enum is the
// enemy... any system that encodes a right way does in the same breath preclude
// other ways."
//
// The continuity grammar is the whole design: start, middle and end are
// different shapes so the eye reads one band, and only the START carries the
// title -- a name repeated on every day of a week-long span is noise.

import 'package:flutter/widgets.dart';

import '../core/exact.dart';
import '../core/projection.dart';
import 'facts.dart';
import 'theme.dart';
import 'tunables.dart';

/// Where a day sits within its span. `whole` is a span that begins and ends on
/// the same day and needs no continuity at all.
const String zoneWhole = 'whole', zoneStart = 'start';
const String zoneMiddle = 'middle', zoneEnd = 'end';

String zoneSegment(Segment segment) {
  if (!segment.continuation) return segment.continuesAfter ? zoneStart : zoneWhole;
  return segment.continuesAfter ? zoneMiddle : zoneEnd;
}

/// Does this fact draw as a zone? Read off the frames that bear on it -- its
/// placement frame, the frames above that, and every group it belongs to -- so
/// authoring it once on the group settles it in every lens at once. The shipped
/// default is the tunable, which is what a document with nothing authored gets.
bool zoneFill(ProjectionEngine engine, Fact fact, Tunable? read) =>
    switch (engine.authoredHandling(fact.event.id, 'zone', nearest: fact.relation.frame)) {
      final bool authored => authored,
      _ => tunable(read, 'zone.default') > Rational.zero,
    };

/// The band a zone day paints: a wash of the object's own color, an edge rule,
/// and corners rounded only where the band actually begins or ends.
({Paint fill, Paint edge, RRect shape}) zoneBand(
  Rect bounds,
  Color color,
  String segment,
  ChronoTheme theme,
  Tunable? read,
) {
  final radius = Radius.circular(pixels(read, 'zone.radius'));
  final open = Radius.zero;
  final shape = RRect.fromRectAndCorners(
    bounds,
    topLeft: segment == zoneMiddle || segment == zoneEnd ? open : radius,
    bottomLeft: segment == zoneMiddle || segment == zoneEnd ? open : radius,
    topRight: segment == zoneMiddle || segment == zoneStart ? open : radius,
    bottomRight: segment == zoneMiddle || segment == zoneStart ? open : radius,
  );
  return (
    fill: Paint()..color = Color.lerp(theme.paper, color, pixels(read, 'zone.fill'))!,
    edge: Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = pixels(read, 'zone.rule')
      ..color = color.withValues(alpha: pixels(read, 'zone.edge')),
    shape: shape,
  );
}

/// Only the first day of a band is titled.
bool zoneTitled(String segment) => segment == zoneStart || segment == zoneWhole;
