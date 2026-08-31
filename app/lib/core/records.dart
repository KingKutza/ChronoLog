// The document's record types.
//
// THE FILE IS THE TRUTH. Every JSON field name here is the JavaScript
// implementation's own, and the schema string is left exactly as the JavaScript
// writes it, because a document written by that implementation must load here
// unchanged. Nothing in this file renames, defaults, or migrates a field.
//
// ENUM IS THE ENEMY. "Any system that encodes a right way does in the same
// breath preclude other ways." So a relation's `type`, a staple's `kind`, a
// frame's traits, a relation's roles and the whole state vocabulary are OPEN
// STRINGS -- never Dart enums. An unknown relation type is legal data: it
// parses, it is preserved, it round-trips verbatim, and it is never refused.
// That is what every record's `extra` map is for. A record keeps the fields it
// does not name, in file order, and writes them back out.
//
// SEALED ONLY FOR STRUCTURE. [StapleEnd] and [Position] are sealed because
// their forms are genuinely structural: an end names exactly one thing, and
// carries at most one position on it. That makes "an end declares exactly one
// position form" a shape the type system cannot express wrongly, which is why
// the ~60 lines that used to check it are absent rather than ported.
//
// N-ARY, DIRECTIONAL, NOT TYPED. The staple, in the owner's words: "a piece of
// metal existing in a third dimension that pierces 1 or more pages (objects and
// frames) at 0 or more points causing all of said points to be bound together
// through that third dimension." It does ONE thing: "n points on objects or
// frames are one point", n >= 0, where a point is of size 0, all, or some one
// math value between. So `ends` is a LIST OF ANY LENGTH -- one end is a pin that
// gives a point identity, two is the familiar pair, three is the sticky note
// stapled to two calendars -- and direction is the authored order of that list.
// There is no scope gate anywhere below deciding which things a connection may
// join, and `kind` is carried as open data.
//
// COORDINATES BELONG TO THE COORDINATE-LAW LAYER, and there is exactly one
// coordinate type: that layer's [Coordinate]. Nothing here mints a second one.
// What a record STORES is the raw map the file carries, because that is what
// makes a round-trip byte-faithful; the typed [Coordinate] is parsed on demand
// through the accessors below. A law declaration stays raw JSON for the same
// reason -- the law layer reads it, this layer only carries it.

import 'package:freezed_annotation/freezed_annotation.dart';

import 'coordinate_law.dart';
import 'exact.dart';

part 'records.freezed.dart';

/// Parsed JSON, exactly as `jsonDecode` hands it over.
typedef Json = Map<String, dynamic>;

/// The persisted schema string. Not a version this layer may raise: it is what
/// the JavaScript writes, and the file is the truth.
const String schemaVersion = 'chronolog/1';

/// The seven maps an op may name -- the five typed record maps first, then the
/// two plain ones. ONE list: `meta` and `foreign` hold values rather than
/// records, which is the only distinction, and [recordMapsTyped] takes the
/// prefix rather than restating the names.
const List<String> recordMaps = [
  'frames',
  'events',
  'patterns',
  'relations',
  'overrides',
  'meta',
  'foreign',
];

/// The five maps whose values are records, in the order a document writes them.
final List<String> recordMapsTyped = recordMaps.take(5).toList();

/// The fields of [json] a record does not name, in file order. This is what
/// makes an unfamiliar field -- or a whole unfamiliar relation type -- survive
/// a load and save untouched.
Json extrasOf(Json json, Set<String> known) => {
  for (final entry in json.entries)
    if (!known.contains(entry.key)) entry.key: entry.value,
};

/// Canonical output: the named fields first in declaration order (a null one
/// omitted, so an absent field stays absent), then the preserved unknowns in
/// file order.
Json withExtras(Json named, Json extra) => {
  for (final entry in named.entries)
    if (entry.value != null) entry.key: entry.value,
  ...extra,
};

