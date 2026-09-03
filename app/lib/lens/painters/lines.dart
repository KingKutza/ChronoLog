// LINES: the prime line straightened, companions weaving in and out, and the
// warp drawn only where somebody authored it.
//
// N STAPLES = WARP, LINES DRAWS IT (AGENTS.md, Coordinate law; ROADMAP #4). A
// companion is positioned by its STAPLE POINTS to the prime -- correspondence
// staples and shared placements both, because CONNECTION IS NOT INCLUSION and a
// shared placement is a real edge. Between two pinned points the mapping
// STRETCHES, and the stretch is drawn as it falls: piecewise, pin to pin, never
// averaged into one rigid offset. A companion with nothing authored between it
// and the prime is not near the prime; it is unrelated, and the honest picture
// of that is no line at all plus the sentence saying so.
//
// The origin sketch is `local/GUI_Mockup/signal-2023-08-31-09-24-39-007.jpg`: lines
// running at their own heights, dropping to the prime exactly where they are
// stapled. `bak.png` is the robustness target -- a mapping that folds back on
// itself is legal data and draws as a fold, not as an error.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../core/exact.dart';
import '../../core/projection.dart';
import '../../core/records.dart';
import '../../session/lens_catalog.dart';
import '../capacity.dart';
import '../color.dart';
import '../display_weight.dart';
import '../facts.dart';
import '../law_context.dart';
import '../lens_painter.dart';
import '../lines/plan.dart';
import '../marks.dart';
import '../zones.dart';
import '../minimap/labels.dart';
import '../now.dart';
import '../radial/geometry.dart';
import '../theme.dart';
import '../tree/tree_lens.dart';
import '../view_tile.dart';
import 'radial.dart';
import 'spiral.dart';

/// One authored point of correspondence between a companion frame and the
/// prime: this day over there is that day over here. `eventId` names the object
/// that pins them when a shared placement is what did it.
typedef Pin = ({Rational from, Rational to, String? eventId});

/// Every pin between two frames: correspondence staples first, then every object
/// placed on both. Nothing is deduped, collapsed or averaged -- the substrate's
/// rule holds here too, and a frame pinned twice at odds with itself is a real
/// fold rather than a contradiction to resolve.
List<Pin> warpPins(
  ProjectionEngine engine,
  String companion,
  String prime,
  Map<String, List<Fact>> byFrame,
) {
  final pins = <Pin>[];
  for (final entry in engine.staples.frameCorrespondences(companion, prime)) {
    final from = engine.staples.frameEndDays(entry.from);
    final to = engine.staples.frameEndDays(entry.to);
    if (from != null && to != null) pins.add((from: from, to: to, eventId: null));
  }
  final onPrime = {for (final fact in byFrame[prime] ?? const <Fact>[]) fact.event.id: fact.day};
  for (final fact in byFrame[companion] ?? const <Fact>[]) {
    if (onPrime[fact.event.id] case final Rational at) {
      pins.add((from: fact.day, to: at, eventId: fact.event.id));
    }
  }
  return pins..sort((a, b) => a.from.compareTo(b.from));
}

/// Where a companion day lands on the prime axis: exact at every pin, linear
/// between two of them, and NULL outside the pinned span -- past the last staple
/// nobody has said anything, and a lens must not answer where its author did
/// not.
Rational? warp(List<Pin> pins, Rational day) {
  if (pins.length < 2) {
    return pins.length == 1 && pins.first.from == day ? pins.first.to : null;
  }
  if (day < pins.first.from || day > pins.last.from) return null;
  for (var index = 0; index + 1 < pins.length; index += 1) {
    final before = pins[index], after = pins[index + 1];
    if (day < before.from || day > after.from) continue;
    final width = after.from - before.from;
    return width <= Rational.zero
        ? before.to
        : before.to + (after.to - before.to) * ((day - before.from) / width);
  }
  return null;
}

class LinesPainter extends LensPainter {
  LinesPainter(super.scene);

  static final Rational _two = Rational.fromInt(2);

