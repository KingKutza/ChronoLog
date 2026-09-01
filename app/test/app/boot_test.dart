// THE WHOLE PROGRAM, BOOTED. Not a stand-in for it: `Workspace.open` is the
// same assembly `main` runs, with the filesystem and the clock handed in, so
// what these cases exercise is what ships.
//
// NO REAL I/O INSIDE `testWidgets`. A widget test runs in a fake-async zone; a
// real `DocumentStore.load()` awaited there deadlocks on a future the zone will
// never run. The disk is a map and the clock is one the case moves.
//
// The rulings under test are the ones the dock died for: everything is a tile of
// ONE class, nothing floats, nothing overlaps, no flow raises a dialog, and the
// bars describe the FOCUSED VIEW TILE.

import 'dart:convert';

import 'package:chronolog/app.dart';
import 'package:chronolog/chrome/context_bar.dart';
import 'package:chronolog/chrome/document_bar.dart';
import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/chrome/view_bar.dart';
import 'package:chronolog/core/object_kinds.dart';
import 'package:chronolog/edit/editor.dart';
import 'package:chronolog/host/file_picker.dart';
import 'package:chronolog/lens/theme.dart';
import 'package:chronolog/lens/view_tile.dart';
import 'package:chronolog/session/lens_catalog.dart';
import 'package:chronolog/stage/layout_tree.dart';
import 'package:chronolog/stage/tile.dart';
import 'package:chronolog/store/data_dir.dart';
import 'package:chronolog/store/document_store.dart';
import 'package:chronolog/store/journal.dart';
import 'package:chronolog/stage/stage_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../store/harness.dart';

const Size _surface = Size(1600, 1000);
const String _root = 'C:memory';

/// The program on a data root that holds nothing: the first run.
Future<Workspace> emptyWorkspace(WidgetTester tester) async {
  tester.view.physicalSize = _surface;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final workspace = await Workspace.open(
    dataRoot: _root,
    files: MemoryFiles(),
    scheduler: ManualScheduler(),
    picker: const RefusedFilePicker('no dialog in a spec'),
  );
  addTearDown(workspace.dispose);
  return workspace;
}

Future<void> pumpWorkspace(WidgetTester tester, Workspace workspace) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ChronoSurface(
        chrome: workspace.chrome,
        theme: workspace.theme.value,
        cards: workspace.factory,
      ),
    ),
  );
  await tester.pump();
}

/// Where a tile actually landed. Bars and the minimap answer the same way a
/// lens does, which is the point: they are the same class of thing.
Rect rectOf(WidgetTester tester, String id) => tester.getRect(find.byKey(ValueKey(id)));

