// The projection control: which frames the focused view looks through.
//
// Projection is boolean algebra over connections (Don, 2026-08-26): plain
// selection is OR, the filter effect is authored as NOT, and AND and XOR
// compose the rest. There is no show/hide-by-state knob anywhere here --
// projecting a state frame IS the ruled filter substitute, so state frames join
// the list like any other frame. A state frame may be projected but never lead:
// the primary frame's law reads the window, and a state is not a clock.
//
// Overscale: the list is a search, never an enumeration of every frame in the
// document, and what does not fit is reported as a lower bound.

import 'package:flutter/material.dart';

import '../cards/frames_browser.dart';
import '../core/records.dart';
import '../session/view_state.dart';
import 'controls.dart';
import 'menus.dart';

bool isStateFrame(Frame frame) => frame.traits.contains('state') && frame.traits.contains('group');

class ProjectionControl extends StatefulWidget {
  const ProjectionControl({super.key});

  @override
  State<ProjectionControl> createState() => _ProjectionControlState();
}

class _ProjectionControlState extends State<ProjectionControl> {
  String _find = '';

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeScope.of(context);
    final view = chrome.focusedView;
    if (view == null) return const SizedBox.shrink();
    final frames = chrome.editor?.document.frames ?? const <String, Frame>{};
    final selected = view.selection.selected();
    final bindings = ViewState.bindingsFor(selected, (id) => frames[id]?.title ?? id);
    final reading = view.source.isNotEmpty
        ? view.source
        : ViewState.textFor(selected, view.negated, bindings);
    final needle = _find.trim().toLowerCase();
    final matches = [
      for (final frame in frames.values)
        if (!selected.contains(frame.id) &&
            (needle.isEmpty || (frame.title ?? frame.id).toLowerCase().contains(needle)))
          frame,
    ];
    final rows = chrome.settings.value('chrome.frameRows').round().toInt();
    final shown = matches.take(rows).toList();
    return ChronoMenu(
      label: 'Projection',
      glyph: reading.isEmpty ? 'Nothing projected' : reading,
      body: (context, close) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.all(chrome.px('chrome.pad')),
            child: TextField(
              onChanged: (text) => setState(() => _find = text),
              style: dataStyle(context),
              decoration: InputDecoration(isDense: true, hintText: 'Find a frame'),
            ),
          ),
          // ONE projection row, shared with the frames browser: the two
          // surfaces author the same selection and the same expression, so
          // they cannot read differently.
          for (final frame in [for (final id in selected) frames[id] ?? Frame(id: id), ...shown])
            frameProjectionRow(
              context,
              view: view,
              frame: frame,
              onOpen: chrome.openFrame == null ? null : () => chrome.openFrame!(frame.id),
            ),
          if (matches.length > shown.length)
            Padding(
              padding: EdgeInsets.all(chrome.px('chrome.pad')),
              // A truncated count is a LOWER bound and reads as one.
              child: Text('${matches.length - shown.length}+ more', style: labelStyle(context)),
            ),
          Padding(
            padding: EdgeInsets.all(chrome.px('chrome.pad')),
            child: ExpressionField(
              label: 'Expression',
              source: reading,
              // Reading it IS the validation: the one math parses it, and the
              // frame names are the bindings this view already knows.
              evaluate: (source) => ViewState(
                lensId: view.lensId,
                source: source,
              ).projection(bindings: bindings).frames.join(', '),
              onChanged: (source) => view.source = source,
            ),
          ),
        ],
      ),
    );
  }
}
