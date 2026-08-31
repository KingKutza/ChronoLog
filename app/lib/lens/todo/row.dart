// The one ToDo row, and the population both roster lenses share.
//
// POPULATION IS THE PROJECTION. The state gate is gone: no lens asks which state
// frames are selected, because controlling which states project is what a filter
// would have done, and it is authored as a NOT term. An entry with no connection
// at all -- a bare capture -- is in no expression's universe and is shown, since
// hiding it is how capture silently loses work.
//
// The row is CHROME ONLY. Sections and columns are each lens's own math; what a
// row looks like, what its checkbox does and how a state is authored belong here
// exactly once (survey H2).
//
// AUTHORING STATE (ISSUES 8.26, "no way to author or amend status"): the chooser
// applies ANY state frame the document holds, mints a new one by name, and shows
// the completion instant the end staple records. Done is a frame like any other;
// nothing here enumerates a state vocabulary.

import 'package:flutter/material.dart';

import '../../core/coordinate_entry.dart';
import '../../core/document.dart';
import '../../core/exact.dart';
import '../../core/object_kinds.dart';
import '../../core/projection.dart';
import '../../core/records.dart';
import '../../core/todo_shape.dart';
import '../../edit/editor.dart';
import '../capacity.dart';
import '../display_weight.dart';
import '../mark_gestures.dart';
import '../marks.dart';
import '../theme.dart';
import '../tunables.dart';
import '../view_tile.dart';
import 'board.dart';
import 'list.dart';

const Map<String, String> todoTunableDefaults = {
  'todo.rowHeight': '30',
  'todo.pad': '6',
  'todo.gap': '4',
  'todo.box': '16',
  'todo.titleSize': '13',
  'todo.metaSize': '10',
  'todo.sectionSize': '11',
  'todo.columnWidth': '248',
  'todo.captureHeight': '34',
  'todo.sparseOpacity': '0.55',
  'todo.rowFootprint': '30',
  'todo.list.importantAt': '2',
  'todo.list.landmarkAt': '4',
  'todo.board.importantAt': '2',
  'todo.board.landmarkAt': '4',
};

/// What a hosted roster lens is looking at, read from the view tile itself: the
/// controller carries the projection, the per-lens view map, the selection and
/// the settings, so there is ONE description of what a tile is looking at and a
/// host has no callback to remember.
TodoScene todoSceneOfTile(BuildContext context, ViewTileController tile) => TodoScene(
  lens: tile.lensId,
  editor: tile.editor,
  projection: tile.projection,
  theme: ChronoTheme.of(context),
  nowDays: nowDays(),
  tunable: tile.tunable,
  view: tile.view,
  selection: tile.selection,
  onOpen: tile.openObject,
  // The row is a mark, so it gets the mark vocabulary rather than a tap
  // handler of its own (ruled 2026-08-31).
  gestures: (objectId, child) => MarkGestures(tile: tile, objectId: objectId, child: child),
  onProject: tile.project,
);

/// Both roster lenses, into the ONE widget registry the view tile reads. A
/// roster lens is NOT a time surface: a drag here never mints an event.
void registerTodoLenses() {
  registerLensWidget('list', (context, tile) => ListLens(todoSceneOfTile(context, tile)));
  registerLensWidget('board', (context, tile) => BoardLens(todoSceneOfTile(context, tile)));
}

/// Everything a roster lens draws from, and nothing it could mutate except
/// through [editor].
@immutable
class TodoScene {
  const TodoScene({
    required this.lens,
    required this.editor,
    required this.projection,
    required this.theme,
    required this.nowDays,
    this.tunable,
    this.view = const {},
    this.selection = const {},
    this.onOpen,
    this.gestures,
    this.onProject,
  });

  final String lens;
  final Editor editor;
  final Projection projection;
  final ChronoTheme theme;
  final Rational nowDays;
  final Tunable? tunable;
  final Map<String, Object?> view;
  final Set<String> selection;
  final void Function(String objectId)? onOpen;

  /// The pointer vocabulary a row is wrapped in: select, open, menu. Null where
  /// the surface has no tile behind it, in which case a row is inert chrome and
  /// says nothing it cannot do.
  final Widget Function(String objectId, Widget child)? gestures;

