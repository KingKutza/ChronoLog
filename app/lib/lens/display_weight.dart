// THE BLESSED CHAIN, reaching the surface (Don, 2026-08-27, ruling 10).
//
// Nesting, inside out: the object's own authored math; connected modifying
// frames by increasing graph distance, nearest first, ties broken by stable id;
// the PROJECTING frame last among frames, because uniform monotone math applied
// last cannot reorder the view, which is what "matters least" requires; then
// apparent-magnitude falloff as the projector's own closing step.
//
// NOT-terms gate visibility and NEVER modify weight -- enforced inside
// `composeWeight`, which is handed the mark rather than a filtered list.
//
// FALLOFF APPLIES TO UNRESOLVED OBJECTS ONLY. An object somebody has said a
// status about never fades: its state grammar already says what it is, and
// fading it would say the same thing twice and less clearly. Which status it is
// does not enter into it -- Done is a frame like any other (ISSUES 9.2) -- so
// the question asked is whether it is in a state frame at all. A law with no
// clock mapping has no honest distance from now, so it has no falloff either.
//
// The derivation comes back WHOLE -- every ring, in order -- because the card's
// explainer has to show how a weight was reached, not just what it came to.

import '../core/exact.dart';
import '../core/math.dart';
import '../core/object_kinds.dart';
import '../core/projection.dart';
import '../core/records.dart';
import '../core/staples.dart';
import '../core/weight.dart';
import 'lens_painter.dart';
import 'marks.dart';
import 'tunables.dart';

/// The three-way promotion vocabulary every importance-driven treatment reads.
const String standardWeight = 'standard', importantWeight = 'important';
const String landmarkWeight = 'landmark';

/// One mark's weight and how it got there, plus what falls out of it: the
/// promotion verdict, the falloff bucket, and the state modifier.
typedef DisplayWeight = ({
  Rational weight,
  List<WeightStep> rings,
  String promotion,
  String state,
  int? bucket,
});

/// State, from the ONE derivation (`stateAffiliations` in object_kinds.dart).
///
/// DONE IS A FRAME LIKE ANY OTHER (ISSUES 9.2, Don's question on Done). This
/// reader used to say `done` when the object's state frame was the hard-coded
/// one and `closed` when it was any other -- an enum of states whose second
/// member meant nothing but "not the frame we typed out". No id is consulted
/// now: membership in a state frame IS the statement, and which status it is
/// and what it costs the weight are the frame's own authored handling.
String todoState(ProjectionEngine engine, Fact fact) {
  if (fact.virtualId.isNotEmpty) return 'open';
  if (objectKindForEvent(fact.event) != 'todo') return 'open';
  final states = engine.facts.stateAffiliations(fact.event.id);
  if (resolvedByState([for (final entry in states) entry.frame])) return resolvedStateWord;
  // A title-only capture: nothing said about it beyond that it exists.
  final described = '${obj(fact.event.payload)?['description'] ?? ''}'.trim();
  if (described.isNotEmpty) return 'open';
  if (engine.indexes.directGroupsOf(fact.event.id).isNotEmpty) return 'open';
  // FLAGGED (core zone, ruled 2026-09-01): "nothing has been said about this
  // beyond that it exists" used to be spelled "it has no staples". Every
  // connection is a staple now -- its own placement included -- so the question
  // has to be asked of the SENTENCES: is there anything beyond where it sits?
  final said = engine.indexes
      .staplesOf(fact.event.id)
      .where((staple) => !isPlacement(staple, fact.event.id));
  return said.isEmpty ? 'sparse' : 'open';
}

/// The composed weight of one mark in one projection.
///
/// [keyPrefix] is the settings namespace the promotion thresholds live in. A
/// lens passes its own id so its thresholds are per-lens and visible; the shipped
/// generic pair is the fallback for a surface that has not declared its own.
DisplayWeight factDisplayWeight(LensScene scene, Fact fact, {String keyPrefix = 'weight'}) {
  final state = todoState(scene.engine, fact);
  final resolved = state == resolvedStateWord;
  final fades = !resolved && objectKindForEvent(fact.event) == 'todo' && scene.law.mapsToClock();
  final half = halfDistanceFor(scene, fact);
  final derivation = scene.engine.weightOf(
    fact,
    scene.projection,
    at: fades ? scene.nowDays : null,
    halfDistanceDays: half,
  );
  final near = proximityStep(scene, fact, derivation.weight);
  return (
    weight: near?.weight ?? derivation.weight,
    rings: [...derivation.rings, ?near],
    promotion: promotionOf(near?.weight ?? derivation.weight, scene.tunable, keyPrefix: keyPrefix),
    state: state,
    bucket: fades ? falloffBucket(_ratio(derivation), scene.tunable) : null,
  );
}

