// How a display weight was reached, ring by ring.
//
// The field report this answers: "Testing Display weight, I can set it in
// frames and it dose have an apparent effect on the Stratigic band, but there
// is no clarity into how or what. If I pull up an event from that frame there
// is no clear way to see the display weight either base or modified."
//
// Nothing is recomputed here. `Editor.explainWeight` reads the engine's own
// `weightOf` -- the same fold that drew the mark -- so the explanation cannot
// disagree with the picture. Weight is PROJECTION-RELATIVE by design, so the
// card says what it was read through rather than implying one true number.

import 'package:flutter/material.dart';

import '../chrome/controls.dart';
import '../core/projection.dart';
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

class WeightRings extends StatelessWidget {
  const WeightRings({super.key, required this.objectId});

  final String objectId;

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
    // The focused view's own projection, because weight is relative to what is
    // being looked through. With no view on the stage, the frame the fact sits
    // on speaks for itself.
    final projection =
        chrome.focusedView?.projection() ?? Projection.of([fact.relation.frame ?? '']);
    final explanation = editor.explainWeight(fact, projection);
    final verdict = explanation.weight >= chrome.settings.value('weight.landmarkAt')
        ? 'landmark'
        : explanation.weight >= chrome.settings.value('weight.importantAt')
        ? 'important'
        : 'standard';
    Widget line(String left, String right, {bool strong = false}) => Row(
      children: [
        Expanded(child: Text(left, style: bodyStyle(context))),
        Text(right, style: dataStyle(context, color: strong ? theme.primary : theme.ink)),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        line('Base', explanation.base.toDecimal(3)),
        for (final ring in explanation.rows)
          line(
            '${ring.title} — ${ring.formula}',
            '${ring.from.toDecimal(3)} → ${ring.to.toDecimal(3)}',
          ),
        line(
          'Weight, and its verdict',
          '${explanation.weight.toDecimal(3)} · $verdict',
          strong: true,
        ),
        cardNote(
          context,
          'Read through ${projection.frames.length} projected frame(s). A NOT term gates '
          'visibility and never modifies weight.',
        ),
      ],
    );
  }
}
