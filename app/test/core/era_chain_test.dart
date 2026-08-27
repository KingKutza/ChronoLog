// Eras are frames stapled together: the chain's spec.
//
// Generative by ruling. The properties quantify over random chains -- random
// length, random pin position, random era lengths, and the caller asking from a
// random member -- and over MUTATIONS of a resolvable chain (fork, loop, two
// pins, no pin) which must each refuse and name the whole scope once.
//
// R4 is the ruling under test: succession direction is `ends[0] -> ends[1]`. No
// `role` field appears anywhere in this file or in the builder it uses, so a
// chain that resolves here proves the derivation reads ORDER and nothing else.
//
// The elder-scrolls fixture is not read: `tools/load-dataset.js` is not ported,
// so the chain is HAND-BUILT to the same shape (era frames + succession staples
// + one authored pin). Stated, not implied.

import 'dart:math';

import 'package:chronolog/core/coordinate_law.dart';
import 'package:chronolog/core/era_chain.dart';
import 'package:chronolog/core/eras.dart';
import 'package:chronolog/core/exact.dart';
import 'package:test/test.dart';

import '../helpers/staple_world.dart';

const int specSeed = 20260827;
const int iterations = 120;

/// Tamriel's chain, oldest first: the Dawn Era has no year axis at all, the
/// Merethic counts DOWN and is open below, and the First Era carries the one pin.
World tamriel() {
  final world = World();
  world.era('era:dawn', key: 'Dawn', name: 'Dawn Era', countable: false);
  world.era(
    'era:merethic',
    key: 'ME',
    name: 'Merethic Era',
    direction: 'descending',
    after: 'era:dawn',
  );
  world.era(
    'era:first',
    key: '1E',
    name: 'First Era',
    years: '2920',
    anchor: {'year': '1', 'properYear': '1'},
    after: 'era:merethic',
  );
  world.era('era:second', key: '2E', name: 'Second Era', years: '896', after: 'era:first');
  world.era('era:third', key: '3E', name: 'Third Era', years: '433', after: 'era:second');
  world.era('era:fourth', key: '4E', name: 'Fourth Era', after: 'era:third');
  return world;
}

/// Two eras stapled at the epoch: BCE descending and open below, CE ascending
/// and open above. No year zero exists because none is declared.
World bceCe() {
  final world = World();
  world.era(
    'era:bce',
    key: 'BCE',
    name: 'Before Common Era',
    direction: 'descending',
    affix: 'suffix',
  );
  world.era(
    'era:ce',
    key: 'CE',
    name: 'Common Era',
    affix: 'suffix',
    anchor: {'year': '1', 'properYear': '1'},
    after: 'era:bce',
  );
  return world;
}

Rational _at(CoordinateLaw law, int year, [int month = 1, int day = 1]) =>
    law.toDays(Coordinate.fromJson(civil(year, month, day)));

CoordinateLaw _law(World world, String frameId) =>
    CoordinateLaws(eras: eraLookup(world.document)).of(world.document.toJson(), frameId);

