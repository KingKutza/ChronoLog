// A DRAG BAR MOVES THE TWO WINDOWS IT SITS BETWEEN (ISSUES 9.1, Don's ruling on
// dividers).
//
//   "The minimap's horizontal seam linked to the lens card's horizontal seam and
//   no dragging unstuck them until the minimap was moved and every top bar
//   replaced... 99% of the time a drag bar moves ONLY the two windows it sits
//   between, never aligning across the page; seam-wide alignment becomes an
//   explicit mode -- a ctrl/key chord that VIEWS the drag bars and lets you lock
//   or unlock an alignment -- so linked seams are something you author and can
//   see, not something proximity infers and nothing displays."
//
// The arrangement below is the reported one: two rows, each cut in two, with
// the cuts landing on the same pixel line. Nothing about that coincidence may
// link them.

import 'package:chronolog/chrome/controls.dart';
import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/session/view_state.dart';
import 'package:chronolog/stage/layout_tree.dart';
import 'package:chronolog/stage/tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const Size _surface = Size(1200, 800);

TileSpec _body(String id) => TileSpec(
  id: id,
  type: 'view',
  klass: 'lens',
  title: id,
  build: (context) => SizedBox.expand(key: ValueKey('body-$id')),
);

Branch _row(String id, String left, String right) => Branch(
  id,
  mode: 'split',
  axis: 'row',
  ratios: [Rational.fromInt(1, 2), Rational.fromInt(1, 2)],
  children: [
    TileLeaf(left, type: 'view', klass: 'lens', title: left),
    TileLeaf(right, type: 'view', klass: 'lens', title: right),
  ],
);

/// Two rows, one above the other, each cut down the middle: the two vertical
/// seams sit on the same line, which is exactly the coincidence the old
/// resolver read as one seam.
Future<Chrome> _pumpTwoSeams(WidgetTester tester) async {
  tester.view.physicalSize = _surface;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final settings = chronologSettings();
  final views = ViewBook();
  final stage = Stage(tunable: settings.tunable, onLens: views.setLens);
  for (final id in const ['a', 'b', 'c', 'd']) {
    stage.tiles[id] = _body(id);
    stage.openOrder.add(id);
  }
  stage.root = Branch(
    'root',
    mode: 'split',
    axis: 'column',
    ratios: [Rational.fromInt(1, 2), Rational.fromInt(1, 2)],
    children: [_row('top', 'a', 'b'), _row('bottom', 'c', 'd')],
  );
  stage.focusedId = 'a';
  final chrome = Chrome(settings: settings, stage: stage, views: views);
  await tester.pumpWidget(MaterialApp(home: ChronoSurface(chrome: chrome)));
  await tester.pumpAndSettle();
  return chrome;
}

Branch _branch(Chrome chrome, String id) => findNode(chrome.stage.root, id)! as Branch;

/// The point on the seam between the two tiles of one row.
Offset _seamOf(WidgetTester tester, String left, String right) {
  final a = tester.getRect(find.byKey(ValueKey('body-$left')));
  final b = tester.getRect(find.byKey(ValueKey('body-$right')));
  return Offset((a.right + b.left) / 2, a.center.dy);
}

double _cut(Chrome chrome, String branch) => _branch(chrome, branch).ratios[0].toDouble();

void main() {
  testWidgets('a drag bar moves only the two windows it sits between', (tester) async {
    final chrome = await _pumpTwoSeams(tester);
    final top = _cut(chrome, 'top'), bottom = _cut(chrome, 'bottom');
    await tester.dragFrom(_seamOf(tester, 'a', 'b'), const Offset(-180, 0));
    await tester.pumpAndSettle();
    expect(_cut(chrome, 'top'), lessThan(top - 0.05), reason: 'the seam dragged followed');
    expect(
      _cut(chrome, 'bottom'),
      closeTo(bottom, 0.001),
      reason:
          'ISSUES (9.1): "a drag bar moves ONLY the two windows it sits between, never '
          'aligning across the page" — the row below moved because its cut happened to '
          'land on the same pixel line.',
    );
  });

  testWidgets('the alignment chord shows the drag bars and moves the whole run', (tester) async {
    final chrome = await _pumpTwoSeams(tester);
    final bottom = _cut(chrome, 'bottom');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    addTearDown(() => tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft));
    await tester.pumpAndSettle();
    await tester.dragFrom(_seamOf(tester, 'a', 'b'), const Offset(-180, 0));
    await tester.pumpAndSettle();
    expect(
      _cut(chrome, 'bottom'),
      lessThan(bottom - 0.05),
      reason:
          'ISSUES (9.1): "seam-wide alignment becomes an explicit mode — a ctrl/key chord" '
          '— the chord was held and the collinear run did not come along.',
    );
  });

  testWidgets('a lock is authored under the chord and holds without it', (tester) async {
    final chrome = await _pumpTwoSeams(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    // Under the chord, a click on a drag bar is the one verb: link, or unlink.
    await tester.tapAt(_seamOf(tester, 'a', 'b'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(
      chrome.stage.lockedSeams,
      isNotEmpty,
      reason:
          'ISSUES (9.1): the chord "lets you lock or unlock an alignment", so linked seams '
          'are "something you author and can see"',
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    final bottom = _cut(chrome, 'bottom');
    await tester.dragFrom(_seamOf(tester, 'a', 'b'), const Offset(-180, 0));
    await tester.pumpAndSettle();
    expect(
      _cut(chrome, 'bottom'),
      lessThan(bottom - 0.05),
      reason: 'an authored link outlives the chord that authored it',
    );
    // And it survives the layout file, because an authored thing is saved.
    expect(chrome.stage.toJson()['seams'], chrome.stage.lockedSeams.toList());
  });

  testWidgets('an unlocked seam stays unlocked: the toggle is a toggle', (tester) async {
    final chrome = await _pumpTwoSeams(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await tester.tapAt(_seamOf(tester, 'a', 'b'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    await tester.tapAt(_seamOf(tester, 'a', 'b'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(chrome.stage.lockedSeams, isEmpty);
    final bottom = _cut(chrome, 'bottom');
    await tester.dragFrom(_seamOf(tester, 'a', 'b'), const Offset(-180, 0));
    await tester.pumpAndSettle();
    expect(_cut(chrome, 'bottom'), closeTo(bottom, 0.001), reason: 'back to two windows only');
  });

  testWidgets('a tap off the chord does not quietly re-plumb the page', (tester) async {
    final chrome = await _pumpTwoSeams(tester);
    await tester.tapAt(_seamOf(tester, 'a', 'b'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(
      chrome.stage.lockedSeams,
      isEmpty,
      reason: 'a seam is for dragging; a click that linked the page is the defect being fixed',
    );
  });
}