  late final LawContext law = LawContext(scene.law);
  late final bool topology = scene.flag('topology', 'lines.topology');
  late final Rational span = scene.number('days', 'lines.days');
  late final Rational start = scene.focusDays - span / _two;
  late final Rational end = start + span;
  late final Rect field = Rect.fromLTRB(
    scene.dim('lines.padX'),
    scene.dim('lines.padY'),
    math.max(scene.dim('lines.padX') + 1, scene.size.width - scene.dim('lines.padX')),
    math.max(scene.dim('lines.padY') + 1, scene.size.height - scene.dim('lines.padY')),
  );

  double xAt(Rational days) => field.left + (lineProgress(days, start, end) ?? 0) * field.width;

  double yOf(int index) =>
      field.center.dy +
      apexOffset(index, first: scene.px('lines.apexFirst'), step: scene.px('lines.apexStep'));

  @override
  Offset? project(Rational days) =>
      days < start || days > end ? null : Offset(xAt(days), field.center.dy);

  @override
  Rational? unproject(Offset at) => at.dx < field.left || at.dx > field.right
      ? null
      : start + span * Rational.parse('${(at.dx - field.left) / field.width}');

  /// A rail runs one way, so a pan does: the window moves by the share of its
  /// span the drag crossed, and the height of the gesture is not shown moving,
  /// because down this surface there is nowhere to go (ruled 2026-08-31 -- the
  /// transform shows exactly what release commits).
  @override
  PanLanding panLanding(Offset shift) => (
    days: field.width <= 0
        ? Rational.zero
        : -span * Rational.parse((shift.dx / field.width).toStringAsFixed(9)),
    shown: Offset.zero,
    taken: shift,
  );

  @override
  void paint(Canvas canvas, Size size) {
    hits.clear();
    zones.clear();
    refusals.clear();
    final plan = framePlan(scene.engine, scene.projection, read: scene.tunable);
    for (final refused in plan.refused) {
      refusals.add((source: refused.frame, message: refused.message));
    }
    if (!plan.supported) {
      refusals.add((source: 'Lines', message: 'Lines needs a frame that owns an axis of its own.'));
      return paintRefusals(canvas, size);
    }
    final capacity = capacityOf(field.width, field.height, scene.tunable);
    final cascade = ColorCascade(scene.engine, scene.projection, scene.theme);
    final lines = topology ? _topologyLines() : plan.lines;
    final byFrame = <String, List<Fact>>{};
    var truncated = false;
    if (topology) {
      // AUTHORED TOPOLOGY: only incidences somebody wrote, placed by ordinal,
      // because these frames have no comparable coordinate to place them by.
      for (final line in lines) {
        final placed = scene.engine.explicitFacts(line.frame);
        truncated = truncated || placed.length > capacity.marks;
        byFrame[line.frame] = placed.take(capacity.marks).toList();
      }
    } else {
      final window = queryWindow(
        scene,
        start: start,
        end: end,
        budget: capacity.queryBudget,
        law: law,
      );
      refusals.addAll(window.refusals);
      final weights = {
        for (final fact in window.facts)
          fact.identity: factDisplayWeight(scene, fact, keyPrefix: 'lines'),
      };
      final ranked = [...window.facts]
        ..sort((a, b) => weights[b.identity]!.weight.compareTo(weights[a.identity]!.weight));
      final admitted = admit(ranked, capacity, queryTruncated: window.truncated);
      truncated = admitted.truncated;
      for (final fact in admitted.drawn) {
        (byFrame[fact.relation.frame ?? ''] ??= []).add(fact);
      }
      _paintAxis(canvas);
    }
    if (lines.isEmpty) return paintRefusals(canvas, size);
    final ordinals = topology ? _ordinals(byFrame) : null;
    final primeFrame = lines.first.frame;
    var drawn = 0;
    for (final line in lines) {
      final pins = line.prime || topology
          ? const <Pin>[]
          : warpPins(scene.engine, line.frame, primeFrame, byFrame);
      final identity =
          line.prime ||
          topology ||
          scene.engine.coordinateSpaceOf(line.frame) == scene.engine.coordinateSpaceOf(primeFrame);
      if (!identity && pins.length < 2) {
        refusals.add((
          source: line.title,
          message: pins.isEmpty
              ? 'No authored staple relates this to the prime line, so nothing places it here.'
              : 'One staple pins this at a point; drawing its stretch needs two.',
        ));
      }
      // A companion of ANOTHER coordinate space has its own day ordinals, which
      // the shared window knows nothing about: its facts come from its own axis
      // and the warp is what decides which of them are on screen.
      final facts = identity || topology
          ? byFrame[line.frame] ?? const <Fact>[]
          : scene.engine.explicitFacts(line.frame).take(capacity.marks).toList();
      _paintLine(canvas, line, pins, identity: identity);
      drawn += _paintMarks(canvas, line, pins, facts, cascade, ordinals, identity: identity);
    }
    if (nowIn(law, scene.nowDays) case final Rational at
        when !topology && at >= start && at <= end) {
      paintNow(
        canvas,
        Offset(xAt(at), field.top),
        Offset(xAt(at), field.bottom),
        scene.theme,
        scene.tunable,
      );
    }
    final status = truncated
        ? 'Dense window · some events are not shown'
        : drawn == 0
        ? (topology ? 'No authored topology incidences' : 'No events in this window')
        : '';
    if (status.isNotEmpty) {
      paintHaloed(
        canvas,
        status,
        Offset(field.center.dx, field.bottom + scene.px('lane.gap') * 4),
        theme: scene.theme,
        rightAligned: false,
        read: scene.tunable,
      );
    }
    paintRefusals(canvas, size);
  }

