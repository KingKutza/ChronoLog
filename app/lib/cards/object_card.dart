// The object card: one class of record, three authoring kinds, no type system.
//
// Kind is ADDITIVE -- a ToDo is an object carrying the task traits -- and the
// fields follow from the catalog rather than from a branch per kind. A
// zero-duration kind shows no duration row, which is Don's 8.27 story made
// structural: a todo may sit on the calendar carrying importance without
// asserting duration, completion records what happened without rewriting what
// was scheduled, and PUSH FORWARD is a first-class verb here instead of
// dragging the lie. Importance is a group affiliation the weight explainer can
// show, so the block's hours are never juiced to carry it.
//
// The primary path is short: what it is called, where it is stapled, what it
// belongs to, what state it is in. Everything else is under one fold.
//
// A note is Obsidian-shaped: a name, a large text body in the primary path, and
// properties and tags folded away.

import 'package:flutter/material.dart';

import '../chrome/controls.dart';
import '../core/document.dart';
import '../core/exact.dart';
import '../core/indexes.dart';
import '../core/object_kinds.dart';
import '../core/records.dart';
import '../edit/editor.dart';
import '../lens/marks.dart';
import 'card_chrome.dart';
import 'card_factory.dart';
import 'connection_picker.dart';
import 'staple_editor.dart';
import 'state_control.dart';
import 'weight_explainer.dart';

class ObjectCard extends StatefulWidget {
  const ObjectCard({super.key, required this.request});

  final CardRequest request;

  @override
  State<ObjectCard> createState() => _ObjectCardState();
}

