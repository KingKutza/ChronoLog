// THE KEYBINDINGS PAGE LANDS THIS ROUND (ISSUES 9.2, Don).
//
// "A manual and a keybindings page, reachable in the same places settings are.
// The manual can wait; keybindings next round, and must allow resetting." The
// "The keyboard" sub-card exists over the `keys` area with per-key reset. It
// lacked the pointer bindings as keys, a reset-all, and conflict detection.

import 'package:chronolog/cards/settings_card.dart';
import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/core/document.dart';
import 'package:flutter_test/flutter_test.dart';

import '../cards/object_harness.dart';

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

  testWidgets('the keyboard page offers Reset all, and it puts every chord back', (tester) async {
    // "A RESET ALL for the page" -- Don: the page "must allow RESETTING
    // bindings". One act, one announcement: after it, no `keys.*` and no
    // `pointer.*` override survives, and the shipped chords read again. The
    // reset is asked of the page as rendered, not of the store method behind it.
    final bench = (await tester.runAsync(() => openCards(createEmptyWorkspaceDocument())))!;
    final settings = bench.settings;
    final shipped = {
      for (final key in ['keys.undo', 'keys.closeTile', 'pointer.pan', 'pointer.menu']) key: settings.text(key),
    };
    settings.setText('keys.undo', 'ctrl+alt+q');
    settings.setText('keys.closeTile', 'ctrl+alt+w');
    settings.setText('pointer.pan', 'middle');
    settings.setText('pointer.menu', 'right+ctrl');
    final authored = settings.toJson().keys.where(
      (key) => key.startsWith('keys.') || key.startsWith('pointer.'),
    );
    expect(authored, hasLength(4), reason: 'four bindings are written differently');
    // The sub-card the way a tile hosts it: inside the CardHost, with the bounded
    // height its shell asks for.
    await pumpHosted(tester, bench, const SettingsCard(area: 'keys'), klass: 'settings', shell: true);
    // The action wears its glyph and carries its words as the chip's semantics,
    // so the row is found by what it SAYS, wherever the words sit.
    final reset = find.bySemanticsLabel(RegExp('Reset all', caseSensitive: false));
    expect(
      reset,
      findsWidgets,
      reason: 'ISSUES 9.2: the keyboard sub-card had per-key Reset only; the page owes a Reset all',
    );
    await tester.ensureVisible(reset.first);
    await tester.tap(reset.first, warnIfMissed: false);
    await tester.pumpAndSettle();
    final left = settings.toJson().keys.where(
      (key) => key.startsWith('keys.') || key.startsWith('pointer.'),
    );
    expect(
      left,
      isEmpty,
      reason: 'ISSUES 9.2: after Reset all these bindings are still written differently: $left',
    );
    for (final entry in shipped.entries) {
      expect(settings.text(entry.key), equals(entry.value), reason: '${entry.key} reads shipped again');
    }
  });
}
