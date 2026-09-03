// THE STAPLES REGION: every connection this object is in, as a sentence.
//
// One region, one shape. The implicit placement, every authored staple, and the
// containment and membership records an older document still holds all read the
// same way -- so nothing about this object is hidden behind a widget of its own,
// and the Holds / Held-by picker pair that "should not be here" (ISSUES 9.1) is
// gone with the second authoring path it was.
//
// THERE IS NO MEMBERSHIP, ONLY STAPLES (ruled 9.1). That is what the AUTHORING
// half of this file says: the + writes a staple, always. The older relation
// types are SHOWN, readable and removable, because authored data a person
// cannot see is authored data they cannot correct -- and each one says what it
// is and that saying it again means saying it as a sentence.

import 'package:flutter/material.dart';

import '../chrome/controls.dart';
import '../core/coordinate_law.dart';
import '../core/document.dart';
import '../core/exact.dart';
import '../core/object_kinds.dart';
import '../core/stapled_here.dart';
import '../core/projection.dart';
import '../core/records.dart';
import '../core/staples.dart';
import '../edit/editor.dart';
import '../lens/theme.dart';
import 'card_chrome.dart';
import 'card_factory.dart';
import 'connection_picker.dart';
import 'coordinate_field.dart';
import 'sentences.dart';
import 'staple_editor.dart';

/// One sentence: the substrate's own row, and the word the card reads it in.
///
/// ONE SOURCE (ISSUES 9.1, "there is no membership, only staples"). The card
/// used to walk the document three more times for containments and memberships
/// beside the staples, which is two answers to one question -- the substrate
/// lists EVERY record naming this object now, so the card reads that list and
/// nothing else. A row that says where an end sits is a staple sentence; a row
/// that connects and says nothing about position is a BELONGING sentence, and
/// which word it wears follows from the record itself.
typedef SaidRow = ({ConnectionRow row, String verb, bool belonging});

/// The words a belonging sentence can wear. Display vocabulary, so it is data.
///
/// FLAGGED (core zone, ruled 2026-09-01): keyed by the SENTENCE now, not by the
/// record kind spelling it -- there is one record kind. Which of the pair a row
/// takes follows from which side of the sentence names this object: the same
/// containment reads "holds" from the parent and "is held by" from the child,
/// and an affiliation reads "is a member of" from the object.
const Map<String, ({String own, String other})> belongingWords = {
  'contains': (own: 'holds', other: 'is held by'),
  'membership': (own: 'holds', other: 'is a member of'),
};

/// What this belonging sentence says. A connection nobody has words for says so
/// plainly rather than guessing -- said, never silently blank.
String belongingVerb(Relation relation, String objectId) {
  for (final edge in stapledContainments(relation)) {
    if (edge.parent == objectId) return belongingWords['contains']!.own;
    if (edge.child == objectId) return belongingWords['contains']!.other;
  }
  for (final edge in stapledAffiliations(relation)) {
    if (edge.object == objectId) return belongingWords['membership']!.other;
  }
  return relation.kind ?? 'is connected to';
}

/// Every connection this object is in, in one list, from the one place that
/// knows them all.
List<SaidRow> objectSentences(Editor editor, String objectId) => [
  for (final row in editor.staples.effectiveObjectStaples(objectId))
    (
      row: row,
      // FLAGGED (core zone, ruled 2026-09-01): the record behind a row is the
      // STAPLE now -- there is no second field a connection could arrive in.
      verb: row.positions ? '' : belongingVerb(row.staple ?? row.relation!, objectId),
      belonging: !row.positions,
    ),
];

/// EVERY SENTENCE A FRAME IS IN, from the frame's own side.
///
/// ISSUES 9.2: "no GUI path authors a frame-to-frame sentence ('10:00 here is
/// 9:30 on Wall Time')". The edit card IS sentences (8.31, one card class), so
/// the frame card says them too -- with the frame as the near end. One row per
/// end that names this frame, exactly as the object side does, because a staple
/// piercing one frame at two points says two things about it.
List<SaidRow> frameSentences(Editor editor, String frameId) {
  final rows = <SaidRow>[];
  for (final staple in editor.staples.staplesOf(frameId)) {
    final ends = staple.readEnds;
    for (final (index, end) in ends.indexed) {
      if (end is! FrameEnd || end.frame != frameId) continue;
      final fars = [
        for (final (other, far) in ends.indexed)
          if (other != index) far,
      ];
      rows.add((
        row: (
          implicit: false,
          relation: null,
          staple: staple,
          kind: staple.kind,
          near: end,
          far: fars.length == 1 ? fars.single : null,
          fars: fars,
          // A frame end that names no instant says the thing belongs on this
          // sheet and nothing about where -- the frame's own affiliation.
          positions: end.position != null,
        ),
        verb: staple.kind ?? '',
        belonging: end.position == null,
      ));
    }
  }
  return rows;
}

/// WHAT THE SENTENCE IS, not which record spells it: one containment is read
/// from both sides and one staple may pierce this object at two of its own
/// points, so the record id alone names two rows.
String sentenceKey(SaidRow said) =>
    '${said.row.staple?.id ?? said.row.relation?.id ?? 'implicit'}'
    '/${said.row.far?.id ?? ''}/${endPoint(said.row.near)}';

