// THE ONE COLOUR PICKER.
//
// ISSUES 9.2 (Don): "Plus still no picker for specific colours. I appreciate
// easy options and hex codes, but I still need an in-app picker." Named
// swatches and a hex box are the two ENDS of choosing a colour; the middle --
// where a person actually chooses one -- was missing.
//
// THE HEX IS THE ONLY STATE. A drag reads a colour off the field, quantizes it
// to the hex it will be stored as, and writes that; the handles are then drawn
// from the hex and from nothing else. So dragging and typing are the same act
// in the strongest sense available: after either one, what the page holds is a
// string, and where the handles sit is a function of that string. A round trip
// through either loses nothing because there is nothing else to lose.
//
// MELT MEANS CENTRALIZE: every colour field in the program opens THIS widget. A
// second hue track anywhere is the failure this file exists to prevent.
//
// COLOUR REMAINS AUTHORED. Opening the picker suggests nothing, pre-fills
// nothing and infers nothing from the object it was opened on -- an unauthored
// colour opens an empty picker, and nothing is chosen until a person chooses.

import 'package:flutter/material.dart';

import '../chrome/controls.dart';
import '../lens/theme.dart';
import 'card_chrome.dart';

/// The words the hand and the spec share. Semantics labels, so a reader is told
/// the same thing the eye is shown.
const String hueSaid = 'Hue';
const String shadeSaid = 'Shade';
const String hueHandleSaid = 'Hue handle';
const String shadeHandleSaid = 'Shade handle';

class ColorPicker extends StatefulWidget {
  const ColorPicker({super.key, required this.value, required this.onChanged});

  /// What is authored now -- a hex, a colour name, or nothing at all.
  final String value;

  final void Function(String written) onChanged;

  @override
  State<ColorPicker> createState() => _ColorPickerState();
}

class _ColorPickerState extends State<ColorPicker> {
  late final TextEditingController _hex = TextEditingController(text: _normalized(widget.value));

  /// What a written value reads as in the picker's own spelling. A name the
  /// reader knows is shown as the colour it names; a word nothing reads is left
  /// exactly as written, because the field refuses rather than guesses.
  static String _normalized(String written) {
    final trimmed = written.trim();
    if (trimmed.isEmpty) return '';
    final read = parseColor(trimmed);
    return read == null ? trimmed : hexOf(read);
  }

  @override
  void didUpdateWidget(ColorPicker old) {
    super.didUpdateWidget(old);
    final next = _normalized(widget.value);
    if (widget.value != old.value && next != _hex.text) _hex.text = next;
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  /// The colour the hex says, or null where it says none.
  Color? get _read => parseColor(_hex.text);

  /// WHERE THE HANDLES SIT: a function of the hex and of nothing else.
  HSVColor get _hsv => HSVColor.fromColor(_read ?? const Color(0xff000000));

  /// One write, whichever way it was said. The text is the state, so every road
  /// sets the text and then says it.
  void _say(String written) {
    if (_hex.text != written) _hex.text = written;
    setState(() {});
    widget.onChanged(written);
  }

  void _sayColor(HSVColor picked) => _say(hexOf(picked.toColor()));

  @override
  Widget build(BuildContext context) {
    final width = cardPx(context, 'card.pickerWidth');
    final height = cardPx(context, 'card.pickerHeight');
    final track = cardPx(context, 'card.swatch');
    final grip = cardPx(context, 'card.pickerGrip');
    final hsv = _hsv;
    final authored = _read != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _field(
          said: shadeSaid,
          handleSaid: shadeHandleSaid,
          width: width,
          height: height,
          grip: grip,
          at: Offset(hsv.saturation * width, (1 - hsv.value) * height),
          shown: authored,
          paint: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.white, HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor()],
            ),
          ),
          overlay: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x00000000), Color(0xff000000)],
            ),
          ),
          onAt: (local) => _sayColor(
            HSVColor.fromAHSV(
              1,
              hsv.hue,
              (local.dx / width).clamp(0.0, 1.0),
              1 - (local.dy / height).clamp(0.0, 1.0),
            ),
          ),
        ),
        SizedBox(height: cardPx(context, 'card.gap')),
        _field(
          said: hueSaid,
          handleSaid: hueHandleSaid,
          width: width,
          height: track,
          grip: grip,
          at: Offset(hsv.hue / 360 * width, track / 2),
          shown: authored,
          paint: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xffff0000),
                Color(0xffffff00),
                Color(0xff00ff00),
                Color(0xff00ffff),
                Color(0xff0000ff),
                Color(0xffff00ff),
                Color(0xffff0000),
              ],
            ),
          ),
          onAt: (local) => _sayColor(
            HSVColor.fromAHSV(
              1,
              ((local.dx / width).clamp(0.0, 1.0)) * 360,
              authored && hsv.saturation > 0 ? hsv.saturation : 1,
              authored && hsv.value > 0 ? hsv.value : 1,
            ),
          ),
        ),
        SizedBox(height: cardPx(context, 'card.gap')),
        SizedBox(
          width: width,
          child: TextField(
            controller: _hex,
            style: dataStyle(context),
            decoration: fieldChrome(
              context,
              padding: cardPx(context, 'card.gap') / 2,
            ).copyWith(labelText: 'Hex'),
            onChanged: (text) {
              // TYPING IS CHOOSING: the same act, so it writes what was typed
              // rather than a re-spelling of it. A word that reads as no colour
              // is not chosen -- the field beside this one refuses it in words.
              setState(() {});
              if (parseColor(text) != null) widget.onChanged(text);
            },
          ),
        ),
      ],
    );
  }

  Widget _field({
    required String said,
    required String handleSaid,
    required double width,
    required double height,
    required double grip,
    required Offset at,
    required bool shown,
    required BoxDecoration paint,
    required void Function(Offset local) onAt,
    BoxDecoration? overlay,
  }) {
    final theme = ChronoTheme.of(context);
    return Semantics(
      label: said,
      container: true,
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: DecoratedBox(decoration: paint)),
            if (overlay != null) Positioned.fill(child: DecoratedBox(decoration: overlay)),
            // THE HANDLE IS A READING, never a second store of the choice.
            Positioned(
              left: at.dx - grip / 2,
              top: at.dy - grip / 2,
              child: Semantics(
                label: handleSaid,
                container: true,
                child: Container(
                  width: grip,
                  height: grip,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: shown ? theme.paper : theme.hair,
                      width: ChromeScope.of(context).px('chrome.focusRing'),
                    ),
                  ),
                ),
              ),
            ),
            // The pointer layer sits ON TOP so the handle never eats the press
            // meant for the field under it -- and it is a raw listener rather
            // than a recognizer, because choosing a colour is not a gesture the
            // arena should be able to award to somebody else halfway through a
            // drag.
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) => onAt(event.localPosition),
                onPointerMove: (event) => onAt(event.localPosition),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
