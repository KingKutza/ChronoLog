// SUCCESSION DISSOLVED: era boundaries as plain point staples.
//
// Ruled 2026-08-31 (Don): "A staple connects n points and says each is the same
// as the other. No exceptions No special cases No extra riders." Era 1 and era 2
// are frames with authored bases; where both bases can define a point the staple
// connects those two points -- "one happens to be the end and the other the
// beginning, this case is not special for all it is common, the end of 1 could
// just as easily connect to three weeks into 2." Where a basis cannot label a
// point along the line the staple connects INCLUSIVELY: "the end of 1 staples to
// all of 2."
//
// So this spec never writes the word `succession` except to prove the OLD
// SPELLING still means what it meant. Everything else is authored as ordinary
// points on ordinary frames.
//
// FRESH SEED EVERY RUN, by the generative-tests ruling: the properties are
// sampled over random era chains rather than pinned to one, and the seed is
// printed so a failure reproduces exactly. The Sundering and the sized boundary
// are STORIES and are written as examples, which the ruling allows.

import 'dart:io';
import 'dart:math';

import 'package:chronolog/core/coordinate_law.dart';
import 'package:chronolog/core/correspondence.dart';
import 'package:chronolog/core/era_chain.dart';
import 'package:chronolog/core/eras.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/frame_projection.dart';
import 'package:chronolog/core/frame_points.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/core/staples.dart';
import 'package:test/test.dart';

import '../helpers/staple_world.dart';

final int runSeed =
    int.tryParse(Platform.environment['CHRONOLOG_SEED'] ?? '') ??
    DateTime.now().microsecondsSinceEpoch;

/// A boundary, authored as what it is: the end of one frame identified with the
/// beginning of others. No kind, because a kind selects a derivation and this
/// selects none.
Relation boundary(
  World world, {
  required String finishes,
  required List<String> begins,
  String beginsAt = pointBeginning,
  String? kind,
}) => world.staple(
  kind: kind,
  ends: [
    StapleEnd.frame(finishes, position: const Position.point(pointEnd)),
    for (final id in begins) StapleEnd.frame(id, position: Position.point(beginsAt)),
  ],
);

/// The substrate with its era seam wired, which is what a caller whose document
/// holds era frames passes -- and what the projection engine passes in the app.
/// An era's extent comes from its place in the chain, so a law resolver that
/// cannot see the chain cannot see the extent either.
Staples staplesOf(World world) =>
    Staples(world.document, laws: CoordinateLaws(eras: eraLookup(world.document)));

/// The frame's own extent, as the law derives it.
FrameExtent? extentOf(World world, String frameId) => staplesOf(world).lawOf(frameId)?.extentDays;

Rational? at(World world, String frameId, String point) =>
    staplesOf(world).positionDays(frameId, Position.point(point));

