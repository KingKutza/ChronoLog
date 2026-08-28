// The edit spec's seams. Uncounted test support: nothing here decides
// behaviour, and every property the spec asserts is restated in the spec.
//
// The store runs on a clock the spec never advances, so no case touches the
// disk beyond the empty journal its load creates.

import 'dart:io';

import 'package:chronolog/core/records.dart';
import 'package:chronolog/edit/editor.dart';
import 'package:chronolog/store/document_store.dart';

import '../store/harness.dart';

typedef Bench = ({Editor editor, DocumentStore store, ManualScheduler scheduler, Directory root});

Future<Bench> openEditor(Document document, {String label = 'edit'}) async {
  final root = await tempRoot(label);
  final scheduler = ManualScheduler();
  final store = DocumentStore(dataRoot: root.path, scheduler: scheduler, establish: () => document);
  await store.load();
  return (editor: Editor(store), store: store, scheduler: scheduler, root: root);
}

Future<void> closeEditor(Bench bench) => removeRoot(bench.root);

/// The document as text, keys sorted. Identity on the document is identity on
/// its RECORDS: undo restores every record to the value it had, and record-level
/// ops restore a re-created record at the end of its map rather than in its old
/// slot. Key order carries no meaning anywhere in the substrate -- `staplesFor`
/// sorts by id for exactly that reason -- so a spec that compared it would be
/// asserting the LinkedHashMap's insertion history, not the document.
String stateOf(Document document) => '${_sorted(document.toJson())}';

Object? _sorted(Object? value) => switch (value) {
  final Map<String, dynamic> map => {
    for (final key in map.keys.toList()..sort()) key: _sorted(map[key]),
  },
  final List<dynamic> list => [for (final item in list) _sorted(item)],
  _ => value,
};

/// The records alone. `meta.modified` is a stamp on the ACT of editing, not a
/// record: a create and the discard that unmakes it are two edits, and the
/// document honestly says it was touched twice.
String recordsOf(Document document) => stateOf(document.copyWith(meta: const {}));