/// WHICH KIND THE FAR END OF A SENTENCE WEARS, in the catalog's own words. A
/// frame is not an object, so it gets the other word the substrate already
/// files it under rather than a catalog row that would make a frame an object.
({String kind, String label}) farKind(Document document, StapleEnd? far) {
  final id = far?.id ?? '';
  if (document.frames.containsKey(id)) {
    return (kind: stapledFrameKind, label: stapledFrameLabel.toLowerCase());
  }
  final event = document.events[id];
  if (event == null) return (kind: '', label: 'thing');
  final kind = objectKindForEvent(event);
  return (kind: kind, label: (objectKinds[kind]?.label ?? kind).toLowerCase());
}

/// THE ORDER SENTENCES READ IN (ISSUES 9.2): positional sentences first, then
/// the affiliations, then whatever is left, each run in far-end title order.
/// A card is read top to bottom, so what places the object comes first.
int sentenceRank(SaidRow said, Document document) {
  if (said.row.positions) return 0;
  if (document.frames.containsKey(said.row.far?.id ?? '')) return 1;
  return 2;
}

/// THE SHAPE A SENTENCE HAS, which is what makes two of them alike: the word on
/// it, which point of this object it touches, which point of the far end it
/// touches, and what kind of thing that far end is. Nothing about WHICH far
/// record -- that is the only thing a fold's members differ in.
String sentenceShape(SaidRow said, Document document) => [
  said.row.kind ?? said.verb,
  endPoint(said.row.near),
  said.row.far is ObjectEnd ? endPoint(said.row.far) : '',
  said.row.positions ? 'places' : 'affiliates',
  farKind(document, said.row.far).kind,
].join('/');

/// A run of sentences that say one thing about many things.
typedef SentenceFold = ({String shape, String label, List<SaidRow> members});

/// The point vocabulary read as prose. A point the author invented is left as
/// they wrote it -- there is no closed list here and no guessing at a word.
String pointPhrase(String point) => switch (point) {
  wholePoint => 'the whole',
  'start' => 'the start',
  'end' => 'the end',
  'midpoint' => 'the midpoint',
  _ => 'the $point',
};

/// THE SENTENCES REGION: one line per sentence, like sentences folded, and its
/// own scroll under a header that does not move.
///
/// ISSUES 9.2 (Don): "the staple cards are so tall that it can be
/// overwhelming" -- five to eight lines per sentence at rest, so a meeting with
/// thirteen todos stapled to it was a hundred lines of card. Four things fix
/// it, and all four are here:
///
///   AT REST A SENTENCE IS ONE LINE -- the prose and its sigil. The coordinate
///   field, the fuzziness, the following rule and the unsay belong to the row
///   that is OPEN, and exactly one row is open at a time.
///
///   THE LIKE FOLD. Sentences sharing a shape and a far-end kind read as one
///   line with a count -- "13 todos: their start is the end of this" -- and the
///   mass edits are offered on the fold, because that is where the selection
///   already is. One click opens the list, one more opens any member: every
///   sentence stays reachable in at most two.
///
///   THE REGION SCROLLS ON ITS OWN, so the header stays put however much is
///   said about this object.
///
///   AND IT IS SORTED: positional first, then affiliations, then the rest.
///
/// Overscale is the acceptance: an object with two hundred staples renders this
/// region inside a screen at rest.
class StapleEditor extends StatefulWidget {
  const StapleEditor({super.key, required this.objectId, this.nearEnd, this.openFirst = false});

  final String objectId;

  /// The near end when the card is not an object's -- a frame card says
  /// sentences too, with itself as the near end (ISSUES 9.2: the edit card IS
  /// sentences, one card class).
  final StapleEnd? nearEnd;

  /// Opens holding its first sentence open: the sentence the gesture that made
  /// this card just said.
  final bool openFirst;

  @override
  State<StapleEditor> createState() => _StapleEditorState();
}

class _StapleEditorState extends State<StapleEditor> {
  String? _open;
  bool _openFar = false, _took = false;
  final Set<String> _unfolded = {};

  void _openRow(String key, {required bool far}) => setState(() {
    final same = _open == key && _openFar == far;
    _open = same ? null : key;
    _openFar = !same && far;
  });

  Widget _row(SaidRow said, Editor editor) {
    final key = sentenceKey(said);
    return SentenceRow(
      key: ValueKey(key),
      objectId: widget.objectId,
      said: said,
      editor: editor,
      open: _open == key,
      openFar: _open == key && _openFar,
      onOpen: (far) => _openRow(key, far: far),
    );
  }

