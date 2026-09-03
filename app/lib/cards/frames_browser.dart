// The ONE frames surface. The old build had three -- a browser, a dropdown and
// a dock pane -- and only one of them could overlay, which is how "the only way
// to overlay frames is to use the frame dock active frame window" happened.
// This card and the projection control in the view bar author the SAME
// `FrameSelection` and the same expression, through the one row below.
//
// A ROW IS A LINK, never an inline editor: click the name and the frame's own
// card opens as a tile. An editor embedded per row is a second authoring path
// for the same record, and two paths disagree.
//
// The find box is a FIND, not a filter: it narrows what this list shows and
// changes nothing about what any lens projects. Rows are virtualized, so five
// hundred calendars cost one screen of widgets.

import 'package:flutter/material.dart';

import '../chrome/controls.dart';
import '../chrome/frame_menu.dart';
import '../chrome/menus.dart';
import '../chrome/projection_control.dart';
import '../core/calendar_structure.dart';
import '../core/records.dart';
import '../lens/color.dart';
import '../lens/theme.dart';
import '../session/view_state.dart';
import 'card_chrome.dart';

/// The one projection row: lead marker, colour, name, the groups it belongs to,
/// and the NOT that authors the filter effect. Plain selection is OR.
Widget frameProjectionRow(
  BuildContext context, {
  required ViewState view,
  required Frame frame,
  Iterable<String> groups = const [],
  VoidCallback? onOpen,
  bool basisGap = false,
  List<Widget> trailing = const [],
}) {
  final chrome = ChromeScope.of(context);
  final theme = ChronoTheme.of(context);
  final state = isStateFrame(frame);
  final selected = view.selection.isSelected(frame.id);
  final primary = view.selection.isPrimary(frame.id);
  final negated = view.negated.contains(frame.id);
  void touch(VoidCallback change) {
    change();
    // Any row action means the plain selection speaks again, not the text.
    view.source = '';
    chrome.views.touch();
  }

  return SizedBox(
    height: cardPx(context, 'card.rowHeight'),
    child: Row(
      children: [
        Tooltip(
          message: state ? 'A state frame may be projected, but never lead.' : 'Lead with this',
          child: InkWell(
            onTap: state ? null : () => touch(() => view.selection.setPrimary(frame.id)),
            child: Text(
              primary ? '◉' : '○',
              style: dataStyle(
                context,
                color: state ? theme.hair : (primary ? theme.primary : theme.strong),
              ),
            ),
          ),
        ),
        SizedBox(width: cardPx(context, 'card.gap')),
        InkWell(
          onTap: () => touch(() => view.selection.toggle(frame.id)),
          child: Container(
            width: cardPx(context, 'card.swatch'),
            height: cardPx(context, 'card.swatch'),
            decoration: BoxDecoration(
              color: authoredColorOf(frame.extra),
              border: Border.all(
                color: selected ? theme.ink : theme.hair,
                width: chrome.px(selected ? 'chrome.focusRing' : 'chrome.hair'),
              ),
            ),
          ),
        ),
        SizedBox(width: cardPx(context, 'card.gap')),
        // THE FRAME'S VERBS, WHERE THE FRAME IS NAMED (ISSUES 9.2). The one
        // source -- the same rows the reading on the bar offers -- rather than
        // a second list spelled for this surface.
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onSecondaryTapUp: (details) => showChronoMenu(
              context,
              details.globalPosition,
              frameMenu(context, view, frame.id),
            ),
            child: cardLink(context, frame.title ?? frame.id, onOpen),
          ),
        ),
        if (basisGap)
          Tooltip(
            message: 'No basis: this frame counts in nothing, so it projects nothing.',
            child: Text('unbased', style: labelStyle(context, color: theme.primary)),
          ),
        if (groups.isNotEmpty) cardChips(context, groups),
        ...trailing,
        SizedBox(width: cardPx(context, 'card.gap')),
        if (selected)
          InkWell(
            onTap: () =>
                touch(() => negated ? view.negated.remove(frame.id) : view.negated.add(frame.id)),
            child: Text(
              'not',
              style: labelStyle(context, color: negated ? theme.primary : theme.hair),
            ),
          ),
      ],
    ),
  );
}

/// The frames STANDING as columns on a view, whatever surface reads them.
List<String> standingColumns(ViewState view) => switch (view.view['columns']) {
  final List<Object?> chosen => [for (final id in chosen) '$id'],
  _ => const [],
};

