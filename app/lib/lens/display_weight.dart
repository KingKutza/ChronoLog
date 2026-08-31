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
// FALLOFF APPLIES TO UNRESOLVED OBJECTS ONLY. A done or closed object never
// fades: its state grammar already says what it is, and fading it would say the
// same thing twice and less clearly. A law with no clock mapping has no honest
// distance from now, so it has no falloff either.
//
// The derivation comes back WHOLE -- every ring, in order -- because the card's
// explainer has to show how a weight was reached, not just what it came to.

import '../core/exact.dart';
import '../core/math.dart';
import '../core/object_kinds.dart';
import '../core/projection.dart';
import '../core/records.dart';
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
/// Nothing else may read state, and nothing here enumerates the vocabulary --
/// Done is a frame like any other, and "closed" is simply some other state
/// frame the author made.
String todoState(ProjectionEngine engine, Fact fact) {
  if (fact.virtualId.isNotEmpty) return 'open';
  if (objectKindForEvent(fact.event) != 'todo') return 'open';
  final states = engine.facts.stateAffiliations(fact.event.id);
  if (states.any((entry) => entry.frame == doneStateFrameId)) return 'done';
  if (states.isNotEmpty) return 'closed';
  // A title-only capture: nothing said about it beyond that it exists.
  final described = '${obj(fact.event.payload)?['description'] ?? ''}'.trim();
  if (described.isNotEmpty) return 'open';
  if (engine.indexes.directGroupsOf(fact.event.id).isNotEmpty) return 'open';
  return engine.indexes.staplesOf(fact.event.id).isEmpty ? 'sparse' : 'open';
}

/// The composed weight of one mark in one projection.
///
/// [keyPrefix] is the settings namespace the promotion thresholds live in. A
/// lens passes its own id so its thresholds are per-lens and visible; the shipped
/// generic pair is the fallback for a surface that has not declared its own.
DisplayWeight factDisplayWeight(LensScene scene, Fact fact, {String keyPrefix = 'weight'}) {
  final state = todoState(scene.engine, fact);
  final resolved = state == 'done' || state == 'closed';
  final fades = !resolved && objectKindForEvent(fact.event) == 'todo' && scene.law.mapsToClock();
  final half = halfDistanceFor(scene, fact);
  final derivation = scene.engine.weightOf(
    fact,
    scene.projection,
    at: fades ? scene.nowDays : null,
    halfDistanceDays: half,
  );
  return (
    weight: derivation.weight,
    rings: derivation.rings,
    promotion: promotionOf(derivation.weight, scene.tunable, keyPrefix: keyPrefix),
    state: state,
    bucket: fades ? falloffBucket(_ratio(derivation), scene.tunable) : null,
  );
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
