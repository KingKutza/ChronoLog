// Board: the same roster, laid side by side.
//
// A COLUMN IS A PROJECTION (Don, ISSUES 9.2, answering "how do I author a NOT
// Done for an individual column?"). `view['columns']` is a list of sources: a
// string naming a record is that record's one-term projection, and any other
// string is an expression in the one math over the same names the view bar
// binds -- `AI_Team and not Done`. An entry sits in a column when that column's
// expression ADMITS it, which is the one call `projection.admits(termsOf(id))`
// every column and every lens makes. That is what makes a per-column NOT
// possible at all: while columns were derived from an entry's own connections,
// `(A and not Done) or B` admitted a done item through B and then filed it
// under BOTH, so the exclusion leaked out of the column that said it.
//
// THE ORDER IS THE AUTHORED LIST, NEVER THE CONTENTS (ISSUES 9.2: "when I added
// some todos the second frame moved left"). Populated columns used to sort by
// title with the empty standing ones appended after them, so a frame gaining its
// first member jumped from the tail into the alphabetical block. A column's
// position is its position in the list; empty and populated columns hold their
// place; a new column joins at the end. Nothing here sorts a column.
//
// TWO VERBS ON A HEADER. A header is a `Draggable<String>` carrying its own
// source, and a card is a `Draggable<CardDrag>` carrying an object id, so a
// header drag and a card drag are told apart BY TYPE -- never by where in the
// column the pointer happened to be. Dropping a header on another column
// permutes the list. A single click drops the frames the column can be switched
// to, with the create-a-new-one door on the same list.
//
// A COLUMN EXISTS BEFORE ITS FIRST CARD (ISSUES 8.26). With nothing authored the
// columns are what the grouping reads plus the columns that grouping can stand
// empty -- otherwise the only way to put the first card somewhere is to have
// already put one there.
//
// EACH COLUMN HEAD CAPTURES INTO ITSELF, AND A COLUMN THAT BEARS NO TIME PLACES
// NOTHING (Don's ruling, ISSUES 9.2): a capture at a non-time column's head
// writes ONE staple, to that column, and no calendar placement. TIME-BEARING IS
// DERIVED, never declared -- the frame's own resolved law is asked whether it
// puts positions on the running clock, so a group with a calendar basis bears
// time and a bare group does not, with no flag stored anywhere.
//
// A DRAG RE-AUTHORS THE FACT. Dropping a card in another column writes the
// connection that column stands for and unsays the ones the board's other
// columns stand for, in one transaction; nothing here moves a card in a private
// list of its own.

import 'package:flutter/material.dart';

import '../../core/document.dart';
import '../../core/indexes.dart';
import '../../core/math.dart';
import '../../core/object_kinds.dart';
import '../../core/projection.dart';
import '../../core/records.dart';
import '../../core/staples.dart';
import '../../core/todo_shape.dart';
import '../../core/weight.dart';
import '../../edit/editor.dart';
import '../../session/view_state.dart';
import '../capacity.dart';
import 'capture_bar.dart';
import 'list.dart';
import 'row.dart';

/// What a card carries while it is being dragged. A type of its own, because a
/// header carries a string and the two drops must never be told apart by
/// geometry (ISSUES 9.2).
typedef CardDrag = ({String objectId});

/// One column: the source it stands for, the record that source names where it
/// names exactly one, what its header reads, why it could not be read, and what
/// it holds.
typedef BoardColumn = ({
  String? source,
  String? term,
  String header,
  String? refusal,
  List<TodoEntry> entries,
});

class BoardLens extends StatefulWidget {
  const BoardLens(this.scene, {super.key});

  final TodoScene scene;

  @override
  State<BoardLens> createState() => _BoardLensState();
}

class _BoardLensState extends State<BoardLens> {
  /// The source of the column whose header chooser is open, or the empty string
  /// for the board's own "stand a column" chooser. Null when none is.
  String? _choosing;
  String _query = '';

  TodoScene get scene => widget.scene;

