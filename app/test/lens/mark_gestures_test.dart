// THE PATH BACK TO A CARD, on a lens whose marks are widgets.
//
// Don, 2026-08-31: "Clicking, and double clicking on an event don't open its
// card, also right clicking does not include an open card option. I see no clear
// way to open an events card back up." The ruled class is every mark on every
// lens, so the roster and graph surfaces answer for it too: single click
// selects, double click opens, the menu always carries Open.
//
// The claims are about the DISPATCH, so the tile here records what it was asked
// to do rather than opening anything: a card opener is the whole of what the
// lens layer knows about cards.

import 'package:chronolog/chrome/menus.dart';
import 'package:chronolog/edit/editor.dart';
import 'package:chronolog/lens/context_menu.dart';
import 'package:chronolog/lens/mark_gestures.dart';
import 'package:chronolog/lens/theme.dart';
import 'package:chronolog/lens/view_tile.dart';
import 'package:chronolog/stage/tile.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A controller that answers only what these specs ask of it, and remembers
/// every request. Uncounted test support.
class RecordingTile implements ViewTileController {
  final List<String> selected = [], opened = [];

  @override
  final Stage stage = Stage();

  @override
  CardOpener? get objectCard => (id) {
    opened.add('object:$id');
    return _card(id);
  };

  @override
  CardOpener? get frameCard => (id) {
    opened.add('frame:$id');
    return _card(id);
  };

  TileSpec _card(String id) => TileSpec(
    id: 'card:$id',
    type: 'card',
    klass: 'card',
    title: 'Card',
    build: (_) => const SizedBox.shrink(),
  );

  @override
  String get tileId => 'tile:roster';

  @override
  String? get primaryFrame => 'calendar:a';

  @override
  void selectObject(String objectId) => selected.add(objectId);

  @override
  void select(String? identity) => selected.add('$identity');

  @override
  void openObject(String objectId) {
    final open = objectCard;
    if (open != null) stage.open(open(objectId));
  }

  @override
  Editor get editor => throw UnimplementedError('no spec here writes');

  @override
  void noSuchMethod(Invocation invocation) {}
}

Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: themeDataFor(shipped['paper']!),
    home: Scaffold(body: Center(child: child)),
  ),
);

/// Two clicks close enough together to be one double-click, on the pointer's own
/// clock: the second has to land inside the window, and the surface has to be
/// given the frame in which it lands.
Future<void> twice(WidgetTester tester, Finder target) async {
  await tester.tap(target);
  await tester.pump(kDoubleTapMinTime);
  await tester.tap(target);
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('a widget mark selects on one click and opens its card on two', (tester) async {
    final tile = RecordingTile();
    await pump(
      tester,
      MarkGestures(
        tile: tile,
        objectId: 'event:1',
        child: const SizedBox(width: 120, height: 30, child: Text('Lunch')),
      ),
    );
    await tester.tap(find.text('Lunch'));
    await tester.pump(const Duration(seconds: 1));
    expect(tile.selected, ['event:1']);
    expect(tile.opened, isEmpty, reason: 'one click selects, it does not open');
    await twice(tester, find.text('Lunch'));
    expect(tile.opened, ['object:event:1']);
  });

  testWidgets('a widget mark that names a frame opens the FRAME card', (tester) async {
    final tile = RecordingTile();
    await pump(
      tester,
      MarkGestures(
        tile: tile,
        frameId: 'calendar:a',
        child: const SizedBox(width: 120, height: 30, child: Text('Calendar')),
      ),
    );
    await twice(tester, find.text('Calendar'));
    expect(tile.opened, ['frame:calendar:a']);
  });

  test('the menu carries Open for whatever is under the pointer, and none where nothing is', () {
    final tile = RecordingTile();
    MenuRow? openIn(List<MenuRow> rows) => rows.where((row) => row.label == 'Open').firstOrNull;

    // An object named by id, as a roster row or a graph node names one.
    final onObject = viewMenuRows(tile, objectId: 'event:7');
    expect(openIn(onObject), isNotNull);
    openIn(onObject)!.onTap!();
    expect(tile.opened, ['object:event:7']);

    // A frame node opens the card the record actually has.
    final onFrame = viewMenuRows(tile, frameId: 'frame:work');
    expect(openIn(onFrame), isNotNull);
    openIn(onFrame)!.onTap!();
    expect(tile.opened.last, 'frame:frame:work');

    // And on bare surface there is nothing to open, so nothing claims there is.
    expect(openIn(viewMenuRows(tile)), isNull);
  });
}
