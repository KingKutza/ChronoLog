// WHAT THE CHROME OFFERS THE HAND AND THE READER (ISSUES 9.1).
//
//   "Found by writing the lights: the chrome's chips tap through bare
//   GestureDetectors, invisible to a11y/finders — flagged for the chrome zone."
//
//   "Sub-cards are also launched from right-click context menus at the relevant
//   parts of the app — the lens's own menu opens that lens's settings card, the
//   stage's opens the stage's."
//
// Both are claims about the class rather than about one control: EVERY chip the
// chrome draws is a button that says so, and EVERY chrome surface right-clicks
// to the settings that govern it -- or says in words that no door is registered.

import 'package:chronolog/chrome/controls.dart';
import 'package:chronolog/chrome/document_bar.dart';
import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/session/lens_catalog.dart';
import 'package:chronolog/session/view_state.dart';
import 'package:chronolog/stage/tile.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const Size _surface = Size(1600, 1000);

TileSpec _body(String id, String type, String klass, String title) => TileSpec(
  id: id,
  type: type,
  klass: klass,
  title: title,
  build: (context) => SizedBox.expand(key: ValueKey('body-$id')),
);

Future<Chrome> _pump(WidgetTester tester, {List<String>? opened}) async {
  tester.view.physicalSize = _surface;
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
    openSettings: opened?.add,
  );
  installDefaultStage(chrome, minimap: (id) => _body(id, 'minimap', 'field', 'Minimap'));
  await tester.pumpWidget(MaterialApp(home: ChronoSurface(chrome: chrome)));
  await tester.pumpAndSettle();
  return chrome;
}

Future<void> _rightClick(WidgetTester tester, Offset at) async {
  final gesture = await tester.startGesture(at, buttons: kSecondaryButton);
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('every lens chip is a button, with its own words on it', (tester) async {
    final handle = tester.ensureSemantics();
    final chrome = await _pump(tester);
    // The whole visible run, not one chip somebody picked: a chip class that is
    // invisible to a reader is invisible for all of them.
    for (final id in chrome.views.visibleLenses) {
      final title = lensCatalog[id]!.title;
      final chip = find.text(title);
      if (chip.evaluate().isEmpty) continue;
      final node = tester.getSemantics(chip.first);
      expect(
        node.flagsCollection.isButton,
        isTrue,
        reason:
            'ISSUES (9.1): "the chrome\'s chips tap through bare GestureDetectors, '
            'invisible to a11y/finders" — the $title chip is not a button to anything '
            'looking.',
      );
      expect(node.label, contains(title), reason: 'and it carries its own words');
    }
    handle.dispose();
  });

  testWidgets('a chip whose mark is a glyph is told in words what it does', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    // A glyph is not a word: the node says the verb instead of spelling the
    // mark, which is the half a tooltip was never going to cover.
    for (final said in const ['Undo', 'Redo', 'Forward a window', 'New view']) {
      expect(
        find.bySemanticsLabel(said),
        findsWidgets,
        reason:
            'ISSUES (9.1): a glyph control read as its own mark — "$said" is nowhere in '
            'the semantics of the rendered chrome.',
      );
    }
    handle.dispose();
  });

  testWidgets('a bar right-clicks to the settings that govern the bars', (tester) async {
    final opened = <String>[];
    await _pump(tester, opened: opened);
    // The bar's own surface, between its controls: a chip answers first, and
    // this is the ground around them.
    await _rightClick(tester, tester.getRect(find.byType(DocumentBar)).center);
    expect(
      find.textContaining('settings'),
      findsWidgets,
      reason:
          'ISSUES (9.1, Don\'s ruling on the settings surface): sub-cards are launched '
          'from right-click menus at the relevant parts of the app.',
    );
    await tester.tap(find.textContaining('The bars').first);
    await tester.pumpAndSettle();
    expect(opened, contains('chrome'), reason: 'the bar opened the bars\' own settings');
  });

  testWidgets('a lens chip right-clicks to that lens\'s settings', (tester) async {
    final opened = <String>[];
    final chrome = await _pump(tester, opened: opened);
    final id = chrome.views.visibleLenses.first;
    final spec = lensCatalog[id]!;
    await _rightClick(tester, tester.getCenter(find.text(spec.title).first));
    await tester.tap(find.textContaining('${spec.title} — settings').first);
    await tester.pumpAndSettle();
    expect(
      opened,
      contains(id),
      reason: 'ISSUES (9.1): "the lens\'s own menu opens that lens\'s settings card"',
    );
  });

  testWidgets('the stage right-clicks to the stage\'s settings, off its own handle', (
    tester,
  ) async {
    final opened = <String>[];
    final chrome = await _pump(tester, opened: opened);
    final minimap = chrome.stage.leaves.firstWhere((leaf) => leaf.type == 'minimap');
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    addTearDown(pointer.removePointer);
    // The leading band is where the pointer finds a lone tile's handle (ruled
    // 9.1), so it is where the stage's own menu is reached from.
    final body = tester.getRect(find.byKey(ValueKey('body-${minimap.id}')));
    await pointer.moveTo(Offset(body.left + chrome.px('stage.handleBand') / 2, body.center.dy));
    await tester.pumpAndSettle();
    await _rightClick(tester, tester.getCenter(find.text('⋮')));
    await tester.tap(find.textContaining('The stage — settings').first);
    await tester.pumpAndSettle();
    expect(
      opened,
      contains('stage'),
      reason: 'ISSUES (9.1): "the stage\'s [menu] opens the stage\'s [settings card]"',
    );
  });

  testWidgets('with no settings door registered the menu says so', (tester) async {
    await _pump(tester);
    await _rightClick(tester, tester.getRect(find.byType(DocumentBar)).center);
    expect(
      find.textContaining('no settings card is registered'),
      findsWidgets,
      reason: 'a door that is not there is refused in words, never a row that does nothing',
    );
  });
}
