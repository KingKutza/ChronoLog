// THE WHOLE LIST OF WHAT IS STAPLED TO ONE RECORD.
//
// ISSUES 9.2 (Don): "frames with a lot of events are overflowing rather than
// showing staples. Perhaps a list of stapled items by type." The frame card
// answers the reading question in place -- a window per kind and the true count
// beside it -- and this is where the rest lives: the door off that window, the
// same shape the All frames door already is.
//
// "+N more." was the thing it replaces, and the reason is that a truncation
// note is a dead end: it says what you cannot see and offers no way to see it.
//
// OVERSCALE. Nothing here enumerates into widgets: the rows are virtualized and
// a find narrows them, so five hundred members cost one screen. The counting is
// the neighbourhood query's own, which counts everything and lists a window --
// the count on this card is the true total, however few rows are drawn.

import 'package:flutter/material.dart';

import '../chrome/controls.dart';
import '../core/records.dart';
import '../core/stapled_here.dart';
import 'card_chrome.dart';
import 'card_factory.dart';

class StapledBrowser extends StatefulWidget {
  const StapledBrowser({super.key, required this.recordId, this.onClose});

  /// The frame or object whose neighbourhood this lists.
  final String recordId;

  final VoidCallback? onClose;

  @override
  State<StapledBrowser> createState() => _StapledBrowserState();
}

class _StapledBrowserState extends State<StapledBrowser> {
  String _find = '';

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeScope.of(context);
    final editor = chrome.editor;
    if (editor == null) {
      return CardShell(
        title: 'Stapled here',
        onClose: widget.onClose,
        primary: [cardNote(context, 'No document is open.', refusal: true)],
      );
    }
    final document = editor.document;
    final title =
        document.frames[widget.recordId]?.title ??
        str(document.events[widget.recordId]?.payload?['title']) ??
        widget.recordId;
    // The whole neighbourhood, counted and listed: this card IS the full list,
    // so it asks for no window.
    final here = stapledHere(editor.engine, widget.recordId);
    final needle = _find.trim().toLowerCase();
    String nameOf(String id) =>
        document.frames[id]?.title ?? str(document.events[id]?.payload?['title']) ?? id;
    return CardShell(
      title: 'Stapled to $title',
      sigil: '▤',
      onClose: widget.onClose,
      primary: [
        CardField(
          value: _find,
          width: double.infinity,
          hint: 'Find one of these',
          onChanged: (text) => setState(() => _find = text),
        ),
        for (final group in here.groups)
          Builder(
            builder: (context) {
              final rows = [
                for (final id in group.window)
                  if (needle.isEmpty || nameOf(id).toLowerCase().contains(needle)) id,
              ]..sort((left, right) => nameOf(left).compareTo(nameOf(right)));
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${group.label} — ${group.total}',
                    style: labelStyle(context),
                  ),
                  SizedBox(
                    height: cardPx(context, 'card.listHeight'),
                    child: ListView.builder(
                      itemCount: rows.length,
                      itemExtent: cardPx(context, 'card.rowHeight'),
                      itemBuilder: (context, index) => cardLink(
                        context,
                        nameOf(rows[index]),
                        () => group.kind == stapledFrameKind
                            ? CardHost.maybeOf(context)?.openFrame(rows[index])
                            : CardHost.maybeOf(context)?.openObject(rows[index]),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        if (here.groups.isEmpty) cardNote(context, 'Nothing is stapled here yet.'),
      ],
      footer: [
        cardDoors(context, [
          cardDoor(
            'All frames',
            'The one list of every frame in this document.',
            (factory) => factory.framesBrowser(),
          ),
        ]),
      ],
    );
  }
}
