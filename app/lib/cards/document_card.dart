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
// THREE DOORS ON THE DOCUMENT, NOT ONE (Don, ISSUES 9.2: "No clear mechanism to
// delete all the old data and start a new chronolog -- I had to follow the path
// and delete the directory"):
//
//   NEW is the default and it is option (a): a fresh document at a new location,
//   the old files LEFT IN PLACE. Nothing is deleted by making something.
//
//   OPEN reaches another chronolog, because "sometimes it might make sense to
//   have two chronologs, instead of just two frames" -- multiple documents are
//   a legitimate shape and the door says so.
//
//   DELETE ALL is option (b), its own door, explicitly destructive and never
//   silent: it is armed by TYPING THE WORD (`document.deleteWord`) and nothing
//   else. It is the one act in the program with no undo, which is why it asks
//   for a word instead of a confirmation -- "no confirmation dialogs" is the
//   standing rule, and typing the word is an authored act rather than a dialog
//   a person clicks through without reading.
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
  // THE WORD THAT ARMS THE DELETION (Don, ISSUES 9.2: "behind a type-to-confirm
  // popup -- type the word, obliviate-style -- because full deletion is mostly
  // a testing act but has legitimate cases and no undo"). It is a SETTING and
  // not a constant, because which word a person has to type is not the engine's
  // to decide: a shared machine may want a longer one.
  'document.deleteWord': 'delete',
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
  List<IcsWarningClass> _warnings = const [];
  final Set<String> _opened = {};
  String _preset = '', _elsewhere = '', _typed = '';
  String? _note;

  /// NEW: a fresh chronolog somewhere else, the files here left alone.
  Future<void> _new(Editor editor, String at) async {
    final refusal = await editor.store.establishAt(at);
    editor.resync();
    setState(
      () => _note = refusal ?? 'A new chronolog stands at $at. The old files are where they were.',
    );
  }

  /// OPEN: the chronolog at another location, loaded the way a boot loads one.
  Future<void> _open(Editor editor, String at) async {
    if (at.trim().isEmpty) return setState(() => _note = 'Name a folder to open.');
    await editor.store.openAt(at);
    editor.resync();
    setState(() => _note = 'Opened the chronolog at $at.');
  }

  /// DELETE ALL: armed only by the typed word, and then it is gone. The gate is
  /// here and the deletion is the store's, so neither is half of the other.
  Future<void> _deleteAll(Editor editor) async {
    final root = editor.store.journal.dataRoot;
    await editor.store.deleteEverything();
    editor.resync();
    setState(() {
      _typed = '';
      _warnings = const [];
      _note = 'Everything at $root is deleted. This is a fresh, empty chronolog.';
    });
  }

  Future<void> _import(Editor editor, String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      return setState(() => _note = 'No file at $path.');
    }
    final result = importIcsText(editor, await file.readAsString());
    setState(() {
      _opened.clear();
      _warnings = result.warningClasses;
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

  /// A class as one line: how many events it covers, then what was wrong and
  /// what was done about it. The count is the whole point -- "47 events: start
  /// and end carry different time zones" reads in a screen where forty-seven
  /// notes do not.
  String _classLine(IcsWarningClass klass) =>
      '${klass.events.length} '
      '${klass.events.length == 1 ? 'event' : 'events'}: ${klass.says}';

  /// The host's dialog, answering into the elsewhere field rather than acting:
  /// New and Open are different acts on one location, so the dialog names the
  /// place and the person says which door.
  Future<void> _elsewhereFromDialog(Editor editor, String at) async {
    final picker = widget.picker;
    if (picker == null) {
      return setState(() => _note = 'No file dialog here — write the folder above.');
    }
    final picked = await picker.save(initialPath: at, suggestedName: snapshotFileName);
    if (picked.refusal.isNotEmpty) return setState(() => _note = picked.refusal);
    final path = picked.path;
    if (path == null) return;
    setState(() => _elsewhere = parentDirectory(path));
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
    final deleteWord = chrome.settings.text('document.deleteWord').trim();
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
        // THE THREE DOORS ON THE DOCUMENT ITSELF.
        cardRow(
          context,
          'Another chronolog',
          cardWrap(context, [
            CardField(
              value: _elsewhere,
              hint: 'a folder for another chronolog',
              onChanged: (text) => setState(() => _elsewhere = text),
              mono: true,
            ),
            namedAction(
              context,
              'New chronolog here',
              hint: 'A fresh, empty document at that folder. These files stay where they are.',
              onTap: _elsewhere.trim().isEmpty ? null : () => _new(editor, _elsewhere.trim()),
            ),
            namedAction(
              context,
              'Open the chronolog here',
              hint: 'Loads whatever document that folder holds. Two chronologs is a shape.',
              onTap: _elsewhere.trim().isEmpty ? null : () => _open(editor, _elsewhere.trim()),
            ),
            namedAction(
              context,
              'Choose a folder…',
              hint: 'The dialog this host provides, where it provides one',
              onTap: () => _elsewhereFromDialog(editor, saveAt),
            ),
          ]),
        ),
        cardRow(
          context,
          'Delete all data',
          cardWrap(context, [
            CardField(
              value: _typed,
              hint: 'type ${chrome.settings.text('document.deleteWord')}',
              onChanged: (text) => setState(() => _typed = text),
            ),
            namedAction(
              context,
              'Delete all data…',
              hint: 'The snapshot and the journal here, gone. There is no undo for this one.',
              onTap: deleteWord.isNotEmpty && _typed.trim().toLowerCase() == deleteWord.toLowerCase()
                  ? () => _deleteAll(editor)
                  : null,
            ),
          ]),
        ),
        cardNote(
          context,
          'Delete all data removes the chronolog written at'
          ' ${editor.store.journal.dataRoot} — the snapshot, the journal and'
          ' their sequence file — and leaves this app standing on an empty'
          ' document, as a fresh install would. Nothing else in that folder is'
          ' touched. Every other act in this program is undoable; this one is'
          ' not, so it does nothing at all until the word is typed.',
        ),
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
        // ONE LINE PER CLASS, WITH ITS COUNT, expandable to the events it
        // covers (ISSUES 9.2, the wall of errors). This rendered every warning
        // as its own note, uncapped, and the ICS sites fired PER EVENT naming
        // each by its opaque UID -- so an ordinary Outlook export said the same
        // three things hundreds of times about events nobody could identify. A
        // class is what was actually wrong; the events are which ones it
        // happened to, and they are named by TITLE and DAY, never by UID.
        //
        // EVERY WARNING STILL KNOWS ABOUT THE OTHERS (ISSUES 9.2): "an
        // impressive wall of errors" is one act to copy, and now the thing
        // copied is the summary rather than the wall.
        for (final klass in _warnings) ...[
          cardNote(
            context,
            _classLine(klass),
            refusal: true,
            source: 'this import',
            others: [
              for (final other in _warnings)
                if (other.says != klass.says) _classLine(other),
            ],
          ),
          namedAction(
            context,
            _opened.contains(klass.says)
                ? 'Fold these ${klass.events.length}'
                : 'Name these ${klass.events.length}',
            hint: 'Which events this class covers, by title and day',
            onTap: () => setState(
              () => _opened.contains(klass.says)
                  ? _opened.remove(klass.says)
                  : _opened.add(klass.says),
            ),
          ),
          if (_opened.contains(klass.says))
            cardNote(
              context,
              [for (final event in klass.events) '${event.title} (${event.when})'].join(', '),
            ),
        ],
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
