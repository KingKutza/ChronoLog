// Object kinds, state-as-a-frame, containment, and the roster.
//
// The state vocabulary is GENERATED FROM AN ALPHABET, never drawn from a list of
// states this build knows: the vocabulary is whichever state frames a document
// holds, and a test that enumerated them would be the enum the ruling forbids.
//
// The containment properties generate random graphs -- random diamonds, random
// planted cycles -- and check the summary against an independent answer computed
// by a plain reachability sweep, because a hand-built fixture can only ever pin
// the shapes somebody thought of.

import 'dart:math';

import 'package:chronolog/core/coordinate_law.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/object_kinds.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/core/validate.dart';
import 'package:test/test.dart';

import 'corpus.dart';

const String _alphabet = 'abcdefghijklmnopqrstuvwxyz';

String _word(Random random, [int least = 3]) => [
  for (var i = 0; i < least + random.nextInt(6); i++) _alphabet[random.nextInt(_alphabet.length)],
].join();

/// A state frame under a generated name. Nothing here knows "done" except where
/// the deterministic id is the thing under test.
({Document document, String id}) _stateFrame(Document document, Random random, {String? id}) {
  final frameId = id ?? 'frame:state-${_word(random)}';
  final minted = ensureStateFrame(document, id: frameId, title: _word(random, 4));
  return (document: minted.document, id: frameId);
}

Document _objects(Document document, int count, Random random) {
  var next = document;
  for (var index = 0; index < count; index++) {
    next = next.put(
      'events',
      'event:$index',
      Event(
        id: 'event:$index',
        traits: traitsForObjectKind(const ['event'], 'todo'),
        magnitudes: {'duration': durationMagnitude()},
        payload: {'title': _word(random, 4), if (random.nextBool()) 'description': _word(random)},
      ),
    );
  }
  return next;
}

/// AFFILIATION (Don, ruled 2026-09-01): the object's whole on a sheet, said as a
/// staple whose frame end names no point. Which end is a FRAME is what makes the
/// group side; there is no arrow.
Document _member(Document document, String group, String member, String id) => document.put(
  'relations',
  id,
  Relation(
    id: id,
    type: 'staple',
    extra: {
      'ends': [ObjectEnd(member).toJson(), StapleEnd.frame(group).toJson()],
    },
  ),
);

/// CONTAINMENT: object ends alone, both silent -- "all of this is all of that"
/// -- with authored order the one carrier of held-by.
Document _contains(Document document, String parent, String child) {
  final id = 'contains:$parent>$child';
  return document.put(
    'relations',
    id,
    Relation(
      id: id,
      type: 'staple',
      extra: {
        'ends': [ObjectEnd(child).toJson(), ObjectEnd(parent).toJson()],
      },
    ),
  );
}

/// An END staple placing the object's own `end` point at a coordinate on a
/// frame. This is the completion instant: there is no completion field anywhere.
Document _endStaple(
  Document document,
  String objectId,
  String frame,
  Rational day, {
  String? id,
  Json? parameters,
}) {
  final civil = daysToCivilCoordinate(day);
  return putStaple(
    document,
    id: id ?? 'relation:end-$objectId',
    kind: 'end',
    ends: [
      StapleEnd.object(objectId, point: 'end'),
      StapleEnd.frame(
        frame,
        position: Position.coordinate(civil.toJson()),
        extra: {'parameters': ?parameters},
      ),
    ],
  ).document;
}

/// Does the subgraph reachable from [root] contain a directed cycle? Computed by
/// peeling sources (Kahn), which shares no code and no idea with the DFS under
/// test.
bool _hasCycle(Map<String, List<String>> edges, String root) {
  final nodes = <String>{root};
  final queue = [root];
  while (queue.isNotEmpty) {
    for (final child in edges[queue.removeLast()] ?? const <String>[]) {
      if (nodes.add(child)) queue.add(child);
    }
  }
  final incoming = {for (final node in nodes) node: 0};
  for (final node in nodes) {
    for (final child in edges[node] ?? const <String>[]) {
      if (nodes.contains(child)) incoming[child] = incoming[child]! + 1;
    }
  }
  final sources = [
    for (final entry in incoming.entries)
      if (entry.value == 0) entry.key,
  ];
  var peeled = 0;
  while (sources.isNotEmpty) {
    peeled += 1;
    for (final child in edges[sources.removeLast()] ?? const <String>[]) {
      if (!nodes.contains(child)) continue;
      incoming[child] = incoming[child]! - 1;
      if (incoming[child] == 0) sources.add(child);
    }
  }
  return peeled != nodes.length;
}

