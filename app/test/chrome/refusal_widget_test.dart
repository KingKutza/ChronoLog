// A REFUSAL IS A THING YOU CAN TOUCH (ISSUES 9.2, Don).
//
// "Double-clicking an error message should copy it to the clipboard; right now
// I have no way to interact with them." Lens-top refusals are painted text with
// no hit region; card refusals are plain Texts. One class: every refusal is one
// widget with the same verbs -- click selects, double-click copies (text plus
// source), right-click offers Copy / Copy all / Open what it is about / Dismiss;
// hover shows the full text when a banner truncated it.

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every refusal surface answers a double-click with a clipboard write of its text', () {
    // WORK ITEM (ISSUES 9.2): no `Refusal` widget or mark exists; `paintRefusals`
    // is a TextPainter and `cardNote(refusal: true)` a Text. When the one class
    // exists this test pumps a lens with a starved series and a card with a
    // refusal note, double-taps each, and asserts `Clipboard` (flutter/services,
    // not a plugin) received the refusal's text and source.
    fail(
      'ISSUES 9.2: refusals are inert text on every surface. Make them one interactive class '
      '(select, copy on double-click, context menu, hover for the full text), then assert here.',
    );
  });
}