/// PULL A FRAME UP AS A COLUMN (ISSUES 9.1: "Board, group by frame: I see no
/// power to pull up frames ... the chosen-columns half was never built").
///
/// The board's own chooser writes `view['columns']`, and this is the other half
/// of the same affordance, at the surface where frames are already listed --
/// "the frames browser's rows are the natural chooser". One key, two doors, and
/// neither of them a second list of frames.
Widget standColumn(BuildContext context, ViewState view, Frame frame) {
  final chrome = ChromeScope.of(context);
  final theme = ChronoTheme.of(context);
  final standing = standingColumns(view).contains(frame.id);
  return Tooltip(
    message: standing
        ? 'Standing as a column. A surface with columns holds it open even when '
              'nothing is in it.'
        : 'Stand this frame as a column where the surface has columns.',
    child: InkWell(
      onTap: () {
        final was = standingColumns(view);
        view.write('columns', [
          for (final id in was)
            if (id != frame.id) id,
          if (!standing) frame.id,
        ]);
        chrome.views.touch();
      },
      child: Text(
        'column',
        style: labelStyle(context, color: standing ? theme.primary : theme.hair),
      ),
    ),
  );
}

class FramesBrowser extends StatefulWidget {
  const FramesBrowser({super.key, this.onOpen, this.onClose});

  final void Function(String frameId)? onOpen;
  final VoidCallback? onClose;

  @override
  State<FramesBrowser> createState() => _FramesBrowserState();
}

class _FramesBrowserState extends State<FramesBrowser> {
  String _find = '';

  @override
  Widget build(BuildContext context) {
    // A CONTROL THAT READS LIVE STATE OWNS ITS LISTENING (ISSUES 9.1, the frozen
    // projection drop). Every row here reads the focused view -- what it
    // projects, what leads it, what stands as a column -- so the list re-runs
    // when that changes rather than showing the state it was born with.
    return ListenableBuilder(
      listenable: ChromeScope.of(context).views,
      builder: (context, _) => _list(context),
    );
  }

  Widget _list(BuildContext context) {
    final chrome = ChromeScope.of(context);
    final editor = chrome.editor;
    final view = chrome.focusedView;
    final document = editor?.document;
    final needle = _find.trim().toLowerCase();
    final frames = [
      for (final frame in document?.frames.values ?? const <Frame>[])
        if (needle.isEmpty || (frame.title ?? frame.id).toLowerCase().contains(needle)) frame,
    ]..sort((left, right) => (left.title ?? left.id).compareTo(right.title ?? right.id));
    return CardShell(
      title: 'Frames',
      sigil: '▤',
      onClose: widget.onClose,
      foldLabel: 'What a row does',
      primary: [
        CardField(
          value: _find,
          width: double.infinity,
          hint: 'Find a frame',
          onChanged: (text) => setState(() => _find = text),
        ),
        if (view == null)
          cardNote(context, 'No view is focused, so nothing here can be projected yet.')
        else
          SizedBox(
            height: cardPx(context, 'card.listHeight'),
            child: ListView.builder(
              itemCount: frames.length,
              itemExtent: cardPx(context, 'card.rowHeight'),
              itemBuilder: (context, index) => frameProjectionRow(
                context,
                view: view,
                frame: frames[index],
                groups: [
                  for (final id in editor!.engine.indexes.directGroupsOf(frames[index].id))
                    document?.frames[id]?.title ?? id,
                ],
                // A frame that owns no structure and inherits none counts in
                // nothing, so it projects nothing -- said here, where the
                // author is looking at the list.
                basisGap:
                    frames[index].basis == null &&
                    frames[index].coordinate == null &&
                    frameAuthoringCapabilities('', frames[index].traits).basis,
                trailing: [standColumn(context, view, frames[index])],
                onOpen: () => widget.onOpen?.call(frames[index].id),
              ),
            ),
          ),
      ],
      fold: [
        cardNote(
          context,
          'The ring leads: the frame whose calendar reads the axis. The swatch'
          ' overlays: every selected frame draws. "not" removes what it names --'
          ' that is what a filter is here. "column" stands the frame as a column'
          ' where the surface has columns, empty or not. The name opens the'
          ' frame’s own card.',
        ),
      ],
      // THE CREATE DOOR MINTS A FRAME (ISSUES 9.1). The footer used to iterate
      // a const list of three nouns -- "which looks a lot like an enum to me",
      // and it was one. Frames are groups and kinds are trait bundles, so there
      // is one create affordance here, shared with every other list of frames,
      // and what the frame IS is authored on the card that opens.
      //
      // AND AUTHORING AN OBJECT IS A DOCUMENT ACT (ISSUES 9.1): "no door in the
      // app opens a blank object card, so a note cannot be authored outside a
      // lens at all". A lens coordinate is one way to start the sentence, never
      // the only way -- so the blank cards are reachable from here.
      footer: [
        cardDoors(context, [
          newFrameDoor(),
          ...mintingDoors(),
          cardDoor(
            'The document',
            'What this document is called, where it saves, what crosses the ICS '
                'boundary.',
            (factory) => factory.documentCard(),
          ),
          cardDoor(
            'Settings',
            'Every tunable in the program, in words, cut by the surface it '
                'governs.',
            (factory) => factory.settingsCard(),
          ),
        ]),
      ],
    );
  }
}
