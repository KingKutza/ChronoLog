// The curve family: ONE painter for both radial-family lenses, plus RADIAL --
// one cycle, one band per frame x group, packed inward from the outer edge.
//
// MELTED ON PURPOSE. Radial and Spiral are separate lenses (ruled 2026-08-17)
// with their own view state, and they were separate code twice over in the web
// build: two cycle resolutions, two lane packers, two label passes, two now
// markers. What actually differs between them is the RADIUS a mark sits at and
// what a band is; everything else is one pipeline here, and the two lenses are
// the two answers to those questions.
//
// REFUSE LOUDLY. A cycle this law cannot resolve EXACTLY is not drawn at an
// approximate length -- it is refused in the law's own sentence. `cycles.dart`
// is stricter than `magnitudeDays` on purpose, and this carries the refusal to
// the surface rather than guessing a period.
//
// NO FIVE-LANE CAP. The web build crammed a sixth concurrent event into the
// shortest lane regardless of overlap; lanes come from the one packer and the
// field is thinned by apparent magnitude, never by an integer.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../core/exact.dart';
import '../../core/math.dart';
import '../../core/projection.dart';
import '../../core/records.dart';
import '../../session/lens_catalog.dart';
import '../capacity.dart';
import '../color.dart';
import '../display_weight.dart';
import '../facts.dart';
import '../lanes.dart';
import '../law_context.dart';
import '../lens_painter.dart';
import '../marks.dart';
import '../now.dart';
import '../radial/cycles.dart';
import '../radial/geometry.dart';
import '../zones.dart';
import '../tunables.dart';

/// Every number the curve lenses draw with that the substrate had not already
/// named. Composed by the session beside every other area's map.
const Map<String, String> curveTunableDefaults = {
  // Promotion thresholds, per lens, so a lens that wants a busier landmark bar
  // says so in the settings file rather than in code.
  'lines.importantAt': '2',
  'lines.landmarkAt': '4',
  'spiral.importantAt': '2',
  'spiral.landmarkAt': '4',
  'radial.importantAt': '2',
  'radial.landmarkAt': '4',
  'curve.margin': '28',
  'curve.labelDecimals': '1',
  'curve.labelBudget': '24',
  'curve.labelOffset': '8',
  'curve.arcMinimum': '1/250',
  'curve.bandOpacity': '0.16',
  'curve.coreOpacity': '0.28',
  'curve.laneShare': '0.72',
  'spiral.innerRadius': '82',
  'spiral.spacingMax': '78',
  'spiral.samplesPerTurn': '120',
  'radial.bandSpacingMax': '48',
  'lines.topology': 'false',
  'lines.padX': '96',
  'lines.padY': '52',
  'lines.primeStroke': '5',
  'lines.companionStroke': '3',
  'lines.unitTicks': '12',
  'lines.tickHeight': '5',
};

/// One setting's shipped value, from the caller's own map first and then from
/// the maps every lens shares. A key in no map at all is a refusal naming it.
Object? shippedSetting(Map<String, String> defaults, String key) {
  final source = defaults[key] ?? sessionTunableDefaults[key] ?? lensTunableDefaults[key];
  if (source == null) throw MathRefusal('No setting named $key');
  return evaluateSource(source, const Env());
}

/// The settings reads a curve lens makes: a number, a pixel, a count, and a view
/// value that falls back to its own shipped default.
extension CurveScene on LensScene {
  Rational tune(String key) {
    final read = this.tunable;
    if (read != null) return read(key);
    final value = shippedSetting(curveTunableDefaults, key);
    if (value is! Rational) throw MathRefusal('Setting $key must be a number');
    return value;
  }

  double dim(String key) => tune(key).toDouble();

  int many(String key) => tune(key).round().toInt();

  Rational number(String viewKey, String settingKey) {
    final raw = viewValue(viewKey);
    if (raw is num) return Rational.parse('$raw');
    if (raw is String && raw.trim().isNotEmpty) return Rational.parse(raw);
    return tune(settingKey);
  }