  void _open(String? which) => setState(() {
    _choosing = which;
    _query = '';
  });

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: scene.theme.paper,
    child: LayoutBuilder(
      builder: (context, box) {
        final admitted = todoEntries(scene, box.maxWidth, box.maxHeight);
        final columns = _columns(admitted.drawn);
        final filed = {
          for (final column in columns)
            for (final entry in column.entries) entry.id,
        };
        final unfiled = admitted.drawn.where((entry) => !filed.contains(entry.id)).length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            groupingNote(scene),
            _standDoor(columns),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var index = 0; index < columns.length; index += 1)
                      _column(columns[index], index, columns),
                  ],
                ),
              ),
            ),
            // NOTHING DISAPPEARS SILENTLY: an entry the authored columns all
            // refuse is still projected, and the board says how many rather
            // than dropping them out of the picture.
            if (unfiled > 0) footerNote(scene, '$unfiled admitted by no column'),
            if (admitted.truncated) overflowFooter(scene, overflowLabel(admitted)),
          ],
        );
      },
    ),
  );

  // --- What the columns are --------------------------------------------------

  /// THE AUTHORED LIST WHERE THERE IS ONE, and what the grouping reads where
  /// there is not. An authored board is exactly its own columns, in its own
  /// order: that is what lets one column say NOT and mean it.
  List<BoardColumn> _columns(List<TodoEntry> drawn) {
    final authored = scene.chosenColumns;
    if (authored.isNotEmpty) {
      // The names an expression may use are the frame titles, bound exactly as
      // the view bar binds them, so one column and the whole board are written
      // in one vocabulary. Bound only when a column actually spells an
      // expression: a board of plain record columns must not pay for the
      // document's whole title list on every paint.
      final document = scene.engine.document;
      final spelled = authored.any(
        (source) => !document.frames.containsKey(source) && !document.events.containsKey(source),
      );
      final bindings = spelled
          ? ViewState.bindingsFor(document.frames.keys, (id) => frameTitle(scene, id))
          : const <String, String>{};
      return [for (final source in authored) _authored(source, drawn, bindings)];
    }
    final sections = sectionsOf<TodoEntry>(drawn, (entry) => placementsOf(scene, entry));
    final grouping = groupingFor(scene.grouping);
    return [
      for (final section in sections)
        (
          source: section.key,
          term: section.key,
          header: section.title,
          refusal: null,
          entries: _chained(section.entries),
        ),
      for (final key in grouping.standing(scene.engine.document.frames.values))
        if (!sections.any((section) => section.key == key))
          (
            source: key,
            term: key,
            header: columnTitle(scene, key),
            refusal: null,
            entries: const <TodoEntry>[],
          ),
    ];
  }

  /// One authored column, read as a projection. A source naming a record is that
  /// record's own term and reads as its title; anything else is the one math and
  /// reads as itself, so what a column filters by is legible on the column.
  BoardColumn _authored(String source, List<TodoEntry> drawn, Map<String, String> bindings) {
    final document = scene.engine.document;
    final names = document.frames.containsKey(source) || document.events.containsKey(source);
    final header = names ? frameTitle(scene, source) : source;
    Projection? projection;
    String? refusal;
    final held = <TodoEntry>[];
    try {
      projection = names ? Projection.of([source]) : Projection.parse(source, bindings: bindings);
      for (final entry in drawn) {
        if (projection.admits(scene.engine.termsOf(entry.id).contains)) held.add(entry);
      }
    } on MathRefusal catch (refused) {
      refusal = refused.message;
      held.clear();
    }
    return (
      source: source,
      term: names ? source : null,
      header: header,
      refusal: refusal,
      entries: _chained(held),
    );
  }

  /// WHAT A SENTENCE JOINED, WEIGHT NEVER SEPARATES (ISSUES 9.2: "I would expect
  /// a sigil, a line, an adjacency, something"). Entries an object-to-object
  /// staple joins are one CHAIN, adjacent in the column; the chain stands where
  /// its heaviest member would stand, and inside it the members keep the order
  /// weight already gave them. Weight still orders the column -- it just orders
  /// chains rather than rows.
  List<TodoEntry> _chained(List<TodoEntry> ranked) {
    if (ranked.length < 2) return List.of(ranked);
    final at = {for (var index = 0; index < ranked.length; index += 1) ranked[index].id: index};
    final root = [for (var index = 0; index < ranked.length; index += 1) index];
    int find(int index) => root[index] == index ? index : (root[index] = find(root[index]));
    for (var index = 0; index < ranked.length; index += 1) {
      for (final end in ranked[index].farEnds) {
        if (end.frame != null) continue;
        final other = at[end.id];
        if (other == null) continue;
        final left = find(index), right = find(other);
        // The EARLIER index leads, and the list arrived ranked, so a chain's
        // root is its heaviest member with nothing here reading a weight.
        if (left != right) root[left < right ? right : left] = left < right ? left : right;
      }
    }
    final led = <int>{};
    final chained = <TodoEntry>[];
    for (var index = 0; index < ranked.length; index += 1) {
      if (!led.add(find(index))) continue;
      for (var member = index; member < ranked.length; member += 1) {
        if (find(member) == find(index)) chained.add(ranked[member]);
      }
    }
    return chained;
  }

  // --- One column ------------------------------------------------------------

  Widget _column(BoardColumn column, int index, List<BoardColumn> columns) => SizedBox(
    width: scene.px('todo.columnWidth'),
    child: DragTarget<String>(
      // A HEADER LANDING: the dragged column takes this one's place.
      onAcceptWithDetails: (details) => _reorder(details.data, index, columns),
      builder: (context, headers, _) => DragTarget<CardDrag>(
        onAcceptWithDetails: (details) => _move(details.data.objectId, column, columns),
        builder: (context, cards, _) => Container(
          color: headers.isEmpty && cards.isEmpty
              ? null
              : scene.theme.accent.withValues(alpha: scene.px('grid.washToday')),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(column),
              if (_choosing == column.source && column.source != null)
                _chooser(
                  onPicked: (id) => _switch(column.source!, id, columns),
                  onCreate: (name) => _mint(name, replacing: column.source, columns: columns),
                ),
              if (column.refusal case final refused?) _refusal(refused),
              _capture(column.term),
              for (final entry in column.entries)
                Draggable<CardDrag>(
                  data: (objectId: entry.id),
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
    ),
  );

  /// THE HEADER, WITH ITS TWO VERBS. Drag it and the authored order is
  /// rewritten; click it and the frames this column could stand for drop, the
  /// typed name among them offering to make what nothing is called yet.
  ///
  /// The unnamed column -- what the grouping had nothing to say about -- names no
  /// source, so it carries neither verb: there is no list entry to permute and
  /// nothing to switch it to.
  Widget _header(BoardColumn column) {
    final head = sectionHeader(scene, column.header, column.entries.length);
    final source = column.source;
    if (source == null || scene.onView == null) return head;
    return GestureDetector(
      onTap: () => _open(_choosing == source ? null : source),
      child: Draggable<String>(
        data: source,
        feedback: Material(
          color: scene.theme.surface,
          child: SizedBox(width: scene.px('todo.columnWidth'), child: head),
        ),
        childWhenDragging: Opacity(opacity: scene.px('todo.sparseOpacity'), child: head),
        child: head,
      ),
    );
  }

  /// The capture at a column's head, born holding what the column stands for.
  ///
  /// A TIME-BEARING COLUMN IS PLACED ON, ANYTHING ELSE IS STAPLED TO. The
  /// question is asked of the frame's own law rather than of a type: a frame
  /// bears time when its resolved coordinate -- its own, or the one its basis
  /// hands it -- puts positions on the running clock.
  Widget _capture(String? term) {
    final bearing = term != null && bearsTime(scene, term);
    return CaptureBar(
      scene: scene,
      seed: bearing ? const {} : columnSeed(scene.engine.document, term),
      frame: bearing ? term : null,
    );
  }

  Widget _refusal(String said) => Padding(
    padding: EdgeInsets.symmetric(horizontal: scene.px('todo.pad')),
    child: Text(
      said,
      style: scene.theme.data.copyWith(
        fontSize: scene.px('todo.metaSize'),
        color: scene.theme.primary,
      ),
    ),
  );

  // --- The chooser -----------------------------------------------------------

  /// PULL A FRAME UP AS A COLUMN (ISSUES 9.1: "I see no power to pull up
  /// frames"). The board's own door onto the same chooser a header carries, so
  /// standing a new column and switching an old one are one instrument.
  Widget _standDoor(List<BoardColumn> columns) {
    final write = scene.onView;
    if (write == null) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: scene.px('todo.pad')),
        child: Text(
          'No view behind this board to hold a chosen column.',
          style: scene.theme.ui.copyWith(
            fontSize: scene.px('todo.metaSize'),
            color: scene.theme.muted,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: scene.px('todo.pad')),
          child: GestureDetector(
            onTap: () => _open(_choosing == '' ? null : ''),
            child: Text(
              'Stand a column…',
              style: scene.theme.ui.copyWith(fontSize: scene.px('todo.metaSize')),
            ),
          ),
        ),
        if (_choosing == '')
          SizedBox(
            width: scene.px('todo.columnWidth'),
            child: _chooser(
              onPicked: (id) => _stand(id, columns),
              onCreate: (name) => _mint(name, replacing: null, columns: columns),
            ),
          ),
      ],
    );
  }

  /// A NAME NOTHING WEARS IS AN OFFER TO MAKE IT (ISSUES 9.2). One typed entry
  /// over a WINDOWED find -- nothing enumerates the document, so this reads the
  /// same at five frames and at five hundred -- and a name no frame answers to
  /// offers to become one.
  Widget _chooser({
    required void Function(String id) onPicked,
    required void Function(String name) onCreate,
  }) {
    final document = scene.engine.document;
    final window = scene.setting('todo.chooserRows').floor().toInt();
    final typed = _query.trim();
    final matches = typed.isEmpty
        ? [
            for (final frame in document.frames.values) frame.id,
          ]
        : [
            for (final id in titleIndexOf(document).matching(typed).keys)
              if (document.frames.containsKey(id)) id,
          ];
    final rows = (matches..sort((a, b) => frameTitle(scene, a).compareTo(frameTitle(scene, b))))
        .take(window)
        .toList();
    final worn = rows.any(
      (id) => frameTitle(scene, id).toLowerCase() == typed.toLowerCase(),
    );
    final mints = groupingFor(scene.grouping).columnTraits.isNotEmpty;
    return Padding(
      padding: EdgeInsets.all(scene.px('todo.pad')),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: scene.px('todo.captureHeight'),
            child: TextField(
              style: scene.theme.ui.copyWith(fontSize: scene.px('todo.metaSize')),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Find a frame, or name a new one',
                hintStyle: scene.theme.ui.copyWith(
                  fontSize: scene.px('todo.metaSize'),
                  color: scene.theme.muted,
                ),
              ),
              onChanged: (text) => setState(() => _query = text),
            ),
          ),
          for (final id in rows)
            GestureDetector(
              onTap: () => onPicked(id),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: scene.px('todo.gap')),
                child: Text(
                  frameTitle(scene, id),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: scene.theme.ui.copyWith(fontSize: scene.px('todo.metaSize')),
                ),
              ),
            ),
          if (typed.isNotEmpty && !worn && mints)
            GestureDetector(
              onTap: () => onCreate(typed),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: scene.px('todo.gap')),
                child: Text(
                  'New column $typed',
                  style: scene.theme.ui.copyWith(
                    fontSize: scene.px('todo.metaSize'),
                    color: scene.theme.primary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // --- Writing the authored order --------------------------------------------

  /// The order as it stands on the surface, which is what a permutation permutes:
  /// the authored list where there is one, and otherwise the columns the grouping
  /// read, materialised the moment a person first says one of them moves.
  List<String> _order(List<BoardColumn> columns) => [
    for (final column in columns) ?column.source,
  ];

  void _write(List<String> order) {
    scene.onView?.call('columns', order);
    setState(() => _choosing = null);
  }

  void _reorder(String source, int onto, List<BoardColumn> columns) {
    final order = _order(columns);
    final from = order.indexOf(source);
    if (from < 0) return;
    final landing = order.indexOf(columns[onto].source ?? source);
    if (landing < 0 || landing == from) return;
    order.removeAt(from);
    order.insert(landing, source);
    _write(order);
  }

  void _switch(String source, String id, List<BoardColumn> columns) {
    final order = _order(columns);
    final at = order.indexOf(source);
    if (at < 0) return;
    order[at] = id;
    _write(order);
  }

  void _stand(String id, List<BoardColumn> columns) {
    final order = _order(columns);
    if (!order.contains(id)) order.add(id);
    _write(order);
  }

  /// MINT A FRAME AT THE MOMENT YOU SEE THE COLUMN IS MISSING (ISSUES 9.2). The
  /// traits are the grouping's own -- a group frame where columns are frames, a
  /// state frame where they are states -- and the column joins the authored order
  /// at the end, or takes the place of the column that offered to make it.
  void _mint(String name, {required String? replacing, required List<BoardColumn> columns}) {
    final traits = groupingFor(scene.grouping).columnTraits;
    if (traits.isEmpty) return;
    // A STATE IS NOT A PROMOTION. A group frame is born carrying the shipped
    // weight every new group carries; a state frame is born carrying none, the
    // same as one minted by the row's own "New state..." -- two doors onto one
    // kind of record must not write two different records.
    final promoted = !traits.contains('state');
    final frame = Frame(
      id: createId('frame'),
      title: name,
      traits: traits,
      extra: {
        if (promoted) 'display': {'weight': defaultWeightForNewFrame('group')?.toJson()},
      },
    );
    scene.editor.transaction('New frame $name', (current) => current.put('frames', frame.id, frame));
    if (replacing == null) {
      _stand(frame.id, columns);
    } else {
      _switch(replacing, frame.id, columns);
    }
  }

  // --- A card lands in another column ----------------------------------------

  /// RE-AUTHOR THE CONNECTION THE DESTINATION COLUMN STANDS FOR, and unsay the
  /// ones the board's other columns stand for. One transaction, one undo entry:
  /// leaving a column and entering another is one act.
  ///
  /// The discrimination is STRUCTURAL, never a list of grouping names: a state
  /// frame is entered and dated, an ordinary frame is stapled to, and an object
  /// holds what is dropped on it. A column that is an expression rather than one
  /// record has no single sentence to write, and says so instead of guessing
  /// which half of `A and not Done` the person meant.
  void _move(String objectId, BoardColumn into, List<BoardColumn> columns) {
    final editor = scene.editor;
    final term = into.term;
    if (term == null) return;
    // WHAT IT LEAVES IS THE OTHER COLUMNS OF THIS BOARD, and nothing else: a
    // card moved from one column to another leaves the column it was in, and a
    // frame that is not on this board was never part of the act. Which is also
    // why a placement is never unsaid here -- an affiliation is a column, a
    // position is not.
    final leaving = [
      for (final column in columns)
        if (column.term case final other?)
          if (other != term) other,
    ];
    editor.transaction('Move to ${into.header}', (current) {
      var next = current;
      for (final other in leaving) {
        next = _unsay(next, objectId, other);
      }
      return _say(next, objectId, term);
    });
  }

  Document _say(Document current, String objectId, String term) {
    final frame = current.frames[term];
    if (frame == null) {
      return current.events.containsKey(term)
          ? scene.editor.withContains(current, term, objectId, true)
          : current;
    }
    if (isStateFrame(frame)) {
      return _affiliation(current, objectId, term) != null
          ? current
          : scene.editor.withState(current, objectId, term, title: frame.title ?? term);
    }
    if (_affiliation(current, objectId, term) != null) return current;
    final joined = scene.editor.membership(objectId, term);
    return current.put('relations', joined.id, joined);
  }

  Document _unsay(Document current, String objectId, String term) {
    final frame = current.frames[term];
    if (frame == null) {
      return current.events.containsKey(term)
          ? scene.editor.withContains(current, term, objectId, false)
          : current;
    }
    final said = _affiliation(current, objectId, term);
    if (said == null) return current;
    return isStateFrame(frame)
        ? scene.editor.withState(current, objectId, term, title: frame.title ?? term)
        : current.remove('relations', said.id);
  }

  /// The record saying this object is in that frame, in EITHER spelling -- a
  /// `membership` from an older build and a staple whose frame end names no
  /// point are one sentence (ruled 2026-09-01).
  Relation? _affiliation(Document current, String objectId, String frameId) {
    for (final relation in current.relations.values) {
      if (relation.type == 'membership') {
        if (relation.member == objectId && relation.group == frameId) return relation;
        continue;
      }
      for (final edge in stapledAffiliations(relation)) {
        if (edge.object == objectId && edge.frame == frameId) return relation;
      }
    }
    return null;
  }
}
