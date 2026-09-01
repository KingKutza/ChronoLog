// The program, assembled: where the data is, what the document is, what the
// surface is looking at, and the one place all of it is wired together.
//
// EVERY SEAM IS INJECTED. `open` takes the filesystem, the clock and the data
// root, so the whole workspace -- store, editor, settings, session files, stage,
// chrome, cards -- can be stood up in memory by a spec and is the same object
// the running program uses. There is no second, simpler assembly for tests.
//
// FIRST-RUN HONESTY. An empty data root establishes an EMPTY document: the two
// structural frames a workspace cannot function without, and nothing else. No
// seeded calendar, no seeded group, no phantom event. A view tile on it draws a
// real, empty Gregorian surface, and a law with no clock mapping draws no Now.
//
// A CARD IS AN EDIT SESSION, not furniture. The layout file may name one from a
// previous run; it does not survive the process, so the leaf is dropped rather
// than left as a hole in the stage.

import 'package:flutter/material.dart';

import 'cards/card_factory.dart';
import 'cards/frame_card.dart';
import 'chrome/controls.dart';
import 'chrome/shell.dart';
import 'core/document.dart';
import 'core/records.dart';
import 'edit/editor.dart';
import 'host/file_picker.dart';
import 'lens/minimap/minimap_tile.dart';
import 'lens/painters/lines.dart';
import 'lens/painters/month_grid.dart';
import 'lens/theme.dart';
import 'lens/todo/row.dart';
import 'lens/view_tile.dart';
import 'session/files.dart';
import 'session/settings.dart';
import 'session/view_state.dart';
import 'stage/layout_tree.dart';
import 'stage/tile.dart';
import 'store/data_dir.dart';
import 'store/document_store.dart';
import 'store/journal.dart';
import 'store/seams.dart';

/// Every shipped lens into the ONE painter and widget registries the view tile
/// reads. The catalog says what a lens IS; this says what puts it on a canvas.
void registerShippedLenses() {
  registerGridLenses();
  registerCurveLenses();
  registerTodoLenses();
}

/// What a fresh view tile looks through: the document's own calendars, or --
/// on a first run, where the user has authored none -- the shipped wall-time
/// frame, which is a real frame and not a phantom. Nothing is invented; an
/// empty document simply projects an empty calendar.
List<String> defaultFramesOf(Document document) {
  final calendars = [
    for (final frame in document.frames.values)
      if (frame.traits.contains('calendar')) frame.id,
  ];
  if (calendars.isNotEmpty) return calendars;
  return [
    for (final frame in document.frames.values)
      if (frame.traits.contains('temporal')) frame.id,
  ];
}

/// The running program, as one value.
class Workspace {
  Workspace._({
    required this.root,
    required this.settings,
    required this.files,
    required this.store,
    required this.editor,
    required this.views,
    required this.stage,
    required this.factory,
    required this.chrome,
    required this.theme,
    required this.load,
  });

  final String root;
  final Settings settings;
  final SessionFiles files;
  final DocumentStore store;
  final Editor editor;
  final ViewBook views;
  final Stage stage;
  final CardFactory factory;
  final Chrome chrome;

  /// The palette in force. Apply swaps it live; `theme.name` in the settings
  /// file is the persistent choice.
  final ValueNotifier<ChronoTheme> theme;

  /// What the journal reported on the way in -- repairs, refusals, a torn tail.
  /// Surfaced, never swallowed.
  final JournalLoad load;

  /// A move in flight. A relocation writes settings-adjacent state, and a
  /// second listener callback arriving mid-write would ask for the same move
  /// twice.
  bool _moving = false;

