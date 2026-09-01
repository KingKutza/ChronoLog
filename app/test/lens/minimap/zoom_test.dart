// THE MINIMAP ANSWERS THE WHOLE POINTER VOCABULARY (ISSUES 9.1).
//
// "Ctrl+scroll on the minimap does not zoom the minimap. Two gaps: the
// minimap's `_signal` has NO ctrl arm — every wheel event, ctrl held or not,
// falls into the one pan path and nudges the focused view's window — and the
// minimap has no zoom verb to reach anyway." The class Don named is the point:
// the pointer table is ONE vocabulary, and a surface never silently reroutes a
// gesture into a different verb. So the claims are both halves — ctrl+wheel
// widens or narrows the minimap's OWN range, and it does not move the view.

import 'dart:io';

import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/lens/minimap/minimap_tile.dart';
import 'package:chronolog/lens/minimap/painter.dart';
import 'package:chronolog/lens/theme.dart';
import 'package:chronolog/lens/view_tile.dart';
import 'package:chronolog/session/settings.dart';
import 'package:chronolog/session/view_state.dart';
import 'package:chronolog/stage/tile.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../edit/harness.dart';

const String tileId = 'view:1';
const String wallTime = 'frame:wall-time';

final List<Directory> roots = [];

typedef Bed = ({Surface surface, ViewBook views, Settings settings});

Future<Bed> layOut(WidgetTester tester) async {
  final bench = (await tester.runAsync(() => openEditor(createEmptyWorkspaceDocument())))!;
  roots.add(bench.root);
  final settings = chronologSettings();
  final views = ViewBook()..defaultFrames = [wallTime];
  views.of(tileId).lensId = 'intimate';
  final stage = Stage();
  final surface = (
    editor: bench.editor,
    settings: settings,
    views: views,
    stage: stage,
    objectCard: null,
    frameCard: null,
    settingsCard: null,
  );
  stage.open(
    TileSpec(
      id: tileId,
      type: 'view',
      klass: 'lens',
      title: 'View',
      build: (_) => const SizedBox.shrink(),
    ),
  );
  stage.focus(tileId);
  return (surface: surface, views: views, settings: settings);
}

MinimapPainter painterOf(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((paint) => paint.painter)
    .whereType<MinimapPainter>()
    .first;

Rational breadthOf(WidgetTester tester) {
  final range = painterOf(tester).field.range;
  return range.end - range.start;
}

Future<void> wheel(WidgetTester tester, double dy, {bool control = false}) async {
  if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  final pointer = TestPointer(1, PointerDeviceKind.mouse);
  final centre = tester.getCenter(find.byType(MinimapTile));
  await tester.sendEventToBinding(pointer.hover(centre));
  await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
  await tester.pump();
  if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
}

Future<void> pump(WidgetTester tester, Bed bed) => tester.pumpWidget(
  MaterialApp(
    theme: ThemeData(extensions: [shipped['paper']!]),
    home: Scaffold(
      body: SizedBox(width: 600, height: 120, child: MinimapTile(surface: bed.surface)),
    ),
  ),
);

void main() {
  tearDownAll(() {
    for (final root in roots) {
      if (root.existsSync()) root.deleteSync(recursive: true);
    }
  });

  testWidgets('ctrl+wheel changes the MINIMAP own range breadth, both ways', (tester) async {
    final bed = await layOut(tester);
    await pump(tester, bed);
    final notch = bed.settings.value('pointer.wheelNotch').toDouble();
    final rest = breadthOf(tester);

    await wheel(tester, -notch * 2, control: true);
    final zoomedIn = breadthOf(tester);
    expect(
      zoomedIn < rest,
      isTrue,
      reason:
          'ISSUES (9.1): ctrl+wheel up left the minimap range at $zoomedIn against '
          '$rest — the surface has no zoom verb of its own to reach.',
    );

    await wheel(tester, notch * 4, control: true);
    expect(
      breadthOf(tester) > zoomedIn,
      isTrue,
      reason: 'and it runs both ways: a notch the other way widens the range',
    );
  });

  testWidgets('a verb the minimap answers is never rerouted into the pan', (tester) async {
    // The class, in Don's words: "a surface that cannot honour a verb refuses in
    // words, it never silently reroutes the gesture into a different verb."
    // Ctrl+wheel is zoom here, so it must not nudge the view's window at all.
    final bed = await layOut(tester);
    await pump(tester, bed);
    final notch = bed.settings.value('pointer.wheelNotch').toDouble();
    final focus = bed.views.focusOf(tileId);
    await wheel(tester, -notch * 3, control: true);
    expect(
      bed.views.focusOf(tileId),
      focus,
      reason:
          'ISSUES (9.1): ctrl+wheel fell through into the pan path and moved the '
          'focused view instead of zooming the field.',
    );
    // And the plain wheel still scrubs, so the pan verb was not traded away.
    await wheel(tester, notch * 3);
    expect(bed.views.focusOf(tileId), isNot(focus));
  });
}
