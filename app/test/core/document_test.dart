// The document's spec: the first run, the one virtual-id derivation, the one
// cascade sweep, staple placement, and the dedupe-merge.

import 'dart:convert';

import 'package:chronolog/core/coordinate_law.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/ops.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/core/validate.dart';
import 'package:test/test.dart';

import 'corpus.dart';

void main() {
  group('the honest first run', () {
    test('is two structural frames and nothing else at all', () {
      final document = createEmptyWorkspaceDocument();
      // RULED ANCHOR (no phantom frames): the two frames a workspace cannot
      // function without, and zero seeded calendars, groups, events, patterns,
      // relations or overrides.
      expect(document.frames.keys.toSet(), {'measure:human-time', 'frame:wall-time'});
      expect(document.events, isEmpty);
      expect(document.patterns, isEmpty);
      expect(document.relations, isEmpty);
      expect(document.overrides, isEmpty);
      expect(validateDocument(document).errors, isEmpty);
    });

    test('writes no phantom record either', () {
      final text = jsonEncode(createEmptyWorkspaceDocument().toJson());
      for (final phantom in ['calendar:', 'group:', 'pattern:', 'event:']) {
        expect(text, isNot(contains(phantom)), reason: phantom);
      }
      expect(jsonDecode(text), isA<Map>().having((m) => m['schema'], 'schema', 'chronolog/1'));
    });

    test('ships the registered declarations rather than a hand-copied subset', () {
      final document = createEmptyWorkspaceDocument();
      final wall = document.frames['frame:wall-time']!.coordinate!;
      expect(wall['kind'], 'gregorian');
      // The weekday is a CYCLE, not a ladder level: seven days repeat across
      // month and year boundaries with no regard for either.
      final cycles = wall['cycles'] as List;
      expect(cycles.single, containsPair('name', 'weekday'));
      expect((wall['levels'] as List).map((l) => (l as Map)['name']), isNot(contains('weekday')));
      final measure = document.frames['measure:human-time']!.coordinate!;
      expect(measure['kind'], 'nested');
    });

    test('carries a created and a modified stamp that touch moves', () {
      final document = createEmptyWorkspaceDocument(now: DateTime.utc(2026, 8, 27));
      expect(document.meta['created'], '2026-08-27T00:00:00.000Z');
      expect(document.meta['modified'], '2026-08-27T00:00:00.000Z');
      final bumped = touch(document, at: DateTime.utc(2027));
      expect(bumped.meta['created'], document.meta['created']);
      expect(bumped.meta['modified'], '2027-01-01T00:00:00.000Z');
    });
  });

  group('ids', () {
    test('are prefixed UUIDv4s, distinct across a large draw', () {
      final minted = {for (var i = 0; i < 5000; i++) createId('frame')};
      expect(minted.length, 5000);
      final pattern = RegExp(
        r'^frame:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      expect(minted.every(pattern.hasMatch), isTrue);
    });
  });

  group('the one virtual-id derivation', () {
    test('splits at the last slash for every hostile key', () {
      for (final patternId in ['pattern:standing', 'pattern/with/slashes', 'p']) {
        for (final key in hostileKeys) {
          final virtual = stableVirtualId(patternId, key);
          expect(virtualPatternId(virtual), patternId, reason: '$patternId + $key');
          final encoded = virtual.substring(patternId.length + 1);
          expect(Uri.decodeComponent(encoded), key, reason: '$patternId + $key');
        }
      }
    });

    test('distinct keys never collide, however hostile', () {
      final ids = {for (final key in hostileKeys) stableVirtualId('p', key)};
      expect(ids.length, hostileKeys.length);
    });

    test('an override and a bare string are read the same way', () {
      final virtual = stableVirtualId('pattern:standing', 'a/b');
      expect(overridePatternId(Override(id: 'o', virtualId: virtual)), 'pattern:standing');
      expect(virtualPatternId(''), '');
      expect(virtualPatternId(null), '');
      expect(overridePatternId(null), '');
      expect(overridePatternId(const Override(id: 'o')), '');
    });
  });

  group('suppression', () {
    test('removes exactly the suppressed occurrences, by virtual id', () {
      for (final seed in seeds(20)) {
        final document = Corpus(seed).document();
        final suppressed = document.overrides.values
            .where((override) => override.suppress)
            .map((override) => override.virtualId)
            .toSet();
        final generated = [...suppressed, 'pattern:x/never-suppressed'];
        final kept = applyVirtualOverrides(document, generated, (id) => id);
        expect(kept, ['pattern:x/never-suppressed'], reason: 'seed $seed');
      }
    });

    test('suppressing writes one override and bumps modified', () {
      final document = createEmptyWorkspaceDocument(now: DateTime.utc(2026));
      final result = suppressVirtual(
        document,
        stableVirtualId('pattern:p', '2026-01-12T09:00:00'),
        replacements: const ['event:moved'],
        id: 'override:one',
      );
      expect(result.document.overrides.keys, ['override:one']);
      expect(result.override.suppress, isTrue);
      expect(result.override.replacements, ['event:moved']);
      expect(result.document.meta['modified'], isNot(document.meta['modified']));
    });
  });

  group('the one cascade sweep', () {
    /// The closure computed a second way -- from the raw JSON rather than from
    /// the predicates under test -- so the two have to agree.
    Set<String> doomedRelations(Document document, Set<String> ids) {
      final doomed = <String>{};
      for (final entry in document.relations.entries) {
        final json = entry.value.toJson();
        final type = json['type'];
        final ends = (json['ends'] as List?) ?? const [];
        final touched = switch (type) {
          'staple' => ends.any(
            (end) => ids.contains((end as Map)['frame'] ?? end['object'] ?? end['series']),
          ),
          'contains' => ids.contains(json['parent']) || ids.contains(json['child']),
          'membership' => ids.contains(json['member']),
          _ => false,
        };
        if (touched) doomed.add(entry.key);
      }
      return doomed;
    }

    test('removes exactly the reachable closure and nothing else', () {
      for (final seed in seeds(30)) {
        final corpus = Corpus(seed);
        final document = corpus.document();
        final ids = corpus.eventIds.take(2).toSet();
        final expected = doomedRelations(document, ids);

        var swept = document;
        var removed = 0;
        for (final doomed in [
          staplesTouching(ids),
          containmentsTouching(ids),
          membershipsOf(ids),
        ]) {
          final result = sweep(swept, 'relations', doomed);
          swept = result.document;
          removed += result.removed;
        }
        expect(removed, expected.length, reason: 'seed $seed');
        expect(
          document.relations.keys.toSet().difference(swept.relations.keys.toSet()),
          expected,
          reason: 'seed $seed',
        );
        // Nothing outside the swept map moved.
        expect(swept.events, document.events);
        expect(swept.frames, document.frames);
      }
    });

    test('an override belongs to its pattern and travels with it', () {
      for (final seed in seeds(20)) {
        final corpus = Corpus(seed);
        final document = corpus.document();
        final doomedPattern = corpus.patternIds.first;
        final expected = document.overrides.entries
            .where((entry) => overridePatternId(entry.value) == doomedPattern)
            .map((entry) => entry.key)
            .toSet();
        final result = sweep(document, 'overrides', overridesOfPatterns({doomedPattern}));
        expect(result.removed, expected.length, reason: 'seed $seed');
        expect(
          result.document.overrides.keys.toSet(),
          document.overrides.keys.toSet().difference(expected),
        );
        // A pattern's deletion takes its staples too -- same invariant, same
        // sweep, one more predicate -- and the document still loads.
        final staples = sweep(result.document, 'relations', staplesTouching({doomedPattern}));
        expect(
          validateDocument(staples.document.remove('patterns', doomedPattern)).errors,
          isEmpty,
          reason: 'seed $seed',
        );
      }
    });

    test('a sweep that removes nothing returns the identical document', () {
      final document = Corpus().document();
      final result = sweep(document, 'relations', (_) => false);
      expect(identical(result.document, document), isTrue);
      expect(result.removed, 0);
      // Which is what keeps the op diff silent.
      expect(opsFromMaps(mapSnapshot(document), mapSnapshot(result.document)), isEmpty);
    });
  });

  group('staples', () {
    test('are placed as whole records, added by default and updated by id', () {
      var document = createEmptyWorkspaceDocument();
      final placed = putStaple(
        document,
        kind: 'correspondence',
        ends: [
          StapleEnd.frame('frame:wall-time', position: const Position.coordinate({'levels': []})),
          const StapleEnd.frame('measure:human-time', position: Position.authoredVoid()),
        ],
      );
      document = placed.document;
      expect(document.relations.length, 1);
      expect(placed.staple.kind, 'correspondence');
      expect(placed.staple.ends.length, 2);

      // Adding again ADDS: the collection is open.
      document = putStaple(document, kind: 'anchor', ends: placed.staple.ends).document;
      expect(document.relations.length, 2);

      // Re-placing by id REPLACES the whole record: no field survives that the
      // new record does not name.
      final replaced = putStaple(
        document,
        id: placed.staple.id,
        ends: [const StapleEnd.series('pattern:p')],
      );
      expect(replaced.staple.kind, isNull);
      expect(replaced.staple.ends.length, 1);
      expect(replaced.document.relations.length, 2);

      expect(removeStaple(replaced.document, placed.staple.id).relations.length, 1);
      // Removing something that is not a staple is not a change.
      final untouched = removeStaple(replaced.document, 'relation:nothing');
      expect(identical(untouched, replaced.document), isTrue);
    });

    test('a staple is two ends IN ORDER, which is the whole of its direction', () {
      final forward = putStaple(
        const Document(),
        ends: [
          const StapleEnd.object('event:a', point: 'end'),
          const StapleEnd.object('event:b'),
        ],
      ).staple;
      expect(forward.ends.map((end) => end.id).toList(), ['event:a', 'event:b']);
      // No scope pair is refused: an object may be stapled to a series, a frame
      // to a frame, an object to an object.
      expect(forward.extra.containsKey('connects'), isFalse);
      expect(forward.extra.keys, containsAll(['ends']));
    });

    test('staplesFor needs a selector and answers in a stable total order', () {
      for (final seed in seeds(10)) {
        final corpus = Corpus(seed);
        final document = corpus.document();
        expect(staplesFor(document), isEmpty);
        for (final id in [...corpus.eventIds, ...corpus.patternIds]) {
          final found = staplesFor(document, object: id);
          expect(
            found.map((staple) => staple.id).toList(),
            found.map((staple) => staple.id).toList()..sort(),
            reason: 'seed $seed',
          );
          for (final staple in found) {
            expect(staple.ends.any((end) => end.id == id), isTrue);
          }
        }
      }
    });
  });

  group('the dedupe-merge', () {
    test('rewrites every referrer and keeps every merged payload', () {
      var document = createEmptyWorkspaceDocument();
      for (final id in ['event:a', 'event:b', 'event:c']) {
        document = document.put(
          'events',
          id,
          Event(
            id: id,
            traits: const ['event'],
            magnitudes: {'duration': durationMagnitude()},
            payload: {'title': id},
            extra: {
              'foreign': {'uid': '$id@example.test'},
            },
          ),
        );
      }
      document = document
          .put(
            'relations',
            'attachment:b',
            const Relation(
              id: 'attachment:b',
              type: 'attachment',
              extra: {'event': 'event:b', 'frame': 'frame:wall-time', 'role': 'observed'},
            ),
          )
          .put(
            'patterns',
            'pattern:p',
            const Pattern(
              id: 'pattern:p',
              language: 'chronolog-ics/1',
              extra: {'kind': 'ics-rrule', 'templateEvent': 'event:c'},
            ),
          )
          .put(
            'overrides',
            'override:o',
            Override(
              id: 'override:o',
              virtualId: stableVirtualId('pattern:p', 'k'),
              suppress: true,
              replacements: const ['event:b', 'event:a'],
            ),
          );

      final merged = stapleEvents(document, ['event:a', 'event:b', 'event:c']);
      final result = merged.document;
      expect(result.events.keys, ['event:a']);
      expect(merged.canonical!.id, 'event:a');
      expect(result.relations['attachment:b']!.event, 'event:a');
      expect(result.patterns['pattern:p']!.templateEvent, 'event:a');
      expect(result.overrides['override:o']!.replacements, ['event:a', 'event:a']);

      final stapled = (result.events['event:a']!.extra['foreign'] as Json)['stapled'] as List;
      expect(stapled.map((entry) => (entry as Map)['id']).toList(), ['event:b', 'event:c']);
      expect((stapled.first as Map)['payload'], {'title': 'event:b'});
      expect(((stapled.first as Map)['foreign'] as Map)['uid'], 'event:b@example.test');
      expect(validateDocument(result).errors, isEmpty);
    });

    test('fewer than two ids is not a merge', () {
      final document = Corpus().document();
      expect(identical(stapleEvents(document, const []).document, document), isTrue);
      expect(stapleEvents(document, const []).canonical, isNull);
      final one = document.events.keys.first;
      final single = stapleEvents(document, [one, 'event:not-here']);
      expect(identical(single.document, document), isTrue);
      expect(single.canonical!.id, one);
    });

    test('a merge leaves the document loadable and diffs to its own records', () {
      for (final seed in seeds(20)) {
        final corpus = Corpus(seed);
        final document = corpus.document();
        final before = mapSnapshot(document);
        final merged = stapleEvents(document, corpus.eventIds.take(3)).document;
        expect(validateDocument(merged).errors, isEmpty, reason: 'seed $seed');
        final ops = opsFromMaps(before, mapSnapshot(merged));
        // The two merged events vanish, and so does any connection that
        // collapsed to one thing joined to itself.
        expect(
          ops.where((op) => op.op == 'del' && op.map == 'events').map((op) => op.id).toSet(),
          corpus.eventIds.skip(1).take(2).toSet(),
          reason: 'seed $seed',
        );
        // No surviving record still names a merged-away id.
        expect(
          jsonEncode(merged.toJson()),
          isNot(anyOf(corpus.eventIds.skip(1).take(2).map(contains))),
          reason: 'seed $seed',
        );
      }
    });
  });

  group('duration', () {
    test('a magnitude reads its own levels, and zero is a fact', () {
      // Read back through the coordinate-law layer's own type: there is only
      // one coordinate shape, and a magnitude's value is in it.
      expect(durationMagnitude().coordinate, Coordinate.of(const [('second', '0')]));
      expect(durationMagnitude('90', 'minute').frame, 'measure:human-time');
      expect(isZeroDuration(Event(id: 'e', magnitudes: {'duration': durationMagnitude()})), isTrue);
      expect(
        isZeroDuration(Event(id: 'e', magnitudes: {'duration': durationMagnitude('1', 'hour')})),
        isFalse,
      );
      // A malformed level counts as nothing rather than throwing.
      expect(
        isZeroDuration(Event(id: 'e', magnitudes: {'duration': durationMagnitude('not-a-number')})),
        isTrue,
      );
      expect(isZeroDuration(null), isTrue);
      expect(isZeroDuration(const Event(id: 'e')), isTrue);
    });

    test('incidence is the count of an object\'s attachments', () {
      for (final seed in seeds(10)) {
        final corpus = Corpus(seed);
        final document = corpus.document();
        for (final id in corpus.eventIds) {
          final found = eventRelations(document, id);
          expect(found.every((relation) => relation.type == 'attachment'), isTrue);
          expect(
            found.length,
            document.relations.values.where((r) => r.type == 'attachment' && r.event == id).length,
          );
        }
      }
    });
  });
}
