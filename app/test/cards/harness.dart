// The card spec's seam: a chrome to hang one card in, and a surface big enough
// that nothing under test is off-screen. Uncounted test support.

import 'package:chronolog/chrome/controls.dart';
import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/edit/editor.dart';
import 'package:chronolog/host/file_picker.dart';
import 'package:chronolog/lens/theme.dart';
import 'package:chronolog/session/view_state.dart';
import 'package:chronolog/stage/tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const Size cardSurface = Size(1500, 2200);

Chrome cardChrome(Editor? editor, {bool withView = true}) {
  final settings = chronologSettings();
  final views = ViewBook();
  final stage = Stage(tunable: settings.tunable, onLens: views.setLens);
  if (withView) {
    stage.open(
      TileSpec(
        id: 'view:1',
        type: 'view',
        klass: 'lens',
        title: 'View',
        build: (_) => const SizedBox.shrink(),
      ),
    );
  }
  return Chrome(settings: settings, stage: stage, views: views, editor: editor);
}

Future<void> pumpCard(WidgetTester tester, Chrome chrome, Widget card) async {
  tester.view.physicalSize = cardSurface;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Theme(
        data: themeDataFor(shipped['paper']!),
        child: ChromeScope(
          chrome: chrome,
          child: Material(child: card),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// A text field carrying exactly this text right now -- the only honest way to
/// name one field among a grid of them.
Finder fieldHolding(String text) =>
    find.byWidgetPredicate((widget) => widget is TextField && widget.controller?.text == text);

/// A text field by the hint it shows, which is the wording the author reads.
Finder fieldHinted(String hint) =>
    find.byWidgetPredicate((widget) => widget is TextField && widget.decoration?.hintText == hint);

Future<void> tapText(WidgetTester tester, String text) async {
  final finder = find.text(text).first;
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder, warnIfMissed: false);
  await tester.pumpAndSettle();
}

/// Taps a control whose text merely CONTAINS this -- a fold heading carries its
/// own disclosure glyph, so its label is never the whole string.
Future<void> tapPart(WidgetTester tester, String text) async {
  final finder = find.textContaining(text).first;
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder, warnIfMissed: false);
  await tester.pumpAndSettle();
}

/// A host whose dialog ANSWERS, so the picked-a-path road can be walked without
/// a dialog in a spec. The refusing seam covers the other road; this one covers
/// what happens after a person chooses.
class AnsweringFilePicker extends FilePicker {
  const AnsweringFilePicker(this.answer);

  final String answer;

  @override
  Future<PickedFile> open({String? initialPath, List<String> extensions = const []}) async =>
      (path: answer, refusal: '');

  @override
  Future<PickedFile> save({
    String? initialPath,
    String? suggestedName,
    List<String> extensions = const [],
  }) async => (path: answer, refusal: '');
}
