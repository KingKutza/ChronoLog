// The document bar: what this document is, whether it is safe, and the actions
// that act on the whole of it.
//
// It holds no forms. The document menu OPENS TILES -- the document card, the
// settings card, the frames browser, import and export, themes -- because a bar
// that grows a form is the "very programmer interface" complaint in miniature.
//
// THE SAVE CONTROL IS DISCOVERABLE (ISSUES 8.31, evening, Don live: "Also still
// no save button"). The control was there since 8/28 as a bare glyph whose only
// words lived in a tooltip, which is the same defect as not having one: nothing
// on the bar said "save". So the glyph now carries its WORD beside it, and the
// save state is read off the bar in words rather than hovered for -- colour is
// the glance, the words are the claim, and neither carries the meaning alone.

import 'package:flutter/material.dart';

import '../cards/card_chrome.dart';
import '../lens/theme.dart';
import '../store/document_store.dart';
import 'controls.dart';
import 'menus.dart';

class DocumentBar extends StatelessWidget {
  const DocumentBar({super.key});

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeScope.of(context);
    final editor = chrome.editor;
    return ListenableBuilder(
      listenable: chrome.pulse,
      builder: (context, _) => barShell(
        context,
        [
          barItem(
            chrome.title,
            Text(chrome.title, style: bodyStyle(context)),
            compact: const SizedBox.shrink(),
          ),
          barItem('Save state', _state(context)),
        ],
        trailing: [
          barAction(
            context,
            'Undo',
            glyph: '↶',
            hint: 'Undo the last edit',
            onTap: editor != null && editor.canUndo ? editor.undo : null,
          ),
          barItem('Save', _save(context), compact: _save(context, word: false)),
          barAction(
            context,
            'Redo',
            glyph: '↷',
            hint: 'Redo the last undone edit',
            onTap: editor != null && editor.canRedo ? editor.redo : null,
          ),
          barItem(
            'Document',
            ChronoMenu(
              label: 'Document',
              glyph: '⋯',
              rows: [
                for (final entry in chrome.cards.entries)
                  menuRow(entry.value().title, () => chrome.stage.open(entry.value())),
                if (chrome.cards.isEmpty) menuRow('No cards are registered yet.', null),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What the save state is, in every register the bar speaks: the colour of the
/// lamp, the short words on the bar, and the whole claim a reader (or a screen
/// reader) is given.
({Color color, String words, String said}) _saveState(BuildContext c) {
  final theme = ChronoTheme.of(c);
  final status = ChromeScope.of(c).editor?.store.status;
  return switch (status?.state) {
    SaveState.clean => (color: theme.secondary, words: 'saved', said: 'Saved.'),
    SaveState.dirty => (color: theme.accent, words: 'unsaved edits', said: 'Unsaved changes.'),
    SaveState.saving => (color: theme.accent, words: 'saving…', said: 'Saving…'),
    SaveState.error => (
      color: theme.primary,
      words: 'not saved',
      said: 'Not saved: ${status?.error}',
    ),
    _ => (color: theme.hair, words: 'no document', said: 'No document is open.'),
  };
}

/// The save state ON THE BAR, in words. The lamp is the glance; this is the
/// claim, and it is not behind a hover.
Widget _state(BuildContext c) {
  final state = _saveState(c);
  return Semantics(
    label: state.said,
    child: Tooltip(
      message: state.said,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _lamp(c, state.color),
          SizedBox(width: cardPx(c, 'document.saveGap')),
          Text(state.words, style: labelStyle(c, color: state.color)),
        ],
      ),
    ),
  );
}

/// The lamp: colour AND never colour alone -- every site that draws it puts the
/// words beside it.
Widget _lamp(BuildContext c, Color color) {
  final chrome = ChromeScope.of(c);
  final size = cardPx(c, 'document.lamp');
  return AnimatedContainer(
    duration: chrome.motion,
    curve: chrome.curve,
    width: size,
    height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );
}

/// THE SAVE BUTTON: the mark and the word together. [word] is dropped only when
/// the bar has run out of room for it, which is the one bar rule.
Widget _save(BuildContext c, {bool word = true}) {
  final editor = ChromeScope.of(c).editor;
  final state = _saveState(c);
  return Semantics(
    label: 'Save',
    button: true,
    enabled: editor != null,
    child: controlChip(
      c,
      hint: 'Write the document now — ${state.said}',
      onTap: editor == null ? null : () => editor.store.save(force: true),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '◍',
            style: dataStyle(
              c,
              color: editor == null ? ChronoTheme.of(c).hair : state.color,
            ),
          ),
          if (word) ...[
            SizedBox(width: cardPx(c, 'document.saveGap')),
            Text('Save', style: bodyStyle(c)),
          ],
        ],
      ),
    ),
  );
}
