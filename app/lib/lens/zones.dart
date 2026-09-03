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
// different shapes so the eye reads one band.
//
// AND EVERY VISIBLE SEGMENT NAMES ITSELF (ISSUES 9.2). The title used to be the
// head's alone, on the grounds that a name repeated down a week is noise. Don:
// "if I can't see the start I have no way to know what it is" -- a band scrolled
// past its own head was an anonymous wash, and a name a person cannot see is not
// noise saved, it is the object gone. The lens titles each segment it draws; the
// head is still where the band's own START INSTANT reads, because a continuation
// segment has no start of its own to report.

import 'package:flutter/widgets.dart';

import '../core/exact.dart';
import '../core/projection.dart';
import 'facts.dart';
import 'lens_painter.dart';
import 'marks.dart';
import 'theme.dart';
import 'tunables.dart';

/// Where a day sits within its span. `whole` is a span that begins and ends on
/// the same day and needs no continuity at all.
const String zoneWhole = 'whole', zoneStart = 'start';
const String zoneMiddle = 'middle', zoneEnd = 'end';

/// The continuity grammar from the two facts it is made of: whether this day
/// carries on from a previous one, and whether another follows. Said once, so a
/// surface with minutes to consult and one whose unit IS the day cannot come to
/// different answers about the same span.
String zoneSegmentOf({required bool continuation, required bool continuesAfter}) => continuation
    ? (continuesAfter ? zoneMiddle : zoneEnd)
    : (continuesAfter ? zoneStart : zoneWhole);

String zoneSegment(Segment segment) => zoneSegmentOf(
  continuation: segment.continuation,
  continuesAfter: segment.continuesAfter,
);

/// Does this fact draw as a zone? Read off the frames that bear on it -- its
/// placement frame, the frames above that, and every group it belongs to -- so
/// authoring it once on the group settles it in every lens at once. The shipped
/// default is the tunable, which is what a document with nothing authored gets.
///
/// THE DAY IS ONE OF THESE (ruled 2026-08-31): "day start/end is an authored
/// object -- a daily series -- whose handling says display-as-zone ... The
/// setting dies." Nothing here knows what a day is; it draws the zone whatever
/// authored object asked for one, and a document with no day object simply has
/// no day zone.
bool zoneFill(ProjectionEngine engine, Fact fact, Tunable? read) =>
    switch (engine.authoredHandling(
      handlingSubject(engine, fact),
      'zone',
      nearest: fact.relation.frame,
    )) {
      final bool authored => authored,
      _ => tunable(read, 'zone.default') > Rational.zero,
    };

/// The band a zone day paints: a wash of the object's own color, an edge rule,
/// and corners rounded only where the band actually begins or ends.
///
/// FILL IS GROUND, AND A GROUND IS TRANSLUCENT (Don, ruled; ISSUES 9.3). The
/// wash was `Color.lerp(theme.paper, color, zone.fill)`, and a lerp of two
/// OPAQUE colours is opaque: a zone did not wash over what it covered, it erased
/// it -- "the Code Freeze event is now covering the Labor Day event". It was also
/// a third colour nobody authored, paper mixed into a hue the person chose, so a
/// palette change moved every zone's colour.
///
/// The authored hue, at the alpha the setting states, is both answers at once:
/// what is under the ground reads through it, and two grounds over one span read
/// as two rather than one hiding the other. NOTHING DISAPPEARS SILENTLY.
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
    fill: Paint()..color = color.withValues(alpha: pixels(read, 'zone.fill')),
    edge: Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = pixels(read, 'zone.rule')
      ..color = color.withValues(alpha: pixels(read, 'zone.edge')),
    shape: shape,
  );
}

/// Is this segment the band's HEAD -- the day its own start instant falls on?
/// The clock reading belongs to that segment and to no other; the NAME belongs
/// to every segment (ISSUES 9.2).
bool zoneTitled(String segment) => segment == zoneStart || segment == zoneWhole;

/// THE ONE ZONE PASS EVERY TIMED LENS SHARES (ISSUES 9.2, Don: "zone is working
/// on Intimate but not on Strategic -- or Tactical or Wall").
///
/// A lens supplies only its own projection -- the region this ground covers on
/// this surface -- and this draws it and records it. Recording here is what
/// makes the list and the picture ONE derivation: a lens cannot paint a ground
/// it does not report, nor report one it did not paint.
///
/// A GROUND SPANS BY NATURE. The [bounds] handed in are the region the ground
/// COVERS on this surface -- a whole cell, a whole column of a day, the whole
/// arc of its interval -- never a chip box and never a lane, because a ground
/// that lanes has been treated as a mark.
void paintGround(
  Canvas canvas,
  LensPainter lens,
  Fact fact,
  Rect bounds,
  String segment,
  Color color,
) {
  final grammar = zoneBand(bounds, color, segment, lens.scene.theme, lens.scene.tunable);
  canvas.drawRRect(grammar.shape, grammar.fill);
  canvas.drawRRect(grammar.shape, grammar.edge);
  lens.zones.add((fact: fact, bounds: bounds));
}

