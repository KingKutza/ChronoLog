// THE PLACEMENT INTERFACE. No staple is special, "start time" included.
//
// Owner's ruling (8.20): "Staples GUI in New Event Card is seperated from start
// date and time GUI ... This is bad because it treats the Start time as
// special, when no staple should be special ... Further, the Staple is not
// interfacing with the frame, or another event or other object. This is fatle
// as the point and purpose of a staple is to connect two things at a point."
// So every row here is one shape -- the implicit placement, an authored object
// staple, a series staple, an end staple -- and its coordinate is the one
// variable-precision field, never a date beside a time.
//
// BOTH ENDS. `effectiveObjectStaples` finds this object at whichever end names
// it, so a connection authored from the other side appears here too, and every
// far label is a LINK to that record's own card: "a staple you can only see
// from one side is half a record."
//
// STEERING, NOT REFUSAL (ISSUES 8.26). A kind selects a DERIVATION. When the
// chosen kind's derivation cannot author what this pair of ends means, the row
// offers the kind that can, in the registry's own labels, instead of failing at
// save time with "Ends here cannot connect an event to another object."

import 'package:flutter/material.dart';

import '../chrome/controls.dart';
import '../core/coordinate_law.dart';
import '../core/document.dart';
import '../core/exact.dart';
import '../core/projection.dart';
import '../core/records.dart';
import '../core/recurrence_end.dart';
import '../core/rrule.dart';
import '../core/staples.dart';
import '../edit/editor.dart';
import '../lens/theme.dart';
import 'card_chrome.dart';
import 'card_factory.dart';
import 'connection_picker.dart';
import 'coordinate_field.dart';

/// What the chosen kind cannot author, and which registered kind can.
typedef KindSteer = ({String kind, String why});

/// Every registered kind by its own label -- the vocabulary a kind menu shows.
Map<String, String> stapleKindLabels() => {
  for (final entry in stapleKinds.entries) entry.key: entry.value.label,
};

/// The named points of an extent the substrate itself reads. A point the author
/// invented carries its own offset instead and is left as typed.
const List<String> extentPoints = ['start', 'end', 'midpoint'];

/// THE ONE STEERING RULE, pure and testable.
///
/// A kind whose derivation is inert for this pair of ends is a connection that
/// will silently do nothing, which is exactly the field report: an author
/// reaching for "Ends here" to PLACE an object gets no event and "start time is
/// null". Each case names the kind that authors the SAME connection and says
/// why in the registry's own words. Nothing is refused -- the author may keep
/// what they chose, because direction and meaning are theirs.
KindSteer? steerStapleKind(String kind, StapleEnd? near, StapleEnd? far) {
  final registered = stapleKinds[kind];
  if (registered == null || near == null || far == null) return null;
  final ends = [near, far];
  final series = ends.any((end) => end is SeriesEnd);
  final frames = ends.whereType<FrameEnd>().length;
  final objects = ends.whereType<ObjectEnd>().length;
  final anchor = stapleKinds['anchor']!.label;
  KindSteer to(String why) => (kind: 'anchor', why: why);
  if (kind == 'correspondence' && frames < 2) {
    return to(
      'A correspondence joins two frames. This pair names an object, which "$anchor" connects.',
    );
  }
  if (kind == 'succession' && objects > 0) {
    return to(
      'A succession is the adjacency between two eras and carries no position. To place this object, use "$anchor".',
    );
  }
  if (registered.partitions && !series && objects > 0 && kind != 'end') {
    return to(
      '"${registered.label}" partitions a series\' rules, and no series is named here. "$anchor" places the object.',
    );
  }
  // `end` is `anchors: false` by law -- it records when something finished and
  // never relocates it. Reaching for it to place an object is the 8.26 report.
  if (kind == 'end' && !series && objects > 0) {
    return to(
      '"${registered.label}" records where this ends; it does not place it. "$anchor" places it at the same point.',
    );
  }
  return null;
}

class StapleEditor extends StatelessWidget {
  const StapleEditor({super.key, required this.objectId});

  final String objectId;

