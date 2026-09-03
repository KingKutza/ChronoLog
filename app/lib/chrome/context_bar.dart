// The context bar: the focused view tile's own controls, rendered from the
// lens's declaration. There is no `if (lens == ...)` here and there never will
// be -- a lens that wants a control declares one.
//
// Law-aware throughout: an hour count is bounded by THIS frame's hours per day
// (a 23-hour day offers 23), a step is one of the lens's own span units, and
// "Today" is disabled with an honest reason on a law that maps nothing onto the
// running clock. Reset comes before Today (Don, 8.17).

import 'package:flutter/material.dart';

import '../cards/coordinate_field.dart';
import '../core/coordinate_law.dart';
import '../core/exact.dart';
import '../lens/view_tile.dart';
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
            // THE DOOR THAT TAKES A COORDINATE (ISSUES 9.2, Don: "We have no
            // clear jump-to-date option"). The bar's whole vocabulary was
            // relative steps plus one absolute destination, now -- so reaching
            // February 2200 meant holding an arrow down. This says WHERE.
            //
            // It stands wherever the view HAS a law to place a coordinate in,
            // which is derived from the projection's primary frame and not
            // declared anywhere: a lens does not opt in to being jumpable.
            if (law != null) _jump(context, tile, law),
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

/// JUMP TO A DATE: the same variable-precision coordinate field every other
/// coordinate in the program uses, over the primary frame's own law, landing at
/// THE DEPTH TYPED -- a year lands on the year, a month on the month, an instant
/// on the instant. No new parser, and no picker of three boxes.
///
/// The landing rides the view tile's own glide, which is why it reaches for
/// `jumpTo` rather than writing the focus here: a second "put the focus there"
/// beside the glide would snap, and the two would drift apart.
BarItem _jump(BuildContext c, String tile, CoordinateLaw law) {
  final chrome = ChromeScope.of(c);
  Widget door(String face) => Builder(
    builder: (c) => controlChip(
      c,
      button: true,
      hint: 'Jump to a date — type a coordinate at whatever depth you mean',
      semantics: 'Jump to a date',
      onTap: () {
        final box = c.findRenderObject() as RenderBox?;
        showChronoPanel(
          c,
          box == null ? Offset.zero : box.localToGlobal(box.size.bottomLeft(Offset.zero)),
          CoordinateField(
            law: law,
            value: law.fromDays(chrome.views.focusOf(tile)),
            onChanged: (value, _) {
              if (value == null) return;
              _goTo(chrome, tile, law.toDays(value));
            },
          ),
        );
      },
      child: Text(face, style: dataStyle(c)),
    ),
  );
  return (label: 'Jump to a date', full: door('Jump to…'), compact: door('⇥'));
}

/// GO THERE, THROUGH THE ONE DOOR. A step and a jump and Today are the same
/// verb at three destinations, so they take the same road: the view tile's own
/// glide. A bar that wrote the focus itself would be a second mechanism beside
/// the glide, and the two would drift -- Today gliding while the arrow beside
/// it snapped is exactly that, and it is what this closes.
///
/// With no view tile mounted there is nothing to animate, so the focus is
/// simply where it is set. That is the ABSENCE of a surface, not a second way
/// of moving one.
void _goTo(Chrome chrome, String tile, Rational days) {
  final controller = viewTileControllers[tile];
  controller == null ? chrome.views.setFocus(tile, days) : controller.jumpTo(days);
}

BarItem _step(BuildContext c, String glyph, String label, Rational by, String tile) {
  final chrome = ChromeScope.of(c);
  return barAction(
    c,
    label,
    glyph: glyph,
    onTap: () => _goTo(chrome, tile, chrome.views.focusOf(tile) + by),
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
