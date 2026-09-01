// Seeded random record graphs.
//
// The spec tests PROPERTIES over generated documents, not pinned facts. A
// property that holds for forty random record graphs says something a hand-built
// fixture cannot, and it does not have to be rewritten every time the vocabulary
// grows -- which it will, because the vocabulary is open by ruling.
//
// Generation is seeded from [specSeed] so a failure is reproducible, and every
// generated document is VALID by construction: the properties about validation
// plant their own defects and then count them.

import 'dart:math';

import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/records.dart';

/// The spec's seed. Derived seeds are `specSeed + i`, so a failing iteration
/// names the exact document that produced it.
const int specSeed = 20260827;

List<int> seeds(int count) => [for (var i = 0; i < count; i++) specSeed + i];

/// Relation types this build carries no validator for. The first four are the
/// time-travel taxonomy, whose hardcoded validators died as written; the rest are
/// invented on the spot. Every one of them must load, validate clean, and save
/// back byte for byte -- an unknown type is data, never a refusal.
const List<String> unknownRelationTypes = [
  // THE FOUR RETIRED KINDS (ruled 2026-09-01). They are unknown types now, and
  // that is not a demotion but the whole claim: a prior prebuild's records load,
  // validate clean and round-trip byte for byte, and no reader assigns them
  // meaning.
  'attachment',
  'membership',
  'contains',
  'composition',
  'shared-segment',
  'termination',
  'displacement',
  'coordinate-mapping',
  'wormhole',
  'ruled-by',
  'ᚱᚢᚾᛖ-relation',
];

/// Occurrence keys chosen to be hostile to the virtual-id boundary: slashes,
/// percent signs, quotes, spaces, astral characters.
const List<String> hostileKeys = [
  '2026-01-12T09:00:00',
  'a/b',
  'a//b/',
  '100%/sure',
  'ключ/значение',
  '日/本',
  '☃/☃',
  '🌍/🌎',
  'has "quotes" and \\ backslash',
  ' leading and trailing ',
  '',
];

/// A coordinate-law declaration, held here only as nested JSON to be preserved.
/// The corpus makes no claim about what it means; that is the law layer's.
const Json _declaration = {
  'kind': 'nested',
  'levels': [
    {'name': 'age'},
    {'name': 'sky-day', 'within': 'age', 'radix': '400'},
  ],
  'cycles': [
    {
      'name': 'tide',
      'radix': '3',
      'offset': '0',
      'names': ['ebb', 'slack', 'flood'],
    },
  ],
};

const Json _coordinate = {
  'levels': [
    {'level': 'year', 'value': '2026'},
    {'level': 'month', 'value': '8'},
    {'level': 'day', 'value': '27'},
  ],
};

class Corpus {
  Corpus([int seed = specSeed]) : random = Random(seed);

  final Random random;
  int _minted = 0;

  String mint(String prefix) => '$prefix:${_minted++}';

  T pick<T>(List<T> from) => from[random.nextInt(from.length)];

  bool get coin => random.nextBool();

  /// A field name and value this build has never heard of. Sprinkled into
  /// records so preservation is tested on real records rather than in isolation.
  Json unknownFields() => coin
      ? const {}
      : {
          'x-authored-by': 'the corpus',
          'nested': {
            'deep': [
              1,
              'two',
              null,
              true,
              {'deeper': '3'},
            ],
          },
        };

  final List<String> frameIds = ['frame:wall-time', 'measure:human-time'];
  final List<String> groupIds = [];
  final List<String> eventIds = [];
  final List<String> patternIds = [];
  final List<String> relationIds = [];

  /// A valid document with the shapes the model core actually has to carry:
  /// frames that are groups and frames that are lines, objects that are tasks
  /// and objects that are not, staples over every end form, patterns, overrides,
  /// and unknown relation types mixed in among the known ones.
  Document document({
    int frames = 4,
    int events = 6,
    int patterns = 2,
    int relations = 14,
    int overrides = 3,
  }) {
    var document = createEmptyWorkspaceDocument(now: DateTime.utc(2026, 8, 27));
    for (var index = 0; index < frames; index++) {
      final id = mint('frame');
      final group = index.isEven;
      document = document.put(
        'frames',
        id,
        Frame(
          id: id,
          title: 'Frame $index',
          traits: group
              ? ['set', 'group']
              : [
                  'line',
                  'temporal',
                  pick(['calendar', 'timeline']),
                ],
          extra: {
            if (coin) 'basis': pick(frameIds),
            if (!group && coin) 'coordinate': _declaration,
            ...unknownFields(),
          },
        ),
      );
      frameIds.add(id);
      if (group) groupIds.add(id);
    }
    for (var index = 0; index < events; index++) {
      final id = mint('event');
      final task = index % 3 == 0;
      document = document.put(
        'events',
        id,
        Event(
          id: id,
          traits: task ? ['event', 'task'] : ['event'],
          magnitudes: {
            'duration': task
                ? durationMagnitude()
                : durationMagnitude('${random.nextInt(180)}', 'minute'),
          },
          payload: {'title': 'Object $index'},
          extra: unknownFields(),
        ),
      );
      eventIds.add(id);
    }
    for (var index = 0; index < patterns; index++) {
      final id = mint('pattern');
      document = document.put(
        'patterns',
        id,
        Pattern(
          id: id,
          language: 'chronolog-ics/1',
          extra: {
            'kind': 'ics-rrule',
            'templateEvent': pick(eventIds),
            'rrule': {'FREQ': 'WEEKLY', 'INTERVAL': '2'},
            ...unknownFields(),
          },
        ),
      );
      patternIds.add(id);
    }
    for (var index = 0; index < relations; index++) {
      final relation = _relation(index);
      document = document.put('relations', relation.id, relation);
      relationIds.add(relation.id);
    }
    for (var index = 0; index < overrides; index++) {
      final id = mint('override');
      document = document.put(
        'overrides',
        id,
        Override(
          id: id,
          virtualId: stableVirtualId(pick(patternIds), pick(hostileKeys)),
          suppress: true,
          replacements: coin ? [pick(eventIds)] : const [],
          extra: unknownFields(),
        ),
      );
    }
    return document;
  }

