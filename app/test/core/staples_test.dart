// The staple substrate's spec.
//
// Generative by ruling (Don, 2026-08-27): "We should never be testing for a
// specific case, we should be testing for a general case." Every assertion below
// is a property quantified over seeded random generation, except the ones
// labelled RULED ANCHOR -- a worked example the ruling itself states, or a
// regression the owner reported in those words, neither of which is derivable
// from a property.
//
// The restatements (`_expectedExtent`, `_lastInstantOfDay`, `_shape`) are
// written from the RULING TEXT and from `exact.dart`'s own calendar kernel,
// deliberately not from staples.dart, so agreement between them means something.
//
// The seed is fixed so a failure reproduces exactly. Change it only to widen
// coverage deliberately, never to make a red suite green.

import 'dart:math';

import 'package:chronolog/core/coordinate_law.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/core/staples.dart';
import 'package:test/test.dart';

import '../helpers/staple_world.dart';

const int specSeed = 20260827;
const int iterations = 120;

T _pick<T>(Random random, List<T> items) => items[random.nextInt(items.length)];

Rational _minutes(int count) => Rational.fromInt(count, 1440);

Rational _days(int year, int month, int day) =>
    Rational(daysFromCivil(BigInt.from(year), month, day));

/// The last measurable instant of a whole day, from the calendar kernel and the
/// registered standard's own finest unit -- not from staples.dart.
Rational _lastInstantOf(Rational firstInstant) =>
    firstInstant + Rational.one - Rational.fromInt(1, 86400);

/// The ruled anchor precedence, restated: `start` outranks `end` outranks
/// `midpoint` outranks any point the user named.
int _rank(String role) {
  final index = const ['start', 'end', 'midpoint'].indexOf(role);
  return index == -1 ? 3 : index;
}

/// The three role pairs the substrate can derive a magnitude from, restated from
/// the ruling. Every other pairing involves a named point whose relationship to
/// the other anchor nobody declared, and refuses.
Rational? _pairMagnitude(String first, String second, Rational a, Rational b) =>
    switch ('$first+$second') {
      'start+end' => b - a,
      'start+midpoint' => (b - a) * Rational.fromInt(2),
      'end+midpoint' => (a - b) * Rational.fromInt(2),
      _ => null,
    };

/// The whole ruled derivation, restated: the magnitude comes from the two
/// highest-precedence anchors when their pairing defines one, otherwise from the
/// object's own duration; the extent is placed from the LEADING anchor.
({Rational? start, Rational? end, String source}) _expectedExtent(
  List<({String role, Rational days})> anchors,
  Rational duration,
) {
  final sorted = [...anchors]..sort((a, b) => _rank(a.role) - _rank(b.role));
  if (sorted.isEmpty) return (start: null, end: null, source: 'unstapled');
  final derived = sorted.length < 2
      ? null
      : _pairMagnitude(sorted[0].role, sorted[1].role, sorted[0].days, sorted[1].days);
  final size = derived == null ? duration : derived.abs();
  final at = sorted[0].days;
  final half = size / Rational.fromInt(2);
  final (start, end) = switch (sorted[0].role) {
    'end' => (at - size, at),
    'midpoint' => (at - half, at + half),
    _ => (at, at + size),
  };
  return (start: start, end: end, source: derived == null ? 'anchor+magnitude' : 'anchors');
}

StapleEnd _frameAt(Json coordinate, [String frame = 'calendar:work']) =>
    StapleEnd.frame(frame, position: Position.coordinate(coordinate));

