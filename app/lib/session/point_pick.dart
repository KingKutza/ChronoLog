// PICK IS A CLICK ON THE PICTURE (ISSUES 9.2, Don: "When I click Pick I should
// be able to click a point on an open lens or the minimap").
//
// Pick used to be the ladder picker alone, while the lens on screen was already
// showing the very coordinate space the field was asking about. So Pick ARMS a
// point-capture mode across every open surface -- lens tiles and the minimap
// alike -- and the mode lives HERE, on the session, because a card and a tile
// both hold the session and a mode that lived on either would be one mode per
// surface.
//
// A MODE SHOWS ITSELF AND TAKES ESCAPE (butter navigation). The pointer wears
// the ⌖ with a live readout of the coordinate under it at THAT surface'S OWN
// precision; Escape or a second Pick disarms; a click commits and disarms.
// The ladder stays as the keyboard-and-precision path, untouched: this is a
// second door onto the same field, not a replacement for the first.
//
// It knows nothing about lenses. A surface hands it what its own
// `LensPainter.pickAt` answered, so what lands is the surface's own depth and
// this file never converts a coordinate.

import 'package:flutter/foundation.dart';

import '../core/coordinate_entry.dart';

/// What one surface is showing under the pointer while the mode is armed: which
/// tile it is, the coordinate that surface named, and the text IT formatted --
/// the reading belongs to the surface, whose law it is.
typedef PickReadout = ({String surface, CoordinateEntry entry, String text});

/// THE ONE POINT-CAPTURE MODE. Armed by whoever is asking for a coordinate,
/// answered by whichever surface the person clicks.
class PointPick extends ChangeNotifier {
  void Function(CoordinateEntry entry)? _onPicked;
  PickReadout? _readout;

  /// Armed IS having somebody waiting for an answer. There is no second flag to
  /// fall out of step with the callback.
  bool get armed => _onPicked != null;

  /// What the pointer is over right now, or null when it is over nothing that
  /// can name a coordinate. Cleared when the mode ends, because a readout that
  /// outlives its mode is a surface lying about what a click will do.
  PickReadout? get readout => _readout;

  void arm({required void Function(CoordinateEntry entry) onPicked}) {
    _onPicked = onPicked;
    _readout = null;
    notifyListeners();
  }

  /// A second Pick disarms, which is what a person who changed their mind does
  /// with the same button they armed it with.
  void toggle({required void Function(CoordinateEntry entry) onPicked}) =>
      armed ? disarm() : arm(onPicked: onPicked);

  void disarm() {
    if (!armed && _readout == null) return;
    _onPicked = null;
    _readout = null;
    notifyListeners();
  }

  /// A surface says what is under the pointer. Ignored when nothing is armed,
  /// so a surface may report freely without asking first.
  void hover(PickReadout? readout) {
    if (!armed || readout == _readout) return;
    _readout = readout;
    notifyListeners();
  }

  /// A click landed. The mode ends BEFORE the answer is delivered, so a
  /// listener that opens a card or moves the eye is not doing it inside a mode
  /// that is still armed.
  void land(CoordinateEntry entry) {
    final waiting = _onPicked;
    _onPicked = null;
    _readout = null;
    notifyListeners();
    waiting?.call(entry);
  }
}

/// The glyph an armed surface wears. A mode must show itself, and this is the
/// one place the mark is spelled.
const String pickGlyph = '⌖';
