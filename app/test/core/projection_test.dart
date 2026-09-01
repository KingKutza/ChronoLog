// The projection engine's spec.
//
// GENERATIVE BY RULING (Don, 2026-08-27): "We should never be testing for a
// specific case, we should be testing for a general case." Every assertion below
// is a property quantified over seeded random generation, except the ones
// labelled RULED ANCHOR -- a worked example the ruling itself states, or a defect
// the owner reported in those words, neither of which is derivable from a
// property.
//
// The restatements (`_union`, `_deMorgan`, the expected populations) are written
// from the RULING TEXT -- projection is boolean algebra over connections, OR is
// union, filters are authored as NOT -- deliberately not from projection.dart, so
// agreement between them means something.
//
// The seed is fixed so a failure reproduces exactly. Change it only to widen
// coverage deliberately, never to make a red suite green.

import 'dart:math';

import 'package:chronolog/core/coordinate_law.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/eras.dart' show firstMatch;
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/math.dart';
import 'package:chronolog/core/ops.dart';
import 'package:chronolog/core/projection.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/core/rrule.dart' show noOccurrenceLimit;
import 'package:chronolog/core/staples.dart';
import 'package:test/test.dart';

import '../helpers/projection_scene.dart';

const int specSeed = 20260827;
const int iterations = 130;

T _pick<T>(Random random, List<T> items) => items[random.nextInt(items.length)];

/// The standard population window, IN EXACT DAYS.
///
/// Days rather than coordinates on purpose. The window is resolved through the
/// PRIMARY frame's law, so two projections naming different primaries genuinely
/// ask about different windows -- and a set property written over coordinates
/// would be a statement about law resolution wearing the algebra's clothes.
/// Handing the same exact instants to every query is what makes `or` is union a
/// claim about POPULATION. Which law reads a coordinate window is its own
/// property, below.
final Rational _windowFrom = Rational(daysFromCivil(BigInt.from(1900), 1, 1));
final Rational _windowTo = Rational(daysFromCivil(BigInt.from(2100), 1, 1));

QueryResult _all(ProjectionEngine engine, Projection projection, {int? limit}) => engine.queryFacts(
  projection,
  start: _windowFrom,
  end: _windowTo,
  limit: limit ?? noOccurrenceLimit,
);

Set<String> _population(ProjectionEngine engine, Projection projection) => {
  for (final fact in _all(engine, projection).facts) fact.identity,
};

/// The bindings the algebra properties are written in: two, three or four frames
/// under short names the math grammar accepts.
Projection _expression(String source, List<String> frames) => Projection.parse(
  source,
  bindings: {for (final (index, frame) in frames.indexed) String.fromCharCode(97 + index): frame},
);

// --- A random world --------------------------------------------------------

/// Calendars, groups, objects, placements, memberships, staples and series --
/// the shapes a projection actually has to carry, over one seed.
class _World {
  _World(this.random) {
    final calendarCount = 2 + random.nextInt(3);
    for (var index = 0; index < calendarCount; index += 1) {
      final id = scene.mint('calendar');
      scene.calendar(
        id,
        hoursPerDay: random.nextInt(4) == 0 ? 20 + random.nextInt(6) : null,
        weight: random.nextBool() ? '${1 + random.nextInt(3)}' : null,
      );
      calendars.add(id);
    }
    final groupCount = 2 + random.nextInt(3);
    for (var index = 0; index < groupCount; index += 1) {
      final id = scene.mint('group');
      scene.group(id, const [], weight: random.nextBool() ? 'w * 1.5' : null);
      groups.add(id);
    }
    // Nesting only downward through the list, so the generated graph is acyclic
    // and the cycle guard is asserted where it is authored rather than by luck.
    for (final (index, group) in groups.indexed) {
      final candidates = [...calendars, ...groups.skip(index + 1)];
      for (var edge = random.nextInt(3); edge > 0; edge -= 1) {
        scene.join(group, _pick(random, candidates));
      }
    }
    final objectCount = 3 + random.nextInt(6);
    for (var index = 0; index < objectCount; index += 1) {
      final id = scene.object(title: 'Object $index', duration: '${random.nextInt(200)}');
      objects.add(id);
      final home = _pick(random, calendars);
      scene.place(home, _at(), event: id);
      if (random.nextInt(4) == 0) scene.place(_pick(random, calendars), _at(), event: id);
      // A membership of an OBJECT: the ruled route the JavaScript did not have,
      // and the reason a group shows a ToDo placed on a calendar.
      if (random.nextInt(3) == 0) scene.join(_pick(random, groups), id);
      // An anchor staple to a frame, paired with the coordinate-less attachment
      // that lets the connection supply the placement.
      if (random.nextInt(5) == 0) {
        final anchored = _pick(random, calendars);
        final id2 = scene.mint('relation');
        scene.document = scene.document.put(
          'relations',
          id2,
          Relation(
            id: id2,
            type: 'staple',
            extra: {
              'role': 'placed',
              'ends': [
                ObjectEnd(id, point: 'start').toJson(),
                StapleEnd.frame(anchored).toJson(),
              ],
            },
          ),
        );
        scene.staple(
          kind: 'anchor',
          ends: [
            StapleEnd.object(id, point: random.nextBool() ? 'start' : 'end'),
            StapleEnd.frame(anchored, position: Position.coordinate(_at())),
          ],
        );
      }
    }
    for (var index = random.nextInt(3); index > 0; index -= 1) {
      final frame = _pick(random, calendars);
      patterns.add(
        scene.series(
          frame,
          {
            'FREQ': _pick(random, ['DAILY', 'WEEKLY', 'MONTHLY']),
            if (random.nextBool()) 'INTERVAL': '${1 + random.nextInt(3)}',
            // Always bounded: the windowed cache and the open-ended path are
            // asserted by the overscale anchors, where the window is the point.
            'COUNT': '${1 + random.nextInt(12)}',
          },
          at: _at(),
          appliesTo: [frame],
        ),
      );
    }
  }

  final Random random;
  final Scene scene = Scene();
  final List<String> calendars = [], groups = [], objects = [], patterns = [];

  List<String> get frames => [...calendars, ...groups];

  Json _at() => civil(
    2026,
    1 + random.nextInt(12),
    1 + random.nextInt(28),
    random.nextInt(20),
    random.nextInt(60),
  );

  ProjectionEngine get engine => ProjectionEngine(scene.document);
}