class _ObjectCardState extends State<ObjectCard> {
  Draft? _draft;
  String _objectId = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_draft != null) return;
    final editor = CardHost.of(context).editor;
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
    _draft?.close();
    super.dispose();
  }

  Editor get _editor => CardHost.of(context).editor;

  /// The record this card edits -- from the document, or, before the first
  /// value lands, the one the editor is holding for it. One read, so no row
  /// below has to know which of the two it is looking at.
  Event? get _event => _editor.document.events[_objectId] ?? _editor.pending[_objectId];

  void _write(String label, Event next) =>
      _editor.transaction(label, (d) => d.put('events', next.id, next));

  void _payload(String key, String value) {
    final event = _event;
    if (event != null) {
      _write('Edit $key', event.copyWith(payload: {...?event.payload, key: value}));
    }
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
    final host = CardHost.of(context);
    final event = _event;
    if (event == null) {
      return cardNote(context, 'This object is no longer in the document.', refusal: true);
    }
    final kind = objectKindForEvent(event);
    final definition = objectKinds[kind]!;
    final title = str(event.payload?['title']) ?? '';
    final note = str(event.payload?['description']) ?? '';
    final isNote = kind == 'note';
    Widget body(int lines, String hint) => CardField(
      value: note,
      hint: hint,
      lines: lines,
      width: double.infinity,
      onChanged: (text) => _payload('description', text),
    );
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
            value: title,
            hint: definition.newTitle,
            onChanged: (text) => _payload('title', text),
          ),
        ]),
        if (isNote)
          body(
            cardPx(context, 'card.noteLines').round(),
            'Write. A staple typed inline is where the note appears.',
          ),
        StapleEditor(objectId: _objectId),
        _Membership(objectId: _objectId, editor: _editor),
        cardRow(context, 'State', StateControl(objectId: _objectId)),
      ],
      fold: [
        if (!isNote)
          cardRow(context, 'Description', body(cardPx(context, 'card.textLines').round(), '')),
        cardRow(
          context,
          'Location',
          CardField(
            value: str(event.payload?['location']) ?? '',
            onChanged: (text) => _payload('location', text),
          ),
        ),
        if (!definition.zeroDuration) cardRow(context, 'Duration', _duration(context, event)),
        _Recurrence(objectId: _objectId, editor: _editor),
        cardRow(context, 'Colour', _colour(context, event)),
        cardRow(context, 'Traits', _traits(context, event)),
        cardRow(context, 'Display weight', WeightRings(objectId: _objectId)),
        ..._seriesMode(context),
      ],
      footer: [
        for (final (label, hint, act) in <(String, String, VoidCallback)>[
          (
            'Push forward',
            'Re-staples it later without touching what it claims to be.',
            _pushForward,
          ),
          (
            'Discard',
            'Throws this edit session away as its own undo entry. Nothing asks twice.',
            () {
              _draft?.discard();
              _draft = null;
              host.close();
            },
          ),
          (
            'Delete',
            'Undoable, with its connections and memberships.',
            () {
              // Release the session FIRST: a hold left behind would defer
              // autosave forever, and a record still merely held is one this
              // never authored, so deleting it is nothing at all.
              _draft?.close();
              _draft = null;
              _editor.deleteObject(_objectId);
              host.close();
            },
          ),
        ])
          namedAction(context, label, hint: hint, onTap: act),
      ],
    );
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

  /// Explicit versus inherit, with no button that does nothing: "color has an
  /// inheritance line, the further down you go the higher the precidens".
  /// Inheriting DELETES the field so the cascade sees nothing.
  Widget _colour(BuildContext context, Event event) {
    final own = str(event.extra['color']) ?? '';
    return cardWrap(context, [
      CardField(
        value: own,
        hint: '#rrggbb, or inherit',
        mono: true,
        width: cardPx(context, 'card.narrowWidth'),
        onChanged: (text) => _write('Set colour', event.withField('color', text)),
      ),
      namedAction(
        context,
        'Inherit',
        hint: 'Removes the field entirely, so the group and frame cascade speaks.',
        onTap: own.isEmpty
            ? null
            : () => _write(
                'Inherit colour',
                event.copyWith(extra: {...event.extra}..remove('color')),
              ),
      ),
    ]);
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

/// What it belongs to: calendar frames many-to-many, and groups as chips with
/// their provenance. The frame carrying the coordinate is the one that PLACES
/// it, marked as such rather than stored as a second claim that could disagree.
class _Membership extends StatelessWidget {
  const _Membership({required this.objectId, required this.editor});

  final String objectId;
  final Editor editor;

  void _attach(Connectable hit) {
    final placement = editor.engine.indexes.placementOf(objectId);
    final frame = placement?.frame;
    final role = objectKinds[objectKindForEvent(editor.document.events[objectId])]!.relationRole;
    // A coordinate-less attachment is bare MEMBERSHIP; with an instant in hand
    // the object is placed on the new frame under THAT frame's own law.
    final relation = placement == null || frame == null
        ? Relation(
            id: createId('relation'),
            type: 'attachment',
            extra: {'event': objectId, 'frame': hit.id, 'role': role},
          )
        : editor.placement(
            objectId,
            hit.id,
            editor.engine.coordinateDays(frame, placement.coordinate),
            role,
          );
    editor.transaction('Attach to ${hit.label}', (d) => d.put('relations', relation.id, relation));
  }

  /// A new GROUP boosts by default, so an object crossing more frames reads as
  /// more prominent without anyone authoring arithmetic. Calendars do not.
  void _newGroup(String title) {
    final frame = Frame(
      id: createId('frame'),
      title: title,
      traits: const ['set', 'group'],
      extra: const {
        'display': {'weight': 'w * 1.5'},
      },
    );
    final joined = editor.membership(objectId, frame.id);
    editor.transaction(
      'New group $title',
      (d) => d.put('frames', frame.id, frame).put('relations', joined.id, joined),
    );
  }

  String _provenance(Indexes indexes, String groupId) {
    final found = indexes.members[groupId]?[objectId]?.firstOrNull;
    if (found == null) return 'authored membership';
    return found.via == null ? found.kind : '${found.kind} through ${found.via}';
  }

  @override
  Widget build(BuildContext context) {
    final host = CardHost.of(context);
    final indexes = editor.engine.indexes;
    final placing = indexes.calendarFrameOf(objectId);
    final calendars = editor.engine.eventCalendarFrames(objectId);
    final groups = indexes
        .directGroupsOf(objectId)
        .where((id) => !isStateFrame(editor.document.frames[id]));
    String titleOf(String id) => editor.document.frames[id]?.title ?? id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        cardRow(
          context,
          'Frames',
          cardWrap(context, [
            for (final id in calendars) ...[
              cardLink(context, titleOf(id), () => host.openFrame(id)),
              if (id == placing) Text('places it', style: labelStyle(context)),
            ],
            if (calendars.isEmpty) Text('on no frame yet', style: labelStyle(context)),
          ]),
        ),
        ConnectionPicker(
          document: editor.document,
          objects: false,
          hint: 'Also on this frame…',
          onPicked: _attach,
        ),
        cardRow(
          context,
          'Groups',
          cardWrap(context, [
            for (final id in groups)
              Tooltip(
                message: _provenance(indexes, id),
                child: cardLink(context, titleOf(id), () => host.openFrame(id)),
              ),
            if (groups.isEmpty) Text('in no group', style: labelStyle(context)),
            CardCompose(
              hint: 'New group…',
              action: 'Make group',
              refusal: 'Name the group first.',
              onSubmit: _newGroup,
            ),
          ]),
        ),
      ],
    );
  }
}

/// The repeat over the pattern this object is the template of, through THE one
/// repeat editor. Only the pattern record is this row's own business: minting
/// one when a frequency is first chosen, and retiring it when the repeat is set
/// back to never.
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
    final frame = editor.engine.indexes.placementOf(objectId)?.frame;
    return RepeatSugar(
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
    );
  }
}
