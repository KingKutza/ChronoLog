// "STAPLED HERE" IS A NEIGHBOURHOOD QUERY ON THE GRAPH (ISSUES 9.2, Don).
//
// "The frame for PTP shows nothing stapled here when there are two events. And
// frames with a lot of events are overflowing rather than showing staples.
// Perhaps a list of stapled items by type."
//
// Verified, three defects in one function (`cards/frame_card.dart`
// `_stapledHere`): it asks `indexes.framesOf`, which is the PLACEMENT index --
// "PLACED, not merely connected", gated on `isPlacement`, which demands an
// anchoring kind AND a coordinate. A staple to a GROUP frame carries neither, so
// two objects stapled to PTP were invisible in the row built to show them. It
// iterates `document.events` alone, so a frame stapled to a frame can never
// appear -- and eras are frames stapled together. And it truncates at
// `card.searchWindow` into a dead-end `'+N more.'`.
//
// The rule, and it is one fix: the row reads the WHOLE pile -- every record
// kind, every staple, coordinate or none, anchoring kind or none -- because the
// stapled pile is a graph and this row is a neighbourhood query on it. The
// groups come from the object-kind CATALOG (`core/object_kinds.dart`: "a catalog,
// not a type system: a fourth kind is a row ... nothing below branches on which
// key it is"), so a fourth kind gets its heading with no code change. Each group
// carries its TRUE total even when windowed. "If it is not usable at 500
// calendars it is improperly built for 3."
//
// THE CONTRACT this file names, which does not exist yet:
//
//   package:chronolog/core/stapled_here.dart
//     typedef StapledGroup = ({String kind, String label, int total, List<String> window});
//     class StapledHere { List<StapledGroup> groups; int total; StapledGroup? group(String kind); }
//     StapledHere stapledHere(ProjectionEngine engine, String frameId,
//         {Map<String, ObjectKind> kinds = objectKinds, int? window});
//
// `groups` holds one group per catalog kind that has members here, in catalog
// order, plus one group of kind `frame` for frames stapled to this frame. The
// catalog is a PARAMETER so the fourth-kind claim can be made executable -- an
// object's kind is the catalog row whose traits it wears (most specific bundle
// wins), never a branch on `task`/`todo`/`note`. `window` bounds the ids
// listed per group and NEVER the count. MELT, not a second walk: the engine
// already answers `connectionsOf(frameId)` with every staple edge from either
// side; this groups that answer and must not re-implement the traversal.

import 'dart:math';

import 'package:chronolog/core/object_kinds.dart';
import 'package:chronolog/core/projection.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/core/stapled_here.dart';
import 'package:test/test.dart';

import '../helpers/projection_scene.dart';
import '../helpers/staple_world.dart' as staple_world;
import 'corpus.dart';

T _pick<T>(Random random, List<T> items) => items[random.nextInt(items.length)];

/// Gives an object a catalog kind by its traits, the way the card's noun does.
void wear(Scene scene, String id, String kind, {Map<String, ObjectKind> kinds = objectKinds}) {
  final event = scene.document.events[id]!;
  scene.document = scene.document.put(
    'events',
    id,
    event.copyWith(traits: kinds[kind]!.traits),
  );
}

/// A group frame with members said EVERY way a staple can say it: an affiliation
/// (frame end, no point), a placement (frame end with a coordinate), an anchor
/// to the frame with no coordinate, and a plain staple whose verb is a word
/// nobody registered. Returns the seeded count per kind and the member ids.
({Map<String, int> counts, Set<String> members}) populate(
  Scene scene,
  Random random,
  String frameId, {
  required int count,
  Map<String, ObjectKind> kinds = objectKinds,
}) {
  final counts = <String, int>{};
  final members = <String>{};
  final ways = <void Function(String)>[
    (id) => scene.join(frameId, id),
    (id) => scene.place(frameId, civil(2026, 9, 1 + random.nextInt(28), 9), event: id),
    (id) => scene.staple(
      kind: 'anchor',
      ends: [ObjectEnd(id, point: 'start'), StapleEnd.frame(frameId)],
    ),
    // A verb carries zero engine meaning: a word nothing registered is as legal
    // as any and must be as visible.
    (id) => scene.staple(
      kind: 'concerns',
      ends: [ObjectEnd(id), StapleEnd.frame(frameId)],
    ),
  ];
  for (var index = 0; index < count; index += 1) {
    final kind = _pick(random, kinds.keys.toList());
    final id = scene.object(title: 'Member $index');
    wear(scene, id, kind, kinds: kinds);
    _pick(random, ways)(id);
    counts[kind] = (counts[kind] ?? 0) + 1;
    members.add(id);
  }
  return (counts: counts, members: members);
}