void main() {
  testWidgets('a first run lays the shipped palettes down as files a person can edit', (
    tester,
  ) async {
    tester.view.physicalSize = _surface;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final disk = MemoryFiles();
    final workspace = await Workspace.open(
      dataRoot: _root,
      files: disk,
      scheduler: ManualScheduler(),
      picker: const RefusedFilePicker('no dialog in a spec'),
    );
    addTearDown(workspace.dispose);
    for (final palette in shipped.values) {
      final text = disk.find('${palette.name}.json');
      expect(text, isNotNull, reason: '${palette.name} shipped but was never written');
      final read = ChronoTheme.fromJson(Map<String, Object?>.from(jsonDecode(text!) as Map));
      for (final field in themeFields) {
        expect(hexOf(read.palette[field]!), hexOf(palette.palette[field]!), reason: field);
      }
    }
    // An edited theme is the user's. Booting again must not put the shipped
    // one back over it.
    final written = disk.contents.keys.firstWhere((key) => key.endsWith('paper.json'));
    disk.write(written, '{"name":"paper","ground":"#123456"}');
    final second = await Workspace.open(
      dataRoot: _root,
      files: disk,
      scheduler: ManualScheduler(),
      picker: const RefusedFilePicker('no dialog in a spec'),
    );
    addTearDown(second.dispose);
    expect(disk.find('paper.json'), contains('123456'));
  });

  testWidgets('a first run establishes an empty document and seeds no frames of its own', (
    tester,
  ) async {
    final workspace = await emptyWorkspace(tester);
    await pumpWorkspace(tester, workspace);
    final document = workspace.editor.document;
    expect(document.events, isEmpty, reason: 'nothing is seeded that the user did not author');
    expect(document.patterns, isEmpty);
    expect(document.relations, isEmpty);
    // The two structural frames a workspace cannot function without, and no
    // seeded calendar: a phantom frame would be a claim nobody made.
    expect(
      document.frames.values.where((frame) => frame.traits.contains('calendar')),
      isEmpty,
      reason: 'no phantom calendar',
    );
    expect(document.frames, isNotEmpty, reason: 'wall time and the measure frame are structure');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the shipped preset is bars pinned to their edges, lens beside a narrow minimap', (
    tester,
  ) async {
    final workspace = await emptyWorkspace(tester);
    await pumpWorkspace(tester, workspace);
    final height = workspace.chrome.px('chrome.barHeight');
    // A BAR IS A TILE: its content thickness is what it arrives at and the
    // least it takes, and the stage divides what is left (ruled 2026-08-28).
    // It spends nothing on chrome of its own: the grip at its leading end is
    // retired with the window bar (ISSUES 9.1), so a bar is its tile's whole
    // width less its own hairline.
    final full = _surface.width - tileChrome(workspace.chrome);
    for (final bar in [DocumentBar, ViewBar, ContextBar]) {
      expect(tester.getSize(find.byType(bar)).width, closeTo(full, 2), reason: '$bar');
      expect(tester.getSize(find.byType(bar)).height, closeTo(height, 1), reason: '$bar');
    }
    final minimap = rectOf(tester, 'minimap:main');
    final view = rectOf(tester, 'view:1');
    final share = workspace.chrome.px('stage.minimapWidth');
    expect(minimap.left, greaterThan(view.right - 1), reason: 'the minimap is right of the lens');
    expect(minimap.width / (minimap.width + view.width), closeTo(share, 0.02));
    expect(view.height, greaterThan(height * 2), reason: 'the stage row dominates the column');
    expect(rectOf(tester, 'bar:context').top, greaterThan(view.bottom - 1));
  });

  testWidgets('every tile is the same tree class: none floats, none overlaps', (tester) async {
    final workspace = await emptyWorkspace(tester);
    await pumpWorkspace(tester, workspace);
    final leaves = leavesOf(workspace.stage.root);
    expect(
      leaves.map((leaf) => leaf.type).toSet().length,
      greaterThan(1),
      reason: 'the preset holds more than one kind of tile, or this proves nothing',
    );
    final stage = tester.getRect(find.byType(ChronoSurface));
    final rects = [for (final leaf in leaves) rectOf(tester, leaf.id)];
    for (final rect in rects) {
      expect(stage.contains(rect.topLeft), isTrue, reason: 'a tile left the stage');
      expect(stage.contains(rect.bottomRight - const Offset(1, 1)), isTrue);
    }
    for (var i = 0; i < rects.length; i += 1) {
      for (var j = i + 1; j < rects.length; j += 1) {
        expect(rects[i].intersect(rects[j]).isEmpty, isTrue, reason: 'tiles overlap');
      }
    }
  });

  testWidgets('every shipped lens is registered, as a painter or as a widget', (tester) async {
    await emptyWorkspace(tester);
    for (final id in lensCatalog.keys) {
      final registered = lensPainters.containsKey(id) || lensWidgets.containsKey(id);
      expect(registered, isTrue, reason: '$id has nothing to draw it');
    }
    for (final id in lensPainters.keys) {
      expect(
        lensCatalog[id]?.isTimeSurface,
        isTrue,
        reason: '$id paints but is not a time surface',
      );
    }
    for (final id in lensWidgets.keys) {
      expect(lensCatalog[id], isNotNull, reason: '$id is registered and not in the catalog');
    }
  });

  testWidgets('the bars follow the focused view tile', (tester) async {
    final workspace = await emptyWorkspace(tester);
    await pumpWorkspace(tester, workspace);
    final second = openViewTile(workspace.chrome, lensId: 'tactical');
    await tester.pump();
    expect(workspace.stage.focusedViewTile, second);
    expect(find.text('Rows'), findsOneWidget, reason: 'the context bar reads the focused lens');
    workspace.stage.focus('view:1');
    await tester.pump();
    expect(workspace.stage.focusedViewTile, 'view:1');
    expect(find.text('Rows'), findsNothing);
    expect(find.text('Days behind'), findsNothing, reason: 'Intimate folds its own detail');
    // The view bar swaps THAT tile's lens and opens nothing; the context bar
    // follows it there and leaves the other tile alone.
    workspace.stage.swapLens('view:1', 'list');
    await tester.pump();
    expect(workspace.views.of('view:1').lensId, 'list');
    expect(workspace.views.of(second).lensId, 'tactical');
    expect(find.text('Group by'), findsOneWidget, reason: 'the focused tile is now a roster');
    workspace.stage.focus(second);
    await tester.pump();
    expect(find.text('Group by'), findsNothing, reason: 'the other tile is still Tactical');
    expect(find.text('Rows'), findsOneWidget);
  });

  testWidgets('no flow raises a dialog: closing, deleting and discarding all just happen', (
    tester,
  ) async {
    final workspace = await emptyWorkspace(tester);
    await pumpWorkspace(tester, workspace);
    void nothingAsked() {
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
    }

    workspace.stage.open(workspace.factory.documentCard());
    await tester.pump();
    nothingAsked();
    // A create, a card over it, a discard, a delete: every one of them is
    // undoable, so none of them has anything to ask.
    workspace.stage.open(workspace.factory.newObjectCard('event'));
    await tester.pump();
    nothingAsked();
    // E1: the new card HOLDS its record until a value lands, so opening one
    // mints nothing. Stating a state is a value, and it mints.
    expect(workspace.editor.document.events, isEmpty);
    final minted = workspace.editor.pending.keys.toList();
    expect(minted, hasLength(1), reason: 'the new card is holding one record');
    workspace.editor.toggleState(minted.first, doneStateFrameId);
    await tester.pump();
    expect(workspace.editor.document.events.keys, contains(minted.first));
    workspace.editor.drafts[minted.first]?.discard();
    await tester.pump();
    nothingAsked();
    expect(workspace.editor.document.events, isEmpty);
    expect(workspace.editor.undo(), isTrue, reason: 'the discard is its own undo entry');
    await tester.pump();
    workspace.editor.deleteObject(minted.first);
    await tester.pump();
    nothingAsked();
    expect(workspace.editor.document.events, isEmpty);
    for (final id in workspace.stage.tiles.keys.toList()) {
      workspace.stage.close(id);
      await tester.pump();
      nothingAsked();
    }
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('every card class the factory can open has a registered body', (tester) async {
    final workspace = await emptyWorkspace(tester);
    await pumpWorkspace(tester, workspace);
    final opened = <String>[];
    for (final make in <TileSpec Function()>[
      () => workspace.factory.objectCard('event:none'),
      () => workspace.factory.newObjectCard('todo'),
      () => workspace.factory.frameCard('frame:wall-time'),
      workspace.factory.newFrameCard,
      workspace.factory.framesBrowser,
      workspace.factory.documentCard,
      workspace.factory.settingsCard,
      workspace.factory.themesCard,
    ]) {
      final spec = make();
      opened.add(spec.klass);
      expect(
        workspace.factory.bodies.containsKey(spec.klass),
        isTrue,
        reason: '${spec.klass} would render a stated gap',
      );
      workspace.stage.open(spec);
      await tester.pump();
      expect(find.textContaining('has no registered body'), findsNothing, reason: spec.klass);
      workspace.stage.close(spec.id);
      await tester.pump();
    }
    expect(opened.toSet(), workspace.factory.bodies.keys.toSet());
  });

  testWidgets('a card is an edit session: a layout naming one does not resurrect it', (
    tester,
  ) async {
    final workspace = await emptyWorkspace(tester);
    workspace.stage.open(workspace.factory.documentCard());
    final card = workspace.stage.tiles.keys.firstWhere((id) => id.startsWith('card:'));
    // What a restart looks like: the tree remembers the leaf, nothing has built
    // the tile.
    workspace.stage.tiles.remove(card);
    Workspace.rehost(workspace.stage, (
      editor: workspace.editor,
      settings: workspace.settings,
      views: workspace.views,
      stage: workspace.stage,
      objectCard: workspace.factory.objectCard,
      frameCard: workspace.factory.frameCard,
      settingsCard: workspace.factory.settingsCard,
    ));
    await pumpWorkspace(tester, workspace);
    expect(findNode(workspace.stage.root, card), isNull);
    expect(find.textContaining('No tile named'), findsNothing);
  });

  // --- THE SAVE LOCATION IS AUTHORED (ISSUES 8.31, "Save location") ---------
  //
  // Don: "I don't appear to be able to set a save location." It is a setting, so
  // it is read from `chronolog.settings` before the store is pointed anywhere,
  // and writing it later MOVES the document. The card and the file are one road.

  test('a save location written in the settings file is where the document is established', () async {
    final root = resolveDataRoot(explicit: _root);
    const elsewhere = 'D:elsewhere';
    final files = MemoryFiles()
      ..write(
        storePath(root, 'chronolog.settings'),
        jsonEncode({'document.saveAt': elsewhere}),
      );
    final workspace = await Workspace.open(
      dataRoot: _root,
      files: files,
      scheduler: ManualScheduler(),
      picker: const RefusedFilePicker('no dialog in a spec'),
    );
    addTearDown(workspace.dispose);
    expect(workspace.store.journal.dataRoot, elsewhere);
    expect(
      files.written.keys.where((path) => path.startsWith(elsewhere)),
      isNotEmpty,
      reason: 'the document was established at the chosen place, not beside the app',
    );
    expect(
      files.written.keys.any((path) => path == storePath(root, snapshotFileName)),
      isFalse,
      reason: 'no phantom document beside the app the author did not ask for',
    );
  });

  test('writing the setting afterwards moves the document, and keeps saving there', () async {
    final root = resolveDataRoot(explicit: _root);
    final files = MemoryFiles();
    final workspace = await Workspace.open(
      dataRoot: _root,
      files: files,
      scheduler: ManualScheduler(),
      picker: const RefusedFilePicker('no dialog in a spec'),
    );
    addTearDown(workspace.dispose);
    expect(workspace.store.journal.dataRoot, root, reason: 'beside the app by default');
    workspace.editor.commit(
      'Rename document',
      workspace.editor.document.copyWith(
        meta: {...workspace.editor.document.meta, 'title': 'Moved'},
      ),
    );

    const chosen = 'D:chosen';
    workspace.settings.setText('document.saveAt', chosen);
    // The move is asynchronous the way every write here is; nothing sleeps.
    for (var turn = 0; turn < 8; turn += 1) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(workspace.store.journal.dataRoot, chosen);
    final moved = await JournalStore(dataRoot: chosen, files: files).load();
    expect(moved.document.meta['title'], 'Moved', reason: 'the document travelled whole');
  });

  test('a save location another chronolog occupies is refused in words, not overwritten', () async {
    final files = MemoryFiles();
    const occupied = 'D:occupied';
    // Somebody else's document, sitting where this one is about to be sent.
    final sitting = DocumentStore(
      dataRoot: occupied,
      files: files,
      scheduler: ManualScheduler(),
    );
    await sitting.load();
    sitting.commit('Theirs', sitting.document.put('meta', 'title', 'Theirs'));
    await sitting.save(force: true);

    final workspace = await Workspace.open(
      dataRoot: _root,
      files: files,
      scheduler: ManualScheduler(),
      picker: const RefusedFilePicker('no dialog in a spec'),
    );
    addTearDown(workspace.dispose);
    workspace.settings.setText('document.saveAt', occupied);
    for (var turn = 0; turn < 8; turn += 1) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(
      workspace.store.journal.dataRoot,
      resolveDataRoot(explicit: _root),
      reason: 'a refused move moved nothing',
    );
    expect(
      workspace.settings.refusals.where((line) => line.startsWith('document.saveAt')),
      isNotEmpty,
      reason: 'the words are reported where every settings refusal is read',
    );
    expect(
      (await JournalStore(dataRoot: occupied, files: files).load()).document.meta['title'],
      'Theirs',
      reason: 'the document already there is untouched',
    );
  });
}