void main() {
  // --- The algebra ----------------------------------------------------------

  test('OR is union, AND is intersection, and both hold over random worlds', () {
    var checked = 0;
    for (var index = 0; index < iterations; index += 1) {
      final world = _World(Random(specSeed + index));
      final engine = world.engine;
      final a = _pick(world.random, world.frames), b = _pick(world.random, world.frames);
      final left = _population(engine, Projection.of([a]));
      final right = _population(engine, Projection.of([b]));
      expect(_population(engine, _expression('a or b', [a, b])), left.union(right));
      expect(_population(engine, _expression('a and b', [a, b])), left.intersection(right));
      // The default projection for a plain selection IS the OR of the selection.
      expect(_population(engine, Projection.of([a, b])), left.union(right));
      checked += 1;
    }
    expect(checked, iterations);
  });

  test('NOT is complement within the OR-ed universe, and never a refusal', () {
    for (var index = 0; index < iterations; index += 1) {
      final world = _World(Random(specSeed + index));
      final engine = world.engine;
      final a = _pick(world.random, world.frames), b = _pick(world.random, world.frames);
      final left = _population(engine, Projection.of([a]));
      final right = _population(engine, Projection.of([b]));
      final universe = left.union(right);
      expect(_population(engine, _expression('a and not b', [a, b])), left.difference(right));
      expect(
        _population(engine, _expression('(a or b) and not b', [a, b])),
        universe.difference(right),
      );
      // R2: the three refusals are gone. A negation is the mechanism, so it
      // answers with a population rather than with an empty list and a complaint.
      expect(_all(engine, _expression('a and not b', [a, b])).errors, isEmpty);
    }
  });

  test('XOR is the symmetric difference', () {
    for (var index = 0; index < iterations; index += 1) {
      final world = _World(Random(specSeed + index));
      final engine = world.engine;
      final a = _pick(world.random, world.frames), b = _pick(world.random, world.frames);
      final left = _population(engine, Projection.of([a]));
      final right = _population(engine, Projection.of([b]));
      expect(
        _population(engine, _expression('a xor b', [a, b])),
        left.union(right).difference(left.intersection(right)),
      );
    }
  });

  test('De Morgan holds ON POPULATIONS, in both directions', () {
    for (var index = 0; index < iterations; index += 1) {
      final world = _World(Random(specSeed + index));
      final engine = world.engine;
      final a = _pick(world.random, world.frames), b = _pick(world.random, world.frames);
      // not (a and b)  ==  not a or not b, and not (a or b) == not a and not b --
      // each evaluated over the same universe, which is what makes the equality a
      // statement about the algebra rather than about which frames were named.
      expect(
        _population(engine, _expression('not (a and b)', [a, b])),
        _population(engine, _expression('not a or not b', [a, b])),
      );
      expect(
        _population(engine, _expression('not (a or b)', [a, b])),
        _population(engine, _expression('not a and not b', [a, b])),
      );
      // And the universe a NOT complements is the union of what the expression
      // talks about, so a wholly negative projection selects nothing.
      expect(_population(engine, _expression('not (a or b)', [a, b])), isEmpty);
    }
  });

  test('a three-frame expression composes associatively and commutatively', () {
    for (var index = 0; index < iterations; index += 1) {
      final world = _World(Random(specSeed + index));
      final engine = world.engine;
      final frames = [
        _pick(world.random, world.frames),
        _pick(world.random, world.frames),
        _pick(world.random, world.frames),
      ];
      expect(
        _population(engine, _expression('(a or b) or c', frames)),
        _population(engine, _expression('a or (b or c)', frames)),
      );
      expect(
        _population(engine, _expression('a and (b or c)', frames)),
        _population(engine, _expression('(a and b) or (a and c)', frames)),
      );
    }
  });

  test('a NOT term changes population and leaves every surviving weight identical', () {
    var withNot = 0;
    for (var index = 0; index < iterations; index += 1) {
      final world = _World(Random(specSeed + index));
      final engine = world.engine;
      final a = _pick(world.random, world.calendars), b = _pick(world.random, world.groups);
      final plain = Projection.of([a]);
      final filtered = _expression('a and not b', [a, b]);
      final before = _all(engine, plain).facts;
      final after = _all(engine, filtered).facts;
      expect(after.length, lessThanOrEqualTo(before.length));
      if (after.length < before.length) withNot += 1;
      // RULING 10, verbatim: "NOT-terms gate visibility and never modify weight."
      // A surviving fact's whole derivation -- every ring, in order -- is what it
      // was before the filter existed.
      final was = {for (final fact in before) fact.identity: engine.weightOf(fact, plain)};
      for (final fact in after) {
        final now = engine.weightOf(fact, filtered);
        expect(now.weight, was[fact.identity]!.weight, reason: fact.identity);
        expect(
          [for (final ring in now.rings) '${ring.id} ${ring.via} ${ring.weight}'],
          [for (final ring in was[fact.identity]!.rings) '${ring.id} ${ring.via} ${ring.weight}'],
        );
      }
    }
    expect(withNot, greaterThan(0), reason: 'the NOT must actually have filtered something');
  });

  test('the weight chain nests inside out, in the blessed order', () {
    // RULED ANCHOR (ruling 10): the object first, then connected frames by
    // increasing distance with ties by stable id, then the projecting frame last,
    // then falloff. Restated here from the ruling, not read off the engine.
    final scene = Scene();
    scene.calendar('calendar:work', weight: '3');
    scene.group('group:inner', const ['calendar:work'], weight: '5');
    scene.group('group:outer', const ['group:inner'], weight: '7');
    final object = scene.object(duration: '0');
    scene.document = scene.document.put(
      'events',
      object,
      scene.document.events[object]!.withField('display', {'weight': '2'}),
    );
    scene.place('calendar:work', civil(2026, 5, 5), event: object);
    final engine = ProjectionEngine(scene.document);
    final derivation = engine.weightOf(
      engine.explicitFacts('calendar:work').single,
      Projection.of(const ['group:outer']),
    );
    expect(
      [for (final ring in derivation.rings) ring.id],
      ['object', 'calendar:work', 'group:inner', 'group:outer'],
      reason: 'nearest frame first; the projecting frame last among frames',
    );
    expect(derivation.weight, Rational.fromInt(2 * 3 * 5 * 7));
    // Falloff is the projector's own CLOSING step, applied after the fold.
    final away = engine.weightOf(
      engine.explicitFacts('calendar:work').single,
      Projection.of(const ['group:outer']),
      at: Rational(daysFromCivil(BigInt.from(2026), 5, 12)),
    );
    expect(away.rings.last.id, 'falloff');
    expect(away.weight < derivation.weight, isTrue);
  });

  test('a projection is one expression in the one math, and a broken one is refused', () {
    // The leaf seam is shared with weight formulas: `w * 1.5` and
    // `work and not done` are the same tree walked by the same evaluator.
    expect(() => Projection.parse('a and'), throwsA(isA<MathRefusal>()));
    final scene = Scene();
    scene.calendar('calendar:work');
    scene.place('calendar:work', civil(2026, 5, 5));
    final engine = ProjectionEngine(scene.document);
    // An expression that comes to a NUMBER is a refusal, reported to the author,
    // never a truthy guess.
    final result = _all(engine, _expression('a + 1', const ['calendar:work']));
    expect(result.facts, isEmpty);
    expect(result.errors, isNotEmpty);
  });

  // --- The group union (D11), as the OR case --------------------------------

  test('a group contributes MEMBERSHIP and ORDER and no arithmetic', () {
    // RULED ANCHOR, and a field-measured defect in the owner's own document:
    // `queryFacts` on the Back-to-the-Future parent frame returned zero while
    // every child answered one. A group is not a coordinate space, so each
    // member's facts resolve under that member's OWN law and are unioned.
    final scene = Scene();
    scene.calendar('calendar:1955');
    scene.calendar('calendar:1985');
    scene.group('frame:bttf', const ['calendar:1955', 'calendar:1985']);
    scene.place('calendar:1955', civil(1955, 11, 12, 22), title: 'Lightning strikes the tower');
    scene.place('calendar:1985', civil(1985, 10, 26, 1), title: 'The DeLorean hits 88');
    final engine = ProjectionEngine(scene.document);
    final parent = _all(engine, Projection.of(const ['frame:bttf']));
    expect([for (final fact in parent.facts) fact.event.payload!['title']]..sort(), [
      'Lightning strikes the tower',
      'The DeLorean hits 88',
    ]);
    // Every fact's day is exactly what a direct query on its own member gives:
    // the group re-resolves nothing.
    final byTitle = {for (final fact in parent.facts) fact.event.payload!['title']: fact.day};
    for (final member in ['calendar:1955', 'calendar:1985']) {
      for (final fact in _all(engine, Projection.of([member])).facts) {
        expect(byTitle[fact.event.payload!['title']], fact.day);
      }
    }
  });

  test('each member resolves under its OWN law, and the group imposes none', () {
    // RULED ANCHOR: a member whose day is 23 standard hours long drifts under
    // bottom-up composition, so the same calendar date is a different absolute
    // instant on it. Two laws, two answers; the group flattens neither.
    final scene = Scene();
    scene.calendar('calendar:standard');
    scene.calendar('calendar:shortened', hoursPerDay: 23);
    scene.group('frame:both', const ['calendar:standard', 'calendar:shortened']);
    scene.place('calendar:standard', civil(2026, 8, 20, 12), title: 'Standard noon');
    scene.place('calendar:shortened', civil(2026, 8, 20, 12), title: 'Shortened noon');
    final facts = _all(ProjectionEngine(scene.document), Projection.of(const ['frame:both'])).facts;
    final days = {for (final fact in facts) fact.event.payload!['title']: fact.day};
    expect(days.length, 2);
    expect(days['Standard noon'] == days['Shortened noon'], isFalse);
  });

  test('nested groups union transitively, and a group containing itself reports once', () {
    // RULED ANCHOR. The cycle terminates and says so; it is never thrown and
    // never unioned forever, because the loop is authored data.
    final nested = Scene();
    nested.calendar('calendar:leaf');
    nested.group('frame:inner', const ['calendar:leaf']);
    nested.group('frame:outer', const ['frame:inner']);
    nested.place('calendar:leaf', civil(2026, 3, 4), title: 'Deep event');
    expect(
      _all(ProjectionEngine(nested.document), Projection.of(const ['frame:outer'])).facts.length,
      1,
    );

    final looped = Scene();
    looped.calendar('calendar:leaf');
    looped.group('frame:a', const ['calendar:leaf', 'frame:b']);
    looped.group('frame:b', const ['frame:a']);
    looped.place('calendar:leaf', civil(2026, 3, 4), title: 'Reachable');
    final result = _all(ProjectionEngine(looped.document), Projection.of(const ['frame:a']));
    expect(result.facts.length, 1, reason: 'the reachable fact still comes back');
    expect(
      result.errors.where((entry) => entry.message.contains('contains itself')).length,
      greaterThan(0),
    );
    expect(
      result.errors.where((entry) => entry.source == 'frame:a').length,
      1,
      reason: 'one report per group, not one per path',
    );
  });

  test('two placements of one object are two facts; one relation reached twice is one', () {
    // RULED ANCHOR: dedupe identity is the RELATION, not the event.
    final twice = Scene();
    twice.calendar('calendar:a');
    twice.calendar('calendar:b');
    twice.group('frame:union', const ['calendar:a', 'calendar:b']);
    final object = twice.object(title: 'Twice placed', duration: '0');
    twice.place('calendar:a', civil(2026, 1, 1), event: object);
    twice.place('calendar:b', civil(2026, 6, 1), event: object);
    expect(
      _all(ProjectionEngine(twice.document), Projection.of(const ['frame:union'])).facts.length,
      2,
    );

    final diamond = Scene();
    diamond.calendar('calendar:shared');
    diamond.group('frame:left', const ['calendar:shared']);
    diamond.group('frame:right', const ['calendar:shared']);
    diamond.group('frame:top', const ['frame:left', 'frame:right']);
    diamond.place('calendar:shared', civil(2026, 5, 5), title: 'Reached twice');
    expect(
      _all(ProjectionEngine(diamond.document), Projection.of(const ['frame:top'])).facts.length,
      1,
    );
  });

  test('a member that cannot resolve is skipped, the rest survive, and it is named once', () {
    // RULED ANCHOR (D3): a declaration whose transition nothing implements makes
    // every coordinate on it unresolvable, and one such record used to abort the
    // whole projection.
    final scene = Scene();
    scene.calendar('calendar:good');
    scene.frame(
      'calendar:broken',
      const ['set', 'calendar'],
      const {
        'coordinate': {
          'kind': 'nested',
          'levels': [
            {'name': 'year'},
            {'name': 'month', 'within': 'year', 'transition': 'invented.months'},
          ],
        },
      },
    );
    scene.group('frame:mixed', const ['calendar:good', 'calendar:broken']);
    scene.place('calendar:good', civil(2026, 2, 2), title: 'Survivor');
    for (var index = 0; index < 4; index += 1) {
      scene.place('calendar:broken', civil(2026, 2, 2), title: 'Lost $index');
    }
    final result = _all(ProjectionEngine(scene.document), Projection.of(const ['frame:mixed']));
    expect([for (final fact in result.facts) fact.event.payload!['title']], ['Survivor']);
    final named = result.errors.where((entry) => entry.source == 'calendar:broken').toList();
    expect(named.length, 1, reason: 'one reason per frame, not one per record');
  });

  test('the union leans on each member own index rather than rebuilding it', () {
    // RULED ANCHOR (overscale doctrine): 500-member groups are the design point.
    final scene = Scene();
    final members = <String>[];
    for (var index = 0; index < 60; index += 1) {
      final id = 'calendar:m$index';
      scene.calendar(id);
      scene.place(id, civil(2026, 1, 1 + (index % 28)), title: 'Event $index');
      members.add(id);
    }
    scene.group('frame:big', members);
    final engine = ProjectionEngine(scene.document);
    expect(_all(engine, Projection.of(const ['frame:big'])).facts.length, 60);
    for (final member in members) {
      expect(engine.explicitFacts(member).length, 1, reason: '$member kept its own index');
    }
    // Asking again is stable and does not multiply facts.
    expect(_all(engine, Projection.of(const ['frame:big'])).facts.length, 60);
  });

  test('group inclusion spans authored, query and nested membership', () {
    // RULED ANCHOR, ported from the workspace-composition contract: a selector is
    // a LEAF in the one pool now, so a query naming a nested group reaches that
    // group's members with no second mechanism involved.
    final scene = Scene();
    scene.calendar('calendar:work');
    scene.group('group:project', const []);
    scene.group(
      'group:umbrella',
      const [],
      extra: const {
        'query': {
          'groups': ['group:project'],
        },
      },
    );
    final object = scene.object(title: 'A work thing', duration: '60');
    scene.place('calendar:work', civil(2030, 1, 1), event: object);
    scene.join('group:project', object);
    final engine = ProjectionEngine(scene.document);
    expect(engine.indexes.memberObjects('group:umbrella'), {object});
    expect(engine.eventCalendarFrames(object), ['calendar:work']);
    expect(
      [
        for (final fact in _all(engine, Projection.of(const ['group:umbrella'])).facts)
          fact.event.id,
      ],
      [object],
    );
    // A trait selector reaches the same pool.
    scene.group(
      'group:traits',
      const [],
      extra: const {
        'query': {
          'traitsAny': ['event'],
        },
      },
    );
    expect(
      ProjectionEngine(scene.document).indexes.memberObjects('group:traits').contains(object),
      isTrue,
    );
  });

  test('membership populates a group from wherever the object sits', () {
    for (var index = 0; index < iterations; index += 1) {
      final world = _World(Random(specSeed + index));
      final engine = world.engine;
      for (final group in world.groups) {
        final population = _population(engine, Projection.of([group]));
        for (final member in engine.indexes.memberObjects(group)) {
          // Every placement of a member object is in the group's projection --
          // unless the object is placed on a frame the group already reads, in
          // which case that placement represents it and nothing foreign is
          // imported beside it.
          final frames = engine.indexes.framesOf(member);
          if (frames.any(engine.indexes.frameClosure(group).contains)) continue;
          for (final frame in frames) {
            for (final fact in engine.explicitFacts(frame)) {
              if (fact.relation.event != member) continue;
              expect(population.contains(fact.identity), isTrue, reason: '$member on $frame');
            }
          }
        }
      }
    }
  });

  test('a staple to a frame projects the object there, positioned by its own placement', () {
    // THE STAPLE-TO-FRAME ROUTE as a population route. The JavaScript realized a
    // staple only as an anchored placement ON the stapled frame, so a staple to a
    // frame that owns no coordinate space projected nothing at all -- which is
    // exactly the shape "this ToDo is important" takes: an importance frame has no
    // axis, and the object's position comes from the calendar it already sits on.
    final scene = Scene();
    scene.calendar('calendar:work');
    scene.group('frame:important', const [], traits: const ['set', 'group', 'importance']);
    final object = scene.object(title: 'Matters a lot', duration: '0');
    scene.place('calendar:work', civil(2026, 4, 4), event: object);
    scene.staple(
      kind: 'anchor',
      ends: [StapleEnd.object(object), const StapleEnd.frame('frame:important')],
    );
    final engine = ProjectionEngine(scene.document);
    final projected = _all(engine, Projection.of(const ['frame:important'])).facts;
    expect([for (final fact in projected) fact.event.id], [object]);
    // Positioned by its OWN placement, resolved under its own frame's law: the
    // importance frame imposes no arithmetic, exactly as a group does not.
    expect(projected.single.day, engine.explicitFacts('calendar:work').single.day);
    // And it composes: the same object filtered OUT of the calendar by a NOT.
    expect(
      _population(engine, _expression('a and not b', const ['calendar:work', 'frame:important'])),
      isEmpty,
    );
  });

  // --- The window law (D12) -------------------------------------------------

  test('a group query spans its window and is never collapsed to one day', () {
    // RULED ANCHOR: a frame with no declared levels permissively reads a bare
    // `day` level, so a year/month/day window became [1, 1] and every group
    // answered zero. Decided by CAPABILITY, so an era or invented frame keeps its
    // own law and a group with no space reads the standard boundary.
    final scene = Scene();
    scene.calendar('calendar:earth');
    scene.frame('frame:invented', const ['line', 'temporal'], const {'coordinate': inventedLaw});
    scene.frame(
      'frame:era',
      const ['line', 'temporal', 'era'],
      const {
        'era': {'key': 'unmeasured', 'name': 'The unmeasured age', 'countable': false},
      },
    );
    scene.group('frame:everything', const ['calendar:earth', 'frame:invented', 'frame:era']);
    for (var index = 0; index < 6; index += 1) {
      scene.place('calendar:earth', civil(2026, 1 + index, 3), title: 'Earth $index');
    }
    scene.place('frame:invented', stroke(400, 3), title: 'A stroke');
    final engine = ProjectionEngine(scene.document);
    expect(engine.windowFrameFor('frame:everything'), isNull);
    expect(engine.windowFrameFor('frame:invented'), 'frame:invented');
    expect(engine.windowFrameFor('frame:era'), isNull, reason: 'no year axis, no day ordinals');
    final result = engine.queryFacts(
      Projection.of(const ['frame:everything']),
      start: civil(2026, 1, 1),
      end: civil(2027, 1, 1),
    );
    // The window is the real span read through the registered standard boundary,
    // not one day.
    expect(result.fromDays, gregorianLaw.toDays(Coordinate.fromJson(civil(2026, 1, 1))));
    expect(result.toDays - result.fromDays, Rational(BigInt.from(365)));
    expect([for (final fact in result.facts) fact.event.payload!['title']].length, 6);
    // The invented frame reads its OWN law, which is a different axis entirely.
    final own = engine.queryFacts(
      Projection.of(const ['frame:invented']),
      start: stroke(0),
      end: stroke(1000),
    );
    expect(own.facts.length, 1);
  });

  test('the window law is the primary frame law, over random worlds', () {
    for (var index = 0; index < iterations; index += 1) {
      final world = _World(Random(specSeed + index));
      final engine = world.engine;
      for (final frame in world.frames) {
        final result = engine.queryFacts(
          Projection.of([frame]),
          start: civil(2026, 1, 1),
          end: civil(2026, 12, 31),
        );
        final law = engine.windowFrameFor(frame) == null ? gregorianLaw : engine.lawOf(frame);
        expect(result.fromDays, law.toDays(Coordinate.fromJson(civil(2026, 1, 1))));
        expect(result.toDays > result.fromDays, isTrue, reason: '$frame collapsed its window');
      }
    }
  });

  test('a reversed window is read as the same window', () {
    for (var index = 0; index < iterations; index += 1) {
      final world = _World(Random(specSeed + index));
      final engine = world.engine;
      final frame = _pick(world.random, world.frames);
      final forward = engine.queryFacts(
        Projection.of([frame]),
        start: civil(2026, 1, 1),
        end: civil(2026, 12, 1),
      );
      final backward = engine.queryFacts(
        Projection.of([frame]),
        start: civil(2026, 12, 1),
        end: civil(2026, 1, 1),
      );
      expect(
        [for (final fact in backward.facts) fact.identity],
        [for (final fact in forward.facts) fact.identity],
      );
    }
  });

  // --- Occurrences (D4) -----------------------------------------------------

  test('every projected occurrence carries its exact resolved day, and resolves from it', () {
    // RULED ANCHOR, the 8.19 field report in the owner's words: "If I click on an
    // instance of a series in the right day columns, of intimate view, I get a
    // 'That generated fact is outside the current query window' error." The cause
    // was two independent derivations of what is on screen. THE DAY-LESS PATH IS
    // UNREPRESENTABLE here: `Fact.day` is a non-nullable exact Rational, so there
    // is no fact to hand out that a caller could ask about without saying where
    // it was drawn.
    // Quantified over the facts a third of the corpus actually produces: the
    // guarantee is CLASS-level (every fact the lens drew), so the loop is over
    // the whole population rather than over one occurrence from a report.
    for (var index = 0; index < iterations ~/ 3; index += 1) {
      final world = _World(Random(specSeed + index));
      final engine = world.engine;
      for (final frame in world.calendars) {
        for (final fact in _all(engine, Projection.of([frame])).facts) {
          // Resolving against the fact's own day finds it, however far that day
          // sits from any window a caller might have guessed -- and the
          // asymmetric, buffered render window of a lens is exactly such a guess.
          final resolved = engine.queryFacts(
            Projection.of([frame]),
            start: fact.day,
            end: fact.day,
          );
          expect(
            [for (final found in resolved.facts) found.identity],
            contains(fact.identity),
            reason: '${fact.identity} at ${fact.day}',
          );
        }
      }
    }
  });

  test('a segmented series keeps one identity and never collides on a day', () {
    // RULED ANCHOR (the Rob-and-John ruling): a rule change is not a new
    // identity. The staple closes its segment inclusively and opens the next
    // exclusively, so consecutive segments cannot both project the boundary.
    final scene = Scene();
    scene.calendar('calendar:work');
    final pattern = scene.series(
      'calendar:work',
      const {'FREQ': 'WEEKLY', 'BYDAY': 'MO'},
      at: civil(2026, 1, 5, 12),
      appliesTo: const ['calendar:work'],
    );
    scene.staple(
      kind: 'inflection',
      ends: [
        StapleEnd.series(pattern),
        StapleEnd.frame('calendar:work', position: Position.coordinate(civil(2026, 3, 2))),
      ],
      extra: {
        'payload': {
          'rule': {
            'rrule': {'FREQ': 'WEEKLY', 'BYDAY': 'TH'},
            'magnitude': durationMagnitude('45', 'minute').toJson(),
          },
        },
      },
    );
    final engine = ProjectionEngine(scene.document);
    final facts = engine
        .queryFacts(
          Projection.of(const ['calendar:work']),
          start: civil(2026, 1, 1),
          end: civil(2026, 5, 1),
        )
        .facts;
    expect(facts.length, greaterThan(8));
    expect({for (final fact in facts) fact.virtualId}.length, facts.length, reason: 'no collision');
    expect({for (final fact in facts) fact.pattern}, {pattern}, reason: 'one provenance');
    // The following rule's own magnitude overrides the template's duration for
    // its own segment's occurrences, and only those.
    final durations = {for (final fact in facts) engine.eventDurationDays(fact.event).toJson()};
    expect(durations.length, 2);
  });

  test('a phase staple moves the whole series and removing it restores the phase', () {
    // RULED ANCHOR: "stapling an arbitrary occurrence anchors the cycle's phase."
    final scene = Scene();
    scene.calendar('calendar:work');
    final pattern = scene.series(
      'calendar:work',
      const {'FREQ': 'WEEKLY'},
      at: civil(2026, 1, 5, 9),
      appliesTo: const ['calendar:work'],
    );
    final before = _all(
      ProjectionEngine(scene.document),
      Projection.of(const ['calendar:work']),
      limit: 40,
    ).facts.map((fact) => fact.day.toJson()).toList();
    final staple = scene.staple(
      kind: 'phase',
      ends: [
        StapleEnd.series(pattern),
        StapleEnd.frame('calendar:work', position: Position.coordinate(civil(2026, 1, 7, 9))),
      ],
    );
    final shifted = _all(
      ProjectionEngine(scene.document),
      Projection.of(const ['calendar:work']),
      limit: 40,
    ).facts.map((fact) => fact.day.toJson()).toList();
    expect(shifted, isNot(before));
    scene.document = scene.document.remove('relations', staple.id);
    expect(
      _all(
        ProjectionEngine(scene.document),
        Projection.of(const ['calendar:work']),
        limit: 40,
      ).facts.map((fact) => fact.day.toJson()).toList(),
      before,
      reason: 'removing the staple restores the original phase for free',
    );
  });

  test('a live exclusion resolves at projection time against another frame', () {
    // RULED ANCHOR (Rob-and-John beat 2): "holiday exclusion is a live reference
    // to another frame's events, not a baked list." Adding a holiday changes the
    // series with no edit to the series.
    final scene = Scene();
    scene.calendar('calendar:work');
    scene.calendar('calendar:holidays');
    scene.series(
      'calendar:work',
      const {'FREQ': 'DAILY', 'COUNT': '10'},
      at: civil(2026, 1, 5, 9),
      appliesTo: const ['calendar:work'],
    );
    final patternId = scene.document.patterns.keys.first;
    scene.document = scene.document.put(
      'patterns',
      patternId,
      scene.document.patterns[patternId]!.withField('exclude', {
        'frames': ['calendar:holidays'],
      }),
    );
    final full = _all(ProjectionEngine(scene.document), Projection.of(const ['calendar:work']));
    expect(full.facts.length, 10);
    scene.place('calendar:holidays', civil(2026, 1, 7), title: 'A holiday');
    final trimmed = _all(ProjectionEngine(scene.document), Projection.of(const ['calendar:work']));
    expect(trimmed.facts.length, 9, reason: 'matched by WHOLE DAY, not by instant');
  });

  test('an unprojectable rule is refused by name and does not take the frame offline', () {
    final scene = Scene();
    scene.calendar('calendar:work');
    scene.place('calendar:work', civil(2026, 2, 2), title: 'Survivor');
    final pattern = scene.series(
      'calendar:work',
      const {'FREQ': 'WEEKLY', 'BYSETPOS': '1'},
      at: civil(2026, 1, 5),
      appliesTo: const ['calendar:work'],
    );
    final result = _all(ProjectionEngine(scene.document), Projection.of(const ['calendar:work']));
    expect([for (final fact in result.facts) fact.event.payload!['title']], ['Survivor']);
    expect(result.errors.map((entry) => entry.source), contains(pattern));
    expect(result.errors.single.message, contains('BYSETPOS'));
  });

  test('overrides suppress the occurrence they name, and only when asked', () {
    for (var index = 0; index < iterations; index += 1) {
      final world = _World(Random(specSeed + index));
      if (world.patterns.isEmpty) continue;
      final frame = _pick(world.random, world.calendars);
      var engine = world.engine;
      final facts = _all(engine, Projection.of([frame])).facts;
      final occurrence = facts.where((fact) => fact.virtualId.isNotEmpty).firstOrNull;
      if (occurrence == null) continue;
      world.scene.document = suppressVirtual(world.scene.document, occurrence.virtualId).document;
      engine = ProjectionEngine(world.scene.document);
      expect(_population(engine, Projection.of([frame])), isNot(contains(occurrence.identity)));
      // `applyOverrides: false` yields the projection as the patterns alone
      // describe it -- what the series heal has to compare against, since an
      // override hides the very slot it must reconstruct.
      final unsuppressed = engine.queryFacts(
        Projection.of([frame]),
        start: _windowFrom,
        end: _windowTo,
        applyOverrides: false,
      );
      expect([for (final fact in unsuppressed.facts) fact.identity], contains(occurrence.identity));
    }
  });

  // --- Authored precision (D10) ---------------------------------------------

  test('authored precision is the level the author stopped at, skipped rungs included', () {
    // AUTHORED PRECISION IS DEPTH, NOT A COUNT. A coordinate naming a year and a
    // day but no month stopped at the DAY -- it is a date, however many rungs it
    // skipped saying so -- and counting the levels present would call it two and
    // read it as coarser than it is. The seam is `coordinate_entry.dart`'s own
    // [authoredDepth], so the partition-close rule and this engine cannot
    // disagree about what an author wrote.
    final ladder = ['year', 'month', 'day', 'hour', 'minute'];
    for (var index = 0; index < iterations; index += 1) {
      final random = Random(specSeed + index);
      final depth = 1 + random.nextInt(ladder.length);
      // A rung is dropped at random from the middle, so the coordinate names its
      // deepest level while saying nothing about a coarser one.
      final skip = depth > 2 && random.nextBool() ? 1 + random.nextInt(depth - 2) : -1;
      final written = {
        'levels': [
          for (final (rung, name) in ladder.take(depth).indexed)
            if (rung != skip)
              {'level': name, 'value': '${name == 'year' ? 2026 : 1 + random.nextInt(12)}'},
        ],
      };
      final scene = Scene();
      scene.calendar('calendar:precision');
      scene.place('calendar:precision', written, title: 'At depth $depth');
      final engine = ProjectionEngine(scene.document);
      final fact = engine.explicitFacts('calendar:precision').single;
      expect(fact.precision, ladder[depth - 1], reason: 'depth $depth skipping rung $skip');
      // And the count that would have been wrong is genuinely different whenever a
      // rung was skipped, so the property has teeth.
      if (skip >= 0) {
        expect(
          (written['levels']! as List).length,
          lessThan(depth),
          reason: 'a level count would have read this coordinate as coarser',
        );
      }
    }
  });

  test('an injected precision seam is the only thing that decides depth', () {
    final scene = Scene();
    scene.calendar('calendar:work');
    scene.place('calendar:work', civil(2026, 5, 5, 9), title: 'Placed');
    final engine = ProjectionEngine(scene.document, precisionOf: (value, law) => 'whatever');
    expect(engine.explicitFacts('calendar:work').single.precision, 'whatever');
  });

  // --- Overscale (D5, D7), with HARD bounds ---------------------------------

  test('fact queries use the indexes and honor the caller budget', () {
    // RULED ANCHOR. Ruling 9: the cap is the CALLER's one derived budget, so it
    // arrives as a parameter and the engine holds no number of its own.
    final scene = Scene();
    scene.calendar('calendar:dense');
    for (var index = 0; index < 1000; index += 1) {
      scene.place('calendar:dense', civil(2026, 8, 1 + (index % 28), 9), title: 'Event $index');
    }
    final engine = ProjectionEngine(scene.document);
    expect(engine.indexes.attachmentsOf('calendar:dense').length, 1000);
    expect(engine.explicitFacts('calendar:dense').length, 1000);
    final result = engine.queryFacts(
      Projection.of(const ['calendar:dense']),
      start: civil(2026, 8, 1),
      end: civil(2026, 9, 1),
      limit: 75,
    );
    expect(result.facts.length, 75);
    expect(result.truncated, isTrue);
  });

  test('dense recurrence expansion stops at the render limit', () {
    final scene = Scene();
    scene.calendar('calendar:dense');
    for (var index = 0; index < 80; index += 1) {
      scene.series(
        'calendar:dense',
        const {'FREQ': 'DAILY', 'COUNT': '30'},
        at: civil(2026, 8, 1 + (index % 28), 9),
        appliesTo: const ['calendar:dense'],
      );
    }
    final result = ProjectionEngine(scene.document).queryFacts(
      Projection.of(const ['calendar:dense']),
      start: civil(2026, 8, 1),
      end: civil(2026, 9, 1),
      limit: 120,
    );
    expect(result.facts.length, 120);
    expect(result.truncated, isTrue);
  });

  test('open-ended recurrence windows are cached for adjacent queries', () {
    final scene = Scene();
    scene.calendar('calendar:open');
    for (var index = 0; index < 20; index += 1) {
      scene.series(
        'calendar:open',
        const {'FREQ': 'DAILY'},
        at: civil(2026, 8, 1 + (index % 28), 9),
        appliesTo: const ['calendar:open'],
      );
    }
    final engine = ProjectionEngine(scene.document);
    engine.queryFacts(
      Projection.of(const ['calendar:open']),
      start: civil(2026, 8, 1),
      end: civil(2026, 8, 21),
      limit: 1000,
    );
    final before = engine.cacheLoad.windows;
    expect(before, greaterThan(0));
    engine.queryFacts(
      Projection.of(const ['calendar:open']),
      start: civil(2026, 8, 2),
      end: civil(2026, 8, 22),
      limit: 1000,
    );
    expect(engine.cacheLoad.windows, before, reason: 'the adjacent query reused every window');
  });

  test('sustained navigation keeps the recurrence caches inside HARD bounds', () {
    // Hard, not best-effort: the assertion is the bound itself, so a cache that
    // merely trends the right way fails here.
    final scene = Scene();
    scene.calendar('calendar:open');
    for (var index = 0; index < 200; index += 1) {
      scene.series(
        'calendar:open',
        const {'FREQ': 'WEEKLY'},
        at: civil(2026, 8, 1 + (index % 28), 9),
        appliesTo: const ['calendar:open'],
      );
    }
    final engine = ProjectionEngine(scene.document);
    for (var offset = 0; offset < 24 * 31; offset += 31) {
      engine.queryFacts(
        Projection.of(const ['calendar:open']),
        start: civil(2026, 8, 1 + offset),
        end: civil(2026, 8, 43 + offset),
        limit: 600,
      );
    }
    expect(engine.cacheLoad.windows, lessThanOrEqualTo(maxRecurrenceWindows));
    expect(engine.cacheLoad.windowFacts, lessThanOrEqualTo(maxRecurrenceWindowFacts));
  });

  test('the whole-series cache stays inside its own fact budget', () {
    final scene = Scene();
    scene.calendar('calendar:counted');
    for (var index = 0; index < 120; index += 1) {
      scene.series(
        'calendar:counted',
        {'FREQ': 'DAILY', 'COUNT': '${1 + (index % maxCachedRecurrenceCount)}'},
        at: civil(2026, 1, 1 + (index % 28)),
        appliesTo: const ['calendar:counted'],
      );
    }
    final engine = ProjectionEngine(scene.document);
    for (var year = 2026; year < 2032; year += 1) {
      engine.queryFacts(
        Projection.of(const ['calendar:counted']),
        start: civil(year, 1, 1),
        end: civil(year + 1, 1, 1),
        limit: 4000,
      );
    }
    expect(engine.cacheLoad.seriesFacts, lessThanOrEqualTo(maxRecurrenceSeriesFacts));
  });

  test('truncation is a LOWER BOUND and never a silent drop', () {
    for (var index = 0; index < iterations; index += 1) {
      final world = _World(Random(specSeed + index));
      final engine = world.engine;
      final frame = _pick(world.random, world.frames);
      final projection = Projection.of([frame]);
      final whole = _all(engine, projection);
      expect(whole.truncated, isFalse, reason: 'an unbounded query truncates nothing');
      for (final limit in [1, 3, 7, 40]) {
        final bounded = _all(engine, projection, limit: limit);
        expect(bounded.facts.length, lessThanOrEqualTo(limit));
        if (!bounded.truncated) {
          // Not truncated means NOTHING was dropped: the bounded answer is the
          // whole answer.
          expect(
            [for (final fact in bounded.facts) fact.identity],
            [for (final fact in whole.facts) fact.identity],
          );
        } else {
          expect(bounded.facts.length, limit);
          expect(whole.facts.length, greaterThanOrEqualTo(bounded.facts.length));
        }
      }
    }
  });

  // --- Being told what changed (D6) -----------------------------------------

  test('applyChange answers identically to a full rebuild, over random op runs', () {
    var opsApplied = 0;
    for (var index = 0; index < iterations; index += 1) {
      final world = _World(Random(specSeed + index));
      final random = world.random;
      final engine = ProjectionEngine(world.scene.document);
      var document = world.scene.document;
      for (var round = 0; round < 4; round += 1) {
        final ops = _edits(random, document, world);
        if (ops.isEmpty) continue;
        opsApplied += ops.length;
        engine.applyChange(ops);
        document = applyOps(document, ops);
        final rebuilt = ProjectionEngine(document);
        for (final frame in world.frames) {
          final incremental = _all(engine, Projection.of([frame]));
          final whole = _all(rebuilt, Projection.of([frame]));
          expect(
            [for (final fact in incremental.facts) '${fact.identity}@${fact.day}'],
            [for (final fact in whole.facts) '${fact.identity}@${fact.day}'],
            reason: 'frame $frame after round $round of seed ${specSeed + index}',
          );
          expect(
            incremental.errors.map((entry) => entry.source).toSet(),
            whole.errors.map((entry) => entry.source).toSet(),
          );
        }
      }
    }
    expect(opsApplied, greaterThan(iterations));
  });

  test('setDocument is the full-rebuild path and drops every recurrence cache', () {
    final scene = Scene();
    scene.calendar('calendar:open');
    scene.series(
      'calendar:open',
      const {'FREQ': 'DAILY'},
      at: civil(2026, 8, 1),
      appliesTo: const ['calendar:open'],
    );
    final engine = ProjectionEngine(scene.document);
    _all(engine, Projection.of(const ['calendar:open']), limit: 100);
    expect(engine.cacheLoad.windows, greaterThan(0));
    engine.setDocument(scene.document);
    expect(engine.cacheLoad.windows, 0);
    expect(engine.cacheLoad.windowFacts, 0);
  });

  test('an edit that cannot move an occurrence keeps the recurrence cache warm', () {
    // The JavaScript could not tell a staple edit from a plain attachment edit --
    // both live in the `relations` map -- so it kept a fingerprint of every staple
    // and distrusted the caller. Being told the ops answers it exactly.
    final scene = Scene();
    scene.calendar('calendar:open');
    scene.series(
      'calendar:open',
      const {'FREQ': 'DAILY'},
      at: civil(2026, 8, 1),
      appliesTo: const ['calendar:open'],
    );
    final engine = ProjectionEngine(scene.document);
    _all(engine, Projection.of(const ['calendar:open']), limit: 100);
    final warm = engine.cacheLoad;
    engine.applyChange([putOp('overrides', 'override:none', const Override(id: 'override:none'))]);
    expect(engine.cacheLoad.windows, warm.windows);
    expect(engine.cacheLoad.windowFacts, warm.windowFacts);
    // A staple on the series is a `relations` edit that DOES move occurrences,
    // and its cache goes.
    final pattern = scene.document.patterns.keys.first;
    engine.applyChange([
      putOp(
        'relations',
        'relation:cut',
        Relation(
          id: 'relation:cut',
          type: 'staple',
          extra: {
            'kind': 'end',
            'ends': [
              StapleEnd.series(pattern).toJson(),
              StapleEnd.frame(
                'calendar:open',
                position: Position.coordinate(civil(2026, 8, 10)),
              ).toJson(),
            ],
          },
        ),
      ),
    ]);
    expect(engine.cacheLoad.windows, 0, reason: 'the staple change is known, not guessed');
  });

  // --- Indexes (D7) ---------------------------------------------------------

  test('one index pass answers every question the same way a scan would', () {
    for (var index = 0; index < iterations; index += 1) {
      final world = _World(Random(specSeed + index));
      final engine = world.engine;
      final document = world.scene.document;
      for (final frame in world.frames) {
        expect(engine.indexes.attachmentsOf(frame).map((relation) => relation.id).toSet(), {
          // RESTATED under the ruling of 2026-09-01: a connection is a staple,
          // and what puts it on a frame is a frame end.
          for (final relation in document.relations.values)
            if (relation.isStaple && relation.frame == frame) relation.id,
        });
      }
      for (final object in world.objects) {
        expect(engine.indexes.staplesOf(object).map((relation) => relation.id).toList(), [
          for (final relation
              in (document.relations.values.toList()
                ..sort((left, right) => left.id.compareTo(right.id))))
            if (relation.isStaple && relation.ends.any((end) => end.id == object)) relation.id,
        ]);
        expect(
          engine.indexes.placementOf(object)?.id,
          firstMatch(document.relations.values, (relation) => isPlacement(relation, object))?.id,
        );
        // PLACED, not merely connected (ruled 2026-09-01): an affiliation says
        // the object is somewhere on a sheet without saying where, and reading
        // that as a placement would make the object's own calendar position
        // invisible to the frame it is affiliated with.
        expect(engine.indexes.framesOf(object).toSet(), {
          for (final relation in document.relations.values)
            if (isPlacement(relation, object)) ?relation.frame,
        });
      }
      // Ends are parsed ONCE and answer the same list every time.
      for (final relation in document.relations.values) {
        if (!relation.isStaple) continue;
        expect(engine.indexes.endsOf(relation), same(engine.indexes.endsOf(relation)));
        expect(engine.indexes.endsOf(relation).length, relation.ends.length);
      }
    }
  });

  test('membership closure is the least fixed point, with provenance', () {
    for (var index = 0; index < iterations; index += 1) {
      final world = _World(Random(specSeed + index));
      final engine = world.engine;
      // Restated from the ruling: the closure is the transitive reachability of
      // the authored edges, computed here by plain repeated expansion.
      final direct = <String, Set<String>>{};
      // AFFILIATION is the authored edge now (ruled 2026-09-01): a staple whose
      // frame end names no point. Which end is a FRAME makes the group side.
      for (final relation in world.scene.document.relations.values) {
        for (final edge in stapledAffiliations(relation)) {
          (direct[edge.frame] ??= <String>{}).add(edge.object);
        }
      }
      for (final frame in world.scene.document.frames.values) {
        for (final nested in (obj(frame.extra['query'])?['groups'] as List? ?? const [])) {
          (direct[frame.id] ??= <String>{}).add('$nested');
        }
      }
      Set<String> reach(String from) {
        final found = <String>{};
        final queue = [...?direct[from]];
        while (queue.isNotEmpty) {
          final next = queue.removeLast();
          if (!found.add(next)) continue;
          queue.addAll(direct[next] ?? const <String>{});
        }
        return found;
      }

      for (final group in world.groups) {
        expect(engine.indexes.members[group]?.keys.toSet() ?? <String>{}, reach(group));
        for (final provenance in engine.indexes.members[group]?.values ?? const []) {
          expect(provenance, isNotEmpty, reason: 'every membership explains itself');
        }
      }
    }
  });

  test('modifying-frame distance is the shortest path, and it is deterministic', () {
    for (var index = 0; index < iterations; index += 1) {
      final world = _World(Random(specSeed + index));
      final engine = world.engine;
      for (final object in world.objects) {
        final distances = engine.modifyingFrames(object);
        expect(distances, engine.modifyingFrames(object), reason: 'memoized, not recomputed');
        // CONNECTION IS NOT INCLUSION: a' on A and B genuinely connects A and B,
        // and this walk answers INCLUSION, so the seed object's own placements are
        // not its edges -- they locate a fact, route one, and the placement ring
        // still reaches the weight chain from there (asserted just below). What IS
        // one hop here: a membership the object carries, and a frame stapled to it.
        for (final group in engine.indexes.directGroupsOf(object)) {
          expect(distances[group], 1, reason: 'a membership is one hop');
        }
        for (final staple in engine.indexes.staplesOf(object)) {
          // A PLACEMENT IS STILL ROUTE ONE'S BUSINESS (ruled 2026-09-01 makes it
          // a staple; it does not make it an edge of this walk). "A staple" is
          // no longer a way to say "not this object's own placement", so the
          // exclusion is asked of the sentence instead.
          if (isPlacement(staple, object)) continue;
          for (final end in engine.indexes.endsOf(staple)) {
            if (end is FrameEnd) expect(distances[end.frame], 1, reason: 'a staple is one hop');
          }
        }
        // And the placement ring reaches the weight chain from route one instead:
        // the frame a fact sits on is one hop away from it, its groups one more.
        for (final frame in engine.indexes.framesOf(object)) {
          for (final fact in engine.explicitFacts(frame)) {
            if (fact.relation.event != object) continue;
            final rings = {
              for (final ring in engine.weightOf(fact, Projection.of([frame])).rings) ring.id,
            };
            expect(rings.contains(frame), isTrue, reason: 'the placement frame is a ring');
          }
        }
        for (final entry in distances.entries) {
          expect(entry.value, greaterThan(0));
          // Any frame at distance n+1 has a direct member at distance n or is
          // reached from an object -- restated as: the map is closed upward.
          for (final group in engine.indexes.directGroupsOf(entry.key)) {
            expect(distances.containsKey(group), isTrue);
            expect(distances[group]!, lessThanOrEqualTo(entry.value + 1));
          }
        }
      }
    }
  });

  // --- Determinism and n+1 invariance ---------------------------------------

  test('two identical queries answer identically, and an unrelated frame changes nothing', () {
    for (var index = 0; index < iterations; index += 1) {
      final world = _World(Random(specSeed + index));
      final engine = world.engine;
      final frame = _pick(world.random, world.frames);
      final projection = Projection.of([frame]);
      final first = [for (final fact in _all(engine, projection).facts) fact.identity];
      expect([for (final fact in _all(engine, projection).facts) fact.identity], first);
      // n+1: a frame nothing is connected to adds no population anywhere.
      world.scene.calendar('calendar:unrelated');
      final widened = ProjectionEngine(world.scene.document);
      expect([for (final fact in _all(widened, projection).facts) fact.identity], first);
      expect(_population(widened, Projection.of(const ['calendar:unrelated'])), isEmpty);
    }
  });

  test('the accessors agree with the document they read', () {
    for (var index = 0; index < iterations; index += 1) {
      final world = _World(Random(specSeed + index));
      final engine = world.engine;
      for (final object in world.objects) {
        expect(engine.eventFrames(object).toSet(), engine.indexes.framesOf(object).toSet());
        expect(engine.eventCalendarFrames(object).toSet(), {
          for (final frame in engine.indexes.framesOf(object))
            if (world.scene.document.frames[frame]!.traits.contains('calendar')) frame,
        });
      }
      for (final frame in world.calendars) {
        expect(engine.matchingPatterns(frame).map((pattern) => pattern.id).toSet(), {
          for (final pattern in world.scene.document.patterns.values)
            if ((pattern.extra['appliesTo'] as List?)?.contains(frame) ?? true) pattern.id,
        });
      }
      // refreshFrame drops one frame's own indexes and nothing else.
      final frame = _pick(world.random, world.calendars);
      final before = [for (final fact in engine.explicitFacts(frame)) fact.identity];
      engine.refreshFrame(frame);
      expect([for (final fact in engine.explicitFacts(frame)) fact.identity], before);
    }
  });
}

