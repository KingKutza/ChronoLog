// A tiny mutable builder over the immutable [Document], so a projection spec
// reads as the document it authors rather than as a chain of `copyWith`.
//
// Uncounted test support. Nothing here decides behaviour: every derivation the
// spec asserts is restated in the spec itself, from the ruling text, so agreement
// between the two means something.

import 'package:chronolog/core/coordinate_law.dart' show gregorianDeclarationJson;
import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/records.dart';

/// A nested Gregorian coordinate, at exactly the depth the caller names -- so an
/// omitted level is authored precision, not a zero.
Json civil(int year, [int? month, int? day, int? hour, int? minute]) => {
  'levels': [
    for (final (name, value) in [
      ('year', year),
      ('month', month),
      ('day', day),
      ('hour', hour),
      ('minute', minute),
    ])
      if (value != null) {'level': name, 'value': '$value'},
  ],
};

/// A coordinate in an invented ladder whose atom is a pen stroke: a real axis of
/// its own, with no relation to Earth days at all.
Json stroke(int stroke, [int step = 0]) => {
  'levels': [
    {'level': 'stroke', 'value': '$stroke'},
    {'level': 'step', 'value': '$step'},
  ],
};

const Json inventedLaw = {
  'kind': 'nested',
  'levels': [
    {'name': 'stroke'},
    {'name': 'step', 'within': 'stroke', 'radix': '8'},
  ],
};

class Scene {
  Scene() {
    document = createEmptyWorkspaceDocument(now: DateTime.utc(2026, 8, 27));
  }

  late Document document;
  int _minted = 0;

  String mint(String prefix) => '$prefix:${(++_minted).toString().padLeft(3, '0')}';

  void frame(String id, List<String> traits, [Json extra = const {}]) =>
      document = document.put('frames', id, Frame(id: id, title: id, traits: traits, extra: extra));

  /// A calendar over wall time. `hoursPerDay` edits the ladder so the frame's
  /// own day is not 24 standard hours, which is what makes "each member resolves
  /// under its OWN law" testable rather than asserted.
  void calendar(String id, {int? hoursPerDay, Object? weight}) {
    final declaration = Json.from(gregorianDeclarationJson);
    if (hoursPerDay != null) {
      declaration['levels'] = [
        for (final level in declaration['levels'] as List)
          if ((level as Map)['name'] == 'hour') {...level, 'radix': '$hoursPerDay'} else level,
      ];
    }
    frame(
      id,
      const ['set', 'calendar'],
      {
        if (hoursPerDay == null) 'basis': 'frame:wall-time' else 'coordinate': declaration,
        if (weight != null) 'display': {'weight': weight},
      },
    );
  }

  void group(
    String id,
    List<String> members, {
    List<String> traits = const ['set', 'group'],
    Json extra = const {},
    Object? weight,
  }) {
    frame(id, traits, {
      ...extra,
      if (weight != null) 'display': {'weight': weight},
    });
    for (final member in members) {
      join(id, member);
    }
  }

  String join(String group, String member) {
    final id = mint('relation');
    document = document.put(
      'relations',
      id,
      Relation(id: id, type: 'membership', extra: {'group': group, 'member': member}),
    );
    return id;
  }

  String object({String title = 'Object', String duration = '30', String unit = 'minute'}) {
    final id = mint('event');
    document = document.put(
      'events',
      id,
      Event(
        id: id,
        traits: const ['event'],
        magnitudes: {'duration': durationMagnitude(duration, unit)},
        payload: {'title': title},
      ),
    );
    return id;
  }

  /// Places an existing object, or mints one and places it. The relation id comes
  /// back, because dedupe identity is the RELATION.
  String place(String frameId, Json at, {String? event, String title = 'Object'}) {
    final objectId = event ?? object(title: title);
    final id = mint('relation');
    document = document.put(
      'relations',
      id,
      Relation(
        id: id,
        type: 'attachment',
        extra: {'event': objectId, 'frame': frameId, 'role': 'placed', 'coordinate': at},
      ),
    );
    return id;
  }

  /// An ICS-RRULE series: template event, template placement, pattern.
  String series(
    String frameId,
    Json rrule, {
    required Json at,
    String duration = '60',
    List<String>? appliesTo,
  }) {
    final templateEvent = object(title: 'Standing', duration: duration);
    final templateRelation = mint('relation');
    document = document.put(
      'relations',
      templateRelation,
      Relation(
        id: templateRelation,
        type: 'attachment',
        extra: {'event': templateEvent, 'frame': frameId, 'role': 'template', 'coordinate': at},
      ),
    );
    final id = mint('pattern');
    document = document.put(
      'patterns',
      id,
      Pattern(
        id: id,
        language: 'chronolog-ics/1',
        extra: {
          'kind': 'ics-rrule',
          'templateEvent': templateEvent,
          'templateRelation': templateRelation,
          'rrule': rrule,
          'frame': frameId,
          'appliesTo': ?appliesTo,
        },
      ),
    );
    return id;
  }

  Relation staple({String? kind, required List<StapleEnd> ends, Json extra = const {}}) {
    final placed = putStaple(document, id: mint('relation'), kind: kind, ends: ends, extra: extra);
    document = placed.document;
    return placed.staple;
  }
}
