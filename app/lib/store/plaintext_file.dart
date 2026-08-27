// A named plaintext file the app reads, writes, and notices being edited.
//
// THE OBSIDIAN POSTURE, as a seam and nothing more. Editing the plaintext file
// is a valid authoring path and it hot-reloads -- and no user should ever need
// to, so the GUI path rides too. This utility is what makes the file half true
// for whatever the chrome wave names: settings, themes, layouts. It carries NO
// schema, because a schema here would be this file deciding what those are.
//
// Writes are ATOMIC for the same reason the snapshot's are: a reader -- the
// user's own editor, or a reload -- sees the whole old file or the whole new
// one.
//
// The watch POLLS rather than subscribing to filesystem events. Editors save by
// writing a temporary and renaming over the original, which platform watchers
// report as a delete on some hosts and a modify on others; a poll asks the only
// question that matters -- has the text changed -- and answers it the same way
// everywhere. Its interval runs on the injected clock, so a spec advances it
// instead of sleeping.

import 'dart:convert';

import 'seams.dart';

class PlaintextFile {
  PlaintextFile(
    this.path, {
    this.files = const IoStoreFiles(),
    this.scheduler = const WallScheduler(),
    this.interval = const Duration(seconds: 1),
  });

  final String path;
  final Duration interval;
  final StoreFiles files;
  final Scheduler scheduler;

  String? _known;
  StoreTimer? _timer;
  Future<void>? _polling;
  void Function(String text)? _onChange;

  /// The poll currently reading the file, or null. What a lifecycle hook waits
  /// on before it lets the app act on the file's contents.
  Future<void>? get polling => _polling;

  /// The file's text, or null when it does not exist. Malformed bytes decode
  /// with replacement rather than throwing: a half-saved file is a state to
  /// report, not a crash.
  Future<String?> read() async {
    final bytes = await files.read(path);
    _known = bytes == null ? null : utf8.decode(bytes, allowMalformed: true);
    return _known;
  }

  /// Write-new, flush, rename -- and remember the text as ours, so the store's
  /// own write never comes back as an external change.
  Future<void> write(String text) async {
    final temporary = '$path.tmp';
    await files.delete(temporary);
    await files.writeNew(temporary, utf8.encode(text));
    await files.rename(temporary, path);
    _known = text;
  }

  /// Call [onChange] whenever the file's text differs from what we last read or
  /// wrote. Idempotent: watching twice replaces the callback rather than
  /// stacking a second poll.
  void watch(void Function(String text) onChange) {
    _timer?.cancel();
    _onChange = onChange;
    _arm();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _onChange = null;
  }

  /// One poll. Public so a spec -- and a lifecycle-resume hook, which wants the
  /// check immediately rather than at the next tick -- can ask directly.
  Future<void> checkForChange() async {
    final bytes = await files.read(path);
    if (bytes == null) return;
    final text = utf8.decode(bytes, allowMalformed: true);
    if (text == _known) return;
    _known = text;
    _onChange?.call(text);
  }

  void _arm() => _timer = scheduler.run(interval, () {
    _timer = null;
    _polling = checkForChange().whenComplete(() {
      _polling = null;
      if (_onChange != null && _timer == null) _arm();
    });
    _polling!.ignore();
  });
}
