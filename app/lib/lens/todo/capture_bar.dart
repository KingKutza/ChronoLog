// The one quick-capture field, used by both roster lenses.
//
// EXACTLY ONE INPUT (survey B22): the web build grew a second capture box on the
// same list, and two inputs for one verb is two places for the grammar to
// diverge. This is the only one, and the grammar is `capture_grammar.dart`'s --
// nothing here re-parses a line.
//
// THE ASK COMES BEFORE THE WRITE (ruled, Don 2026-08-26). A `#group` that misses
// used to be reported in a toast AFTER the object was already committed. Here
// [Editor.captureQuickTodo] writes nothing; a near-miss renders its candidates
// in place, and only [Editor.confirmCapture] commits. A typo never mints a
// frame; a person confirming the name has authored one.
//
// Tab expands the row to fields IN PLACE and Escape collapses it: the expansion
// is the same capture, spelled out, and it composes back into one line so the
// grammar stays the single reader.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../edit/editor.dart';
import 'row.dart';

class CaptureBar extends StatefulWidget {
  const CaptureBar({required this.scene, this.seed = const {}, this.frame, super.key});

  final TodoScene scene;

  /// The frame a capture from here is PLACED on, where the column it heads bears
  /// time itself (ISSUES 9.2, the column-born todo). Null falls back to what the
  /// view projects, which is what a list with no column of its own means; a
  /// column that bears no time seeds a staple instead and places nothing.
  final String? frame;

  /// The facts the section or column this bar sits in already carries, by
  /// `group` / `contains` / `state`. A capture from a column head is BORN
  /// holding the column's meaning (ISSUES 8.26).
  final Map<String, String> seed;

  @override
  State<CaptureBar> createState() => _CaptureBarState();
}

class _CaptureBarState extends State<CaptureBar> {
  final TextEditingController _line = TextEditingController();
  final TextEditingController _group = TextEditingController();
  final TextEditingController _when = TextEditingController();
  final TextEditingController _note = TextEditingController();
  bool _expanded = false;
  Capture? _pending;

  TodoScene get scene => widget.scene;

  @override
  void dispose() {
    for (final controller in [_line, _group, _when, _note]) {
      controller.dispose();
    }
    super.dispose();
  }

  /// The expanded fields folded back into one line, so the grammar reads the
  /// same text whichever way it was typed.
  String get _composed => [
    _line.text.trim(),
    if (_group.text.trim().isNotEmpty) '#${_group.text.trim()}',
    if (_when.text.trim().isNotEmpty) '@${_when.text.trim()}',
    if (_note.text.trim().isNotEmpty) '> ${_note.text.trim()}',
  ].join(' ');

  void _submit() {
    final capture = scene.editor.captureQuickTodo(
      _composed,
      frameId: widget.frame ?? scene.frameId,
      todayDays: scene.nowDays,
    );
    if (capture == null) return;
    if (capture.ask != null) return setState(() => _pending = capture);
    _commit(capture);
  }

  void _commit(Capture capture, {String? groupId, bool createGroup = false}) {
    final id = scene.editor.confirmCapture(
      capture,
      groupId: groupId ?? widget.seed['group'],
      createGroup: createGroup,
    );
    if (widget.seed['contains'] case final holder?) scene.editor.setContains(holder, id, true);
    if (widget.seed['state'] case final state?) {
      scene.editor.toggleState(id, state, title: frameTitle(scene, state));
    }
    for (final controller in [_line, _group, _when, _note]) {
      controller.clear();
    }
    setState(() => _pending = null);
  }

  KeyEventResult _keys(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      setState(() => _expanded = !_expanded);
      return KeyEventResult.handled;
    }
    if (event.logicalKey != LogicalKeyboardKey.escape) return KeyEventResult.ignored;
    setState(() {
      _expanded = false;
      _pending = null;
    });
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final pad = scene.px('todo.pad');
    return Focus(
      onKeyEvent: _keys,
      child: Padding(
        padding: EdgeInsets.all(pad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: scene.px('todo.captureHeight'),
              child: TextField(
                controller: _line,
                style: scene.theme.ui.copyWith(fontSize: scene.px('todo.titleSize')),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Capture — #group @when > note',
                  hintStyle: scene.theme.ui.copyWith(
                    fontSize: scene.px('todo.metaSize'),
                    color: scene.theme.muted,
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
            ),
            if (_expanded)
              Row(
                children: [
                  _field(_group, 'group'),
                  SizedBox(width: pad),
                  _field(_when, 'when'),
                  SizedBox(width: pad),
                  _field(_note, 'note'),
                ],
              ),
            if (_pending?.ask case final ask?) _ask(ask),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController controller, String label) => Expanded(
    child: TextField(
      controller: controller,
      style: scene.theme.ui.copyWith(fontSize: scene.px('todo.metaSize')),
      decoration: InputDecoration(isDense: true, hintText: label),
      onSubmitted: (_) => _submit(),
    ),
  );

  /// The question the capture still has, answered in place: an existing group,
  /// the one the line named, or none. Nothing has been written yet.
  Widget _ask(CaptureAsk ask) => Wrap(
    spacing: scene.px('todo.gap'),
    children: [
      Text(
        'No group named "${ask.unmatched}".',
        style: scene.theme.data.copyWith(
          fontSize: scene.px('todo.metaSize'),
          color: scene.theme.primary,
        ),
      ),
      for (final candidate in ask.candidates)
        _choice(candidate.title, () => _commit(_pending!, groupId: candidate.id)),
      _choice('Create "${ask.unmatched}"', () => _commit(_pending!, createGroup: true)),
      _choice('No group', () => _commit(_pending!)),
    ],
  );

  Widget _choice(String label, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Text(
      label,
      style: scene.theme.ui.copyWith(
        fontSize: scene.px('todo.metaSize'),
        decoration: TextDecoration.underline,
      ),
    ),
  );
}
