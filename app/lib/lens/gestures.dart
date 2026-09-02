// THE ONE POINTER TABLE, and the arithmetic behind it.
//
// The web build had no pointer vocabulary at all: middle-drag drag-created
// because nothing inspected `event.button`, right-click got the browser's menu
// because nothing listened for `contextmenu`, and every drag path re-derived its
// own snap. Three field reports (ISSUES 8.26) are one defect -- the buttons were
// unowned. So the mapping from button and modifier to verb lives HERE, once, and
// every time lens reads the same table.
//
// A verb is a string, not an enum: nothing here encodes a right way, and an
// unfamiliar verb is data a later surface may learn rather than a crash.

import 'package:flutter/gestures.dart';

import '../core/exact.dart';
import 'law_context.dart';

/// Every number the pointer surface moves by, as a named setting whose shipped
/// default is an expression in the one math. Motion (the ratified 220ms
/// cubic-bezier(.25,.9,.25,1)) is NOT restated here: it is one curve for the
/// whole app and lives in `lensTunableDefaults` as `motion.duration` and
/// `motion.curve.*`, which the spin and the jump read directly.
const Map<String, String> pointerTunableDefaults = {
  // A drag is a drag once it has travelled this far; below it, the gesture is
  // still a click, so a click with a shaky hand still selects.
  'pointer.dragThreshold': '5',
  'pointer.doubleClickMillis': '280',
  // One wheel notch, in the pixels a platform reports for it.
  'pointer.wheelNotch': '90',
  // Ctrl+wheel: what one notch multiplies the visible span by.
  'pointer.zoomStep': '1.25',
  // WHICH WAY IS IN (ISSUES 9.1, "scroll-wheel zoom is reversed: wheel up zooms
  // out"). Butter is muscle memory from other apps, and every map and browser
  // the hand has learned zooms IN on wheel-up. The direction is a SIGNED
  // FACTOR here rather than a minus sign buried in the handler: ship it
  // positive for wheel-up-zooms-in, author it negative to have the old way
  // back, and every surface that zooms reads this one key.
  'pointer.zoomDirection': '1',
  // A plain notch on a coarse surface: this share of the visible span.
  'pointer.panStepFraction': '1/18',
  // The ghost.
  'pointer.ghostOpacity': '0.28',
  'pointer.ghostStroke': '1.5',
  'pointer.ghostCorner': '3',
  'pointer.ghostMinimum': '6',
  'pointer.ghostLabelGap': '6',
  'pointer.ghostLabelPad': '3',
  'pointer.ghostLabelSize': '11',
  // The minimap window box: how near its edge the pointer must land to GRAB the
  // box rather than jump the focus to where it clicked, as a multiple of the
  // box's own half-width.
  'pointer.minimapGrab': '1',
  // A stated refusal sits in from the edge of the surface it explains.
  'pointer.refusalPad': '12',
};

/// THE POINTER BINDINGS ARE SETTINGS, BESIDE THE KEYBOARD CHORDS (ISSUES 9.2,
/// Don: "a manual and a keybindings page... the keybindings page lands next
/// round and must allow resetting").
///
/// They were hard-wired in `pointerVerb` -- shift meant pan, alt meant create,
/// right meant menu, and none of the three could be moved without a recompile,
/// which is the same defect the keyboard had before every chord became a key.
/// TEXT settings, like the keyboard's: a chord is not arithmetic, and reading
/// `pointer.pan` as algebra would be a category error.
///
/// THE GRAMMAR, and it is deliberately tiny: modifiers (`ctrl`, `shift`, `alt`,
/// `meta`) and one button (`left`, `middle`, `right`), joined by `+`, with `|`
/// between whole ALTERNATIVES -- pan is the middle button OR shift and the
/// left, and it always was. A `drag` term says the binding wants motion rather
/// than a press. An EMPTY setting is a binding turned off, not a binding that
/// matches everything.
const Map<String, String> pointerBindingDefaults = {
  'pointer.pan': 'middle | shift+left',
  'pointer.menu': 'right',
  'pointer.create': 'alt+left',
  // RIGHT-DRAG, on Don's own reading of what the modifiers already cost:
  // "shift is taken; right is free only if the menu moves to
  // release-without-movement, which is also the ordinary desktop convention"
  // (ISSUES 9.2, the marquee binding). Declared here so the page and the file
  // can author it; the verb that reads it lands with multi-select.
  'pointer.marquee': 'right+drag',
  'pointer.toggleSelect': 'ctrl+left',
};