  /// ONE SHAPE (Don, ruled 2026-09-01). Every connection the corpus draws is a
  /// staple; the four retired record kinds are drawn too -- from
  /// [unknownRelationTypes], where they now belong -- so the corpus keeps
  /// proving the property that matters about them: they load, they validate
  /// clean, and they save back byte for byte while nothing reads them.
  Relation _relation(int index) {
    final id = mint('relation');
    return switch (index % 6) {
      // A PLACEMENT: an object's start identified with a point on a frame.
      // Always retrospective, so a generated task placement on a calendar frame
      // is valid whichever pair the draw produced.
      0 => Relation(
        id: id,
        type: 'staple',
        extra: {
          'kind': 'anchor',
          'role': 'observed',
          'ends': [
            ObjectEnd(pick(eventIds), point: 'start').toJson(),
            FrameEnd(pick(frameIds), position: Position.coordinate(_coordinate)).toJson(),
          ],
          ...unknownFields(),
        },
      ),
      // FRAME TO FRAME, no point on either: two sheets in one pile.
      1 => _twoFrames(id),
      // AFFILIATION: the whole of an object on a sheet, nothing about where.
      2 => Relation(
        id: id,
        type: 'staple',
        extra: {
          'role': 'member',
          'ends': [ObjectEnd(pick(eventIds)).toJson(), StapleEnd.frame(pick(groupIds)).toJson()],
        },
      ),
      3 => _contains(id),
      4 => staple(id),
      _ => Relation(
        id: id,
        type: pick(unknownRelationTypes),
        extra: {
          'lines': [pick(frameIds), pick(frameIds)],
          'traveler': pick(frameIds),
          'properDirection': 'sideways',
          'state': 'undecided',
          ...unknownFields(),
        },
      ),
    };
  }

  /// Two DISTINCT sheets in one pile: neither end names a point, so nothing on
  /// either projects onto the other. Distinct because a staple joining one point
  /// to itself says nothing and is refused.
  Relation _twoFrames(String id) {
    final first = pick(frameIds);
    final second = pick(frameIds.where((f) => f != first).toList());
    return Relation(
      id: id,
      type: 'staple',
      extra: {
        'ends': [StapleEnd.frame(first).toJson(), StapleEnd.frame(second).toJson()],
      },
    );
  }

  /// CONTAINMENT: object ends alone, both silent -- "all of this is all of
  /// that" -- with authored order the one carrier of held-by.
  Relation _contains(String id) {
    final parent = pick(eventIds);
    final child = pick(eventIds.where((e) => e != parent).toList());
    return Relation(
      id: id,
      type: 'staple',
      extra: {
        'ends': [ObjectEnd(child).toJson(), ObjectEnd(parent).toJson()],
      },
    );
  }

  /// A staple whose two ends are distinct things, over the whole end and
  /// position vocabulary. `kind` is drawn from a list that includes a name no
  /// registry knows, because a kind is open data here.
  Relation staple(String id) {
    final first = end();
    var second = end();
    while (second.id == first.id || (first is SeriesEnd && second is SeriesEnd)) {
      second = end();
    }
    return Relation(
      id: id,
      type: 'staple',
      extra: {
        'kind': pick(['end', 'anchor', 'correspondence', 'phase', 'invented']),
        'ends': [first.toJson(), second.toJson()],
        if (coin)
          'spread': const Spread(
            before: Magnitude(
              frame: 'measure:human-time',
              value: {
                'levels': [
                  {'level': 'hour', 'value': '2'},
                ],
              },
            ),
          ).toJson(),
      },
    );
  }

  StapleEnd end() => switch (random.nextInt(6)) {
    0 => StapleEnd.frame(pick(frameIds), position: Position.coordinate(_coordinate)),
    1 => StapleEnd.frame(
      pick(frameIds),
      position: const Position.selector({'cycle': 'weekday', 'value': 'Tuesday'}),
    ),
    2 => StapleEnd.frame(
      pick(frameIds),
      position: const Position.span({
        'from': {
          'levels': [
            {'level': 'year', 'value': '2026'},
          ],
        },
        'to': {
          'levels': [
            {'level': 'year', 'value': '2027'},
          ],
        },
      }),
    ),
    3 => StapleEnd.frame(pick(frameIds), position: const Position.authoredVoid()),
    4 => StapleEnd.object(
      pick(eventIds),
      point: pick(['start', 'end', 'midpoint', 'the bit I care about']),
    ),
    _ =>
      patternIds.isEmpty
          ? StapleEnd.object(pick(eventIds), point: 'start')
          : StapleEnd.series(pick(patternIds)),
  };
}
