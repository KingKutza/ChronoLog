// How a display weight was reached: ONE composed line, coloured by source.
//
// The field report this answers: "Testing Display weight, I can set it in
// frames and it dose have an apparent effect on the Stratigic band, but there
// is no clarity into how or what. If I pull up an event from that frame there
// is no clear way to see the display weight either base or modified." And, 9.2:
// "I don't see a clear way on an event to edit its weight ... could it be
// written as one one-math formula, colour-coded by source."
//
// So the row is the formula. Each term is inked in the authored colour of the
// frame that contributed it -- the colour that names that frame everywhere else
// on the surface -- and the object's OWN term is a field, because that is the
// one term of the composition this object owns. The paragraph of sentences that
// used to stand here is the hover.
//
// Nothing is recomputed. `Editor.explainWeight` reads the engine's own
// `weightOf` -- the same fold that drew the mark -- so the explanation cannot
// disagree with the picture. Weight is PROJECTION-RELATIVE by design: with a
// view focused the card reads through it, and with nothing focused the object
// speaks through every frame it is in rather than through one.

import 'package:flutter/material.dart';

import '../chrome/controls.dart';
import '../core/eras.dart';
import '../core/projection.dart';
import '../core/records.dart';
import '../core/weight.dart';
import '../edit/editor.dart';
import '../lens/theme.dart';
import 'card_chrome.dart';
import 'card_factory.dart';

/// The fact this object contributes to a frame, or null when nothing places it.
/// Read from the engine's own explicit index rather than a fresh window query:
/// one derivation, so there is no second answer to disagree with.
Fact? factForObject(ProjectionEngine engine, String objectId) {
  final frame =
      engine.indexes.calendarFrameOf(objectId) ?? engine.indexes.framesOf(objectId).firstOrNull;
  if (frame == null) return null;
  for (final fact in engine.explicitFacts(frame)) {
    if (fact.event.id == objectId) return fact;
  }
  return null;
}

/// THE COLOUR A FRAME IS KNOWN BY. Authored on the frame or in its handling
/// bundle -- the same two places the frame card writes -- and null where the
/// author has said none, because a colour nobody wrote is not a colour.
Color? frameInk(Document document, String frameId) {
  final frame = document.frames[frameId];
  if (frame == null) return null;
  final written =
      str(frame.extra['color']) ?? str(obj(frame.extra['display'])?['color']) ?? '';
  return parseColor(written);
}

class WeightRings extends StatelessWidget {
  const WeightRings({super.key, required this.objectId});

  final String objectId;

  /// The object's own term, as authored -- `display.weight`, the ring the engine
  /// reads first.
  String _own(Editor editor) =>
      declaredText(obj(editor.document.events[objectId]?.extra['display'])?['weight']);

  void _write(Editor editor, String source) {
    final event = editor.document.events[objectId];
    if (event == null) return;
    final display = {...?obj(event.extra['display'])};
    source.trim().isEmpty ? display.remove('weight') : display['weight'] = source;
    editor.transaction(
      'Edit display weight',
      (d) => d.put(
        'events',
        objectId,
        event.withField('display', display.isEmpty ? null : display),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeScope.of(context);
    final editor = CardHost.of(context).editor;
    final theme = ChronoTheme.of(context);
    final fact = factForObject(editor.engine, objectId);
    if (fact == null) {
      return cardNote(
        context,
        'Nothing places this object yet, so no lens has a weight to show for it. '
        'Give it a connection above.',
      );
    }
    // Weight is relative to what is being looked through. With a view focused
    // the card reads through its projection; with nothing focused, the object
    // speaks through every frame it is actually in -- one true number is what
    // this surface must never imply, and one arbitrary frame is that in
    // disguise.
    final projection =
        chrome.focusedView?.projection() ??
        Projection.of([
          fact.relation.frame ?? '',
          ...editor.engine.indexes.framesOf(objectId),
        ]);
    final explanation = editor.explainWeight(fact, projection);
    final verdict = explanation.weight >= chrome.settings.value('weight.landmarkAt')
        ? 'landmark'
        : explanation.weight >= chrome.settings.value('weight.importantAt')
        ? 'important'
        : 'standard';
    // THE HOVER IS THE PARAGRAPH. What used to be six lines of surface is the
    // one thing a person asks of a formula: where each term came from.
    final said = [
      'Starts at ${explanation.base.toDecimal(3)}.',
      for (final ring in explanation.rows)
        '${ring.title} says "${ring.formula}" — ${ring.from.toDecimal(3)} to '
            '${ring.to.toDecimal(3)}.',
      'Read through ${projection.frames.length} projected frame(s): a reading, never one '
          'true number. Important starts at '
          '${chrome.settings.value('weight.importantAt').toDecimal(2)}, a landmark at '
          '${chrome.settings.value('weight.landmarkAt').toDecimal(2)}.',
    ].join(' ');
    return Tooltip(
      message: said,
      child: cardWrap(context, [
        Text(
          '${editor.ringTitle(ownWeightRing, fact)} weighs',
          style: bodyStyle(context, color: theme.ink),
        ),
        // THE ONE EDITABLE TERM: this object's own.
        CardField(
          value: _own(editor),
          mono: true,
          hint: '1',
          width: cardPx(context, 'card.narrowWidth'),
          onChanged: (text) => _write(editor, text),
        ),
        for (final ring in explanation.rows)
          if (ring.id != ownWeightRing)
            Text(
              '${ring.title} ${ring.formula}',
              style: dataStyle(context, color: frameInk(editor.document, ring.id) ?? theme.ink),
            ),
        Text(
          '= ${explanation.weight.toDecimal(3)}, $verdict',
          style: bodyStyle(context, color: theme.primary),
        ),
      ]),
    );
  }
}
