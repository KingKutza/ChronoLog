// RE-SAYING AN END.
//
// "There is no membership, only staples. The only relationship any object or
// frame can have to another is a staple." (Don, ruled 2026-09-01.) And the
// sentences law it lands on, from the same morning's reports: "a sentence that
// shows a connection but not all of its ends as authored terms is display, not
// authoring" -- the placement row offered its frame as a LINK, so the only way to
// change what a connection connects was to delete it and say the whole thing
// again, throwing away every other term with it.
//
// So this file is one verb and the read it needs. [connectionEnds] says what a
// connection's ends ARE, whatever record kind carries them; [resaidConnection]
// re-points ONE of them and leaves every other term standing, translating the
// coordinate through the frames' own laws and the authored correspondence -- or
// refusing in words when nothing carries it there.
//
// THE MELT THIS IS HALF OF. The four record kinds a connection is still spelled
// in -- an attachment's `frame`, a membership's `group`, a containment's
// `parent`, a staple's ends -- are four spellings of one sentence, and the table
// below is the only place that knows they differ. Nothing is migrated: every
// record still loads and saves byte for byte. A future melt writes one staple
// record for all four, and this table is where the four rows collapse to one.

import '../core/coordinate_law.dart';
import '../core/correspondence.dart';
import '../core/eras.dart' show firstMatch;
import '../core/records.dart';
import '../core/staples.dart';

/// One end of one connection, as a term a sentence can re-say.
///
/// [slot] is the record's own word for which end this is (`frame`, `group`,
/// `parent`, or `end:0` for a staple's first end), and it is what a caller hands
/// back to name what it is re-saying. [map] is the record map the end points
/// into, so a picker knows what it may offer.
typedef ConnectionEnd = ({String slot, String id, String map, bool carriesPosition});

/// Every end of a connection, in the order the sentence reads them.
///
/// ONE SHAPE (Don, ruled 2026-09-01), so this is one loop over the ends rather
/// than a table of record kinds. A record still spelled `attachment`,
/// `membership` or `contains` has no ends and therefore no terms -- it is inert
/// data, and offering its fields as authorable terms would be assigning it
/// meaning.
List<ConnectionEnd> connectionEnds(Relation relation) => [
  for (final (index, end) in relation.ends.indexed)
    (
      slot: 'end:$index',
      id: end.id,
      map: end.map,
      carriesPosition: end is FrameEnd && end.position != null,
    ),
];

/// THE SAME INSTANT, SPELLED IN ANOTHER FRAME'S OWN WORDS.
///
/// Read under [from]'s law to an exact day, carried across by the authored
/// correspondence, written back under [onto]'s law. The three refusals are the
/// load-bearing half and each says a different thing: a coordinate its own frame
/// cannot read, a frame nothing relates to the old one, and an instant the
/// authored staples land in more than one place at once -- which is answered as
/// several instants and never averaged into one nobody wrote.
Attempt<Json> restatedCoordinate(
  Staples staples,
  Correspondences correspondences, {
  required String from,
  required String onto,
  required Json coordinate,
}) {
  final days = staples.daysOf(from, Coordinate.fromJson(coordinate));
  if (days == null) {
    return Refused('Frame $from cannot read the coordinate this connection is written at.');
  }
  final landing = correspondences.landing(from, onto, days);
  if (landing.at.isEmpty) return Refused(landing.refusal!);
  if (landing.at.length > 1) {
    return Refused(
      'That instant lands on $onto in ${landing.at.length} places at once, and'
      ' averaging them would invent a position nobody wrote. Say which, by'
      ' authoring the staple that picks it.',
    );
  }
  final law = staples.lawOf(onto);
  if (law == null) {
    return Refused('Frame $onto has no coordinate law, so nothing can be written on it.');
  }
  return Resolved(Json.from(law.fromDays(landing.at.single).toJson()));
}

/// Re-say one end of a connection, keeping every other term.
///
/// The coordinate comes ALONG, translated, whenever the end being re-said is the
/// one the position is written against -- because a coordinate means nothing
/// except under the law of the frame it names, and carrying the written levels
/// over unchanged would silently move the object. When no correspondence can
/// carry it, this refuses and NOTHING is written: a half-moved connection is
/// worse than an unmoved one.
Attempt<Relation> resaidConnection(
  Staples staples,
  Correspondences correspondences,
  Relation relation, {
  required String slot,
  required String becomes,
}) {
  final end = firstMatch(connectionEnds(relation), (row) => row.slot == slot);
  if (end == null) {
    return Refused('This ${relation.type} has no $slot end to re-say.');
  }
  if (becomes.trim().isEmpty) {
    return Refused('An end has to name something; a connection to nothing is not a sentence.');
  }
  if (!staples.document.records(end.map).containsKey(becomes)) {
    return Refused('Nothing in this document is called $becomes.');
  }
  if (end.id == becomes) return Resolved(relation);

  final index = int.parse(slot.substring(4));
  final ends = relation.ends;
  final said = ends[index];
  if (said is! FrameEnd || !end.carriesPosition) {
    return Resolved(_withEnds(relation, ends, index, _renamed(said, becomes)));
  }
  final position = said.position;
  final written = position is CoordinatePosition ? position.json : null;
  if (written == null) {
    return Resolved(
      _withEnds(relation, ends, index, FrameEnd(becomes, position: position, extra: said.extra)),
    );
  }
  final moved = restatedCoordinate(
    staples,
    correspondences,
    from: said.frame,
    onto: becomes,
    coordinate: written,
  );
  final landed = moved.resolved;
  if (landed == null) return Refused(moved.refusal!);
  return Resolved(
    _withEnds(
      relation,
      ends,
      index,
      FrameEnd(becomes, position: Position.coordinate(landed), extra: said.extra),
    ),
  );
}

StapleEnd _renamed(StapleEnd end, String becomes) => switch (end) {
  FrameEnd(:final position, :final extra) => FrameEnd(becomes, position: position, extra: extra),
  ObjectEnd(:final point, :final offset, :final extra) => ObjectEnd(
    becomes,
    point: point,
    offset: offset,
    extra: extra,
  ),
  SeriesEnd(:final extra) => SeriesEnd(becomes, extra: extra),
};

/// The ends written back through the record's own `ends` field, so every other
/// term on the staple -- kind, payload, the ends nobody touched -- stands.
Relation _withEnds(Relation relation, List<StapleEnd> ends, int index, StapleEnd said) {
  final next = [...ends]..[index] = said;
  return relation.copyWith(
    extra: {
      ...relation.extra,
      'ends': [for (final end in next) end.toJson()],
    },
  );
}
