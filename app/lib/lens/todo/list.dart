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
        // ONE ROW PER ENTRY. A board stands an entry under EVERY column that
        // admits it -- that is what a column is for -- but a list is one
        // roster read top to bottom, and the same to-do printed twice under
        // two headings reads as two to-dos. So a list files an entry once and
        // the row's own chips name the rest; nothing is hidden, and nothing is
        // counted twice.
        //
        // UNDER THE LIST IT BELONGS TO, NOT UNDER THE CLOCK. Which one it is
        // filed under must not fall out of an id sort, so the one it is filed
        // under is the first that BEARS NO TIME: "a to-do with only a group
        // staple has no position and that is fine -- the group is its list"
        // (Don, ISSUES 9.2). A to-do placed on Wall Time and stapled to
        // Errands is an errand that happens to be scheduled, and Errands is
        // the heading a person is looking for. With nothing but time to go on,
        // time is the heading.
        final sections = sectionsOf<TodoEntry>(
          admitted.drawn,
          (entry) => _filed(scene, placementsOf(scene, entry)),
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

/// The one section a list files an entry under: the first that bears no time,
/// and otherwise the first there is.
Iterable<Placement> _filed(TodoScene scene, Iterable<Placement> under) {
  Placement? first, timeless;
  for (final placement in under) {
    first ??= placement;
    if (placement.key case final key?) {
      if (timeless == null && !bearsTime(scene, key)) timeless = placement;
    } else {
      timeless ??= placement;
    }
  }
  final filed = timeless ?? first;
  return filed == null ? const [] : [filed];
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

Widget overflowFooter(TodoScene scene, String label) =>
    footerNote(scene, '$label more than this surface holds');

/// One quiet line under the surface, in the one footer voice: what the picture
/// could not hold, and what it holds but could not file.
Widget footerNote(TodoScene scene, String said) => Padding(
  padding: EdgeInsets.all(scene.px('todo.pad')),
  child: Text(
    said,
    style: scene.theme.data.copyWith(fontSize: scene.px('todo.metaSize'), color: scene.theme.muted),
  ),
);