  bool flag(String viewKey, String settingKey) {
    final raw = viewValue(viewKey);
    return raw is bool ? raw : shippedSetting(curveTunableDefaults, settingKey) == true;
  }
}

/// The interval a radial-family lens draws, anchored on the shared days axis.
/// `refusal` is the whole answer when the cycle did not resolve.
typedef CycleSpan = ({Rational start, Rational end, Rational period, int turns, String? refusal});

/// Resolves the drawn cycle: an authored period in days joins the law's own
/// cycles as an option and outranks them, and a fixed period anchors on the
/// cycle boundary its focus falls in, so panning slides the marks not the rings.
CycleSpan cycleFor(LensScene scene, {int past = 0, int future = 0}) {
  final override = scene.number('cycleDays', 'radial.cycleDays');
  final authored = override > Rational.zero;
  final named = '${scene.viewValue('cycle') ?? ''}';
  final resolution = resolveCycle(
    [
      if (authored) (id: 'view:cycleDays', title: 'Cycle', period: null, days: override),
      ...lawCycles(scene.law),
    ],
    authored ? 'view:cycleDays' : (named.isEmpty ? null : named),
    law: scene.law,
    focus: scene.focusDays,
    read: scene.tunable,
  );
  final turns = past + future + 1;
  final period = resolution.period;
  final span = period == null
      ? null
      : cycleWindow(resolution, scene.law, past: past, future: future);
  if (resolution.unsupported || period == null || period <= Rational.zero || span == null) {
    return (
      start: scene.focusDays,
      end: scene.focusDays,
      period: Rational.zero,
      turns: turns,
      refusal: resolution.refusal ?? 'This cycle has no length that resolves exactly.',
    );
  }
  // A dynamic cycle already resolved its own boundaries; a fixed one is anchored
  // on the boundary the focus falls in.
  final anchor = resolution.start != null
      ? Rational.zero
      : Rational((scene.focusDays / period).floor()) * period;
  return (
    start: anchor + span.start,
    end: anchor + span.end,
    period: period,
    turns: turns,
    refusal: null,
  );
}

/// The mark paint one fact carries, once: sigil from what its author wrote and
/// what the law makes of its duration -- never from a trait string -- plus
/// state, authored colour and falloff bucket. Every curve lens draws through it.
MarkSpec markOf(
  LensScene scene,
  Fact fact,
  DisplayWeight weight,
  LawContext law,
  ColorCascade cascade,
) => MarkSpec(
  sigil: sigilFor(
    authored: authoredSigilOf(scene.engine, fact),
    event: fact.event,
    virtual: fact.virtualId.isNotEmpty,
    succession: false,
    durationDays: scene.engine.eventDurationDays(fact.event),
    dayDays: law.dayDays,
    promoted: weight.promotion != standardWeight,
  ),
  state: weight.state,
  color: cascade.colorOf(fact),
  theme: scene.theme,
  bucket: weight.bucket,
  read: scene.tunable,
);

/// A mark's arc as a CLOSED band, so the hit shape is the ribbon the eye sees
/// rather than the bounding box of a half circle.
Path arcBand(Offset centre, double radius, double half, double from, double to) => Path()
  ..addPath(arcPath(centre, radius + half, from, to), Offset.zero)
  ..extendWithPath(arcPath(centre, math.max(half / 2, radius - half), to, from), Offset.zero)
  ..close();


/// One candidate label around a ring, before collision suppression.
typedef RingLabel = ({String text, double angle, double radius});

/// Draws the placed labels, deduped and collision-suppressed by the substrate.
void paintLabels(Canvas canvas, LensScene scene, Offset centre, Iterable<RingLabel> candidates) {
  for (final label in placeLabels(
    candidates,
    centre,
    scene.theme,
    budget: scene.many('curve.labelBudget'),
    read: scene.tunable,
  )) {
    paintHaloed(
      canvas,
      label.text,
      label.at,
      theme: scene.theme,
      rightAligned: label.rightAligned,
      read: scene.tunable,
    );
  }
}

