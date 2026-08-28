// A frame's card. A frame IS a group (ruled 2026-08-19), so handling -- weight
// formula, zone fill, Strategic promotion, falloff half-distance -- is authored
// here as a group property and never as a lens knob.
//
// THE BASIS GUIDANCE (ISSUES 8.26). "Fresh start: Frames > new frame, name it
// 'work', save, switch to frame work -- and nothing. You have to already know to
// go back and set basis frame to Wall Time." Don's clarification: the model is
// right and the process is good; the GUI is spartan and unclear. So this card
// SAYS what a basis is, offers the standard one as a visible choice, and states
// what is missing while it is missing -- and it wires nothing on its own.
// Nothing is chosen for the author; the choice is merely made legible.
//
// A NEW FRAME WRITES NOTHING UNTIL SAVE. One creation order for one record: the
// blank card holds a draft, Save commits it as one undoable entry.

import 'package:flutter/material.dart';

import '../chrome/controls.dart';
import '../core/calendar_structure.dart';
import '../core/document.dart';
import '../core/eras.dart';
import '../core/exact.dart';
import '../core/math.dart';
import '../core/records.dart';
import '../core/weight.dart';
import '../edit/editor.dart';
import 'boundary_series_editor.dart';
import 'card_factory.dart';
import 'card_chrome.dart';
import 'document_card.dart';
import 'frames_browser.dart';
import 'law_editor.dart';
import 'settings_card.dart';
import 'theme_card.dart';

/// The capabilities a frame may carry, most specific first. Kind is ADDITIVE:
/// choosing one contributes traits and removes none, so an unfamiliar trait an
/// author put on a frame survives every edit made here.
const List<String> frameKinds = //
[
  'calendar',
  'group',
  'importance',
  'state',
  'cycle',
  'line',
  'measure',
  'other',
];

/// What this frame most specifically IS. A state frame carries both `group` and
/// `state`, so it is asked about first.
String frameKindOf(Frame frame) {
  final traits = frame.traits.toSet();
  for (final kind in ['state', 'importance', 'calendar', 'cycle', 'measure', 'group', 'line']) {
    if (traits.contains(kind)) return kind;
  }
  return 'other';
}

/// The group display properties a frame authors: what belonging to this frame
/// does to a member. Data, so adding one is a row and not a branch -- and
/// "inherit" is always the first word, because nothing here encodes a right way.
const List<({String key, String label, Map<String, String> options})> frameHandling = [
  (key: 'zone', label: 'Zone fill', options: {'auto': 'inherit', 'fill': 'fill', 'plain': 'plain'}),
  (
    key: 'strategic',
    label: 'In Strategic',
    options: {'auto': 'by weight', 'show': 'promote', 'hide': 'demote'},
  ),
];

List<String> traitsForKind(String kind, Iterable<String> existing) => kind == 'state'
    ? additiveFrameTraits('group', const ['state'], existing)
    : additiveFrameTraits(kind, const [], existing);

/// Sets a field, or DELETES it when the value is null: an authored identity is
/// stored as an absence, never as a redundant no-op.
Frame writeField(Frame frame, String key, Object? value) => frame.copyWith(
  extra: {
    for (final entry in frame.extra.entries)
      if (entry.key != key) entry.key: entry.value,
    key: ?value,
  },
);

class FrameCard extends StatefulWidget {
  const FrameCard({super.key, this.frameId, this.kind = 'calendar', this.onClose, this.onOpen});

  /// Null for a frame that does not exist yet: nothing is written until Save.
  final String? frameId;
  final String kind;
  final VoidCallback? onClose;

  /// Opens another frame's card -- the basis, a copy just made.
  final void Function(String frameId)? onOpen;

  @override
  State<FrameCard> createState() => _FrameCardState();
}

class _FrameCardState extends State<FrameCard> {
  late String _title, _kind, _color, _basis, _weight, _half;
  final Map<String, String> _handling = {};
  Json? _coordinate, _period;
  bool _dirty = false;
  String? _refusal;

  bool _read = false;

