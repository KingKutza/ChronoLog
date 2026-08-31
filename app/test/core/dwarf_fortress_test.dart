// THE DWARF FORTRESS TEST (Don, 2026-08-31; corrected the same day: "No I said
// to generalize it not encode it"). The founding conception as a property
// suite over RANDOM WORLDS, not the story's instances:
//
//   "two frames, with two basises, both random within the range of all
//   possible basises, an event e we staple e'=A'=B' and e''=A''=B'' then we
//   project from A, B, or e and we get the same data from a different angle,
//   Then if we define a random number of addtional staples sequentialy along
//   A, B, and e then when we project we see the peicewse function that
//   derives from that set."
//
// The law under it: "a simple function a complex function and a peicewise
// function are the same thing they differ in percision not in type."
//
// FRESH SEED EVERY RUN, by ruling: "every time you run it has a new seed that
// test a different combination. and so over the course of development we get
// to sample a subset of the posiblity space and ensure that there is no
// possible awnser to pass the test but the right awnser, all others would
// fail somewhere." The run seed is printed; pin CHRONOLOG_SEED to reproduce a
// failure exactly.
//
// The last two cases were the RULED TARGET the substrate did not answer, and
// both are now built: identification through a shared object point (n points on
// objects or frames are ONE POINT, so the far sheet's claim is a second spelling
// rather than a contest), and the piecewise correspondence as an evaluable core
// function -- `core/correspondence.dart`, exact at every stapled point,
// stretched by the authored ratio between two of them, silent outside them.

import 'dart:io';
import 'dart:math';

import 'package:chronolog/core/correspondence.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/frame_projection.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/core/staples.dart';
import 'package:test/test.dart';

final int runSeed =
    int.tryParse(Platform.environment['CHRONOLOG_SEED'] ?? '') ??
    DateTime.now().microsecondsSinceEpoch;

const String frameA = 'frame:alpha';
const String frameB = 'frame:beta';

/// A basis drawn from the space of nested radix ladders: 1..4 levels, each
/// sub-level a seeded radix 2..30. The names are minted so no case can lean on
/// a unit meaning anything.
typedef LawSpec = ({Json law, List<String> names, List<int> radices});

LawSpec genLaw(Random random, String salt) {
  final depth = 1 + random.nextInt(4);
  final names = [for (var i = 0; i < depth; i++) 'u$salt$i'];
  final radices = [for (var i = 1; i < depth; i++) 2 + random.nextInt(29)];
  return (
    law: {
      'kind': 'nested',
      'levels': [
        {'name': names[0]},
        for (var i = 1; i < depth; i++)
          {'name': names[i], 'within': names[i - 1], 'radix': '${radices[i - 1]}'},
      ],
    },
    names: names,
    radices: radices,
  );
}

/// The coordinate at a total count of the law's finest unit, decomposed into
/// the ladder's own digits. Totals give the space an order to be sequential
/// in without the test knowing what any unit means.
Json coordinateAt(LawSpec spec, int total) {
  final digits = <String>[];
  var rest = total;
  for (final radix in spec.radices.reversed) {
    digits.insert(0, '${rest % radix}');
    rest ~/= radix;
  }
  digits.insert(0, '$rest');
  return {
    'levels': [
      for (var i = 0; i < spec.names.length; i++) {'level': spec.names[i], 'value': digits[i]},
    ],
  };
}

/// Strictly increasing totals: sequential along a frame, as the stapler moves.
List<int> increasingTotals(Random random, int count) {
  var at = random.nextInt(50);
  return [for (var i = 0; i < count; i++) at += 1 + random.nextInt(900)];
}

/// Two frames on two random bases, and nothing relating them.
Document twoFrames(LawSpec lawA, LawSpec lawB) =>
    createEmptyWorkspaceDocument(now: DateTime.utc(2026))
        .put('frames', frameA, Frame(
          id: frameA, title: 'Alpha', traits: const ['line', 'temporal'],
          extra: {'coordinate': lawA.law}))
        .put('frames', frameB, Frame(
          id: frameB, title: 'Beta', traits: const ['line', 'temporal'],
          extra: {'coordinate': lawB.law}));

