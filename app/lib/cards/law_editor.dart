// The calendar structure IS the coordinate law, so this is one editor, not two.
//
// Two field reports are rulings here. "When I go into wall time there is no
// section to define calendar structure" -- so the editor follows the coordinate
// CAPABILITY, and Wall Time, the frame every derived calendar inherits from, is
// editable like any other. "With Mon,Tue,Batman,Thu,Fri,Sat,Sun I get an error
// telling me I have to define the same number of days" -- so a weekday list is
// authored as a CYCLE, whose seven names are counted against the cycle's own
// length and never against a month's varying day count.
//
// OWN VERSUS INHERITED IS EXPLICIT. Opening this editor on a derived calendar
// shows the law it inherits; only the toggle detaches it. An editor that
// silently forks a declaration the moment it is looked at is how a calendar
// stops tracking the frame it was meant to follow.
//
// THE LAW IS THE ARBITER: every keystroke rebuilds through
// `buildCoordinateStructure`, which constructs a real law, so a refusal arrives
// in the law's own words at authoring time rather than as a blank lens later.
//
// Levels and cycles are ONE editable grid, because they are the same shape: a
// row of named cells, rebuilt whole on every edit.

import 'dart:convert';

import 'package:flutter/material.dart';

import '../chrome/controls.dart';
import '../core/calendar_structure.dart';
import '../core/coordinate_law.dart';
import '../core/eras.dart';
import '../core/records.dart';
import '../session/lens_catalog.dart';
import 'card_chrome.dart';

const JsonEncoder _pretty = JsonEncoder.withIndent('  ');

/// A level is `[name, count, rule, names]`; a cycle is `[name, length, phase,
/// names]`. Four cells either way, which is why one grid serves both.
const List<String> _blank = ['', '', '', ''];

/// How a level's children are counted, in the words a form can show. The
/// registry is the source, so the form can never offer a rule the law refuses.
List<ControlOption> countingRules() => [
  (value: '', label: 'Fixed'),
  (value: countVaries, label: 'Varies'),
  for (final name in registeredTransitions()) (value: name, label: name.split('.').last),
];

class LawEditor extends StatefulWidget {
  const LawEditor({super.key, required this.law, required this.own, required this.onChanged});

  /// The law in force, authored here or inherited from the basis frame.
  final CoordinateLaw? law;

  /// This frame's OWN declaration, or null when it inherits one.
  final Json? own;

  /// The declaration to store: a map to author it here, null to inherit.
  final void Function(Json? declaration) onChanged;

  @override
  State<LawEditor> createState() => _LawEditorState();
}

class _LawEditorState extends State<LawEditor> {
  final List<List<String>> _levels = [], _cycles = [];
  late String _base, _origin, _kind, _text;
  late bool _detached = widget.own != null;
  bool _showText = false;
  String? _refusal, _summary;

  @override
  void initState() {
    super.initState();
    _fill(editableCoordinateStructure(widget.law));
    _text = _pretty.convert(widget.own ?? widget.law?.declaration.toJson() ?? const {});
    _summary = _readSummary(widget.own ?? widget.law?.declaration.toJson());
  }

  void _fill(CoordinateStructure? structure) {
    final levels = [
      for (final row in structure?.levels ?? const <LevelRow>[])
        [row.name, row.count, row.transition, row.names],
    ];
    final cycles = [
      for (final row in structure?.cycles ?? const <CycleRow>[])
        [row.name, row.length, row.phase, row.names],
    ];
    _levels
      ..clear()
      ..addAll(levels);
    _cycles
      ..clear()
      ..addAll(cycles);
    _base = structure?.baseLevel ?? '';
    _origin = structure?.origin ?? '';
    _kind = structure?.kind ?? 'nested';
  }

  String? _readSummary(Json? declaration) {
    try {
      return coordinateStructureSummary(declaration);
    } on Object catch (error) {
      _refusal = refusalText(error);
      return null;
    }
  }

  /// Every edit goes through the builder, so what the preview says and what
  /// would be stored are the same object.
  void _rebuild() {
    setState(() {
      _refusal = null;
      if (!_detached) {
        _summary = _readSummary(widget.law?.declaration.toJson());
        return widget.onChanged(null);
      }
      try {
        final built = buildCoordinateStructure(
          levels: [
            for (final row in _levels)
              (name: row[0], count: row[1], transition: row[2], names: row[3]),
          ],
          cycles: [
            for (final row in _cycles) (name: row[0], length: row[1], phase: row[2], names: row[3]),
          ],
          baseLevel: _base,
          origin: _origin,
          kind: _kind,
          previous: widget.own,
        );
        _text = _pretty.convert(built);
        _summary = coordinateStructureSummary(built);
        widget.onChanged(built);
      } on Object catch (error) {
        _summary = null;
        _refusal = refusalText(error);
      }
    });
  }