/// The step id the proximity ring reports itself under, so the card's explainer
/// names it the way it names every other ring.
const String proximityWeightRing = 'proximity';

/// What a plain number means when a frame authors `display.proximity: 4`.
///
/// The sugar rule again (`normalizeWeightFormula`), with the meaning this knob
/// actually has: a number is HOW MANY DAYS OF FUTURE the boost is worth half of.
/// At now the weight doubles; that many days out it is up by half; far out the
/// boost lapses to nothing and the object weighs exactly what it always did.
/// Behind now nothing happens at all -- Don asked for the NEAR FUTURE to weigh
/// more, and quietly re-weighting the past would be a second claim nobody made.
String proximitySugar(String number) =>
    '$weightVariable * ($proximityVariable < 0 ? 1 : '
    '1 + ($number) / (($number) + $proximityVariable))';

/// THE NEAR FUTURE MAY WEIGH MORE, WHEN A FRAME SAYS SO (ISSUES 9.1, Don's
/// optional frame rule).
///
/// Read exactly where `display.halfDistance` is read -- the object's own display
/// property, then every frame bearing on it by graph distance -- so this is the
/// same group display property the whole surface already goes through, offered
/// to EVENTS and looking forward. Optional by construction: a frame that authors
/// nothing returns null here and changes nothing at all.
///
/// A curve that will not read is a refusal, not a licence to invent one: the
/// authored text is ignored and the weight passes through untouched, the same
/// no-op an absent knob has always been.
WeightStep? proximityStep(LensScene scene, Fact fact, Rational incoming) {
  final authored = scene.engine.authoredHandling(handlingSubject(scene.engine, fact), 'proximity');
  if (authored == null || !scene.law.mapsToClock()) return null;
  final text = '$authored'.trim();
  if (text.isEmpty) return null;
  final formula = isPlainWeightNumber(text) ? proximitySugar(text) : text;
  // ONE READER (ISSUES 9.1). The signed distance and the evaluation both come
  // from core: `proximityDaysOf` is the one derivation of "how far from now",
  // and `evaluateWeightFormula` is the one evaluator every weight formula goes
  // through, with `days` bound the same way it is bound for every other ring.
  // What stays here is the AUTHORED SURFACE -- which frame property is read, and
  // what a bare number on it means.
  final days = scene.engine.proximityDaysOf(fact, scene.nowDays);
  if (days == null) return null;
  final weight = evaluateWeightFormula(
    formula,
    incoming,
    environment: {proximityVariable: days},
  );
  return weight == null ? null : (id: proximityWeightRing, via: formula, weight: weight);
}

/// How fast this object's apparent magnitude falls off, in days per halving.
///
/// FRAMES ARE GROUPS, so this is a group display property: the nearest frame
/// bearing on the object that authors `display.halfDistance` wins over the
/// global tunable for the objects it modifies (ruled 2026-08-28). The value is
/// authored as an expression in the one math like every other setting, and one
/// that will not read is refused rather than substituted.
Rational halfDistanceFor(LensScene scene, Fact fact) {
  final authored = scene.engine.authoredHandling(
    handlingSubject(scene.engine, fact),
    'halfDistance',
  );
  if (authored != null) {
    try {
      final read = evaluateSource('$authored', const Env());
      if (read is Rational && read > Rational.zero) return read;
    } on MathRefusal {
      // An unreadable formula is not a licence to invent one: the shipped
      // setting answers, and the frame card says why the text will not read.
    }
  }
  return scene.setting('weight.halfDistanceDays');
}

/// The falloff ring's own factor, recovered from the chain: what the closing
/// step multiplied by, which is exactly the apparent-magnitude ratio the opacity
/// ramp buckets. Null when no falloff step ran.
Rational? _ratio(WeightDerivation derivation) {
  for (final (index, step) in derivation.rings.indexed) {
    if (step.id != falloffWeightRing) continue;
    final before = index == 0 ? Rational.one : derivation.rings[index - 1].weight;
    return before.isZero ? Rational.one : step.weight / before;
  }
  return null;
}

/// Where a weight lands against the promotion thresholds. Thresholds are
/// settings, per lens, so a lens that wants a busier landmark bar says so in the
/// settings file instead of in code.
String promotionOf(Rational weight, Tunable? read, {String keyPrefix = 'weight'}) {
  Rational at(String suffix) {
    final key = '$keyPrefix.$suffix';
    return lensTunableDefaults.containsKey(key) || read != null
        ? tunable(read, key)
        : tunable(null, 'weight.$suffix');
  }

  if (weight >= at('landmarkAt')) return landmarkWeight;
  return weight >= at('importantAt') ? importantWeight : standardWeight;
}
