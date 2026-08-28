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

/// Which verb this press means: `pan`, `menu`, `move`, `create` or `select`.
///
/// ONE TABLE. Middle drag pans (the near-universal gesture, ISSUES 8.26); the
/// secondary button is always the app's own menu and never the platform's;
/// shift+left pans as well, which is what the old surface had. A lens that is
/// not a time surface only ever selects -- "a drag onto nothing must never mint
/// an object" is this property, not eight guard clauses. Alt forces create even
/// over an occupied span, which is how creation works THROUGH an existing block
/// (ROADMAP #7) without dragging the occupant away and back.
String pointerVerb({
  required int buttons,
  required bool shift,
  required bool alt,
  required bool onMark,
  required bool timeSurface,
}) {
  if (buttons & kMiddleMouseButton != 0) return 'pan';
  if (buttons & kSecondaryMouseButton != 0) return 'menu';
  if (shift) return 'pan';
  if (!timeSurface) return 'select';
  if (alt) return 'create';
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