  /// Boot. Every seam is a parameter, so a spec runs this exact assembly with a
  /// disk that is a map and a clock it moves.
  static Future<Workspace> open({
    String? dataRoot,
    StoreFiles files = const IoStoreFiles(),
    Scheduler scheduler = const WallScheduler(),
    FilePicker? picker,
  }) async {
    registerShippedLenses();
    final root = resolveDataRoot(explicit: dataRoot);
    final settings = chronologSettings();
    final session = SessionFiles(
      root,
      files: files,
      scheduler: scheduler,
      onRefusal: settings.refusals.add,
    );
    // THE SETTINGS FILE IS READ FIRST, because one of its lines says where the
    // document is saved. A store pointed at the app directory and moved
    // afterwards would write a snapshot nobody asked for.
    await bindSettings(session, settings);
    final store = DocumentStore(
      dataRoot: authoredPath(settings.text('document.saveAt'), root),
      files: files,
      scheduler: scheduler,
      // THE EMPTY DOCUMENT, from the core's own factory: nothing here invents a
      // record the owner did not author.
      establish: createEmptyWorkspaceDocument,
    );
    final load = await store.load();
    final editor = Editor(store, settings: settings.tunable);
    final views = ViewBook()..defaultFrames = defaultFramesOf(editor.document);
    // WHERE A NEW TILE LANDS IS AUTHORED (ISSUES 9.1): the layout FILE carries
    // the rule list -- `bindSession` below reads it and hot-loads it when it
    // changes on disk -- and the `stage.placement` setting is a read/write view
    // of that section, so it can be edited from either road.
    final stage = Stage(tunable: settings.tunable, settings: settings, onLens: views.setLens);
    final theme = ValueNotifier(shipped['paper']!);

    final factory = CardFactory(
      editor,
      settings,
      stage,
      bodies: frameCardBodies,
      files: session,
      dataRoot: root,
      picker: picker ?? FilePicker.forPlatform(),
      onTheme: (palette) => theme.value = palette,
    );
    final surface = (
      editor: editor,
      settings: settings,
      views: views,
      stage: stage,
      objectCard: factory.objectCard,
      frameCard: factory.frameCard,
      settingsCard: factory.settingsCard,
    );
    final chrome = Chrome(
      settings: settings,
      stage: stage,
      views: views,
      editor: editor,
      cards: {
        'document': factory.documentCard,
        'frames': factory.framesBrowser,
        // EVERY LIST OF THINGS OFFERS TO MAKE THE THING (ISSUES 9.1): the one
        // create door, reachable from the frames drop and the document menu
        // alike rather than minted a second time in either.
        'newFrame': factory.newFrameCard,
        'settings': factory.settingsCard,
        'themes': factory.themesCard,
      },
      viewTile: (id) => viewTileSpec(id, surface),
      openFrame: (id) => stage.open(factory.frameCard(id)),
      // THE SETTINGS DOOR ON EVERY SURFACE (ISSUES 9.1). The family answers per
      // area: a surface's own menu opens the card that governs it, and an area
      // no card governs opens the main card and says so.
      openSettings: (area) => stage.open(factory.settingsCard(area: area)),
      // ONE dispatch: a declared action, a keyboard chord and a menu row all
      // land on the focused view tile's own verb.
      onAction: (tile, action) => viewTileControllers[tile]?.runAction(action),
    );
    // EVERY CONTENT REGISTERS (the one ancestor, ruled 2026-09-01): the
    // connectivity law reads this registry, so registration is part of boot,
    // not a test convenience.
    registerShippedContents(factory: factory, surface: surface);
    installDefaultStage(chrome, minimap: (id) => minimapTileSpec(id, surface));
    await bindSession(session, settings, views, stage);
    rehost(stage, surface);
    // THE PLAINTEXT PATH EXISTS FROM THE FIRST RUN. A file nobody has written
    // yet is not an authoring path: editing the layout by hand and rearranging
    // the stage are meant to be the same road, so the road is laid at boot and
    // the debounce keeps it current from then on.
    session.requestSave(session.layout, stage.toJson);
    session.requestSave(session.views, views.toJson);
    session.requestSave(session.settings, settings.toJson);

    final workspace = Workspace._(
      root: root,
      settings: settings,
      files: session,
      store: store,
      editor: editor,
      views: views,
      stage: stage,
      factory: factory,
      chrome: chrome,
      theme: theme,
      load: load,
    );
    await _layTheThemes(session);
    await workspace._dressIn(settings.text('theme.name'));
    settings.addListener(workspace._settingsChanged);
    editor.changes.addListener(workspace._framesChanged);
    return workspace;
  }