/// Total readers. Validation REPORTS; it never throws on data, and every
/// accessor below is read by validation -- so a field of the wrong shape answers
/// null rather than crashing whatever asked.
String? str(Object? value) => value is String ? value : null;

Json? obj(Object? value) => value is Json ? value : null;

List<String> _strings(Object? value) => value is List
    ? [
        for (final item in value)
          if (item is String) item,
      ]
    : const [];

Map<String, T> _records<T>(Object? raw, T Function(Json) from) => raw is Map
    ? {for (final entry in raw.entries) '${entry.key}': from(obj(entry.value) ?? const {})}
    : {};

Map<String, T> _typed<T>(Map<String, Object?> next, T Function(Json) from) => {
  for (final entry in next.entries) entry.key: _asRecord(entry.value, from),
};

/// What every record in a record map answers for: its own id, and its own JSON.
/// One loop over any map can therefore check a key against its record's id, and
/// one line can put a record or already-raw JSON on the wire.
abstract interface class DocumentRecord {
  String get id;
  Json toJson();
}

/// A record or already-raw JSON, as JSON. The one place an op's value crosses to
/// text, so the journal never needs to know what an event is.
Object? jsonValue(Object? value) => value is DocumentRecord ? value.toJson() : value;

T _asRecord<T>(Object? value, T Function(Json) from) =>
    value is T ? value : from(Json.from(value as Map));

/// A quantity in some frame's declared units: a duration, an offset, a spread.
/// `frame` says whose units, and `value` is the raw coordinate the file carries.
@Freezed(fromJson: false, toJson: false)
abstract class Magnitude with _$Magnitude {
  const Magnitude._();
  const factory Magnitude({String? frame, Json? value}) = _Magnitude;

  factory Magnitude.fromJson(Json json) =>
      Magnitude(frame: str(json['frame']), value: obj(json['value']));

  Json toJson() => {'frame': ?frame, 'value': ?value};

  /// This magnitude's value as the coordinate-law layer's own [Coordinate],
  /// parsed on demand. The raw map stays the stored truth, so a round-trip is
  /// byte-faithful and no second coordinate type exists to disagree with it.
  Coordinate get coordinate => Coordinate.fromJson(value);
}

Magnitude? _magnitude(Object? value) {
  final json = obj(value);
  return json == null ? null : Magnitude.fromJson(json);
}

/// Asymmetric fuzziness on a connection. "About 5ish" and a hard ceiling are
/// different shapes, so before and after are independent and either may be
/// absent. Uncertainties add; they never cancel.
@Freezed(fromJson: false, toJson: false)
abstract class Spread with _$Spread {
  const Spread._();
  const factory Spread({Magnitude? before, Magnitude? after}) = _Spread;

  factory Spread.fromJson(Json json) =>
      Spread(before: _magnitude(json['before']), after: _magnitude(json['after']));

  Json toJson() => {'before': ?before?.toJson(), 'after': ?after?.toJson()};
}

/// The seam to the frozen coordinate-law layer for a typed [Magnitude].
///
/// The document stays a RAW MAP on purpose: [CoordinateLaws] caches resolved
/// laws keyed on that map's identity, and handing it a freshly built one would
/// defeat the cache on every call -- which this is asked inside occurrence loops
/// at overscale.
extension MagnitudeDays on CoordinateLaws {
  Rational durationDays(
    Magnitude? magnitude, {
    Map<String, Object?>? document,
    CoordinateLaw? law,
  }) => magnitudeLaw(
    magnitude?.toJson(),
    document: document,
    law: law,
  ).magnitudeDays(magnitude?.coordinate);
}

/// A frame: a coordinate space, a group, a measure, an era. Which of those it
/// is, is a claim its traits make and a projection interprets -- frames are
/// groups, and handling is a group property.
@Freezed(fromJson: false, toJson: false)
abstract class Frame with _$Frame implements DocumentRecord {
  const Frame._();
  const factory Frame({
    required String id,
    String? title,
    @Default(<String>[]) List<String> traits,
    @Default(<String, dynamic>{}) Json extra,
  }) = _Frame;