/// The hairline a ring falls back to when there is nothing to draw on it.
Paint ringRule(LensScene scene) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = scene.px('mark.stroke')
  ..color = scene.theme.hair;

/// One drawn band. For Radial a frame crossed with a group, which is the only
/// key that distinguishes two rings; for Spiral the single track.
typedef Band = ({String title, List<Fact> facts});

/// The pipeline both radial-family lenses run. A subclass answers three
/// questions: what a band is, what radius a mark sits at, and what the track
/// under the marks looks like.
abstract class CurvePainter extends LensPainter {
  CurvePainter(super.scene, this.lens, {this.past = 0, this.future = 0});

  /// The settings namespace, and the name a refusal is signed with.
  final String lens;
  final int past, future;

  late final LawContext law = LawContext(scene.law);
  late final CycleSpan cycle = cycleFor(scene, past: past, future: future);
  late final Offset centre = Offset(scene.size.width / 2, scene.size.height / 2);
  late final double outer = math.min(
    scene.px('radial.outerRadius'),
    scene.size.shortestSide / 2 - scene.dim('curve.margin'),
  );
  late final double inner = math.min(scene.dim(innerKey), outer / 2);

  /// The ring radii of the bands the last paint drew, so a mark's radius is one
  /// lookup rather than a packing recomputed per mark.
  List<double> radii = const [];
  int bands = 1;

  String get innerKey;

  /// How wide the marks of one band may spread.
  double get bandWidth;

  List<double> bandRadii(int count);

  /// Where a mark of this band, at this progress through the window, sits.
  double radiusOf(int band, double progress);

  void paintTrack(Canvas canvas, ColorCascade cascade, List<Band> data);

  List<Band> bandsOf(List<Fact> facts);

  /// How far through the whole drawn window one day sits: the one number every
  /// curve position is derived from.
  double progressOf(Rational days) {
    final span = cycle.end - cycle.start;
    return span <= Rational.zero ? 0 : ((days - cycle.start) / span).toDouble();
  }

  /// Counted THROUGH the turns rather than modulo one, so the mapping stays a
  /// bijection over the drawn window and a wheel notch can spin it.
  double daysToAngle(Rational days) => startRay + progressOf(days) * cycle.turns * math.pi * 2;

  /// The exact inverse of [daysToAngle], COUNTED THROUGH THE TURNS as that one
  /// counts. It does not wrap: an angle two turns past the start ray names a day
  /// two turns along, which on a spiral is a different day from the one on the
  /// same ray one turn in. Wrapping here would collapse every turn onto the
  /// first and stop the pair being a bijection at all.
  Rational angleToDays(double angle) {
    final progress = (angle - startRay) / (cycle.turns * math.pi * 2);
    return cycle.start + (cycle.end - cycle.start) * Rational.parse('$progress');
  }

  /// Where the angle a pointer actually lands at sits on the turn THIS surface
  /// drew.
  ///
  /// `atan2` answers in `(-pi, pi]` and the start ray is `-pi/2`, so the raw
  /// angle of the upper-left quadrant read a NEGATIVE progress: a day before
  /// `cycle.start`, which `project` then refused, and a click there found the
  /// lens disagreeing with itself (ISSUES 9.3). The remainder is taken with `%`,
  /// which is non-negative for a positive divisor -- `remainder` keeps the sign
  /// and would put the bug straight back.
  ///
  /// ONE TURN IS WHAT AN ANGLE CAN NAME. A surface winding more than one turn
  /// puts many instants on the same ray, so its angle alone is the inverse of
  /// nothing; such a surface reads the coordinate that does not repeat -- its
  /// RADIUS -- and says so by overriding [unproject], as Spiral does. Here the
  /// wrap is the whole answer, and on a one-turn window it IS the bijection.
  double angleOnTurn(double angle) => startRay + (angle - startRay) % (math.pi * 2);

  @override
  Offset? project(Rational days) =>
      cycle.period <= Rational.zero || days < cycle.start || days >= cycle.end
      ? null
      : polar(centre, radiusOf(0, progressOf(days)), daysToAngle(days));

