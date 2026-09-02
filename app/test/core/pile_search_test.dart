// ZERO-STAPLE OBJECTS AND ORPHANS ARE FINDABLE, AS A TERM IN THE ONE MATH
// (ISSUES 9.2, Don).
//
// "Is there a way to search for 0-staple objects, and/or orphans? (Same thing.)"
// There is not. The engine already knows: `core/staples.dart` names `unstapled`
// as an extent source, distinct from `unresolved`, and nothing surfaces either.
//
// The rule: it is a TERM IN THE SEARCH GRAMMAR over the pile, not a bespoke
// panel and not a special filter. "The stapled pile is a graph, project the
// graph": an object with zero staples has degree zero in the graph, so the
// honest form is a graph MEASURE the one math can compare -- and that gives the
// neighbouring questions for free out of the same grammar rather than as three
// features:
//
//   staples == 0                     degree zero -- the orphan, Don's question
//   unresolved > 0                   staples that resolve to nothing (a distinct
//                                    source in the engine; kept distinct here)
//   staples > 0 and neighbours == 0  reachable from nothing else -- a component
//                                    of one, which a one-ended pin is
//
// No term is a hardcoded keyword special-cased in the search path: each is a
// NUMBER bound in the one math's `Env`, exactly as `w` is bound for a weight
// formula, so `staples == 0 or a`, `not (staples == 0)`, `unresolved > 0 and not
// b` all parse and mean what the algebra says. "One math, used everywhere."
//
// THE CONTRACT this file names, which does not exist yet:
//
//   package:chronolog/core/pile_search.dart
//     typedef PileHits = ({List<String> ids, int more});
//     PileHits searchPile(ProjectionEngine engine, String source,
//         {Map<String, String> bindings = const {}, int? window});
//
// `source` is parsed by `math.dart`'s own `parse` -- a malformed query is a
// `MathRefusal` with a position, never a silent empty result. Per object, the
// resolver binds three NUMBERS and every bound name:
//
//   staples     the staple records naming this object, however many ends each has
//   unresolved  of those, the ones with an end whose position cannot be read
//               under its frame's law, or that names a record the document does
//               not hold -- the engine's own `unresolved` extent source
//   neighbours  the distinct OTHER records this object's staples NAME and the
//               document holds, position irrelevant: a staple to a frame whose
//               law cannot place it is still a staple to a real neighbour
//   <name>      true when the object is stapled to the frame the binding names
//
// These definitions are what make the three populations below pairwise disjoint,
// which is the whole of "keep them distinct" made executable. `window` bounds
// `ids` and `more` is a LOWER BOUND on the rest, as every windowed find in this
// program reports it. The same expression through the far-end find box
// (`searchConnectables`) reaches the same objects: a query that parses is a pile
// search, one that does not is a title find -- that routing is part of this
// contract.

import 'dart:math';

import 'package:chronolog/cards/connection_picker.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/math.dart';
import 'package:chronolog/core/pile_search.dart';
import 'package:chronolog/core/projection.dart';
import 'package:chronolog/core/records.dart';
import 'package:test/test.dart';

import '../helpers/projection_scene.dart';
import 'corpus.dart';

/// A frame whose own declaration cannot be resolved -- it counts in a frame the
/// document does not hold -- so a staple to it at a coordinate is a staple that
/// resolves to nothing while the document stays loadable.
const String stranded = 'frame:stranded';

/// One seeded world: stapled objects, orphans, objects whose only staples are
/// unresolved, and objects pinned by a one-ended staple to nothing else.
class Pile {
  Pile(Random random, {int stapled = 6, int orphans = 3, int unresolved = 2, int pinned = 2}) {
    scene.calendar('calendar:a');
    scene.group('frame:work', const []);
    scene.document = scene.document.put(
      'frames',
      stranded,
      const Frame(
        id: stranded,
        title: 'Stranded',
        traits: ['set', 'calendar'],
        extra: {'basis': 'frame:nothing-wears-this'},
      ),
    );
    for (var index = 0; index < stapled; index += 1) {
      final id = scene.object(title: 'Stapled $index');
      scene.place('calendar:a', civil(2026, 9, 1 + random.nextInt(28), 9), event: id);
      if (random.nextBool()) {
        scene.join('frame:work', id);
        inWork.add(id);
      }
      this.stapled.add(id);
    }
    for (var index = 0; index < orphans; index += 1) {
      this.orphans.add(scene.object(title: 'Orphan $index'));
    }
    for (var index = 0; index < unresolved; index += 1) {
      final id = scene.object(title: 'Unresolved $index');
      scene.staple(
        kind: 'anchor',
        ends: [
          ObjectEnd(id, point: 'start'),
          FrameEnd(stranded, position: Position.coordinate(civil(2026, 9, 3, 9))),
        ],
      );
      this.unresolved.add(id);
    }
    for (var index = 0; index < pinned; index += 1) {
      final id = scene.object(title: 'Pinned $index');
      // One end: a pin, legal data -- "a staple identifying a single point
      // (n = 1) is a pin that gives a point identity to reference". Degree one,
      // and reachable from nothing else.
      scene.staple(ends: [ObjectEnd(id, point: 'start')]);
      this.pinned.add(id);
    }
  }

  final Scene scene = Scene();
  final Set<String> stapled = {}, inWork = {}, orphans = {}, unresolved = {}, pinned = {};

  ProjectionEngine get engine => ProjectionEngine(scene.document);
}