  factory Frame.fromJson(Json json) => Frame(
    id: '${json['id'] ?? ''}',
    title: str(json['title']),
    traits: _strings(json['traits']),
    extra: extrasOf(json, const {'id', 'title', 'traits'}),
  );

  @override
  Json toJson() =>
      withExtras({'id': id, 'title': title, 'traits': traits.isEmpty ? null : traits}, extra);

  /// This frame's authored coordinate-law declaration, as parsed JSON.
  Json? get coordinate => obj(extra['coordinate']);

  /// The frame whose structure this one inherits.
  String? get basis => str(extra['basis']);

  /// The frame that defines this one's coordinates on its behalf.
  String? get coordinateDefinition => str(extra['coordinateDefinition']);

  Frame withField(String key, Object? value) => copyWith(extra: {...extra, key: value});
}

/// An object: an event, a note, a todo. One class, because containment and
/// state pass no judgment on which of those a record is.
@Freezed(fromJson: false, toJson: false)
abstract class Event with _$Event implements DocumentRecord {
  const Event._();
  const factory Event({
    required String id,
    @Default(<String>[]) List<String> traits,
    @Default(<String, Magnitude>{}) Map<String, Magnitude> magnitudes,
    Json? payload,
    @Default(<String, dynamic>{}) Json extra,
  }) = _Event;

  factory Event.fromJson(Json json) => Event(
    id: '${json['id'] ?? ''}',
    traits: _strings(json['traits']),
    magnitudes: _records(json['magnitudes'], Magnitude.fromJson),
    payload: obj(json['payload']),
    extra: extrasOf(json, const {'id', 'traits', 'magnitudes', 'payload'}),
  );

  @override
  Json toJson() => withExtras({
    'id': id,
    'traits': traits.isEmpty ? null : traits,
    'magnitudes': magnitudes.isEmpty
        ? null
        : {for (final e in magnitudes.entries) e.key: e.value.toJson()},
    'payload': payload,
  }, extra);

  /// The intrinsic duration every object carries, or null when it has none.
  Magnitude? get duration => magnitudes['duration'];

  Event withField(String key, Object? value) => copyWith(extra: {...extra, key: value});
}

/// A generator: a recurrence rule, a formula, a topology replication. Its
/// `language` says how to read it, and an unfamiliar language is data.
@Freezed(fromJson: false, toJson: false)
abstract class Pattern with _$Pattern implements DocumentRecord {
  const Pattern._();
  const factory Pattern({
    required String id,
    String? language,
    @Default(<String, dynamic>{}) Json extra,
  }) = _Pattern;

  factory Pattern.fromJson(Json json) => Pattern(
    id: '${json['id'] ?? ''}',
    language: str(json['language']),
    extra: extrasOf(json, const {'id', 'language'}),
  );

  @override
  Json toJson() => withExtras({'id': id, 'language': language}, extra);

  String? get kind => str(extra['kind']);
  String? get templateEvent => str(extra['templateEvent']);
  String? get templateRelation => str(extra['templateRelation']);

  Pattern withField(String key, Object? value) => copyWith(extra: {...extra, key: value});
}

/// An exception to a generated occurrence, named by the virtual id its pattern
/// derives. Once the pattern is gone the record can never match again, which is
/// why it travels with the pattern's deletion.
@Freezed(fromJson: false, toJson: false)
abstract class Override with _$Override implements DocumentRecord {
  const Override._();
  const factory Override({
    required String id,
    @Default('') String virtualId,
    @Default(false) bool suppress,
    @Default(<String>[]) List<String> replacements,
    @Default(<String, dynamic>{}) Json extra,
  }) = _Override;

  factory Override.fromJson(Json json) => Override(
    id: '${json['id'] ?? ''}',
    virtualId: '${json['virtual'] ?? ''}',
    suppress: json['suppress'] == true,
    replacements: _strings(json['replacements']),
    extra: extrasOf(json, const {'id', 'virtual', 'suppress', 'replacements'}),
  );

