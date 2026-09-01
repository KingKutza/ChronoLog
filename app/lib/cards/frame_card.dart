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
//
// NO KINDS, ONLY TRAITS (ISSUES 9.1): "The frames card still has calendar state
// and group buttons, which looks a lot like an enum to me." It was one. Frames
// are groups and kinds are TRAIT BUNDLES, not species, so the card authors
// TRAITS -- chips you add and take off -- and the bundles it OFFERS are read
// from the document's own frames. A workspace whose frames wear a bundle nobody
// wrote into this file offers it; a bundle nothing wears is not offered. The
// create door mints A FRAME, and what it is, is said here.
//
// A NEW FRAME WRITES NOTHING UNTIL SAVE, AND A NAMED DRAFT NEVER DIES SILENTLY
// (ISSUES 9.1). Don named and coloured a frame and the journal held no `New
// frame` transaction: the draft died with the card. The card wears the shared
// [CardDraft] contract -- the same one the object card keeps -- so the X does
// whatever `card.closeVerb` names and the tile going away underneath does the
// same thing.

import 'package:flutter/material.dart';

import '../chrome/controls.dart';
import '../core/calendar_structure.dart';
import '../core/coordinate_law.dart';
import '../core/document.dart';
import '../core/eras.dart';
import '../core/exact.dart';
import '../core/math.dart';
import '../core/records.dart';
import '../core/weight.dart';
import '../edit/editor.dart';
import '../lens/theme.dart';
import '../session/settings.dart';
import 'boundary_series_editor.dart';
import 'card_factory.dart';
import 'card_chrome.dart';
import 'document_card.dart';
import 'frames_browser.dart';
import 'law_editor.dart';
import 'settings_card.dart';
import 'theme_card.dart';

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

/// The bundles this document ITSELF exhibits, commonest first, with what wears
/// each one counted. Derived, never listed: the offers are what the workspace
/// is already made of, so an authored bundle nobody in this file imagined is
/// offered the moment a frame wears it.
List<({List<String> traits, int worn})> frameStartingBundles(Document document) {
  final counts = <String, int>{};
  final bundles = <String, List<String>>{};
  for (final frame in document.frames.values) {
    final traits = [...frame.traits]..sort();
    if (traits.isEmpty) continue;
    final key = traits.join(' ');
    counts[key] = (counts[key] ?? 0) + 1;
    bundles[key] = traits;
  }
  final keys = counts.keys.toList()
    ..sort((left, right) {
      final by = counts[right]!.compareTo(counts[left]!);
      return by != 0 ? by : left.compareTo(right);
    });
  return [for (final key in keys) (traits: bundles[key]!, worn: counts[key]!)];
}

/// The traits a bundle of words parses to. The one reader for a seed written as
/// a setting and for a bundle read off a frame.
List<String> traitWords(String written) => [
  for (final word in written.split(RegExp(r'[\s,]+')))
    if (word.trim().isNotEmpty) word.trim(),
];

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
  const FrameCard({super.key, this.frameId, this.kind, this.onClose, this.onOpen});

  /// Null for a frame that does not exist yet: nothing is written until Save.
  final String? frameId;

  /// A SEED for a new frame's traits, never a species. Absent, the card reads
  /// the authored starting bundle.
  final String? kind;

  final VoidCallback? onClose;

  /// Opens another frame's card -- the basis, a copy just made.
  final void Function(String frameId)? onOpen;

  @override
  State<FrameCard> createState() => _FrameCardState();
}

class _FrameCardState extends State<FrameCard> {
  late String _title, _color, _basis, _weight, _half;
  late List<String> _traits;
  final Map<String, String> _handling = {};
  Json? _coordinate, _period;
  bool _dirty = false;
  String? _refusal;

  bool _read = false;

  /// Held for `dispose`, where an inherited scope may no longer be asked. The
  /// draft contract has to be keepable at that moment: the tile going away is
  /// one of the doors a draft can leave by.
  Editor? _held;
  Settings? _settings;

  /// Read once, from the document the chrome is looking at. In
  /// `didChangeDependencies` rather than `initState` because that is where an
  /// inherited scope may first be asked.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _held = ChromeScope.of(context).editor;
    _settings = ChromeScope.of(context).settings;
    if (_read) return;
    _read = true;
    final frame = widget.frameId == null ? null : _held?.document.frames[widget.frameId];
    final display = obj(frame?.extra['display']) ?? const <String, dynamic>{};
    _traits = frame != null
        ? [...frame.traits]
        : additiveFrameTraits(
            '',
            traitWords(widget.kind ?? _settings?.text('card.newFrameTraits') ?? ''),
          );
    _title = frame?.title ?? '';
    _color = declaredText(frame?.extra['color'] ?? display['color']);
    _basis = frame?.basis ?? '';
    _weight = declaredText(display['weight'] ?? _startingWeight()?.toJson());
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

  @override
  void dispose() {
    // THE TILE GOING AWAY IS A DOOR TOO. A draft that is named and touched
    // leaves by whatever door it leaves by, and says the same thing each time.
    if (_dirty && _title.trim().isNotEmpty) _draft().closeAsNamed(_settings);
    super.dispose();
  }

