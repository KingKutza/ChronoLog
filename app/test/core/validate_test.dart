// Validation's spec.
//
// Two properties do most of the work: a generated document earns no refusals,
// and a planted defect earns exactly one. Between them they pin both halves --
// nothing is refused that should not be, and nothing slips through.
//
// The rest of this file is about what NO LONGER refuses: negation, an unknown
// relation type, an unregistered staple kind. Those are the rulings, and a test
// that they are silent is the only thing that keeps them silent.

import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/core/validate.dart';
import 'package:test/test.dart';

import 'corpus.dart';

/// A defect planted into an otherwise valid document, and the one message it
/// must earn. Every row of the reference table is here, plus every invariant.
typedef Plant = (String map, DocumentRecord record, String fragment);

List<Plant> plants(Corpus corpus) {
  final event = corpus.eventIds.first;
  final frame = corpus.frameIds.last;
  final pattern = corpus.patternIds.first;
  return [
    // --- reference integrity, one row of the table each -------------------
    (
      'frames',
      Frame(id: 'frame:p', extra: const {'basis': 'frame:nope'}),
      'references a missing basis',
    ),
    (
      'frames',
      Frame(id: 'frame:p', extra: const {'coordinateDefinition': 'frame:nope'}),
      'references a missing coordinate definition',
    ),
    (
      'frames',
      Frame(
        id: 'frame:p',
        extra: const {
          'law': {'pattern': 'pattern:nope'},
        },
      ),
      'references a missing law pattern',
    ),
    (
      'events',
      Event(
        id: 'event:p',
        magnitudes: {'duration': durationMagnitude('0', 'second', 'frame:nope')},
      ),
      'references a missing magnitude frame',
    ),
    (
      'patterns',
      Pattern(
        id: 'pattern:p',
        language: 'x',
        extra: const {'kind': 'ics-rrule', 'templateEvent': 'event:nope'},
      ),
      'references a missing template event',
    ),
    (
      'patterns',
      Pattern(
        id: 'pattern:p',
        language: 'x',
        extra: {'kind': 'ics-rrule', 'templateEvent': event, 'templateRelation': 'relation:nope'},
      ),
      'references a missing template relation',
    ),
    (
      'overrides',
      Override(id: 'override:p', virtualId: stableVirtualId('pattern:nope', 'k')),
      'references a missing virtual pattern',
    ),
    (
      'overrides',
      Override(
        id: 'override:p',
        virtualId: stableVirtualId(pattern, 'k'),
        replacements: const ['event:nope'],
      ),
      'references a missing replacement event',
    ),
    (
      'relations',
      Relation(
        id: 'relation:p',
        type: 'attachment',
        extra: {'event': 'event:nope', 'frame': frame},
      ),
      'references a missing event',
    ),
    (
      'relations',
      Relation(
        id: 'relation:p',
        type: 'attachment',
        extra: {'event': event, 'frame': 'frame:nope'},
      ),
      'references a missing frame',
    ),
    (
      'relations',
      Relation(
        id: 'relation:p',
        type: 'composition',
        extra: {'parent': 'frame:nope', 'child': frame},
      ),
      'references a missing frame',
    ),
    (
      'relations',
      Relation(
        id: 'relation:p',
        type: 'membership',
        extra: {'group': corpus.groupIds.first, 'member': 'event:nope'},
      ),
      'references a missing member',
    ),
    (
      'relations',
      Relation(id: 'relation:p', type: 'contains', extra: {'parent': 'event:nope', 'child': event}),
      'references a missing parent',
    ),
    (
      'relations',
      Relation(id: 'relation:p', type: 'contains', extra: {'parent': event, 'child': 'event:nope'}),
      'references a missing child',
    ),
    (
      'relations',
      Relation(
        id: 'relation:p',
        type: 'staple',
        extra: {
          'ends': [
            {'frame': 'frame:nope'},
            {'object': event},
          ],
        },
      ),
      'end 1 references a missing frame',
    ),
    (
      'relations',
      Relation(
        id: 'relation:p',
        type: 'staple',
        extra: {
          'ends': [
            {'frame': frame},
            {'object': 'event:nope'},
          ],
        },
      ),
      'end 2 references a missing object',
    ),
    (
      'relations',
      Relation(
        id: 'relation:p',
        type: 'staple',
        extra: {
          'ends': [
            {'frame': frame},
            {'series': 'pattern:nope'},
          ],
        },
      ),
      'end 2 references a missing series',
    ),
    // --- the domain invariants that ride ----------------------------------
    (
      'events',
      Event(
        id: 'event:p',
        traits: const ['event', 'task'],
        magnitudes: {'duration': durationMagnitude('1', 'hour')},
      ),
      'must have zero duration',
    ),
    ('events', const Event(id: 'event:p', traits: ['event']), 'requires an intrinsic duration'),
    (
      'frames',
      Frame(id: 'frame:p', extra: const {'coordinateDefinition': 'frame:p'}),
      'cannot define coordinates through itself',
    ),
    ('patterns', Pattern(id: 'pattern:p', extra: {'templateEvent': event}), 'lacks a language'),
    (
      'relations',
      Relation(id: 'relation:p', type: 'contains', extra: {'parent': event, 'child': event}),
      'makes an object contain itself',
    ),
    (
      'relations',
      Relation(id: 'relation:p', type: 'membership', extra: {'group': frame, 'member': event}),
      'references a missing group',
    ),
    (
      'relations',
      Relation(
        id: 'relation:p',
        type: 'staple',
        extra: {
          'ends': [
            {'frame': frame},
          ],
        },
      ),
      'must connect exactly two things',
    ),
    (
      'relations',
      Relation(
        id: 'relation:p',
        type: 'staple',
        extra: {
          'role': 'member',
          'ends': [
            {'frame': frame},
            {'object': event},
          ],
        },
      ),
      'carries a top-level role',
    ),
    (
      'relations',
      Relation(
        id: 'relation:p',
        type: 'staple',
        extra: {
          'ends': [
            {'object': event, 'point': 'start'},
            {'object': event, 'point': 'end'},
          ],
        },
      ),
      'connects one object to itself',
    ),
    (
      'relations',
      Relation(
        id: 'relation:p',
        type: 'staple',
        extra: {
          'ends': [
            {'frame': frame, 'void': true},
            {'frame': frame, 'void': true},
          ],
        },
      ),
      'connects one point to itself',
    ),
    (
      'relations',
      Relation(
        id: 'relation:p',
        type: 'staple',
        extra: {
          'ends': [
            {'series': pattern},
            {'series': corpus.patternIds.last},
          ],
        },
      ),
      'connects two series',
    ),
    (
      'relations',
      Relation(
        id: 'relation:p',
        type: 'staple',
        extra: {
          'ends': [
            {'frame': frame},
            {'object': event, 'point': '  '},
          ],
        },
      ),
      'point must be a non-empty name',
    ),
  ];
}

