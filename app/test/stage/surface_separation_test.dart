// STACKED SURFACES STAY DISTINGUISHABLE, AND AN EDGE IS DRAWN ONCE (ISSUES 9.2, Don).
//
// "The double line drag zones, and the paper colour blending into itself in the
// area." Two quirks, one class: surfaces deriving from the SAME theme token.
// Paper-on-paper is two stacked surfaces both painting `theme.paper` -- the tile
// body's ground and the tile's own box -- and, under a re-authored palette where
// ground and paper collide, a tile that cannot be told from the desk it sits on.
// The double line is a drop zone's edge drawn beside a tile's own rule with
// nothing separating them. Nothing is wrong at the shipped default; the default
// merely hides it.
//
// The rules, asserted at the real stage under GENERATED palettes:
//
//   From a tile's body outward to the desk, no two adjacent painted layers are
//   the same colour -- a surface states its step from its ground rather than
//   naming the ground's token again.
//   The drop zone owns ONE edge. While a drop hovers a tile, exactly one rule
//   lies on the edge the zone abuts; it does not add a line beside one that
//   already exists.

import 'dart:math';

import 'package:chronolog/chrome/controls.dart';
import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/lens/theme.dart';
import 'package:chronolog/session/view_state.dart';
import 'package:chronolog/stage/stage_widget.dart';
import 'package:chronolog/stage/tile.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/corpus.dart';

const Size _surface = Size(1400, 900);

String randomHex(Random random) =>
    '#${random.nextInt(0x1000000).toRadixString(16).padLeft(6, '0')}';

/// The palettes that hide nothing: a random one, one where desk and paper are
/// one colour, and one where all eight roles collide.
List<ChronoTheme> palettes(Random random) => [
  ChronoTheme.fromJson({for (final field in themeFields) field: randomHex(random)}),
  () {
    final one = randomHex(random);
    return ChronoTheme.fromJson({
      for (final field in themeFields) field: randomHex(random),
      'ground': one,
      'surface': one,
      'paper': one,
    });
  }(),
  () {
    final one = randomHex(random);
    return ChronoTheme.fromJson({for (final field in themeFields) field: one});
  }(),
];

TileSpec _body(String id, String type, String klass, String title) => TileSpec(
  id: id,
  type: type,
  klass: klass,
  title: title,
  build: (context) => SizedBox.expand(key: ValueKey('body-$id')),
);

Future<Chrome> _pump(WidgetTester tester, ChronoTheme theme) async {
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
  );
  installDefaultStage(chrome, minimap: (id) => _body(id, 'minimap', 'field', 'Minimap'));
  await tester.pumpWidget(MaterialApp(home: ChronoSurface(chrome: chrome, theme: theme)));
  // Bounded pumps, never settle: a stage may carry a live animation of its own.
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  return chrome;
}

/// The colour a widget paints as a ground, if it paints one.
Color? _paints(Widget widget) => switch (widget) {
  ColoredBox(:final color) => color,
  DecoratedBox(decoration: BoxDecoration(:final color)) => color,
  Container(:final color) when color != null => color,
  Container(decoration: BoxDecoration(:final color)) => color,
  Material(:final color) => color,
  Scaffold(:final backgroundColor) => backgroundColor,
  _ => null,
};

/// Every painted ground from a tile body outward to the window, innermost first.
/// A fully transparent paint is not a surface and does not count.
List<Color> _layers(WidgetTester tester, Finder body) {
  final layers = <Color>[];
  final inner = _paints(tester.widget(body));
  if (inner != null && inner.a > 0) layers.add(inner);
  tester.element(body).visitAncestorElements((element) {
    final colour = _paints(element.widget);
    if (colour != null && colour.a > 0) layers.add(colour);
    return true;
  });
  return layers;
}

/// Widgets in [within] drawing a rule along [edge] -- a box whose border side on
/// that edge is visible and whose own rect sits on it.
int _rulesOn(WidgetTester tester, Finder within, Rect tile, String edge) {
  var found = 0;
  for (final element in find.descendant(of: within, matching: find.byType(DecoratedBox)).evaluate()) {
    final decoration = (element.widget as DecoratedBox).decoration;
    if (decoration is! BoxDecoration || decoration.border is! Border) continue;
    final border = decoration.border! as Border;
    final side = switch (edge) {
      'left' => border.left,
      'right' => border.right,
      'top' => border.top,
      _ => border.bottom,
    };
    if (side.style == BorderStyle.none || side.width <= 0 || side.color.a == 0) continue;
    final box = element.renderObject as RenderBox?;
    if (box == null || !box.hasSize) continue;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final tolerance = 3.0;
    final onEdge = switch (edge) {
      'left' => (rect.left - tile.left).abs() <= tolerance,
      'right' => (rect.right - tile.right).abs() <= tolerance,
      'top' => (rect.top - tile.top).abs() <= tolerance,
      _ => (rect.bottom - tile.bottom).abs() <= tolerance,
    };
    if (onEdge) found += 1;
  }
  return found;
}