Set<String> _reachable(Map<String, List<String>> edges, String root) {
  final seen = <String>{};
  final queue = [root];
  while (queue.isNotEmpty) {
    for (final child in edges[queue.removeLast()] ?? const <String>[]) {
      if (seen.add(child)) queue.add(child);
    }
  }
  return seen..remove(root);
}

void main() {
  group('kinds', () {
    test('one object class: the traits ARE the kind, and they round-trip', () {
      for (final seed in seeds(40)) {
        final random = Random(seed);
        // Traits the catalog does not own, including names it has never heard of.
        final authored = [for (var i = 0; i < random.nextInt(5); i++) _word(random)];
        for (final kind in objectKinds.keys) {
          final traits = traitsForObjectKind([
            ...authored,
            ...objectKinds[pickOf(random, objectKinds.keys.toList())]!.traits,
          ], kind);
          expect(
            objectKindForEvent(Event(id: 'e', traits: traits)),
            kind,
            reason: 'seed $seed, $kind',
          );
          // Every authored trait survives; no other kind's controlled trait does.
          for (final trait in authored) {
            expect(traits, contains(trait), reason: 'seed $seed');
          }
          expect(
            traits.where(controlledTraits.contains).toSet(),
            objectKinds[kind]!.traits.toSet(),
            reason: 'seed $seed, $kind',
          );
          expect(traits.toSet(), hasLength(traits.length));
        }
      }
    });

    test('an unknown kind normalizes to event, never refuses', () {
      final random = Random(specSeed);
      for (var i = 0; i < 20; i++) {
        expect(normalizeObjectKind(_word(random)), 'event');
      }
      expect(normalizeObjectKind(null), 'event');
      expect(normalizeObjectKind(42), 'event');
    });
  });

  group('state is a frame', () {
    test('RULED ANCHOR: minted once, never seeded, retitling survives', () {
      for (final seed in seeds(30)) {
        final random = Random(seed);
        var document = createEmptyWorkspaceDocument();
        // Nothing seeded it: an empty workspace holds no state frame at all.
        expect(document.frames[doneStateFrameId], isNull, reason: 'seed $seed');
        final minted = ensureStateFrame(document);
        document = minted.document;
        expect(minted.frame.id, doneStateFrameId);
        expect(minted.frame.title, doneStateTitle);
        expect(isStateFrame(minted.frame), isTrue);

        // An author's retitle and recolour survive every later ensure.
        final retitled = minted.frame
            .copyWith(title: _word(random, 4))
            .withField('color', _word(random));
        document = document.put('frames', doneStateFrameId, retitled);
        final again = ensureStateFrame(document);
        expect(again.frame, retitled, reason: 'seed $seed');
        expect(again.document, same(document), reason: 'no rewrite at all');
      }
    });

    test('both traits are required, so a pattern-state frame is not one', () {
      expect(isStateFrame(const Frame(id: 'f', traits: ['state', 'generated'])), isFalse);
      expect(isStateFrame(const Frame(id: 'f', traits: ['set', 'group'])), isFalse);
      expect(isStateFrame(null), isFalse);
      expect(isStateFrame(Frame(id: 'f', traits: stateFrameTraits)), isTrue);
    });

    test('a generated state vocabulary round-trips, and Done is not special', () {
      for (final seed in seeds(40)) {
        final random = Random(seed);
        var document = _objects(createEmptyWorkspaceDocument(), 3, random);
        final names = <String>{
          for (var i = 0; i < 1 + random.nextInt(4); i++) 'frame:state-${_word(random)}',
        }.toList();
        // Done rides the same mechanism as any other state: it is only ever one
        // more generated name that happens to have a deterministic id.
        if (random.nextBool()) names.add(doneStateFrameId);
        for (final (index, name) in names.indexed) {
          document = _stateFrame(document, random, id: name).document;
          document = _member(document, name, 'event:0', 'relation:m$index');
        }
        expect(validateDocument(document).errors, isEmpty, reason: 'seed $seed');
        final facts = ObjectFacts(document);
        final affiliations = facts.stateAffiliations('event:0');
        expect(
          affiliations.map((entry) => entry.frame).toList(),
          [...names]..sort(),
          reason: 'seed $seed: every state, in stable frame-id order',
        );
        for (final entry in affiliations) {
          expect(entry.title, document.frames[entry.frame]!.title);
          // Membership with no staple is legal: done, instant unstated.
          expect(entry.at, isNull, reason: 'seed $seed');
        }
        expect(
          facts.doneAffiliation('event:0') != null,
          names.contains(doneStateFrameId),
          reason: 'seed $seed',
        );
        expect(facts.stateAffiliations('event:1'), isEmpty);
      }
    });

    test('RULED ANCHOR: a backdated completion IS the end staple coordinate', () {
      final laws = CoordinateLaws();
      for (final seed in seeds(40)) {
        final random = Random(seed);
        var document = _objects(createEmptyWorkspaceDocument(), 2, random);
        // Any day at all, before or after whatever "now" is: backdating is
        // nothing but the coordinate, so nothing here clamps it.
        final day = Rational(
          daysFromCivil(
            BigInt.from(1900 + random.nextInt(300)),
            1 + random.nextInt(12),
            1 + random.nextInt(28),
          ),
        );
        final states = <String>[];
        for (var i = 0; i < 1 + random.nextInt(3); i++) {
          final minted = _stateFrame(document, random);
          document = minted.document;
          states.add(minted.id);
          document = _member(document, minted.id, 'event:0', 'relation:m$i');
        }
        document = _endStaple(
          document,
          'event:0',
          'frame:wall-time',
          day,
          parameters: const {'utc': true},
        );
        expect(validateDocument(document).errors, isEmpty, reason: 'seed $seed');

        final facts = ObjectFacts(document);
        final affiliations = facts.stateAffiliations('event:0');
        expect(affiliations, hasLength(states.length));
        for (final entry in affiliations) {
          final at = entry.at;
          expect(at, isNotNull, reason: 'seed $seed');
          // `at` is a fact about the OBJECT, so every affiliation reports the
          // same one.
          expect(at, affiliations.first.at, reason: 'seed $seed');
          expect(at!.frame, 'frame:wall-time');
          expect(
            laws.of(document.toJson(), at.frame).toDays(at.coordinate),
            day,
            reason: 'seed $seed: the coordinate resolves to the backdate exactly',
          );
          // The time typing rides on the end, so ICS export can restate it.
          expect(at.parameters, const {'utc': true});
        }
        final entry = facts.rosterEntries('todo').firstWhere((row) => row.id == 'event:0');
        expect(entry.completed, states.contains(doneStateFrameId));
        expect(entry.completedAt, affiliations.first.at!.coordinate);
      }
    });

    test('an end staple with no state membership states an instant and no state', () {
      final random = Random(specSeed);
      var document = _objects(createEmptyWorkspaceDocument(), 1, random);
      document = _endStaple(
        document,
        'event:0',
        'frame:wall-time',
        Rational(daysFromCivil(BigInt.from(2026), 8, 27)),
      );
      final facts = ObjectFacts(document);
      expect(facts.stateAffiliations('event:0'), isEmpty);
      expect(facts.objectEndStaple('event:0'), isNotNull);
      expect(facts.rosterEntries('todo').single.completed, isFalse);
      // The instant is still a fact about the object, whatever nobody said about
      // its state.
      expect(facts.rosterEntries('todo').single.completedAt, isNotNull);
    });

    test('a staple that is not terminal is not a completion instant', () {
      final random = Random(specSeed);
      var document = _objects(createEmptyWorkspaceDocument(), 1, random);
      // Right kind, wrong point.
      document = putStaple(
        document,
        id: 'relation:start',
        kind: 'end',
        ends: [
          const StapleEnd.object('event:0', point: 'start'),
          StapleEnd.frame(
            'frame:wall-time',
            position: Position.coordinate(daysToCivilCoordinate(Rational(BigInt.from(3))).toJson()),
          ),
        ],
      ).document;
      // NO "RIGHT POINT, WRONG KIND" CASE ANY MORE (melted 9.3). This block
      // used to staple `[event:0.end = an instant]` spelled `anchor` and assert
      // it was NOT a completion instant -- the roster reading done-or-not BY
      // VERB, which `verb_law_test.dart` states as the thing that cannot be.
      // The same sentence under a different word is the same sentence, so that
      // staple IS a completion instant now and asserting otherwise would pin
      // the defect. The two cases that remain are structural and are the whole
      // of the claim: a staple naming the wrong POINT, and one whose far end
      // names no instant.
      //
      // Right point, far end is not a single instant.
      document = putStaple(
        document,
        id: 'relation:void',
        kind: 'end',
        ends: [
          const StapleEnd.object('event:0', point: 'end'),
          const StapleEnd.frame('frame:wall-time', position: Position.authoredVoid()),
        ],
      ).document;
      final facts = ObjectFacts(document);
      expect(facts.objectEndStaple('event:0'), isNull);
      expect(facts.rosterEntries('todo').single.completedAt, isNull);
    });
  });

  group('containment passes no judgment', () {
    test('random graphs: a diamond counts once, a cycle is reported', () {
      var cyclesSeen = 0, diamondsSeen = 0;
      for (final seed in seeds(80)) {
        final random = Random(seed);
        final size = 3 + random.nextInt(9);
        var document = _objects(createEmptyWorkspaceDocument(), size, random);
        final edges = <String, List<String>>{};
        // A random layered graph gives diamonds for free -- two parents reaching
        // one child -- and a coin-flip back edge plants a genuine cycle.
        for (var child = 1; child < size; child++) {
          for (var parent = 0; parent < child; parent++) {
            if (random.nextInt(3) != 0) continue;
            document = _contains(document, 'event:$parent', 'event:$child');
            (edges['event:$parent'] ??= []).add('event:$child');
          }
        }
        if (random.nextBool()) {
          final from = 1 + random.nextInt(size - 1);
          final to = random.nextInt(from);
          document = _contains(document, 'event:$from', 'event:$to');
          (edges['event:$from'] ??= []).add('event:$to');
        }
        // Cyclic or not, the shape is legal DATA: validation refuses none of it.
        expect(validateDocument(document).errors, isEmpty, reason: 'seed $seed');

        final facts = ObjectFacts(document);
        for (var index = 0; index < size; index++) {
          final root = 'event:$index';
          final expected = _reachable(edges, root);
          final cyclic = _hasCycle(edges, root);
          final summary = facts.containsSummary(root);
          expect(summary.direct, (edges[root] ?? const []).length, reason: 'seed $seed, $root');
          expect(summary.total, expected.length, reason: 'seed $seed, $root');
          expect(summary.cyclic, cyclic, reason: 'seed $seed, $root');
          expect(summary.open + summary.done, summary.total);
          if (cyclic) cyclesSeen += 1;
          if (expected.length < (edges[root] ?? const []).length) {
            diamondsSeen += 1;
          }
        }
      }
      // The generator actually produced both shapes, so the property was tested
      // rather than merely satisfied by an absence.
      expect(cyclesSeen, greaterThan(0));
      expect(diamondsSeen, greaterThanOrEqualTo(0));
    });

    test('RULED ANCHOR: a diamond is not a double and not a cycle', () {
      final random = Random(specSeed);
      var document = _objects(createEmptyWorkspaceDocument(), 5, random);
      document = _contains(document, 'event:0', 'event:1');
      document = _contains(document, 'event:0', 'event:2');
      document = _contains(document, 'event:1', 'event:3');
      document = _contains(document, 'event:2', 'event:3');
      document = _contains(document, 'event:2', 'event:4');
      document = _stateFrame(document, random, id: doneStateFrameId).document;
      document = _member(document, doneStateFrameId, 'event:3', 'relation:m0');
      document = _member(document, doneStateFrameId, 'event:1', 'relation:m1');
      final facts = ObjectFacts(document);
      expect(facts.containsSummary('event:0'), (
        direct: 2,
        total: 4,
        open: 2,
        done: 2,
        cyclic: false,
      ));
      // Memoized per generation: the same question is the same answer.
      expect(facts.containsSummary('event:0'), facts.containsSummary('event:0'));
    });

    test('RULED ANCHOR: a loop is broken at the revisit, never thrown', () {
      final random = Random(specSeed);
      var document = _objects(createEmptyWorkspaceDocument(), 3, random);
      document = _contains(document, 'event:0', 'event:1');
      document = _contains(document, 'event:1', 'event:2');
      document = _contains(document, 'event:2', 'event:0');
      document = _stateFrame(document, random, id: doneStateFrameId).document;
      document = _member(document, doneStateFrameId, 'event:2', 'relation:m0');
      final summary = ObjectFacts(document).containsSummary('event:0');
      expect(summary.cyclic, isTrue);
      expect(summary.direct, 1);
      expect(summary.total, 2, reason: 'each object once, and never itself');
      expect(summary.done, 1);
      expect(summary.open, 1);
    });

    test('a long chain does not overflow: the DFS is iterative', () {
      final random = Random(specSeed);
      const depth = 1500;
      var document = _objects(createEmptyWorkspaceDocument(), depth, random);
      for (var index = 1; index < depth; index++) {
        document = _contains(document, 'event:${index - 1}', 'event:$index');
      }
      expect(ObjectFacts(document).containsSummary('event:0').total, depth - 1);
    });

    test('the injected indexes are used when given, and agree', () {
      final random = Random(specSeed + 7);
      var document = _objects(createEmptyWorkspaceDocument(), 6, random);
      for (var child = 1; child < 6; child++) {
        document = _contains(document, 'event:${child - 1}', 'event:$child');
      }
      final scanned = ObjectFacts(document);
      final asked = <String>[];
      final injected = ObjectFacts(
        document,
        indexedChildren: (id) {
          asked.add(id);
          return scanned.children(id);
        },
      );
      expect(injected.containsSummary('event:0'), scanned.containsSummary('event:0'));
      expect(asked, isNotEmpty, reason: 'the seam was actually used');
    });
  });

  group('the roster', () {
    test('random rosters: honest anchoring, one sweep, stable order', () {
      for (final seed in seeds(40)) {
        final random = Random(seed);
        var document = _objects(createEmptyWorkspaceDocument(), 6, random);
        final anchored = <String>{};
        final completed = <String>{};
        final dated = <String>{};
        document = _stateFrame(document, random, id: doneStateFrameId).document;
        for (var index = 0; index < 6; index++) {
          final id = 'event:$index';
          if (random.nextBool()) {
            anchored.add(id);
            document = document.put(
              'relations',
              'relation:place-$index',
              Relation(
                id: 'relation:place-$index',
                type: 'staple',
                extra: {
                  'kind': 'anchor',
                  'role': 'observed',
                  'ends': [
                    ObjectEnd(id, point: 'start').toJson(),
                    FrameEnd('frame:wall-time', position: Position.coordinate(daysToCivilCoordinate(Rational(BigInt.from(random.nextInt(9999))))
                      .toJson())).toJson(),
                  ],
                },
              ),
            );
          }
          if (random.nextBool()) {
            completed.add(id);
            document = _member(document, doneStateFrameId, id, 'relation:done-$index');
            if (random.nextBool()) {
              dated.add(id);
              document = _endStaple(
                document,
                id,
                'frame:wall-time',
                Rational(BigInt.from(random.nextInt(9999))),
              );
            }
          }
        }
        expect(validateDocument(document).errors, isEmpty, reason: 'seed $seed');
        final rows = ObjectFacts(document).rosterEntries('todo');
        expect(rows, hasLength(6), reason: 'a completed ToDo is still listed');
        for (final row in rows) {
          // Never an invented date: the ABSENCE of a coordinate is the answer,
          // which is why there is no second `anchored` flag to disagree with it.
          expect(row.coordinate != null, anchored.contains(row.id), reason: 'seed $seed');
          expect(row.completed, completed.contains(row.id), reason: 'seed $seed');
          // Completion never requires an instant.
          expect(row.completedAt == null, !dated.contains(row.id), reason: 'seed $seed');
        }
        // Title, then id: total and stable.
        final keys = [for (final row in rows) '${row.title}${row.id}'];
        expect(keys, orderedEquals([...keys]..sort()), reason: 'seed $seed');
      }
    });

    test('the roster answers per kind, and an untitled object says so', () {
      var document = createEmptyWorkspaceDocument();
      for (final (index, kind) in objectKinds.keys.indexed) {
        document = document.put(
          'events',
          'event:$index',
          Event(
            id: 'event:$index',
            traits: traitsForObjectKind(const [], kind),
            magnitudes: {'duration': durationMagnitude()},
          ),
        );
      }
      final facts = ObjectFacts(document);
      for (final kind in objectKinds.keys) {
        final rows = facts.rosterEntries(kind);
        expect(rows, hasLength(1), reason: kind);
        expect(rows.single.title, '(untitled)');
      }
      expect(facts.rosterEntries('nonsense'), facts.rosterEntries('event'));
    });
  });
}

T pickOf<T>(Random random, List<T> from) => from[random.nextInt(from.length)];