void main() {
  group('R4 -- succession direction is the order of the ends', () {
    test('a random chain orders oldest first from whichever era the caller '
        'names, and derives every range from one pin', () {
      final random = Random(specSeed);
      for (var i = 0; i < iterations; i += 1) {
        final world = World();
        final length = 2 + random.nextInt(7);
        final lengths = [for (var era = 0; era < length; era += 1) 1 + random.nextInt(4000)];
        final pin = random.nextInt(length);
        final pinYear = 1 + random.nextInt(lengths[pin]);
        final pinProper = -2000 + random.nextInt(6000);
        final ids = [for (var era = 0; era < length; era += 1) 'era:$era'];
        for (final (index, id) in ids.indexed) {
          world.era(
            id,
            key: 'E$index',
            years: '${lengths[index]}',
            anchor: index == pin ? {'year': '$pinYear', 'properYear': '$pinProper'} : null,
            after: index == 0 ? null : ids[index - 1],
          );
        }
        // Asked from any member, the answer is the whole chain, oldest first.
        final asked = ids[random.nextInt(length)];
        expect(eraChainFrames(world.document, asked), ids);
        final chain = eraChain(world.document, asked)!;
        expect(chain.ordered, ids);
        expect(chain.countable, ids);
        expect(chain.pin, ids[pin]);

        // Restated from the ruling: the pin says where ITS era's year sits, and
        // every other era's range follows by contiguity outward. Ascending eras
        // number from their first year, so the offset is measured from it.
        final first = <BigInt>[], last = <BigInt>[];
        var at = BigInt.from(pinProper) - BigInt.from(pinYear - 1);
        for (var index = pin; index < length; index += 1) {
          first.add(at);
          last.add(at + BigInt.from(lengths[index]) - BigInt.one);
          at = last.last + BigInt.one;
        }
        at = first.first;
        for (var index = pin - 1; index >= 0; index -= 1) {
          final end = at - BigInt.one;
          first.insert(0, end - BigInt.from(lengths[index]) + BigInt.one);
          last.insert(0, end);
          at = first.first;
        }
        for (final (index, id) in ids.indexed) {
          final entry = chain.byFrame[id]!;
          expect(entry.firstProper, first[index], reason: '$id begins');
          expect(entry.lastProper, last[index], reason: '$id ends');
          // Eras meet exactly: no gap and no overlap.
          if (index > 0) {
            expect(entry.firstProper, last[index - 1] + BigInt.one);
          }
        }
      }
    });

    test('reversing one staple\'s ends reverses what follows what', () {
      // The proof that direction is read from ORDER: nothing else about the
      // record changes, and no `role` field exists to consult.
      final random = Random(specSeed + 1);
      for (var i = 0; i < iterations; i += 1) {
        final world = World();
        world.era('era:one', key: 'E1', years: '100', anchor: {'year': '1', 'properYear': '1'});
        world.era('era:two', key: 'E2', years: '100', after: 'era:one');
        expect(eraChainFrames(world.document, 'era:one'), ['era:one', 'era:two']);
        final staple = world.document.relations.values.singleWhere(
          (relation) => relation.kind == 'succession',
        );
        world.document = world.document.put(
          'relations',
          staple.id,
          staple.withField('ends', [for (final end in staple.ends.reversed) end.toJson()]),
        );
        expect(eraChainFrames(world.document, 'era:one'), ['era:two', 'era:one']);
        // And the derived ranges follow the new order, not the old one.
        final chain = eraChain(world.document, 'era:one')!;
        expect(chain.byFrame['era:two']!.lastProper, BigInt.zero);
        expect(random.nextInt(2), lessThan(2));
      }
    });
  });

  group('a chain that says two contradictory things refuses', () {
    test('a fork, a loop, two pins and no pin each refuse, naming the chain '
        'once', () {
      final random = Random(specSeed + 2);
      for (var i = 0; i < iterations; i += 1) {
        final world = tamriel();
        // The unmutated chain resolves.
        expect(eraChain(world.document, 'era:third'), isNotNull);
        final members = eraChainMembers(world.document, 'era:third');
        expect(members, hasLength(6));

        switch (random.nextInt(4)) {
          case 0: // A fork: two eras claim the same predecessor.
            world.succeed('era:first', 'era:fourth');
            expect(
              () => eraChainFrames(world.document, 'era:first'),
              throwsA(
                isA<LawRefusal>().having(
                  (error) => error.message,
                  'message',
                  contains('cannot fork'),
                ),
              ),
            );
          case 1: // A loop: the chain has no beginning.
            world.succeed('era:fourth', 'era:dawn');
            expect(
              () => eraChainFrames(world.document, 'era:first'),
              throwsA(
                isA<LawRefusal>().having(
                  (error) => error.message,
                  'message',
                  anyOf(contains('no beginning'), contains('loop')),
                ),
              ),
            );
          case 2: // Two pins are two facts that can disagree.
            world.era(
              'era:third',
              key: '3E',
              name: 'Third Era',
              years: '433',
              anchor: {'year': '1', 'properYear': '3817'},
            );
            expect(
              () => eraChain(world.document, 'era:first'),
              throwsA(
                isA<LawRefusal>().having(
                  (error) => error.message,
                  'message',
                  contains('pinned 2 times'),
                ),
              ),
            );
          case 3: // No pin: the chain states nowhere that it sits.
            world.era('era:first', key: '1E', name: 'First Era', years: '2920');
            expect(
              () => eraChain(world.document, 'era:first'),
              throwsA(
                isA<LawRefusal>().having(
                  (error) => error.message,
                  'message',
                  contains('states nowhere that it sits'),
                ),
              ),
            );
        }
        // A refused ordering still knows its whole scope, so a caller reports
        // the chain ONCE instead of once per era in it.
        final after = eraChainMembers(world.document, 'era:third');
        expect(after, hasLength(6));
        expect(after.toSet(), members.toSet());
      }
    });

    test('two eras joined only through a non-era frame have two beginnings', () {
      final world = World();
      world.era('era:one', key: 'E1', years: '100', anchor: {'year': '1', 'properYear': '1'});
      world.era('era:two', key: 'E2', years: '100');
      // `calendar:work` is not an era, so neither edge survives the narrowing
      // and both eras are left claiming to begin the chain.
      world.succeed('era:one', 'calendar:work');
      world.succeed('calendar:work', 'era:two');
      expect(eraChainMembers(world.document, 'era:one'), hasLength(2));
      expect(
        () => eraChainFrames(world.document, 'era:one'),
        throwsA(
          isA<LawRefusal>().having(
            (error) => error.message,
            'message',
            allOf(contains('2 beginnings'), contains('era:two')),
          ),
        ),
      );
    });

    test('a frame that is not an era has no era context, and belongs to no '
        'chain', () {
      final world = tamriel();
      expect(frameEraContext(world.document, 'calendar:work'), isNull);
      expect(frameEraContext(world.document, 'frame:wall-time'), isNull);
      expect(eraChainFrames(world.document, 'calendar:work'), isEmpty);
      expect(eraChain(world.document, 'calendar:work'), isNull);
      expect(isEraFrame(world.document.frames['calendar:work']), isFalse);
      expect(isEraFrame(null), isFalse);
    });
  });

  group('a non-countable era takes part in the order and nothing else', () {
    test('it is in the chain, out of the table, and its law refuses ordinals', () {
      final world = tamriel();
      expect(isCountableEra(world.document.frames['era:dawn']), isFalse);
      expect(eraChainFrames(world.document, 'era:dawn').first, 'era:dawn');
      final chain = eraChain(world.document, 'era:dawn')!;
      expect(chain.ordered, contains('era:dawn'));
      expect(chain.countable, isNot(contains('era:dawn')));
      expect(chain.byFrame.containsKey('era:dawn'), isFalse);

      final context = frameEraContext(world.document, 'era:dawn')!;
      expect(context.countable, isFalse);
      expect(context.identity, 'Dawn');
      expect(context.label, 'Dawn Era');

      final law = _law(world, 'era:dawn');
      expect(law.positional, isFalse);
      expect(law.mapsToClock(), isFalse, reason: 'no year axis means no now');
      expect(
        () => law.toDays(Coordinate.fromJson(civil(1))),
        throwsA(
          isA<LawRefusal>().having(
            (error) => error.message,
            'message',
            contains('has no year axis'),
          ),
        ),
      );
      expect(() => law.fromDays(Rational.zero), throwsA(isA<LawRefusal>()));
    });

    test('a non-countable era cannot anchor the chain', () {
      final world = World();
      world.era(
        'era:dawn',
        key: 'Dawn',
        countable: false,
        anchor: {'year': '1', 'properYear': '1'},
      );
      world.era('era:after', key: 'AE', years: '100', after: 'era:dawn');
      expect(
        () => eraChain(world.document, 'era:dawn'),
        throwsA(
          isA<LawRefusal>().having(
            (error) => error.message,
            'message',
            contains('no year axis, so it cannot anchor'),
          ),
        ),
      );
    });
  });

  group('the CoordinateLaws hook', () {
    test('INTEGRATION: a document with succession staples yields laws whose '
        'formatYear is era-qualified through the hook', () {
      final world = tamriel();
      final raw = world.document.toJson();
      final withEras = CoordinateLaws(eras: eraLookup(world.document));
      final law = withEras.of(raw, 'era:third');
      expect(law.hasEras(), isTrue);
      expect(law.eraKey(), '3E');
      expect(law.formatYear(Coordinate.fromJson(civil(433))), '3E 433');

      // The era is the FRAME, so a coordinate on it carries a plain year and no
      // era level of its own -- and it round-trips as the author wrote it.
      final days = law.toDays(Coordinate.fromJson(civil(433, 1, 1)));
      final back = law.fromDays(days);
      expect(back.has('era'), isFalse);
      expect(back.value('year'), '433');
      expect(law.toDays(back), days);
      expect(law.formatYearAtDays(days), '3E 433');

      // Without the hook the same frame is an ordinary Gregorian line: the era
      // comes from the chain, not from anything on the declaration.
      final without = CoordinateLaws().of(raw, 'era:third');
      expect(without.hasEras(), isFalse);
      expect(without.formatYear(Coordinate.fromJson(civil(433))), '433');
    });

    test('era order is day order across the whole chain', () {
      final world = tamriel();
      final merethic = _law(world, 'era:merethic');
      final first = _law(world, 'era:first');
      final second = _law(world, 'era:second');
      final chain = [
        _at(merethic, 2500),
        _at(merethic, 1000),
        _at(merethic, 1),
        _at(first, 1),
        _at(first, 2920),
        _at(second, 1),
      ];
      for (final (index, value) in chain.indexed) {
        if (index > 0) {
          expect(chain[index - 1] < value, isTrue, reason: 'at $index');
        }
      }
      // Merethic counts DOWN: its higher number is the older year.
      final table = eraChain(world.document, 'era:first')!.table;
      expect(table.era('1E')!.lastProper! + BigInt.one, table.era('2E')!.firstProper);
      // Exactly one year between them, of whatever length that year is.
      final gap = _at(second, 1) - _at(first, 2920);
      expect(gap == Rational.fromInt(365) || gap == Rational.fromInt(366), isTrue);
    });

    test('an ordinal outside an era\'s own range refuses rather than '
        'renumbering into its neighbour', () {
      final world = tamriel();
      final third = _law(world, 'era:third');
      final fourth = _law(world, 'era:fourth');
      expect(
        () => third.fromDays(_at(fourth, 5)),
        throwsA(
          isA<LawRefusal>().having(
            (error) => error.message,
            'message',
            contains('falls in Fourth Era, not Third Era'),
          ),
        ),
      );
      expect(
        () => _at(third, 434),
        throwsA(
          isA<LawRefusal>().having(
            (error) => error.message,
            'message',
            contains('only 433 years long'),
          ),
        ),
      );
    });

    test('RULED ANCHOR: BCE crosses to CE with no year zero, on the stapled '
        'chain', () {
      final world = bceCe();
      final table = eraChain(world.document, 'era:ce')!.table;
      // Structural adjacency: 1 BCE is proper year 0 and 1 CE is proper year 1.
      expect(table.toProperYear('BCE', '1'), BigInt.zero);
      expect(table.toProperYear('CE', '1'), BigInt.one);
      // 44 BCE is proper year -43 -- the fencepost, derived, not special-cased.
      expect(table.toProperYear('BCE', '44'), BigInt.from(-43));

      final bce = _law(world, 'era:bce');
      final ce = _law(world, 'era:ce');
      // In days: 1 BCE runs straight into 1 CE, and that year is 366 days,
      // because proleptic year 0 is divisible by 400.
      expect(_at(bce, 1) < _at(ce, 1), isTrue);
      expect(_at(ce, 1) - _at(bce, 1), Rational.fromInt(366));
      // Descending: an older BCE year is a smaller ordinal, and each era's own
      // authored affix is what renders.
      expect(_at(bce, 44) < _at(bce, 1), isTrue);
      expect(bce.formatYear(Coordinate.fromJson(civil(44))), '44 BCE');
      expect(ce.formatYear(Coordinate.fromJson(civil(2026))), '2026 CE');
      // Round trip both sides, era-local years throughout.
      for (final (law, year) in [(bce, 44), (bce, 1), (ce, 1), (ce, 2026)]) {
        final days = _at(law, year, 3, 15);
        final back = law.fromDays(days);
        expect(back.value('year'), '$year');
        expect(law.toDays(back), days);
      }
      // A CE ordinal read through the BCE frame is refused, not renumbered.
      expect(
        () => bce.fromDays(_at(ce, 2026)),
        throwsA(
          isA<LawRefusal>().having(
            (error) => error.message,
            'message',
            contains('falls in Common Era, not Before Common Era'),
          ),
        ),
      );
    });

    test('the hook notices a re-pinned chain rather than serving a stale law', () {
      final random = Random(specSeed + 3);
      for (var i = 0; i < iterations; i += 1) {
        final world = tamriel();
        expect(_law(world, 'era:third').eraKey(), '3E');
        final before = eraChain(world.document, 'era:first')!.byFrame['era:third']!.firstProper;
        final moved = 1 + random.nextInt(4000);
        world.era(
          'era:first',
          key: '1E',
          name: 'First Era',
          years: '2920',
          anchor: {'year': '1', 'properYear': '$moved'},
        );
        final after = eraChain(world.document, 'era:first')!.byFrame['era:third']!.firstProper;
        expect(after! - before!, BigInt.from(moved - 1));
        // The same era-local coordinate now resolves that much later, through a
        // law resolved after the edit.
        expect(_law(world, 'era:third').formatYear(Coordinate.fromJson(civil(433))), '3E 433');
      }
    });
  });
}
