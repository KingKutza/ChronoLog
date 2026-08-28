// Lines geometry: the prime line straightened, companions weaving in and out,
// and the warp drawn only where somebody authored it.
//
// THE FOUNDING CONCEPTION, made geometry. There are lines, each internally
// consistent to its own function of time; events attach to zero or more of them;
// an event on several STAPLES them together at that point. Render one line and
// see its events along it, with the others weaving in and out -- pinned ONLY at
// staple points, with the drawn weave between them an honest interpolation.
//
// "N STAPLES = WARP, LINES DRAWS IT." Cross-frame projection exists only through
// staples, so the authored-topology plan draws authored incidences and refuses
// to invent a mapping. Two frames with nothing between them are not near each
// other; they are unrelated, and the honest picture of that is no line at all.
//
// CONNECTION IS NOT INCLUSION (Don, 2026-08-27): "an event on two frames does
// connect them but does not include them... if I project A and B then I get A,
// B, and a' -- and A and B are connected at a'. This is the Lines lens in
// action." A shared placement is a real edge here even though it includes
// nothing.

import 'dart:math' as math;

import '../../core/exact.dart';
import '../../core/projection.dart';
import '../../core/records.dart';
import '../tunables.dart';

/// How far along the drawn window one day sits. Null for a window with no width
/// -- a zero span is refused rather than divided by.
double? lineProgress(Rational day, Rational start, Rational end) {
  final span = end - start;
  return span <= Rational.zero ? null : ((day - start) / span).toDouble();
}

/// One drawn line: the frame it is, and where it sits in the ladder. Index zero
/// is the prime line, drawn straight; the rest fan above and below it.
typedef LinePlan = ({String frame, String title, int index, bool prime});

/// A frame the lens was asked to draw and could not, with what it lacked.
typedef LineRefusal = ({String frame, String message});

typedef FramePlan = ({List<LinePlan> lines, List<LineRefusal> refused, bool supported});

/// The lines a projection draws: its primary first, then every other frame it
/// names that carries an axis of its own.
///
/// A frame with no positional coordinate space has no axis to weave -- a state
/// frame, a measure -- so it is REFUSED by name rather than drawn as a flat line
/// meaning nothing.
FramePlan framePlan(ProjectionEngine engine, Projection projection, {Tunable? read}) {
  final primary = projection.primaryFrame;
  if (primary == null) {
    return (lines: const [], refused: const [], supported: false);
  }
  final budget = count(read, 'lines.companions');
  final lines = <LinePlan>[], refused = <LineRefusal>[];
  for (final id in projection.frames) {
    final frame = engine.document.frames[id];
    final title = frame?.title ?? id;
    if (frame == null) {
      refused.add((frame: id, message: 'No frame named $id is in this document.'));
      continue;
    }
    if (engine.windowFrameFor(id) == null && id != primary) {
      refused.add((
        frame: id,
        message: '$title owns no coordinate axis, so it cannot be drawn as a line.',
      ));
      continue;
    }
    if (lines.length > budget) {
      refused.add((frame: id, message: '$title is beyond the drawn line budget.'));
      continue;
    }
    lines.add((frame: id, title: title, index: lines.length, prime: id == primary));
  }
  return (lines: lines, refused: refused, supported: lines.isNotEmpty);
}

/// The apex ladder: how far a companion's arc bows away from the prime line.
/// Alternating sides so companions read as a weave rather than a stack, and
/// stepping outward so two companions never share an apex.
double apexOffset(int index, {required double first, required double step}) {
  if (index == 0) return 0;
  final rung = (index - 1) ~/ 2;
  final side = index.isOdd ? -1 : 1;
  return side * (first + rung * step);
}

/// The y of a companion's weave at a progress fraction, between two pinned
/// staple points. A sine bow, so the line leaves and rejoins the prime line
/// tangentially instead of kinking at each staple.
double weaveAt(double progress, double primeY, double apex) =>
    primeY + apex * math.sin(progress * math.pi);

/// One point on a line, before fanning.
typedef LinePoint = ({String id, String eventId, double x, int line});

/// The same point after its cluster has been fanned.
typedef FannedPoint = ({String id, String eventId, double x, int line, double offset, int cluster});