  /// Add a frame to what this view projects. Null where the surface offers no
  /// such path, in which case a note says where an object went and stops there.
  final void Function(String frameId)? onProject;

  ProjectionEngine get engine => editor.engine;

  String? get frameId => projection.primaryFrame;

  Rational setting(String key) => tunableFrom(todoTunableDefaults, tunable, key);

  double px(String key) => setting(key).toDouble();

  String get grouping => normalizeGrouping(view['grouping']);

  Rational get spanDays => setting('todo.spanDays');
}

/// One roster row: the object, what is known about it, and how it weighed.
typedef TodoEntry = ({
  String id,
  String title,
  Fact? fact,
  String? state,
  List<StateAffiliation> states,
  List<String> groups,
  List<String> parents,
  ContainsSummary contains,
  String promotion,
  Rational weight,
});

/// The projected roster, ranked by weight and cut to what the surface can hold.
/// The remainder is a LOWER BOUND, never a silent drop.
Admitted<TodoEntry> todoEntries(TodoScene scene, double width, double height) {
  final engine = scene.engine;
  final found = engine.queryFacts(
    scene.projection,
    start: scene.nowDays - scene.spanDays,
    end: scene.nowDays + scene.spanDays,
    limit: capacityOf(width, height, scene.tunable, heightKey: 'todo.rowFootprint').queryBudget,
    includeOverlaps: true,
  );
  final entries = <String, TodoEntry>{};
  for (final fact in found.facts) {
    if (objectKindForEvent(fact.event) != 'todo') continue;
    entries[fact.event.id] ??= _entry(scene, fact.event.id, fact);
  }
  // A ToDo with no placement is invisible to a fact query, and it is exactly the
  // one a capture just made. The roster is the model's own enumeration of a
  // kind; the window below it is what keeps the surface bounded.
  for (final row in engine.facts.rosterEntries('todo')) {
    if (entries.containsKey(row.id) || row.coordinate != null) continue;
    final reach = engine.modifyingFrames(row.id).keys.toSet();
    final speaks = scene.projection.inUniverse(reach.contains);
    if (speaks && !scene.projection.admits(reach.contains)) continue;
    entries[row.id] = _entry(scene, row.id, null);
  }
  final ranked = entries.values.toList()
    ..sort((a, b) {
      final byWeight = b.weight.compareTo(a.weight);
      return byWeight != 0 ? byWeight : a.title.compareTo(b.title);
    });
  return admit(
    ranked,
    capacityOf(width, height, scene.tunable, heightKey: 'todo.rowFootprint'),
    queryTruncated: found.truncated,
  );
}

TodoEntry _entry(TodoScene scene, String id, Fact? fact) {
  final facts = scene.engine.facts;
  final states = facts.stateAffiliations(id);
  final groups = [
    for (final group in scene.engine.indexes.directGroupsOf(id))
      if (!isStateFrame(scene.engine.document.frames[group])) group,
  ];
  final weight = fact == null ? Rational.one : scene.engine.weightOf(fact, scene.projection).weight;
  final title = str(scene.engine.document.events[id]?.payload?['title']) ?? '';
  return (
    id: id,
    title: title.isEmpty ? '(untitled)' : title,
    fact: fact,
    state: entryState(facts, id, stateFrames: [for (final s in states) s.frame], groups: groups),
    states: states,
    groups: groups,
    parents: facts.parents(id),
    contains: facts.containsSummary(id),
    promotion: promotionOf(weight, scene.tunable, keyPrefix: 'todo.${scene.lens}'),
    weight: weight,
  );
}

const Map<String, String> promotionTitles = {
  landmarkWeight: 'Landmark',
  importantWeight: 'Important',
  standardWeight: 'Standard',
};

/// What to call a frame or an object by id: its authored title, never a bare
/// record id where one exists.
String frameTitle(TodoScene scene, String id) {
  final frame = scene.engine.document.frames[id];
  if (frame != null) return frame.title ?? id;
  return str(scene.engine.document.events[id]?.payload?['title']) ?? id;
}