  /// A tile the layout file named that nothing has opened: a view or a minimap
  /// is re-hosted, and anything else -- a card, which is an edit session --
  /// is dropped rather than left as a hole.
  static void rehost(Stage stage, Surface surface) {
    for (final leaf in stage.leaves) {
      if (stage.tiles.containsKey(leaf.id)) continue;
      final spec = switch (leaf.type) {
        'view' => viewTileSpec(leaf.id, surface),
        'minimap' => minimapTileSpec(leaf.id, surface),
        _ => null,
      };
      if (spec == null) continue;
      stage.tiles[leaf.id] = spec;
      stage.openOrder.add(leaf.id);
    }
    for (final leaf in stage.leaves.toList()) {
      if (!stage.tiles.containsKey(leaf.id)) stage.root = removeNode(stage.root, leaf.id);
    }
    if (findNode(stage.root, stage.focusedId ?? '') == null) {
      stage.focusedId = stage.focusedViewTile ?? edgeLeaf(stage.root, false)?.id;
    }
  }

  /// THE SHIPPED PALETTES ARE FILES FROM THE FIRST RUN. A theme the program
  /// knows and the disk does not is not an authoring path: `themes/` shipped
  /// empty, so a person who wanted to move one colour had nothing to open.
  /// Written only where the name is absent, so an edited `paper.json` is never
  /// overwritten by the default it was edited away from.
  static Future<void> _layTheThemes(SessionFiles files) async {
    await files.ensure();
    final present = (await files.themeNames()).toSet();
    for (final palette in shipped.values) {
      if (!present.contains(palette.name)) await files.saveTheme(palette);
    }
  }

  Future<void> _dressIn(String name) async {
    final palette = await files.loadTheme(name.isEmpty ? 'paper' : name);
    if (palette != null) theme.value = palette;
  }

  /// ONE listener for the settings that are not arithmetic: the palette to wear
  /// and the directory to save into. Both are authored text, both take effect
  /// whether the words were typed in a card or into `chronolog.settings`.
  void _settingsChanged() {
    final named = settings.text('theme.name');
    if (named.isNotEmpty && named != theme.value.name) _dressIn(named);
    _moveDocument();
  }

  /// Where the document is saved is the user's to choose (Don, 8.31). Editing
  /// the setting IS the move; the store's own journal machinery does the
  /// writing, and a refusal -- a directory another chronolog already occupies --
  /// is reported in the same place every settings refusal is read.
  Future<void> _moveDocument() async {
    if (_moving) return;
    final wanted = authoredPath(settings.text('document.saveAt'), root);
    if (wanted == store.journal.dataRoot) return;
    _moving = true;
    try {
      final refused = await store.relocate(wanted);
      if (refused != null) settings.refusals.add('document.saveAt: $refused');
    } finally {
      _moving = false;
    }
  }

  void _framesChanged() => views.defaultFrames = defaultFramesOf(editor.document);

  /// Everything the process has been told and the disk has not. What a
  /// lifecycle detach does -- a dirty-guard question a person had to answer is
  /// something a process can simply do.
  Future<void> flush() async {
    // Every open draft settles first: a hold that outlives the session it was
    // taken in would leave autosave off with nobody left to release it.
    editor.closeDrafts();
    await files.flush();
    await store.close();
  }

  void dispose() {
    settings.removeListener(_settingsChanged);
    editor.changes.removeListener(_framesChanged);
    files.dispose();
    theme.dispose();
  }
}

/// The app. Boots once, holds the workspace, and flushes when the host takes
/// the process away.
class ChronoLogApp extends StatefulWidget {
  const ChronoLogApp({super.key, this.dataRoot});

  final String? dataRoot;

  @override
  State<ChronoLogApp> createState() => _ChronoLogAppState();
}

class _ChronoLogAppState extends State<ChronoLogApp> with WidgetsBindingObserver {
  late final Future<Workspace> _booting = Workspace.open(dataRoot: widget.dataRoot);
  Workspace? _workspace;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _booting.then((workspace) {
      if (mounted) return setState(() => _workspace = workspace);
      workspace.dispose();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _workspace?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _workspace?.flush();
    }
  }

  @override
  Widget build(BuildContext context) {
    final workspace = _workspace;
    return MaterialApp(
      title: 'ChronoLog',
      debugShowCheckedModeBanner: false,
      theme: themeDataFor(shipped['paper']!),
      darkTheme: themeDataFor(shipped['night']!),
      home: workspace == null
          ? ColoredBox(color: shipped['paper']!.ground, child: const SizedBox.expand())
          : ValueListenableBuilder<ChronoTheme>(
              valueListenable: workspace.theme,
              builder: (context, palette, _) =>
                  ChronoSurface(chrome: workspace.chrome, theme: palette, cards: workspace.factory),
            ),
    );
  }
}
