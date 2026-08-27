// The document: how one is made, how it is changed, and the derivations every
// consumer must share rather than re-invent.
//
// Every function here takes a document and returns a document. Nothing mutates
// in place, so "what did this edit touch" is answerable by identity (see
// `opsFromMaps` in ops.dart) rather than by a bundle the caller hand-collected.

import 'dart:convert';
import 'dart:math';

import 'coordinate_law.dart' show gregorianDeclarationJson;
import 'exact.dart';
import 'records.dart';

final Random _entropy = Random.secure();

/// A plain UUIDv4, prefixed. The JavaScript's three-deep feature-detection
/// ladder (browsers with `crypto.randomUUID`, browsers with `getRandomValues`,
/// browsers with neither) has no counterpart here and is not ported.
String createId([String prefix = 'item']) {
  final bytes = List<int>.generate(16, (_) => _entropy.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '$prefix:${hex.substring(0, 8)}-${hex.substring(8, 12)}'
      '-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

String _stamp(DateTime? now) => (now ?? DateTime.now().toUtc()).toUtc().toIso8601String();

Document createDocument({String title = 'Untitled Chronolog', DateTime? now}) {
  final stamp = _stamp(now);
  return Document(meta: {'title': title, 'created': stamp, 'modified': stamp});
}

const Json _humanTimeDeclaration = {
  'kind': 'nested',
  'levels': [
    {'name': 'year'},
    {'name': 'day', 'within': 'year', 'transition': 'gregorian.daysInYear'},
    {'name': 'hour', 'within': 'day', 'radix': '24'},
    {'name': 'minute', 'within': 'hour', 'radix': '60'},
    {'name': 'second', 'within': 'minute', 'radix': '60'},
    {'name': 'subsecond', 'within': 'second'},
  ],
};

/// Wall time ships the REGISTERED Gregorian declaration -- the coordinate-law
/// layer's own constant, not a hand-copied subset of it -- because the ladder,
/// the month names and the weekday cycle are what the minimap and the day
/// headers read, and putting them in the declaration is what makes them editable
/// at all.
///
/// The honest first run. Two structural frames a workspace cannot function
/// without -- a nested human-time magnitude frame that durations and other
/// measures are read in, and the Gregorian wall-time frame every calendar and
/// attachment hangs off -- and ZERO seeded calendars, groups, events or
/// patterns. Those are authored by the user, never seeded, so nothing renders or
/// is written that the user did not put there.
Document createEmptyWorkspaceDocument({String title = 'Untitled Chronolog', DateTime? now}) =>
    createDocument(title: title, now: now).copyWith(
      frames: const {
        'measure:human-time': Frame(
          id: 'measure:human-time',
          title: 'Human time magnitude',
          traits: ['line', 'measure', 'duration'],
          extra: {'coordinate': _humanTimeDeclaration},
        ),
        'frame:wall-time': Frame(
          id: 'frame:wall-time',
          title: 'Wall time',
          traits: ['line', 'temporal', 'gregorian'],
          extra: {'coordinate': gregorianDeclarationJson},
        ),
      },
    );

/// `meta.modified`, which every commit bumps. A replay that skipped it would
/// drift from the document it is replaying.
Document touch(Document document, {DateTime? at}) =>
    document.copyWith(meta: {...document.meta, 'modified': _stamp(at)});

/// A duration in the human-time magnitude frame's own units.
Magnitude durationMagnitude([
  String value = '0',
  String unit = 'second',
  String frame = 'measure:human-time',
]) => Magnitude(
  frame: frame,
  value: <String, dynamic>{
    'levels': <Json>[
      {'level': unit, 'value': value},
    ],
  },
);

/// True when every level of the object's intrinsic duration is exactly zero. A
/// malformed level counts as nothing rather than throwing: the owner's imported
/// calendars make a malformed magnitude plausible, not hypothetical.
bool isZeroDuration(Event? event) =>
    event?.duration?.coordinate.levels.every((level) {
      try {
        return Rational.parse(level.value).isZero;
      } on FormatException {
        return true;
      }
    }) ??
    true;

/// Every attachment of this object. This is what incidence means: one event
/// attached to several lines staples them together at that point, and the count
/// of attachments is the question several derivations ask of it.
List<Relation> eventRelations(Document document, String eventId) => [
  for (final relation in document.relations.values)
    if (relation.type == 'attachment' && relation.event == eventId) relation,
];

// `unicode: true` so the class matches a whole code point. The JavaScript
// matched UTF-16 code units and therefore encoded each half of an astral
// character as U+FFFD, which made two different keys collide; occurrence keys
// have only ever been ISO datetimes, so no shipped id changes.
final RegExp _reserved = RegExp(r'[^a-zA-Z0-9._~-]', unicode: true);

String _percent(Match match) => utf8
    .encode(match[0]!)
    .map((byte) => '%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}')
    .join();

/// THE virtual-id derivation, and there is only one.
///
/// An override names the occurrence it acts on by `patternId/encodedKey`. The
/// key is percent-encoded, so the LAST slash is always the boundary -- and every
/// consumer (validation, load repair, undo, sync) has to split it the same way
/// or they disagree about which pattern an override belongs to, which is how a
/// handful of dead pointers takes a whole file offline.
String stableVirtualId(String patternId, String key) =>
    '$patternId/${key.replaceAllMapped(_reserved, _percent)}';

String virtualPatternId(String? virtualId) {
  final boundary = (virtualId ?? '').lastIndexOf('/');
  return boundary > 0 ? virtualId!.substring(0, boundary) : '';
}

String overridePatternId(Override? override) => virtualPatternId(override?.virtualId);

/// The suppressed set, applied to whatever a projection generated. Suppression
/// is a set difference over the overrides map; whether it should instead be a
/// NOT connection is an open question, and nothing here presumes either answer.
List<T> applyVirtualOverrides<T>(
  Document document,
  List<T> facts,
  String Function(T fact) virtualIdOf,
) {
  final suppressed = {
    for (final override in document.overrides.values)
      if (override.suppress) override.virtualId,
  };
  return [
    for (final fact in facts)
      if (!suppressed.contains(virtualIdOf(fact))) fact,
  ];
}

({Document document, Override override}) suppressVirtual(
  Document document,
  String virtualId, {
  List<String> replacements = const [],
  String? id,
}) {
  final override = Override(
    id: id ?? createId('override'),
    virtualId: virtualId,
    suppress: true,
    replacements: [...replacements],
  );
  return (document: touch(document.put('overrides', override.id, override)), override: override);
}

/// THE delete cascade, once. The JavaScript carried six near-identical sweep
/// bodies; this is the one they melt into -- name a map, name what is doomed --
/// and the six cases are the predicates below. The count comes back so a caller
/// can report what travelled with the deletion.
({Document document, int removed}) sweep(
  Document document,
  String map,
  bool Function(Object? record) doomed,
) {
  final records = document.records(map);
  final survivors = {
    for (final entry in records.entries)
      if (!doomed(entry.value)) entry.key: entry.value,
  };
  final removed = records.length - survivors.length;
  return (
    document: removed == 0 ? document : document.replaceRecords(map, survivors),
    removed: removed,
  );
}

/// An override belongs to its pattern: once the series is gone the record can
/// never match a fact again, so it cannot be left behind as a pointer to
/// nothing. Sweep `overrides` with this.
bool Function(Object?) overridesOfPatterns(Set<String> patternIds) =>
    (record) => record is Override && patternIds.contains(overridePatternId(record));

/// A staple has two ends, so "does this connection point at something I am
/// deleting" is a question about EITHER end: deleting one event of a stapled
/// pair has to take the connection, or the survivor keeps an anchor to nothing.
/// Sweep `relations` with this -- for objects, for series, for frames alike.
bool Function(Object?) staplesTouching(Set<String> ids) =>
    (record) =>
        record is Relation && record.isStaple && record.ends.any((end) => ids.contains(end.id));

/// A containment edge belongs to BOTH of its objects. Sweep `relations`.
bool Function(Object?) containmentsTouching(Set<String> ids) =>
    (record) =>
        record is Relation &&
        record.type == 'contains' &&
        (ids.contains(record.parent) || ids.contains(record.child));

/// A membership names its member the way a containment names its ends, so a
/// deleted object's memberships -- its state affiliations included -- go with
/// it. Sweep `relations`.
bool Function(Object?) membershipsOf(Set<String> memberIds) =>
    (record) =>
        record is Relation && record.type == 'membership' && memberIds.contains(record.member);

/// Placing and removing staples.
///
/// The collection is OPEN: an object may carry arbitrarily many staples, of
/// arbitrary kind, arbitrarily placed. So this ADDS unless handed an explicit
/// id, and when it does update it REPLACES the whole record rather than
/// assigning fields onto the old one -- a stale field left behind by a
/// field-by-field edit is a claim nobody authored.
///
/// The ends are a LIST IN ORDER. Direction is that order; no gate here asks
/// which two things a connection is allowed to join.
({Document document, Relation staple}) putStaple(
  Document document, {
  String? id,
  String? kind,
  List<StapleEnd> ends = const [],
  Spread? spread,
  Json extra = const {},
}) {
  final staple = Relation(
    id: id ?? createId('relation'),
    type: 'staple',
    extra: {
      'kind': ?kind,
      'ends': [for (final end in ends) end.toJson()],
      'spread': ?spread?.toJson(),
      ...extra,
    },
  );
  return (document: touch(document.put('relations', staple.id, staple)), staple: staple);
}

Document removeStaple(Document document, String stapleId) {
  final existing = document.relations[stapleId];
  if (existing == null || !existing.isStaple) return document;
  return touch(document.remove('relations', stapleId));
}

/// Every staple on a series or an object, in a stable total order.
///
/// The order is by relation id, and it is NOT authoring order: ids are random
/// UUIDs and carry no creation sequence. What a tie-break needs is an order that
/// is total, deterministic, and identical across reload and journal replay,
/// which map key order does not promise.
///
/// A selector is required. An unfiltered call would return every staple in the
/// document, which no caller wants and which would silently "work" while meaning
/// something else entirely.
List<Relation> staplesFor(Document document, {String? series, String? object}) {
  final wanted = [series, object].whereType<String>().toList();
  if (wanted.isEmpty) return const [];
  return document.relations.values
      .where(
        (relation) =>
            relation.isStaple && wanted.every((id) => relation.ends.any((end) => end.id == id)),
      )
      .toList()
    ..sort((left, right) => left.id.compareTo(right.id));
}

/// Dedupe-merge: several imported records are one object.
///
/// The canonical record keeps each duplicate's payload under `foreign.stapled`,
/// so nothing authored is lost, and EVERY referrer is rewritten -- an
/// attachment, a pattern's template, an override's replacement -- because a
/// reference left pointing at a merged-away id is exactly the dangling pointer
/// the next load refuses.
({Document document, Event? canonical}) stapleEvents(Document document, Iterable<String> eventIds) {
  final ids = {...eventIds}.where(document.events.containsKey).toList();
  if (ids.length < 2) {
    return (document: document, canonical: ids.isEmpty ? null : document.events[ids.first]);
  }
  final canonicalId = ids.first;
  final merged = ids.skip(1).toSet();
  final foreign = Json.from(document.events[canonicalId]!.extra['foreign'] as Map? ?? const {});
  foreign['stapled'] = [
    ...?foreign['stapled'] as List?,
    for (final id in merged)
      <String, dynamic>{
        'id': id,
        'payload': document.events[id]!.payload,
        'foreign': document.events[id]!.extra['foreign'] ?? const {},
      },
  ];
  final canonical = document.events[canonicalId]!.withField('foreign', foreign);
  return (
    document: touch(
      document.copyWith(
        events: {
          for (final entry in document.events.entries)
            if (!merged.contains(entry.key))
              entry.key: entry.key == canonicalId ? canonical : entry.value,
        },
        relations: {
          for (final entry in _rewrite(
            document.relations,
            (relation) => _remap(relation, merged, canonicalId),
          ).entries)
            if (!_collapsed(entry.value)) entry.key: entry.value,
        },
        patterns: _rewrite(document.patterns, (pattern) {
          if (!merged.contains(pattern.templateEvent)) return null;
          return pattern.withField('templateEvent', canonicalId);
        }),
        overrides: _rewrite(document.overrides, (override) {
          if (!override.replacements.any(merged.contains)) return null;
          return override.copyWith(
            replacements: [
              for (final id in override.replacements) merged.contains(id) ? canonicalId : id,
            ],
          );
        }),
      ),
    ),
    canonical: canonical,
  );
}

/// EVERY id a relation names, rewritten -- whichever field or end spells it.
/// The JavaScript rewrote only an attachment's `event`, which left a merge's
/// containments, memberships and object-end staples pointing at an id that no
/// longer exists; one dangling pointer takes the whole file offline at its next
/// load, so the class is fixed here rather than the one instance.
Relation? _remap(Relation relation, Set<String> merged, String canonicalId) {
  var next = relation;
  for (final field in const ['event', 'parent', 'child', 'member']) {
    if (merged.contains(next.extra[field])) {
      next = next.withField(field, canonicalId);
    }
  }
  final ends = next.extra['ends'];
  if (ends is List && ends.any((end) => merged.contains(_object(end)))) {
    next = next.withField('ends', [
      for (final end in ends)
        if (merged.contains(_object(end))) {...end as Map, 'object': canonicalId} else end,
    ]);
  }
  return identical(next, relation) ? null : next;
}

Object? _object(Object? end) => end is Map ? end['object'] : null;

/// A connection that has collapsed to one thing joined to itself no longer says
/// anything -- an object's own start-to-end span is its duration magnitude, not a
/// connection -- which is why validation refuses one and why a merge drops it
/// rather than leaving behind a record the next load cannot accept.
bool _collapsed(Relation relation) =>
    (relation.type == 'contains' && relation.parent == relation.child) ||
    (relation.isStaple &&
        relation.ends.length == 2 &&
        relation.ends.first.id == relation.ends.last.id &&
        relation.ends.first is! FrameEnd);

/// Every record a rewrite touches, replaced; every record it returns null for,
/// left as the identical object it was -- which is what keeps the op diff honest.
Map<String, T> _rewrite<T>(Map<String, T> records, T? Function(T) rewrite) => {
  for (final entry in records.entries) entry.key: rewrite(entry.value) ?? entry.value,
};
