// THE EVALUABLE CORRESPONDENCE, beside the Dwarf Fortress suite.
//
// The DF file asserts the parable's own shape: exact at every stapled point, the
// authored ratio between two of them, inverse from either end, refinement that
// moves no anchor, silence outside the brackets. This file asserts what the
// parable implies but does not itself stage -- the correspondence arriving
// THROUGH an object rather than between two frames, many-valued sets staying
// many-valued, a chain of frames composing, and one coordinate space needing no
// staple at all.
//
// FRESH SEED EVERY RUN, by the same ruling. Nothing here knows what a unit
// means: every expected instant is read back through the substrate's own law,
// so no case can pass by agreeing with an arithmetic the test invented.

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

/// A basis drawn from the space of nested radix ladders, its unit names minted
/// so nothing here can lean on a unit meaning anything.
typedef LawSpec = ({Json law, List<String> names, List<int> radices});

LawSpec genLaw(Random random, String salt) {
  final depth = 1 + random.nextInt(3);
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

/// The coordinate at a total count of the law's finest unit, in the ladder's own
/// digits.
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

Document withFrame(Document document, String id, Json law) => document.put(
  'frames',
  id,
  Frame(id: id, title: id, traits: const ['line', 'temporal'], extra: {'coordinate': law}),
);

StapleEnd frameAt(String frame, LawSpec spec, int total) =>
    StapleEnd.frame(frame, position: Position.coordinate(coordinateAt(spec, total)));

List<int> increasingTotals(Random random, int count) {
  var at = random.nextInt(50);
  return [for (var i = 0; i < count; i++) at += 1 + random.nextInt(900)];
}

void main() {
  // ignore: avoid_print
  print('CORRESPONDENCE RUN SEED: $runSeed  (set CHRONOLOG_SEED=$runSeed to reproduce)');

  Random caseRandom(int salt) => Random(runSeed ^ salt);

  Rational at(Staples staples, String frame, LawSpec spec, int total) =>
      staples.frameEndDays(frameAt(frame, spec, total))!;

  test('the sticky note relates the sheets: an object point stapled to two '
      'frames is an anchor pair between them', () {
    final random = caseRandom(0x11);
    for (var draw = 0; draw < 8; draw++) {
      final lawA = genLaw(random, 'a'), lawB = genLaw(random, 'b');
      var document = createEmptyWorkspaceDocument(now: DateTime.utc(2026));
      document = withFrame(document, 'frame:august', lawA.law);
      document = withFrame(document, 'frame:decade', lawB.law);
      document = document.put(
        'events',
        'event:df',
        const Event(id: 'event:df', traits: ['event']),
      );
      // The parable exactly: the sticky's beginning is one point with an instant
      // on each sheet, and so is its end -- authored as two SEPARATE staples,
      // which is the encoding that used to read as a contest.
      final beginA = increasingTotals(random, 2), beginB = increasingTotals(random, 2);
      for (final (index, point) in ['start', 'end'].indexed) {
        for (final (frame, spec, total) in [
          ('frame:august', lawA, beginA[index]),
          ('frame:decade', lawB, beginB[index]),
        ]) {
          document = putStaple(document, kind: 'anchor', ends: [
            StapleEnd.object('event:df', point: point),
            frameAt(frame, spec, total),
          ]).document;
        }
      }
      final staples = Staples(document);
      final correspondence = Correspondences(staples);
      final pairs = correspondence.anchorsBetween('frame:august', 'frame:decade');
      expect(pairs, hasLength(2),
          reason: 'seed $runSeed draw $draw: two points of the sticky, two pairs');
      // "If I project one calendar I can see both the event and the other
      // calendar in that range as there is now a ratio to convert one to the
      // other." The ratio, evaluated, at the sticky's own two points.
      for (final index in [0, 1]) {
        expect(
          correspondence.landing(
            'frame:august',
            'frame:decade',
            at(staples, 'frame:august', lawA, beginA[index]),
          ).at,
          [at(staples, 'frame:decade', lawB, beginB[index])],
          reason: 'seed $runSeed draw $draw',
        );
      }
      // And halfway between them, the stretch -- one value, from the pair.
      final low = pairs.first, high = pairs.last;
      final half = Rational.fromInt(1, 2);
      expect(
        correspondence.landing(
          'frame:august',
          'frame:decade',
          low.from + (high.from - low.from) * half,
        ).at,
        [low.to + (high.to - low.to) * half],
        reason: 'seed $runSeed draw $draw: the warp between the two staples',
      );
    }
  });

  test('an object placed by its own attachment carries an anchor as any other '
      'identification does', () {
    final random = caseRandom(0x12);
    for (var draw = 0; draw < 8; draw++) {
      final lawA = genLaw(random, 'a'), lawB = genLaw(random, 'b');
      var document = createEmptyWorkspaceDocument(now: DateTime.utc(2026));
      document = withFrame(document, 'frame:a', lawA.law);
      document = withFrame(document, 'frame:b', lawB.law);
      document = document.put('events', 'event:e', const Event(id: 'event:e', traits: ['event']));
      final onA = 5 + random.nextInt(400), onB = 3 + random.nextInt(400);
      document = document.put('relations', 'relation:placed', Relation(
        id: 'relation:placed',
        type: 'staple',
        extra: {
          'kind': 'anchor',
          'role': 'placed',
          'ends': [
            ObjectEnd('event:e', point: 'start').toJson(),
            FrameEnd('frame:a', position: Position.coordinate(coordinateAt(lawA, onA))).toJson(),
          ],
        },
      ));
      document = putStaple(document, kind: 'anchor', ends: [
        const StapleEnd.object('event:e', point: 'start'),
        frameAt('frame:b', lawB, onB),
      ]).document;
      final staples = Staples(document);
      final pairs = Correspondences(staples).anchorsBetween('frame:a', 'frame:b');
      expect(pairs, hasLength(1),
          reason: 'seed $runSeed draw $draw: the placement IS the start '
              'identification, so one point of e is on both sheets');
      expect(pairs.single.from, at(staples, 'frame:a', lawA, onA),
          reason: 'seed $runSeed draw $draw');
      expect(pairs.single.to, at(staples, 'frame:b', lawB, onB),
          reason: 'seed $runSeed draw $draw');
    }
  });

  test('many-valued stays many-valued: one instant stapled to two answers with '
      'both, and never with their mean', () {
    final random = caseRandom(0x13);
    for (var draw = 0; draw < 8; draw++) {
      final lawA = genLaw(random, 'a'), lawB = genLaw(random, 'b');
      var document = createEmptyWorkspaceDocument(now: DateTime.utc(2026));
      document = withFrame(document, 'frame:a', lawA.law);
      document = withFrame(document, 'frame:b', lawB.law);
      final onA = 40 + random.nextInt(200);
      final targets = increasingTotals(random, 2);
      for (final total in targets) {
        document = putStaple(document, kind: 'correspondence', ends: [
          frameAt('frame:a', lawA, onA),
          frameAt('frame:b', lawB, total),
        ]).document;
      }
      final staples = Staples(document);
      final landed = Correspondences(staples).landing(
        'frame:a',
        'frame:b',
        at(staples, 'frame:a', lawA, onA),
      );
      final expected = [
        for (final total in targets) at(staples, 'frame:b', lawB, total),
      ]..sort((left, right) => left.compareTo(right));
      expect(landed.at, expected,
          reason: 'seed $runSeed draw $draw: the dot over the i corresponds to '
              'every Tuesday AND to July -- both, never one');
      expect(landed.exact, isTrue, reason: 'seed $runSeed draw $draw');
      final mean = (expected.first + expected.last) / Rational.fromInt(2);
      expect(landed.at, isNot(contains(mean)),
          reason: 'seed $runSeed draw $draw: an average is a third instant '
              'nobody authored');
    }
  });

  test('a chain composes: A through C to B, and refuses where either leg does', () {
    final random = caseRandom(0x14);
    for (var draw = 0; draw < 8; draw++) {
      final lawA = genLaw(random, 'a'), lawB = genLaw(random, 'b'), lawC = genLaw(random, 'c');
      var document = createEmptyWorkspaceDocument(now: DateTime.utc(2026));
      document = withFrame(document, 'frame:a', lawA.law);
      document = withFrame(document, 'frame:b', lawB.law);
      document = withFrame(document, 'frame:c', lawC.law);
      final onA = increasingTotals(random, 2);
      final onC = increasingTotals(random, 2);
      final onB = increasingTotals(random, 2);
      for (final index in [0, 1]) {
        document = putStaple(document, kind: 'correspondence', ends: [
          frameAt('frame:a', lawA, onA[index]),
          frameAt('frame:c', lawC, onC[index]),
        ]).document;
        document = putStaple(document, kind: 'correspondence', ends: [
          frameAt('frame:c', lawC, onC[index]),
          frameAt('frame:b', lawB, onB[index]),
        ]).document;
      }
      final staples = Staples(document);
      final correspondence = Correspondences(staples);
      // Nothing was ever stapled between A and B, and yet they correspond --
      // through C, at the two points where the chain is exact.
      expect(correspondence.anchorsBetween('frame:a', 'frame:b'), isEmpty,
          reason: 'seed $runSeed draw $draw: no anchor pair was authored between them');
      for (final index in [0, 1]) {
        expect(
          correspondence.landing(
            'frame:a',
            'frame:b',
            at(staples, 'frame:a', lawA, onA[index]),
          ).at,
          [at(staples, 'frame:b', lawB, onB[index])],
          reason: 'seed $runSeed draw $draw: the pile is one graph, and the '
              'function composes along it',
        );
      }
      // Past the ends of the chain, the refusal travels too.
      final beyond = correspondence.landing(
        'frame:a',
        'frame:b',
        at(staples, 'frame:a', lawA, onA.first) - Rational.one,
      );
      expect(beyond.at, isEmpty, reason: 'seed $runSeed draw $draw');
      expect(beyond.refusal, isNotNull, reason: 'seed $runSeed draw $draw');
    }
  });

  test('one coordinate space needs no staple: a frame lands on its own basis '
      'at the instant it already is', () {
    final random = caseRandom(0x15);
    for (var draw = 0; draw < 8; draw++) {
      final lawA = genLaw(random, 'a');
      var document = createEmptyWorkspaceDocument(now: DateTime.utc(2026));
      document = withFrame(document, 'frame:a', lawA.law);
      document = document.put(
        'frames',
        'frame:derived',
        const Frame(
          id: 'frame:derived',
          title: 'Derived',
          traits: ['line', 'temporal'],
          extra: {'coordinateDefinition': 'frame:a'},
        ),
      );
      final staples = Staples(document);
      final days = at(staples, 'frame:a', lawA, 12 + random.nextInt(400));
      final landed = Correspondences(staples).landing('frame:a', 'frame:derived', days);
      expect(landed.at, [days],
          reason: 'seed $runSeed draw $draw: one sheet, so the position IS the answer');
      expect(landed.exact, isTrue, reason: 'seed $runSeed draw $draw');
      expect(landed.refusal, isNull, reason: 'seed $runSeed draw $draw');
    }
  });

  test('a single anchor pin is not a correspondence: one point brackets nothing', () {
    final random = caseRandom(0x16);
    for (var draw = 0; draw < 8; draw++) {
      final lawA = genLaw(random, 'a'), lawB = genLaw(random, 'b');
      var document = createEmptyWorkspaceDocument(now: DateTime.utc(2026));
      document = withFrame(document, 'frame:a', lawA.law);
      document = withFrame(document, 'frame:b', lawB.law);
      final onA = 30 + random.nextInt(400), onB = 20 + random.nextInt(400);
      document = putStaple(document, kind: 'correspondence', ends: [
        frameAt('frame:a', lawA, onA),
        frameAt('frame:b', lawB, onB),
      ]).document;
      final staples = Staples(document);
      final correspondence = Correspondences(staples);
      // Exact where it was stapled...
      expect(
        correspondence.landing('frame:a', 'frame:b', at(staples, 'frame:a', lawA, onA)).at,
        [at(staples, 'frame:b', lawB, onB)],
        reason: 'seed $runSeed draw $draw',
      );
      // ...and nowhere else. One staple fixes a point, not a rate: carrying an
      // offset outward from it would be a correspondence nobody authored.
      final off = correspondence.landing(
        'frame:a',
        'frame:b',
        at(staples, 'frame:a', lawA, onA) + Rational.one,
      );
      expect(off.at, isEmpty, reason: 'seed $runSeed draw $draw');
      expect(off.refusal, contains('Staple a point'), reason: 'seed $runSeed draw $draw');
    }
  });

  // --- WHAT RELATES TWO SHEETS IS A CHAIN OF IDENTIFIED POINTS ---------------
  //
  // RULING (8.31, Don): "Points identified through the same event point (one
  // staple or two) make positional correspondence; the record type is not the
  // discriminator -- a placement is the first identification." And its other
  // half: "Event is stapled to A at point 7/15/27 2:30:54, and is stapled to B
  // at Null Point. There B is associated with A through event but no point on B
  // projects to a given point on A."
  //
  // Both seams below read ONE source -- `pointIdentifications` -- so a document
  // can no longer be related in the evaluating seam and unrelated in the
  // answering one, which is what these two tests would have caught.

  test('a placement and a staple are one identification: BOTH seams relate the '
      'sheets, and they land on each other', () {
    final random = caseRandom(0x17);
    for (var draw = 0; draw < 8; draw++) {
      final lawA = genLaw(random, 'a'), lawB = genLaw(random, 'b');
      var document = createEmptyWorkspaceDocument(now: DateTime.utc(2026));
      document = withFrame(document, 'frame:a', lawA.law);
      document = withFrame(document, 'frame:b', lawB.law);
      document = document.put('events', 'event:e', const Event(id: 'event:e', traits: ['event']));
      final onA = 5 + random.nextInt(400), onB = 3 + random.nextInt(400);
      // The event is ATTACHED to A -- a placement, not a staple -- and STAPLED
      // to B at the same point of itself.
      document = document.put(
        'relations',
        'relation:placed',
        Relation(
          id: 'relation:placed',
          type: 'staple',
          extra: {
            'kind': 'anchor',
            'role': 'placed',
            'ends': [
              ObjectEnd('event:e', point: 'start').toJson(),
              FrameEnd('frame:a', position: Position.coordinate(coordinateAt(lawA, onA))).toJson(),
            ],
          },
        ),
      );
      document = putStaple(
        document,
        kind: 'anchor',
        ends: [const StapleEnd.object('event:e', point: 'start'), frameAt('frame:b', lawB, onB)],
      ).document;

      final staples = Staples(document);
      final projection = FrameProjection(document.toJson());
      // WHETHER: one point of the event is a point on both sheets, so the sheets
      // correspond -- however each half of that was spelled.
      expect(
        projection.framesProject('frame:a', 'frame:b'),
        isTrue,
        reason: 'seed $runSeed draw $draw: a placement IS an identification',
      );
      expect(projection.framesProject('frame:b', 'frame:a'), isTrue,
          reason: 'seed $runSeed draw $draw');
      expect(projection.projectableFrames(const ['frame:b'], 'frame:a').refused, isEmpty,
          reason: 'seed $runSeed draw $draw');
      // WHERE: and the two seams agree, both ways round.
      final correspondence = Correspondences(staples);
      expect(
        correspondence.landing('frame:a', 'frame:b', at(staples, 'frame:a', lawA, onA)).at,
        [at(staples, 'frame:b', lawB, onB)],
        reason: 'seed $runSeed draw $draw',
      );
      expect(
        correspondence.landing('frame:b', 'frame:a', at(staples, 'frame:b', lawB, onB)).at,
        [at(staples, 'frame:a', lawA, onA)],
        reason: 'seed $runSeed draw $draw',
      );
    }
  });

  test('a NULL POINT associates without projecting: the sheets are in one pile '
      'and no position on either names a position on the other', () {
    final random = caseRandom(0x18);
    for (var draw = 0; draw < 8; draw++) {
      final lawA = genLaw(random, 'a'), lawB = genLaw(random, 'b');
      var document = createEmptyWorkspaceDocument(now: DateTime.utc(2026));
      document = withFrame(document, 'frame:a', lawA.law);
      document = withFrame(document, 'frame:b', lawB.law);
      document = document.put('events', 'event:e', const Event(id: 'event:e', traits: ['event']));
      final onA = 5 + random.nextInt(400);
      document = document.put(
        'relations',
        'relation:placed',
        Relation(
          id: 'relation:placed',
          type: 'staple',
          extra: {
            'kind': 'anchor',
            'role': 'placed',
            'ends': [
              ObjectEnd('event:e', point: 'start').toJson(),
              FrameEnd('frame:a', position: Position.coordinate(coordinateAt(lawA, onA))).toJson(),
            ],
          },
        ),
      );
      // Two spellings of the same nothing: an authored void, and an end that
      // never named a position at all. Neither says WHERE on B.
      final placed = putStaple(
        document,
        kind: 'anchor',
        ends: [
          const StapleEnd.object('event:e', point: 'start'),
          draw.isEven
              ? const StapleEnd.frame('frame:b', position: Position.authoredVoid())
              : const StapleEnd.frame('frame:b'),
        ],
      );
      document = placed.document;
      final staples = Staples(document);

      // ASSOCIATION IS REAL: the staple is one of the event's connections, so
      // anything that picks the event up finds frame B with it.
      expect(
        staples.effectiveObjectStaples('event:e').any((row) => row.staple?.id == placed.staple.id),
        isTrue,
        reason: 'seed $runSeed draw $draw: the pile is joined',
      );

      // PROJECTION IS NOT: nobody said where on B, so nothing may be drawn on
      // B's axis from A.
      final projection = FrameProjection(document.toJson());
      expect(projection.framesProject('frame:b', 'frame:a'), isFalse,
          reason: 'seed $runSeed draw $draw');
      expect(projection.framesProject('frame:a', 'frame:b'), isFalse,
          reason: 'seed $runSeed draw $draw');
      // And the refusal is worded, not a blank frame.
      expect(
        projection.projectableFrames(const ['frame:b'], 'frame:a').refused.single.message,
        allOf(contains('no authored correspondence'), contains('Staple a point between them')),
        reason: 'seed $runSeed draw $draw',
      );

      // The evaluating seam says the same thing, which is the whole point of
      // both reading one source: no anchor is fabricated from a null point.
      final correspondence = Correspondences(staples);
      expect(correspondence.anchorsBetween('frame:a', 'frame:b'), isEmpty,
          reason: 'seed $runSeed draw $draw');
      final landed = correspondence.landing(
        'frame:a',
        'frame:b',
        at(staples, 'frame:a', lawA, onA),
      );
      expect(landed.at, isEmpty, reason: 'seed $runSeed draw $draw');
      expect(landed.refusal, contains('no authored correspondence'),
          reason: 'seed $runSeed draw $draw');

      // The moment the same end names a point, everything projects around that.
      final onB = 3 + random.nextInt(400);
      final named = putStaple(
        document,
        kind: 'anchor',
        ends: [const StapleEnd.object('event:e', point: 'start'), frameAt('frame:b', lawB, onB)],
      ).document;
      expect(FrameProjection(named.toJson()).framesProject('frame:b', 'frame:a'), isTrue,
          reason: 'seed $runSeed draw $draw');
      expect(
        Correspondences(
          Staples(named),
        ).landing('frame:a', 'frame:b', at(staples, 'frame:a', lawA, onA)).at,
        [at(Staples(named), 'frame:b', lawB, onB)],
        reason: 'seed $runSeed draw $draw',
      );
    }
  });
}