/// The buttons, by the names a person writes them with.
const Map<String, int> _buttons = {
  'left': kPrimaryMouseButton,
  'middle': kMiddleMouseButton,
  'right': kSecondaryMouseButton,
};

/// Does this press satisfy one pointer chord?
///
/// Every named modifier must be held and the named button must be down. A
/// modifier the chord does not name is not forbidden -- precedence between two
/// chords that both match is the ORDER they are asked in, stated once in
/// [pointerVerb], rather than a rule about which chord is more specific.
bool pointerChordMatches(
  String binding, {
  required int buttons,
  required bool shift,
  required bool alt,
  bool control = false,
  bool meta = false,
  bool drag = false,
}) {
  for (final alternative in binding.toLowerCase().split('|')) {
    final parts = alternative.split('+').map((part) => part.trim()).where((p) => p.isNotEmpty);
    if (parts.isEmpty) continue;
    var button = 0;
    var wants = true;
    var wantsDrag = false;
    for (final part in parts) {
      switch (part) {
        case 'ctrl':
          wants &= control;
        case 'shift':
          wants &= shift;
        case 'alt':
          wants &= alt;
        case 'meta':
          wants &= meta;
        case 'drag':
          wantsDrag = true;
        default:
          button |= _buttons[part] ?? 0;
      }
    }
    if (wantsDrag && !drag) continue;
    // A chord naming no button at all names no press: an unreadable line turns
    // the binding off rather than firing on everything.
    if (button == 0 || buttons & button == 0) continue;
    if (wants) return true;
  }
  return false;
}

/// Which verb this press means: `pan`, `menu`, `move`, `create` or `select`.
///
/// ONE TABLE, and the table is now the SETTINGS. Middle drag pans (the
/// near-universal gesture, ISSUES 8.26); the secondary button is the app's own
/// menu and never the platform's; shift+left pans as well, which is what the
/// old surface had -- all three read out of [pointerBindingDefaults] rather
/// than out of these branches. A lens that is not a time surface only ever
/// selects -- "a drag onto nothing must never mint an object" is this property,
/// not eight guard clauses. Create forces itself even over an occupied span,
/// which is how creation works THROUGH an existing block (ROADMAP #7) without
/// dragging the occupant away and back.
///
/// [bindings] is the live settings reader; absent, the shipped chords answer,
/// so a surface with no settings in reach still has the ratified vocabulary.
String pointerVerb({
  required int buttons,
  required bool shift,
  required bool alt,
  required bool onMark,
  required bool timeSurface,
  bool control = false,
  String Function(String key)? bindings,
}) {
  bool bound(String key) => pointerChordMatches(
    bindings?.call(key) ?? pointerBindingDefaults[key] ?? '',
    buttons: buttons,
    shift: shift,
    alt: alt,
    control: control,
  );
  if (bound('pointer.pan')) return 'pan';
  if (bound('pointer.menu')) return 'menu';
  if (!timeSurface) return 'select';
  if (bound('pointer.create')) return 'create';
  return onMark ? 'move' : 'create';
}

/// A wheel accumulator that CARRIES ITS REMAINDER. A trackpad reports a stream
/// of small deltas; discarding what does not fill a notch is how a gesture goes
/// dead on precise hardware.
class Notches {
  double _carry = 0;

  int take(double delta, double notch) {
    if (notch <= 0) return 0;
    _carry += delta;
    final steps = (_carry / notch).truncate();
    _carry -= steps * notch;
    return steps;
  }

  void reset() => _carry = 0;
}

/// The snap grain in days for a lens that declares a grain in minutes, and the
/// law's own whole day for one that does not -- which IS the ruling that a
/// non-Intimate drop rounds to whole days, stated as a property of the lens's
/// declaration rather than as a test of its name.
Rational grainDays(LawContext law, Rational? grainMinutes) =>
    grainMinutes == null ? law.dayDays : law.daysOfMinute(grainMinutes);

/// The drop, snapped. A grain of zero snaps to nothing: the drop lands EXACTLY
/// where the pointer was, which is the other half of the ISSUES 8.26 ruling --
/// either snap visibly or land exactly where clicked.
Rational snapDays(Rational days, Rational grain) =>
    grain <= Rational.zero ? days : Rational((days / grain).round()) * grain;