  @override
  Json toJson() => withExtras({
    'id': id,
    'virtual': virtualId,
    'suppress': suppress ? true : null,
    'replacements': replacements.isEmpty ? null : replacements,
  }, extra);
}

/// A relation: the whole of what one record can say about others. `type` is an
/// open string, and every field beyond `id` and `type` is that type's own -- so
/// a type this build has never heard of loads, validates as far as it can be
/// checked, and saves back byte for byte.
@Freezed(fromJson: false, toJson: false)
abstract class Relation with _$Relation implements DocumentRecord {
  const Relation._();
  const factory Relation({
    required String id,
    required String type,
    @Default(<String, dynamic>{}) Json extra,
  }) = _Relation;

  factory Relation.fromJson(Json json) => Relation(
    id: '${json['id'] ?? ''}',
    type: '${json['type'] ?? ''}',
    extra: extrasOf(json, const {'id', 'type'}),
  );

  @override
  Json toJson() => withExtras({'id': id, 'type': type}, extra);

  String? get event => str(extra['event']);
  String? get frame => str(extra['frame']);
  String? get parent => str(extra['parent']);
  String? get child => str(extra['child']);
  String? get group => str(extra['group']);
  String? get member => str(extra['member']);
  String? get role => str(extra['role']);
  String? get kind => str(extra['kind']);
  Json? get coordinate => obj(extra['coordinate']);
  Json? get payload => obj(extra['payload']);

  Spread? get spread {
    final raw = obj(extra['spread']);
    return raw == null ? null : Spread.fromJson(raw);
  }

  bool get isStaple => type == 'staple';

  /// This staple's n ends, IN ORDER -- the n points it says are one point. Any
  /// length is legal data: zero pierces pages without identifying a point, one
  /// is a pin, and three or more is the sticky stapled to several sheets at
  /// once. An end naming nothing resolvable is not an end and does not appear,
  /// which is how the count stays a countable claim rather than a shape check
  /// on each element.
  List<StapleEnd> get ends {
    final raw = extra['ends'];
    if (raw is! List) return const [];
    return [
      for (final end in raw)
        if (end is Map) ?StapleEnd.tryFrom(Json.from(end)),
    ];
  }

  Relation withField(String key, Object? value) => copyWith(extra: {...extra, key: value});
}

/// One end of a staple: exactly one thing, plus at most one position on it.
///
/// A frame end may carry no position when the connection's own derivation
/// supplies one (a succession's boundary comes from the eras it joins), so the
/// position is optional -- but it can never be two positions at once.
@Freezed(fromJson: false, toJson: false)
sealed class StapleEnd with _$StapleEnd {
  const StapleEnd._();

  /// A position in a coordinate space. The frame travels with the position
  /// because it is that frame's own law that makes the position mean anything.
  const factory StapleEnd.frame(
    String frame, {
    Position? position,
    @Default(<String, dynamic>{}) Json extra,
  }) = FrameEnd;

  /// A named point of an object's extent -- start, end, or a point the user
  /// named, which carries its own offset from the start.
  const factory StapleEnd.object(
    String object, {
    String? point,
    Magnitude? offset,
    @Default(<String, dynamic>{}) Json extra,
  }) = ObjectEnd;

  /// A whole pattern, positioned by the other end.
  const factory StapleEnd.series(String series, {@Default(<String, dynamic>{}) Json extra}) =
      SeriesEnd;

  /// Null when the end names nothing this substrate can reach.
  static StapleEnd? tryFrom(Json json) => switch (json) {
    {'frame': final String frame} => FrameEnd(
      frame,
      position: Position.tryFrom(json),
      extra: extrasOf(json, _frameKeys),
    ),
    {'object': final String object} => ObjectEnd(
      object,
      point: str(json['point']),
      offset: _magnitude(json['offset']),
      extra: extrasOf(json, _objectKeys),
    ),
    {'series': final String series} => SeriesEnd(series, extra: extrasOf(json, _seriesKeys)),
    _ => null,
  };

