// THE KEYBINDINGS PAGE LANDS THIS ROUND (ISSUES 9.2, Don).
//
// "A manual and a keybindings page, reachable in the same places settings are.
// The manual can wait; keybindings next round, and must allow resetting." The
// "The keyboard" sub-card exists over the `keys` area with per-key reset. It
// lacked the pointer bindings as keys, a reset-all, and conflict detection.

import 'package:chronolog/cards/settings_card.dart';
import 'package:chronolog/chrome/controls.dart';
import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/core/coordinate_entry.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/session/view_state.dart';
import 'package:chronolog/stage/tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../cards/object_harness.dart';

TileSpec _body(String id, String type, String klass, String title) => TileSpec(
  id: id,
  type: type,
  klass: klass,
  title: title,
  build: (context) => SizedBox.expand(key: ValueKey('body-$id')),
);

/// The shipped surface, with its keyboard map over it.
Future<Chrome> _surface(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final settings = chronologSettings();
  final views = ViewBook();
  final stage = Stage(tunable: settings.tunable, onLens: views.setLens);
  final chrome = Chrome(
    settings: settings,
    stage: stage,
    views: views,
    viewTile: (id) => _body(id, 'view', 'lens', 'View'),
  );
  installDefaultStage(chrome, minimap: (id) => _body(id, 'minimap', 'field', 'Minimap'));
  await tester.pumpWidget(MaterialApp(home: ChronoSurface(chrome: chrome)));
  await tester.pump();
  return chrome;
}

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

  testWidgets('a rebind takes effect at once: the map is read live, not once at build', (
    tester,
  ) async {
    // A BINDING THAT DOES NOT TAKE EFFECT IS A SETTING THAT LIES. The whole
    // settings design is "author it and the surface obeys", and the keyboard
    // map was the one place that broke: it was read out of the settings when
    // the dispatcher happened to build and never again, so a chord changed on
    // the keyboard page went on doing nothing while the OLD chord went on
    // firing -- until some unrelated widget rebuilt and it silently corrected
    // itself.
    //
    // The ordering is the whole point. Setting the binding BEFORE the surface
    // is built proves nothing: a map read once at build passes that. This sets
    // it AFTER, which is what a person at the keyboard page does.
    final chrome = await _surface(tester);
    // Escape is the case that caught it: it ends the armed pick mode, and the
    // rung that does it reads `keys.escape` like every other chord.
    chrome.views.pick.arm(onPicked: (CoordinateEntry _) {});
    expect(chrome.views.pick.armed, isTrue, reason: 'a mode is standing');

    chrome.settings.setText('keys.escape', 'ctrl+escape');
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(
      chrome.views.pick.armed,
      isTrue,
      reason:
          'the bare key is no longer bound to anything, yet it still fired -- the shortcuts map '
          'is the one the surface was built with, not the one the settings now say.',
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(
      chrome.views.pick.armed,
      isFalse,
      reason: 'the chord the setting now names is the chord the surface obeys',
    );
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
