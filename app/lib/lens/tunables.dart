// NO LITERALS IN LENSES OR CHROME (ruled 2026-08-28). Every tunable -- pixel
// size, threshold, budget, spacing, duration, snap point, half-distance, label
// cap -- is a NAMED SETTING whose shipped default is an expression string in the
// one math (`core/math.dart`). The only bare numbers left in a lens are
// arithmetic identity: zero, one, two for halving, and pi.
//
// "Enum is the enemy": a default is data, so a setting the author disagrees with
// is a line in `chronolog.settings`, never a recompile.
//
// THE SEAM. Every area declares its own `<area>TunableDefaults` map beside the
// code that reads it; the session composes them all and supplies one [Tunable].
// Nothing here reads a file, and nothing here caches -- memoization belongs to
// whoever owns the settings file, because only it knows when a key changed.

import '../core/exact.dart';
import '../core/math.dart';
import 'minimap/tunables.dart';

/// Reads one setting by dotted lowercase key. Total by contract: the composer
/// falls back to the shipped default, so a lens never handles a miss.
typedef Tunable = Rational Function(String key);

/// The value of [key]: from [read] when a session supplies one, otherwise the
/// shipped default evaluated through the one math.
Rational tunable(Tunable? read, String key) =>
    read != null ? read(key) : tunableFrom(lensTunableDefaults, null, key);

/// The same read against an arbitrary defaults map, for an area whose keys this
/// file has never heard of. A key in no map at all is a REFUSAL naming the key:
/// silently substituting a zero is how a surface renders wrong instead of
/// saying so.
Rational tunableFrom(Map<String, String> defaults, Tunable? read, String key) {
  if (read != null) return read(key);
  final expression = defaults[key];
  if (expression == null) throw MathRefusal('No setting named $key');
  final value = evaluateSource(expression, const Env());
  if (value is! Rational) throw MathRefusal('Setting $key must be a number');
  return value;
}

/// Convenience for the overwhelmingly common pixel read. Host doubles are for
/// pixels only and never re-enter document math.
double pixels(Tunable? read, String key) => tunable(read, key).toDouble();

int count(Tunable? read, String key) => tunable(read, key).round().toInt();

/// Every number the lens layer draws with. Keys are dotted lowercase; values are
/// expressions, so a default may state its own arithmetic (`24 * 12`) rather
/// than hide it in a computed constant.
const Map<String, String> lensTunableDefaults = {
  // --- Motion (ratified 220ms cubic-bezier(.25,.9,.25,1)) -------------------
  'motion.duration': '220',
  'motion.curve.x1': '0.25',
  'motion.curve.y1': '0.9',
  'motion.curve.x2': '0.25',
  'motion.curve.y2': '1',

  // --- The one overscale budget --------------------------------------------
  // Capacity is screen space divided by mark footprint, times how many marks
  // deep a surface will stack them. No integer cap anywhere.
  'capacity.markWidth': '92',
  'capacity.markHeight': '18',
  'capacity.stackDepth': '3',
  'capacity.floor': '8',
  'capacity.queryMultiple': '2',

  // --- Weight, falloff, promotion ------------------------------------------
  'weight.halfDistanceDays': '7',
  'weight.importantAt': '2',
  'weight.landmarkAt': '4',
  'falloff.bucket1': '0.75',
  'falloff.bucket2': '0.5',
  'falloff.bucket3': '0.25',
  'falloff.opacity1': '0.78',
  'falloff.opacity2': '0.58',
  'falloff.opacity3': '0.42',

  // --- Marks ----------------------------------------------------------------
  'mark.pip': '6',
  'mark.stroke': '1.5',
  'mark.strokeStrong': '2.5',
  'mark.dashOn': '2',
  'mark.dashOff': '1',
  'mark.dotOn': '1',
  'mark.dotOff': '3',
  'mark.doneOpacity': '0.62',
  'mark.sparseOpacity': '0.55',
  'mark.overflowScale': '0.9',

  // --- Zones ----------------------------------------------------------------
  'zone.default': '0',
  'zone.fill': '0.24',
  'zone.edge': '0.42',
  'zone.radius': '7',
  'zone.rule': '2',

  // --- Selection (an ink ring, never a color) -------------------------------
  'selection.inner': '2',
  'selection.ring': '4',
  'selection.ringOpacity': '0.28',

  // --- Now ------------------------------------------------------------------
  'now.width': '2.5',
  'now.halo': '2',

  // --- Lanes ----------------------------------------------------------------
  'lane.gap': '2',
  'lane.minWidth': '18',

  // --- Minimap --------------------------------------------------------------
  // The wave's own numbers live beside the painter that reads them; the rest of
  // the minimap's settings are here with every other lens number.
  ...minimapTunableDefaults,
  'minimap.rangeMultiple': '5',
  'minimap.bandLow': '0.12',
  'minimap.bandHigh': '0.88',
  'minimap.anchorLow': '0.25',
  'minimap.anchorHigh': '0.75',
  'minimap.bins': '288',
  'minimap.busyQuantile': '0.9',
  // The scale ladder, generated: powers of the base interleaved with the
  // half-step multiple is the 1 2 3 4 6 8 12 16 ... sequence, authored as three
  // settings rather than tabulated as twenty numbers nobody can edit.
  'minimap.ladderBase': '2',
  'minimap.ladderHalfStep': '3',
  'minimap.ladderRungs': '20',
  'minimap.particles': '5200',
  'minimap.particleRadius': '0.7',
  'minimap.driftSeconds': '18',
  'minimap.driftAmplitude': '1.5',
  'minimap.baselineOpacity': '0.46',
  'minimap.unlitOpacity': '0.2',
  'minimap.litOpacity': '0.82',
  'minimap.labelInset': '3',
  'minimap.labelSize': '9',
  'minimap.windowStroke': '1.25',
  'minimap.focusStroke': '1.4',
  'minimap.budget.hour': '12',
  'minimap.budget.day': '16',
  'minimap.budget.month': '14',
  'minimap.budget.quarter': '18',
  'minimap.budget.fallback': '12',

  // --- Radial and Spiral ----------------------------------------------------
  'radial.outerRadius': '278',
  'radial.innerRadius': '58',
  'radial.ribbonWidth': '20',
  'radial.samplesPerTurn': '96',
  'radial.divisionsMax': '64',
  'radial.hourCycleDays': '5',
  'radial.weekCycleDays': '20',
  'radial.majorWeek': '7',
  'radial.majorQuarter': '4',
  'radial.tickPlain': '1',
  'radial.tickMajor': '1.5',
  'radial.tickStrong': '2',
  'radial.noonTick': '2.5',
  'radial.labelHalo': '3',
  'radial.labelGapY': '15',
  'radial.labelGapX': '145',
  'radial.arcWidth': '7',
  'radial.monthCycleMax': '24',

  // --- Lines ----------------------------------------------------------------
  'lines.clusterPixels': '16',
  'lines.fanSpread': '18',
  'lines.fanStep': '8',
  'lines.apexFirst': '75',
  'lines.apexStep': '52',
  'lines.companions': '8',
  'lines.axisTicks': '8',
  'lines.stapleDashOn': '4',
  'lines.stapleDashOff': '3',
  'lines.dotRadius': '4',
  'lines.sharedDotRadius': '6',
};