  /// The keys each end form names for itself; anything else on an end is
  /// preserved as that end's own unknown field.
  static const Set<String> _frameKeys = {
    'frame',
    'coordinate',
    'selector',
    'span',
    'void',
    'point',
  };
  static const Set<String> _objectKeys = {'object', 'point', 'offset'};
  static const Set<String> _seriesKeys = {'series'};

  Json toJson() => switch (this) {
    FrameEnd(:final frame, :final position, :final extra) => withExtras({
      'frame': frame,
      ...?position?.toJson(),
    }, extra),
    ObjectEnd(:final object, :final point, :final offset, :final extra) => withExtras({
      'object': object,
      'point': point,
      'offset': offset?.toJson(),
    }, extra),
    SeriesEnd(:final series, :final extra) => withExtras({'series': series}, extra),
  };

  /// The id this end names, whatever it names.
  String get id => switch (this) {
    FrameEnd(:final frame) => frame,
    ObjectEnd(:final object) => object,
    SeriesEnd(:final series) => series,
  };

  /// The record map this end points into.
  String get map => switch (this) {
    FrameEnd() => 'frames',
    ObjectEnd() => 'events',
    SeriesEnd() => 'patterns',
  };
}

/// Where on a frame an end touches.
///
/// A coordinate is ONE INSTANT. A selector is EVERY instant that satisfies it
/// ("Tuesdays"), which is why it is its own form rather than a coordinate with
/// levels left off -- writing "Tuesdays" as one coordinate would pick an
/// arbitrary Tuesday and call it the answer. A span is a region. A void is the
/// authored claim that there is nothing here, which is a different claim from an
/// absent staple: the absence says only that nobody has said yet.
///
/// A POINT is the frame's own extent spoken about: "the beginning", "the end",
/// "all of it", "three weeks in". Ruled 8.31 -- "the end of 1 could just as
/// easily connect to three weeks into 2" -- so a frame end says which of its own
/// points it touches the same way an object end always could, and the value is a
/// ONE MATH expression over that frame's extent rather than a vocabulary of
/// names. `frame_points.dart` reads it; this layer only carries it.
///
/// Every case stores the raw value the file carries, under the key the file
/// uses. The typed accessors below parse it on demand.
@Freezed(fromJson: false, toJson: false)
sealed class Position with _$Position {
  const Position._();
  const factory Position.coordinate(Json json) = CoordinatePosition;
  const factory Position.selector(Json json) = SelectorPosition;
  const factory Position.span(Json json) = SpanPosition;
  const factory Position.authoredVoid() = VoidPosition;

  /// A point of the frame's own extent. [source] is whatever the file carries
  /// under `point` -- a string expression for a point of size zero, or a map of
  /// `from`/`to` expressions for a sized one -- kept verbatim so a spelling this
  /// build cannot evaluate still round-trips.
  const factory Position.point(Object? source) = PointPosition;

  static Position? tryFrom(Json json) {
    if (json['void'] == true) return const VoidPosition();
    if (json.containsKey('point') && json['point'] != null) {
      return PointPosition(json['point']);
    }
    return switch (json) {
      {'selector': final Map it} => SelectorPosition(Json.from(it)),
      {'span': final Map it} => SpanPosition(Json.from(it)),
      {'coordinate': final Map it} => CoordinatePosition(Json.from(it)),
      _ => null,
    };
  }

  Json toJson() => switch (this) {
    CoordinatePosition(:final json) => {'coordinate': json},
    SelectorPosition(:final json) => {'selector': json},
    SpanPosition(:final json) => {'span': json},
    PointPosition(:final source) => {'point': source},
    VoidPosition() => const {'void': true},
  };

  /// The one instant this position names, or null -- because only a coordinate
  /// IS one instant. A selector, a span and a void each answer a different
  /// question, and collapsing any of them to a single coordinate would invent a
  /// fact. Parsed on demand from the stored map, which stays the truth.
  Coordinate? get coordinate => switch (this) {
    CoordinatePosition(:final json) => Coordinate.fromJson(json),
    _ => null,
  };

