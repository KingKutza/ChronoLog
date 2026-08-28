// Observed boundaries: a cycle authored from what was MEASURED, never averaged,
// filled or extrapolated. A lunar month is new moon to new moon, and the second
// one is not the mean of the first and the third.
//
// The series is validated by the model's own reader before it is stored, so a
// list that is not strictly increasing, or whose ids collide, refuses here with
// the reason rather than resolving into a cycle nobody observed. Pasting a list
// is a designed path with the same discipline: the offending LINE is named.

import 'package:flutter/material.dart';

import '../chrome/controls.dart';
import '../core/eras.dart';
import '../core/event_cycle.dart';
import '../core/exact.dart';
import '../core/records.dart';
import 'card_chrome.dart';

/// One authored boundary, as the grid holds it.
typedef BoundaryRow = ({String id, String at, String event});

/// One authored boundary per line: an exact position, optionally preceded by
/// the name it is filed under.
List<BoundaryRow> parseBoundaryList(String text) {
  final rows = <BoundaryRow>[];
  for (final (index, line) in text.split('\n').indexed) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    final parts = [for (final part in trimmed.split(RegExp('[,\t]'))) part.trim()];
    final at = parts.length > 1 ? parts[1] : parts[0];
    try {
      Rational.parse(at);
    } on FormatException {
      throw LawRefusal('Line ${index + 1} ("$trimmed") is not an exact boundary position.');
    }
    rows.add((
      id: parts.length > 1 && parts[0].isNotEmpty ? parts[0] : 'boundary-${rows.length + 1}',
      at: at,
      event: parts.length > 2 ? parts[2] : '',
    ));
  }
  return rows;
}

class BoundarySeriesEditor extends StatefulWidget {
  const BoundarySeriesEditor({
    super.key,
    required this.period,
    required this.onChanged,
    this.frameId,
  });

  final Json? period;
  final String? frameId;
  final void Function(Json? period) onChanged;

  @override
  State<BoundarySeriesEditor> createState() => _BoundarySeriesEditorState();
}

class _BoundarySeriesEditorState extends State<BoundarySeriesEditor> {
  late List<BoundaryRow> _rows = [
    for (final row in asList(widget.period?['boundaries']))
      (
        id: declaredText(asMap(row)?['id']),
        at: declaredText(asMap(row)?['at']),
        event: declaredText(asMap(row)?['event']),
      ),
  ];
  String? _refusal;
  bool _pasting = false;

  /// The model's own reader is the arbiter: what it refuses is not stored.
  void _emit() {
    setState(() {
      if (_rows.isEmpty) {
        _refusal = null;
        return widget.onChanged(null);
      }
      final period = <String, dynamic>{
        ...?widget.period,
        'kind': 'event-defined',
        if (widget.frameId != null) 'frame': widget.frameId,
        'boundaries': [
          for (final row in _rows)
            <String, dynamic>{
              'id': row.id,
              'at': row.at,
              if (row.event.isNotEmpty) 'event': row.event,
            },
        ],
      };
      final read = eventBoundarySeries(period);
      _refusal = read.refusal;
      if (_refusal == null) widget.onChanged(period);
    });
  }

  void _move(int index, int by) {
    final to = index + by;
    if (to < 0 || to >= _rows.length) return;
    _rows.insert(to, _rows.removeAt(index));
    _emit();
  }

  Widget _row(BuildContext context, int index) {
    final row = _rows[index];
    final narrow = cardPx(context, 'card.narrowWidth');
    return Row(
      children: [
        CardField(
          value: row.id,
          width: narrow,
          hint: 'name',
          onChanged: (text) {
            _rows[index] = (id: text, at: row.at, event: row.event);
            _emit();
          },
        ),
        CardField(
          value: row.at,
          mono: true,
          hint: 'observed at (days)',
          onChanged: (text) {
            _rows[index] = (id: row.id, at: text, event: row.event);
            _emit();
          },
        ),
        namedAction(context, 'Earlier', glyph: '▲', onTap: () => _move(index, -1)),
        namedAction(context, 'Later', glyph: '▼', onTap: () => _move(index, 1)),
        namedAction(
          context,
          'Remove',
          glyph: '−',
          onTap: () {
            _rows.removeAt(index);
            _emit();
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Observed boundaries', style: labelStyle(context)),
        for (var index = 0; index < _rows.length; index++) _row(context, index),
        cardWrap(context, [
          namedAction(
            context,
            'Add a boundary',
            glyph: '+ boundary',
            onTap: () {
              _rows.add((id: 'boundary-${_rows.length + 1}', at: '', event: ''));
              _emit();
            },
          ),
          namedAction(context, 'Paste a list', onTap: () => setState(() => _pasting = !_pasting)),
        ]),
        if (_pasting)
          CardField(
            value: '',
            mono: true,
            width: double.infinity,
            hint: 'one boundary per line: name, position',
            lines: cardTunable(ChromeScope.of(context).settings, 'card.textLines').round().toInt(),
            onChanged: (text) {
              try {
                _rows = parseBoundaryList(text);
                _emit();
              } on LawRefusal catch (refusal) {
                setState(() => _refusal = refusal.message);
              }
            },
          ),
        if (_refusal != null) cardNote(context, _refusal!, refusal: true),
      ],
    );
  }
}