/// Fans coincident points rather than hiding a cluster.
///
/// Points closer than the cluster width become one cluster, ordered inside it by
/// event id then point id -- a STABLE tie-break, meaningless but identical
/// across reload -- and spread symmetrically about their own centre, capped so a
/// crowd never runs off its line. Every point in a cluster stays individually
/// reachable, which is the whole reason not to collapse them into a count.
List<FannedPoint> fanPoints(List<LinePoint> points, {required double pixelSpan, Tunable? read}) {
  final width = pixels(read, 'lines.clusterPixels');
  final spread = pixels(read, 'lines.fanSpread');
  final step = pixels(read, 'lines.fanStep');
  final ordered = [...points]
    ..sort((a, b) {
      final byX = a.x.compareTo(b.x);
      if (byX != 0) return byX;
      final byEvent = a.eventId.compareTo(b.eventId);
      return byEvent != 0 ? byEvent : a.id.compareTo(b.id);
    });
  final clusters = <List<LinePoint>>[];
  var lastX = double.negativeInfinity;
  for (final point in ordered) {
    if (clusters.isEmpty || (point.x - lastX) * pixelSpan > width) {
      clusters.add([point]);
    } else {
      clusters.last.add(point);
    }
    lastX = point.x;
  }
  final fanned = <FannedPoint>[];
  for (final cluster in clusters) {
    final members = [...cluster]
      ..sort((a, b) {
        final byEvent = a.eventId.compareTo(b.eventId);
        return byEvent != 0 ? byEvent : a.id.compareTo(b.id);
      });
    final size = members.length;
    for (final (index, point) in members.indexed) {
      final raw = size == 1 ? 0.0 : (index - (size - 1) / 2) * step;
      fanned.add((
        id: point.id,
        eventId: point.eventId,
        x: point.x,
        line: point.line,
        offset: raw < -spread ? -spread : (raw > spread ? spread : raw),
        cluster: size,
      ));
    }
  }
  return fanned;
}

/// A staple mark: one object present on two or more drawn lines, which is
/// exactly where those lines are pinned together.
typedef StapleMark = ({String eventId, List<String> frames, List<double> progress});

/// Every shared incidence among the drawn lines: an object placed on more than
/// one of them, and where it sits on each. THE ONLY thing that relates two
/// lines; nothing else here draws a connection.
List<StapleMark> sharedMarks(
  ProjectionEngine engine,
  Iterable<Fact> facts,
  List<LinePlan> lines,
  Rational start,
  Rational end,
) {
  final drawn = {for (final line in lines) line.frame};
  final byEvent = <String, Map<String, Rational>>{};
  for (final fact in facts) {
    final frame = fact.relation.frame;
    if (frame == null || !drawn.contains(frame)) continue;
    (byEvent[fact.event.id] ??= {})[frame] = fact.day;
  }
  final marks = <StapleMark>[];
  for (final entry in byEvent.entries) {
    if (entry.value.length < 2) continue;
    final frames = entry.value.keys.toList()..sort();
    final progress = [
      for (final frame in frames)
        if (lineProgress(entry.value[frame]!, start, end) case final double at) at,
    ];
    if (progress.length == frames.length) {
      marks.add((eventId: entry.key, frames: frames, progress: progress));
    }
  }
  return marks..sort((a, b) => a.eventId.compareTo(b.eventId));
}

/// The AUTHORED topology: which frames are adjacent, and only because somebody
/// stapled them or placed one object on both.
///
/// Breadth-first from the primary so the drawn set is the neighbourhood of what
/// is being looked at, and bounded by the same line budget: whole-graph is the
/// pile, and the pile hides everything by showing everything.
List<String> topologyFrames(ProjectionEngine engine, String primary, {Tunable? read}) {
  final budget = count(read, 'lines.companions');
  final adjacent = <String, Set<String>>{};
  void connect(String left, String right) {
    if (left == right) return;
    (adjacent[left] ??= <String>{}).add(right);
    (adjacent[right] ??= <String>{}).add(left);
  }

  for (final relation in engine.document.relations.values) {
    if (relation.type != 'staple') continue;
    final frames = [
      for (final end in engine.indexes.endsOf(relation))
        if (end is FrameEnd) end.frame,
    ];
    for (final left in frames) {
      for (final right in frames) {
        connect(left, right);
      }
    }
  }
  for (final event in engine.document.events.keys) {
    final frames = engine.indexes.framesOf(event);
    for (final left in frames) {
      for (final right in frames) {
        connect(left, right);
      }
    }
  }
  final found = <String>[];
  final seen = <String>{};
  final queue = [primary];
  while (queue.isNotEmpty && found.length <= budget) {
    final id = queue.removeAt(0);
    if (!seen.add(id) || !engine.document.frames.containsKey(id)) continue;
    found.add(id);
    queue.addAll((adjacent[id] ?? const <String>{}).toList()..sort());
  }
  return found;
}
