// A tiny mutable builder over the immutable [Document], so a test reads as the
// document it authors rather than as a chain of `copyWith`.
//
// Uncounted test support. The frames are the two the honest first run ships plus
// two authored ones: a calendar over wall time, and an INVENTED ladder whose
// atom is a pen stroke -- a law with a real axis of its own and no relation to
// Earth days at all, which is what makes a cross-law correspondence testable.
//
// Nothing here loads a dataset. `tools/load-dataset.js` is not ported, so the
// era chains the spec needs are HAND-BUILT from the same shape the JavaScript
// fixture carries (era frames + succession staples + one pin), stated in the
// test rather than read from a file this build cannot yet open.

import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/core/staples.dart';

/// A nested Gregorian coordinate, at exactly the depth the caller names -- so an
/// omitted level is authored precision, not a zero.
Json civil(int year, [int? month, int? day, int? hour, int? minute, int? second]) => {
  'levels': [
    for (final (name, value) in [
      ('year', year),
      ('month', month),
      ('day', day),
      ('hour', hour),
      ('minute', minute),
      ('second', second),
    ])
      if (value != null) {'level': name, 'value': '$value'},
  ],
};

/// A coordinate in the invented stroke/step ladder.
Json stroke(int stroke, [int step = 0]) => {
  'levels': [
    {'level': 'stroke', 'value': '$stroke'},
    {'level': 'step', 'value': '$step'},
  ],
};

const Json _inventedLaw = {
  'kind': 'nested',
  'levels': [
    {'name': 'stroke'},
    {'name': 'step', 'within': 'stroke', 'radix': '8'},
  ],
};

class World {
  World() {
    final blank = createEmptyWorkspaceDocument(now: DateTime.utc(2026));
    document = blank.copyWith(
      frames: {
        ...blank.frames,
        'calendar:work': const Frame(
          id: 'calendar:work',
          title: 'Work',
          traits: ['set', 'calendar'],
          extra: {'basis': 'frame:wall-time'},
        ),
        'frame:invented': const Frame(
          id: 'frame:invented',
          title: 'A curve of handwriting',
          traits: ['line', 'temporal'],
          extra: {'coordinate': _inventedLaw},
        ),
      },
    );
  }

  late Document document;
  int _minted = 0;

  String _id(String prefix) => '$prefix:${(++_minted).toString().padLeft(3, '0')}';

  Staples get staples => Staples(document);

  /// An object, optionally placed by a plain attachment -- which IS its implicit
  /// start connection.
  String object({
    String duration = '0',
    String unit = 'minute',
    Json? placedAt,
    String frame = 'calendar:work',
  }) {
    final id = _id('event');
    document = document.put(
      'events',
      id,
      Event(
        id: id,
        traits: const ['event'],
        magnitudes: {'duration': durationMagnitude(duration, unit)},
      ),
    );
    if (placedAt != null) {
      final relation = _id('relation');
      document = document.put(
        'relations',
        relation,
        // A placement IS a staple (ruled 2026-09-01): the object's start
        // identified with a point on the frame.
        Relation(
          id: relation,
          type: 'staple',
          extra: {
            'kind': 'anchor',
            'role': 'placed',
            'ends': [
              ObjectEnd(id, point: 'start').toJson(),
              FrameEnd(frame, position: Position.coordinate(placedAt)).toJson(),
            ],
          },
        ),
      );
    }
    return id;
  }

  String pattern({Json rrule = const {'FREQ': 'WEEKLY'}, Json? templateAt}) {
    final id = _id('pattern');
    // The template placement is DERIVED from the template EVENT now, so the
    // pattern needs an event to derive from rather than a relation id to store.
    String? templateEvent;
    if (templateAt != null) {
      templateEvent = _id('event');
      document = document.put(
        'events',
        templateEvent,
        Event(id: templateEvent, traits: const ['event'], payload: const {'title': 'Template'}),
      );
      final template = _id('relation');
      document = document.put(
        'relations',
        template,
        Relation(
          id: template,
          type: 'staple',
          extra: {
            'kind': 'anchor',
            'role': 'template',
            'ends': [
              ObjectEnd(templateEvent, point: 'start').toJson(),
              FrameEnd('calendar:work', position: Position.coordinate(templateAt)).toJson(),
            ],
          },
        ),
      );
    }
    document = document.put(
      'patterns',
      id,
      Pattern(
        id: id,
        language: 'ics',
        extra: {
          'kind': 'ics-rrule',
          'rrule': rrule,
          'templateEvent': ?templateEvent,
          'frame': 'calendar:work',
        },
      ),
    );
    return id;
  }

  /// A staple, ends IN ORDER. No gate anywhere asks which two things they are.
  Relation staple({
    String? kind,
    required List<StapleEnd> ends,
    Spread? spread,
    Json extra = const {},
    String? id,
  }) {
    final placed = putStaple(
      document,
      id: id ?? _id('relation'),
      kind: kind,
      ends: ends,
      spread: spread,
      extra: extra,
    );
    document = placed.document;
    return placed.staple;
  }

  /// An era frame plus the succession staple joining it to its predecessor. The
  /// ends are `[predecessor, this]`: DIRECTION IS THE ORDER, and no `role` field
  /// appears anywhere in this builder.
  void era(
    String id, {
    required String key,
    String? name,
    String direction = 'ascending',
    Object? years = 'open',
    String firstYear = '1',
    String? affix,
    Json? anchor,
    bool countable = true,
    String? after,
    bool reversedEnds = false,
  }) {
    // An era's NAME and its stored KEY must be distinct tokens -- a table where
    // one era answers to the same word twice is refused -- so a caller that
    // names only a key gets a label derived from it.
    final label = name ?? 'The $key era';
    document = document.put(
      'frames',
      id,
      Frame(
        id: id,
        title: label,
        traits: const ['line', 'temporal', 'era'],
        extra: {
          if (countable) 'basis': 'frame:wall-time',
          'era': {
            'key': key,
            'name': label,
            if (!countable) 'countable': false,
            if (countable) 'direction': direction,
            if (countable) 'years': years,
            if (countable) 'firstYear': firstYear,
            'affix': ?affix,
            'anchor': ?anchor,
          },
        },
      ),
    );
    if (after != null) succeed(after, id, reversed: reversedEnds);
  }

  Relation succeed(String from, String to, {bool reversed = false}) => staple(
    kind: 'succession',
    ends: reversed
        ? [StapleEnd.frame(to), StapleEnd.frame(from)]
        : [StapleEnd.frame(from), StapleEnd.frame(to)],
  );

  void remove(String map, String id) => document = document.remove(map, id);
}
