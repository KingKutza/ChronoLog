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
import '../core/eras.dart';
import '../core/records.dart';
import '../core/recurrence_end.dart';
import '../core/rrule.dart';
import '../core/staples.dart';
import '../edit/editor.dart';
import 'card_chrome.dart';
import 'card_factory.dart';

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

/// THE SERIES' EXCLUSIONS, spoken as sentences.
///
/// ISSUES (8.31, evening, Don live): "when I set lunch to repeats every day I
/// had no clear way to put in an except weekends and holidays." The model
/// already holds both readings; what was missing was the authoring surface. So
/// there are exactly two sentences here, and they compile to the same NOT the
/// projection algebra already reads:
///
///   EXCEPT MEMBERS OF a frame -- a LIVE reference to another frame's events,
///   resolved at projection time, so adding a holiday changes the series with
///   no edit to the series and removing one puts the meeting back.
///
///   EXCEPT EVERY TIME THAT MATCHES a selector -- the {cycle, value} form the
///   position selectors already speak, read against the frame's OWN declared
///   cycles, so "Saturday" means whatever THAT frame says a Saturday is. No new
///   vocabulary, and no closed set of selector kinds.
///
/// OVERSCALE: the frames a series may be excluded by are never enumerated. The
/// offers are windowed and a find narrows them, exactly as the far-end
/// typeahead does.
class SeriesExclusions extends StatefulWidget {
  const SeriesExclusions({
    super.key,
    required this.pattern,
    required this.editor,
    this.frameId,
  });

  final Pattern pattern;
  final Editor editor;

  /// The frame this series counts in -- whose declarations a selector reads,
  /// and which cannot exclude the series, since its own occurrences are among
  /// the facts it holds.
  final String? frameId;

  @override
  State<SeriesExclusions> createState() => _SeriesExclusionsState();
}

class _SeriesExclusionsState extends State<SeriesExclusions> {
  String _find = '', _cycle = '', _value = '';

  Json get _exclude => obj(widget.pattern.extra['exclude']) ?? const <String, dynamic>{};

  List<String> get _frames => [
    for (final id in asList(_exclude['frames']))
      if (str(id) case final String named) named,
  ];

  List<Json> get _selectors => [
    for (final row in asList(_exclude['selectors']))
      if (obj(row) case final Json selector) selector,
  ];

  /// One write for both sentences. An exclusion of nothing is stored as
  /// nothing: an empty list left behind is a claim nobody made.
  void _put({List<String>? frames, List<Json>? selectors}) {
    final next = <String, dynamic>{
      ..._exclude,
      'frames': frames ?? _frames,
      'selectors': selectors ?? _selectors,
    }..removeWhere((_, value) => value is List && value.isEmpty);
    widget.editor.transaction(
      'Edit the series exclusions',
      (d) => d.put(
        'patterns',
        widget.pattern.id,
        widget.pattern.withField('exclude', next.isEmpty ? null : next),
      ),
    );
    setState(() => _find = '');
  }

  CoordinateLaw? get _law {
    final frame = widget.frameId;
    if (frame == null) return null;
    try {
      return widget.editor.engine.lawOf(frame);
    } on Object {
      return null;
    }
  }

  String _titleOf(String id) => widget.editor.document.frames[id]?.title ?? id;

  /// The frames this series can be excluded by: not a measure, which holds
  /// magnitudes rather than events; not the frame the series itself counts in,
  /// whose facts include this very series; not one already excluded. Windowed,
  /// with the remainder reported as a lower bound.
  ({List<Frame> offers, int more}) _candidates() {
    final needle = _find.trim().toLowerCase();
    final window = cardPx(context, 'card.searchWindow').round();
    final taken = _frames.toSet();
    final offers = <Frame>[];
    var more = 0;
    for (final frame in widget.editor.document.frames.values) {
      if (frame.id == widget.frameId || taken.contains(frame.id)) continue;
      if (frame.traits.contains('measure')) continue;
      final title = frame.title ?? frame.id;
      if (needle.isNotEmpty && !title.toLowerCase().contains(needle)) continue;
      offers.length < window ? offers.add(frame) : more += 1;
    }
    return (offers: offers, more: more);
  }

  @override
  Widget build(BuildContext context) {
    final found = _candidates();
    final law = _law;
    final cycles = law?.cycles() ?? const <Cycle>[];
    final cycle = _cycle.isEmpty ? (cycles.firstOrNull?.name ?? '') : _cycle;
    final names = law?.cycleNames(cycle) ?? const <String>[];
    final value = _value.isEmpty ? (names.firstOrNull ?? '') : _value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final id in _frames)
          cardWrap(context, [
            Text('Except members of', style: labelStyle(context)),
            cardLink(context, _titleOf(id), () => CardHost.of(context).openFrame(id)),
            namedAction(
              context,
              'Remove',
              glyph: '✕',
              hint: 'The series keeps those days again.',
              onTap: () => _put(frames: [for (final kept in _frames) if (kept != id) kept]),
            ),
          ]),
        for (final selector in _selectors)
          cardWrap(context, [
            Text(
              'Except every time that matches ${str(selector['cycle']) ?? ''}'
              ' ${declaredText(selector['value'])}',
              style: labelStyle(context),
            ),
            namedAction(
              context,
              'Remove',
              glyph: '✕',
              hint: 'The series keeps those times again.',
              onTap: () => _put(
                selectors: [
                  for (final kept in _selectors)
                    if (kept != selector) kept,
                ],
              ),
            ),
          ]),
        cardWrap(context, [
          for (final frame in found.offers)
            namedAction(
              context,
              'Except members of ${frame.title ?? frame.id}',
              hint: 'A live reference: what that frame holds is what is skipped.',
              onTap: () => _put(frames: [..._frames, frame.id]),
            ),
          if (found.offers.isEmpty && _find.trim().isNotEmpty)
            cardNote(context, 'No frame here is called that.'),
          CardField(
            value: _find,
            hint: 'Find a frame to except…',
            width: cardPx(context, 'card.narrowWidth') * 2,
            onChanged: (text) => setState(() => _find = text),
          ),
        ]),
        if (found.more > 0) cardNote(context, '+${found.more} more — narrow the find.'),
        if (cycles.isNotEmpty)
          cardWrap(context, [
            Text('Except every time that matches', style: labelStyle(context)),
            cardMenu(
              context,
              cycle,
              {for (final declared in cycles) declared.name: declared.name},
              (picked) => setState(() {
                _cycle = picked;
                _value = '';
              }),
            ),
            if (names.isEmpty)
              CardField(
                value: value,
                mono: true,
                width: cardPx(context, 'card.narrowWidth'),
                onChanged: (text) => setState(() => _value = text),
              )
            else
              cardMenu(
                context,
                value,
                {for (final name in names) name: name},
                (picked) => setState(() => _value = picked),
              ),
            namedAction(
              context,
              'Except these',
              hint: 'Read against this frame\'s own declarations, never a borrowed calendar.',
              onTap: value.isEmpty
                  ? null
                  : () => _put(
                      selectors: [
                        ..._selectors,
                        // The selector NAMES THE FRAME whose declarations it is
                        // read against: "Saturday" is whatever that frame says
                        // a Saturday is, and a sentence that did not say which
                        // frame would be borrowing someone else's calendar.
                        {'cycle': cycle, 'value': value, if (widget.frameId != null) 'frame': widget.frameId},
                      ],
                    ),
            ),
          ]),
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