/// What must stay silent. Each of these was a refusal in the JavaScript, or
/// would be under a closed vocabulary, and each is now legal data.
List<(String, String, DocumentRecord)> silences(Corpus corpus) {
  final event = corpus.eventIds.first;
  final frame = corpus.frameIds.last;
  return [
    (
      'a frame authoring a NOT term',
      'frames',
      Frame(
        id: 'frame:s',
        extra: const {
          'query': {
            'notGroups': ['group:a'],
            'excludeGroups': ['group:b'],
          },
        },
      ),
    ),
    (
      'a membership authored as an exclusion',
      'relations',
      Relation(
        id: 'relation:s',
        type: 'membership',
        extra: {
          'group': corpus.groupIds.first,
          'member': event,
          'include': false,
          'mode': 'exclude',
        },
      ),
    ),
    (
      'a staple kind no registry knows',
      'relations',
      Relation(
        id: 'relation:s',
        type: 'staple',
        extra: {
          'kind': 'gravitational-lensing',
          'ends': [
            {'object': event, 'point': 'end'},
            {'series': corpus.patternIds.first},
          ],
        },
      ),
    ),
    (
      'a staple with no kind at all',
      'relations',
      Relation(
        id: 'relation:s',
        type: 'staple',
        extra: {
          'ends': [
            {'frame': frame},
            {'object': event},
          ],
        },
      ),
    ),
    (
      'a frame stapled to itself at two different positions',
      'relations',
      Relation(
        id: 'relation:s',
        type: 'staple',
        extra: {
          'kind': 'correspondence',
          'ends': [
            {
              'frame': frame,
              'coordinate': {
                'levels': [
                  {'level': 'year', 'value': '1'},
                ],
              },
            },
            {
              'frame': frame,
              'coordinate': {
                'levels': [
                  {'level': 'year', 'value': '2'},
                ],
              },
            },
          ],
        },
      ),
    ),
  ];
}

