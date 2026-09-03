// The shape half of the ToDo lenses.
//
// THE STATE-GATE IS GONE, and its absence is the first thing pinned here: there
// is no selected-frames parameter anywhere in this module, so no entry handed to
// it can be silently dropped. Visibility is authored as NOT over connections in
// the projection engine, and a lens that cannot see the selection cannot
// second-guess it.
//
// The rest is the shape rules as properties over random placements: a section
// exists because an entry put it there, the unnamed section leads, and the named
// ones follow in title order.

import 'dart:math';

import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/object_kinds.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/core/todo_shape.dart';
import 'package:chronolog/core/validate.dart';
import 'package:test/test.dart';

import 'corpus.dart';

const String _alphabet = 'abcdefghij';

String _word(Random random) =>
    [for (var i = 0; i < 2 + random.nextInt(4); i++) _alphabet[random.nextInt(_alphabet.length)]]
        .join();

void main() {
  group('the groupings are data', () {
    test('one shared list, and an unknown value normalizes', () {
      // FRAME LEADS AND FRAME IS THE DEFAULT (ISSUES 172, ruled): state,
      // container and frame are one reading -- the record at the far end of a
      // staple -- differing only in which frames a column admits, so the
      // unfiltered case is the default. The keys are spellings an old view may
      // still carry, not a closed set the engine reasons about, so an unknown
      // one normalizes to the table's FIRST ROW rather than to a named word.
      expect(lensGroupings.first, 'frame');
      expect(lensGroupings.toSet(), {'frame', 'importance', 'container', 'state'});
      for (final grouping in lensGroupings) {
        expect(normalizeGrouping(grouping), grouping);
      }
      final random = Random(specSeed);
      for (var index = 0; index < 20; index++) {
        expect(normalizeGrouping(_word(random)), lensGroupings.first);
      }
      expect(normalizeGrouping(null), lensGroupings.first);
      expect(normalizeGrouping(7), lensGroupings.first);
    });
  });

  group('one state derivation', () {
    test('random documents: done beats closed beats sparse beats nothing', () {
      for (final seed in seeds(60)) {
        final random = Random(seed);
        var document = createEmptyWorkspaceDocument();
        final described = random.nextBool();
        document = document.put(
          'events',
          'event:0',
          Event(
            id: 'event:0',
            traits: traitsForObjectKind(const [], 'todo'),
            magnitudes: {'duration': durationMagnitude()},
            payload: {'title': _word(random), if (described) 'description': _word(random)},
          ),
        );
        // Generated state names, plus Done sometimes -- the vocabulary is not a
        // list this test knows.
        final states = <String>{
          for (var i = 0; i < random.nextInt(3); i++) 'frame:state-${_word(random)}',
          if (random.nextInt(3) == 0) doneStateFrameId,
        }.toList();
        final plainGroups = <String>[
          for (var i = 0; i < random.nextInt(3); i++) 'frame:group-${_word(random)}',
        ];
        for (final (index, id) in [...states, ...plainGroups].indexed) {
          final isState = states.contains(id);
          document = document.put(
            'frames',
            id,
            Frame(
              id: id,
              title: _word(random),
              traits: isState ? stateFrameTraits : const ['set', 'group'],
            ),
          );
          document = document.put(
            'relations',
            'relation:m$index',
            Relation(
              id: 'relation:m$index',
              // AFFILIATION (ruled 2026-09-01): the object's whole on the sheet,
              // said as a staple whose frame end names no point.
              type: 'staple',
              extra: {
                'ends': [
                  const ObjectEnd('event:0').toJson(),
                  StapleEnd.frame(id).toJson(),
                ],
              },
            ),
          );
        }
        final stapled = random.nextBool();
        if (stapled) {
          document = putStaple(
            document,
            id: 'relation:anchor',
            kind: 'anchor',
            ends: [
              const StapleEnd.object('event:0', point: 'start'),
              StapleEnd.frame(
                'frame:wall-time',
                position: Position.coordinate(const {
                  'levels': [
                    {'level': 'year', 'value': '2026'},
                  ],
                }),
              ),
            ],
          ).document;
        }
        expect(validateDocument(document).errors, isEmpty, reason: 'seed $seed');

        final facts = ObjectFacts(document);
        final groups = facts.groups('event:0');
        final state = entryState(
          facts,
          'event:0',
          stateFrames: [
            for (final id in groups)
              if (isStateFrame(document.frames[id])) id,
          ],
          groups: groups,
        );
        // DONE IS A FRAME LIKE ANY OTHER (ISSUES 9.2). This ladder used to
        // read `doneStateFrameId` for its first rung and call every other state
        // frame `closed` -- the very split the ruling deleted, which is why the
        // frames below are built indistinguishable but for their ids. Somebody
        // said a status, or nobody did.
        final expected = states.isNotEmpty
            ? resolvedStateWord
            : (described || groups.isNotEmpty || stapled)
            ? null
            : 'sparse';
        expect(state, expected, reason: 'seed $seed');
      }
    });

    test('RULED ANCHOR: sparse is the title-only predicate, nothing more', () {
      var document = createEmptyWorkspaceDocument().put(
        'events',
        'event:0',
        Event(
          id: 'event:0',
          traits: traitsForObjectKind(const [], 'todo'),
          magnitudes: {'duration': durationMagnitude()},
          payload: const {'title': 'Just a title'},
        ),
      );
      final bare = ObjectFacts(document);
      expect(entryState(bare, 'event:0', stateFrames: const [], groups: const []), 'sparse');
      // A blank description is not a description.
      document = document.put(
        'events',
        'event:0',
        document.events['event:0']!.copyWith(
          payload: const {'title': 'Just a title', 'description': '   '},
        ),
      );
      expect(
        entryState(ObjectFacts(document), 'event:0', stateFrames: const [], groups: const []),
        'sparse',
      );
    });
  });

  group('section shape', () {
    test('random placements: no empty sections, null leads, titles order', () {
      for (final seed in seeds(60)) {
        final random = Random(seed);
        final keys = <String?>[null, for (var i = 0; i < 1 + random.nextInt(5); i++) 'key:$i'];
        final titles = {
          for (final key in keys) key: random.nextInt(3) == 0 ? 'shared' : _word(random),
        };
        final entries = [for (var i = 0; i < random.nextInt(12); i++) 'entry:$i'];
        final placed = <String, List<String?>>{
          for (final entry in entries)
            entry: [
              for (final key in keys)
                if (random.nextInt(3) == 0) key,
            ],
        };
        final sections = sectionsOf<String>(
          entries,
          (entry) => [
            for (final key in placed[entry]!)
              (key: key, title: titles[key]!, meta: key == null ? null : 'meta'),
          ],
        );
        // A section exists BECAUSE an entry put it there.
        for (final section in sections) {
          expect(section.entries, isNotEmpty, reason: 'seed $seed');
          expect(section.title, titles[section.key], reason: 'seed $seed');
          for (final entry in section.entries) {
            expect(placed[entry], contains(section.key), reason: 'seed $seed');
          }
        }
        final expectedKeys = {for (final entry in entries) ...placed[entry]!};
        expect(
          sections.map((section) => section.key).toSet(),
          expectedKeys,
          reason: 'seed $seed: every used key, and no unused one',
        );
        // An entry in N sections appears N times, never more, never fewer.
        for (final entry in entries) {
          expect(
            sections.where((section) => section.entries.contains(entry)).length,
            placed[entry]!.length,
            reason: 'seed $seed: $entry',
          );
        }
        if (expectedKeys.contains(null)) {
          expect(sections.first.key, isNull, reason: 'seed $seed: null leads');
        }
        final named = sections.where((section) => section.key != null).toList();
        final ordered = [for (final s in named) '${s.title} ${s.key}'];
        expect(
          ordered,
          orderedEquals([...ordered]..sort()),
          reason: 'seed $seed: title order, broken by key',
        );
        // Entry order WITHIN a section is the order given.
        for (final section in sections) {
          expect(
            section.entries,
            orderedEquals(entries.where((entry) => placed[entry]!.contains(section.key))),
            reason: 'seed $seed',
          );
        }
      }
    });

    test('RULED ANCHOR: no entries means no sections, not an empty scaffold', () {
      expect(sectionsOf<String>(const [], (_) => const []), isEmpty);
      // An entry with no placement puts nothing anywhere -- and is not lost to a
      // gate, because there is no gate: the caller decides what it hands over.
      expect(sectionsOf<String>(const ['a', 'b'], (_) => const []), isEmpty);
    });

    test('RULED ANCHOR: the unnamed section leads, whatever it is called', () {
      final sections = sectionsOf<String>(
        const ['a', 'b', 'c'],
        (entry) => [
          if (entry == 'a') (key: null, title: 'Open', meta: null),
          if (entry != 'a') (key: 'frame:1', title: 'Aardvark', meta: null),
          if (entry == 'c') (key: 'frame:2', title: 'Zebra', meta: 7),
        ],
      );
      expect(sections.map((section) => section.title), ['Open', 'Aardvark', 'Zebra']);
      expect(sections.first.key, isNull);
      expect(sections.last.meta, 7);
      expect(sections[1].entries, ['b', 'c']);
    });

    test('a state-affiliated entry is never dropped for being in a state', () {
      // The condemned gate would have removed this entry unless its state frame
      // happened to be selected. There is nothing to select against, so it is
      // sectioned like any other.
      final sections = sectionsOf<String>(const [
        'done-one',
      ], (entry) => [(key: doneStateFrameId, title: 'Done', meta: null)]);
      expect(sections, hasLength(1));
      expect(sections.single.entries, ['done-one']);
    });
  });
}
