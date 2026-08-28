// The Windows picker's marshalling, WITHOUT OPENING A DIALOG.
//
// The seam is the point: `HostDialogs` is the whole surface the picker touches,
// so a fake one allocates real memory, receives the exact struct the real call
// would receive, and answers the way the dialog answers. Nothing here shows a
// window, and nothing here needs the dialog to exist.

import 'dart:ffi';
import 'dart:io';

import 'package:chronolog/host/file_picker.dart';
import 'package:test/test.dart';

/// The host, faked: real heap blocks so the struct writes are real writes, and
/// a dialog that reports what it was handed instead of showing itself.
class FakeHost {
  FakeHost({this.answer, this.accepts = true});

  /// What the "dialog" writes back into the caller's own buffer.
  final String? answer;

  /// Whether the person picked something. False is an ordinary cancel.
  final bool accepts;

  final List<int> allocated = [], released = [];
  int size = 0, flags = 0, maxFile = 0;
  String filter = '', title = '', suggested = '';

  Pointer<Void> _allocate(int bytes) {
    final block = _heap.allocate(bytes);
    allocated.add(block.address);
    return block;
  }

  void _release(Pointer<Void> block) => released.add(block.address);

  int _run(Pointer<OpenFileNameW> struct) {
    size = struct.ref.structSize;
    flags = struct.ref.flags;
    maxFile = struct.ref.maxFile;
    filter = _read(struct.ref.filter);
    title = _read(struct.ref.title);
    suggested = _read(struct.ref.file);
    if (!accepts) return 0;
    writeUnits(struct.ref.file, answer ?? '');
    return 1;
  }

  HostDialogs get dialogs => (open: _run, save: _run, allocate: _allocate, release: _release);

  static String _read(Pointer<Uint16> at) => at == nullptr ? '' : readUnits(at) ?? '';

  static final _NativeHeap _heap = _NativeHeap();
}

/// A heap borrowed from the host itself, since nothing in this program adds a
/// package to get one. On a platform with no such call the cases below skip.
class _NativeHeap {
  _NativeHeap() {
    final kernel = DynamicLibrary.open('kernel32.dll');
    final process = kernel.lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
      'GetProcessHeap',
    );
    _heap = process();
    _alloc = kernel
        .lookupFunction<
          Pointer<Void> Function(Pointer<Void>, Uint32, IntPtr),
          Pointer<Void> Function(Pointer<Void>, int, int)
        >('HeapAlloc');
  }

  late final Pointer<Void> _heap;
  late final Pointer<Void> Function(Pointer<Void>, int, int) _alloc;

  Pointer<Void> allocate(int bytes) => _alloc(_heap, 8, bytes);
}

void main() {
  test('the filter is pair-wise and double-NUL terminated, with an all-files pair last', () {
    final filter = windowsFilter(const ['ics']);
    expect(filter.split('\u0000').take(4).toList(), ['ICS files', '*.ics', 'All files', '*.*']);
    expect(filter.endsWith('\u0000\u0000'), isTrue, reason: 'the list ends on a double NUL');
    expect(windowsFilter(const []).split('\u0000').take(2).toList(), ['All files', '*.*']);
    expect(windowsFilter(const ['.ics']), windowsFilter(const ['ics']), reason: 'a dot is noise');
  });

  test('the struct reports a pointer-aligned size, which is what the dialog validates first', () {
    expect(sizeOf<OpenFileNameW>() % sizeOf<Pointer<Void>>(), 0);
    expect(
      sizeOf<OpenFileNameW>(),
      greaterThanOrEqualTo(sizeOf<Pointer<Void>>() * 12),
      reason: 'twelve pointer members plus the scalars',
    );
  });

  test('a refused platform says so and never answers as though the person cancelled', () async {
    const picker = RefusedFilePicker('no picker here');
    for (final answer in [await picker.open(), await picker.save()]) {
      expect(answer.path, isNull);
      expect(answer.refusal, 'no picker here');
    }
    // The ordinary cancel is the OTHER shape, and the two must never be
    // confused: a cancel is not a failure and carries no words.
    expect(cancelled.refusal, isEmpty);
    expect(cancelled.path, isNull);
  });

  test('a library that will not load is a stated refusal, not a crash', () async {
    final picker = WindowsFilePicker(dialogs: () => throw ArgumentError('no comdlg32 here'));
    final answer = await picker.open();
    expect(answer.path, isNull);
    expect(answer.refusal, contains('No Windows file dialog'));
  });

  group('the struct the dialog is handed', () {
    test('carries its own size, the buffer length, the filter and the title', () async {
      final host = FakeHost(answer: r'C:\work\calendar.ics');
      final picked = await WindowsFilePicker(dialogs: () => host.dialogs)
          .open(initialPath: r'C:\work', extensions: const ['ics']);
      expect(host.size, sizeOf<OpenFileNameW>(), reason: 'lStructSize is the struct itself');
      expect(host.maxFile, maxPathUnits);
      expect(host.filter.split('\u0000').first, 'ICS files');
      expect(host.title, 'Open');
      expect(picked.path, r'C:\work\calendar.ics', reason: 'read back out of our own buffer');
      expect(picked.refusal, isEmpty);
      expect(host.released.toSet(), containsAll(host.allocated.toSet()));
    });

    test('a save never sets the overwrite prompt: no confirmation dialogs, anywhere', () async {
      final host = FakeHost(answer: r'C:\work\out.ics');
      await WindowsFilePicker(dialogs: () => host.dialogs).save(suggestedName: 'out.ics');
      const overwritePrompt = 0x00000002;
      expect(host.flags & overwritePrompt, 0);
      expect(host.flags & ofnFileMustExist, 0, reason: 'a save names a file that need not exist');
      expect(host.suggested, 'out.ics', reason: 'the suggestion rides in the buffer itself');
    });

    test('a cancel is a null path with no refusal', () async {
      final host = FakeHost(accepts: false);
      final picked = await WindowsFilePicker(dialogs: () => host.dialogs).open();
      expect(picked.path, isNull);
      expect(picked.refusal, isEmpty);
    });

    test('an open demands a file that exists, which a save must not', () async {
      final opening = FakeHost(answer: 'x.ics');
      await WindowsFilePicker(dialogs: () => opening.dialogs).open();
      expect(opening.flags & ofnFileMustExist, ofnFileMustExist);
      expect(opening.flags & ofnExplorer, ofnExplorer);
      expect(opening.flags & ofnNoChangeDir, ofnNoChangeDir);
    });
  }, skip: Platform.isWindows ? null : 'the heap seam is a Windows call');
}