Set<String> found(Pile pile, String source, {Map<String, String> bindings = const {}}) =>
    searchPile(pile.engine, source, bindings: bindings).ids.toSet();

void main() {
  for (final seed in seeds(5)) {
    final random = Random(seed);

    test('degree zero finds exactly the orphans -- not the unresolved, not the pinned '
        '(seed $seed)', () {
      final pile = Pile(random, orphans: 1 + random.nextInt(6));
      expect(
        found(pile, 'staples == 0'),
        equals(pile.orphans),
        reason:
            'ISSUES 9.2: "Is there a way to search for 0-staple objects, and/or orphans?" '
            'An object with zero staples has degree zero in the graph; that is the whole '
            'answer, and an object with a staple that resolves to nothing is NOT it.',
      );
    });

    test('unresolved staples are a distinct question with a distinct answer (seed $seed)', () {
      final pile = Pile(random, unresolved: 1 + random.nextInt(5));
      expect(
        found(pile, 'unresolved > 0'),
        equals(pile.unresolved),
        reason:
            '"Nobody said" and "somebody said something that will not resolve" are different '
            'facts (`staples.dart`): the engine keeps them apart, and so must the search.',
      );
    });

    test('reachable from nothing else is a third question: a pin has a staple and no '
        'neighbour (seed $seed)', () {
      final pile = Pile(random, pinned: 1 + random.nextInt(5));
      expect(found(pile, 'staples > 0 and neighbours == 0'), equals(pile.pinned));
      // The three populations are pairwise disjoint and together are exactly
      // what is not ordinarily stapled.
      final everythingElse = found(pile, 'staples == 0 or unresolved > 0 or neighbours == 0');
      expect(everythingElse, equals({...pile.orphans, ...pile.unresolved, ...pile.pinned}));
      expect(everythingElse.intersection(pile.stapled), isEmpty);
    });

    test('the term composes with the rest of the grammar: NOT, OR with a frame, AND with a '
        'frame (seed $seed)', () {
      final pile = Pile(random);
      final bindings = {'work': 'frame:work'};
      final all = pile.scene.document.events.keys.toSet();
      expect(
        found(pile, 'not (staples == 0)'),
        equals(all.difference(pile.orphans)),
        reason: 'NOT is complement within the pile',
      );
      expect(
        found(pile, 'staples == 0 or work', bindings: bindings),
        equals({...pile.orphans, ...pile.inWork}),
        reason: 'OR is union: orphans together with everything stapled to work',
      );
      expect(
        found(pile, 'work and not (staples == 0)', bindings: bindings),
        equals(pile.inWork),
        reason: 'AND is intersection, and a frame name means "stapled to it"',
      );
      // Arithmetic, because these are numbers and not keywords: a hub reads as
      // a degree, not as a fourth feature.
      final hub = pile.stapled.first;
      for (var index = 0; index < 3; index += 1) {
        pile.scene.staple(ends: [ObjectEnd(hub), ObjectEnd(pile.stapled.last)]);
      }
      expect(found(pile, 'staples >= 4'), contains(hub));
    });

    test('a query the grammar cannot read is refused with its position, never an empty '
        'answer (seed $seed)', () {
      final pile = Pile(random);
      expect(
        () => searchPile(pile.engine, 'staples == '),
        throwsA(isA<MathRefusal>()),
        reason: '"a sentence that does not parse is refused with the part named, never guessed at"',
      );
    });
  }

  test('overscale: thousands of objects, and every seeded orphan is recovered exactly, with the '
      'window bounding the listing and never the count', () {
    final random = Random(specSeed);
    final orphans = 40 + random.nextInt(60);
    final pile = Pile(random, stapled: 5000, orphans: orphans, unresolved: 20, pinned: 20);
    final whole = searchPile(pile.engine, 'staples == 0');
    expect(whole.ids.toSet(), equals(pile.orphans), reason: 'exact over a large pile');
    expect(whole.more, 0);
    final windowed = searchPile(pile.engine, 'staples == 0', window: 12);
    expect(windowed.ids, hasLength(12));
    expect(windowed.ids.toSet(), everyElement(isIn(pile.orphans)));
    expect(
      windowed.more,
      orphans - 12,
      reason: 'a budget bounds WORK (the window shown), never DATA (what can be found)',
    );
  });

  test('the far-end find box speaks the same grammar: the expression reaches the same objects', () {
    // "It is a search term, not a new panel." The one search surface a person
    // already types into is the connection picker's find box; a query that
    // parses as one math is the pile search, and a query that does not is the
    // title find it always was.
    final pile = Pile(Random(specSeed), orphans: 4);
    // Objects only: the report is about objects, and the structural frames of a
    // fresh document are stapled to nothing by design.
    final hits = searchConnectables(
      pile.scene.document,
      'staples == 0',
      window: 12,
      scan: 2000,
      frames: false,
    );
    expect(
      hits.hits.map((hit) => hit.id).toSet(),
      equals(pile.orphans),
      reason:
          'ISSUES 9.2: the find box is a substring match over titles and nothing else; the pile '
          'grammar has no door a person can type into.',
    );
    // And a plain word is still a title find.
    final byTitle = searchConnectables(
      pile.scene.document,
      'orphan',
      window: 12,
      scan: 2000,
      frames: false,
    );
    expect(byTitle.hits.map((hit) => hit.id).toSet(), equals(pile.orphans));
  });
}
