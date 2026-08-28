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

Widget sectionHeader(TodoScene scene, String title, int count) => Padding(
  padding: EdgeInsets.fromLTRB(
    scene.px('todo.pad'),
    scene.px('todo.pad'),
    scene.px('todo.pad'),
    scene.px('todo.gap'),
  ),
  child: Text(
    '$title · $count',
    style: scene.theme.ui.copyWith(
      fontSize: scene.px('todo.sectionSize'),
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
