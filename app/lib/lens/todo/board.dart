// Board: the same roster, laid side by side. THE COLUMNS ARE THE GROUPING --
// there is no second sectioning rule and no board-only vocabulary.
//
// A COLUMN EXISTS BEFORE ITS FIRST CARD (ISSUES 8.26). Every state frame the
// document holds is a column whether or not anything is in it, and a container
// or frame the view has chosen keeps its column while empty -- otherwise the
// only way to put the first card somewhere is to have already put one there.
//
// EACH COLUMN HEAD CAPTURES INTO ITSELF: the field at a column's head mints a
// ToDo already carrying that column's meaning -- held by this object, in this
// state, in this group.
//
// A DRAG RE-AUTHORS THE FACT. Dropping a card in another column writes the
// connection that column stands for, through the edit service; nothing here
// moves a card in a private list of its own.

import 'package:flutter/material.dart';

import '../../core/object_kinds.dart';
import '../../core/todo_shape.dart';
import '../../edit/editor.dart';
import '../capacity.dart';
import 'capture_bar.dart';
import 'list.dart';
import 'row.dart';

class BoardLens extends StatelessWidget {
  const BoardLens(this.scene, {super.key});

  final TodoScene scene;

  /// The keys that get a column even with nothing in them: every authored state
  /// under the state grouping, and whatever the view has chosen otherwise.
  List<String> get standing => scene.grouping == 'state'
      ? [
          for (final frame in scene.engine.document.frames.values)
            if (isStateFrame(frame)) frame.id,
        ]
      : [
          if (scene.view['columns'] case final List<Object?> chosen)
            for (final key in chosen) '$key',
        ];

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: scene.theme.paper,
    child: LayoutBuilder(
      builder: (context, box) {
        final admitted = todoEntries(scene, box.maxWidth, box.maxHeight);
        final sections = sectionsOf<TodoEntry>(
          admitted.drawn,
          (entry) => placementsOf(scene, entry),
        );
        final columns = <Section<TodoEntry>>[
          ...sections,
          for (final key in standing)
            if (!sections.any((section) => section.key == key))
              (key: key, title: frameTitle(scene, key), entries: const [], meta: key),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [for (final column in columns) _column(column)],
                ),
              ),
            ),
            if (admitted.truncated) overflowFooter(scene, overflowLabel(admitted)),
          ],
        );
      },
    ),
  );

  Widget _column(Section<TodoEntry> column) => SizedBox(
    width: scene.px('todo.columnWidth'),
    child: DragTarget<String>(
      onAcceptWithDetails: (details) => _move(details.data, column.key),
      builder: (context, candidate, _) => Container(
        color: candidate.isEmpty
            ? null
            : scene.theme.accent.withValues(alpha: scene.px('grid.washToday')),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            sectionHeader(scene, column.title, column.entries.length),
            CaptureBar(scene: scene, seed: _seed(column.key)),
            for (final entry in column.entries)
              Draggable<String>(
                data: entry.id,
                feedback: Material(
                  color: scene.theme.surface,
                  child: SizedBox(
                    width: scene.px('todo.columnWidth'),
                    child: TodoRow(scene: scene, entry: entry),
                  ),
                ),
                childWhenDragging: const SizedBox.shrink(),
                child: TodoRow(scene: scene, entry: entry),
              ),
          ],
        ),
      ),
    ),
  );

  /// What a capture at this column's head is born holding.
  Map<String, String> _seed(String? key) => key == null
      ? const {}
      : switch (scene.grouping) {
          'state' => {'state': key},
          'container' => {'contains': key},
          'frame' => {'group': key},
          _ => const {},
        };

  /// Re-author the connection the destination column stands for. Importance is
  /// derived, never assigned, so a card cannot be dragged into being important.
  ///
  /// ONE UNDO ENTRY (ruled 2026-08-28): leaving the old column and entering the
  /// new one is one act, so the leave and the enter are composed into a single
  /// transaction rather than committed one after the other.
  void _move(String objectId, String? key) {
    final editor = scene.editor;
    final facts = scene.engine.facts;
    final where = key == null ? 'nothing' : frameTitle(scene, key);
    editor.transaction('Move to $where', (current) {
      var next = current;
      switch (scene.grouping) {
        case 'state':
          for (final state in facts.stateAffiliations(objectId)) {
            next = editor.withState(next, objectId, state.frame, title: state.title);
          }
          if (key != null) {
            next = editor.withState(next, objectId, key, title: where);
          }
        case 'container':
          for (final parent in facts.parents(objectId)) {
            next = editor.withContains(next, parent, objectId, false);
          }
          if (key != null) next = editor.withContains(next, key, objectId, true);
        case 'frame':
          final leaving = scene.engine.indexes.directGroupsOf(objectId).toSet();
          for (final relation in next.relations.values.toList()) {
            if (relation.type != 'membership' || relation.member != objectId) continue;
            if (!leaving.contains(relation.group)) continue;
            next = next.remove('relations', relation.id);
          }
          if (key != null) {
            final joined = editor.membership(objectId, key);
            next = next.put('relations', joined.id, joined);
          }
      }
      return next;
    });
  }
}