/// Where one entry belongs under [TodoScene.grouping]. A null key is the unnamed
/// section, which leads; nothing here emits an empty one.
Iterable<Placement> placementsOf(TodoScene scene, TodoEntry entry) => switch (scene.grouping) {
  'importance' => [
    (key: entry.promotion, title: promotionTitles[entry.promotion] ?? entry.promotion, meta: null),
  ],
  'container' =>
    entry.parents.isEmpty
        ? const [(key: null, title: 'Held by nothing', meta: null)]
        : [
            for (final parent in entry.parents)
              (key: parent, title: frameTitle(scene, parent), meta: parent),
          ],
  'frame' =>
    entry.groups.isEmpty
        ? const [(key: null, title: 'No frame', meta: null)]
        : [
            for (final group in entry.groups)
              (key: group, title: frameTitle(scene, group), meta: group),
          ],
  _ =>
    entry.states.isEmpty
        ? const [(key: null, title: 'Open', meta: null)]
        : [
            for (final state in entry.states)
              (key: state.frame, title: state.title, meta: state.at),
          ],
};

/// The one row. A card on a board and a line in a list are the same chrome.
class TodoRow extends StatefulWidget {
  const TodoRow({required this.scene, required this.entry, super.key});

  final TodoScene scene;
  final TodoEntry entry;

  @override
  State<TodoRow> createState() => _TodoRowState();
}

class _TodoRowState extends State<TodoRow> {
  final TextEditingController _minted = TextEditingController();
  bool _naming = false;
  String? _departed;

  TodoScene get scene => widget.scene;
  TodoEntry get entry => widget.entry;

  @override
  void dispose() {
    _minted.dispose();
    super.dispose();
  }

