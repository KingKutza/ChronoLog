// The context bar: the focused view tile's own controls, rendered from the
// lens's declaration. There is no `if (lens == ...)` here and there never will
// be -- a lens that wants a control declares one.
//
// Law-aware throughout: an hour count is bounded by THIS frame's hours per day
// (a 23-hour day offers 23), a step is one of the lens's own span units, and
// "Today" is disabled with an honest reason on a law that maps nothing onto the
// running clock. Reset comes before Today (Don, 8.17).

import 'package:flutter/material.dart';

import '../core/coordinate_law.dart';
import '../core/exact.dart';
import '../session/lens_catalog.dart';
import '../session/view_state.dart';
import 'controls.dart';
import 'menus.dart';

class ContextBar extends StatelessWidget {
  const ContextBar({super.key});

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeScope.of(context);
    return ListenableBuilder(
      listenable: chrome.pulse,
      builder: (context, _) {
        final tile = chrome.stage.focusedViewTile;
        final view = chrome.focusedView;
        if (tile == null || view == null) {
          final said = Text('No view tile is focused.', style: labelStyle(context));
          return barShell(context, [barItem('No view tile is focused.', said)]);
        }
        final law = _law(chrome, view);
        final unit = law?.meanUnitDays(view.spec.spanUnit) ?? Rational.one;
        final window = law == null ? unit : view.spanDays(law, chrome.settings);
        final clock = law?.mapsToClock() ?? false;
        // A control nobody has claimed is NOT RENDERED (ruled 2026-08-28): a
        // disabled button carrying an apology is chaff on a bar that is one
        // instrument.
        final shown = [
          for (final control in view.spec.controls)
            if (control.kind != 'action' || chrome.onAction != null) control,
        ];
        final folded = [
          for (final control in shown)
            if (!control.primary) control,
        ];
        return barShell(
          context,
          [
            for (final control in shown)
              if (control.primary) _control(context, control, view, law, tile),
            if (folded.isNotEmpty)
              barItem(
                '${view.spec.title} options',
                ChronoMenu(
                  label: '${view.spec.title} options',
                  glyph: 'Options',
                  body: (context, close) => Padding(
                    padding: EdgeInsets.all(chrome.px('chrome.pad')),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final control in folded)
                          Padding(
                            padding: EdgeInsets.only(bottom: chrome.px('chrome.gap')),
                            child: _control(context, control, view, law, tile).full,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
          trailing: [
            _step(context, '«', 'Back a window', -window, tile),
            _step(context, '‹', 'Back one ${view.spec.spanUnit}', -unit, tile),
            _step(context, '›', 'Forward one ${view.spec.spanUnit}', unit, tile),
            _step(context, '»', 'Forward a window', window, tile),
            barAction(
              context,
              'Reset ${view.spec.title}',
              glyph: '↺',
              hint: 'Put ${view.spec.title} back to its shipped settings',
              onTap: chrome.onAction == null
                  ? () {
                      view.resetView();
                      chrome.views.touch();
                    }
                  : () => chrome.onAction!(tile, 'reset'),
            ),
            barAction(
              context,
              'Today',
              glyph: '◎',
              hint: clock
                  ? 'Centre ${view.spec.title} on now'
                  : 'This frame has no now-mapping, so there is no today to centre on.',
              // ONE derivation of the verb: the view tile's own `jumpToNow`,
              // which glides rather than snapping and refuses on a law with no
              // clock. A second "set the focus to now" here would be the same
              // verb spelled twice, and the two would drift.
              onTap: clock && chrome.onAction != null
                  ? () => chrome.onAction!(tile, 'today')
                  : null,
            ),
          ],
        );
      },
    );
  }
}

CoordinateLaw? _law(Chrome chrome, ViewState view) {
  final primary = view.projection().primaryFrame;
  final engine = chrome.editor?.engine;
  if (primary == null || engine == null) return null;
  try {
    return engine.lawOf(primary);
  } on Object {
    // A broken frame must not blank the bar; the lens says what is wrong.
    return null;
  }
}

BarItem _step(BuildContext c, String glyph, String label, Rational by, String tile) {
  final chrome = ChromeScope.of(c);
  return barAction(
    c,
    label,
    glyph: glyph,
    onTap: () => chrome.views.setFocus(tile, chrome.views.focusOf(tile) + by),
  );
}

/// One declared control, rendered. The only thing this knows about a lens is
/// what the lens said about itself.
BarItem _control(
  BuildContext c,
  ControlSpec spec,
  ViewState view,
  CoordinateLaw? law,
  String tile,
) {
  final chrome = ChromeScope.of(c);
  void changed(Object? value) {
    view.write(spec.key, value);
    chrome.views.touch();
  }

  // A number bounded by its unit: how many of that unit fill one day of THIS
  // law. A unit at or above the day has no such ceiling.
  final per = spec.unit == null || law == null ? null : law.unitsPer(spec.unit!, 'day');
  if (spec.kind == 'action') {
    // An action narrows to its own initial; a number or a chooser cannot narrow
    // without becoming a different control, so it folds whole instead.
    return barAction(
      c,
      spec.label,
      hint: spec.hint ?? spec.label,
      onTap: () => chrome.onAction?.call(tile, spec.key),
    );
  }
  return barItem(spec.label, switch (spec.kind) {
    'toggle' => namedToggle(c, spec.label, view.flag(spec.key, chrome.settings), changed),
    'choice' => namedChoice(
      c,
      spec.label,
      view.choice(spec.key, chrome.settings),
      spec.options,
      changed,
    ),
    'number' => namedNumber(
      c,
      spec.label,
      view.number(spec.key, chrome.settings),
      (value) => changed(value.toJson()),
      min: Rational.zero,
      max: per != null && per > Rational.one ? per : null,
      hint: spec.hint,
    ),
    _ => ExpressionField(
      label: spec.label,
      source: '${view.read(spec.key, chrome.settings) ?? ''}',
      onChanged: changed,
    ),
  });
}
