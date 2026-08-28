// The document itself: what it is called, whether it is written down, where it
// lives, what crosses the ICS boundary, and which layouts are saved.
//
// This is the card the document menu OPENS. The old build put these controls in
// a dropdown -- "Document dropdown should just open a proper settings card in
// the dock, not that mess, and not document things should not be nested under a
// label called documents."
//
// ICS is an explicitly lossy boundary: an import is ONE undoable entry and its
// warnings are shown rather than swallowed; an export writes rules where ICS can
// say them and projections where it cannot.
//
// PORTABLE, WITH NO PLUGIN. The host's own dialog is reached through
// `lib/host/file_picker.dart` -- dart:ffi into comdlg32 on Windows, a stated
// refusal where no child is built -- because a plugin would need symlink
// support this machine's policy forbids, and a feature that cannot be built is
// not a feature.
//
// THE PATH FIELD IS THE ALWAYS-VALID SECOND ROAD. `document.icsPath` defaults
// to the app's own data directory; a path naming a directory lists the .ics
// files in it to pick from, and a path naming a file is that file. Export
// writes to that path, or to `<title>.ics` inside it when it is a directory,
// and SHOWS the path it wrote. So a platform with no dialog loses a
// convenience, never the boundary.

import 'dart:io';

import 'package:flutter/material.dart';

import '../chrome/controls.dart';
import '../core/ics.dart';
import '../core/records.dart';
import '../edit/editor.dart';
import '../host/file_picker.dart';
import '../lens/theme.dart';
import '../store/data_dir.dart';
import '../store/document_store.dart';
import 'card_chrome.dart';

/// The settings this card authors that are not arithmetic. Reading a path as
/// algebra would be a category error, so it is a TEXT setting.
const Map<String, String> frameCardTextDefaults = {'document.icsPath': ''};

/// Where ICS crosses, resolved: the authored path, or the data root when the
/// author has written none.
String icsPathOf(String? authored, String root) =>
    (authored ?? '').trim().isEmpty ? root : authored!.trim();

/// The .ics files a directory holds, by full path, in name order. A path that
/// is not a directory yields nothing: it is already the answer.
List<String> icsFilesIn(String path) {
  final directory = Directory(path);
  if (!directory.existsSync()) return const [];
  return [
    for (final entry in directory.listSync())
      if (entry is File && entry.path.toLowerCase().endsWith('.ics')) entry.path,
  ]..sort();
}

/// One import, one undo entry. Separated from the path so the act can be
/// proven without a filesystem.
IcsImport importIcsText(Editor editor, String text) {
  final result = importIcs(text, editor.document);
  editor.commit('Import calendar', result.document);
  return result;
}

class DocumentCard extends StatefulWidget {
  const DocumentCard({super.key, this.onClose, this.root, this.picker});

  final VoidCallback? onClose;

  /// The data directory. Injected so a spec can answer without one.
  final String? root;

  /// The host's file dialog. Absent, the path field is the whole road, which
  /// it always is anyway.
  final FilePicker? picker;

  @override
  State<DocumentCard> createState() => _DocumentCardState();
}

class _DocumentCardState extends State<DocumentCard> {
  List<String> _warnings = const [];
  String _preset = '';
  String? _note;