  /// A group boosts by default so an object crossing more frames reads as more
  /// prominent; a calendar does not, because every event is on one. Read from
  /// the traits the card opened holding.
  Rational? _startingWeight() {
    for (final trait in _traits) {
      final weight = defaultWeightForNewFrame(trait);
      if (weight != null) return weight;
    }
    return null;
  }

  void _touch(VoidCallback change) => setState(() {
    change();
    _dirty = true;
  });

  /// The shared contract. Save writes and closes, Apply writes and stays,
  /// Discard leaves the draft unwritten as the plain fact that it never was --
  /// nothing was committed, so there is nothing to undo.
  CardDraft _draft() {
    final editor = _held;
    return CardDraft(
      save: () {
        if (editor != null) _save(editor, andClose: true);
      },
      apply: () {
        if (editor != null) _save(editor);
      },
      discard: () {
        _dirty = false;
        widget.onClose?.call();
      },
      // A verb no card offers must not cost the work: keep it, and the refusal
      // the contract pushed says why.
      keep: () {
        if (editor != null) _save(editor);
      },
    );
  }

  /// The guidance, stated while the gap exists. An unconnected frame is not an
  /// empty calendar, and the difference is exactly what nothing used to say.
  String? get _basisGap {
    if (!frameAuthoringCapabilities('', _traits).basis) return null;
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
      // A COLOUR OR NOTHING. Text the one reader cannot read is refused at the
      // field, in words, and never written here as though it were a colour.
      if (parseColor(_color) != null) 'color': _color.trim(),
    }..removeWhere((_, value) => value == null);
    return built.isEmpty ? null : built;
  }

  void _save(Editor editor, {bool andClose = false}) {
    final Json? display;
    try {
      display = _display;
    } on MathRefusal catch (refusal) {
      return setState(() => _refusal = '$refusal');
    }
    final id = widget.frameId ?? createId('frame');
    final minting = widget.frameId == null;
    editor.transaction(minting ? 'New frame' : 'Edit frame', (document) {
      final existing = document.frames[id] ?? Frame(id: id);
      var frame = existing.copyWith(
        title: _title.trim().isEmpty ? null : _title.trim(),
        traits: additiveFrameTraits('', _traits, const []),
      );
      frame = writeField(frame, 'basis', _basis.isEmpty ? null : _basis);
      frame = writeField(frame, 'coordinate', _coordinate);
      frame = writeField(frame, 'period', _period);
      frame = writeField(frame, 'display', display);
      return document.put('frames', id, frame);
    });
    final refusal = editor.refusals.isEmpty ? null : editor.refusals.join(' ');
    _dirty = false;
    _refusal = refusal;
    if (mounted) setState(() {});
    if (refusal != null) return;
    if (minting) widget.onOpen?.call(id);
    if (andClose) widget.onClose?.call();
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

  /// WHAT THIS FRAME IS, as traits: chips with their own remove, one composer to
  /// add, and the bundles the document already exhibits offered as starting
  /// points. Never a closed noun list.
  Widget _traitEditor(BuildContext context, Document document) {
    final worn = _traits.toSet();
    final bundles = [
      for (final bundle in frameStartingBundles(document))
        if (!worn.containsAll(bundle.traits)) bundle,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        cardWrap(context, [
          for (final trait in _traits)
            namedAction(
              context,
              trait,
              glyph: '$trait ✕',
              hint: 'Take this trait off the frame.',
              onTap: () => _touch(() => _traits = [..._traits.where((other) => other != trait)]),
            ),
          if (_traits.isEmpty) Text('nothing said yet', style: labelStyle(context)),
          CardCompose(
            hint: 'Add a trait…',
            action: 'Add',
            refusal: 'Name the trait first.',
            onSubmit: (word) =>
                _touch(() => _traits = additiveFrameTraits('', [..._traits, word], const [])),
          ),
        ]),
        if (bundles.isNotEmpty)
          cardWrap(context, [
            Text('Starts like', style: labelStyle(context)),
            for (final bundle in bundles.take(
              cardTunable(ChromeScope.of(context).settings, 'card.searchWindow').round().toInt(),
            ))
              namedAction(
                context,
                bundle.traits.join(' '),
                hint: '${bundle.worn} frame(s) here wear exactly this. Adds them all; removes none.',
                onTap: () => _touch(
                  () => _traits = additiveFrameTraits('', [..._traits, ...bundle.traits], const []),
                ),
              ),
          ]),
      ],
    );
  }

  /// WHAT IS STAPLED HERE. A frame that could not show what it holds is why a
  /// note attached to it could not be found again (ISSUES 9.1). Windowed, and
  /// every name opens that record's own card.
  Widget _stapledHere(BuildContext context, Editor editor, String frameId) {
    final window = cardTunable(ChromeScope.of(context).settings, 'card.searchWindow').round().toInt();
    final held = <String>[];
    var more = 0;
    for (final event in editor.document.events.values) {
      if (!editor.engine.indexes.framesOf(event.id).contains(frameId)) continue;
      held.length < window ? held.add(event.id) : more += 1;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        cardWrap(context, [
          for (final id in held)
            cardLink(
              context,
              str(editor.document.events[id]?.payload?['title']) ?? id,
              () => CardHost.maybeOf(context)?.openObject(id),
            ),
          if (held.isEmpty)
            Text('Nothing is stapled here yet.', style: labelStyle(context)),
        ]),
        if (more > 0) cardNote(context, '+$more more.'),
      ],
    );
  }

  /// The ways onward, spelled once so the live card and the card whose record
  /// has been deleted offer the same ones.
  Widget _doors(BuildContext context) => cardDoors(context, [
    cardDoor(
      'All frames',
      'The one list of every frame in this document.',
      (factory) => factory.framesBrowser(),
    ),
    newFrameDoor(),
    // The blank cards open with their placement region EMPTY and waiting to be
    // said (ISSUES 9.1) -- coming from a frame does not staple anything to it,
    // because the staple is the sentence and the sentence is authored.
    ...mintingDoors(),
    cardDoor(
      'The document',
      'What this document is called, where it saves, what crosses the ICS '
          'boundary.',
      (factory) => factory.documentCard(),
    ),
  ]);

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
    // A CARD WHOSE RECORD IS GONE SAYS SO. Delete is one of this card's own
    // verbs, and undo can take a frame away from under any surface, so the read
    // that follows must not be made at all -- asking the engine for a deleted
    // frame's law is a refusal that would take the card down with it.
    if (id != null && !document.frames.containsKey(id)) {
      return CardShell(
        title: _title.isEmpty ? 'Frame' : _title,
        onClose: widget.onClose,
        primary: [
          cardNote(
            context,
            'This frame is no longer in the document. Deleting is undoable, so '
            'it comes back the way anything else does.',
            refusal: true,
          ),
          // THE WAYS ONWARD SURVIVE THE RECORD. A card you arrived at and
          // cannot leave is the dead end the butter forbids, and it is exactly
          // where a deleted record leaves you.
          _doors(context),
        ],
      );
    }
    final capabilities = frameAuthoringCapabilities('', _traits);
    final gap = _basisGap;
    // The law is a derivation over a declaration a person authors, so it can
    // refuse in the law's own words. Reported where the structure editor stands,
    // never thrown through the card.
    CoordinateLaw? law;
    try {
      law = id == null ? null : editor.engine.lawOf(id);
    } on LawRefusal {
      law = null;
    }
    final draft = _draft();
    return CardShell(
      title: _title.isEmpty ? 'New frame' : _title,
      sigil: id == null ? '+' : '▤',
      dirty: _dirty,
      // THE X IS THE CONTRACT'S DOOR, not a bare close.
      onClose: () {
        if (_dirty && _title.trim().isNotEmpty) return draft.closeAsNamed(_settings);
        widget.onClose?.call();
      },
      foldLabel: 'Structure, handling and boundaries',
      primary: [
        cardTextRow(
          context,
          'Name',
          _title,
          (text) => _touch(() => _title = text),
          hint: 'What this frame is called',
        ),
        // WHAT THIS FRAME HOLDS, and where to go from it. Reading first: the
        // question Don's morning brought here was "where did my note go", and a
        // frame that could not show what is stapled to it is why that question
        // had no surface to ask. The doors belong with the reading -- one more
        // of these, all of them, a frame that does not exist yet.
        if (id != null) cardRow(context, 'Stapled here', _stapledHere(context, editor, id)),
        _doors(context),
        cardRule(context),
        cardRow(context, 'This frame is', _traitEditor(context, document)),
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
        namedAction(context, 'Save', hint: draftVerbSays['Save'], onTap: () => draft.save()),
        // THE THREE VERBS ONCE CHANGES EXIST -- the object card's contract,
        // kept here by the same class rather than by a second promise.
        if (_dirty) ...[
          namedAction(context, 'Apply', hint: draftVerbSays['Apply'], onTap: () => draft.apply()),
          namedAction(
            context,
            'Discard',
            hint: 'Leaves the draft unwritten. Nothing was committed, so there is '
                'nothing to undo.',
            onTap: () => draft.discard(),
          ),
        ],
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
              _dirty = false;
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
    kind: request.kind,
    onClose: host.close,
    onOpen: host.openFrame,
  );
}

Widget _framesBody(BuildContext context, CardRequest request) {
  final host = CardHost.of(context);
  return FramesBrowser(onClose: host.close, onOpen: host.openFrame);
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

/// The settings family: one body, and which area it governs is the request's
/// own word. A main card names none.
Widget _settingsBody(BuildContext context, CardRequest request) =>
    SettingsCard(onClose: CardHost.of(context).close, area: request.kind);

/// Apply is a live swap, Save is a file (ISSUES 8.17): the factory carries the
/// swap so the card can offer both verbs and mean them.
Widget _themesBody(BuildContext context, CardRequest request) {
  final host = CardHost.of(context);
  return ThemeCard(onClose: host.close, onApply: host.factory.onTheme, files: host.factory.files);
}