  /// The escape hatch a law needs, validated: the declaration as text, read
  /// back into the grid so the two are never two truths.
  void _readText(String source) {
    setState(() {
      try {
        final parsed = jsonDecode(source);
        if (parsed is! Map) throw const LawRefusal('A declaration is an object.');
        final declaration = Json.from(parsed);
        _fill(editableCoordinateStructure(CoordinateLaw.parse(declaration)));
        _refusal = null;
        _summary = coordinateStructureSummary(declaration);
        _detached = true;
        widget.onChanged(declaration);
      } on Object catch (error) {
        _summary = null;
        _refusal = refusalText(error);
      }
    });
  }

  Widget _cell(
    List<List<String>> rows,
    int index,
    int cell,
    String hint, {
    bool narrow = false,
    bool mono = false,
  }) => CardField(
    value: rows[index][cell],
    hint: hint,
    mono: mono,
    width: narrow ? cardPx(context, 'card.narrowWidth') : null,
    onChanged: (text) {
      rows[index][cell] = text;
      _rebuild();
    },
  );

  Widget _act(String label, String glyph, VoidCallback act) => namedAction(
    context,
    label,
    glyph: glyph,
    onTap: () {
      act();
      _rebuild();
    },
  );

  /// One grid: a heading, a row per record, a remove on each, and one add.
  Widget _grid(
    String title,
    List<List<String>> rows,
    String add,
    List<Widget> Function(int index) cells,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: labelStyle(context)),
      for (var index = 0; index < rows.length; index++)
        Row(children: [...cells(index), _act('Remove', '−', () => rows.removeAt(index))]),
      _act(add, add, () => rows.add([..._blank])),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        namedToggle(context, 'Own structure', _detached, (value) {
          _detached = value;
          _rebuild();
        }),
        if (!_detached)
          cardNote(
            context,
            'This frame counts in the structure it inherits. Turn on its own'
            ' structure to change the levels, the cycles or the names here --'
            ' until then, editing the basis frame changes this one too.',
          ),
        _grid('Levels', _levels, '+ level', (index) {
          final row = _levels[index];
          return [
            _cell(_levels, index, 0, 'name', narrow: true),
            // The root level takes neither a count nor a rule: nothing above it
            // states how many of it there are.
            if (index > 0) ...[
              namedChoice(context, '', row[2], countingRules(), (rule) {
                _levels[index][1] = '';
                _levels[index][2] = rule;
                _rebuild();
              }),
              if (row[2].isEmpty) _cell(_levels, index, 1, 'count', narrow: true, mono: true),
            ],
            Flexible(child: _cell(_levels, index, 3, 'names, one per child')),
          ];
        }),
        _grid('Cycles', _cycles, '+ cycle', (index) {
          return [
            _cell(_cycles, index, 0, 'name', narrow: true),
            _cell(_cycles, index, 1, 'length', narrow: true, mono: true),
            _cell(_cycles, index, 2, 'phase', narrow: true, mono: true),
            Flexible(child: _cell(_cycles, index, 3, 'names, one per unit')),
          ];
        }),
        cardTextRow(
          context,
          'Base unit',
          _base,
          (text) {
            _base = text;
            _rebuild();
          },
          hint: 'day',
          width: cardPx(context, 'card.narrowWidth'),
        ),
        cardTextRow(
          context,
          'Origin (days)',
          _origin,
          (text) {
            _origin = text;
            _rebuild();
          },
          hint: '0',
          mono: true,
          width: cardPx(context, 'card.narrowWidth'),
        ),
        if (_refusal != null) cardNote(context, _refusal!, refusal: true),
        if (_summary != null) cardNote(context, _summary!),
        InkWell(
          onTap: () => setState(() => _showText = !_showText),
          child: Text('${_showText ? '▾' : '▸'}  As text', style: labelStyle(context)),
        ),
        if (_showText)
          CardField(
            value: _text,
            mono: true,
            width: double.infinity,
            lines: cardTunable(ChromeScope.of(context).settings, 'card.textLines').round().toInt(),
            onChanged: _readText,
          ),
      ],
    );
  }
}