  @override
  Widget build(BuildContext context) {
    final editor = CardHost.of(context).editor;
    final staples = editor.staples;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _extent(context, editor.engine, staples.resolveObjectExtent(objectId)),
        for (final row in staples.effectiveObjectStaples(objectId))
          _ConnectionRow(
            key: ValueKey(row.staple?.id ?? row.relation?.id ?? 'implicit'),
            objectId: objectId,
            row: row,
            editor: editor,
          ),
        _AddConnection(objectId: objectId, editor: editor),
        _Containment(objectId: objectId, editor: editor),
      ],
    );
  }

  /// The derived extent: where the connections actually put this object, in the
  /// law's own text, with provenance. Overdetermined and unresolved connections
  /// are LISTED, never averaged and never hidden -- an average of contradictory
  /// anchors is a third position nobody wrote.
  Widget _extent(BuildContext context, ProjectionEngine engine, Extent extent) {
    final frame = extent.frame;
    String at(Rational? days) => days == null || frame == null
        ? 'unstated'
        : coordinateText(
            Coordinate.fromJson(engine.daysCoordinate(frame, days)),
            engine.lawOf(frame),
          );
    return cardNote(
      context,
      [
        'Starts ${at(extent.startDays)} · ends ${at(extent.endDays)} · from ${extent.source}',
        if (extent.cyclic)
          'These connections resolve back through this object. There is no instant to report.',
        for (final contest in extent.overdetermined)
          'Also claims ${contest.role}: ${contest.reason} — reported, never averaged in.',
        for (final contest in extent.unresolved) 'Unresolved ${contest.role}: ${contest.reason}',
        if (!extent.spread.isZero)
          'Fuzzy by ${extent.spread.before.toDecimal(3)} before and '
              '${extent.spread.after.toDecimal(3)} after, in days.',
      ].join('\n'),
      refusal: extent.cyclic,
    );
  }
}

/// One connection, in the one row shape every source of one wears.
class _ConnectionRow extends StatelessWidget {
  const _ConnectionRow({
    super.key,
    required this.objectId,
    required this.row,
    required this.editor,
  });

  final String objectId;
  final ConnectionRow row;
  final Editor editor;

  String get _kind => row.kind ?? 'anchor';

  /// The staple with one end replaced, written WHOLE -- a field-by-field edit
  /// would leave a stale claim nobody authored.
  void _writeEnd(StapleEnd next, {required bool near}) {
    final staple = row.staple;
    if (staple == null) return;
    final index = staple.endIndexOf(objectId);
    final target = near ? index : 1 - index;
    editor.transaction(
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
    final relation = row.relation;
    if (relation != null) {
      // The implicit placement is edited IN PLACE. Clearing it clears the
      // coordinate and KEEPS the membership -- the engine's coordinate-less
      // placement then applies, and no second contradicting record is minted.
      final extra = {...relation.extra};
      value == null ? extra.remove('coordinate') : extra['coordinate'] = value.toJson();
      return editor.transaction(
        'Edit placement',
        (document) => document.put('relations', relation.id, relation.copyWith(extra: extra)),
      );
    }
    final far = row.far;
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

  void _setKind(String kind) {
    final staple = row.staple;
    if (staple == null) return;
    editor.transaction(
      'Change connection kind',
      (d) => d.put('relations', staple.id, staple.withField('kind', kind)),
    );
  }

  Widget _points(
    BuildContext context,
    StapleEnd? end, {
    required bool near,
    required String lead,
  }) => cardMenu(
    context,
    endPoint(end),
    {for (final point in extentPoints) point: '$lead $point'},
    end is! ObjectEnd || (near && row.staple == null)
        ? null
        : (point) => _writeEnd(
            ObjectEnd(end.object, point: point, offset: end.offset, extra: end.extra),
            near: near,
          ),
    hint: 'The implicit placement is the object\'s own attachment.',
  );

  @override
  Widget build(BuildContext context) {
    final host = CardHost.of(context);
    final document = editor.document;
    final far = row.far;
    final steer = steerStapleKind(_kind, row.near, far);
    final farId = far?.id ?? '';
    final frame = document.frames[farId];
    final label = frame != null
        ? (frame.title ?? farId)
        : str(document.events[farId]?.payload?['title']) ?? farId;
    final law = frame == null ? null : editor.engine.lawOf(farId);
    final positions = stapleKinds[_kind]?.positions ?? true;
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
            cardMenu(
              context,
              _kind,
              stapleKindLabels(),
              row.staple == null ? null : _setKind,
              hint: 'The implicit placement has no kind to change.',
            ),
            _points(context, row.near, near: true, lead: 'this object\'s'),
            Text('↔', style: dataStyle(context)),
            cardLink(context, label, () {
              if (frame != null) return host.openFrame(farId);
              if (document.events.containsKey(farId)) host.openObject(farId);
            }),
            if (far is ObjectEnd) _points(context, far, near: false, lead: 'at its'),
            if (row.implicit) Text('(placement)', style: labelStyle(context)),
            namedAction(
              context,
              'Remove',
              glyph: '✕',
              onTap: () {
                final staple = row.staple;
                staple == null
                    ? _setCoordinate(null)
                    : editor.transaction('Remove connection', (d) => removeStaple(d, staple.id));
              },
            ),
          ]),
          if (steer != null)
            cardWrap(context, [
              Flexible(child: cardNote(context, steer.why)),
              namedAction(
                context,
                'Use ${stapleKinds[steer.kind]!.label}',
                onTap: () => _setKind(steer.kind),
              ),
            ]),
          if (law != null)
            CoordinateField(
              law: law,
              value: row.implicit
                  ? Coordinate.fromJson(row.relation?.coordinate)
                  : (far as FrameEnd).position?.coordinate,
              onChanged: (value, _) => _setCoordinate(value),
              disabledReason: positions
                  ? null
                  : 'A ${stapleKinds[_kind]!.label.toLowerCase()} carries no position: the '
                        'boundary is wherever the earlier extent runs out.',
            ),
          if (row.staple != null) _Fuzzy(staple: row.staple!, editor: editor),
          if (row.staple != null && (stapleKinds[_kind]?.carriesRule ?? false))
            _FollowingRule(staple: row.staple!, editor: editor),
        ],
      ),
    );
  }
}