  /// Unsays every member of a fold in ONE act. The mass edit lives on the fold
  /// because the fold is the selection: thirteen sentences chosen by saying one
  /// thing about them.
  void _unsayAll(Editor editor, SentenceFold fold) {
    final ids = <String>{
      for (final said in fold.members)
        if (said.row.staple?.id ?? said.row.relation?.id case final String id) id,
    };
    editor.transaction('Unsay these', (document) {
      var next = document;
      for (final id in ids) {
        next = next.relations[id]?.isStaple ?? false
            ? removeStaple(next, id)
            : next.remove('relations', id);
      }
      return next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final editor = CardHost.maybeOf(context)?.editor ?? ChromeScope.of(context).editor;
    if (editor == null) return const SizedBox.shrink();
    final document = editor.document;
    final said = [
      ...widget.nearEnd == null
          ? objectSentences(editor, widget.objectId)
          : frameSentences(editor, widget.objectId),
    ]
      ..sort((left, right) {
        final byRank = sentenceRank(left, document) - sentenceRank(right, document);
        if (byRank != 0) return byRank;
        final byTitle = titleOfRecord(document, left.row.far?.id ?? '')
            .compareTo(titleOfRecord(document, right.row.far?.id ?? ''));
        return byTitle != 0 ? byTitle : sentenceKey(left).compareTo(sentenceKey(right));
      });
    // The folds, in the order their first member reads.
    final order = <String>[];
    final byShape = <String, List<SaidRow>>{};
    for (final one in said) {
      final shape = sentenceShape(one, document);
      if (!byShape.containsKey(shape)) order.add(shape);
      byShape.putIfAbsent(shape, () => []).add(one);
    }
    if (!_took && widget.openFirst && said.isNotEmpty) {
      _took = true;
      _open = sentenceKey(said.first);
    }
    final body = <Widget>[];
    for (final shape in order) {
      final members = byShape[shape]!;
      if (members.length < 2) {
        body.add(_row(members.single, editor));
        continue;
      }
      final fold = (
        shape: shape,
        label: farKind(document, members.first.row.far).label,
        members: members,
      );
      body.add(_fold(context, editor, fold));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // WHERE THE SENTENCES PUT THIS. A frame is not put anywhere by them --
        // it is the sheet -- so the note belongs to the object side alone.
        if (widget.nearEnd == null)
          extentSentence(
            context,
            editor.engine,
            editor.staples.resolveObjectExtent(widget.objectId),
          ),
        // THE REGION'S OWN SCROLL. The header above it does not move, however
        // many sentences are said about this object.
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: cardPx(context, 'card.regionHeight')),
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: body),
          ),
        ),
        NewSentence(objectId: widget.objectId, editor: editor, nearEnd: widget.nearEnd),
      ],
    );
  }

  Widget _fold(BuildContext context, Editor editor, SentenceFold fold) {
    final open = _unfolded.contains(fold.shape);
    final first = fold.members.first;
    final count = fold.members.length;
    final near = pointPhrase(endPoint(first.row.near));
    final far = first.row.far;
    final says = far is ObjectEnd
        ? 'their ${endPoint(far)} is $near of this'
        : first.row.positions
        ? 'this sits on them at $near'
        : 'this is stapled to them';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        cardWrap(context, [
          namedAction(
            context,
            '$count ${fold.label}s: $says.',
            hint: 'One line for $count sentences that say one thing. Opens the list.',
            onTap: () => setState(
              () => open ? _unfolded.remove(fold.shape) : _unfolded.add(fold.shape),
            ),
          ),
          if (open)
            namedAction(
              context,
              'Unsay all $count',
              hint: 'Takes all $count sentences off, as one undoable act.',
              onTap: () => _unsayAll(editor, fold),
            ),
        ]),
        if (open)
          Padding(
            padding: EdgeInsets.only(left: cardPx(context, 'card.pad')),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final said in fold.members) _row(said, editor)],
            ),
          ),
      ],
    );
  }
}

/// What a record is CALLED -- a frame by its title, an object by its own.
String titleOfRecord(Document document, String id) {
  final frame = document.frames[id];
  if (frame != null) return frame.title ?? id;
  return str(document.events[id]?.payload?['title']) ?? id;
}

/// WHERE THE SENTENCES ACTUALLY PUT THIS, in words (ISSUES 9.1: "the readouts
/// read as info but do not say what they are trying to say"). It was a run of
/// fields joined by dots; it is prose now, and it says the same facts.
/// Overdetermined and unresolved connections are LISTED, never averaged and
/// never hidden -- an average of contradictory anchors is a third position
/// nobody wrote.
Widget extentSentence(BuildContext context, ProjectionEngine engine, Extent extent) {
  final frame = extent.frame;
  String? at(Rational? days) {
    if (days == null || frame == null) return null;
    try {
      return coordinateText(
        Coordinate.fromJson(engine.daysCoordinate(frame, days)),
        engine.lawOf(frame),
      );
    } on Object {
      return null;
    }
  }

  final starts = at(extent.startDays);
  final ends = at(extent.endDays);
  // ONE LINE, AND ONLY WHAT IS KNOWN (ISSUES 9.2). "'which is a legal thing for
  // a record to say' is the card reassuring the person about the model -- cut."
  // A real contest is not a note about the object at all: it is a refusal
  // beside the sentence that caused it, which is where the correction is made.
  return cardNote(
    context,
    [
      if (starts == null) 'No start said.' else 'This starts at $starts.',
      if (ends == null) 'No end said.' else 'It ends at $ends.',
      if (extent.cyclic)
        'These sentences resolve back through this object, so there is no instant to report.',
      if (!extent.spread.isZero)
        'Fuzzy by ${extent.spread.before.toDecimal(3)} of a day before and '
            '${extent.spread.after.toDecimal(3)} after.',
    ].join(' '),
    refusal: extent.cyclic,
  );
}

/// THE CONTESTS ONE SENTENCE CAUSED. A contest names the record it came off, so
/// it is shown at that record's row and nowhere else -- and a sentence that
/// claims no point cannot have caused one, whatever the derivation reported.
List<String> contestsOn(Extent extent, ConnectionRow row) {
  final id = row.staple?.id ?? row.relation?.id;
  if (id == null || !row.positions) return const [];
  bool mine(Contest contest) => (contest.staple?.id ?? contest.relation?.id) == id;
  return [
    for (final contest in extent.overdetermined)
      if (mine(contest))
        'Another sentence also says where its ${contest.role} is. Both are kept; '
            'neither is averaged in.',
    for (final contest in extent.unresolved)
      if (mine(contest)) 'This says nothing an instant can be read off yet.',
  ];
}