void main() {
  test('a generated document earns no refusals, over many graphs', () {
    for (final seed in seeds(60)) {
      final document = Corpus(seed).document();
      expect(validateDocument(document).errors, isEmpty, reason: 'seed $seed');
      expect(validateDocument(document).valid, isTrue);
    }
  });

  test('a planted defect earns exactly one refusal, and it names the record', () {
    for (final seed in seeds(8)) {
      final corpus = Corpus(seed);
      final document = corpus.document();
      for (final (map, record, fragment) in plants(corpus)) {
        final result = validateDocument(document.put(map, record.id, record));
        expect(
          result.errors,
          hasLength(1),
          reason:
              'seed $seed, ${record.id} expecting "$fragment", '
              'got ${result.errors}',
        );
        expect(result.errors.single, contains(fragment), reason: 'seed $seed');
        expect(result.errors.single, contains(record.id), reason: 'seed $seed');
      }
    }
  });

  test('every planted reference defect is found, none is found twice', () {
    // The whole table planted at once: as many refusals as plants, no more.
    final corpus = Corpus();
    var document = corpus.document();
    final rows = plants(corpus).where((p) => p.$3.contains('references a missing'));
    var index = 0;
    for (final (map, record, _) in rows) {
      final id = '${record.id}-${index++}';
      document = document.put(map, id, record.toJson()..['id'] = id);
    }
    expect(validateDocument(document).errors, hasLength(index));
  });

  test('what no longer refuses stays silent', () {
    for (final seed in seeds(8)) {
      final corpus = Corpus(seed);
      final document = corpus.document();
      for (final (label, map, record) in silences(corpus)) {
        expect(
          validateDocument(document.put(map, record.id, record)).errors,
          isEmpty,
          reason: '$label (seed $seed)',
        );
      }
    }
  });

  test('an unknown relation type is never refused, whatever it carries', () {
    final corpus = Corpus();
    final document = corpus.document();
    for (final type in unknownRelationTypes) {
      final relation = Relation(
        id: 'relation:unknown',
        type: type,
        extra: const {
          'lines': ['frame:does-not-exist', 'frame:neither'],
          'terminator': 'attachment:gone',
          'state': 'open',
          'anchors': {
            'anything': ['at', 'all'],
          },
        },
      );
      expect(
        validateDocument(document.put('relations', relation.id, relation)).errors,
        isEmpty,
        reason: type,
      );
    }
  });

  test('a key that disagrees with its record is refused, in every map', () {
    final corpus = Corpus();
    final document = corpus.document();
    final records = <String, DocumentRecord>{
      'frames': const Frame(id: 'frame:real'),
      'events': Event(id: 'event:real', magnitudes: {'duration': durationMagnitude()}),
      'patterns': const Pattern(id: 'pattern:real', language: 'x'),
      'relations': const Relation(id: 'relation:real', type: 'wormhole'),
      'overrides': Override(
        id: 'override:real',
        virtualId: stableVirtualId(corpus.patternIds.first, 'k'),
      ),
    };
    for (final entry in records.entries) {
      final result = validateDocument(document.put(entry.key, 'wrong:key', entry.value));
      expect(result.errors, hasLength(1), reason: entry.key);
      expect(result.errors.single, contains('map key wrong:key does not match'));
    }
  });

  test('the schema is what the JavaScript writes, and nothing else loads', () {
    expect(validateDocument(const Document()).errors, isEmpty);
    expect(validateDocument(const Document(schema: 'chronolog/2')).errors, [
      'Unsupported schema: chronolog/2',
    ]);
    expect(validateDocument(const Document(schema: '')).errors, ['Unsupported schema: (missing)']);
  });

  test('validation reports; it never throws on data', () {
    // Records whose fields are the wrong shape entirely still come back as
    // messages, because a refusal a caller cannot catch is a crash.
    final wrong = Document.fromJson({
      'schema': 'chronolog/1',
      'relations': {
        'relation:odd': {'id': 'relation:odd', 'type': 'staple', 'ends': 'not a list', 'kind': 42},
        'relation:odder': {
          'id': 'relation:odder',
          'type': 'membership',
          'group': 12,
          'member': null,
        },
      },
    });
    expect(validateDocument(wrong).valid, isFalse);
    expect(validateDocument(wrong).errors, isNotEmpty);
  });
}