  /// Enter or leave a state, then say where the object went if the projection no
  /// longer speaks for it -- a note in place, never a dialog, and never a
  /// disappearance (ISSUES 8.26).
  void _toggle(String frameId, String title) {
    scene.editor.toggleState(entry.id, frameId, title: title);
    final reach = scene.engine.modifyingFrames(entry.id).keys.toSet();
    final gone = scene.projection.inUniverse(reach.contains)
        ? !scene.projection.admits(reach.contains)
        : false;
    setState(() {
      _naming = false;
      _departed = gone ? frameId : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = scene.theme;
    final resolved = entry.states.isNotEmpty;
    final faded = entry.state == 'sparse' ? scene.px('todo.sparseOpacity') : 1.0;
    final pad = scene.px('todo.pad');
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: pad, vertical: scene.px('todo.gap')),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // The done checkbox is its own click target, distinct from the
              // open action beside it.
              _Box(
                scene: scene,
                filled: resolved,
                onTap: () => _toggle(doneStateFrameId, doneStateTitle),
              ),
              SizedBox(width: pad),
              Expanded(
                child: _named(
                  Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.ui.copyWith(
                      fontSize: scene.px('todo.titleSize'),
                      color: theme.ink.withValues(alpha: faded),
                      decoration: resolved ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
              ),
              _chooser(),
            ],
          ),
          _meta(),
          if (_naming) _mint(),
          if (_departed != null) _note(_departed!),
        ],
      ),
    );
  }

  /// The row's name, under the one pointer vocabulary and inside the ink ring
  /// that says it is selected. A roster row is a mark: single click selects,
  /// double click opens its card, the secondary button raises the menu with Open
  /// on it -- the same rules the painted surfaces keep.
  Widget _named(Widget title) {
    final selected = scene.selection.contains(entry.id);
    final ring = tunable(scene.tunable, 'selection.ring').toDouble();
    final wrapped = Container(
      padding: EdgeInsets.symmetric(horizontal: scene.px('todo.gap')),
      decoration: selected
          ? BoxDecoration(
              border: Border.all(
                color: scene.theme.ink.withValues(
                  alpha: tunable(scene.tunable, 'selection.ringOpacity').toDouble(),
                ),
                width: tunable(scene.tunable, 'selection.inner').toDouble(),
              ),
              borderRadius: BorderRadius.circular(ring),
            )
          : null,
      child: title,
    );
    final gestures = scene.gestures;
    return gestures == null
        ? GestureDetector(onTap: () => scene.onOpen?.call(entry.id), child: wrapped)
        : gestures(entry.id, wrapped);
  }

  /// The state chooser: every state frame the document holds, plus a new one by
  /// name. The vocabulary is whatever has been authored -- nothing enumerates it.
  Widget _chooser() {
    final frames = [
      for (final frame in scene.engine.document.frames.values)
        if (isStateFrame(frame)) frame,
    ];
    return MenuAnchor(
      menuChildren: [
        for (final frame in frames)
          MenuItemButton(
            onPressed: () => _toggle(frame.id, frame.title ?? frame.id),
            leadingIcon: _Box(
              scene: scene,
              filled: entry.states.any((state) => state.frame == frame.id),
              onTap: null,
            ),
            child: Text(frame.title ?? frame.id, style: scene.theme.ui),
          ),
        MenuItemButton(
          onPressed: () => setState(() => _naming = true),
          child: Text('New state…', style: scene.theme.ui),
        ),
      ],
      builder: (context, controller, _) => GestureDetector(
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        child: Text(
          entry.states.isEmpty ? '·' : entry.states.map((state) => state.title).join(', '),
          style: scene.theme.data.copyWith(
            fontSize: scene.px('todo.metaSize'),
            color: scene.theme.muted,
          ),
        ),
      ),
    );
  }

  Widget _mint() => TextField(
    controller: _minted,
    autofocus: true,
    style: scene.theme.ui.copyWith(fontSize: scene.px('todo.metaSize')),
    decoration: const InputDecoration(hintText: 'Name the state', isDense: true),
    onSubmitted: (name) => name.trim().isEmpty
        ? setState(() => _naming = false)
        : _toggle(createId('frame'), name.trim()),
  );

  /// A sparse row reads light and says so; a contained one reports what it
  /// holds; a resolved one reports when, from the end staple that states it.
  Widget _meta() {
    final parts = <String>[
      if (entry.contains.total > 0)
        '${entry.contains.done} of ${entry.contains.total}${entry.contains.cyclic ? ' (loops)' : ''}',
      for (final state in entry.states)
        if (state.at case final instant?)
          '${state.title} ${formatCoordinateEntry(instant.coordinate, scene.engine.lawOf(instant.frame))}',
      for (final group in entry.groups) frameTitle(scene, group),
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(left: scene.px('todo.box') + scene.px('todo.pad')),
      child: Text(
        parts.join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: scene.theme.data.copyWith(
          fontSize: scene.px('todo.metaSize'),
          color: scene.theme.muted,
        ),
      ),
    );
  }

  Widget _note(String frameId) => Row(
    children: [
      Expanded(
        child: Text(
          'Now in ${frameTitle(scene, frameId)}, which this view does not project.',
          style: scene.theme.data.copyWith(
            fontSize: scene.px('todo.metaSize'),
            color: scene.theme.primary,
          ),
        ),
      ),
      if (scene.onProject != null)
        GestureDetector(
          onTap: () {
            scene.onProject!(frameId);
            setState(() => _departed = null);
          },
          child: Text(
            'Project it',
            style: scene.theme.ui.copyWith(fontSize: scene.px('todo.metaSize')),
          ),
        ),
    ],
  );
}

/// The state box: the task ring from the ONE sigil vocabulary, so a roster and
/// a calendar say the same thing with the same shape. A click target of its
/// own, distinct from the open action beside it.
class _Box extends StatelessWidget {
  const _Box({required this.scene, required this.filled, required this.onTap});

  final TodoScene scene;
  final bool filled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final side = scene.px('todo.box');
    return GestureDetector(
      onTap: onTap,
      child: CustomPaint(size: Size(side, side), painter: _BoxPainter(scene, filled)),
    );
  }
}

class _BoxPainter extends CustomPainter {
  _BoxPainter(this.scene, this.filled);

  final TodoScene scene;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    final spec = MarkSpec(
      sigil: 'task',
      state: filled ? 'done' : 'open',
      color: scene.theme.ink,
      theme: scene.theme,
      read: scene.tunable,
    );
    final box = Offset.zero & size;
    canvas.drawPath(spec.path(box.deflate(spec.strokeWidth)), spec.stroke());
    if (filled) canvas.drawPath(spec.path(box.deflate(size.width / 4)), spec.fill());
  }

  @override
  bool shouldRepaint(covariant _BoxPainter old) => old.filled != filled;
}
