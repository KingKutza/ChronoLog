// State, and when it happened.
//
// There is no resolution property and no lifecycle enum: STATE IS A FRAME, and
// being in a state is an ordinary membership in it. So this is a chooser over
// the state frames the document happens to hold, plus the verb that mints a new
// one -- ISSUES 8.26's "no surface authors an affiliation with any other state
// frame (cancelled, postponed) ... and no surface shows or edits the completion
// instant after the fact" is exactly what this closes. Nothing here can
// enumerate a fixed vocabulary of states, which is the point.
//
// THE INSTANT IS A TERMINAL STAPLE, edited through the same variable-precision
// field every other connection uses -- which is why an era-governed frame needs
// no special disabling: the field speaks that law's own year affix. The old
// date/time pair, which "cannot express an era", does not survive.

import 'package:flutter/material.dart';

import '../chrome/controls.dart';
import '../core/coordinate_law.dart';
import '../core/document.dart';
import '../core/object_kinds.dart';
import '../core/records.dart';
import '../edit/editor.dart';
import 'card_chrome.dart';
import 'coordinate_field.dart';
import 'card_factory.dart';

class StateControl extends StatelessWidget {
  const StateControl({super.key, required this.objectId});

  final String objectId;

  /// Rewrites the terminal staple's frame end. Backdating is nothing but this
  /// coordinate; clearing it leaves the membership standing, which is the legal
  /// shape "done, instant unstated".
  void _setInstant(Editor editor, StateInstant at, Coordinate? value) => editor.transaction(
    value == null ? 'Clear the instant' : 'Amend the instant',
    (document) => value == null
        ? removeStaple(document, at.staple.id)
        : document.put(
            'relations',
            at.staple.id,
            at.staple.withField('ends', [
              for (final end in at.staple.ends)
                (end is FrameEnd
                        ? FrameEnd(
                            end.frame,
                            position: Position.coordinate(Json.from(value.toJson())),
                            extra: end.extra,
                          )
                        : end)
                    .toJson(),
            ]),
          ),
  );

  @override
  Widget build(BuildContext context) {
    final editor = CardHost.of(context).editor;
    final document = editor.document;
    final affiliations = ObjectFacts(document).stateAffiliations(objectId);
    final entered = {for (final entry in affiliations) entry.frame};
    final states = [
      for (final frame in document.frames.values)
        if (isStateFrame(frame)) frame,
    ];
    final at = affiliations.map((entry) => entry.at).nonNulls.firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        cardWrap(context, [
          // Done is the one state the substrate itself ever names, and the
          // first completion MINTS it -- it is never seeded, so undoing that
          // completion takes the frame with it.
          if (!states.any((frame) => frame.id == doneStateFrameId))
            namedToggle(
              context,
              doneStateTitle,
              false,
              (_) => editor.toggleState(objectId, doneStateFrameId),
            ),
          for (final frame in states)
            namedToggle(
              context,
              frame.title ?? frame.id,
              entered.contains(frame.id),
              (_) => editor.toggleState(objectId, frame.id, title: frame.title ?? frame.id),
            ),
          CardCompose(
            hint: 'New state…',
            action: 'Mint state',
            refusal: 'Name a state — cancelled, postponed, whatever you mean.',
            onSubmit: (title) => editor.toggleState(objectId, createId('frame'), title: title),
          ),
        ]),
        if (at != null)
          cardRow(
            context,
            'It happened at',
            CoordinateField(
              law: editor.engine.lawOf(at.frame),
              value: at.coordinate,
              onChanged: (value, _) => _setInstant(editor, at, value),
            ),
          )
        else if (affiliations.isNotEmpty)
          cardNote(context, 'In a state, instant unstated — which is a legal record.'),
      ],
    );
  }
}
