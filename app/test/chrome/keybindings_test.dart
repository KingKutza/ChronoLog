// THE KEYBINDINGS PAGE LANDS THIS ROUND (ISSUES 9.2, Don).
//
// "A manual and a keybindings page, reachable in the same places settings are.
// The manual can wait; keybindings next round, and must allow resetting." The
// "The keyboard" sub-card exists over the `keys` area with per-key reset. It
// lacks the pointer bindings as keys, a reset-all, and conflict detection.

import 'package:chronolog/chrome/shell.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('two bindings on one chord is a refusal shown beside both, never last-wins', () {
    final settings = chronologSettings();
    final chord = settings.text('keys.zoomTile');
    expect(chord, isNotEmpty);
    settings.setText('keys.closeTile', chord);
    expect(
      settings.refusals.where((line) => line.contains('keys.closeTile') && line.contains('keys.zoomTile')),
      isNotEmpty,
      reason:
          'ISSUES 9.2: closeTile and zoomTile now share "$chord" and nothing said so. A '
          'conflict is a refusal naming both keys.',
    );
  });

  test('pointer bindings are settings keys on the same page', () {
    final settings = chronologSettings();
    for (final key in const ['pointer.marquee', 'pointer.pan', 'pointer.create', 'pointer.menu']) {
      expect(
        settings.text(key),
        isNotEmpty,
        reason:
            'ISSUES 9.2: `$key` is hard-wired in `pointerVerb` (shift = pan, alt = create, '
            'right = menu) and must be a settings key beside the keyboard chords.',
      );
    }
  });

  test('the keyboard page offers Reset all', () {
    fail(
      'ISSUES 9.2: the keyboard sub-card has per-key Reset only. Add Reset all for the page, '
      'then assert every `keys.*` and `pointer.*` override is gone after it.',
    );
  });
}