/// A random op run over the document: puts and deletes across every map an edit
/// can touch, so the equivalence property is quantified over real edits rather
/// than over one shape of them.
List<Op> _edits(Random random, Document document, _World world) {
  final ops = <Op>[];
  for (var count = 1 + random.nextInt(3); count > 0; count -= 1) {
    switch (random.nextInt(6)) {
      case 0:
        // Move a placement.
        final placements = [
          for (final relation in document.relations.values)
            if (isPlacement(relation)) relation,
        ];
        if (placements.isEmpty) break;
        final relation = _pick(random, placements);
        ops.add(
          putOp(
            'relations',
            relation.id,
            relation.withField(
              'coordinate',
              civil(2026, 1 + random.nextInt(12), 1 + random.nextInt(28)),
            ),
          ),
        );
      case 1:
        // Delete a relation outright.
        if (document.relations.isEmpty) break;
        ops.add(delOp('relations', _pick(random, document.relations.keys.toList())));
      case 2:
        // Retime a series.
        if (document.patterns.isEmpty) break;
        final pattern = document.patterns[_pick(random, document.patterns.keys.toList())]!;
        ops.add(
          putOp(
            'patterns',
            pattern.id,
            pattern.withField('rrule', {
              'FREQ': _pick(random, ['DAILY', 'WEEKLY', 'MONTHLY']),
              'COUNT': '${1 + random.nextInt(9)}',
            }),
          ),
        );
      case 3:
        // Change an object's duration, which moves what overlaps a window.
        if (document.events.isEmpty) break;
        final event = document.events[_pick(random, document.events.keys.toList())]!;
        ops.add(
          putOp(
            'events',
            event.id,
            event.copyWith(magnitudes: {'duration': durationMagnitude('${random.nextInt(400)}')}),
          ),
        );
      case 4:
        // Edit a frame's law, which can move every occurrence on it.
        if (world.calendars.isEmpty) break;
        final frame = document.frames[_pick(random, world.calendars)]!;
        ops.add(putOp('frames', frame.id, frame.withField('basis', 'frame:wall-time')));
      case 5:
        // Add a membership, which changes what a group projects.
        final id = 'relation:added-${random.nextInt(1 << 30)}';
        ops.add(
          putOp(
            'relations',
            id,
            Relation(
              id: id,
              type: 'membership',
              extra: {
                'group': _pick(random, world.groups),
                'member': _pick(random, [...world.objects, ...world.calendars]),
              },
            ),
          ),
        );
    }
  }
  return ops;
}
