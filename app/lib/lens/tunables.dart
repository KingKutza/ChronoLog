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

/// Reads one setting by dotted lowercase key. The composer falls back to the
/// shipped default, so a lens never handles a miss -- and a key NO map declares
/// is a refusal naming it, raised here and at [Settings.value] alike, rather
/// than a zero the surface would draw with. A lens still handles no miss; what
/// changed is that a composer's omission says so instead of rendering wrong.
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
  // HOW FAR INSIDE THE SURFACE THE ARMED PICK'S READOUT SITS (ISSUES 9.2). Its
  // own key: the readout was borrowing `pointer.refusalPad`, which is how far a
  // refusal sits from an edge, and two things that happen to want the same
  // number are still two things -- move one and the other moves with it for no
  // reason anybody could state.
  'pick.readoutInset': '12',
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
  // EVERY minimap number lives beside the painter that reads it, and is spread
  // in here so the lens layer still answers for one composed map. Four keys
  // that nothing read at all -- a drift the painter never had and two opacities
  // it replaced -- are gone: a shipped default for a setting no surface reads
  // is a promise the settings card would make and nothing would keep.
  ...minimapTunableDefaults,

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

/// EVERY LENS SETTING WHOSE VALUE IS AN EQUATION rather than a number, composed
/// as one name so the session adds a family and not a file. Kept apart from
/// [lensTunableDefaults] because that map's promise -- every value evaluates, by
/// itself, to a number -- is one these cannot keep and should not have to: their
/// variables are bound by whoever asks, at the moment of asking.
const Map<String, String> lensFormulaDefaults = {...minimapFormulaDefaults};