void main() {
  group('R3 -- a staple is two ends in order, and any two may join', () {
    test('authoring the ends in the other order describes the identical '
        'connection', () {
      final random = Random(specSeed);
      for (var i = 0; i < iterations; i += 1) {
        final world = World();
        final object = world.object(duration: '60');
        final at = civil(
          2026,
          1 + random.nextInt(12),
          1 + random.nextInt(28),
          random.nextInt(24),
          0,
          0,
        );
        final ends = <StapleEnd>[
          StapleEnd.object(object, point: _pick(random, ['start', 'end', 'midpoint'])),
          _frameAt(at),
        ];
        final forward = world.staple(kind: 'anchor', ends: ends);
        final reversed = world.staple(kind: 'anchor', ends: ends.reversed.toList());
        final staples = world.staples;
        // Direction is not STORED, so the instant each names is one instant.
        expect(staples.stapleDays(forward), staples.stapleDays(reversed));
        expect(
          forward.ends.map((end) => end.id).toSet(),
          reversed.ends.map((end) => end.id).toSet(),
        );
        // Two ends IN ORDER: index 0 of one is index 1 of the other, and
        // `otherThan` is the same involution read from either side.
        expect(forward.otherThan(0)!.id, reversed.ends.first.id);
        expect(forward.otherThan(1)!.id, reversed.ends.last.id);
        // Both things reach it, which is what every cascade sweep relies on.
        expect(staples.staplesForObject(object), hasLength(2));
      }
    });

    test('every ordered pair of scopes joins -- the end-scope gate is gone', () {
      // The JavaScript refused six of these nine outright ("cannot connect
      // object to series", `frame+frame` only for a correspondence). Under the
      // directional-not-typed ruling the substrate does not ask.
      final world = World();
      final object = world.object(duration: '30');
      final other = world.object(duration: '30');
      final series = world.pattern();
      final ends = <String, StapleEnd>{
        'frame': _frameAt(civil(2026, 8, 20, 9, 0, 0)),
        'object': StapleEnd.object(object, point: 'end'),
        'series': StapleEnd.series(series),
      };
      final second = <String, StapleEnd>{
        'frame': _frameAt(civil(2026, 8, 21, 9, 0, 0)),
        'object': StapleEnd.object(other, point: 'start'),
        'series': StapleEnd.series(series),
      };
      for (final left in ends.keys) {
        for (final right in second.keys) {
          for (final kind in stapleKinds.keys) {
            final staple = world.staple(kind: kind, ends: [ends[left]!, second[right]!]);
            expect(staple.ends, hasLength(2), reason: '$kind $left+$right');
            expect(staple.ends.first.id, ends[left]!.id);
          }
        }
      }
      // And the derivations read them: a series-to-object `end` staple -- the
      // pairing the JavaScript named as refused -- is found from both sides.
      final staples = world.staples;
      expect(staples.staplesForSeries(series), isNotEmpty);
      expect(staples.staplesForObject(object), isNotEmpty);
    });

    test('a kind carries derivation flags only', () {
      // The registry answers what a kind DOES, never what it may join: there is
      // no `connects` to read, and every name below is a flag a derivation asks
      // for by name.
      expect(stapleKind('end')!.partitions, isTrue);
      expect(stapleKind('end')!.anchors, isFalse);
      expect(stapleKind('inflection')!.carriesRule, isTrue);
      expect(stapleKind('anchor')!.anchors, isTrue);
      expect(stapleKind('correspondence')!.anchors, isFalse);
      expect(stapleKind('correspondence')!.partitions, isFalse);
      expect(stapleKind('succession')!.positions, isFalse);
      expect(stapleKind('not-a-kind'), isNull);
      expect(stapleKind(null), isNull);
    });
  });

  group('the four position forms', () {
    test('only a coordinate is one instant; a selector, a span and a void '
        'answer membership instead', () {
      final random = Random(specSeed + 1);
      for (var i = 0; i < iterations; i += 1) {
        final world = World();
        final month = 1 + random.nextInt(12);
        final day = 1 + random.nextInt(28);
        final one = civil(2026, month, day);
        final world2 = world;
        final staple = world2.staple(
          kind: 'correspondence',
          ends: [_frameAt(stroke(1 + random.nextInt(6)), 'frame:invented'), _frameAt(one)],
        );
        final selector = world2.staple(
          kind: 'correspondence',
          ends: [
            _frameAt(stroke(2), 'frame:invented'),
            StapleEnd.frame(
              'calendar:work',
              position: const Position.selector({'cycle': 'weekday', 'value': 'Tuesday'}),
            ),
          ],
        );
        final span = world2.staple(
          kind: 'correspondence',
          ends: [
            _frameAt(stroke(3), 'frame:invented'),
            StapleEnd.frame(
              'calendar:work',
              position: Position.span({
                'from': civil(2026, month, day),
                'to': civil(2026, month, day, 23, 0, 0),
              }),
            ),
          ],
        );
        final nothing = world2.staple(
          kind: 'correspondence',
          ends: [
            _frameAt(stroke(4), 'frame:invented'),
            const StapleEnd.frame('calendar:work', position: Position.authoredVoid()),
          ],
        );
        final staples = world2.staples;
        final law = staples.lawOf('calendar:work')!;
        final instant = _days(2026, month, day);

        // Each end resolves under ITS OWN law, and neither coordinate is
        // readable through the other's.
        final invented = staples.lawOf('frame:invented')!;
        expect(
          staples.frameEndDays(staple.ends.first),
          invented.toDays(Coordinate.fromJson(staple.ends.first.toJson()['coordinate'] as Json)),
        );
        expect(staples.frameEndDays(staple.ends.last), instant);
        expect(staples.frameEndDays(staple.ends.first), isNot(instant));
        for (final many in [selector, span, nothing]) {
          expect(
            staples.frameEndDays(many.ends.last),
            isNull,
            reason: 'a many-valued or empty position is never one instant',
          );
        }
        // Membership is the question they can answer.
        expect(frameEndMatches(law, staple.ends.last, instant), isTrue);
        expect(frameEndMatches(law, staple.ends.last, instant + Rational.one), isFalse);
        expect(frameEndMatches(law, span.ends.last, instant), isTrue);
        expect(frameEndMatches(law, span.ends.last, instant - Rational.one), isFalse);
        expect(frameEndMatches(law, nothing.ends.last, instant), isFalse);
        // "Tuesdays" is every Tuesday and nothing else, decided by the frame's
        // own cycle rather than by the selector's spelling.
        expect(
          frameEndMatches(law, selector.ends.last, instant),
          law.weekdayLabel(instant) == 'Tuesday',
        );
      }
    });

    test("a selector means what THIS frame's declaration says", () {
      // RULED ANCHOR: the "Mon,Tue,Batman" field report. An authored name list
      // is what a selector reads, never the registered one.
      final world = World();
      world.document = world.document.put(
        'frames',
        'frame:renamed',
        Frame(
          id: 'frame:renamed',
          title: 'Renamed week',
          traits: ['line', 'temporal', 'gregorian'],
          extra: {
            'coordinate': {
              ...gregorianDeclarationJson,
              'cycles': [
                {
                  'name': 'weekday',
                  'radix': '7',
                  'offset': '4',
                  'names': ['Sun', 'Mon', 'Batman', 'Wed', 'Thu', 'Fri', 'Sat'],
                },
              ],
            },
          },
        ),
      );
      final staples = world.staples;
      final law = staples.lawOf('frame:renamed')!;
      final tuesday = _days(2026, 8, 18);
      expect(law.weekdayLabel(tuesday), 'Batman');
      StapleEnd named(String value) => StapleEnd.frame(
        'frame:renamed',
        position: Position.selector({'cycle': 'weekday', 'value': value}),
      );
      expect(frameEndMatches(law, named('Batman'), tuesday), isTrue);
      expect(frameEndMatches(law, named('batman'), tuesday), isTrue);
      expect(frameEndMatches(law, named('Tuesday'), tuesday), isFalse);
      // The numeric spelling of the same cycle position agrees with the name.
      expect(frameEndMatches(law, named('2'), tuesday), isTrue);
      // A level selector reads the level's own value under this frame's ladder.
      StapleEnd month(String value) => StapleEnd.frame(
        'frame:renamed',
        position: Position.selector({'level': 'month', 'value': value}),
      );
      expect(frameEndMatches(law, month('July'), _days(2026, 7, 4)), isTrue);
      expect(frameEndMatches(law, month('July'), _days(2027, 7, 30)), isTrue);
      expect(frameEndMatches(law, month('July'), _days(2026, 8, 4)), isFalse);
      expect(frameEndMatches(law, month('7'), _days(2026, 7, 4)), isTrue);
      // A cycle the frame never declared matches nothing rather than forever.
      expect(
        frameEndMatches(
          staples.lawOf('frame:invented')!,
          StapleEnd.frame(
            'frame:invented',
            position: const Position.selector({'cycle': 'weekday', 'value': 'Tuesday'}),
          ),
          Rational.zero,
        ),
        isFalse,
      );
    });
  });

  group('anchoring', () {
    test('the derived extent is the highest-precedence anchors\' own answer, '
        'and every other anchor is reported', () {
      final random = Random(specSeed + 2);
      for (var i = 0; i < iterations; i += 1) {
        final world = World();
        final duration = 30 + random.nextInt(600);
        final object = world.object(duration: '$duration');
        // One anchor per role, so precedence is a total order and the
        // restatement needs no tie-break of its own.
        final roles = ['start', 'end', 'midpoint', 'handover']..shuffle(random);
        final count = 1 + random.nextInt(4);
        final authored = <({String role, Rational days})>[];
        for (final role in roles.take(count)) {
          final day = 1 + random.nextInt(20);
          final hour = random.nextInt(24);
          world.staple(
            kind: 'anchor',
            ends: [
              StapleEnd.object(object, point: role),
              _frameAt(civil(2026, 8, day, hour, 0, 0)),
            ],
          );
          authored.add((role: role, days: _days(2026, 8, day) + Rational.fromInt(hour, 24)));
        }
        final extent = world.staples.resolveObjectExtent(object);
        final expected = _expectedExtent(authored, _minutes(duration));
        expect(extent.source, expected.source);
        expect(extent.startDays, expected.start);
        expect(extent.endDays, expected.end);
        // Nothing is averaged: the leading anchor's own instant survives.
        final leading = ([...authored]..sort((a, b) => _rank(a.role) - _rank(b.role))).first;
        expect(
          leading.role == 'start' ? extent.startDays : isNotNull,
          leading.role == 'start' ? leading.days : isNotNull,
        );
        // Every anchor the derivation did not believe is REPORTED, never
        // silently dropped.
        final believed = expected.source == 'anchors' ? 2 : 1;
        expect(extent.overdetermined.length, authored.length - min(believed, authored.length));
        expect(extent.cyclic, isFalse);
        expect(extent.unresolved, isEmpty);
      }
    });

    test('RULED ANCHOR: an end anchor plus the object\'s own magnitude places '
        'the shift, and moving the end moves the start', () {
      final world = World();
      final object = world.object(duration: '8', unit: 'hour');
      final staple = world.staple(
        kind: 'anchor',
        ends: [
          StapleEnd.object(object, point: 'end'),
          _frameAt(civil(2026, 8, 10, 17, 0, 0)),
        ],
      );
      var extent = world.staples.resolveObjectExtent(object);
      expect(extent.source, 'anchor+magnitude');
      expect(extent.startDays, _days(2026, 8, 10) + Rational.fromInt(9, 24));
      // The magnitude is PRESERVED and the start moves with the end, rather
      // than the start staying put and the magnitude being refit.
      world.staple(
        id: staple.id,
        kind: 'anchor',
        ends: [
          StapleEnd.object(object, point: 'end'),
          _frameAt(civil(2026, 8, 10, 18, 0, 0)),
        ],
      );
      extent = world.staples.resolveObjectExtent(object);
      expect(extent.startDays, _days(2026, 8, 10) + Rational.fromInt(10, 24));
      expect(extent.magnitudeDays, Rational.fromInt(8, 24));
    });

    test('RULED ANCHOR: two anchors derive the magnitude and the object\'s own '
        'duration is ignored for placement', () {
      final world = World();
      // Deliberately wrong: the object says two hours.
      final object = world.object(duration: '2', unit: 'hour');
      world.staple(
        kind: 'anchor',
        ends: [
          StapleEnd.object(object, point: 'start'),
          _frameAt(civil(2026, 8, 10, 9, 0, 0)),
        ],
      );
      world.staple(
        kind: 'anchor',
        ends: [
          StapleEnd.object(object, point: 'end'),
          _frameAt(civil(2026, 8, 10, 17, 30, 0)),
        ],
      );
      final extent = world.staples.resolveObjectExtent(object);
      expect(extent.source, 'anchors');
      expect(extent.derivedMagnitude, isTrue);
      expect(extent.magnitudeDays, Rational.fromInt(17, 2) / Rational.fromInt(24));
      expect(extent.startDays, _days(2026, 8, 10) + Rational.fromInt(9, 24));
    });

    test('RULED ANCHOR: an end+midpoint pair places the start EARLIER than '
        'either anchor', () {
      // The trap the ruling names: the magnitude is 2*(end - mid), so the start
      // is 2*mid - end. Placing from the earlier anchor would halve the event.
      final world = World();
      final object = world.object(duration: '5', unit: 'minute');
      world.staple(
        kind: 'anchor',
        ends: [
          StapleEnd.object(object, point: 'end'),
          _frameAt(civil(2026, 8, 10, 18, 0, 0)),
        ],
      );
      world.staple(
        kind: 'anchor',
        ends: [
          StapleEnd.object(object, point: 'midpoint'),
          _frameAt(civil(2026, 8, 10, 15, 0, 0)),
        ],
      );
      final extent = world.staples.resolveObjectExtent(object);
      expect(extent.magnitudeDays, Rational.fromInt(6, 24));
      expect(extent.startDays, _days(2026, 8, 10) + Rational.fromInt(12, 24));
      expect(extent.endDays, _days(2026, 8, 10) + Rational.fromInt(18, 24));
    });

    test('an overdetermined point is reported and never averaged', () {
      final random = Random(specSeed + 3);
      for (var i = 0; i < iterations; i += 1) {
        final world = World();
        final object = world.object(duration: '30');
        final role = _pick(random, ['start', 'end', 'midpoint']);
        final firstHour = random.nextInt(12);
        final secondHour = 12 + random.nextInt(12);
        for (final hour in [firstHour, secondHour]) {
          world.staple(
            kind: 'anchor',
            ends: [
              StapleEnd.object(object, point: role),
              _frameAt(civil(2026, 8, 10, hour, 0, 0)),
            ],
          );
        }
        final extent = world.staples.resolveObjectExtent(object);
        final first = _days(2026, 8, 10) + Rational.fromInt(firstHour, 24);
        final second = _days(2026, 8, 10) + Rational.fromInt(secondHour, 24);
        final resolved = switch (role) {
          'end' => extent.endDays!,
          'midpoint' => (extent.startDays! + extent.endDays!) / Rational.fromInt(2),
          _ => extent.startDays!,
        };
        expect(extent.overdetermined, hasLength(1));
        expect(extent.overdetermined.single.role, role);
        expect(extent.overdetermined.single.days, second);
        // One of the two authored values, never the mean of them.
        expect(resolved, first);
        expect(resolved, isNot((first + second) / Rational.fromInt(2)));
      }
    });

    test('RULED ANCHOR: an object placed by an attachment AND by a start anchor '
        'reports the contest', () {
      final world = World();
      final upstream = world.object(
        duration: '1',
        unit: 'hour',
        placedAt: civil(2026, 8, 10, 8, 0, 0),
      );
      final object = world.object(duration: '30', placedAt: civil(2026, 8, 10, 9, 30, 0));
      world.staple(
        kind: 'anchor',
        ends: [
          StapleEnd.object(object, point: 'start'),
          StapleEnd.object(upstream, point: 'end'),
        ],
      );
      final extent = world.staples.resolveObjectExtent(object);
      final connection = _days(2026, 8, 10) + Rational.fromInt(9, 24);
      final own = _days(2026, 8, 10) + Rational.fromInt(19, 48);
      expect(extent.startDays, connection);
      expect(extent.startDays, isNot((connection + own) / Rational.fromInt(2)));
      final contest = extent.overdetermined.singleWhere((item) => item.staple == null);
      expect(contest.relation!.type, 'attachment');
      expect(contest.role, 'start');
    });

    test('REGRESSION GUARD: an object with no anchor staples resolves to plain '
        'start-plus-duration placement, exactly', () {
      final random = Random(specSeed + 4);
      for (var i = 0; i < iterations; i += 1) {
        final world = World();
        final duration = random.nextInt(1440);
        final month = 1 + random.nextInt(12);
        final day = 1 + random.nextInt(28);
        final hour = random.nextInt(24);
        final object = world.object(
          duration: '$duration',
          placedAt: civil(2026, month, day, hour, 0, 0),
        );
        final extent = world.staples.resolveObjectExtent(object);
        final start = _days(2026, month, day) + Rational.fromInt(hour, 24);
        expect(extent.source, 'placement');
        expect(extent.startDays, start);
        expect(extent.endDays, start + _minutes(duration));
        expect(extent.magnitudeDays, _minutes(duration));
        expect(extent.anchors, isEmpty);
        expect(extent.overdetermined, isEmpty);
        expect(extent.spread.before, Rational.zero);
      }
    });

    test('an object nothing positions has no extent, and says so', () {
      final world = World();
      final object = world.object(duration: '30');
      final extent = world.staples.resolveObjectExtent(object);
      expect(extent.source, 'unstapled');
      expect(extent.startDays, isNull);
      expect(extent.endDays, isNull);
      // A placement whose frame cannot be read is a different answer from an
      // absent one: 'unresolved' says the author placed it somewhere this
      // build cannot resolve, which is not the same claim as 'nowhere'.
      final unreadable = world.object(
        duration: '30',
        placedAt: civil(2026, 8, 10),
        frame: 'frame:gone',
      );
      expect(world.staples.resolveObjectExtent(unreadable).source, 'unresolved');
    });

    test('chains compose: moving the head moves the tail by exactly as much', () {
      final random = Random(specSeed + 5);
      for (var i = 0; i < iterations; i += 1) {
        final world = World();
        final length = 2 + random.nextInt(4);
        final head = world.object(
          duration: '${1 + random.nextInt(4)}',
          unit: 'hour',
          placedAt: civil(2026, 8, 10, 9, 0, 0),
        );
        var previous = head;
        for (var link = 0; link < length; link += 1) {
          final next = world.object(duration: '${15 + random.nextInt(45)}');
          world.staple(
            kind: 'anchor',
            ends: [
              StapleEnd.object(next, point: 'start'),
              StapleEnd.object(previous, point: 'end'),
            ],
          );
          previous = next;
        }
        final before = world.staples.resolveObjectExtent(previous).startDays!;
        // Move the head: every link follows, exactly.
        final shiftHours = 1 + random.nextInt(6);
        final placement = world.document.relations.values.firstWhere(
          (relation) => isPlacement(relation, head),
        );
        world.document = world.document.put(
          'relations',
          placement.id,
          placement.withField('coordinate', civil(2026, 8, 10, 9 + shiftHours, 0, 0)),
        );
        final after = world.staples.resolveObjectExtent(previous).startDays!;
        expect(after - before, Rational.fromInt(shiftHours, 24));
      }
    });

    test('a cycle refuses to fabricate an instant, and the rest of the '
        'document still resolves', () {
      final random = Random(specSeed + 6);
      for (var i = 0; i < iterations; i += 1) {
        final world = World();
        final length = 2 + random.nextInt(3);
        final ring = [
          for (var link = 0; link < length; link += 1)
            world.object(duration: '${15 + random.nextInt(45)}'),
        ];
        for (var link = 0; link < length; link += 1) {
          world.staple(
            kind: 'anchor',
            ends: [
              StapleEnd.object(ring[link], point: 'start'),
              StapleEnd.object(ring[(link + 1) % length], point: 'end'),
            ],
          );
        }
        final unrelated = world.object(duration: '30', placedAt: civil(2026, 8, 11, 9, 0, 0));
        final staples = world.staples;
        for (final id in ring) {
          final extent = staples.resolveObjectExtent(id);
          expect(extent.startDays, isNull, reason: 'no fabricated instant');
          expect(extent.endDays, isNull);
          expect(extent.cyclic, isTrue, reason: 'the cycle is reported');
          expect(extent.unresolved, isNotEmpty);
        }
        expect(staples.resolveObjectExtent(unrelated).source, 'placement');
      }
    });

    test('uncertainties add along a connection and never cancel', () {
      final random = Random(specSeed + 7);
      for (var i = 0; i < iterations; i += 1) {
        final world = World();
        final before = 1 + random.nextInt(30);
        final after = 1 + random.nextInt(30);
        final chained = 1 + random.nextInt(30);
        final upstream = world.object(
          duration: '2',
          unit: 'hour',
          placedAt: civil(2026, 8, 10, 9, 0, 0),
        );
        world.staple(
          kind: 'anchor',
          ends: [
            StapleEnd.object(upstream, point: 'end'),
            _frameAt(civil(2026, 8, 10, 11, 0, 0)),
          ],
          spread: Spread(before: durationMagnitude('$before'), after: durationMagnitude('$after')),
        );
        final downstream = world.object(duration: '30');
        world.staple(
          kind: 'anchor',
          ends: [
            StapleEnd.object(downstream, point: 'start'),
            StapleEnd.object(upstream, point: 'end'),
          ],
          spread: Spread(before: durationMagnitude('$chained'), after: durationMagnitude('0')),
        );
        final staples = world.staples;
        final head = staples.resolveObjectExtent(upstream);
        final tail = staples.resolveObjectExtent(downstream);
        // durationMagnitude defaults to seconds, so the sums are exact seconds.
        expect(head.spread.before, Rational.fromInt(before, 86400));
        expect(tail.spread.before, Rational.fromInt(before + chained, 86400));
        expect(tail.spread.after, Rational.fromInt(after, 86400));
        // At least as uncertain as what it follows -- never less.
        expect(tail.spread.before >= head.spread.before, isTrue);
        expect(staples.isFuzzy(staples.staplesForObject(downstream).first), isTrue);
      }
    });

    test('two fuzzy anchors\' spreads add rather than cancel', () {
      final random = Random(specSeed + 8);
      for (var i = 0; i < iterations; i += 1) {
        final world = World();
        final object = world.object(duration: '8', unit: 'hour');
        final spreads = [
          for (var side = 0; side < 2; side += 1)
            (before: 1 + random.nextInt(30), after: 1 + random.nextInt(30)),
        ];
        for (final (index, role) in ['start', 'end'].indexed) {
          world.staple(
            kind: 'anchor',
            ends: [
              StapleEnd.object(object, point: role),
              _frameAt(civil(2026, 8, 10, index == 0 ? 9 : 17, 0, 0)),
            ],
            spread: Spread(
              before: durationMagnitude('${spreads[index].before}'),
              after: durationMagnitude('${spreads[index].after}'),
            ),
          );
        }
        final extent = world.staples.resolveObjectExtent(object);
        expect(
          extent.spread.before,
          Rational.fromInt(spreads[0].before + spreads[1].before, 86400),
        );
        expect(extent.spread.after, Rational.fromInt(spreads[0].after + spreads[1].after, 86400));
      }
    });

    test('the implicit placement staple is a READING: "Start time" is one row '
        'and no record moves', () {
      final world = World();
      final object = world.object(duration: '30', placedAt: civil(2026, 8, 10, 9, 0, 0));
      final before = world.document.relations.length;
      world.staple(
        kind: 'anchor',
        ends: [
          StapleEnd.object(object, point: 'end'),
          _frameAt(civil(2026, 8, 10, 17, 0, 0)),
        ],
      );
      final rows = world.staples.effectiveObjectStaples(object);
      expect(rows, hasLength(2));
      expect(rows.first.implicit, isTrue);
      expect(rows.first.staple, isNull);
      expect(rows.first.relation!.type, 'attachment');
      expect(endPoint(rows.first.near), 'start');
      expect((rows.first.far! as FrameEnd).frame, 'calendar:work');
      expect(rows.last.implicit, isFalse);
      expect(rows.last.kind, 'anchor');
      // No migration: the attachment is still an attachment, and the only new
      // record is the staple that was authored.
      expect(world.document.relations.length, before + 1);
      expect(world.document.relations.values.where((r) => r.type == 'attachment'), hasLength(1));
    });
  });

  group('correspondence', () {
    test('the whole many-valued set is the answer, in stable order, and its '
        'shape is DERIVED', () {
      final random = Random(specSeed + 9);
      for (var i = 0; i < iterations; i += 1) {
        final world = World();
        final count = 1 + random.nextInt(5);
        final sources = <Rational>[], targets = <Rational>[];
        var voids = 0, manyValued = 0;
        for (var entry = 0; entry < count; entry += 1) {
          final at = 1 + random.nextInt(6);
          final day = 1 + random.nextInt(27);
          final form = random.nextInt(6);
          final Position far = switch (form) {
            0 => const Position.authoredVoid(),
            1 => const Position.selector({'cycle': 'weekday', 'value': 'Tuesday'}),
            _ => Position.coordinate(civil(2026, 8, day)),
          };
          if (form == 0) {
            voids += 1;
          } else if (form == 1) {
            manyValued += 1;
          } else {
            sources.add(Rational.fromInt(at - 1) * Rational.fromInt(8));
            targets.add(_days(2026, 8, day));
          }
          world.staple(
            kind: 'correspondence',
            ends: [
              _frameAt(stroke(at), 'frame:invented'),
              StapleEnd.frame('calendar:work', position: far),
            ],
          );
        }
        final staples = world.staples;
        final entries = staples.frameCorrespondences('frame:invented', 'calendar:work');
        expect(entries, hasLength(count));
        // Enumerated in the substrate's own stable relation-id order: nothing
        // sorted them by position, on either side.
        final ids = [for (final entry in entries) entry.staple.id];
        expect(ids, [...ids]..sort());
        expect(entries.every((entry) => entry.from.frame == 'frame:invented'), isTrue);

        final shape = staples.describeCorrespondence('frame:invented', 'calendar:work');
        expect(shape.count, count);
        expect(shape.voids, voids);
        expect(shape.manyValued, manyValued);
        expect(shape.points, sources.length);
        // The claim narrows with the domain: any many-valued member, and the
        // set cannot be called one-to-anything at all.
        final expectedCardinality = manyValued > 0
            ? 'many-valued'
            : sources.isEmpty
            ? 'void'
            : sources.toSet().length == sources.length && targets.toSet().length == targets.length
            ? 'one-to-one'
            : targets.toSet().length == targets.length
            ? 'one-to-many'
            : sources.toSet().length == sources.length
            ? 'many-to-one'
            : 'many-to-many';
        expect(shape.cardinality, expectedCardinality);
        if (manyValued > 0 || voids > 0) {
          expect(shape.monotonic, isNull);
        }
      }
    });

    test('a frame with no correspondence enumerates empty rather than reaching '
        'for a neighbour', () {
      final world = World();
      final staples = world.staples;
      expect(staples.frameCorrespondences('frame:invented'), isEmpty);
      expect(staples.frameCorrespondences(null), isEmpty);
      expect(staples.describeCorrespondence('frame:invented', 'calendar:work'), (
        count: 0,
        points: 0,
        manyValued: 0,
        voids: 0,
        cardinality: 'empty',
        monotonic: true,
      ));
    });

    test('a rising set is monotone, a falling one is not, and neither is '
        'reordered', () {
      final world = World();
      for (final (at, day) in [(1, 1), (2, 8), (3, 15)]) {
        world.staple(
          kind: 'correspondence',
          ends: [_frameAt(stroke(at), 'frame:invented'), _frameAt(civil(2026, 8, day))],
        );
      }
      expect(
        world.staples.describeCorrespondence('frame:invented', 'calendar:work').monotonic,
        isTrue,
      );
      final falling = World();
      for (final (at, day) in [(1, 20), (2, 8), (3, 15)]) {
        falling.staple(
          kind: 'correspondence',
          ends: [_frameAt(stroke(at), 'frame:invented'), _frameAt(civil(2026, 8, day))],
        );
      }
      expect(
        falling.staples.describeCorrespondence('frame:invented', 'calendar:work').monotonic,
        isFalse,
      );
    });

    test('a frame corresponds to ITSELF at two points, enumerated from both', () {
      final world = World();
      world.staple(
        kind: 'correspondence',
        ends: [_frameAt(stroke(2), 'frame:invented'), _frameAt(stroke(5), 'frame:invented')],
      );
      final entries = world.staples.frameCorrespondences('frame:invented', 'frame:invented');
      expect(entries, hasLength(2));
      expect({for (final entry in entries) world.staples.frameEndDays(entry.from)}, hasLength(2));
    });

    test('RULED ANCHOR: N authored points stay N points', () {
      // "we place 8 that is where lines shows us the warp" -- a second staple
      // is a second exact point, never reconciled into one offset.
      final random = Random(specSeed + 10);
      for (var i = 0; i < iterations; i += 1) {
        final world = World();
        final count = 2 + random.nextInt(6);
        for (var entry = 0; entry < count; entry += 1) {
          world.staple(
            kind: 'correspondence',
            ends: [
              _frameAt(stroke(entry + 1), 'frame:invented'),
              _frameAt(civil(2026, 8, 1 + random.nextInt(27))),
            ],
          );
        }
        final shape = world.staples.describeCorrespondence('frame:invented', 'calendar:work');
        expect(shape.count, count);
        expect(shape.points, count);
      }
    });

    test('a correspondence never anchors an extent', () {
      final world = World();
      final object = world.object(duration: '30', placedAt: civil(2026, 8, 10, 9, 0, 0));
      world.staple(
        kind: 'correspondence',
        ends: [
          StapleEnd.object(object, point: 'start'),
          _frameAt(civil(2026, 1, 1)),
        ],
      );
      final extent = world.staples.resolveObjectExtent(object);
      expect(extent.source, 'placement');
      expect(extent.anchors, isEmpty);
    });
  });

  group('series partitioning', () {
    test('a coordinate at or above the base closes at its unit\'s last '
        'instant; below the base it closes exactly there', () {
      final random = Random(specSeed + 11);
      for (var i = 0; i < iterations; i += 1) {
        final world = World();
        final month = 1 + random.nextInt(12);
        final day = 1 + random.nextInt(28);
        final hour = random.nextInt(24);
        final timed = random.nextBool();
        final series = world.pattern(templateAt: civil(2026, 1, 5, 9, 0, 0));
        world.staple(
          kind: 'end',
          ends: [
            StapleEnd.series(series),
            _frameAt(timed ? civil(2026, month, day, hour, 0, 0) : civil(2026, month, day)),
          ],
        );
        final segments = world.staples.seriesSegments(world.document.patterns[series]!);
        final midnight = _days(2026, month, day);
        expect(
          segments.first.untilDays,
          timed ? midnight + Rational.fromInt(hour, 24) : _lastInstantOf(midnight),
        );
        expect(segments, hasLength(1), reason: 'no following rule terminates');
        expect(segments.first.closedBy, isNotNull);
      }
    });

    test('RULED ANCHOR: the precision-aware close', () {
      // A bare date keeps that day's own 09:00 occurrence; a bare month keeps
      // the whole month, read from the month's own declared length; a bare date
      // on the last day of a month carries into the next month without spilling
      // past it; an explicit clock time gets no end-of-unit expansion at all.
      final cases = <(Json, Rational)>[
        (civil(2026, 1, 19), _lastInstantOf(_days(2026, 1, 19))),
        (civil(2026, 1), _lastInstantOf(_days(2026, 1, 31))),
        (civil(2026, 1, 31), _lastInstantOf(_days(2026, 1, 31))),
        (civil(2026, 2, 28), _lastInstantOf(_days(2026, 2, 28))),
        (civil(2024, 2, 29), _lastInstantOf(_days(2024, 2, 29))),
        (civil(2026), _lastInstantOf(_days(2026, 12, 31))),
        (civil(2026, 1, 19, 8, 0, 0), _days(2026, 1, 19) + Rational.fromInt(8, 24)),
      ];
      for (final (authored, expected) in cases) {
        final world = World();
        final series = world.pattern(templateAt: civil(2026, 1, 5, 9, 0, 0));
        world.staple(kind: 'end', ends: [StapleEnd.series(series), _frameAt(authored)]);
        final segments = world.staples.seriesSegments(world.document.patterns[series]!);
        expect(segments.first.untilDays, expected, reason: 'closing at ${authored['levels']}');
      }
    });

    test('N partitioning staples carrying rules make N+1 segments, each opening '
        'exclusively where the last closed', () {
      final random = Random(specSeed + 12);
      for (var i = 0; i < iterations; i += 1) {
        final world = World();
        final series = world.pattern(templateAt: civil(2026, 1, 5, 9, 0, 0));
        final count = 1 + random.nextInt(4);
        final months = <int>{};
        while (months.length < count) {
          months.add(1 + random.nextInt(12));
        }
        for (final month in months) {
          world.staple(
            kind: 'inflection',
            ends: [StapleEnd.series(series), _frameAt(civil(2026, month, 15, 9, 0, 0))],
            extra: {
              'payload': {
                'rule': {
                  'rrule': {'FREQ': 'DAILY'},
                  'coordinate': civil(2026, month, 16, 9, 0, 0),
                },
              },
            },
          );
        }
        final segments = world.staples.seriesSegments(world.document.patterns[series]!);
        expect(segments, hasLength(count + 1));
        // Chronological, and each segment opens exactly where the last closed.
        for (final (index, segment) in segments.indexed) {
          expect(segment.index, index);
          if (index > 0) {
            expect(segment.fromDays, segments[index - 1].untilDays);
            expect(segment.openedBy, isNotNull);
            expect(segment.rule.rrule['FREQ'], 'DAILY');
          }
        }
        expect(segments.last.untilDays, isNull);
        expect(world.staples.seriesIsSegmented(world.document.patterns[series]!), isTrue);
      }
    });

    test('a phase staple names the generator\'s base without rewriting the '
        'template', () {
      final random = Random(specSeed + 13);
      for (var i = 0; i < iterations; i += 1) {
        final world = World();
        final template = civil(2026, 1, 5, 9, 0, 0);
        final series = world.pattern(templateAt: template);
        expect(
          world.staples.seriesPhaseDays(world.document.patterns[series]!),
          isNull,
          reason: 'no phase staple means "use the segment\'s own base"',
        );
        final day = 1 + random.nextInt(27);
        world.staple(
          kind: 'phase',
          ends: [StapleEnd.series(series), _frameAt(civil(2026, 3, day, 22, 0, 0))],
        );
        expect(
          world.staples.seriesPhaseDays(world.document.patterns[series]!),
          _days(2026, 3, day) + Rational.fromInt(22, 24),
        );
        // The template is untouched, so removing the staple restores the
        // original phase for free.
        final segments = world.staples.seriesSegments(world.document.patterns[series]!);
        expect(segments.first.rule.baseCoordinate, template);
      }
    });

    test('the single end-staple convenience updates in place and clears', () {
      final world = World();
      final series = world.pattern(templateAt: civil(2026, 1, 5, 9, 0, 0));
      expect(seriesEndStaple(world.document, series), isNull);
      var placed = setSeriesEndStaple(
        world.document,
        series,
        'calendar:work',
        civil(2026, 1, 19, 9, 0, 0),
      );
      world.document = placed.document;
      final first = seriesEndStaple(world.document, series)!;
      expect(first.ends.first, isA<SeriesEnd>());
      expect(first.ends.last, isA<FrameEnd>());
      // Re-placing UPDATES the one record rather than adding a second.
      placed = setSeriesEndStaple(
        world.document,
        series,
        'calendar:work',
        civil(2026, 2, 19, 9, 0, 0),
      );
      world.document = placed.document;
      expect(placed.staple.id, first.id);
      expect(world.document.relations.values.where((r) => r.kind == 'end'), hasLength(1));
      world.document = clearSeriesEndStaple(world.document, series);
      expect(seriesEndStaple(world.document, series), isNull);
    });
  });

  group('live exclusions', () {
    test('a whole day is excluded whatever time of day the occurrence falls '
        'at, and only inside the window', () {
      final random = Random(specSeed + 14);
      for (var i = 0; i < iterations; i += 1) {
        final world = World();
        world.document = world.document.put(
          'frames',
          'calendar:holidays',
          const Frame(
            id: 'calendar:holidays',
            title: 'Holidays',
            traits: ['set', 'calendar'],
            extra: {'basis': 'frame:wall-time'},
          ),
        );
        final month = 1 + random.nextInt(11);
        final day = 1 + random.nextInt(27);
        final span = 1 + random.nextInt(3);
        world.object(
          duration: '$span',
          unit: 'day',
          placedAt: civil(2026, month, day),
          frame: 'calendar:holidays',
        );
        final staples = world.staples;
        final excluded = staples.liveExclusionDays(
          {
            'frames': ['calendar:holidays'],
          },
          _days(2026, 1, 1),
          _days(2026, 12, 31),
        );
        // An all-day event stored as an N-day duration covers exactly its own
        // N days -- never the day after it ends.
        for (var offset = 0; offset < span; offset += 1) {
          final at = _days(2026, month, day) + Rational.fromInt(offset);
          expect(isLiveExcluded(excluded, at), isTrue);
          // A 06:15 meeting on that date is excluded too, by WHOLE DAY.
          expect(isLiveExcluded(excluded, at + Rational.fromInt(25, 96)), isTrue);
        }
        expect(isLiveExcluded(excluded, _days(2026, month, day) + Rational.fromInt(span)), isFalse);
        // A window that excludes the holiday excludes nothing.
        expect(
          staples.liveExclusionDays(
            {
              'frames': ['calendar:holidays'],
            },
            _days(2027, 1, 1),
            _days(2027, 12, 31),
          ),
          isEmpty,
        );
        // No referenced frame is a different answer from an empty set.
        expect(staples.liveExclusionDays(null, _days(2026, 1, 1), _days(2026, 12, 31)), isNull);
        expect(isLiveExcluded(null, _days(2026, month, day)), isFalse);
      }
    });
  });

  group('ends and ids', () {
    test('remapping rewrites only the ids it was given, and the original is '
        'untouched', () {
      final random = Random(specSeed + 15);
      for (var i = 0; i < iterations; i += 1) {
        final world = World();
        final object = world.object(duration: '30');
        final staple = world.staple(
          kind: 'anchor',
          ends: [
            StapleEnd.object(object, point: _pick(random, ['start', 'end'])),
            _frameAt(civil(2026, 8, 1 + random.nextInt(27), 17, 0, 0)),
          ],
        );
        final moved = withRemappedEnds(staple, {object: 'event:copy'});
        expect(moved.ends.map((end) => end.id), ['event:copy', 'calendar:work']);
        // The point survives the copy, and so does the far end's coordinate.
        expect(endPoint(moved.ends.first), endPoint(staple.ends.first));
        expect((moved.ends.last as FrameEnd).position, (staple.ends.last as FrameEnd).position);
        // The original still names what it named.
        expect(staple.ends.first.id, object);
        expect(withRemappedEnds(staple, const {}).ends, staple.ends);
      }
    });
  });
}