/// ONE SENTENCE, in terms you can say again.
class SentenceRow extends StatefulWidget {
  const SentenceRow({
    super.key,
    required this.objectId,
    required this.said,
    required this.editor,
    this.open = false,
    this.openFar = false,
    this.onOpen,
  });

  final String objectId;
  final SaidRow said;
  final Editor editor;

  /// The one row the region is holding open. At rest a sentence is one line of
  /// prose and its sigil; everything that edits a term belongs to the open row.
  final bool open;

  /// Opened by touching the far term, so that term is already being said again.
  final bool openFar;

  /// Asks the region to open this row -- and, when the far term was the thing
  /// touched, to open it saying that term again.
  final void Function(bool far)? onOpen;

  @override
  State<SentenceRow> createState() => _SentenceRowState();
}

class _SentenceRowState extends State<SentenceRow> {
  String? _refusal;

  Editor get _editor => widget.editor;
  ConnectionRow get _row => widget.said.row;
  String get _verb => _row.kind ?? widget.said.verb;

  /// The word this sentence READS AS from this side.
  String get _reads =>
      _belonging && widget.said.verb.isNotEmpty ? widget.said.verb : _verb;

  /// A row that connects and says nothing about where either end sits: the
  /// belonging sentences, spelled in a record kind of their own.
  bool get _belonging => widget.said.belonging;

  /// THE PLACEMENT: the one implicit row that DOES place this object. A
  /// belonging row is implicit too, so `implicit` alone names both.
  bool get _placement => _row.implicit && _row.positions;

  /// The staple with one end replaced, written WHOLE -- a field-by-field edit
  /// would leave a stale claim nobody authored.
  void _writeEnd(StapleEnd next, {required bool near}) {
    final staple = _row.staple;
    if (staple == null) return;
    final index = staple.endIndexOf(widget.objectId);
    final target = near ? index : 1 - index;
    _editor.transaction(
      'Edit connection',
      (document) => document.put(
        'relations',
        staple.id,
        staple.withField('ends', [
          for (final (at, end) in staple.ends.indexed) (at == target ? next : end).toJson(),
        ]),
      ),
    );
  }

  void _setCoordinate(Coordinate? value) {
    // A belonging sentence carries no position, so nothing here may write one
    // onto its record.
    if (_belonging) return;
    final relation = _row.relation;
    if (relation != null) {
      // The implicit placement is edited IN PLACE. Clearing it clears the
      // coordinate and KEEPS the attachment -- the engine's coordinate-less
      // placement then applies, and no second contradicting record is minted.
      // FLAGGED (core zone, ruled 2026-09-01): the instant lives on the frame
      // END, so it is re-said through the one definition rather than written as
      // a field nothing reads. Clearing it keeps the connection and drops only
      // the position -- an affiliation, which is what "somewhere on this sheet,
      // nothing about where" has always meant.
      return _editor.transaction(
        'Edit placement',
        (document) => document.put(
          'relations',
          relation.id,
          sayingInstant(relation, value?.toJson()),
        ),
      );
    }
    final far = _row.far;
    if (far is! FrameEnd) return;
    _writeEnd(
      FrameEnd(
        far.frame,
        position: value == null ? null : Position.coordinate(Json.from(value.toJson())),
        extra: far.extra,
      ),
      near: false,
    );
  }

  void _setVerb(String verb) {
    final staple = _row.staple;
    if (staple == null) return;
    _editor.transaction(
      'Say the connection again',
      (d) => d.put('relations', staple.id, staple.withField('kind', verb)),
    );
  }

  /// THE COORDINATE, CARRIED ACROSS (ISSUES 9.1). Re-pointing a frame end
  /// re-frames the object, and the instant comes along expressed in the new
  /// frame's own law. Where nothing carries it -- no shared basis, a frame that
  /// cannot label a point at all -- the re-saying is REFUSED in words and
  /// nothing moves: a silently dropped coordinate is the same object quietly
  /// claiming a different time.
  Json? _carried(String from, String to, Json? coordinate) {
    if (coordinate == null) return null;
    final days = _editor.engine.coordinateDays(from, coordinate);
    return _editor.engine.daysCoordinate(to, days);
  }

