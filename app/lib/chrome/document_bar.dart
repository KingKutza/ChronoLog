// The document bar: what this document is, whether it is safe, and the actions
// that act on the whole of it.
//
// It holds no forms. The document menu OPENS TILES -- the document card, the
// settings card, the frames browser, import and export, themes -- because a bar
// that grows a form is the "very programmer interface" complaint in miniature.

import 'package:flutter/material.dart';

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
          barItem('Save state', _lamp(context)),
        ],
        trailing: [
          barAction(
            context,
            'Undo',
            glyph: '↶',
            hint: 'Undo the last edit',
            onTap: editor != null && editor.canUndo ? editor.undo : null,
          ),
          barAction(
            context,
            'Save',
            glyph: '◍',
            hint: 'Write the document now',
            onTap: editor == null ? null : () => editor.store.save(force: true),
          ),
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

/// Save state as colour AND as words: the colour is the glance, the tooltip is
/// the claim. Colour alone never carries meaning here either.
Widget _lamp(BuildContext c) {
  final chrome = ChromeScope.of(c);
  final theme = ChronoTheme.of(c);
  final status = chrome.editor?.store.status;
  final (color, message) = switch (status?.state) {
    SaveState.clean => (theme.secondary, 'Saved.'),
    SaveState.dirty => (theme.accent, 'Unsaved changes.'),
    SaveState.saving => (theme.accent, 'Saving…'),
    SaveState.error => (theme.primary, 'Not saved: ${status?.error}'),
    _ => (theme.hair, 'No document is open.'),
  };
  final dot = chrome.px('chrome.label');
  return Tooltip(
    message: message,
    child: Semantics(
      label: message,
      child: AnimatedContainer(
        duration: chrome.motion,
        curve: chrome.curve,
        width: dot,
        height: dot,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    ),
  );
}