  Future<void> _import(Editor editor, String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      return setState(() => _note = 'No file at $path.');
    }
    final result = importIcsText(editor, await file.readAsString());
    setState(() {
      _warnings = result.warnings;
      _note =
          'Imported ${result.events.length} objects on ${result.frames.length} frames'
          ' from $path, as one undoable change.';
    });
  }

  /// The host's dialog, where there is one. A refusal is SHOWN and the path
  /// field answers instead; a cancel says nothing, because nothing happened.
  Future<void> _browse(Editor editor, {required bool saving, String? frameId}) async {
    final picker = widget.picker;
    if (picker == null) {
      return setState(() => _note = 'No file dialog here — use the path below.');
    }
    final root = widget.root ?? resolveDataRoot();
    final at = icsPathOf(ChromeScope.of(context).settings.text('document.icsPath'), root);
    final picked = saving
        ? await picker.save(initialPath: at, suggestedName: '${declaredTitle(editor.document)}.ics')
        : await picker.open(initialPath: at, extensions: const ['ics']);
    if (picked.refusal.isNotEmpty) return setState(() => _note = picked.refusal);
    final path = picked.path;
    if (path == null) return;
    if (saving && frameId != null) return _export(editor, frameId, path);
    if (!saving) return _import(editor, path);
  }

  Future<void> _export(Editor editor, String frameId, String path) async {
    final directory = Directory(path).existsSync();
    final target = directory ? storePath(path, '${declaredTitle(editor.document)}.ics') : path;
    final text = exportIcs(editor.document, frame: frameId, engine: editor.engine);
    await File(target).writeAsString(text);
    setState(() => _note = 'Exported to $target.');
  }

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeScope.of(context);
    final theme = ChronoTheme.of(context);
    final editor = chrome.editor;
    if (editor == null) {
      return CardShell(
        title: 'Document',
        onClose: widget.onClose,
        primary: [cardNote(context, 'No document is open.', refusal: true)],
      );
    }
    final status = editor.store.status;
    final root = widget.root ?? resolveDataRoot();
    final ics = icsPathOf(chrome.settings.text('document.icsPath'), root);
    final found = icsFilesIn(ics);
    final calendars = [
      for (final frame in editor.document.frames.values)
        if (frame.traits.contains('calendar')) frame,
    ];
    return CardShell(
      title: declaredTitle(editor.document),
      sigil: '▣',
      dirty: status.dirty,
      onClose: widget.onClose,
      foldLabel: 'Storage, boundary and layouts',
      primary: [
        cardTextRow(
          context,
          'Title',
          declaredTitle(editor.document),
          (text) => editor.commit(
            'Rename document',
            editor.document.copyWith(meta: {...editor.document.meta, 'title': text}),
          ),
        ),
        cardRow(
          context,
          'Saved',
          // WRAPS, never clips: a card is a tile and a tile can be any width.
          cardWrap(context, [
            Tooltip(
              message: '${status.state.name}${status.error == null ? '' : ': ${status.error}'}',
              child: Text(
                status.dirty ? '● unsaved edits' : '○ ${status.state.name}',
                style: dataStyle(
                  context,
                  color: status.state == SaveState.error
                      ? theme.primary
                      : (status.dirty ? theme.accent : theme.strong),
                ),
              ),
            ),
            namedAction(context, 'Save now', onTap: () => editor.store.save(force: true)),
          ]),
        ),
        if (_note != null) cardNote(context, _note!),
        for (final warning in _warnings) cardNote(context, warning, refusal: true),
      ],
      fold: [
        cardRow(
          context,
          'Data directory',
          SelectableText(root, style: dataStyle(context, color: theme.strong)),
        ),
        ExpressionField(
          label: 'Snapshot every (minutes)',
          source: chrome.settings.expressionOf('document.compactMinutes').isEmpty
              ? '${cardTunable(chrome.settings, 'document.compactMinutes')}'
              : chrome.settings.expressionOf('document.compactMinutes'),
          onChanged: (source) => chrome.settings.set('document.compactMinutes', source),
        ),
        cardTextRow(
          context,
          'Calendars at',
          chrome.settings.text('document.icsPath'),
          (text) => setState(() => chrome.settings.setText('document.icsPath', text)),
          hint: root,
          mono: true,
          width: double.infinity,
        ),
        cardNote(
          context,
          'A folder lists the .ics files in it; a file is that file. Export'
          ' writes there, and says the path it wrote.',
        ),
        cardWrap(context, [
          namedAction(
            context,
            'Choose a file…',
            hint: 'The dialog this host provides, where it provides one',
            onTap: () => _browse(editor, saving: false),
          ),
          for (final file in found)
            namedAction(
              context,
              'Import ${file.split(Platform.pathSeparator).last}',
              hint: file,
              onTap: () => _import(editor, file),
            ),
          if (found.isEmpty)
            namedAction(context, 'Import this file', hint: ics, onTap: () => _import(editor, ics)),
          for (final frame in calendars) ...[
            namedAction(
              context,
              'Export ${frame.title ?? frame.id}',
              hint: 'Rules where ICS can say them, occurrences where it cannot',
              onTap: () => _export(editor, frame.id, ics),
            ),
            namedAction(
              context,
              'Export ${frame.title ?? frame.id} to…',
              hint: 'Choose where, in the dialog this host provides',
              onTap: () => _browse(editor, saving: true, frameId: frame.id),
            ),
          ],
        ]),
        cardRow(
          context,
          'Layout preset',
          cardWrap(context, [
            CardField(
              value: _preset,
              hint: 'name this arrangement',
              onChanged: (text) => setState(() => _preset = text),
            ),
            namedAction(
              context,
              'Save layout',
              onTap: _preset.trim().isEmpty ? null : () => chrome.stage.savePreset(_preset.trim()),
            ),
          ]),
        ),
        cardWrap(context, [
          for (final name in chrome.stage.presets.keys)
            namedAction(context, name, onTap: () => chrome.stage.applyPreset(name)),
        ]),
      ],
    );
  }
}

String declaredTitle(Document document) => '${document.meta['title'] ?? 'Untitled Chronolog'}';