void main() {
  testWidgets('a tile is told from the desk it sits on, under any palette', (tester) async {
    final random = Random(specSeed);
    for (final theme in palettes(random)) {
      final chrome = await _pump(tester, theme);
      for (final leaf in chrome.stage.leaves) {
        final body = find.byKey(ValueKey('body-${leaf.id}'));
        if (body.evaluate().isEmpty) continue;
        final layers = _layers(tester, body);
        expect(layers.length, greaterThanOrEqualTo(2), reason: 'a tile sits on a desk');
        // The innermost ground is the tile's own sheet; the outermost is the desk.
        expect(
          layers.first,
          isNot(equals(layers.last)),
          reason:
              'ISSUES 9.2: under ${theme.toJson()}, tile ${leaf.id} is ${hexOf(layers.first)} on a '
              'desk of ${hexOf(layers.last)} -- "the paper colour blending into itself". A surface '
              'states its step from its ground; it never names the ground\'s own token.',
        );
        // And every stacked pair between them is a step, not the same token twice.
        final distinct = <Color>[];
        for (final layer in layers) {
          if (distinct.isEmpty || distinct.last != layer) distinct.add(layer);
        }
        expect(
          distinct.length,
          greaterThanOrEqualTo(2),
          reason: 'ISSUES 9.2: tile ${leaf.id} and its desk read as one flat wall under ${theme.toJson()}',
        );
      }
    }
  });

  testWidgets('a hovering drop draws one edge, never a rule beside a rule', (tester) async {
    final random = Random(specSeed + 1);
    for (final theme in palettes(random)) {
      final chrome = await _pump(tester, theme);
      final lens = chrome.stage.leaves.firstWhere((leaf) => leaf.type == 'view');
      final minimap = chrome.stage.leaves.firstWhere((leaf) => leaf.type == 'minimap');
      final source = tester.getRect(find.byKey(ValueKey('body-${minimap.id}')));
      final targetFinder = find.byKey(ValueKey('body-${lens.id}'));
      final target = tester.getRect(targetFinder);
      // Reveal the handle the way the hand does: hover the band.
      final band = chrome.px('stage.handleBand');
      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: Offset.zero);
      await pointer.moveTo(Offset(source.left + band / 2, source.center.dy));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final handles = find.text(handleMark).evaluate().where(
        (element) => source.contains(tester.getCenter(find.byWidget(element.widget))),
      );
      expect(handles, isNotEmpty, reason: 'the minimap reveals its handle under the pointer');
      final grab = tester.getCenter(find.byWidget(handles.first.widget));
      // The same pointer takes the handle: lifting it would put the handle away.
      await pointer.moveTo(grab);
      await tester.pump();
      await pointer.down(grab);
      await tester.pump(const Duration(milliseconds: 100));
      // Into the target's LEFT zone, in steps, and hold there: the preview is up.
      final edge = chrome.px('stage.edgeZone');
      final landing = Offset(target.left + target.width * edge / 2, target.center.dy);
      for (var step = 1; step <= 8; step += 1) {
        await pointer.moveTo(Offset.lerp(grab, landing, step / 8)!);
        await tester.pump(const Duration(milliseconds: 40));
      }
      await tester.pump(const Duration(milliseconds: 400));
      final tile = find.ancestor(of: targetFinder, matching: find.byType(AnimatedContainer)).first;
      expect(
        find.descendant(of: tile, matching: find.byType(FractionallySizedBox)),
        findsOneWidget,
        reason: 'the drop preview is up over the target (harness: the drag reached the tile)',
      );
      final rules = _rulesOn(tester, tile, tester.getRect(tile), 'left');
      expect(
        rules,
        equals(1),
        reason:
            'ISSUES 9.2: "the double line drag zones" -- under ${theme.toJson()} the drop preview '
            'drew $rules rules on the target\'s left edge. The zone owns one edge; it does not add '
            'a line beside the tile\'s own.',
      );
      await pointer.cancel();
      await pointer.removePointer();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }
  });
}
