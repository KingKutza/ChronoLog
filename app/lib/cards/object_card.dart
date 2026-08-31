// The object card: one class of record, three authoring kinds, no type system.
//
// TWO REGIONS OF AUTHORED SENTENCES, AND NOTHING ELSE (ISSUES 8.31, ruled
// redesign). The noun stays a dropdown -- click EVENT to say ToDo -- and below
// it there are exactly two regions with a rule between them:
//
//   PROPERTIES, in the open: the name, the description, the colour, the
//   location, and whatever else this object carries, with a + that adds one.
//   No fold: "everything below it is a dense mess that leaves the eye no
//   natural path", and a fold over the basics is the densest mess of all.
//
//   STAPLES, with its own +: every connection is a sentence. A FRAME
//   CONNECTION IS A STAPLE, so the standalone frame section is gone --
//   membership, placement and kinship are one vocabulary, and typing a name
//   nothing wears offers to make it and opens that record's own card.
//
// Kind is ADDITIVE -- a ToDo is an object carrying the task traits -- and the
// rows follow from the catalog rather than from a branch per kind. A
// zero-duration kind shows no duration row, which is Don's 8.27 story made
// structural: a todo may sit on the calendar carrying importance without
// asserting duration, completion records what happened without rewriting what
// was scheduled, and PUSH FORWARD is a first-class verb here instead of
// dragging the lie.
//
// THE VERBS: Delete always; Save, Apply and Discard once changes exist -- apply
// writes and stays, save writes and closes. What the X does is `card.closeVerb`,
// which names one of those three and is refused in words if it names none.

import 'package:flutter/material.dart';

import '../chrome/controls.dart';
import '../core/document.dart';
import '../core/exact.dart';
import '../core/object_kinds.dart';
import '../core/records.dart';
import '../edit/editor.dart';
import '../lens/marks.dart';
import '../session/settings.dart';
import 'card_chrome.dart';
import 'card_factory.dart';
import 'staple_editor.dart';
import 'state_control.dart';
import 'weight_explainer.dart';

/// The payload keys this card's own rows already speak for. Anything else in
/// the payload is a property the author added, and it gets a row of its own --
/// which is what makes the + a real door rather than a decoration.
const Set<String> namedObjectProperties = {'title', 'description', 'location'};

class ObjectCard extends StatefulWidget {
  const ObjectCard({super.key, required this.request});

  final CardRequest request;

  @override
  State<ObjectCard> createState() => _ObjectCardState();
}

class _ObjectCardState extends State<ObjectCard> {
  Draft? _draft;
  String _objectId = '';

  /// Properties named through the + that carry no value yet: a row exists the
  /// moment it is named, and the record hears about it when something is typed.
  final Set<String> _added = {};
  bool _naming = false;