  void _sayFarEnd(String id, {required bool isFrame}) {
    setState(() => _refusal = null);
    final relation = _placement ? _row.relation : null;
    if (relation != null) {
      // The implicit placement: its far end IS the frame this object counts in,
      // so re-saying it is the re-framing Don asked for.
      if (!isFrame) {
        return setState(
          () => _refusal =
              'A placement counts in a FRAME. To say this object sits with another '
              'object, add a sentence below and name it there.',
        );
      }
      final from = relation.frame ?? '';
      Json? carried;
      try {
        carried = _carried(from, id, relation.coordinate);
      } on Object catch (refusal) {
        return setState(
          () => _refusal =
              'Nothing carries this instant from ${_nameOf(from)} to ${_nameOf(id)}: '
              '$refusal Staple the two frames together, or clear the instant and say it '
              'again in the new frame\'s own words.',
        );
      }
      // FLAGGED (core zone, ruled 2026-09-01): the frame and the instant both
      // live on the END, so the row re-says the end rather than two fields.
      final said = relation.withField('ends', [
        for (final end in relation.ends)
          end is FrameEnd
              ? FrameEnd(
                  id,
                  position: carried == null ? null : Position.coordinate(carried),
                  extra: end.extra,
                ).toJson()
              : end.toJson(),
      ]);
      return _editor.transaction(
        'Re-frame',
        (d) => d.put('relations', relation.id, said),
      );
    }
    final far = _row.far;
    if (far == null) return;
    if (!isFrame) return _writeEnd(ObjectEnd(id, point: endPoint(far)), near: false);
    Json? carried;
    if (far is FrameEnd) {
      try {
        carried = _carried(far.frame, id, far.position?.coordinate?.toJson());
      } on Object catch (refusal) {
        return setState(
          () => _refusal =
              'Nothing carries this instant from ${_nameOf(far.frame)} to ${_nameOf(id)}: '
              '$refusal Staple the two frames together, or clear the instant first.',
        );
      }
    }
    _writeEnd(
      FrameEnd(id, position: carried == null ? null : Position.coordinate(carried)),
      near: false,
    );
  }

  String _nameOf(String id) {
    final document = _editor.document;
    final frame = document.frames[id];
    if (frame != null) return frame.title ?? id;
    return str(document.events[id]?.payload?['title']) ?? id;
  }

  /// What a far term may become: the frames and objects the document holds,
  /// narrowed by what has been typed. Windowed -- a term never enumerates.
  List<({String value, String label})> _records(BuildContext context, String typed) {
    final found = searchConnectables(
      _editor.document,
      typed,
      window: cardPx(context, 'card.searchWindow').round(),
      scan: cardPx(context, 'card.searchScan').round(),
      exclude: widget.objectId,
    );
    return [
      for (final hit in found.hits)
        (value: hit.id, label: '${hit.kind == 'frame' ? '▤' : '●'} ${hit.label}'),
    ];
  }

  List<({String value, String label})> _points(String typed) => [
    for (final point in extentPoints)
      if (typed.trim().isEmpty || point.contains(typed.trim().toLowerCase()))
        (value: point, label: point),
  ];

  void _remove() {
    // FLAGGED (core zone, ruled 2026-09-01): the record behind a row is the
    // STAPLE now, whichever sentence it says, so unsaying one is one path. A row
    // with no record at all is the placement's own instant, which is cleared
    // rather than removed -- the connection stands, the position goes.
    final record = _row.staple ?? _row.relation;
    if (record == null) return _setCoordinate(null);
    if (_belonging) {
      return _editor.transaction('Unsay this', (d) => d.remove('relations', record.id));
    }
    return _editor.transaction('Unsay this', (d) => removeStaple(d, record.id));
  }

  /// MAKE WHAT NOTHING IS CALLED YET, inside the sentence being said. The frame
  /// is minted as a GROUP -- a frame IS a group (ruled 2026-08-19) -- and what
  /// it should really be is authored on the card that opens.
  void _create(String name) {
    final host = CardHost.of(context);
    final frame = Frame(
      id: createId('frame'),
      title: name,
      traits: const ['set', 'group'],
      extra: const {
        'display': {'weight': 'w * 1.5'},
      },
    );
    _editor.transaction('New frame $name', (d) => d.put('frames', frame.id, frame));
    _sayFarEnd(frame.id, isFrame: true);
    host.openFrame(frame.id);
  }

  /// THE COORDINATE ONE END SAYS, in that frame's own words, or null where it
  /// says none.
  String? _coordinateOf(StapleEnd? end) {
    Json? coordinate;
    String? frameId;
    if (end is FrameEnd) {
      frameId = end.frame;
      coordinate = end.position?.coordinate?.toJson();
    }
    if (_placement && end == _row.far) {
      frameId = _row.relation?.frame ?? frameId;
      coordinate = _row.relation?.coordinate ?? coordinate;
    }
    if (frameId == null || coordinate == null) return null;
    try {
      return coordinateText(Coordinate.fromJson(coordinate), _editor.engine.lawOf(frameId));
    } on Object {
      return null;
    }
  }