/// A random number of staples laid sequentially along A and along B: pair i
/// identifies the i-th instant on each. What the second stapler wrote.
({Document document, int count}) sequentialStaples(
  Document document,
  Random random,
  LawSpec lawA,
  LawSpec lawB, {
  int atLeast = 1,
}) {
  final count = atLeast + random.nextInt(9);
  final alphas = increasingTotals(random, count);
  final betas = increasingTotals(random, count);
  var out = document;
  for (var i = 0; i < count; i++) {
    out = putStaple(out, kind: 'correspondence', ends: [
      StapleEnd.frame(frameA, position: Position.coordinate(coordinateAt(lawA, alphas[i]))),
      StapleEnd.frame(frameB, position: Position.coordinate(coordinateAt(lawB, betas[i]))),
    ]).document;
  }
  return (document: out, count: count);
}

void main() {
  // One line names the world this run sampled.
  // ignore: avoid_print
  print('DWARF FORTRESS RUN SEED: $runSeed  (set CHRONOLOG_SEED=$runSeed to reproduce)');

  Random caseRandom(int salt) => Random(runSeed ^ salt);

  test('no staple, no projection: the refusal is honest and worded, whatever the bases', () {
    final random = caseRandom(0x01);
    for (var draw = 0; draw < 10; draw++) {
      final document = twoFrames(genLaw(random, 'a'), genLaw(random, 'b'));
      final projection = FrameProjection(document.toJson());
      expect(projection.framesProject(frameA, frameB), isFalse,
          reason: 'seed $runSeed draw $draw: nothing anybody authored relates the two');
      final answer = projection.projectableFrames([frameA], frameB);
      expect(answer.projectable, isEmpty, reason: 'seed $runSeed draw $draw');
      expect(answer.refused.single.message, contains('Staple a point'),
          reason: 'seed $runSeed draw $draw: the refusal tells the author the remedy');
    }
  });

  test('pick up any, pick up all: one identification relates both ways, chains carry', () {
    final random = caseRandom(0x02);
    for (var draw = 0; draw < 10; draw++) {
      final lawA = genLaw(random, 'a'), lawB = genLaw(random, 'b');
      var document = sequentialStaples(twoFrames(lawA, lawB), random, lawA, lawB).document;
      final projection = FrameProjection(document.toJson());
      expect(projection.framesProject(frameA, frameB), isTrue, reason: 'seed $runSeed draw $draw');
      expect(projection.framesProject(frameB, frameA), isTrue,
          reason: 'seed $runSeed draw $draw: identification has no direction');
      // A third random basis stapled only to B reaches A through it: the pile
      // is one graph and reachability is the pick-up.
      final lawC = genLaw(random, 'c');
      document = document.put('frames', 'frame:gamma', Frame(
          id: 'frame:gamma', title: 'Gamma', traits: const ['line', 'temporal'],
          extra: {'coordinate': lawC.law}));
      document = putStaple(document, kind: 'correspondence', ends: [
        StapleEnd.frame('frame:gamma',
            position: Position.coordinate(coordinateAt(lawC, 1 + random.nextInt(500)))),
        StapleEnd.frame(frameB,
            position: Position.coordinate(coordinateAt(lawB, 1 + random.nextInt(500)))),
      ]).document;
      expect(FrameProjection(document.toJson()).framesProject('frame:gamma', frameA), isTrue,
          reason: 'seed $runSeed draw $draw: reachability over authored staples');
    }
  });

  test('from A or from B: the same set from a different angle', () {
    final random = caseRandom(0x03);
    for (var draw = 0; draw < 10; draw++) {
      final lawA = genLaw(random, 'a'), lawB = genLaw(random, 'b');
      final marked = sequentialStaples(twoFrames(lawA, lawB), random, lawA, lawB, atLeast: 2);
      final staples = Staples(marked.document);
      final fromA = staples.frameCorrespondences(frameA, frameB);
      final fromB = staples.frameCorrespondences(frameB, frameA);
      expect(fromA, hasLength(marked.count), reason: 'seed $runSeed draw $draw');
      expect(fromB, hasLength(marked.count),
          reason: 'seed $runSeed draw $draw: the other angle sees every staple too');
      // Entry for entry, the same metal mirrored: same staple id, ends swapped.
      for (final entry in fromA) {
        final mirrored = fromB.where((other) =>
            other.staple.id == entry.staple.id &&
            other.from.toJson().toString() == entry.to.toJson().toString() &&
            other.to.toJson().toString() == entry.from.toJson().toString());
        expect(mirrored, hasLength(1),
            reason: 'seed $runSeed draw $draw: one record, two renderings');
      }
      final shapeAB = staples.describeCorrespondence(frameA, frameB);
      final shapeBA = staples.describeCorrespondence(frameB, frameA);
      expect(shapeAB.count, shapeBA.count, reason: 'seed $runSeed draw $draw');
      expect(shapeAB.monotonic, shapeBA.monotonic,
          reason: 'seed $runSeed draw $draw: the set has one shape from either angle');
    }
  });

  test('exact at every stapled point, monotone when laid sequentially, refinement moves nothing',
      () {
    final random = caseRandom(0x04);
    for (var draw = 0; draw < 10; draw++) {
      final lawA = genLaw(random, 'a'), lawB = genLaw(random, 'b');
      final marked = sequentialStaples(twoFrames(lawA, lawB), random, lawA, lawB, atLeast: 2);
      final staples = Staples(marked.document);
      final entries = staples.frameCorrespondences(frameA, frameB);
      for (final entry in entries) {
        expect(staples.frameEndDays(entry.from), isNotNull,
            reason: 'seed $runSeed draw $draw: an authored instant resolves under its own law');
        expect(staples.frameEndDays(entry.to), isNotNull, reason: 'seed $runSeed draw $draw');
      }
      expect(staples.describeCorrespondence(frameA, frameB).monotonic, isTrue,
          reason: 'seed $runSeed draw $draw: laid sequentially along both frames, and the '
              'derivation reads that off the set rather than storing it');
      // REFINEMENT -- precision, not type: more staples never move an anchor.
      final before = [
        for (final entry in entries)
          (staples.frameEndDays(entry.from), staples.frameEndDays(entry.to)),
      ];
      final refined = Staples(
          sequentialStaples(marked.document, random, lawA, lawB).document);
      final after = [
        for (final entry in refined.frameCorrespondences(frameA, frameB))
          (refined.frameEndDays(entry.from), refined.frameEndDays(entry.to)),
      ];
      expect(after.length, greaterThan(before.length), reason: 'seed $runSeed draw $draw');
      for (final pair in before) {
        expect(after, contains(pair),
            reason: 'seed $runSeed draw $draw: a new staple refines the function; '
                'it never moves an anchor');
      }
    }
  });

  test('the host frame is unchanged by the marks: no staple invents an occurrence', () {
    final random = caseRandom(0x05);
    for (var draw = 0; draw < 10; draw++) {
      final lawA = genLaw(random, 'a'), lawB = genLaw(random, 'b');
      var document = twoFrames(lawA, lawB);
      document = document.put('events', 'event:e',
          const Event(id: 'event:e', traits: ['event']));
      document = document.put('relations', 'relation:placed', Relation(
          id: 'relation:placed', type: 'attachment', extra: {
        'event': 'event:e', 'frame': frameA, 'role': 'placed',
        'coordinate': coordinateAt(lawA, 5 + random.nextInt(500)),
      }));
      Set<String> factsOn(Document doc) =>
          {for (final fact in Staples(doc).factsOf(frameA)) fact.event.id};
      final beforeMarks = factsOn(document);
      final marked = sequentialStaples(document, random, lawA, lawB).document;
      expect(factsOn(marked), beforeMarks,
          reason: 'seed $runSeed draw $draw: looking at the host frame, nothing has changed');
    }
  });

  test("e'=A'=B' and e''=A''=B'' as the pair encoding: one point per sheet, no contest", () {
    final random = caseRandom(0x06);
    for (var draw = 0; draw < 10; draw++) {
      final lawA = genLaw(random, 'a'), lawB = genLaw(random, 'b');
      var document = twoFrames(lawA, lawB);
      document = document.put('events', 'event:e',
          const Event(id: 'event:e', traits: ['event']));
      final begin = increasingTotals(random, 2);
      // The pair encoding of the two identifications: begin on A (placement)
      // and on B; end on A and on B. Four claims on two points of e -- and by
      // the ruling those four claims are TWO POINTS, each spelled on two
      // sheets, not two believed claims and two rivals.
      final authored = <(String, String, Json)>[];
      final placedAt = coordinateAt(lawA, begin[0]);
      document = document.put('relations', 'relation:placed', Relation(
          id: 'relation:placed', type: 'attachment', extra: {
        'event': 'event:e', 'frame': frameA, 'role': 'placed', 'coordinate': placedAt,
      }));
      authored.add(('start', frameA, placedAt));
      for (final (point, frame, law, total) in [
        (null, frameB, lawB, 3 + random.nextInt(400)),
        ('end', frameA, lawA, begin[1]),
        ('end', frameB, lawB, 7 + random.nextInt(600)),
      ]) {
        final at = coordinateAt(law, total);
        document = putStaple(document, kind: 'anchor', ends: [
          StapleEnd.object('event:e', point: point),
          StapleEnd.frame(frame, position: Position.coordinate(at)),
        ]).document;
        authored.add((point ?? 'start', frame, at));
      }
      final staples = Staples(document);
      final extent = staples.resolveObjectExtent('event:e');
      expect(extent.startDays, isNotNull, reason: 'seed $runSeed draw $draw: e sits somewhere');
      expect(extent.endDays, isNotNull, reason: 'seed $runSeed draw $draw: and ends somewhere');
      // IDENTIFICATION, NOT CONTEST: nothing here disagrees with anything, so
      // nothing is reported -- and nothing is dropped or averaged either.
      expect([...extent.overdetermined, ...extent.unresolved], isEmpty,
          reason: 'seed $runSeed draw $draw: claims on different sheets are one '
              'point on several sheets, never a contest');
      // Every claim is READABLE where it was written: a point holds one
      // position per coordinate space, which is what "n points are one point"
      // comes to when the sheets are different.
      for (final (point, frame, at) in authored) {
        expect(
            extent.positions[point]?[staples.spaceOfFrame(frame)],
            staples.frameEndDays(
                StapleEnd.frame(frame, position: Position.coordinate(at))),
            reason: 'seed $runSeed draw $draw: $point of e, as written on $frame');
      }
      for (final point in ['start', 'end']) {
        expect(extent.positions[point]!.keys, unorderedEquals([
          staples.spaceOfFrame(frameA),
          staples.spaceOfFrame(frameB),
        ]), reason: 'seed $runSeed draw $draw: two sheets, both spelled, neither '
            'collapsed into the other');
      }
    }
  });

  test("e'=A'=B' as ONE staple: the frames correspond through e, and no claim is a contest", () {
    final random = caseRandom(0x07);
    for (var draw = 0; draw < 6; draw++) {
      final lawA = genLaw(random, 'a'), lawB = genLaw(random, 'b');
      var document = twoFrames(lawA, lawB);
      document = document.put('events', 'event:e',
          const Event(id: 'event:e', traits: ['event']));
      // The metal as ruled: one staple, three pages, three points made one --
      // at the beginning, and again at the end.
      final beginA = 5 + random.nextInt(400);
      document = putStaple(document, kind: 'anchor', ends: [
        StapleEnd.object('event:e'),
        StapleEnd.frame(frameA, position: Position.coordinate(coordinateAt(lawA, beginA))),
        StapleEnd.frame(frameB,
            position: Position.coordinate(coordinateAt(lawB, 3 + random.nextInt(400)))),
      ]).document;
      document = putStaple(document, kind: 'anchor', ends: [
        StapleEnd.object('event:e', point: 'end'),
        StapleEnd.frame(frameA,
            position: Position.coordinate(coordinateAt(lawA, beginA + 1 + random.nextInt(400)))),
        StapleEnd.frame(frameB,
            position: Position.coordinate(coordinateAt(lawB, 900 + random.nextInt(400)))),
      ]).document;
      expect(FrameProjection(document.toJson()).framesProject(frameA, frameB), isTrue,
          reason: 'seed $runSeed draw $draw: n points on objects or frames are one point, '
              'so the sheets correspond through the sticky');
      final extent = Staples(document).resolveObjectExtent('event:e');
      expect(extent.startDays, isNotNull, reason: 'seed $runSeed draw $draw');
      expect(extent.endDays, isNotNull, reason: 'seed $runSeed draw $draw');
      expect([...extent.overdetermined, ...extent.unresolved], isEmpty,
          reason: 'seed $runSeed draw $draw: one point on three sheets is an '
              'identification, never a contest');
    }
  });

  test('the piecewise function derived from the staple set is evaluable from any angle', () {
    // "A simple function a complex function and a peicewise function are the
    // same thing they differ in percision not in type." So one seam answers
    // "where does this instant on A land on B" from whatever the author wrote:
    // exact at every stapled point, stretched by the authored ratio between two
    // of them, silent outside them, and silent between frames nothing relates.
    final random = caseRandom(0x08);
    for (var draw = 0; draw < 8; draw++) {
      final lawA = genLaw(random, 'a'), lawB = genLaw(random, 'b');

      // NO STAPLE, NO ANSWER. The refusal is the load-bearing half.
      final bare = Correspondences(Staples(twoFrames(lawA, lawB)));
      final nowhere = bare.landing(frameA, frameB, Rational.fromInt(3));
      expect(nowhere.at, isEmpty,
          reason: 'seed $runSeed draw $draw: nothing relates the two bases, so '
              'no instant on one lands anywhere on the other');
      expect(nowhere.refusal, contains('Staple a point'),
          reason: 'seed $runSeed draw $draw: the refusal names the remedy');

      final marked = sequentialStaples(twoFrames(lawA, lawB), random, lawA, lawB, atLeast: 3);
      final staples = Staples(marked.document);
      final correspondence = Correspondences(staples);
      final pairs = correspondence.anchorsBetween(frameA, frameB);
      expect(pairs, hasLength(marked.count),
          reason: 'seed $runSeed draw $draw: one anchor pair per authored staple');

      // The set as the author left it: every instant on A that was stapled, and
      // every instant on B it was stapled to. Grouped, never collapsed -- two
      // staples at one instant are two answers.
      final marks = <Rational, List<AnchorPair>>{};
      for (final pair in pairs) {
        (marks[pair.from] ??= []).add(pair);
      }
      final ordered = marks.keys.toList()..sort((left, right) => left.compareTo(right));

      // EXACT AT EVERY STAPLED POINT, from either angle, and known to be exact.
      for (final mark in ordered) {
        final landed = correspondence.landing(frameA, frameB, mark);
        expect(landed.exact, isTrue, reason: 'seed $runSeed draw $draw');
        expect(landed.at, {for (final pair in marks[mark]!) pair.to}.toList()
          ..sort((left, right) => left.compareTo(right)),
            reason: 'seed $runSeed draw $draw: the authored instants, all of '
                'them, and nothing invented between them');
        for (final pair in marks[mark]!) {
          expect(correspondence.landing(frameB, frameA, pair.to).at, contains(mark),
              reason: 'seed $runSeed draw $draw: the same staple read from B');
        }
      }

      // THE RATIO BETWEEN TWO ANCHORS, and the two directions inverse of each
      // other within one piece.
      for (var index = 1; index < ordered.length; index++) {
        final low = ordered[index - 1], high = ordered[index];
        final span = high - low;
        final steps = 2 + random.nextInt(5);
        for (var step = 1; step < steps; step++) {
          final ratio = Rational.fromInt(step, steps);
          final on = low + span * ratio;
          final landed = correspondence.landing(frameA, frameB, on);
          expect(landed.exact, isFalse,
              reason: 'seed $runSeed draw $draw: between anchors, not on one');
          // Computed here from the pairs themselves: the piece is the authored
          // ratio and nothing else. Many-valued marks stay many-valued -- every
          // combination of the bracketing pairs is a piece somebody wrote.
          final expected = <Rational>{
            for (final lower in marks[low]!)
              for (final upper in marks[high]!)
                lower.to + (upper.to - lower.to) * ratio,
          }.toList()..sort((left, right) => left.compareTo(right));
          expect(landed.at, expected,
              reason: 'seed $runSeed draw $draw: the stretch IS the authored '
                  'ratio, never averaged and never interpolated across a gap');
          if (marks[low]!.length == 1 && marks[high]!.length == 1) {
            expect(correspondence.landing(frameB, frameA, landed.at.single).at, contains(on),
                reason: 'seed $runSeed draw $draw: one function, read from the '
                    'other end of the same piece');
          }
        }
      }

      // OUTSIDE THE BRACKETING ANCHORS: no answer at all. Not the nearest
      // anchor's offset carried outward -- nothing, and a sentence saying so.
      for (final beyond in [ordered.first - Rational.one, ordered.last + Rational.one]) {
        final refused = correspondence.landing(frameA, frameB, beyond);
        expect(refused.at, isEmpty,
            reason: 'seed $runSeed draw $draw: an unstapled range projects no advance');
        expect(refused.refusal, isNotNull, reason: 'seed $runSeed draw $draw');
      }

      // REFINEMENT IS PRECISION, NOT TYPE: more staples never move an anchor.
      final refined = Correspondences(
          Staples(sequentialStaples(marked.document, random, lawA, lawB).document));
      expect(refined.anchorsBetween(frameA, frameB).length, greaterThan(pairs.length),
          reason: 'seed $runSeed draw $draw');
      for (final pair in pairs) {
        expect(refined.landing(frameA, frameB, pair.from).at, contains(pair.to),
            reason: 'seed $runSeed draw $draw: the second stapler refines the '
                'function between the anchors; it moves none of them');
      }
    }
  });
}