  /// Held for `dispose`, where an inherited scope may no longer be asked.
  Editor? _held;
  Settings? _settings;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final host = CardHost.of(context);
    _held = host.editor;
    _settings = ChromeScope.of(context).settings;
    if (_draft != null) return;
    final editor = host.editor;
    final request = widget.request;
    if (request.id case final String existing) {
      _objectId = existing;
      _draft = editor.beginDraft(existing);
      return;
    }
    // A NEW OBJECT IS A DRAFT UNTIL THE FIRST AUTHORED VALUE (E1). A seed that
    // already carries a placement is one such value -- drag-create states where
    // the thing is, so it commits on mouse-up and this card opens over a real
    // record. A bare "+" states nothing, so the record is merely HELD: every row
    // below edits it, and whichever row is used first mints it along with what
    // it said, as one undo entry. Closing untouched means nothing happened.
    final kind = request.kind ?? 'event';
    if (request.frameId case final String frame) {
      _objectId = editor.createAt(
        frame,
        request.startDays ?? Rational.zero,
        request.endDays,
        kind: kind,
      );
      _draft = editor.beginDraft(_objectId, provisional: true);
      return;
    }
    final held = editor.newObject(kind, title: '');
    _objectId = held.id;
    _draft = editor.beginDraft(_objectId, provisional: true, holding: held);
  }

  @override
  void dispose() {
    _closeAsSettled();
    super.dispose();
  }

  Editor get _editor => _held ?? CardHost.of(context).editor;

  /// The record this card edits -- from the document, or, before the first
  /// value lands, the one the editor is holding for it. One read, so no row
  /// below has to know which of the two it is looking at.
  Event? get _event => _editor.document.events[_objectId] ?? _editor.pending[_objectId];

  /// Has this session authored anything? The draft remembers the document it
  /// opened over, and a document is immutable, so this is an identity check.
  bool get _changed => _draft?.changed ?? false;

  void _write(String label, Event next) =>
      _editor.transaction(label, (d) => d.put('events', next.id, next));

  void _payload(String key, String value) {
    final event = _event;
    if (event != null) {
      _write('Edit $key', event.copyWith(payload: {...?event.payload, key: value}));
    }
  }

  void _dropProperty(Event event, String key) {
    setState(() => _added.remove(key));
    if (event.payload?.containsKey(key) ?? false) {
      _write('Remove $key', event.copyWith(payload: {...?event.payload}..remove(key)));
    }
  }

  // --- The verbs -------------------------------------------------------------

  /// Writes the document to disk. A card holds autosave off while it is open,
  /// so this is the explicit request that gets through the deferral.
  void _writeNow() => _editor.store.save(force: true);

  /// Apply: writes and STAYS. The session stays open, so the hold stays taken.
  void _apply() => _writeNow();

  /// Save: writes and CLOSES. Settling the draft first is what lets a
  /// materialized occurrence retire itself back into its series.
  void _save() {
    _settle();
    _writeNow();
    CardHost.of(context).close();
  }

  void _discard() {
    _draft?.discard();
    _draft = null;
    CardHost.of(context).close();
  }

  void _settle() {
    _draft?.close();
    _draft = null;
  }

  /// What the X does, by NAME. The verbs are data and the setting picks one; a
  /// name none of them wears is refused in words -- pushed into the settings
  /// refusals, which announce, so the settings card says so at once. The
  /// "stays open" half of Apply is moot once the card is going away; the write
  /// is the same write.
  void _closeAsSettled() {
    final draft = _draft;
    if (draft == null || !draft.open) return;
    // Nothing authored is nothing to write, keep or throw away.
    if (!draft.changed) {
      draft.close();
      _draft = null;
      return;
    }
    final verbs = <String, void Function()>{
      'save': () {
        _settle();
        _writeNow();
      },
      'apply': () {
        _settle();
        _writeNow();
      },
      'discard': () {
        draft.discard();
        _draft = null;
      },
    };
    final named = (_settings?.text('card.closeVerb') ?? '').trim().toLowerCase();
    final verb = verbs[named];
    if (verb == null) {
      _settings?.refusals.add(
        'card.closeVerb: "$named" is not a verb this card offers'
        ' (${verbs.keys.join(', ')}). The card closed and kept its work.',
      );
      _settle();
      return;
    }
    verb();
  }

  /// PUSH FORWARD, first class. It moves the placement and touches nothing
  /// else: duration is not a dial for importance, and completing a pushed item
  /// must not force a second lie about what was scheduled.
  void _pushForward() {
    final editor = _editor;
    final placement = editor.engine.indexes.placementOf(_objectId);
    final frame = placement?.frame;
    if (placement == null || frame == null) return;
    final was = editor.engine.coordinateDays(frame, placement.coordinate);
    editor.transaction(
      'Push forward',
      (d) => d.put(
        'relations',
        placement.id,
        placement.withField(
          'coordinate',
          editor.engine.daysCoordinate(frame, was + editor.setting('edit.newSpanDays')),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // A card reads the document, so it redraws when the document changes: a
    // frame minted elsewhere joins this card's sentences at once.
    return ListenableBuilder(
      listenable: _editor.changes,
      builder: (context, _) => _card(context),
    );
  }

  Widget _card(BuildContext context) {
    final host = CardHost.of(context);
    final event = _event;
    if (event == null) {
      return cardNote(context, 'This object is no longer in the document.', refusal: true);
    }
    final kind = objectKindForEvent(event);
    final definition = objectKinds[kind]!;
    final title = str(event.payload?['title']) ?? '';
    return CardShell(
      title: title.isEmpty ? definition.newTitle : title,
      sigil:
          sigilGlyphs[switch (kind) {
            'todo' => 'task',
            'note' => 'note',
            _ => 'point',
          }]!,
      // Dirty means UNSAVED EDITS, and a card still holding its record has
      // authored none: the session is open over nothing the document has heard
      // of. So the mark waits for the first value, exactly as the record does.
      dirty: (_draft?.open ?? false) && !_editor.pending.containsKey(_objectId),
      onClose: host.close,
      primary: [
        ..._properties(context, event, definition, kind),
        cardRule(context),
        StapleEditor(objectId: _objectId),
        cardRow(context, 'State', StateControl(objectId: _objectId)),
        ..._seriesMode(context),
      ],
      footer: [
        if (_changed)
          for (final (label, hint, act) in <(String, String, VoidCallback)>[
            ('Save', 'Writes the document and closes this card.', _save),
            ('Apply', 'Writes the document and leaves this card open.', _apply),
            (
              'Discard',
              'Throws this edit session away as its own undo entry. Nothing asks twice.',
              _discard,
            ),
          ])
            namedAction(context, label, hint: hint, onTap: act),
        namedAction(
          context,
          'Push forward',
          hint: 'Re-staples it later without touching what it claims to be.',
          onTap: _pushForward,
        ),
        namedAction(
          context,
          'Delete',
          hint: 'Undoable, with its connections and memberships.',
          onTap: () {
            // Release the session FIRST: a hold left behind would defer
            // autosave forever, and a record still merely held is one this
            // never authored, so deleting it is nothing at all.
            _settle();
            _editor.deleteObject(_objectId);
            host.close();
          },
        ),
      ],
    );
  }

  // --- Region one: the properties --------------------------------------------

  /// The properties, in the open. The basics first, then whatever this kind
  /// admits, then every property the author added -- each one a row, never a
  /// comma string and never behind a disclosure.
  List<Widget> _properties(
    BuildContext context,
    Event event,
    ObjectKind definition,
    String kind,
  ) {
    final payload = event.payload ?? const <String, dynamic>{};
    final own = <String>{
      for (final key in payload.keys)
        if (!namedObjectProperties.contains(key)) key,
      ..._added,
    };
    return [
      cardWrap(context, [
        cardMenu(
          context,
          kind,
          {for (final entry in objectKinds.entries) entry.key: entry.value.label},
          // Additive: the catalog's traits change and every trait the author
          // wrote survives untouched.
          (picked) => _write(
            'Change kind',
            event.copyWith(traits: traitsForObjectKind(event.traits, picked)),
          ),
        ),
        CardField(
          value: str(payload['title']) ?? '',
          hint: definition.newTitle,
          onChanged: (text) => _payload('title', text),
        ),
        namedAction(
          context,
          'Add a property',
          glyph: '+',
          hint: 'Names one more thing about this object.',
          onTap: () => setState(() => _naming = !_naming),
        ),
      ]),
      if (_naming)
        CardCompose(
          hint: 'What the property is called…',
          action: 'Add',
          refusal: 'Name the property first.',
          onSubmit: (name) => setState(() {
            _added.add(name);
            _naming = false;
          }),
        ),
      cardRow(
        context,
        'Description',
        CardField(
          value: str(payload['description']) ?? '',
          hint: kind == 'note' ? 'Write. A staple typed inline is where the note appears.' : '',
          // A note is Obsidian-shaped: its body IS the description, given the
          // room to be a body.
          lines: cardPx(context, kind == 'note' ? 'card.noteLines' : 'card.textLines').round(),
          width: double.infinity,
          onChanged: (text) => _payload('description', text),
        ),
      ),
      cardRow(context, 'Colour', _colour(context, event)),
      cardRow(
        context,
        'Location',
        CardField(
          value: str(payload['location']) ?? '',
          onChanged: (text) => _payload('location', text),
        ),
      ),
      if (!definition.zeroDuration) cardRow(context, 'Duration', _duration(context, event)),
      _Recurrence(objectId: _objectId, editor: _editor),
      cardRow(context, 'Traits', _traits(context, event)),
      cardRow(context, 'Display weight', WeightRings(objectId: _objectId)),
      for (final key in own)
        cardRow(
          context,
          key,
          cardWrap(context, [
            CardField(
              value: str(payload[key]) ?? '',
              onChanged: (text) => _payload(key, text),
            ),
            namedAction(
              context,
              'Remove',
              glyph: '✕',
              hint: 'Takes this property off the object.',
              onTap: () => _dropProperty(event, key),
            ),
          ]),
        ),
    ];
  }

  /// Duration, read and written through the GOVERNING FRAME'S OWN LAW: setting
  /// hours-per-day to 23 changes what "one hour" is worth here.
  Widget _duration(BuildContext context, Event event) {
    final indexes = _editor.engine.indexes;
    final frame = indexes.calendarFrameOf(_objectId) ?? indexes.framesOf(_objectId).firstOrNull;
    final law = frame == null ? null : _editor.engine.lawOf(frame);
    final level = event.duration?.coordinate.levels.firstOrNull;
    final unit = level?.level ?? 'minute';
    final amount = level?.value ?? '0';
    void put(String value, String named) => _write(
      'Edit duration',
      event.copyWith(
        magnitudes: {...event.magnitudes, 'duration': durationMagnitude(value, named)},
      ),
    );
    return cardWrap(context, [
      CardField(
        value: amount,
        mono: true,
        width: cardPx(context, 'card.narrowWidth'),
        onChanged: (text) => put(text, unit),
      ),
      cardMenu(context, unit, {
        for (final name in law?.levelNames() ?? const ['minute']) name: name,
      }, (name) => put(amount, name)),
    ]);
  }

  /// Explicit versus inherit, through THE one colour control: "color has an
  /// inheritance line, the further down you go the higher the precidens".
  /// Inheriting DELETES the field so the cascade sees nothing, and a written
  /// colour that reads as none is refused by the control rather than stored.
  Widget _colour(BuildContext context, Event event) {
    final own = str(event.extra['color']) ?? '';
    return colorField(context, own, (text) {
      if (text.trim().isEmpty) {
        return _write('Inherit colour', event.copyWith(extra: {...event.extra}..remove('color')));
      }
      _write('Set colour', event.withField('color', text));
    });
  }

  /// Traits as chips with their own remove, and one composer to add. Never a
  /// comma string -- that widget is exactly the condemned programmer interface.
  Widget _traits(BuildContext context, Event event) => cardWrap(context, [
    // The catalog owns the kind traits; those are the kind menu's business.
    for (final trait in event.traits.where((t) => !controlledTraits.contains(t)))
      namedAction(
        context,
        trait,
        glyph: '$trait ✕',
        hint: 'Remove this trait.',
        onTap: () => _write(
          'Remove trait',
          event.copyWith(traits: [...event.traits.where((other) => other != trait)]),
        ),
      ),
    CardCompose(
      hint: 'Add a trait…',
      action: 'Add',
      refusal: 'Name the trait first.',
      onSubmit: (text) => _write('Add trait', event.copyWith(traits: [...event.traits, text])),
    ),
  ]);

  /// Two buttons, not a checkbox: they edit two different objects. A generated
  /// occurrence materializes ONLY when asked, so an untouched one stays a
  /// projection the convergence invariant can reassert.
  List<Widget> _seriesMode(BuildContext context) {
    final provenance = obj(_event?.extra['provenance']);
    if (str(provenance?['replaces']) == null) return const [];
    final template = _editor.document.patterns[str(provenance?['pattern'])]?.templateEvent;
    return [
      cardRow(
        context,
        'This occurrence',
        cardWrap(context, [
          namedAction(
            context,
            'Edit the series',
            hint: 'Opens the template the whole series is generated from.',
            onTap: template == null ? null : () => CardHost.of(context).openObject(template),
          ),
          Flexible(
            child: cardNote(
              context,
              'This one deviates. Match the pattern again and it retires itself.',
            ),
          ),
        ]),
      ),
    ];
  }
}

/// The repeat over the pattern this object is the template of, through THE one
/// repeat editor, with the series' exclusions beneath it.
///
/// Only the pattern record is this row's own business: minting one when a
/// frequency is first chosen, and retiring it when the repeat is set back to
/// never. A minted pattern NAMES ITS TEMPLATE PLACEMENT -- ISSUES (8.31,
/// evening, Don live): "It did not project out." The occurrence generator reads
/// the template relation for its base coordinate and answers with nothing at
/// all without one, so a pattern minted without it is a rule stored over a
/// starved generator.
class _Recurrence extends StatelessWidget {
  const _Recurrence({required this.objectId, required this.editor});

  final String objectId;
  final Editor editor;

  Pattern? get _pattern => editor.document.patterns.values
      .where((pattern) => pattern.templateEvent == objectId)
      .firstOrNull;

  @override
  Widget build(BuildContext context) {
    final pattern = _pattern;
    final placement = editor.engine.indexes.placementOf(objectId);
    final frame = placement?.frame;
    // NEVER MINT A SERIES THAT CANNOT PROJECT. The generalized rule behind "it
    // did not project out": a pattern's occurrences are counted from its
    // template placement, so an object nothing places has no first occurrence
    // and a repeat set on it would be a rule stored over a starved generator.
    // Said, not silently allowed.
    if (pattern == null && placement == null) {
      return cardNote(
        context,
        'Nothing places this yet, so a repeat has no first occurrence to count'
        ' from. Staple it to a frame below, and the repeat is offered here.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RepeatSugar(
          rrule: readRRule(pattern?.extra['rrule']),
          // An unplaced object has no governing law to name weekdays with, and
          // asking a frame that is not there is a refusal, not a crash: the sugar
          // falls back to the codes rather than taking the card down.
          lawOf: (_) {
            try {
              return frame == null ? null : editor.engine.lawOf(frame).weekdayNames();
            } on Object {
              return null;
            }
          },
          onChanged: (next) {
            final record =
                pattern ??
                Pattern(
                  id: createId('pattern'),
                  language: 'chronolog-ics/1',
                  extra: {
                    'kind': 'ics-rrule',
                    'templateEvent': objectId,
                    // THE SEAM. Without the template relation the series has no
                    // base coordinate and projects nothing.
                    if (placement != null) 'templateRelation': placement.id,
                    if (frame != null) ...{
                      'frame': frame,
                      'appliesTo': [frame],
                    },
                  },
                );
            editor.transaction(
              'Edit repeat',
              (d) => next.isEmpty && pattern != null
                  ? d.remove('patterns', pattern.id)
                  : d.put('patterns', record.id, record.withField('rrule', next)),
            );
          },
        ),
        if (pattern != null)
          SeriesExclusions(pattern: pattern, editor: editor, frameId: frame),
      ],
    );
  }
}