  /// ONE LINE OF PROSE AND ITS SIGIL (ISSUES 9.2). The far end is its own word,
  /// because touching the thing this is stapled to is how a person re-says it.
  Widget _atRest(BuildContext context) {
    final row = _row;
    final far = row.far;
    final farId = far?.id ?? '';
    final isFrame = _editor.document.frames.containsKey(farId);
    final nearAt = _coordinateOf(row.near);
    final farAt = _coordinateOf(far);
    final near = nearAt != null
        ? '$nearAt here'
        : endPoint(row.near) == wholePoint
        ? 'This'
        : pointPhrase(endPoint(row.near));
    // THE WORD IS ITS OWN WORD. A belonging sentence wears a verb the author
    // (or an older record) chose, and reading it means seeing it -- so it is
    // said on its own rather than glued into a phrase.
    final says = _belonging
        ? null
        : far is ObjectEnd
        ? '$near is ${pointPhrase(endPoint(far))} of'
        : '$near is on';
    final after = farAt == null ? '.' : ' at $farAt.';
    final host = CardHost.maybeOf(context);
    final name = _nameOf(farId);
    return _framed(
      context,
      cardWrap(context, [
        // THE SIGIL IS THE HANDLE. Touching it opens this sentence -- one row
        // at a time -- and everything that edits a term lives in the open row.
        controlChip(
          context,
          button: true,
          semantics: 'Open this sentence',
          hint: 'Opens the sentence, where every term can be said again.',
          onTap: () => widget.onOpen?.call(false),
          child: Text(isFrame ? '▤' : '●', style: labelStyle(context)),
        ),
        if (says != null)
          Text(says, style: bodyStyle(context))
        else ...[
          Text(near, style: bodyStyle(context)),
          // WHICH SIDE IS READING. One containment reads "holds" from the
          // parent and "is held by" from the child; the word on the record is
          // the same record either way, so the reading is what is shown.
          Text(_reads.isEmpty ? 'is stapled to' : _reads, style: bodyStyle(context)),
        ],
        // THE WORD IS THE LINK where it names a record -- "a staple you can
        // only see from one side is half a record" -- and the mark beside it is
        // the way to say the end again, which is the other half.
        cardLink(context, name, () {
          if (farId.isEmpty || host == null) return;
          isFrame ? host.openFrame(farId) : host.openObject(farId);
        }),
        Text(after, style: bodyStyle(context)),
        controlChip(
          context,
          button: true,
          semantics: 'Say $name again',
          hint: 'Points this end at something else, and carries what it says along.',
          onTap: () => widget.onOpen?.call(true),
          child: Text('✎', style: dataStyle(context)),
        ),
      ]),
    );
  }

  Widget _framed(BuildContext context, Widget child, {VoidCallback? onTap}) {
    final framed = Container(
      margin: EdgeInsets.only(bottom: cardPx(context, 'card.gap')),
      padding: EdgeInsets.all(cardPx(context, 'card.gap')),
      decoration: BoxDecoration(
        border: Border.all(
          color: ChronoTheme.of(context).hair,
          width: ChromeScope.of(context).px('chrome.hair'),
        ),
        borderRadius: BorderRadius.circular(ChromeScope.of(context).px('chrome.corner')),
      ),
      child: child,
    );
    return onTap == null
        ? framed
        : InkWell(onTap: onTap, child: framed);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.open) return _atRest(context);
    final host = CardHost.of(context);
    final document = _editor.document;
    final row = _row;
    final far = row.far;
    final farId = far?.id ?? '';
    final frame = document.frames[farId];
    final steer = _belonging ? null : steerStapleKind(_verb, row.near, far);
    // A COORDINATE ONLY WHERE THE SENTENCE HAS ONE. A belonging sentence names
    // a frame and says nothing about where on it either end sits, so it is
    // offered no position field to write one into.
    CoordinateLaw? law;
    if (frame != null && row.positions) {
      try {
        law = _editor.engine.lawOf(farId);
      } on Object {
        law = null;
      }
    }
    final positions = stapleKinds[_verb]?.positions ?? true;
    final implicit = _placement;
    final near = row.near;
    return _framed(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          cardWrap(context, [
            namedAction(
              context,
              'This',
              hint: 'Closes this sentence back to its one line.',
              onTap: () => widget.onOpen?.call(false),
            ),
            // WHICH POINT OF THIS OBJECT the sentence touches.
            SentenceTerm(
              said: near == null ? 'point' : endPoint(near),
              offers: _points,
              hint: 'which point of this object',
              onSaid: near is! ObjectEnd || row.staple == null
                  ? null
                  : (point) => _writeEnd(
                      ObjectEnd(
                        near.object,
                        point: point,
                        offset: near.offset,
                        extra: near.extra,
                      ),
                      near: true,
                    ),
              refusal: implicit
                  ? 'A placement touches this object at its start. Say another sentence to '
                        'name a different point of it.'
                  : 'This end is not this object\'s to move.',
            ),
            // THE VERB, authored. Never a closed drop of species.
            SentenceTerm(
              said: implicit ? 'is placed on' : _verb,
              // A belonging sentence wears the word its own record spells, and
              // that record is not a staple -- so the word is read, not re-said.
              offers: (typed) => [
                for (final verb in verbOffers(document))
                  if (typed.trim().isEmpty || verb.contains(typed.trim().toLowerCase()))
                    (value: verb, label: stapleKinds[verb]?.label ?? verb),
              ],
              hint: 'the word this sentence uses',
              onSaid: row.staple == null ? null : _setVerb,
              refusal: implicit
                  ? 'A placement is the attachment itself, so it wears no word of its own. '
                        'Say another sentence to use one.'
                  : _belonging
                  ? 'This word is how a ${_row.relation?.type} record reads. Unsay it and '
                        'say it again as a sentence to choose the word.'
                  : verbSays(_verb),
            ),
            // THE FAR END, re-sayable. This is the re-frame.
            SentenceTerm(
              said: _nameOf(farId),
              strong: true,
              open: widget.openFar,
              offers: (typed) => _records(context, typed),
              hint: 'Connect to a frame or an object',
              onOpen: farId.isEmpty
                  ? null
                  : () => frame != null ? host.openFrame(farId) : host.openObject(farId),
              // A BELONGING SENTENCE IS STILL A STAPLE, and every end of a
              // staple is an authored term. Only a record that is NOT a staple
              // -- an older kind nothing writes any more -- has an end this
              // card cannot re-say, and that is what the refusal is about.
              onSaid: row.staple == null
                  ? null
                  : (id) => _sayFarEnd(id, isFrame: document.frames.containsKey(id)),
              onCreate: row.staple == null ? null : _create,
              refusal: row.staple != null
                  ? null
                  : 'This is an older ${_row.relation?.type} record rather than a staple. '
                        'Unsay it and say it again as a sentence.',
            ),
            if (far is ObjectEnd)
              SentenceTerm(
                said: 'at its ${endPoint(far)}',
                offers: _points,
                hint: 'which point of that one',
                onSaid: (point) => _writeEnd(
                  ObjectEnd(far.object, point: point, offset: far.offset, extra: far.extra),
                  near: false,
                ),
              ),
            namedAction(
              context,
              'Unsay this',
              hint: 'Takes the sentence off. Undoable, like everything else.',
              onTap: _remove,
            ),
          ]),
          if (_refusal != null) cardNote(context, _refusal!, refusal: true),
          // A CONTEST IS SAID WHERE IT WAS CAUSED, not as a paragraph about the
          // object: the sentence that made it is the one a person corrects.
          for (final contest in contestsOn(
            _editor.staples.resolveObjectExtent(widget.objectId),
            _row,
          ))
            cardNote(context, contest, refusal: true),
          if (steer != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                cardNote(context, steer.why),
                namedAction(
                  context,
                  'Say "${stapleKinds[steer.kind]!.label}" instead',
                  onTap: () => _setVerb(steer.kind),
                ),
              ],
            ),
          if (law != null)
            CoordinateField(
              law: law,
              value: implicit
                  ? Coordinate.fromJson(row.relation?.coordinate)
                  : (far as FrameEnd).position?.coordinate,
              onChanged: (value, _) => _setCoordinate(value),
              disabledReason: positions
                  ? null
                  : 'A ${stapleKinds[_verb]!.label.toLowerCase()} carries no position: the '
                        'boundary is wherever the earlier extent runs out.',
            ),
          if (row.staple case final staple?) Fuzziness(staple: staple, editor: _editor),
          if (row.staple case final staple?)
            if (stapleKinds[_verb]?.carriesRule ?? false)
              FollowingRule(staple: staple, editor: _editor),
        ],
      ),
    );
  }
}