  /// The region this position names, or null. Same rule, same parse.
  ({Coordinate from, Coordinate to})? get span => switch (this) {
    SpanPosition(:final json) => (
      from: Coordinate.fromJson(obj(json['from'])),
      to: Coordinate.fromJson(obj(json['to'])),
    ),
    _ => null,
  };

  /// The cycle or level this position selects in, and the value it selects --
  /// read under the frame's OWN law, which is what makes a name mean anything.
  Json? get selector => switch (this) {
    SelectorPosition(:final json) => json,
    _ => null,
  };

  /// The authored point expression, exactly as the file carries it, or null.
  Object? get point => switch (this) {
    PointPosition(:final source) => source,
    _ => null,
  };
}

/// The document. Eight top-level keys in this order, which is the order the
/// JavaScript writes and both shipped fixtures carry.
@Freezed(fromJson: false, toJson: false)
abstract class Document with _$Document {
  const Document._();
  const factory Document({
    @Default(schemaVersion) String schema,
    @Default(<String, dynamic>{}) Json meta,
    @Default(<String, Frame>{}) Map<String, Frame> frames,
    @Default(<String, Event>{}) Map<String, Event> events,
    @Default(<String, Pattern>{}) Map<String, Pattern> patterns,
    @Default(<String, Relation>{}) Map<String, Relation> relations,
    @Default(<String, Override>{}) Map<String, Override> overrides,
    @Default(<String, dynamic>{}) Json foreign,
  }) = _Document;

  factory Document.fromJson(Json json) => Document(
    schema: '${json['schema'] ?? ''}',
    meta: obj(json['meta']) ?? {},
    frames: _records(json['frames'], Frame.fromJson),
    events: _records(json['events'], Event.fromJson),
    patterns: _records(json['patterns'], Pattern.fromJson),
    relations: _records(json['relations'], Relation.fromJson),
    overrides: _records(json['overrides'], Override.fromJson),
    foreign: obj(json['foreign']) ?? {},
  );

  Json toJson() => {
    'schema': schema,
    'meta': meta,
    for (final map in recordMapsTyped)
      map: {for (final entry in records(map).entries) entry.key: jsonValue(entry.value)},
    'foreign': foreign,
  };

  /// One record map by name. Every uniform question -- what does an op mean,
  /// what did an edit touch, what does this reference point at -- is asked
  /// through here rather than by naming a field seven times over.
  Map<String, Object?> records(String map) => switch (map) {
    'events' => events,
    'frames' => frames,
    'patterns' => patterns,
    'relations' => relations,
    'overrides' => overrides,
    'meta' => meta,
    'foreign' => foreign,
    _ => throw ArgumentError('unknown record map "$map"'),
  };

  /// One record map, wholesale. `Map.from` is what re-types the collection, so
  /// a value of the wrong shape is refused here rather than surfacing as a cast
  /// error inside some later derivation.
  Document replaceRecords(String map, Map<String, Object?> next) => switch (map) {
    'events' => copyWith(events: _typed(next, Event.fromJson)),
    'frames' => copyWith(frames: _typed(next, Frame.fromJson)),
    'patterns' => copyWith(patterns: _typed(next, Pattern.fromJson)),
    'relations' => copyWith(relations: _typed(next, Relation.fromJson)),
    'overrides' => copyWith(overrides: _typed(next, Override.fromJson)),
    'meta' => copyWith(meta: Json.from(next)),
    'foreign' => copyWith(foreign: Json.from(next)),
    _ => throw ArgumentError('unknown record map "$map"'),
  };

  /// Whole-record assignment. A put carries the whole record -- records are the
  /// unit, not fields -- so a journal can apply one with no idea what an event
  /// is, and applying the same put twice lands on the same state.
  Document put(String map, String id, Object? value) =>
      replaceRecords(map, {...records(map), id: value});

  Document remove(String map, String id) => replaceRecords(map, {...records(map)}..remove(id));
}
