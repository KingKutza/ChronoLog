// List: every projected ToDo in one column, sectioned by the chosen grouping.
//
// NO STATE GATE. A section is a section because entries put it there; which
// entries exist at all is the projection's boolean algebra and nothing else.
// The null section LEADS -- an unfiled capture must never be buried -- and an
// empty section is never emitted, by construction in `sectionsOf`.
//
// The overflow is a LOWER BOUND: what the surface could not hold reads "N+",
// because the field knows only that at least one more existed.

import 'package:flutter/material.dart';

import '../../core/todo_shape.dart';
import '../capacity.dart';
import 'capture_bar.dart';
import 'row.dart';

class ListLens extends StatelessWidget {
  const ListLens(this.scene, {super.key});

  final TodoScene scene;

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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CaptureBar(scene: scene),
            Expanded(
              child: ListView(
                children: [
                  for (final section in sections) ...[
                    sectionHeader(scene, section.title, section.entries.length),
                    for (final entry in section.entries) TodoRow(scene: scene, entry: entry),
                  ],
                ],
              ),
            ),
            if (admitted.truncated) overflowFooter(scene, overflowLabel(admitted)),
          ],
        );
      },
    ),
  );
}

/// A section head: THE COLUMN'S NAME, and beside it how many are in it.
///
/// Two widgets rather than one welded string (ISSUES 9.1): a column's name is a
/// name, and a heading that reads "AI Tiger Team · 1" as one run of text is a
/// name nothing on the surface -- a finder, a screen reader, a person scanning
/// the row of heads -- can pick out.
Widget sectionHeader(TodoScene scene, String title, int count) => Padding(
  padding: EdgeInsets.fromLTRB(
    scene.px('todo.pad'),
    scene.px('todo.pad'),
    scene.px('todo.pad'),
    scene.px('todo.gap'),
  ),
  child: Row(
    children: [
      Flexible(
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: scene.theme.ui.copyWith(
            fontSize: scene.px('todo.sectionSize'),
            color: scene.theme.muted,
          ),
        ),
      ),
      SizedBox(width: scene.px('todo.gap')),
      Text(
        '· $count',
        style: scene.theme.data.copyWith(
          fontSize: scene.px('todo.sectionSize'),
          color: scene.theme.muted,
        ),
      ),
    ],
  ),
);

/// What this surface's grouping READS, said in words above the columns. A
/// grouping that quietly counts one kind of connection and not another is how
/// "I see no power to pull up frames" happened (ISSUES 9.1); the sentence is
/// the surface owning its own rule.
Widget groupingNote(TodoScene scene) => Padding(
  padding: EdgeInsets.fromLTRB(
    scene.px('todo.pad'),
    scene.px('todo.pad'),
    scene.px('todo.pad'),
    0,
  ),
  child: Text(
    groupingReads(scene.grouping),
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: scene.theme.ui.copyWith(
      fontSize: scene.px('todo.metaSize'),
      color: scene.theme.muted,
    ),
  ),
);

Widget overflowFooter(TodoScene scene, String label) => Padding(
  padding: EdgeInsets.all(scene.px('todo.pad')),
  child: Text(
    '$label more than this surface holds',
    style: scene.theme.data.copyWith(fontSize: scene.px('todo.metaSize'), color: scene.theme.muted),
  ),
);