/// THE + THAT STARTS ONE (ISSUES 9.1). Saying the far end writes the sentence,
/// with the verb this row is currently wearing -- so the verb is authored
/// BEFORE the connection exists rather than steered to one word after it does.
class NewSentence extends StatefulWidget {
  const NewSentence({super.key, required this.objectId, required this.editor, this.nearEnd});

  final String objectId;
  final Editor editor;

  /// The near end when the card is not an object's. A frame card says sentences
  /// with the frame as the near end, and this is that end.
  final StapleEnd? nearEnd;

  @override
  State<NewSentence> createState() => _NewSentenceState();
}

class _NewSentenceState extends State<NewSentence> {
  String _verb = '';
  String _near = '', _far = '';

  String _said(Document document) => _verb.isEmpty ? verbOffers(document).first : _verb;

  /// THE DEFAULT POINTS ARE SETTINGS (ISSUES 9.2, the horde of todos). The + row
  /// wrote the WHOLE on both ends, so the only sentence it could say between two
  /// objects was "connected to" and thirteen stapled todos drew nowhere. Which
  /// point each end starts at is authored, not compiled.
  String _point(BuildContext context, String key, String held) =>
      held.isNotEmpty ? held : ChromeScope.of(context).settings.text(key);

  void _say(BuildContext context, String id, {required bool isFrame}) {
    final editor = widget.editor;
    final verb = _said(editor.document);
    final nearPoint = _point(context, 'edit.newPointNear', _near);
    final farPoint = _point(context, 'edit.newPointFar', _far);
    // A FRAME END NAMES NO POINT OF THE FRAME, so the near end says the WHOLE:
    // "this belongs on that sheet, nothing about where" is the affiliation
    // (ruled 9.1), and it is the same claim the minting gesture writes. A start
    // with no instant beside it would be a position nobody said.
    final near =
        widget.nearEnd ??
        ObjectEnd(widget.objectId, point: isFrame ? defaultPoint : nearPoint);
    final far = isFrame
        ? StapleEnd.frame(id)
        : ObjectEnd(id, point: farPoint) as StapleEnd;
    editor.transaction(
      'Say a sentence',
      (d) => putStaple(d, kind: verb, ends: [near, far]).document,
    );
  }

  /// MAKES WHAT NOTHING IS CALLED YET, by kind, inside the sentence being said.
  /// The offers are the registry's own rows -- a frame, and one per catalog
  /// entry -- so a fourth kind is a door with no edit here.
  List<({String label, void Function(String typed) make})> _creates(BuildContext context) => [
    (label: 'Create a new frame', make: (name) => _createFrame(name)),
    for (final entry in objectKinds.entries)
      (
        label: 'Create a new ${entry.value.label}',
        make: (name) => _createObject(entry.key, name),
      ),
  ];

  void _createFrame(String name) {
    final editor = widget.editor;
    final host = CardHost.of(context);
    final frame = Frame(
      id: createId('frame'),
      title: name,
      traits: const ['set', 'group'],
      extra: const {
        'display': {'weight': 'w * 1.5'},
      },
    );
    editor.transaction('New frame $name', (d) => d.put('frames', frame.id, frame));
    _say(context, frame.id, isFrame: true);
    host.openFrame(frame.id);
  }

