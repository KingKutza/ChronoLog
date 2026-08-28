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
        Expanded(child: cardLink(context, frame.title ?? frame.id, onOpen)),
        if (basisGap)
          Tooltip(
            message: 'No basis: this frame counts in nothing, so it projects nothing.',
            child: Text('unbased', style: labelStyle(context, color: theme.primary)),
          ),
        if (groups.isNotEmpty) cardChips(context, groups),
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

class FramesBrowser extends StatefulWidget {
  const FramesBrowser({super.key, this.onOpen, this.onCreate, this.onClose});

  final void Function(String frameId)? onOpen;
  final void Function(String kind)? onCreate;
  final VoidCallback? onClose;

  @override
  State<FramesBrowser> createState() => _FramesBrowserState();
}

class _FramesBrowserState extends State<FramesBrowser> {
  String _find = '';

  @override
  Widget build(BuildContext context) {
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
          ' that is what a filter is here. The name opens the frame’s own card.',
        ),
      ],
      footer: [
        for (final kind in const ['calendar', 'group', 'state'])
          namedAction(
            context,
            '+ ${kind[0].toUpperCase()}${kind.substring(1)}',
            onTap: widget.onCreate == null ? null : () => widget.onCreate!(kind),
          ),
      ],
    );
  }
}
