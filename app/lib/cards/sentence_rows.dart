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

class StapleEditor extends StatelessWidget {
  const StapleEditor({super.key, required this.objectId});

  final String objectId;

  @override
  Widget build(BuildContext context) {
    final editor = CardHost.of(context).editor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        extentSentence(context, editor.engine, editor.staples.resolveObjectExtent(objectId)),
        for (final said in objectSentences(editor, objectId))
          SentenceRow(
            // WHAT THE SENTENCE IS, not which record spells it: one containment
            // is read from both sides and one staple may pierce this object at
            // two of its own points, so the record id alone names two rows.
            key: ValueKey(
              '${said.row.staple?.id ?? said.row.relation?.id ?? 'implicit'}'
              '/${said.row.far?.id ?? ''}/${endPoint(said.row.near)}',
            ),
            objectId: objectId,
            said: said,
            editor: editor,
          ),
        NewSentence(objectId: objectId, editor: editor),
      ],
    );
  }
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
  return cardNote(
    context,
    [
      if (starts == null)
        'Nothing here says when this starts.'
      else
        'This starts at $starts.',
      if (ends == null)
        'Nothing says when it ends, which is a legal thing for a record to say.'
      else
        'It ends at $ends.',
      'Read from ${extent.source}.',
      if (extent.cyclic)
        'These sentences resolve back through this object, so there is no instant to report.',
      for (final contest in extent.overdetermined)
        'Something else also claims its ${contest.role}: ${contest.reason}. Both are kept and '
            'neither is averaged in.',
      for (final contest in extent.unresolved)
        'Its ${contest.role} is claimed by something that resolves nowhere: ${contest.reason}.',
      if (!extent.spread.isZero)
        'It is fuzzy by ${extent.spread.before.toDecimal(3)} of a day before and '
            '${extent.spread.after.toDecimal(3)} after.',
    ].join(' '),
    refusal: extent.cyclic,
  );
}

/// ONE SENTENCE, in terms you can say again.
class SentenceRow extends StatefulWidget {
  const SentenceRow({
    super.key,
    required this.objectId,
    required this.said,
    required this.editor,
  });

  final String objectId;
  final SaidRow said;
  final Editor editor;

  @override
  State<SentenceRow> createState() => _SentenceRowState();
}

class _SentenceRowState extends State<SentenceRow> {
  String? _refusal;

  Editor get _editor => widget.editor;
  ConnectionRow get _row => widget.said.row;
  String get _verb => _row.kind ?? widget.said.verb;

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

  @override
  Widget build(BuildContext context) {
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
    return Container(
      margin: EdgeInsets.only(bottom: cardPx(context, 'card.gap')),
      padding: EdgeInsets.all(cardPx(context, 'card.gap')),
      decoration: BoxDecoration(
        border: Border.all(
          color: ChronoTheme.of(context).hair,
          width: ChromeScope.of(context).px('chrome.hair'),
        ),
        borderRadius: BorderRadius.circular(ChromeScope.of(context).px('chrome.corner')),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          cardWrap(context, [
            Text('This', style: labelStyle(context)),
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
              offers: (typed) => _records(context, typed),
              hint: 'Connect to a frame or an object',
              onOpen: farId.isEmpty
                  ? null
                  : () => frame != null ? host.openFrame(farId) : host.openObject(farId),
              onSaid: _belonging
                  ? null
                  : (id) => _sayFarEnd(id, isFrame: document.frames.containsKey(id)),
              onCreate: _belonging ? null : _create,
              refusal: _belonging
                  ? 'This is an older ${_row.relation?.type} record rather than a staple. '
                        'Unsay it and say it again as a sentence.'
                  : null,
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
              glyph: '✕',
              hint: 'Takes the sentence off. Undoable, like everything else.',
              onTap: _remove,
            ),
          ]),
          if (_refusal != null) cardNote(context, _refusal!, refusal: true),
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
  const NewSentence({super.key, required this.objectId, required this.editor});

  final String objectId;
  final Editor editor;

  @override
  State<NewSentence> createState() => _NewSentenceState();
}

class _NewSentenceState extends State<NewSentence> {
  String _verb = '';

  String _said(Document document) => _verb.isEmpty ? verbOffers(document).first : _verb;

  void _say(String id, {required bool isFrame}) {
    final editor = widget.editor;
    final verb = _said(editor.document);
    final near = ObjectEnd(widget.objectId, point: defaultPoint);
    final far = isFrame ? StapleEnd.frame(id) : ObjectEnd(id, point: defaultPoint) as StapleEnd;
    editor.transaction(
      'Say a sentence',
      (d) => putStaple(d, kind: verb, ends: [near, far]).document,
    );
  }

  void _create(String name) {
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
    _say(frame.id, isFrame: true);
    host.openFrame(frame.id);
  }

  @override
  Widget build(BuildContext context) {
    final document = widget.editor.document;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        cardWrap(context, [
          Text('+', style: dataStyle(context, color: ChronoTheme.of(context).primary)),
          Text('This', style: labelStyle(context)),
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
          onSaid: (id) => _say(id, isFrame: document.frames.containsKey(id)),
          onCreate: _create,
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
