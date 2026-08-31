// The plaintext side of the surface: layout, views, settings and themes as
// files in the app's own directory, hot-reloaded when something else edits
// them, and written on a debounce -- never once per frame, which is the defect
// the old render loop shipped.
//
// A refusal (bad JSON, a bad expression) is reported and the last good state
// stays. A file the app cannot read never blanks the stage.

import 'dart:convert';

import '../lens/theme.dart';
import '../stage/tile.dart';
import '../store/data_dir.dart';
import '../store/plaintext_file.dart';
import '../store/seams.dart';
import 'settings.dart';
import 'view_state.dart';

const JsonEncoder _pretty = JsonEncoder.withIndent('  ');

class SessionFiles {
  SessionFiles(
    this.root, {
    this.files = const IoStoreFiles(),
    this.scheduler = const WallScheduler(),
    this.delay = const Duration(milliseconds: 350),
    this.onRefusal,
  });

  final String root;
  final StoreFiles files;
  final Scheduler scheduler;
  final Duration delay;
  final void Function(String message)? onRefusal;

  final Map<String, StoreTimer> _pending = {};
  final Map<String, (PlaintextFile, Map<String, Object?> Function())> _waiting = {};

  late final PlaintextFile layout = file('chronolog.layout');
  late final PlaintextFile views = file('chronolog.view');
  late final PlaintextFile settings = file('chronolog.settings');

  PlaintextFile theme(String name) => file('themes/$name.json');

  PlaintextFile file(String name) =>
      PlaintextFile(storePath(root, name), files: files, scheduler: scheduler);

  Future<void> ensure() => files.ensureDirectory(storePath(root, 'themes'));

  /// Every theme file on disk, by name. Through the store's own listing seam,
  /// so a surface that wants to know what themes exist never reaches for
  /// dart:io itself -- and a spec answers it in memory.
  Future<List<String>> themeNames() async => [
    for (final name in await files.namesIn(storePath(root, 'themes')))
      if (name.endsWith('.json')) name.substring(0, name.length - '.json'.length),
  ];

  /// Reads once and then watches: the file is a live authoring path.
  Future<void> bind(PlaintextFile file, void Function(Map<String, Object?>) onRead) async {
    final text = await file.read();
    _feed(file, text, onRead);
    file.watch((text) => _feed(file, text, onRead));
  }

  void _feed(PlaintextFile file, String? text, void Function(Map<String, Object?>) onRead) {
    if (text == null || text.trim().isEmpty) return;
    try {
      final parsed = jsonDecode(text);
      if (parsed is Map) {
        onRead(Map<String, Object?>.from(parsed));
      } else {
        onRefusal?.call('${file.path} is not a settings object.');
      }
    } on FormatException catch (refusal) {
      onRefusal?.call('${file.path}: ${refusal.message}');
    }
  }

  /// Coalesced: a burst of edits writes once, and a later request retargets
  /// the same timer rather than queueing a second write.
  void requestSave(PlaintextFile file, Map<String, Object?> Function() content) {
    _pending.remove(file.path)?.cancel();
    _waiting[file.path] = (file, content);
    _pending[file.path] = scheduler.run(delay, () {
      _pending.remove(file.path);
      _waiting.remove(file.path);
      saveNow(file, content());
    });
  }

  /// Write everything a debounce is still holding, NOW. What a lifecycle detach
  /// asks for: a coalesced write still waiting on its timer is an edit the
  /// process has been told about and the disk has not.
  Future<void> flush() async {
    final waiting = [..._waiting.values];
    _waiting.clear();
    for (final timer in _pending.values) {
      timer.cancel();
    }
    _pending.clear();
    for (final (file, content) in waiting) {
      await saveNow(file, content());
    }
  }

  Future<void> saveNow(PlaintextFile file, Map<String, Object?> content) async {
    try {
      await file.write(_pretty.convert(content));
    } on Object catch (refusal) {
      onRefusal?.call('${file.path}: $refusal');
    }
  }

  /// A named theme file, or the shipped preset of that name. A theme is
  /// authored by hand, so a file that will not read reports and falls back
  /// rather than leaving the surface with no palette at all.
  Future<ChronoTheme?> loadTheme(String name) async {
    final text = await theme(name).read();
    if (text == null || text.trim().isEmpty) return shipped[name];
    try {
      final parsed = jsonDecode(text);
      if (parsed is Map) return ChronoTheme.fromJson(Map<String, Object?>.from(parsed));
      onRefusal?.call('themes/$name.json is not a theme object.');
    } on FormatException catch (refusal) {
      onRefusal?.call('themes/$name.json: ${refusal.message}');
    }
    return shipped[name];
  }

  Future<void> saveTheme(ChronoTheme palette) => saveNow(theme(palette.name), palette.toJson());

  void dispose() {
    for (final timer in _pending.values) {
      timer.cancel();
    }
    _pending.clear();
    for (final file in [layout, views, settings]) {
      file.stop();
    }
  }
}

/// The SETTINGS file, read and watched, ahead of everything else.
///
/// Its own call because one of the settings says WHERE THE DOCUMENT LIVES: the
/// save location is authored (Don, 8.31), so the file that carries it has to be
/// read before the store is pointed anywhere. Reading it twice would be a
/// second road to the same state, so `bindSession` does not read it again.
Future<void> bindSettings(SessionFiles files, Settings settings) async {
  await files.ensure();
  await files.bind(files.settings, settings.applyJson);
}

/// Reads the three files, then writes them back on a debounce whenever what
/// they hold changes. Both directions, so editing the file by hand and using
/// the GUI are the same authoring path.
Future<void> bindSession(SessionFiles files, Settings settings, ViewBook views, Stage stage) async {
  await bindSettings(files, settings);
  await files.bind(files.views, views.applyJson);
  await files.bind(files.layout, stage.applyJson);
  settings.addListener(() => files.requestSave(files.settings, settings.toJson));
  views.addListener(() => files.requestSave(files.views, views.toJson));
  stage.addListener(() => files.requestSave(files.layout, stage.toJson));
}