  /// Read once, from the document the chrome is looking at. In
  /// `didChangeDependencies` rather than `initState` because that is where an
  /// inherited scope may first be asked.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_read) return;
    _read = true;
    final frame = widget.frameId == null
        ? null
        : ChromeScope.of(context).editor?.document.frames[widget.frameId];
    final display = obj(frame?.extra['display']) ?? const <String, dynamic>{};
    _kind = frame == null ? widget.kind : frameKindOf(frame);
    _title = frame?.title ?? '';
    _color = declaredText(frame?.extra['color'] ?? display['color']);
    _basis = frame?.basis ?? '';
    _weight = declaredText(display['weight'] ?? defaultWeightForNewFrame(_kind)?.toJson());
    _handling['zone'] = display['zone'] is bool
        ? (display['zone'] == true ? 'fill' : 'plain')
        : 'auto';
    _handling['strategic'] = declaredText(display['strategic']).isEmpty
        ? 'auto'
        : declaredText(display['strategic']);
    _half = declaredText(display['halfDistance']);
    _coordinate = frame?.coordinate;
    _period = obj(frame?.extra['period']);
  }

  void _touch(VoidCallback change) => setState(() {
    change();
    _dirty = true;
  });

  /// The guidance, stated while the gap exists. An unconnected frame is not an
  /// empty calendar, and the difference is exactly what nothing used to say.
  String? get _basisGap {
    if (!frameAuthoringCapabilities(_kind).basis) return null;
    if (_basis.isNotEmpty || _coordinate != null) return null;
    return 'No basis yet. A basis is the frame whose calendar this one counts'
        ' in -- until it has one, this frame shares a clock with nothing, so'
        ' projecting it draws an empty view rather than an empty calendar.'
        ' Choose Wall time to count in the standard calendar, or give this frame'
        ' its own structure below. Nothing is wired for you.';
  }

  Json? get _display {
    final built = <String, dynamic>{
      'weight': resolveAuthoredWeight(_weight),
      if (_handling['zone'] != 'auto') 'zone': _handling['zone'] == 'fill',
      if (_handling['strategic'] != 'auto') 'strategic': _handling['strategic'],
      if (_half.trim().isNotEmpty) 'halfDistance': _half.trim(),
      if (_color.trim().isNotEmpty) 'color': _color.trim(),
    }..removeWhere((_, value) => value == null);
    return built.isEmpty ? null : built;
  }

  void _save(Editor editor) {
    final Json? display;
    try {
      display = _display;
    } on MathRefusal catch (refusal) {
      return setState(() => _refusal = '$refusal');
    }
    final id = widget.frameId ?? createId('frame');
    editor.transaction(widget.frameId == null ? 'New frame' : 'Edit frame', (document) {
      final existing = document.frames[id] ?? Frame(id: id);
      var frame = existing.copyWith(
        title: _title.trim().isEmpty ? null : _title.trim(),
        traits: traitsForKind(_kind, existing.traits),
      );
      frame = writeField(frame, 'basis', _basis.isEmpty ? null : _basis);
      frame = writeField(frame, 'coordinate', _coordinate);
      frame = writeField(frame, 'period', _period);
      frame = writeField(frame, 'display', display);
      return document.put('frames', id, frame);
    });
    setState(() {
      _dirty = false;
      _refusal = editor.refusals.isEmpty ? null : editor.refusals.join(' ');
    });
    if (widget.frameId == null && _refusal == null) widget.onOpen?.call(id);
  }

  /// Every frame that could BE a basis: one that owns a calendar structure.
  /// Windowed, because a workspace may hold five hundred of them.
  Widget _basisPicker(BuildContext context, Document document) {
    final rows = cardTunable(ChromeScope.of(context).settings, 'card.findRows').round().toInt();
    return cardMenu(context, _basis, {
      '': 'None chosen',
      for (final frame in document.frames.values.take(rows))
        if (frame.id != widget.frameId && frame.coordinate != null)
          frame.id: frame.title ?? frame.id,
    }, (id) => _touch(() => _basis = id));
  }

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeScope.of(context);
    final editor = chrome.editor;
    if (editor == null) {
      return CardShell(
        title: 'Frame',
        onClose: widget.onClose,
        primary: [cardNote(context, 'No document is open.', refusal: true)],
      );
    }
    final document = editor.document;
    final id = widget.frameId;
    final frame = id == null ? null : document.frames[id];
    final capabilities = frameAuthoringCapabilities(_kind, frame?.traits ?? const []);
    final gap = _basisGap;
    final law = id == null ? null : editor.engine.lawOf(id);
    return CardShell(
      title: _title.isEmpty ? 'New frame' : _title,
      sigil: id == null ? '+' : '▤',
      dirty: _dirty,
      onClose: widget.onClose,
      foldLabel: 'Structure, handling and boundaries',
      primary: [
        cardTextRow(
          context,
          'Name',
          _title,
          (text) => _touch(() => _title = text),
          hint: 'What this frame is called',
        ),
        cardChoiceRow(context, 'Kind', _kind, {
          for (final kind in frameKinds) kind: kind,
        }, (kind) => _touch(() => _kind = kind)),
        cardRow(context, 'Color', colorField(context, _color, (t) => _touch(() => _color = t))),
        if (capabilities.basis) cardRow(context, 'Basis', _basisPicker(context, document)),
        if (gap != null) cardNote(context, gap),
        if (_refusal != null) cardNote(context, _refusal!, refusal: true),
      ],
      fold: [
        Text('Handling — this frame is a group', style: labelStyle(context)),
        ExpressionField(
          label: 'Display weight',
          source: _weight,
          evaluate: (source) {
            final stored = resolveAuthoredWeight(source);
            return stored == null
                ? 'identity — the field is deleted'
                : 'a member weighing 1 weighs '
                      '${applyWeightFormula(stored, Rational.one).toDecimal(3)}';
          },
          onChanged: (source) => _touch(() => _weight = source),
        ),
        for (final row in frameHandling)
          cardChoiceRow(
            context,
            row.label,
            _handling[row.key] ?? 'auto',
            row.options,
            (value) => _touch(() => _handling[row.key] = value),
          ),
        ExpressionField(
          label: 'Falloff half-distance (days)',
          source: _half,
          evaluate: (source) => source.trim().isEmpty
              ? 'the shipped half-distance'
              : '${evaluateSource(source, const Env())} days',
          onChanged: (source) => _touch(() => _half = source),
        ),
        if (frame != null) cardChips(context, frame.traits),
        if (capabilities.calendarStructure)
          LawEditor(
            key: ValueKey('law:$id:$_basis'),
            law: law,
            own: _coordinate,
            onChanged: (declaration) => _touch(() => _coordinate = declaration),
          ),
        if (capabilities.observedBoundaries)
          BoundarySeriesEditor(
            frameId: id,
            period: _period,
            onChanged: (period) => _touch(() => _period = period),
          ),
      ],
      footer: [
        namedAction(context, 'Save', onTap: () => _save(editor)),
        if (id != null)
          namedAction(
            context,
            'Duplicate',
            hint: 'A deep copy: every staple end and pattern names the copy',
            onTap: () => editor.transaction('Duplicate frame', (d) => duplicateFrame(d, id)),
          ),
        if (id != null)
          namedAction(
            context,
            'Delete',
            hint: 'Undoable — its attachments, staple ends and patterns go with it',
            onTap: () {
              editor.deleteFrame(id);
              widget.onClose?.call();
            },
          ),
      ],
    );
  }
}