void main() {
  // ignore: avoid_print
  print('frame_points seed: $runSeed  (pin CHRONOLOG_SEED to reproduce)');

  group('a frame speaks its own points', () {
    test('an era knows where it begins and where it runs out, and the two meet '
        'the next era with nothing in between', () {
      final random = Random(runSeed);
      for (var i = 0; i < 24; i += 1) {
        final world = World();
        final firstLength = 1 + random.nextInt(400);
        final secondLength = 1 + random.nextInt(400);
        world.era(
          'era:one',
          key: 'E1',
          years: '$firstLength',
          anchor: {'year': '1', 'properYear': '${1 + random.nextInt(1000)}'},
        );
        world.era('era:two', key: 'E2', years: '$secondLength');
        boundary(world, finishes: 'era:one', begins: const ['era:two']);

        final first = extentOf(world, 'era:one')!;
        final second = extentOf(world, 'era:two')!;
        // THE SPLIT DERIVES FROM WHERE THE EARLIER ERA RUNS OUT. No literal
        // anywhere: both expressions resolve through the eras' own year ladders
        // and land on the one same number.
        expect(first.end, isNotNull);
        expect(second.beginning, first.end);
        expect(at(world, 'era:one', pointEnd), first.end);
        expect(at(world, 'era:two', pointBeginning), first.end);
        expect(first.beginning!, lessThan(first.end!));
        expect(second.beginning!, lessThan(second.end!));
      }
    });

    test('a point is an expression, so "three weeks into 2" is as ordinary as '
        'its beginning', () {
      final random = Random(runSeed + 1);
      for (var i = 0; i < 24; i += 1) {
        final world = World();
        world.era(
          'era:one',
          key: 'E1',
          years: '${1 + random.nextInt(200)}',
          anchor: const {'year': '1', 'properYear': '1'},
        );
        world.era('era:two', key: 'E2', years: '${1 + random.nextInt(200)}');
        boundary(world, finishes: 'era:one', begins: const ['era:two']);
        final beginning = at(world, 'era:two', pointBeginning)!;
        final offset = random.nextInt(2000);
        // Arithmetic in the frame's OWN vocabulary: `day` is a unit its law
        // names, so the author writes weeks rather than a day count.
        expect(at(world, 'era:two', 'beginning + $offset * day'), beginning + Rational.fromInt(offset));
        expect(at(world, 'era:two', 'beginning + $offset'), beginning + Rational.fromInt(offset));
        // The bounds are ordinary names, so they compose with each other.
        final end = at(world, 'era:two', pointEnd)!;
        expect(at(world, 'era:two', '(beginning + end) / 2'), (beginning + end) / Rational.fromInt(2));
      }
    });

    test('the all-point is a size, not a place: it holds at every instant of '
        'the frame and names none of them', () {
      final world = World();
      world.era(
        'era:one',
        key: 'E1',
        years: '10',
        anchor: const {'year': '1', 'properYear': '1'},
      );
      world.era('era:two', key: 'E2', years: '10');
      boundary(world, finishes: 'era:one', begins: const ['era:two']);
      final staples = staplesOf(world);
      final law = staples.lawOf('era:two')!;
      final all = staples.pointRegionOf('era:two', const Position.point('all'))!;
      final extent = extentOf(world, 'era:two')!;
      expect(all.from, extent.beginning);
      expect(all.to, extent.end);
      // A REGION IS NOT AN INSTANT. Reducing it to one would pick an arbitrary
      // year of era two and call it the answer.
      expect(staples.positionDays('era:two', const Position.point('all')), isNull);
      final inside = FrameEnd('era:two', position: const Position.point('all'));
      expect(frameEndMatches(law, inside, extent.beginning!), isTrue);
      expect(frameEndMatches(law, inside, extent.end!), isTrue);
      expect(
        frameEndMatches(law, inside, (extent.beginning! + extent.end!) / Rational.fromInt(2)),
        isTrue,
      );
      expect(frameEndMatches(law, inside, extent.beginning! - Rational.one), isFalse);
      // A point of size zero holds at exactly one instant -- the same
      // derivation, differing in size rather than in kind.
      final tip = FrameEnd('era:two', position: const Position.point(pointBeginning));
      expect(frameEndMatches(law, tip, extent.beginning!), isTrue);
      expect(frameEndMatches(law, tip, extent.beginning! + Rational.one), isFalse);
    });

    test('a basis with no power to label a point refuses in words, and the '
        'staple that reaches it still orders the chain', () {
      final world = World();
      world.era(
        'era:dawn',
        key: 'DAWN',
        countable: false,
      );
      world.era(
        'era:one',
        key: 'E1',
        years: '100',
        anchor: const {'year': '1', 'properYear': '1'},
      );
      // "the end of 1 staples to all of 2" -- here the uncountable era is the
      // one that cannot label a point, so the inclusive connection runs to it.
      boundary(world, finishes: 'era:one', begins: const ['era:dawn'], beginsAt: 'all');
      final staples = staplesOf(world);
      expect(extentOf(world, 'era:dawn'), isNull);
      expect(staples.positionDays('era:dawn', const Position.point('all')), isNull);
      expect(
        staples.pointRefusal('era:dawn', const Position.point('all')),
        allOf(contains('does not say where it begins'), contains('all of it')),
      );
      // ORDERING IS WHAT AN ERA WITH NO YEAR AXIS DOES HAVE.
      expect(
        successionEdges(world.document).map((edge) => '${edge.from}>${edge.to}'),
        contains('era:one>era:dawn'),
      );
      expect(eraChainPaths(world.document, 'era:one'), [
        ['era:one', 'era:dawn'],
      ]);
      // ASSOCIATION WITHOUT PROJECTION. The pile picks the Dawn Era up with
      // everything else, and no position on it lands on wall time -- the
      // null-point answer, reached from the other direction.
      final projection = FrameProjection(world.document.toJson());
      expect(projection.framesProject('era:dawn', 'frame:wall-time'), isFalse);
      expect(
        Correspondences(staples).landing(
          'era:dawn',
          'frame:wall-time',
          Rational.zero,
        ).refusal,
        isNotNull,
      );
    });

    test('an identification that names neither bound orders nothing', () {
      final world = World();
      world.era(
        'era:one',
        key: 'E1',
        years: '100',
        anchor: const {'year': '1', 'properYear': '1'},
      );
      world.era('era:two', key: 'E2', years: '100');
      // "the end of 1 could just as easily connect to three weeks into 2" -- a
      // true statement about where they meet, and NOT a statement about which
      // follows which.
      world.staple(
        ends: [
          StapleEnd.frame('era:one', position: const Position.point(pointEnd)),
          StapleEnd.frame('era:two', position: const Position.point('beginning + 21 * day')),
        ],
      );
      expect(successionEdges(world.document), isEmpty);
    });
  });

  group('the old spelling is one spelling', () {
    test('a positionless record and an authored-point record are the same '
        'statement, and the file is untouched', () {
      final random = Random(runSeed + 2);
      for (var i = 0; i < 16; i += 1) {
        final lengths = [
          for (var era = 0; era < 2 + random.nextInt(3); era += 1) 1 + random.nextInt(300),
        ];
        Document build({required bool spelled}) {
          final world = World();
          for (final (index, years) in lengths.indexed) {
            world.era(
              'era:$index',
              key: 'E$index',
              years: '$years',
              anchor: index == 0 ? const {'year': '1', 'properYear': '1'} : null,
            );
            if (index == 0) continue;
            if (spelled) {
              boundary(world, finishes: 'era:${index - 1}', begins: ['era:$index']);
            } else {
              world.succeed('era:${index - 1}', 'era:$index');
            }
          }
          return world.document;
        }

        final legacy = build(spelled: false), authored = build(spelled: true);
        final last = 'era:${lengths.length - 1}';
        expect(eraChainFrames(legacy, last), eraChainFrames(authored, last));
        for (var index = 0; index < lengths.length; index += 1) {
          final left = frameEraContext(legacy, 'era:$index')!.entry!;
          final right = frameEraContext(authored, 'era:$index')!.entry!;
          expect(left.firstProper, right.firstProper);
          expect(left.lastProper, right.lastProper);
        }
        // THE FILE IS THE TRUTH. Reading a positionless end as a point is a
        // READING; nothing is rewritten, so the record saves back as it loaded.
        for (final relation in legacy.relations.values) {
          if (!relation.isStaple) continue;
          expect(relation.toJson()['ends'], [
            for (final end in relation.ends) end.toJson(),
          ]);
          for (final end in relation.ends) {
            if (end is FrameEnd) expect(end.toJson().containsKey('point'), isFalse);
          }
        }
      }
    });

    test('a positionless end is read as the point the order always meant', () {
      final world = World();
      world.era(
        'era:one',
        key: 'E1',
        years: '100',
        anchor: const {'year': '1', 'properYear': '1'},
      );
      world.era('era:two', key: 'E2', years: '100', after: 'era:one');
      final staple = world.document.relations.values.firstWhere((it) => it.isStaple);
      expect(staple.kind, 'succession');
      final read = staple.readEnds.whereType<FrameEnd>().toList();
      expect(pointSourceOf(read[0].position?.point), (from: pointEnd, to: pointEnd));
      expect(pointSourceOf(read[1].position?.point), (from: pointBeginning, to: pointBeginning));
      // And it now NAMES AN INSTANT, which is the split projecting.
      final staples = staplesOf(world);
      expect(staples.frameEndDays(read[0]), extentOf(world, 'era:one')!.end);
      expect(staples.frameEndDays(read[1]), extentOf(world, 'era:two')!.beginning);
    });

    test('a lone frame end is left alone: one sheet pierced at an unnamed point '
        'claims no bound', () {
      final world = World();
      world.era(
        'era:one',
        key: 'E1',
        years: '100',
        anchor: const {'year': '1', 'properYear': '1'},
      );
      final object = world.object();
      final staple = world.staple(
        ends: [StapleEnd.object(object), StapleEnd.frame('era:one')],
      );
      expect(staple.readEnds.whereType<FrameEnd>().single.position, isNull);
      expect(successionEdges(world.document), isEmpty);
    });
  });

  group('THE SUNDERING, authored as points', () {
    // "in the mythic age humans and elves got along then the sundering came and
    // they have kept separate calendars since. they agree on era 1 and the
    // sundering when they split but nothing since."
    World sundered() {
      final world = World();
      world.era(
        'era:mythic',
        key: 'MY',
        years: '500',
        anchor: const {'year': '1', 'properYear': '1'},
      );
      world.era('era:elves', key: 'EL', years: '300');
      world.era('era:men', key: 'ME', years: '300');
      boundary(world, finishes: 'era:mythic', begins: const ['era:elves', 'era:men']);
      return world;
    }

    test('one boundary, two successors, no order invented between them', () {
      final world = sundered();
      expect(
        successionEdges(world.document).map((edge) => '${edge.from}>${edge.to}').toSet(),
        {'era:mythic>era:elves', 'era:mythic>era:men'},
      );
      expect(eraChainPaths(world.document, 'era:mythic'), [
        ['era:mythic', 'era:elves'],
        ['era:mythic', 'era:men'],
      ]);
    });

    test('both successors begin at the split, and the split is where the mythic '
        'age runs out', () {
      final world = sundered();
      final split = extentOf(world, 'era:mythic')!.end;
      expect(split, isNotNull);
      expect(at(world, 'era:elves', pointBeginning), split);
      expect(at(world, 'era:men', pointBeginning), split);
      // Neither table knows the other's eras.
      expect(frameEraContext(world.document, 'era:elves')!.table!.eraKeys(), ['MY', 'EL']);
      expect(frameEraContext(world.document, 'era:men')!.table!.eraKeys(), ['MY', 'ME']);
    });

    test('the shared era lies on both successions and refuses to pick one', () {
      final world = sundered();
      expect(
        () => eraChainFrames(world.document, 'era:mythic'),
        throwsA(
          isA<LawRefusal>().having(
            (error) => error.message,
            'message',
            contains('lies on 2 successions'),
          ),
        ),
      );
    });
  });

  group('THE SPLIT PROJECTS', () {
    // Ruled 8.31: the split is projectable as written, "derived from where the
    // earlier era runs out". Two eras of one calendar are one sheet, so the
    // claim only means something across sheets: here the boundary is identified
    // with an instant on wall time, and the second era's own beginning -- which
    // nobody wrote a coordinate for -- lands there exactly.
    test('the boundary instant lands on another sheet without anyone writing a '
        'coordinate for it', () {
      final world = World();
      // A calendar of its own, so its space is not wall time's -- and two eras
      // over it, authored here rather than through the shared helper because
      // that one only builds wall-time eras.
      world.document = world.document.put(
        'frames',
        'calendar:other',
        const Frame(
          id: 'calendar:other',
          title: 'Another reckoning',
          traits: ['line', 'temporal'],
          extra: {
            'coordinate': {
              'kind': 'nested',
              'levels': [
                {'name': 'season'},
                {'name': 'span', 'within': 'season', 'radix': '12'},
                {'name': 'tick', 'within': 'span', 'radix': '30'},
              ],
            },
          },
        ),
      );
      for (final (id, key, anchor) in [
        ('age:first', 'AF', const {'year': '1', 'properYear': '1'}),
        ('age:second', 'AS', null),
      ]) {
        world.document = world.document.put(
          'frames',
          id,
          Frame(
            id: id,
            title: 'The $key age',
            traits: const ['line', 'temporal', 'era'],
            extra: {
              'basis': 'calendar:other',
              'era': {
                'key': key,
                'name': 'The $key age',
                'direction': 'ascending',
                'years': '40',
                'firstYear': '1',
                'anchor': ?anchor,
              },
            },
          ),
        );
      }
      boundary(world, finishes: 'age:first', begins: const ['age:second']);
      // ONE identification between the boundary and wall time. Nothing names a
      // coordinate on the era side.
      world.staple(
        ends: [
          StapleEnd.frame('age:first', position: const Position.point(pointEnd)),
          StapleEnd.frame('frame:wall-time', position: Position.coordinate(civil(2026, 1, 1))),
        ],
      );
      final staples = staplesOf(world);
      final wall = staples.daysOf('frame:wall-time', Coordinate.fromJson(civil(2026, 1, 1)))!;
      final split = extentOf(world, 'age:first')!.end!;
      expect(at(world, 'age:second', pointBeginning), split);
      final landing = Correspondences(staples).landing('age:second', 'frame:wall-time', split);
      expect(landing.refusal, isNull);
      expect(landing.at, [wall]);
      expect(landing.exact, isTrue);
    });
  });

  group('the boundary may itself be a frame', () {
    // "it could also be a frame 3 years long and be filled with the chronicals
    // of the sundering war, and at zoom out it shows a point 1 ends 2&3 begin
    // and on zoom in it shows the sundering as its own mini-era."
    test('a mini-era stapled at both its ends is just frames, and nothing '
        'refuses that shape', () {
      final world = World();
      world.era(
        'era:one',
        key: 'E1',
        years: '100',
        anchor: const {'year': '1', 'properYear': '1'},
      );
      world.era('era:war', key: 'WAR', years: '3');
      world.era('era:two', key: 'E2', years: '100');
      boundary(world, finishes: 'era:one', begins: const ['era:war']);
      boundary(world, finishes: 'era:war', begins: const ['era:two']);
      expect(eraChainFrames(world.document, 'era:war'), [
        'era:one',
        'era:war',
        'era:two',
      ]);
      final war = extentOf(world, 'era:war')!;
      expect(war.beginning, extentOf(world, 'era:one')!.end);
      expect(war.end, extentOf(world, 'era:two')!.beginning);
      // ZOOMED OUT IT IS A POINT AND ZOOMED IN IT IS AN ERA -- and the model
      // holds both readings at once because the sized thing is the frame.
      expect(war.end! - war.beginning!, greaterThan(Rational.zero));
      final entry = frameEraContext(world.document, 'era:war')!.entry!;
      expect(entry.years, BigInt.from(3));
    });
  });
}