  /// The frames the AUTHORED topology reaches from the primary, in the
  /// substrate's own breadth-first order.
  List<LinePlan> _topologyLines() => [
    for (final (index, id) in topologyFrames(
      scene.engine,
      scene.projection.primaryFrame ?? '',
      read: scene.tunable,
    ).indexed)
      (
        frame: id,
        title: scene.engine.document.frames[id]?.title ?? id,
        index: index,
        prime: index == 0,
      ),
  ];

  /// Ordinal placement for topology mode: one column per object, ordered by a
  /// stable id, because no coordinate here may be compared with another.
  Map<String, double> _ordinals(Map<String, List<Fact>> byFrame) {
    final ids = <String>{
      for (final facts in byFrame.values) ...facts.map((fact) => fact.event.id),
    }.toList()..sort();
    return {
      for (final (index, id) in ids.indexed)
        id: field.left + field.width * (index + 1) / (ids.length + 1),
    };
  }

  /// The line itself: the prime straight across, a companion pinned at its
  /// staples with the stretch between them drawn as it falls. A segment whose
  /// mapping runs BACKWARDS bows over itself rather than hiding in a retrace --
  /// a fold is authored meaning (bak.png), not an error to smooth away.
  void _paintLine(Canvas canvas, LinePlan line, List<Pin> pins, {required bool identity}) {
    final y = yOf(line.index);
    final ink = _ink(line.frame, line.prime);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = scene.dim(line.prime ? 'lines.primeStroke' : 'lines.companionStroke')
      ..color = ink;
    if (identity) {
      canvas.drawLine(Offset(field.left, y), Offset(field.right, y), stroke);
    } else if (pins.length >= 2) {
      final path = Path()..moveTo(xAt(pins.first.to), y);
      for (var index = 1; index < pins.length; index += 1) {
        final from = xAt(pins[index - 1].to), to = xAt(pins[index].to);
        if (to < from) {
          path.quadraticBezierTo((from + to) / 2, y - scene.px('lines.apexStep') / 2, to, y);
        } else {
          path.lineTo(to, y);
        }
      }
      canvas.drawPath(path, stroke);
      _paintWarpTicks(canvas, pins, y, ink);
    }
    final hair = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = scene.px('mark.stroke')
      ..color = ink;
    for (final pin in pins) {
      final at = xAt(pin.to);
      dashLine(
        canvas,
        Offset(at, y),
        Offset(at, field.center.dy),
        hair,
        scene.px('lines.stapleDashOn'),
        scene.px('lines.stapleDashOff'),
      );
      canvas.drawCircle(Offset(at, y), scene.px('lines.sharedDotRadius') / 2, Paint()..color = ink);
    }
    paintHaloed(
      canvas,
      '${line.prime ? 'Prime · ' : ''}${line.title}',
      Offset(scene.px('lane.gap'), y),
      theme: scene.theme,
      rightAligned: false,
      read: scene.tunable,
    );
  }

