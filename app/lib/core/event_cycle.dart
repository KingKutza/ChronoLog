// Event-defined cycles.
//
// A cycle whose period is OBSERVED rather than declared contains occurrences, not
// a mean duration: `at` is an exact coordinate in the period's own frame, and a
// boundary may name the event whose observation established it.
//
// THE FINITE AUTHORED SERIES IS THE AUTHORITY. There is no extrapolation before
// the first boundary or after the last, and no averaging in either direction --
// asked for a cycle outside the authored window, this refuses. An observed lunar
// month is 29.31 days here and 29.61 there, and replacing either with the mean
// synodic month would be inventing an observation nobody made.
//
// Refusals travel as the coordinate-law layer's own [Attempt], so "resolved, or
// the author's sentence about why not" has one shape across the model.

import 'coordinate_law.dart';
import 'eras.dart';
import 'exact.dart';
import 'records.dart';

/// One authored boundary: its own id, the exact coordinate it sits at, and the
/// observed event that established it when one is named.
typedef Boundary = ({String id, Rational at, String? event});

/// The authored series, and whose units its coordinates are in.
typedef BoundarySeries = ({String frame, List<Boundary> boundaries});

/// One authored interval, `[start, end)`. Its period is the SUBTRACTION of two
/// observations, never a mean.
class EventCycle {
  const EventCycle(this.series, this.index);

  final BoundarySeries series;
  final int index;

  Boundary get boundary => series.boundaries[index];
  Boundary get next => series.boundaries[index + 1];
  Rational get start => boundary.at;
  Rational get end => next.at;
  Rational get period => end - start;
}

/// A window made only from authored ADJACENT intervals, for the radial and
/// spiral lenses.
typedef CycleWindow = ({
  EventCycle cycle,
  Rational start,
  Rational end,
  int firstIndex,
  int lastIndex,
});

Rational _exact(Object? value) => value is Rational ? value : Rational.parse(declaredText(value));

Attempt<BoundarySeries> eventBoundarySeries(Json? period) {
  if (declaredText(period?['kind']) != 'event-defined') {
    return const Refused('not an event-defined period');
  }
  final frame = declaredText(period?['frame']);
  if (frame.isEmpty) {
    return const Refused('event-defined period needs a boundary frame');
  }
  final rows = asList(period!['boundaries']);
  if (rows.length < 2) {
    return const Refused('event-defined period needs at least two explicit boundaries');
  }
  final ids = <String>{};
  final boundaries = <Boundary>[];
  for (final (index, row) in rows.indexed) {
    final entry = asMap(row);
    final id = declaredText(entry?['id']);
    if (id.isEmpty) return Refused('boundary ${index + 1} needs an id');
    if (!ids.add(id)) return Refused('boundary ids must be unique ($id)');
    final Rational at;
    try {
      at = _exact(entry?['at']);
    } catch (_) {
      return Refused('boundary $id needs an exact finite coordinate');
    }
    if (boundaries.isNotEmpty && at <= boundaries.last.at) {
      return const Refused('event-defined boundaries must be strictly ordered and unambiguous');
    }
    boundaries.add((
      id: id,
      at: at,
      event: entry?['event'] is String ? entry!['event'] as String : null,
    ));
  }
  return Resolved((frame: frame, boundaries: boundaries));
}

/// The one authored interval containing [focus], using `[start, end)`.
Attempt<EventCycle> resolveEventCycle(Json? period, Object? focus) {
  final series = eventBoundarySeries(period);
  final resolved = series.resolved;
  if (resolved == null) return Refused(series.refusal!);
  final Rational at;
  try {
    at = _exact(focus);
  } catch (_) {
    return const Refused('focus must be an exact coordinate');
  }
  final boundaries = resolved.boundaries;
  for (var cursor = 0; cursor < boundaries.length - 1; cursor += 1) {
    if (at >= boundaries[cursor].at && at < boundaries[cursor + 1].at) {
      return Resolved(EventCycle(resolved, cursor));
    }
  }
  return const Refused('focus is outside the authored boundary window');
}

/// Move by authored intervals. Reverse traversal never infers a predecessor, and
/// stepping past either end of the series refuses rather than extrapolating.
Attempt<EventCycle> stepCycle(EventCycle cycle, int direction) {
  if (direction == 0) {
    return const Refused('cycle step must be a non-zero whole number');
  }
  final index = cycle.index + direction;
  if (index < 0 || index >= cycle.series.boundaries.length - 1) {
    return const Refused('requested cycle is outside the authored boundary window');
  }
  return Resolved(EventCycle(cycle.series, index));
}

Attempt<EventCycle> stepEventCycle(Json? period, Object? focus, [int direction = 1]) {
  final current = resolveEventCycle(period, focus);
  final cycle = current.resolved;
  return cycle == null ? current : stepCycle(cycle, direction);
}

/// A finite radial/spiral window: [past] intervals before the focus and [future]
/// after it, refused outright when the authored series does not reach that far.
Attempt<CycleWindow> eventCycleWindow(Json? period, Object? focus, {int past = 0, int future = 0}) {
  final current = resolveEventCycle(period, focus);
  final cycle = current.resolved;
  if (cycle == null) return Refused(current.refusal!);
  final first = cycle.index - (past < 0 ? 0 : past);
  final last = cycle.index + (future < 0 ? 0 : future) + 1;
  if (first < 0 || last >= cycle.series.boundaries.length) {
    return const Refused('requested window exceeds authored boundaries');
  }
  return Resolved((
    cycle: cycle,
    start: cycle.series.boundaries[first].at,
    end: cycle.series.boundaries[last].at,
    firstIndex: first,
    lastIndex: last - 1,
  ));
}
