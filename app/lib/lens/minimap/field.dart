// The minimap's activity field: a sliding range, an exact magnitude
// accumulation, and a scale that does not shimmer.
//
// THE MINIMAP IS NAVIGATION CHROME, NOT A SECOND EVENT LIST. It reads the
// engine's already-indexed explicit facts by binary search over their day order
// and never triggers a second recurrence expansion -- which is the whole reason
// it stays cheap at 500 calendars.
//
// HYSTERESIS. The range is a multiple of the visible span; while the focus stays
// inside a band the range does not move, and outside it re-anchors to a stated
// fraction. Without that the field slides under the pointer on every pan frame
// and the eye can never fix on anything.
//
// THE LADDER. A field renormalized to its own maximum would reshuffle its scale
// on every pan, and one landmark would flatten everything else. So the ceiling
// snaps to a coarse ladder chosen from the field's BUSY END rather than its
// maximum, and between rungs the mapping is exactly position-independent: equal
// activity reads identically wherever it sits.

import '../../core/exact.dart';
import '../../core/projection.dart';
import '../../core/staples.dart';
import '../tunables.dart';

/// The window the field covers. Wider than what the lens shows, so there is
/// context on both sides of the view box.
typedef MinimapRange = ({Rational start, Rational end});

/// The range for this focus and span, re-anchored only when the focus leaves
/// the band. Pass the current range to keep it; pass null for a first paint.
MinimapRange slideRange(MinimapRange? current, Rational focus, Rational span, Tunable? read) {
  final width = span * tunable(read, 'minimap.rangeMultiple');
  if (current != null && current.end - current.start == width) {
    final where = (focus - current.start) / width;
    final low = tunable(read, 'minimap.bandLow'), high = tunable(read, 'minimap.bandHigh');
    if (where >= low && where <= high) return current;
    final anchor = where < low
        ? tunable(read, 'minimap.anchorLow')
        : tunable(read, 'minimap.anchorHigh');
    final start = focus - width * anchor;
    return (start: start, end: start + width);
  }
  final start = focus - width / Rational.fromInt(2);
  return (start: start, end: start + width);
}

/// ONE placed fact, kept so a quiet stretch can be COUNTED rather than
/// estimated. Don, with four events in a cluster: "why aren't there four dots".
typedef Mote = ({Rational day, double weight, int hash});

/// A hash of a fact's identity that is the same on every run. A String's own
/// hashCode is not promised to be, and a mote whose place in its cluster moved
/// between runs would be a different picture of the same document.
int stableHash(String text) {
  var hash = 0x811c9dc5;
  for (final unit in text.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0x3fffffff;
  }
  return hash;
}

/// The accumulated field: one magnitude and one object count per bin, plus the
/// ladder rung the scale snapped to, and the placed facts themselves while
/// there are few enough of them to draw one by one.
class MinimapField {
  MinimapField(
    this.magnitudes,
    this.counts,
    this.ceiling,
    this.range, {
    this.motes = const [],
    this.present = const [],
  });

  final List<double> magnitudes;
  final List<int> counts;
  final double ceiling;
  final MinimapRange range;

  /// Facts PLACED in this bin, capped at one more than the countable threshold:
  /// a bin holding more than that is dense by definition, so the rest are never
  /// needed and never stored, and the cap is what keeps this bounded at scale.
  final List<List<Mote>> motes;

  /// How many are placed there in truth, uncapped -- what the regime is decided
  /// on, so a truncated bin can never be mistaken for a countable one.
  final List<int> present;

  List<Mote> motesAt(int bin) => bin < motes.length ? motes[bin] : const [];

  int presentAt(int bin) => bin < present.length ? present[bin] : 0;

  int get bins => magnitudes.length;

  /// The bin's share of the ceiling, clamped -- saturation is deliberate,
  /// because saturation is what makes "busy" read instantly.
  double level(int bin) {
    final value = ceiling <= 0 ? 0.0 : magnitudes[bin] / ceiling;
    return value > 1 ? 1 : value;
  }

  /// A bin holding objects can never read as empty: the count is a floor under
  /// the magnitude, so one short unweighted object still lights its bin.
  double heightAt(int bin) {
    final floor = counts[bin] == 0 ? 0.0 : 1 / (bins.toDouble());
    final value = level(bin);
    return value > floor ? value : floor;
  }
}

/// One object's contribution: its own presence, every connection it carries, and
/// how long it lasts, scaled by its composed display weight. Structure earns
/// magnitude, which is why a heavily stapled object reads heavier than a bare
/// one of the same length.
double magnitudeOf(ProjectionEngine engine, Projection projection, Fact fact) {
  // FLAGGED (core zone, ruled 2026-09-01): "every connection it carries" means
  // every connection BEYOND the one that puts it here. A placement is a staple
  // now, and `Rational.one` below is already its own presence -- counting the
  // placement again would say every object is structured merely by existing.
  final staples = engine.indexes
      .staplesOf(fact.event.id)
      .where((staple) => !isPlacement(staple, fact.event.id))
      .length;
  final duration = engine.eventDurationDays(fact.event);
  final weight = engine.weightOf(fact, projection).weight;
  return (Rational.one + Rational.fromInt(staples) + duration).toDouble() * weight.toDouble();
}