  /// THE WARP MADE VISIBLE: the companion's own units, evenly spaced in ITS
  /// time, landing where the pins put them. Bunched ticks are a compressed
  /// stretch and spread ticks a dilated one, which is the whole picture.
  void _paintWarpTicks(Canvas canvas, List<Pin> pins, double y, Color ink) {
    final steps = scene.many('lines.unitTicks');
    final height = scene.dim('lines.tickHeight');
    final reach = pins.last.from - pins.first.from;
    if (reach <= Rational.zero || steps < 1) return;
    final rule = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = scene.px('mark.stroke')
      ..color = ink.withValues(alpha: scene.px('falloff.opacity2'));
    for (var step = 0; step <= steps; step += 1) {
      final at = warp(pins, pins.first.from + reach * Rational.fromInt(step, steps));
      if (at == null) continue;
      canvas.drawLine(Offset(xAt(at), y - height), Offset(xAt(at), y + height), rule);
    }
  }

  /// One line's marks, fanned where they crowd. A companion mark is drawn ONLY
  /// where the warp places it: no pin, no point.
  int _paintMarks(
    Canvas canvas,
    LinePlan line,
    List<Pin> pins,
    List<Fact> source,
    ColorCascade cascade,
    Map<String, double>? ordinals, {
    required bool identity,
  }) {
    final facts = {for (final fact in source) fact.identity: fact};
    // FILL IS GROUND, ON THIS SURFACE TOO (ISSUES 9.2). A ground on a line is
    // the STRETCH OF THE LINE its span covers, drawn beneath the marks and
    // taking no fan offset -- a ground does not lane. What is left is the
    // figures, which fan and stack as they always did.
    final grounds = <Fact>[], marks = <String, Fact>{};
    for (final fact in facts.values) {
      if (zoneFill(scene.engine, fact, scene.tunable)) {
        grounds.add(fact);
      } else {
        marks[fact.identity] = fact;
      }
    }
    _paintGrounds(canvas, line, grounds, cascade, pins, ordinals, identity: identity);
    final points = <LinePoint>[];
    final xs = <String, double>{};
    for (final fact in marks.values) {
      final mapped = identity ? fact.day : warp(pins, fact.day);
      final at = ordinals != null ? ordinals[fact.event.id] : (mapped == null ? null : xAt(mapped));
      if (at == null || at < field.left || at > field.right) continue;
      xs[fact.identity] = at;
      points.add((id: fact.identity, eventId: fact.event.id, x: at, line: line.index));
    }
    final y = yOf(line.index);
    final pip = scene.px('mark.pip');
    for (final point in fanPoints(points, pixelSpan: 1, read: scene.tunable)) {
      final fact = facts[point.id]!;
      final weight = factDisplayWeight(scene, fact, keyPrefix: 'lines');
      final centre = Offset(xs[point.id]!, y + point.offset);
      final bounds = Rect.fromCenter(center: centre, width: pip, height: pip);
      if (point.offset != 0) {
        canvas.drawLine(
          Offset(centre.dx, y),
          centre,
          Paint()
            ..strokeWidth = scene.px('mark.stroke')
            ..color = cascade.colorOf(fact),
        );
      }
      final hit = markOf(scene, fact, weight, law, cascade).paint(canvas, bounds, fact);
      if (scene.isSelected(fact)) paintSelection(canvas, hit.shape ?? (Path()..addRect(bounds)));
      hits.add(hit);
    }
    return points.length;
  }