/// Per-staple fuzziness: asymmetric before and after, authored ONLY by this
/// toggle. "About 5ish" and a hard ceiling are different shapes, so one
/// plus-or-minus would flatten the distinction the owner drew -- and depth typed
/// in the coordinate field never implies any of it.
class _Fuzzy extends StatelessWidget {
  const _Fuzzy({required this.staple, required this.editor});

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
class _FollowingRule extends StatelessWidget {
  const _FollowingRule({required this.staple, required this.editor});

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

/// A new connection: pick the far end, and the registry says what kind can
/// author it. No kind control sits in the primary path -- the row that appears
/// carries its own kind menu, and the steering rule already knows which kind a
/// pair admits, so choosing one up front only invites the refusal this whole
/// module exists to retire.
class _AddConnection extends StatelessWidget {
  const _AddConnection({required this.objectId, required this.editor});

  final String objectId;
  final Editor editor;

  @override
  Widget build(BuildContext context) => ConnectionPicker(
    document: editor.document,
    exclude: objectId,
    hint: 'Connect to a frame or an object',
    onPicked: (far) {
      final near = ObjectEnd(objectId, point: 'start');
      final other = far.kind == 'frame'
          ? StapleEnd.frame(far.id)
          : ObjectEnd(far.id, point: 'start') as StapleEnd;
      editor.transaction(
        'Connect to ${far.label}',
        (d) => putStaple(
          d,
          kind: steerStapleKind('anchor', near, other)?.kind ?? 'anchor',
          ends: [near, other],
        ).document,
      );
    },
  );
}

/// Containment, which passes no judgment: any object may hold any objects,
/// multi-parent and cyclic shapes included. This is the authoring surface the
/// model shipped without -- ISSUES 8.26: "containment is write-only-by-code".
class _Containment extends StatelessWidget {
  const _Containment({required this.objectId, required this.editor});

  final String objectId;
  final Editor editor;

  @override
  Widget build(BuildContext context) {
    final host = CardHost.of(context);
    final indexes = editor.engine.indexes;
    Widget side(String label, List<String> ids, bool holds) {
      void set(String other, bool contained) =>
          editor.setContains(holds ? objectId : other, holds ? other : objectId, contained);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          cardWrap(context, [
            Text(label, style: labelStyle(context)),
            for (final id in ids) ...[
              cardLink(
                context,
                str(editor.document.events[id]?.payload?['title']) ?? id,
                () => host.openObject(id),
              ),
              namedAction(context, 'Release', glyph: '✕', onTap: () => set(id, false)),
            ],
            if (ids.isEmpty) Text('nothing yet', style: labelStyle(context)),
          ]),
          ConnectionPicker(
            document: editor.document,
            exclude: objectId,
            frames: false,
            hint: holds ? 'Hold another object' : 'Put this inside an object',
            onPicked: (hit) => set(hit.id, true),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        side('Holds', indexes.childrenOf(objectId), true),
        side('Held by', indexes.parentsOf(objectId), false),
      ],
    );
  }
}

/// An RRULE head as a map of strings, from wherever it was stored.
RRule readRRule(Object? source) => {
  for (final entry in (obj(source) ?? const <String, dynamic>{}).entries)
    entry.key: '${entry.value}',
};

/// THE repeat editor: FREQ, interval, weekday sugar and the two ways a rule can
/// stop. ONE derivation, read by the object card's recurrence row and by the
/// rule that follows an inflection staple -- two surfaces authoring the same
/// rule head could only disagree.
///
/// COUNT and UNTIL are mutually exclusive and the unused one is not shown
/// holding a value it is not using. Weekday labels come from the governing
/// law's own weekday cycle, so a renamed seven-name cycle reads in its own
/// names. A pattern this sugar cannot say is ROADMAP #5's one-math surface, and
/// the row says so rather than pretending a dropdown covers it.
class RepeatSugar extends StatelessWidget {
  const RepeatSugar({
    super.key,
    required this.rrule,
    required this.onChanged,
    required this.lawOf,
    this.label = 'Repeats',
  });