void main() {
  for (final seed in seeds(5)) {
    test('every object stapled to a frame by any staple appears, grouped by its kind, '
        'and nothing unstapled does (seed $seed)', () {
      final random = Random(seed);
      final scene = Scene()..calendar('calendar:a');
      scene.group('frame:ptp', const []);
      final seeded = populate(scene, random, 'frame:ptp', count: 3 + random.nextInt(12));
      // Strangers: placed on the calendar, stapled to nothing here.
      final strangers = {
        for (var index = 0; index < 1 + random.nextInt(4); index += 1)
          scene.place('calendar:a', civil(2026, 9, 2, 10), title: 'Stranger $index'),
      };

      final here = stapledHere(ProjectionEngine(scene.document), 'frame:ptp');
      final listed = {
        for (final group in here.groups)
          for (final id in group.window) id,
      };
      expect(
        listed,
        equals(seeded.members),
        reason:
            'ISSUES 9.2: the row answers "placed here" when it is labelled "stapled here" -- '
            'an affiliation, an anchor without a coordinate and an unregistered verb are all '
            'staples to this frame, and a placement on another frame is not.',
      );
      for (final id in strangers) {
        expect(listed, isNot(contains(scene.document.relations[id]!.event)));
      }
      for (final entry in seeded.counts.entries) {
        expect(
          here.group(entry.key)?.total,
          entry.value,
          reason: 'the ${entry.key} group counts exactly the ${entry.key}s stapled here',
        );
      }
      expect(here.total, seeded.members.length);
    });

    test('a frame stapled to a frame appears: eras are frames stapled together (seed $seed)', () {
      final random = Random(seed);
      final world = staple_world.World();
      world.era('era:first', key: '1E', years: '${100 + random.nextInt(900)}');
      world.era('era:second', key: '2E', after: 'era:first');
      // And a correspondence, frame to frame, at a point: a different sentence,
      // the same graph.
      world.staple(
        kind: 'correspondence',
        ends: [
          FrameEnd('era:second', position: Position.coordinate(staple_world.civil(3, 1, 1))),
          FrameEnd(
            'frame:invented',
            position: Position.coordinate(staple_world.stroke(1 + random.nextInt(40))),
          ),
        ],
      );
      final engine = ProjectionEngine(world.document);

      final second = stapledHere(engine, 'era:second');
      final frames = second.group('frame');
      expect(
        frames?.window,
        containsAll(const ['era:first', 'frame:invented']),
        reason:
            'ISSUES 9.2: `_stapledHere` iterates `document.events` alone, so a frame stapled '
            'to a frame -- a succession, a correspondence -- can never appear, and the region '
            'cannot show an era\'s own neighbours.',
      );
      // From either end: a staple you can only see from one side is half a record.
      expect(stapledHere(engine, 'era:first').group('frame')?.window, contains('era:second'));
    });

    test('a fourth kind in the catalog is a fourth heading, with no code change (seed $seed)', () {
      // "A catalog, not a type system: a fourth kind is a row." This FAILS if
      // the grouping branches on a written list of kinds, or if kind derivation
      // does -- an object wearing the meeting bundle is a meeting, not an event
      // that happens to carry an extra trait.
      final random = Random(seed);
      final kinds = {
        ...objectKinds,
        'meeting': const ObjectKind('Meeting', 'New meeting', ['event', 'meeting'], 'placed', false),
      };
      final scene = Scene()..group('frame:ptp', const []);
      // At least one meeting, whatever the seed deals: the claim is about the
      // fourth kind and needs one to be about.
      final certain = scene.object(title: 'The standing meeting');
      wear(scene, certain, 'meeting', kinds: kinds);
      scene.join('frame:ptp', certain);
      final seeded = populate(scene, random, 'frame:ptp', count: 6 + random.nextInt(10), kinds: kinds);
      final counts = {...seeded.counts, 'meeting': (seeded.counts['meeting'] ?? 0) + 1};
      final here = stapledHere(ProjectionEngine(scene.document), 'frame:ptp', kinds: kinds);
      for (final entry in counts.entries) {
        expect(
          here.group(entry.key)?.total,
          entry.value,
          reason: 'the ${entry.key} heading counts its own, from the catalog handed in',
        );
      }
      expect(
        here.group('meeting')?.label,
        kinds['meeting']!.label,
        reason: 'the heading is the catalog row\'s own label',
      );
      final meetings = here.group('meeting')?.window ?? const [];
      expect(meetings, contains(certain));
      for (final id in meetings) {
        expect(
          here.group('event')?.window ?? const [],
          isNot(contains(id)),
          reason: 'a meeting is not also counted as an event',
        );
      }
    });

    test('a window bounds what is listed and never what is counted (seed $seed)', () {
      final random = Random(seed);
      final scene = Scene()..group('frame:ptp', const []);
      final window = 3 + random.nextInt(6);
      final seeded = populate(scene, random, 'frame:ptp', count: window * 2 + 1 + random.nextInt(9));
      final here = stapledHere(ProjectionEngine(scene.document), 'frame:ptp', window: window);
      for (final group in here.groups) {
        expect(group.window.length, lessThanOrEqualTo(window));
        expect(
          group.total,
          seeded.counts[group.kind],
          reason:
              'ISSUES 9.2: the remainder became "+N more." with no way in. A group says its '
              'true total however few it lists.',
        );
      }
      expect(here.total, seeded.members.length);
    });
  }

  test('overscale: a frame holding hundreds of members among thousands of objects reads as '
      'counts by kind with a window into each', () {
    // "If it is not usable at 500 calendars it is improperly built for 3." No
    // millisecond pin; the claim is that the answer is exact and bounded in what
    // it lists, over a document this size, with no full enumeration handed back.
    final random = Random(specSeed);
    final scene = Scene()..calendar('calendar:a');
    for (var index = 0; index < 500; index += 1) {
      scene.group('group:$index', const []);
    }
    final seeded = populate(scene, random, 'group:7', count: 600);
    for (var index = 0; index < 4400; index += 1) {
      final id = scene.object(title: 'Elsewhere $index');
      final elsewhere = 1 + random.nextInt(499);
      scene.join('group:${elsewhere == 7 ? 8 : elsewhere}', id);
    }
    const window = 12;
    final here = stapledHere(ProjectionEngine(scene.document), 'group:7', window: window);
    expect(here.total, seeded.members.length);
    for (final group in here.groups) {
      expect(group.total, seeded.counts[group.kind] ?? 0);
      expect(group.window.length, lessThanOrEqualTo(window));
    }
    final listed = {
      for (final group in here.groups)
        for (final id in group.window) id,
    };
    expect(listed, everyElement(isIn(seeded.members)));
  });
}