  /// THE GROUNDS ON ONE LINE, through the one pass every timed lens shares: the
  /// stretch of the line each span covers, at the line's own height.
  ///
  /// A ground whose span runs off an end is CUT BY THE FIELD, not dropped: what
  /// is on screen of it is drawn, and the continuity grammar says which end the
  /// rest of it is over -- which is the whole reason the grammar exists.
  void _paintGrounds(
    Canvas canvas,
    LinePlan line,
    List<Fact> grounds,
    ColorCascade cascade,
    List<Pin> pins,
    Map<String, double>? ordinals, {
    required bool identity,
  }) {
    if (grounds.isEmpty) return;
    final y = yOf(line.index);
    final half = scene.px('mark.pip');
    for (final fact in grounds) {
      final endDay = fact.day + scene.engine.eventDurationDays(fact.event);
      final from = identity ? fact.day : warp(pins, fact.day);
      final to = identity ? endDay : warp(pins, endDay);
      if (from == null || to == null) continue;
      final left = ordinals != null ? ordinals[fact.event.id] : xAt(from);
      final right = ordinals != null ? left : xAt(to);
      if (left == null || right == null) continue;
      final box = Rect.fromLTRB(
        left < field.left ? field.left : left,
        y - half,
        right > field.right ? field.right : right,
        y + half,
      );
      if (box.right <= field.left || box.left >= field.right) continue;
      paintGround(
        canvas,
        this,
        fact,
        box,
        zoneSegmentOf(
          continuation: left < field.left,
          continuesAfter: right > field.right,
        ),
        cascade.colorOf(fact),
      );
      hits.add((bounds: box, shape: null, grab: null, fact: fact, identity: fact.identity));
    }
  }

  /// The axis ladder: ticks on REAL boundaries of this law, never on an
  /// arbitrary eighth of the window.
  void _paintAxis(Canvas canvas) {
    final rule = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = scene.px('mark.stroke')
      ..color = scene.theme.hair;
    for (final tick in labelTicks(
      start,
      end,
      granularityFor('lines'),
      law,
      maxLabels: scene.whole('lines.axisTicks'),
      read: scene.tunable,
    )) {
      final at = xAt(tick.days);
      canvas.drawLine(Offset(at, field.top), Offset(at, field.bottom), rule);
      paintHaloed(
        canvas,
        tick.text,
        Offset(at, field.bottom + scene.px('lane.gap')),
        theme: scene.theme,
        rightAligned: false,
        read: scene.tunable,
      );
    }
  }

  /// A line's ink: the frame's OWN authored colour, or the structural role --
  /// prime or companion -- when its author has said nothing.
  Color _ink(String frameId, bool prime) {
    final frame = scene.engine.document.frames[frameId];
    return parseColor(frame?.extra['color']) ??
        parseColor(obj(frame?.extra['display'])?['color']) ??
        (prime ? scene.theme.primary : scene.theme.strong);
  }
}

/// Lines' extra affordance beyond what the catalog already ships.
const Map<String, List<ControlSpec>> _extraControls = {
  'lines': [ControlSpec('toggle', 'topology', 'Authored topology', 'lines.topology')],
};

/// The curve family's builders and catalog entries.
///
/// The catalog ships each lens's title, description and view keys; the lens that
/// DRAWS it fills in the controls it actually affords -- here its own promotion
/// thresholds, which are per-lens settings by ruling.
void registerCurveLenses() {
  registerLensPainter('lines', LinesPainter.new);
  registerLensPainter('spiral', SpiralPainter.new);
  registerLensPainter('radial', RadialPainter.new);
  registerLensWidget('tree', treeLensBuilder);
  for (final id in ['lines', 'spiral', 'radial', 'tree']) {
    final spec = lensCatalog[id];
    if (spec == null) continue;
    lensCatalog[id] = LensSpec(
      spec.id,
      spec.title,
      spec.description,
      isTimeSurface: spec.isTimeSurface,
      spanUnit: spec.spanUnit,
      spanFormula: spec.spanFormula,
      controls: [
        ...spec.controls,
        ...?_extraControls[id],
        ControlSpec('number', 'importantAt', 'Important at', '$id.importantAt'),
        ControlSpec('number', 'landmarkAt', 'Landmark at', '$id.landmarkAt'),
      ],
    );
  }
}