  /// THE SURFACE REACHES AS FAR AS ITS INK, NOT AS FAR AS ITS CENTRELINE
  /// (ISSUES 9.3). A band is stroked [bandWidth] wide about its own radius, so
  /// the outermost ring's ink ends half a band past [outer] -- and `project`
  /// itself answers exactly [outer] for the outer ring, which a bound of
  /// `outer` refused on the last bit of a double. A painter that knows both
  /// directions may not refuse the very point it drew, so the bound is derived
  /// from the drawing: the ink, plus whatever grace `curve.margin` states.
  @override
  Rational? unproject(Offset at) {
    final radius = (at - centre).distance;
    final reach = outer + bandWidth / 2 + scene.dim('curve.margin');
    if (cycle.period <= Rational.zero || radius > reach) return null;
    return angleToDays(angleOnTurn(math.atan2(at.dy - centre.dy, at.dx - centre.dx)));
  }

  @override
  void paint(Canvas canvas, Size size) {
    hits.clear();
    zones.clear();
    refusals.clear();
    if (cycle.refusal case final String message) {
      refusals.add((source: lens, message: message));
      canvas.drawCircle(centre, outer, ringRule(scene));
      return paintRefusals(canvas, size);
    }
    final capacity = capacityOf(math.pi * 2 * outer * cycle.turns, outer - inner, scene.tunable);
    final window = queryWindow(
      scene,
      start: cycle.start,
      end: cycle.end,
      budget: capacity.queryBudget,
      law: law,
    );
    refusals.addAll(window.refusals);
    final weights = {
      for (final fact in window.facts)
        fact.identity: factDisplayWeight(scene, fact, keyPrefix: lens),
    };
    final ranked = [...window.facts]
      ..sort((a, b) => weights[b.identity]!.weight.compareTo(weights[a.identity]!.weight));
    final admitted = admit(ranked, capacity, queryTruncated: window.truncated);
    final cascade = ColorCascade(scene.engine, scene.projection, scene.theme);
    // FILL IS GROUND, ON A RING TOO (ISSUES 9.2). A ground never enters the band
    // packing: on Radial a band is a frame crossed with a group, and a ground
    // put into one would be a ring of its own that the figures it covers are
    // nowhere near. A GROUND SPANS BY NATURE, so it spans the surface's whole
    // radial reach for its own arc and the figures read over it wherever their
    // own rings put them.
    final grounds = [
      for (final fact in admitted.drawn)
        if (zoneFill(scene.engine, fact, scene.tunable)) fact,
    ];
    final drawn = bandsOf([
      for (final fact in admitted.drawn)
        if (!zoneFill(scene.engine, fact, scene.tunable)) fact,
    ]);
    bands = drawn.isEmpty ? 1 : drawn.length;
    radii = bandRadii(bands);
    // A track whose figure this size cannot hold SAYS SO. The geometry refuses
    // rather than drawing a pinched or backwards ribbon (ISSUES 9.3), and a
    // lens paints its refusals and never throws, so the sentence lands in the
    // same list a cycle refusal lands in and the rest of the scene still draws.
    try {
      paintTrack(canvas, cascade, drawn);
    } on GeometryRefusal catch (refused) {
      refusals.add((source: lens, message: refused.message));
    }
    _paintGrounds(canvas, grounds, cascade);
    final labels = _paintGuide(canvas);
    for (final (index, band) in drawn.indexed) {
      labels.addAll(_paintBand(canvas, band, index, weights, cascade));
    }
    if (nowFraction(law, scene.nowDays, cycle.start, cycle.end) case final double at) {
      final angle = startRay + at * cycle.turns * math.pi * 2;
      final radius = radiusOf(0, at);
      paintNow(
        canvas,
        polar(centre, radius - bandWidth / 2, angle),
        polar(centre, radius + bandWidth / 2, angle),
        scene.theme,
        scene.tunable,
      );
    }
    if (scene.flag('labels', 'radial.labels')) paintLabels(canvas, scene, centre, labels);
    if (overflowLabel(admitted) case final String more when more.isNotEmpty) {
      paintHaloed(
        canvas,
        more,
        centre,
        theme: scene.theme,
        rightAligned: false,
        read: scene.tunable,
      );
    }
    paintRefusals(canvas, size);
  }

