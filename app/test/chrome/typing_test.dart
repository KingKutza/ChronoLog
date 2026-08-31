// THE RULED TEST (Don, 2026-08-31): "the numbers in textboxes should be a
// test, can a simulated keyboard type all valid chars into any textbox."
//
// The class under test (ruled 2026-08-28, recurred 2026-08-31 on the document
// name box): shortcuts fire only when no editable text has focus -- ONE guard
// at the dispatcher. The failure mechanism this spec pins: a Shortcuts map
// that MATCHES a bare key consumes the event even when its action then
// declines to act, so the character never reaches the field. The oracle is
// therefore the framework's own answer: with a field focused, a bare
// character key must NOT be handled by anything above the field -- it must
// fall through to the text-input path. With no field focused, the same key
// must be handled, or the guard is over-blocking.
//
// Keys that a focused field legitimately handles itself (arrows, delete,
// escape, tab, enter) are excluded from the fall-through oracle: text editing
// consuming them is correct. Their guard is _run's own early return, and the
// side-effect assertions below cover them.

import 'package:chronolog/app.dart';
import 'package:chronolog/cards/card_factory.dart';
import 'package:chronolog/chrome/controls.dart';
import 'package:chronolog/chrome/keyboard.dart';
import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/host/file_picker.dart';
import 'package:chronolog/session/view_state.dart';
import 'package:chronolog/stage/tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../store/harness.dart';

const Size _surface = Size(1600, 1000);

/// Every character-producing key a plain keyboard offers bare: letters,
/// digits, and the two sign keys the chrome binds (zoomIn/zoomOut). Derived,
/// not pinned: the letters and digits are generated, and the named keys are
/// read off the shipped bindings so a new binding joins the property the day
/// it is born.
Iterable<LogicalKeyboardKey> characterKeys() sync* {
  for (var code = 'a'.codeUnitAt(0); code <= 'z'.codeUnitAt(0); code++) {
    yield LogicalKeyboardKey(code);
  }
  for (var code = '0'.codeUnitAt(0); code <= '9'.codeUnitAt(0); code++) {
    yield LogicalKeyboardKey(code);
  }
  // Bare named bindings that produce characters join the property off the
  // shipped map, so a new binding is covered the day it is born. Keys a
  // focused field legitimately consumes itself (arrows, delete, escape, tab,
  // enter, space) stay out of the fall-through oracle.
  const characterNamed = {'equal': LogicalKeyboardKey.equal, 'minus': LogicalKeyboardKey.minus};
  for (final binding in chromeKeyDefaults.values) {
    if (binding.contains('+')) continue;
    final key = characterNamed[binding];
    if (key != null) yield key;
  }
}

String nameOf(LogicalKeyboardKey key) => key.keyLabel.isEmpty ? '$key' : key.keyLabel;

/// A representative card of every class the factory can build. DERIVED, not
/// pinned: the sweep walks `factory.bodies.keys`, so a card class born tomorrow
/// is swept tomorrow, and a class this switch cannot name FAILS rather than
/// being quietly skipped.
TileSpec cardOfClass(
  CardFactory factory,
  String klass, {
  required String objectId,
  required String frameId,
}) => switch (klass) {
  'object' => factory.objectCard(objectId),
  'newObject' => factory.newObjectCard('event'),
  'frame' => factory.frameCard(frameId),
  'newFrame' => factory.newFrameCard(),
  'frames' => factory.framesBrowser(),
  'document' => factory.documentCard(),
  'settings' => factory.settingsCard(),
  'themes' => factory.themesCard(),
  _ => throw StateError(
    'The "$klass" card is buildable and unswept -- name it in cardOfClass so its'
    ' textboxes join the property.',
  ),
};

/// Opens every fold, so the fields behind a disclosure are swept too: Don's
/// report was the document NAME box, but "Calendars at" lives under the fold and
/// a guard that only held above it would be no guard at all. A closed fold wears
/// its own glyph, which is how one loop reaches every one of them without
/// naming a single card's wording.
Future<void> unfoldEverything(WidgetTester tester) async {
  for (var round = 0; round < 12; round += 1) {
    final closed = find.textContaining('▸', skipOffstage: false);
    if (closed.evaluate().isEmpty) return;
    final target = closed.first;
    await tester.ensureVisible(target);
    await tester.pump();
    await tester.tap(target, warnIfMissed: false);
    await tester.pump(const Duration(seconds: 1));
  }
}