// --- Registration -----------------------------------------------------------

Widget _frameBody(BuildContext context, CardRequest request) {
  final host = CardHost.of(context);
  return FrameCard(
    frameId: request.id,
    kind: request.kind ?? 'calendar',
    onClose: host.close,
    onOpen: host.openFrame,
  );
}

Widget _framesBody(BuildContext context, CardRequest request) {
  final host = CardHost.of(context);
  return FramesBrowser(
    onClose: host.close,
    onOpen: host.openFrame,
    onCreate: (kind) => host.factory.open(host.factory.newFrameCard(kind: kind)),
  );
}

/// The card bodies this area registers with [CardFactory]. A class nobody
/// registered renders a stated gap, so this map is what turns these six from
/// gaps into cards -- pass it as `CardFactory(..., bodies: frameCardBodies)`.
const Map<String, CardBody> frameCardBodies = {
  'frame': _frameBody,
  'newFrame': _frameBody,
  'frames': _framesBody,
  'document': _documentBody,
  'settings': _settingsBody,
  'themes': _themesBody,
};

Widget _documentBody(BuildContext context, CardRequest request) {
  final host = CardHost.of(context);
  return DocumentCard(
    onClose: host.close,
    root: host.factory.dataRoot,
    picker: host.factory.picker,
  );
}

Widget _settingsBody(BuildContext context, CardRequest request) =>
    SettingsCard(onClose: CardHost.of(context).close);

/// Apply is a live swap, Save is a file (ISSUES 8.17): the factory carries the
/// swap so the card can offer both verbs and mean them.
Widget _themesBody(BuildContext context, CardRequest request) {
  final host = CardHost.of(context);
  return ThemeCard(onClose: host.close, onApply: host.factory.onTheme, files: host.factory.files);
}