  /// Every ground, over its own arc, through the one pass every timed lens
  /// shares. Drawn after the track and before the bands, which is what "beneath
  /// everything" means on a surface whose track is the paper.
  void _paintGrounds(Canvas canvas, List<Fact> grounds, ColorCascade cascade) {
    for (final fact in grounds) {
      final end = fact.day + scene.engine.eventDurationDays(fact.event);
      final shape = groundArc(fact.day, end);
      paintGround(
        canvas,
        this,
        fact,
        shape.getBounds(),
        zoneSegmentOf(continuation: fact.day < cycle.start, continuesAfter: end > cycle.end),
        cascade.colorOf(fact),
      );
      hits.add((
        bounds: shape.getBounds(),
        shape: shape,
        grab: null,
        fact: fact,
        identity: fact.identity,
      ));
    }
  }

  /// THE REACH A GROUND COVERS ON THIS CURVE, between the two instants. Radial
  /// spans every ring it has; Spiral spans its one track, whose radius is itself
  /// the coordinate and cannot be spanned without covering other turns.
  Path groundArc(Rational start, Rational end) {
    final from = daysToAngle(start < cycle.start ? cycle.start : start);
    final to = daysToAngle(end > cycle.end ? cycle.end : end);
    return arcBand(centre, (outer + inner) / 2, (outer - inner) / 2, from, to);
  }

  /// The guide ring: the tick ladder from the law -- a 23-hour day gets 23 ticks
  /// -- and, on every major mark, how much of the law's own time has elapsed.
  /// The web build's hardcoded "Week N" died with its literal seven.
  List<RingLabel> _paintGuide(Canvas canvas) {
    final guide = guideSettings(
      scene.law,
      cycle.period,
      divisions: scene.number('divisions', 'radial.divisions').round().toInt(),
      majorEvery: scene.number('majorEvery', 'radial.majorEvery').round().toInt(),
      read: scene.tunable,
    );
    final decimals = scene.many('curve.labelDecimals');
    final labels = <RingLabel>[];
    final ticks = guideTicks(
      divisions: guide.divisions,
      majorEvery: guide.majorEvery,
      unitsPerCycle: (guide.cycleDays / law.dayDays).toDouble(),
      dayNight: guide.dayNight,
    );
    for (final (index, tick) in ticks.indexed) {
      canvas.drawLine(
        polar(centre, inner, tick.angle),
        polar(centre, outer, tick.angle),
        guidePaint(tick, scene.theme, scene.tunable),
      );
      if (!tick.major) continue;
      final elapsed = guide.cycleDays * Rational.fromInt(index) / Rational.fromInt(guide.divisions);
      final days = elapsed / law.dayDays;
      final short = days < Rational.one;
      final value = (short ? days * law.hoursPerDay : days).toDouble();
      labels.add((
        text: elapsed <= Rational.zero
            ? 'cycle start'
            : '+${value.toStringAsFixed(decimals)}${short ? 'h' : 'd'}',
        angle: tick.angle,
        radius: outer + scene.dim('curve.labelOffset'),
      ));
    }
    return labels;
  }

