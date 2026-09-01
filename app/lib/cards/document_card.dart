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
// THE PATH FIELD IS THE ALWAYS-VALID SECOND ROAD. A path naming a directory
// lists the .ics files in it to pick from, and a path naming a file is that
// file. Export writes to that path, or to `<title>.ics` inside it when it is a
// directory, and SHOWS the path it wrote. So a platform with no dialog loses a
// convenience, never the boundary.
//
// TWO AUTHORED LOCATIONS, NEITHER A SINGLETON (Don, 8.31: "I don't appear to be
// able to set a save location, only a location to look for .ics file and even
// then only one such location"):
//
//   `document.saveAt` is WHERE THE CHRONOLOG SAVES. Empty means beside the app,
//   which is the portable default and not a blessed directory. Writing a path
//   here MOVES the document -- through the journal machinery, so it is still an
//   update path -- and a directory another chronolog occupies is refused in
//   words rather than overwritten.
//
//   `document.icsPaths` is WHERE CALENDARS ARE LOOKED FOR, one location PER
//   LINE. A list, because a person has a work feed and a home feed and no
//   reason to choose between them.

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
import '../store/journal.dart';
import 'card_chrome.dart';

/// The settings this card authors that are not arithmetic. Reading a path as
/// algebra would be a category error, so it is a TEXT setting.
const Map<String, String> frameCardTextDefaults = {
  'document.icsPaths': '',
  'document.saveAt': '',
  // WHAT THE COLOUR PICKER OFFERS: authored colour names, not a closed set of
  // legal colours. The field takes any name or hex the reader knows; this is
  // the short way in, and a person who wants another palette writes one.
  'card.palette':
      'crimson orangered orange gold yellowgreen seagreen teal steelblue '
          'royalblue slateblue rebeccapurple orchid sienna olive slategray dimgray',
  // WHAT THE CARD'S X DOES, by name (ISSUES 8.31: "what the card's X does by
  // default is a settings key -- Don's instinct: save, but that is just a
  // setting"). The value names one of the card's own verbs; a name no card
  // offers is refused in words rather than guessed at.
  'card.closeVerb': 'save',
  // WHAT A NEW FRAME STARTS AS. A seed, not a species (ISSUES 9.1: "kinds are
  // TRAIT BUNDLES, not species"). The create door mints A FRAME; this is the
  // bundle the card opens holding, and every word of it is authored on the card.
  'card.newFrameTraits': 'set calendar',
  // SETTINGS OVER SETTINGS (ISSUES 9.1, Don's ruling: "the counts are shapes,
  // not literals"). Which keys the main settings card puts in front of you is
  // itself a setting -- so "the top fifteen most general" is an authored list a
  // person can rewrite, never a hardcoded fifteen.
  'settings.general':
      'chrome.body chrome.hit theme.name motion.duration card.closeVerb '
          'document.saveAt document.icsPaths edit.historyDepth edit.newSpanDays '
          'edit.snapGrainMinutes pointer.zoomStep pointer.dragThreshold '
          'stage.splitRatio stage.maxTabs weight.halfDistanceDays',
};

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
    final at = authoredPaths(
      ChromeScope.of(context).settings.text('document.icsPaths'),
      root,
    ).first;
    final picked = saving
        ? await picker.save(
            initialPath: at,
            suggestedName: '${declaredTitle(editor.document)}.ics',
            extensions: const ['ics'],
          )
        : await picker.open(initialPath: at, extensions: const ['ics']);
    if (picked.refusal.isNotEmpty) return setState(() => _note = picked.refusal);
    final path = picked.path;
    if (path == null) return;
    if (saving && frameId != null) return _export(editor, frameId, path);
    if (!saving) return _import(editor, path);
  }

  /// WHERE THE CHRONOLOG SAVES, chosen. The host's dialog names a FILE; the
  /// location is the directory that file sits in, because the document's own
  /// file names are the store's and not the author's to pick. Writing the
  /// setting is the whole act -- the workspace watches it and moves the
  /// document, so the card and `chronolog.settings` are the same road.
  Future<void> _chooseSaveLocation(Chrome chrome, String at) async {
    final picker = widget.picker;
    if (picker == null) {
      return setState(() => _note = 'No file dialog here — write the path below.');
    }
    final picked = await picker.save(initialPath: at, suggestedName: snapshotFileName);
    if (picked.refusal.isNotEmpty) return setState(() => _note = picked.refusal);
    final path = picked.path;
    if (path == null) return;
    final chosen = parentDirectory(path);
    chrome.settings.setText('document.saveAt', chosen);
    setState(() => _note = 'The chronolog saves to $chosen.');
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
    // WHERE THE DOCUMENT SAVES, and WHERE CALENDARS ARE LOOKED FOR: one
    // resolver, two authored settings, and the second one is a LIST.
    final saveAt = authoredPath(chrome.settings.text('document.saveAt'), root);
    final locations = authoredPaths(chrome.settings.text('document.icsPaths'), root);
    final found = {for (final at in locations) at: icsFilesIn(at)};
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
        cardTextRow(
          context,
          'Saves to',
          chrome.settings.text('document.saveAt'),
          (text) => setState(() => chrome.settings.setText('document.saveAt', text)),
          hint: root,
          mono: true,
          width: double.infinity,
        ),
        // THE WAYS ONWARD. The document is where a person arrives with nothing
        // in mind, so it owes the doors to everything else -- including the
        // blank object cards, because authoring an object is a document act and
        // not a lens act (ISSUES 9.1).
        cardDoors(context, [
          cardDoor(
            'Frames',
            'The one list of every frame in this document.',
            (factory) => factory.framesBrowser(),
          ),
          newFrameDoor(),
          ...mintingDoors(),
          cardDoor(
            'Settings',
            'Every tunable in the program, in words, cut by the surface it '
                'governs.',
            (factory) => factory.settingsCard(),
          ),
          cardDoor(
            'The palette',
            'The colours the whole surface is drawn in. Apply is live; Save '
                'writes a file.',
            (factory) => factory.themesCard(),
          ),
        ]),
        cardWrap(context, [
          namedAction(
            context,
            'Choose a folder…',
            hint: 'The dialog this host provides, where it provides one',
            onTap: () => _chooseSaveLocation(chrome, saveAt),
          ),
          namedAction(
            context,
            'Beside the app',
            hint: root,
            onTap: chrome.settings.text('document.saveAt').trim().isEmpty
                ? null
                : () => setState(() => chrome.settings.setText('document.saveAt', '')),
          ),
        ]),
        cardNote(
          context,
          // WHERE IT ACTUALLY IS, read off the store rather than off the field:
          // a refused move leaves the words in the box and the document where it
          // was, and a card that reported the box would be lying.
          'Saving to ${editor.store.journal.dataRoot}. An empty path is beside'
          ' the app, which is where a'
          ' portable chronolog lives by default; any other path is yours. Moving'
          ' writes the document at the new place and leaves the old files where'
          ' they are.',
        ),
        if (_note != null) cardNote(context, _note!),
        for (final warning in _warnings) cardNote(context, warning, refusal: true),
        // The settings layer's own refusals for these keys -- a save location
        // another chronolog already occupies says so here.
        for (final line in chrome.settings.refusals)
          if (line.startsWith('document.')) cardNote(context, line, refusal: true),
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
          chrome.settings.text('document.icsPaths'),
          (text) => setState(() => chrome.settings.setText('document.icsPaths', text)),
          hint: root,
          mono: true,
          width: double.infinity,
          lines: cardPx(context, 'card.textLines').round(),
        ),
        cardNote(
          context,
          'ONE LOCATION PER LINE, as many as you keep calendars in. A folder'
          ' lists the .ics files in it; a file is that file. Export writes to'
          ' the first location, and says the path it wrote.',
        ),
        cardWrap(context, [
          namedAction(
            context,
            'Choose a file…',
            hint: 'The dialog this host provides, where it provides one',
            onTap: () => _browse(editor, saving: false),
          ),
          for (final entry in found.entries) ...[
            for (final file in entry.value)
              namedAction(
                context,
                'Import ${file.split(Platform.pathSeparator).last}',
                hint: file,
                onTap: () => _import(editor, file),
              ),
            // A location naming a file, or a folder holding no calendar, is
            // still a location: it offers itself rather than vanishing.
            if (entry.value.isEmpty)
              namedAction(
                context,
                'Import ${entry.key.split(Platform.pathSeparator).last}',
                hint: entry.key,
                onTap: () => _import(editor, entry.key),
              ),
          ],
          for (final frame in calendars) ...[
            namedAction(
              context,
              'Export ${frame.title ?? frame.id}',
              hint: 'Rules where ICS can say them, occurrences where it cannot',
              onTap: () => _export(editor, frame.id, locations.first),
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
