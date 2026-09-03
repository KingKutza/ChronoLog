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
import 'frame_menu.dart';
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
    // A CONTROL READING LIVE STATE OWNS ITS LISTENING (ISSUES 9.1: "the
    // checkboxes ripple but never check"). The view bar hands this control the
    // SAME widget instance on every rebuild, and Flutter skips a child it has
    // already been given -- so the bar's own ListenableBuilder never reached in
    // here, the lens behind the open drop moved, and the list went on saying
    // what was true when it opened. Nothing upstream can be relied on to
    // rebuild a const child; whoever reads live state subscribes to it.
    return ListenableBuilder(
      listenable: chrome.pulse,
      builder: (context, _) => _reading(context, chrome),
    );
  }

  Widget _reading(BuildContext context, Chrome chrome) {
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
    final lone = loneFrameOf(view);
    final rows = chrome.settings.value('chrome.frameRows').round().toInt();
    final shown = matches.take(rows).toList();
    final newFrame = chrome.cards['newFrame'];
    return ChronoMenu(
      label: 'Projection',
      // The drop's glyph is a READING -- which frames this view looks through --
      // so it wears its name beside it: what the value is of, in words, rather
      // than a phrase on a bar you have to already know how to read.
      name: 'Projection',
      glyph: reading.isEmpty ? 'Nothing projected' : reading,
      // CAPPED, BY A SETTING (ISSUES 9.2). Ten projected frames of long titles
      // is a sentence; unbounded on the bar it took every lens chip down to its
      // initial. The whole reading is right here in the drop, and in the
      // Expression field at the bottom of it, so nothing is lost by the cap.
      cap: chrome.px('chrome.readingWidth'),
      // THE READING NAMES A FRAME, SO THE READING CARRIES ITS VERBS (ISSUES
      // 9.2). One source for those rows, never a list spelled here. A reading
      // over several frames answers nothing: RULINGS #12 is open on what it
      // should offer, and a guess would be the ruling.
      onMenu: lone == null
          ? null
          : (at) => showChronoMenu(context, at, frameMenu(context, view, lone)),
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
          // THE EXPRESSION IS THE WHOLE STATEMENT, so it stands with the
          // reading rather than under everything the reading is made of
          // (ISSUES 9.2: "I don't see an expression field when I right-click
          // on a frame" -- it was real, and it was at the bottom of a list).
          // Statement first, then the parts it is made of.
          Padding(
            padding: EdgeInsets.all(chrome.px('chrome.pad')),
            child: projectionExpression(context, view),
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
          // EVERY LIST OF THINGS OFFERS TO MAKE THE THING (ISSUES 9.1): "the
          // moment you discover the frame you want does not exist is exactly
          // the moment you are looking at the list of frames". ONE create
          // affordance, the frames browser's own door, called through the
          // chrome's registered cards rather than spelled a second time here.
          menuTile(
            context,
            menuRow(
              newFrame == null
                  ? 'New frame — no card is registered to author one'
                  : 'New frame',
              newFrame == null ? null : () => chrome.stage.open(newFrame()),
            ),
            close: close,
          ),
          if (matches.length > shown.length)
            Padding(
              padding: EdgeInsets.all(chrome.px('chrome.pad')),
              // A truncated count is a LOWER bound and reads as one.
              child: Text('${matches.length - shown.length}+ more', style: labelStyle(context)),
            ),
        ],
      ),
    );
  }
}
