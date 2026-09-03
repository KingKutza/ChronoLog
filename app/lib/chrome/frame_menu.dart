// A FRAME'S VERBS ARE WHERE THE FRAME IS NAMED (ISSUES 9.2, Don: "the moment
// you are looking at a frame is the moment its verbs should be at hand").
//
// The report was "I don't see an expression field when I right-click on a frame
// in the context bar", and what it found was worse than a missing field: the
// frame's name in the chrome had no right-click at all. The Expression field
// existed, one drop away, and nothing in the chrome said so.
//
// ONE SOURCE. [frameMenu] is the whole of a frame's menu, and every chip and
// every link that names a frame hands its right-click here -- the projection
// reading on the view bar, the frame's own row inside the open projection drop,
// and whatever names a frame next. A second list per surface is how two
// surfaces come to offer different verbs for the same thing.
//
// WHAT THE ROWS ARE. The three-state the projection drop already authors -- in
// / NOT / off, writing `selection` and `negated` and never a filter -- then the
// frame's card, then the one-math Expression over this view's whole projection,
// then the frame's own settings through the same `settingsRows` every other
// surface's menu carries.
//
// UNRULED, AND NOT DECIDED HERE (RULINGS #12): what a right-click on a reading
// that names SEVERAL frames should offer -- rows per frame, or the drop itself.
// The reading answers a right-click only while it names exactly one frame, so
// the joined case is left standing as it was rather than guessed at.

import 'package:flutter/material.dart';

import '../core/records.dart';
import '../session/view_state.dart';
import 'controls.dart';
import 'menus.dart';

/// Every verb a frame has, for the view that is looking at it.
List<MenuRow> frameMenu(BuildContext context, ViewState view, String frameId) {
  final chrome = ChromeScope.of(context);
  final frames = chrome.editor?.document.frames ?? const <String, Frame>{};
  final title = frames[frameId]?.title ?? frameId;
  final selected = view.selection.isSelected(frameId);
  final negated = selected && view.negated.contains(frameId);

  // A ROW ACTION MEANS THE PLAIN SELECTION SPEAKS AGAIN, not the authored text
  // -- the same rule the projection row follows, because they are the same act
  // said in two places.
  void said(VoidCallback change) {
    change();
    view.source = '';
    chrome.views.touch();
  }

  void take(String state) => said(() {
    if (state == 'off') {
      view.negated.remove(frameId);
      if (selected) view.selection.toggle(frameId);
      return;
    }
    if (!selected) view.selection.toggle(frameId);
    state == 'not' ? view.negated.add(frameId) : view.negated.remove(frameId);
  });

  return [
    // IN / NOT / OFF, and the state it is in is the row with no verb left in
    // it: a row that says what is already true is a statement, not a door.
    menuRow(
      'In $title',
      selected && !negated ? null : () => take('in'),
      active: selected && !negated,
    ),
    menuRow('Not $title', negated ? null : () => take('not'), active: negated),
    // Turning the LAST frame off would leave the view looking through nothing,
    // which the selection refuses anyway -- so the row says so rather than
    // being a door that quietly does not open.
    menuRow(
      view.selection.selected().length == 1 && selected
          ? 'Off — $title is the only frame this view projects, so nothing would be left'
          : 'Off — $title projects nothing here',
      selected && view.selection.selected().length > 1 ? () => take('off') : null,
      active: !selected,
    ),
    menuRow(
      'Open $title',
      chrome.openFrame == null ? null : () => chrome.openFrame!(frameId),
    ),
    // THE FIELD THE REPORT WENT LOOKING FOR, at the place it went looking. It
    // is the same one-math field the projection drop carries, over the same
    // expression, so editing it here and editing it there are one act.
    menuRow('Expression — the whole projection, in the one math', () {
      final box = context.findRenderObject() as RenderBox?;
      showChronoPanel(
        context,
        box == null ? Offset.zero : box.localToGlobal(box.size.bottomLeft(Offset.zero)),
        projectionExpression(context, view),
      );
    }),
    ...settingsRows(context, frameId, title),
  ];
}

/// The view's projection as an editable expression, in the one math, with the
/// frame names this view already knows bound. One widget, so the drop and the
/// frame's own menu cannot offer two different fields for one expression.
Widget projectionExpression(BuildContext context, ViewState view) {
  final chrome = ChromeScope.of(context);
  final frames = chrome.editor?.document.frames ?? const <String, Frame>{};
  final selected = view.selection.selected();
  final bindings = ViewState.bindingsFor(selected, (id) => frames[id]?.title ?? id);
  final reading = view.source.isNotEmpty
      ? view.source
      : ViewState.textFor(selected, view.negated, bindings);
  return ExpressionField(
    label: 'Expression',
    source: reading,
    // Reading it IS the validation: the one math parses it, and the frame names
    // are the bindings this view already knows.
    evaluate: (source) => ViewState(lensId: view.lensId, source: source)
        .projection(bindings: bindings)
        .frames
        .join(', '),
    onChanged: (source) {
      view.source = source;
      chrome.views.touch();
    },
  );
}

/// WHICH FRAME A READING NAMES, when it names exactly one.
///
/// Null for a reading over several -- `A or B or C` -- because what a
/// right-click there should offer is unruled (RULINGS #12), and null for none.
/// A menu that guessed which of three frames the hand meant would be inventing
/// the answer to an open question.
String? loneFrameOf(ViewState view) {
  if (view.source.trim().isNotEmpty) return null;
  final selected = view.selection.selected();
  return selected.length == 1 ? selected.single : null;
}