  final RRule rrule;
  final void Function(RRule next) onChanged;

  /// The weekday vocabulary, or null when this site has no governing law.
  final List<String>? Function(BuildContext context) lawOf;

  final String label;

  static const List<String> weekdayCodes = ['SU', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA'];
  static const Map<String, String> frequencies = {
    '': 'never',
    'DAILY': 'daily',
    'WEEKLY': 'weekly',
    'MONTHLY': 'monthly',
    'YEARLY': 'yearly',
  };

  @override
  Widget build(BuildContext context) {
    final frequency = rrule['FREQ'] ?? '';
    final mode = recurrenceEndMode(rrule);
    final byDay = (rrule['BYDAY'] ?? '').split(',').where((code) => code.isNotEmpty).toSet();
    final names = lawOf(context) ?? weekdayCodes;
    void set(String key, String value) => onChanged(RRule.of(rrule)..[key] = value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        cardRow(
          context,
          label,
          cardWrap(context, [
            cardMenu(
              context,
              frequency,
              frequencies,
              (picked) => picked.isEmpty ? onChanged(const {}) : set('FREQ', picked),
            ),
            if (frequency.isNotEmpty) ...[
              Text('every', style: labelStyle(context)),
              CardField(
                value: rrule['INTERVAL'] ?? '1',
                mono: true,
                width: cardPx(context, 'card.narrowWidth'),
                onChanged: (text) => set('INTERVAL', text),
              ),
            ],
          ]),
        ),
        if (frequency == 'WEEKLY')
          cardRow(
            context,
            'On',
            cardWrap(context, [
              for (final (index, code) in weekdayCodes.indexed)
                namedToggle(
                  context,
                  index < names.length ? names[index] : code,
                  byDay.contains(code),
                  (_) => set(
                    'BYDAY',
                    [
                      for (final other in weekdayCodes)
                        if (other == code ? !byDay.contains(other) : byDay.contains(other)) other,
                    ].join(','),
                  ),
                ),
            ]),
          ),
        if (frequency.isNotEmpty)
          cardRow(
            context,
            'Ends',
            cardWrap(context, [
              cardMenu(
                context,
                mode.name,
                {for (final option in RecurrenceEnd.values) option.name: option.name},
                (picked) => onChanged(
                  applyRecurrenceEnd(
                    rrule,
                    mode: recurrenceEndNamed(picked),
                    count: rrule['COUNT'],
                    until: recurrenceUntilDate(rrule['UNTIL']),
                  ),
                ),
              ),
              if (mode == RecurrenceEnd.count)
                CardField(
                  value: rrule['COUNT'] ?? '$countMinimum',
                  mono: true,
                  width: cardPx(context, 'card.narrowWidth'),
                  onChanged: (text) =>
                      onChanged(applyRecurrenceEnd(rrule, mode: RecurrenceEnd.count, count: text)),
                )
              else if (mode == RecurrenceEnd.until)
                CardField(
                  value: recurrenceUntilDate(rrule['UNTIL']),
                  mono: true,
                  onChanged: (text) =>
                      onChanged(applyRecurrenceEnd(rrule, mode: RecurrenceEnd.until, until: text)),
                )
              else
                Text('until a staple cuts it', style: labelStyle(context)),
            ]),
          ),
        if (frequency.isNotEmpty)
          cardNote(
            context,
            'A pattern this sugar cannot say — "every odd day of every even month" — '
            'is authored in the one math, not here.',
          ),
      ],
    );
  }
}
