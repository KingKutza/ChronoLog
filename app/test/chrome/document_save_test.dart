// THE VISIBLE SAVE (ISSUES 8.31, evening): "Also still no save button."
//
// The ruled shape is a DOCUMENT-level control: "the document bar carries a save
// action with dirty state visible (saves are updates, never overwrites)". The
// card-level Save / Apply / Discard is a different ruling and a different spec.
//
// Booted, not assembled: `Workspace.open` is what `main` runs, so what these
// cases look at is the bar a person is actually looking at.

import 'package:chronolog/app.dart';
import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/host/file_picker.dart';
import 'package:chronolog/store/document_store.dart';
import 'package:chronolog/core/records.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../store/harness.dart';

/// A control that SAYS what it is, read off the widget tree rather than off an
/// enabled semantics tree: what a person hears is what the widget declares.
Finder saying(String label) =>
    find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == label);

const Size _surface = Size(1600, 1000);
const String _root = 'C:memory';

Future<Workspace> boot(WidgetTester tester) async {
  tester.view.physicalSize = _surface;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final workspace = await Workspace.open(
    dataRoot: _root,
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
  return workspace;
}

void main() {
  testWidgets('the document bar carries a save control a person can reach', (tester) async {
    await boot(tester);
    expect(
      saying('Save'),
      findsWidgets,
      reason:
          'ISSUES (8.31, evening): "Also still no save button" — the document bar '
          'carries a save action.',
    );
  });

  // DISCOVERABILITY IS THE DEFECT (ISSUES 8.31, evening): the control existed
  // since 8/28 as a bare glyph whose only words lived in a tooltip, and Don
  // read that as no save button at all. A control nobody can find is a control
  // nobody has, so the word itself has to be ON the bar -- not in a tooltip, not
  // in a semantics label, but drawn.
  testWidgets('the save control shows its word, not only its glyph', (tester) async {
    await boot(tester);
    expect(
      find.text('Save'),
      findsWidgets,
      reason:
          'ISSUES (8.31, evening, Don live): "Also still no save button" — the control '
          'is a bare glyph and says nothing on the bar.',
    );
  });

  testWidgets('the dirty state is legible ON the bar, not only on hover', (tester) async {
    final workspace = await boot(tester);
    workspace.editor.transaction(
      'Name it',
      (d) => d.put(
        'events',
        'event:one',
        Event(id: 'event:one', traits: const ['event'], payload: const {'title': 'Lunch'}),
      ),
    );
    await tester.pump();
    expect(
      find.textContaining('unsaved'),
      findsWidgets,
      reason:
          'ISSUES (8.31): the save state is the bar\'s claim, and a claim behind a '
          'hover is a claim nobody reads.',
    );
  });

  testWidgets('the save state is stated in words, not by a colour alone', (tester) async {
    final workspace = await boot(tester);
    // Whatever the state is at boot, the bar SAYS it: the colour is the glance,
    // the words are the claim.
    expect(
      const ['Saved.', 'Unsaved changes.', 'Saving…', 'No document is open.']
          .where((said) => saying(said).evaluate().isNotEmpty),
      isNotEmpty,
      reason: 'the save lamp states its condition in words',
    );
    // Author something, and the bar must say the document is unsaved.
    workspace.editor.transaction(
      'Name it',
      (d) => d.put(
        'events',
        'event:one',
        Event(id: 'event:one', traits: const ['event'], payload: const {'title': 'Lunch'}),
      ),
    );
    await tester.pump();
    expect(
      saying('Unsaved changes.'),
      findsWidgets,
      reason:
          'ISSUES (8.31, evening): the document bar carries a save action WITH DIRTY '
          'STATE VISIBLE — an edit is not announced on the bar.',
    );
  });

  testWidgets('the save control writes the document, and the state follows', (tester) async {
    final workspace = await boot(tester);
    workspace.editor.transaction(
      'Name it',
      (d) => d.put(
        'events',
        'event:one',
        Event(id: 'event:one', traits: const ['event'], payload: const {'title': 'Lunch'}),
      ),
    );
    await tester.pump();
    await tester.tap(saying('Save').first, warnIfMissed: false);
    await tester.pump();
    expect(
      workspace.editor.store.status.state,
      anyOf(SaveState.clean, SaveState.saving),
      reason: 'the control on the bar is the one that writes',
    );
  });
}
