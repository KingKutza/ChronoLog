// THE RULE LADDER: one function of pixels-per-unit, run in BOTH directions, and
// TWO-TIER at every rung.
//
// Don, 2026-08-28: "as I zoom out, lines dividing a day decrease to maintain
// clarity; as I zoom in so that an hour or minute fills the screen I don't get
// new more granular lines to split the screen." Extended 2026-08-31: "every rung
// pairs a major and a minor unit with clear visual delineation between them" --
// at rest minors at the authored increment and majors at the hour, zoomed in
// majors 15m and minors 5m, zoomed out majors at the week and minors at the day.
// Some rungs may be majors-only, but NEVER a flat undifferentiated tone.
//
// So a rung is a PAIR, and choosing one is one function of how many pixels a
// unit spans: the minor is the finest authored increment that still clears its
// target spacing, and the major is the next increment that clears the wider
// target AND is a whole number of minors -- which is what makes the delineation
// readable rather than decorative. Past either end of the authored ladder the
// steps halve and double, so there is no zoom at which the surface stops
// subdividing or starts drawing one grey block.
//
// NO LITERALS. Every increment and both target spacings are settings keys; the
// unit the ladder is asked in belongs to the caller's law (Intimate asks in ITS
// hours, a day grid in ITS days), so a hundred-minute hour subdivides too.
//
// THE TIERS DIFFER BY THEME, never by colour: the minor is the hairline every
// seam is drawn in and the major the secondary-text tone, both at widths and
// opacities that are settings. Colour carries authored frame and group meaning
// alone.

import 'package:flutter/widgets.dart';

import '../core/exact.dart';
import 'theme.dart';
import 'tunables.dart';

/// Every number the ladder draws with. Spread into the grid area's defaults, so
/// one composed settings map still answers for it.
const Map<String, String> ladderTunableDefaults = {
  // What one MINOR rule should span on screen, and what one MAJOR should. The
  // pair is the whole two-tier ruling stated as two numbers, and the two of them
  // are what puts the shipped rest state where Don named it: at Intimate's own
  // row height the minors land on the quarter hour and the majors on the hour,
  // three times in the minors go to five minutes with majors at the quarter, and
  // zoomed out to a day of a dozen pixels the minors are days and the majors the
  // law's own week.
  'rule.minorSpacing': '8',
  'rule.majorSpacing': '30',
  // A label is only offered where a rule of that tier has this much room.
  'rule.labelSpacing': '34',
  'rule.minor': '1',
  'rule.major': '1',
  'rule.minorOpacity': '0.42',
  'rule.majorOpacity': '0.8',
  // How far past the ends of the authored ladder the search may double or
  // halve. A bound, not a limit on zoom: it is spent per rung, not per lens.
  'rule.extension': '24',
};

/// One rung of the ladder: what a MAJOR rule spans and what a MINOR one does, in
/// whatever unit the ladder was asked in. Never equal -- a rung with one tier is
/// the flat tone the ruling forbids.
typedef Rung = ({Rational major, Rational minor});

Rational get _two => Rational.fromInt(2);

/// The authored increments of one ladder family, ascending. Written as a family
/// of keys (`intimate.ruleLadder.01`...) so the count and the steps are both
/// settings and neither is a literal in a lens.
List<Rational> ladderSteps(Rational Function(String key) read, String prefix, String countKey) {
  final steps = <Rational>[];
  final count = read(countKey).round().toInt();
  for (var rung = 1; rung <= count; rung += 1) {
    final step = read('$prefix${'$rung'.padLeft(2, '0')}');
    if (step > Rational.zero) steps.add(step);
  }
  steps.sort((a, b) => a.compareTo(b));
  return steps;
}

/// THE LADDER. [unitPixels] is how many pixels one ladder unit spans right now;
/// [steps] are the authored increments in that unit, and [extra] are increments
/// the caller's LAW supplies rather than settings -- its day, its week, its
/// month -- so the rungs above a day are the calendar's own and not ours.
///
/// Both directions, always two tiers.
Rung rungFor({
  required double unitPixels,
  required double minorTarget,
  required double majorTarget,
  required List<Rational> steps,
  List<Rational> extra = const [],
  int reach = 24,
}) {
  final minorWanted = minorTarget <= 0 ? 0.0 : minorTarget;
  final majorWanted = majorTarget < minorWanted ? minorWanted : majorTarget;
  final rungs = <Rational>[
    for (final step in [...steps, ...extra])
      if (step > Rational.zero) step,
  ]..sort((a, b) => a.compareTo(b));
  if (unitPixels <= 0 || rungs.isEmpty) {
    return (major: Rational.one, minor: Rational.one / _two);
  }
  double span(Rational step) => step.toDouble() * unitPixels;
  // BELOW the ladder: halve while a finer step still clears the minor target,
  // which is how an hour that fills the screen keeps subdividing.
  var finest = rungs.first;
  for (var step = 0; step < reach && span(finest / _two) >= minorWanted; step += 1) {
    finest /= _two;
    rungs.insert(0, finest);
  }
  // ABOVE it: double while the coarsest step still does not reach the major
  // target, which is how a screen holding years stops ruling every day.
  var coarsest = rungs.last;
  for (var step = 0; step < reach && span(coarsest) < majorWanted; step += 1) {
    coarsest *= _two;
    rungs.add(coarsest);
  }
  final minor = rungs.firstWhere((step) => span(step) >= minorWanted, orElse: () => rungs.last);
  for (final step in rungs) {
    if (step <= minor || span(step) < majorWanted) continue;
    // A whole number of minors, or the delineation reads as noise.
    if ((step % minor).isZero) return (major: step, minor: minor);
  }
  // Nothing on the ladder pairs with this minor, so the major is the smallest
  // whole multiple of it that clears the target: two tiers, always.
  final room = span(minor);
  final times = room <= 0
      ? 2
      : Rational.parse((majorWanted / room).toStringAsFixed(9)).ceil().toInt();
  return (major: minor * Rational.fromInt(times < 2 ? 2 : times), minor: minor);
}

/// Is the rule at [at] a major one? Exact arithmetic, so a boundary is a
/// boundary and not a rounding.
bool isMajorRule(Rational at, Rung rung) =>
    rung.major <= Rational.zero || (at % rung.major).isZero;

/// One ladder setting, against the ladder's OWN defaults: a surface reading
/// these has no business knowing which composed map they were spread into.
double ladderPixels(Tunable? read, String key) =>
    tunableFrom(ladderTunableDefaults, read, key).toDouble();

/// The two pens. THE DIFFERENCE IS THE THEME'S: the hairline every seam uses for
/// the minor, the secondary-text tone for the major.
({Paint major, Paint minor}) rulePens(ChronoTheme theme, Tunable? read) => (
  major: Paint()
    ..strokeWidth = ladderPixels(read, 'rule.major')
    ..color = theme.strong.withValues(alpha: ladderPixels(read, 'rule.majorOpacity')),
  minor: Paint()
    ..strokeWidth = ladderPixels(read, 'rule.minor')
    ..color = theme.hair.withValues(alpha: ladderPixels(read, 'rule.minorOpacity')),
);

/// The tone a label of each tier is written in -- the same two-tier reading the
/// rules carry, so a label never contradicts the line it names.
({Color major, Color minor}) labelTones(ChronoTheme theme) => (
  major: theme.strong,
  minor: theme.muted,
);