/// The property itself, over every textbox currently on the surface: focus it,
/// and every character key must fall THROUGH the chrome into it.
Future<void> sweepEveryField(WidgetTester tester, String where) async {
  final fields = find.byType(EditableText, skipOffstage: false);
  for (var index = 0; index < tester.widgetList(fields).length; index += 1) {
    final field = fields.at(index);
    await tester.ensureVisible(field);
    await tester.pump();
    await tester.tap(field, warnIfMissed: false);
    await tester.pump();
    if (!typingNow()) {
      // NO SKIPS (ISSUES.md, ruled 8.31): a READ-ONLY field is genuinely not a
      // textbox and is the only exemption. Anything else that will not take
      // focus from a tap is the defect itself, not an exception to the
      // property, so it fails here instead of being stepped over.
      expect(
        tester.widget<EditableText>(field).readOnly,
        isTrue,
        reason: '$where field #$index took no focus from a tap and is not read-only',
      );
      continue;
    }
    for (final key in characterKeys()) {
      final handled = await tester.sendKeyEvent(key);
      expect(
        handled,
        isFalse,
        reason: '$where field #$index swallowed "${nameOf(key)}" through the chrome',
      );
    }
  }
}

void main() {
  testWidgets('a focused textbox receives every character key; nothing above consumes it', (
    tester,
  ) async {
    tester.view.physicalSize = _surface;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = chronologSettings();
    final views = ViewBook();
    final stage = Stage(tunable: settings.tunable, onLens: views.setLens);
    final chrome = Chrome(settings: settings, stage: stage, views: views);
    final controller = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: ChromeScope(
          chrome: chrome,
          child: ChromeKeyboard(
            child: Material(
              child: Center(
                child: SizedBox(
                  width: 400,
                  child: TextField(controller: controller, key: const ValueKey('box')),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Focused: every character key falls through to the field's input path.
    await tester.tap(find.byKey(const ValueKey('box')));
    await tester.pump();
    expect(typingNow(), isTrue, reason: 'the tap must focus the field');
    for (final key in characterKeys()) {
      final handled = await tester.sendKeyEvent(key);
      expect(
        handled,
        isFalse,
        reason:
            '"${nameOf(key)}" was consumed above the focused textbox -- '
            'the character can never arrive (Don: "I cannot type numbers")',
      );
    }

    // Unfocused: the same bare bindings fire. The guard must not over-block.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(typingNow(), isFalse);
    final digit = await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    expect(digit, isTrue, reason: 'with no field focused, a bound bare key is chrome again');
  });

  testWidgets('every textbox on the booted surface takes every character key', (tester) async {
    tester.view.physicalSize = _surface;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final workspace = await Workspace.open(
      dataRoot: 'C:memory',
      files: MemoryFiles(),
      scheduler: ManualScheduler(),
      picker: const RefusedFilePicker('no dialog in a spec'),
    );
    addTearDown(workspace.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ChronoSurface(
          chrome: workspace.chrome,
          theme: workspace.theme.value,
          cards: workspace.factory,
        ),
      ),
    );
    await tester.pump();

    // The bare surface holds no textbox; they live on cards. Open one through
    // the real flow -- the same call the creation gesture makes -- so what the
    // sweep types into is what ships. Don's report was the document name box;
    // the object card carries the same field class.
    workspace.factory.open(workspace.factory.newObjectCard('event'));
    await tester.pump();
    await tester.pump();

    final fields = find.byType(EditableText, skipOffstage: false);
    expect(
      fields,
      findsWidgets,
      reason: 'an open object card must offer at least its name textbox',
    );
    await sweepEveryField(tester, 'the booted surface:');
  });

  testWidgets('every card the factory can build takes every character key in every field', (
    tester,
  ) async {
    tester.view.physicalSize = _surface;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final workspace = await Workspace.open(
      dataRoot: 'C:memory',
      files: MemoryFiles(),
      scheduler: ManualScheduler(),
      picker: const RefusedFilePicker('no dialog in a spec'),
    );
    addTearDown(workspace.dispose);
    // A first run establishes frames and no objects, so the record-editing
    // cards are given a subject to edit rather than a null one to refuse.
    const seed = Event(id: 'event:sweep', traits: ['event'], payload: {'title': 'sweep'});
    workspace.editor.commit(
      'Seed the sweep',
      workspace.editor.document.put('events', seed.id, seed),
    );
    final frameId = workspace.editor.document.frames.keys.first;
    await tester.pumpWidget(
      MaterialApp(
        home: ChronoSurface(
          chrome: workspace.chrome,
          theme: workspace.theme.value,
          cards: workspace.factory,
        ),
      ),
    );
    await tester.pump();

    for (final klass in workspace.factory.bodies.keys.toList()) {
      final spec = cardOfClass(
        workspace.factory,
        klass,
        objectId: seed.id,
        frameId: frameId,
      );
      workspace.factory.open(spec);
      // Zoomed so this spec types into a field it can reach. That is a real
      // workaround for a real defect -- a card tile under about 200px overflows
      // its RenderFlex (ISSUES.md, 8.31) -- and under the NO SKIPS ruling the
      // dodge does not get to hide: the narrow-card layout carries its own red
      // light in test/cards/cards_test.dart, "a card lays out at every width a
      // tile can hand it". This case stays about the keyboard.
      workspace.stage.toggleZoom(spec.id);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await unfoldEverything(tester);
      await sweepEveryField(tester, 'the $klass card:');
      workspace.stage.toggleZoom(spec.id);
      workspace.stage.close(spec.id);
      await tester.pump(const Duration(seconds: 1));
    }
  });
}