/// Accumulates the field over [range].
///
/// A span's magnitude is DIVIDED across the bins it occupies, so it counts
/// everywhere it is present without inflating the total -- a week-long event is
/// a week of presence, not seven events.
MinimapField accumulate(
  ProjectionEngine engine,
  Projection projection,
  MinimapRange range,
  Tunable? read,
) {
  final bins = count(read, 'minimap.bins');
  final magnitudes = List.filled(bins, 0.0);
  final counts = List.filled(bins, 0);
  final present = List.filled(bins, 0);
  final motes = [for (var bin = 0; bin < bins; bin += 1) <Mote>[]];
  final cap = count(read, 'minimap.countable') + 1;
  final width = range.end - range.start;
  if (width > Rational.zero) {
    final sources = <String>{
      for (final frameId in projection.frames) ...engine.indexes.frameClosure(frameId),
    };
    final seen = <String>{};
    for (final source in sources) {
      final facts = engine.explicitFacts(source);
      for (var index = _lowerBound(facts, range.start); index < facts.length; index += 1) {
        final fact = facts[index];
        if (fact.day > range.end) break;
        if (!seen.add(fact.identity)) continue;
        _spread(engine, projection, fact, range, width, magnitudes, counts, present, motes, cap);
      }
    }
  }
  return MinimapField(
    magnitudes,
    counts,
    ceilingFor(magnitudes, read),
    range,
    motes: motes,
    present: present,
  );
}

void _spread(
  ProjectionEngine engine,
  Projection projection,
  Fact fact,
  MinimapRange range,
  Rational width,
  List<double> magnitudes,
  List<int> counts,
  List<int> present,
  List<List<Mote>> motes,
  int cap,
) {
  final bins = magnitudes.length;
  final end = fact.day + engine.eventDurationDays(fact.event);
  final from = _bin((fact.day - range.start) / width, bins);
  final to = _bin((end - range.start) / width, bins);
  final occupied = to - from + 1;
  final share = magnitudeOf(engine, projection, fact) / occupied;
  // The mote goes where the fact is PLACED, once: a span is one thing that
  // happened, so counting its bins would be counting it seven times.
  present[from] += 1;
  if (motes[from].length < cap) {
    motes[from].add((
      day: fact.day,
      weight: engine.weightOf(fact, projection).weight.toDouble(),
      hash: stableHash(fact.identity),
    ));
  }
  for (var bin = from; bin <= to; bin += 1) {
    magnitudes[bin] += share;
    counts[bin] += 1;
  }
}

int _bin(Rational fraction, int bins) {
  final index = (fraction * Rational.fromInt(bins)).floor().toInt();
  return index < 0 ? 0 : (index >= bins ? bins - 1 : index);
}

/// Binary search into the day-sorted explicit index. The facts are already
/// ordered by the engine, so the minimap pays a log rather than a scan per frame.
int _lowerBound(List<Fact> facts, Rational day) {
  var low = 0, high = facts.length;
  while (low < high) {
    final middle = (low + high) >> 1;
    if (facts[middle].day < day) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low;
}

/// The coarse scale ladder, GENERATED rather than tabulated: powers of the base,
/// interleaved with the half-step multiple, which is the 1 2 3 4 6 8 12 16 …
/// sequence. A ladder written out as twenty numbers is twenty numbers nobody can
/// edit; two settings and a count is the same ladder, authored.
List<double> magnitudeLadder(Tunable? read) {
  final base = tunable(read, 'minimap.ladderBase').toDouble();
  final step = tunable(read, 'minimap.ladderHalfStep').toDouble();
  final rungs = count(read, 'minimap.ladderRungs');
  final values = <double>{};
  for (var power = 0; power < rungs; power += 1) {
    final rung = _pow(base, power);
    values.addAll([rung, rung * step]);
  }
  final sorted = values.toList()..sort();
  return sorted.sublist(0, rungs < sorted.length ? rungs : sorted.length);
}

double _pow(double base, int power) {
  var value = 1.0;
  for (var index = 0; index < power; index += 1) {
    value *= base;
  }
  return value;
}

/// The rung the field's busy end sits on. The QUANTILE, not the maximum: one
/// exceptional bucket must not squash the rest of the field, and buckets at or
/// above the rung saturate on purpose.
double ceilingFor(List<double> magnitudes, Tunable? read) {
  final ladder = magnitudeLadder(read);
  final occupied = [
    for (final value in magnitudes)
      if (value > 0) value,
  ]..sort();
  if (occupied.isEmpty) return ladder.first;
  final quantile = tunable(read, 'minimap.busyQuantile').toDouble().clamp(0.0, 1.0);
  final index = (quantile * occupied.length).floor().clamp(0, occupied.length - 1);
  final busy = occupied[index];
  for (final rung in ladder) {
    if (rung >= busy) return rung;
  }
  return ladder.last;
}