  /// One band's marks: lanes from the one packer, each drawn as a
  /// CONSTANT-RADIUS arc at its own midpoint radius, round caps by intent.
  List<RingLabel> _paintBand(
    Canvas canvas,
    Band band,
    int index,
    Map<String, DisplayWeight> weights,
    ColorCascade cascade,
  ) {
    final minimum = scene.tune('curve.arcMinimum') * (cycle.end - cycle.start);
    final spans = [
      for (final fact in band.facts)
        (
          start: fact.day,
          end:
              fact.day +
              (scene.engine.eventDurationDays(fact.event) > minimum
                  ? scene.engine.eventDurationDays(fact.event)
                  : minimum),
        ),
    ];
    final packing = packLanes(spans);
    final step = math.max(
      scene.px('lane.gap'),
      bandWidth * scene.dim('curve.laneShare') / math.max(1, packing.count),
    );
    final gap = scene.dim('curve.labelOffset');
    final labels = <RingLabel>[
      if (band.title.isNotEmpty)
        (text: band.title, angle: startRay, radius: radiusOf(index, 0) + gap),
    ];
    for (final (at, fact) in band.facts.indexed) {
      final weight = weights[fact.identity]!;
      final from = daysToAngle(spans[at].start), to = daysToAngle(spans[at].end);
      final middle = (progressOf(spans[at].start) + progressOf(spans[at].end)) / 2;
      final radius = radiusOf(index, middle) + (packing.lanes[at] - (packing.count - 1) / 2) * step;
      final stroke = math.max(
        scene.px(weight.promotion == landmarkWeight ? 'mark.strokeStrong' : 'mark.stroke'),
        step * scene.dim('curve.laneShare'),
      );
      final shape = arcBand(centre, radius, stroke / 2, from, to);
      canvas.drawPath(
        arcPath(centre, radius, from, to),
        markOf(scene, fact, weight, law, cascade).stroke()..strokeWidth = stroke,
      );
      if (scene.isSelected(fact)) paintSelection(canvas, shape);
      hits.add((
        bounds: shape.getBounds(),
        shape: shape,
        grab: null,
        fact: fact,
        identity: fact.identity,
      ));
      labels.add((
        text: '${obj(fact.event.payload)?['title'] ?? ''}',
        angle: (from + to) / 2,
        radius: radius + gap,
      ));
    }
    return labels;
  }
}

/// RADIAL: one cycle, bands packed inward, each ring a frame crossed with a
/// group.
class RadialPainter extends CurvePainter {
  RadialPainter(LensScene scene) : super(scene, 'radial');

  @override
  String get innerKey => 'radial.innerRadius';

  @override
  double get bandWidth => math.min(
    scene.dim('radial.bandSpacingMax'),
    bands < 2 ? outer - inner : (outer - inner) / bands,
  );

  @override
  List<double> bandRadii(int count) => ringRadii(count, outer: outer, inner: inner);

  @override
  double radiusOf(int band, double progress) =>
      radii.isEmpty ? outer : radii[band.clamp(0, radii.length - 1)];

  @override
  void paintTrack(Canvas canvas, ColorCascade cascade, List<Band> data) {
    if (data.isEmpty) return canvas.drawCircle(centre, outer, ringRule(scene));
    for (final (index, band) in data.indexed) {
      canvas.drawCircle(
        centre,
        radii[index],
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(scene.px('radial.ribbonWidth') / 2, bandWidth)
          ..color = cascade
              .colorOf(band.facts.first)
              .withValues(alpha: scene.dim('curve.bandOpacity')),
      );
    }
  }

  /// Frame x group, title-sorted. The calendar frame of the object, then the
  /// group it is a member of -- both authored, neither inferred.
  @override
  List<Band> bandsOf(List<Fact> facts) {
    final found = <String, Band>{};
    for (final fact in facts) {
      final source = fact.virtualId.isEmpty
          ? fact.event.id
          : scene.engine.document.patterns[fact.pattern]?.templateEvent ?? fact.event.id;
      final frameId = scene.engine.indexes.calendarFrameOf(source) ?? fact.relation.frame ?? source;
      final groupId = scene.engine.indexes.directGroupsOf(source).firstOrNull;
      final frame = scene.engine.document.frames[frameId];
      final group = groupId == null ? null : scene.engine.document.frames[groupId];
      final band = found['$frameId ${groupId ?? ''}'] ??= (
        title: '${frame?.title ?? frameId} · ${group?.title ?? 'Ungrouped'}',
        facts: <Fact>[],
      );
      band.facts.add(fact);
    }
    return found.values.toList()..sort((a, b) => a.title.compareTo(b.title));
  }
}