  void _createObject(String kind, String name) {
    final editor = widget.editor;
    final host = CardHost.of(context);
    final made = editor.newObject(kind, title: name);
    editor.transaction('New ${objectKinds[kind]!.label} $name', (d) => d.put('events', made.id, made));
    _say(context, made.id, isFrame: false);
    host.openObject(made.id);
  }

  @override
  Widget build(BuildContext context) {
    final document = widget.editor.document;
    final nearPoint = _point(context, 'edit.newPointNear', _near);
    final farPoint = _point(context, 'edit.newPointFar', _far);
    // EVERY TERM FROM THE FIRST KEYSTROKE (ISSUES 9.2): "the [start] of this
    // [is] the [end] of [that]" -- what the row shows is what it writes.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        cardWrap(context, [
          Text('+', style: dataStyle(context, color: ChronoTheme.of(context).primary)),
          Text('This', style: labelStyle(context)),
          if (widget.nearEnd == null)
            SentenceTerm(
              said: nearPoint,
              offers: (typed) => [
                for (final point in extentPoints)
                  if (typed.trim().isEmpty || point.contains(typed.trim().toLowerCase()))
                    (value: point, label: point),
              ],
              hint: 'which point of this object',
              onSaid: (point) => setState(() => _near = point),
            ),
          SentenceTerm(
            said: _said(document),
            offers: (typed) => [
              for (final verb in verbOffers(document))
                if (typed.trim().isEmpty || verb.contains(typed.trim().toLowerCase()))
                  (value: verb, label: stapleKinds[verb]?.label ?? verb),
            ],
            hint: 'the word this sentence uses',
            onSaid: (verb) => setState(() => _verb = verb),
            refusal: verbSays(_said(document)),
          ),
          SentenceTerm(
            said: farPoint,
            offers: (typed) => [
              for (final point in extentPoints)
                if (typed.trim().isEmpty || point.contains(typed.trim().toLowerCase()))
                  (value: point, label: point),
            ],
            hint: 'which point of that one',
            onSaid: (point) => setState(() => _far = point),
          ),
        ]),
        // The far term is the one that writes the sentence. Its offers are the
        // document's own records; a name nothing wears is an offer to MAKE it,
        // said here rather than in a widget beside the sentences.
        SentenceTerm(
          said: '',
          open: true,
          offers: (typed) {
            final found = searchConnectables(
              document,
              typed,
              window: cardPx(context, 'card.searchWindow').round(),
              scan: cardPx(context, 'card.searchScan').round(),
              exclude: widget.objectId,
            );
            return [
              for (final hit in found.hits)
                (value: hit.id, label: '${hit.kind == 'frame' ? '▤' : '●'} ${hit.label}'),
            ];
          },
          hint: 'Connect to a frame or an object',
          onSaid: (id) => _say(context, id, isFrame: document.frames.containsKey(id)),
          creates: _creates(context),
        ),
      ],
    );
  }
}

/// Per-staple fuzziness: asymmetric before and after, authored ONLY by this
/// toggle. "About 5ish" and a hard ceiling are different shapes, so one
/// plus-or-minus would flatten the distinction the owner drew -- and depth typed
/// in the coordinate field never implies any of it.
class Fuzziness extends StatelessWidget {
  const Fuzziness({super.key, required this.staple, required this.editor});

  final Relation staple;
  final Editor editor;

  void _write(Spread? spread) {
    final extra = {...staple.extra};
    spread == null ? extra.remove('spread') : extra['spread'] = spread.toJson();
    editor.transaction(
      'Edit fuzziness',
      (d) => d.put('relations', staple.id, staple.copyWith(extra: extra)),
    );
  }

  String _amount(Magnitude? magnitude) => magnitude?.coordinate.levels.firstOrNull?.value ?? '0';

  @override
  Widget build(BuildContext context) {
    final spread = staple.spread;
    Widget side(String label, Magnitude? own, Spread Function(Magnitude) put) => cardWrap(context, [
      Text(label, style: labelStyle(context)),
      CardField(
        value: _amount(own),
        width: cardPx(context, 'card.narrowWidth'),
        mono: true,
        onChanged: (text) => _write(put(durationMagnitude(text, 'minute'))),
      ),
    ]);
    return cardWrap(context, [
      namedToggle(context, 'Fuzzy', spread != null, (on) => _write(on ? const Spread() : null)),
      if (spread != null) ...[
        side('minutes before', spread.before, (m) => Spread(before: m, after: spread.after)),
        side('after', spread.after, (m) => Spread(before: spread.before, after: m)),
      ],
    ]);
  }
}

/// The rule that FOLLOWS an inflection, through THE one repeat editor. A blank
/// repeat is the other preference, stated: the staple partitions and nothing
/// follows.
class FollowingRule extends StatelessWidget {
  const FollowingRule({super.key, required this.staple, required this.editor});

  final Relation staple;
  final Editor editor;

  @override
  Widget build(BuildContext context) {
    final rule = obj(obj(staple.payload)?['rule']) ?? const <String, dynamic>{};
    return RepeatSugar(
      label: 'then repeats',
      rrule: readRRule(rule['rrule']),
      lawOf: (_) => null,
      onChanged: (next) => editor.transaction(
        'Edit the following rule',
        (d) => d.put(
          'relations',
          staple.id,
          staple.withField('payload', {
            ...?obj(staple.payload),
            if (next.isNotEmpty) 'rule': {...rule, 'rrule': next},
          }),
        ),
      ),
    );
  }
}
