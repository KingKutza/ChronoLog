// THREE GROUPINGS ARE ONE FILTER; IMPORTANCE IS WEIGHT (ISSUES 9.2).
//
// Don: "Why is frame not the default, and what do state and importance indicate
// if both are staples to frames?" Under his rulings, state / container / frame
// are one grouping -- the frame at the far end of a staple -- differing only in
// which frames are admitted as columns. Frame is the unfiltered case, so it is
// the default. Importance bands the derived weight and is labelled WEIGHT:
// "Importance is weight, I assume, and should probably be relabeled for
// clarity."
//
// The melt is asked of the surface, not of a list: what the person READS on the
// grouping control and in the board's own sentence about itself, and what the
// unfiltered grouping actually COLUMNS -- every frame a todo is stapled to,
// state frames included, because a filter that is always on is not the
// unfiltered case.

import 'package:chronolog/core/object_kinds.dart';
import 'package:chronolog/core/todo_shape.dart';
import 'package:chronolog/lens/theme.dart';
import 'package:chronolog/lens/todo/board.dart';
import 'package:chronolog/lens/todo/row.dart';
import 'package:chronolog/session/lens_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../edit/harness.dart';
import '../../helpers/projection_scene.dart';
import '../painters/grid_scene.dart';

const String calendar = 'calendar:a';

void main() {
  test('the board\'s default grouping is the unfiltered one: frame', () {
    expect(
      normalizeGrouping(null),
      equals('frame'),
      reason:
          'ISSUES 9.2: state defaulted. State and container are FILTERS over the frame grouping '
          '(state frames only; containment far ends only); frame is the whole set.',
    );
  });

  test('the weight-band grouping is labelled weight, never importance', () {
    // "Ruled: it is labelled WEIGHT, and it is the one non-staple grouping; if it
    // stays, it is 'group by weight band', the bands being the thresholds
    // already in settings." Read from the catalog's own control, which is what
    // the bar renders, and from the sentence the board says about itself.
    for (final lens in const ['list', 'board']) {
      final control = lensCatalog[lens]!.controls.firstWhere((entry) => entry.key == 'grouping');
      final labels = control.options.map((option) => option.label.toLowerCase()).toList();
      expect(
        labels.any((label) => label.contains('weight')),
        isTrue,
        reason: 'ISSUES 9.2: $lens offers no grouping that says "weight": $labels',
      );
      expect(
        labels.any((label) => label.contains('importance')),
        isFalse,
        reason: 'ISSUES 9.2: $lens still says "importance" for a band of the derived weight',
      );
    }
    final said = groupingReads('importance').toLowerCase();
    expect(said, contains('weight'), reason: 'the board\'s own sentence says weight');
    expect(said, isNot(contains('importance')));
  });

  testWidgets('frame is the unfiltered grouping: a state frame columns under it too', (
    tester,
  ) async {
    // "State = frames with the state trait, container = frames at the far end of
    // a whole-of-this-sits-in-that staple, all = no filter. Frame becomes the
    // default because it is the unfiltered case." So under frame grouping a todo
    // in Done stands under a Done column as well; under state grouping only the
    // state frames column. Same grouping, one filter or none.
    final scene = Scene()..calendar(calendar);
    scene.frame('group:ai', const ['set', 'group']);
    scene.document = scene.document.put(
      'frames',
      'group:ai',
      scene.document.frames['group:ai']!.copyWith(title: 'AI Team'),
    );
    scene.frame(doneStateFrameId, stateFrameTraits);
    scene.document = scene.document.put(
      'frames',
      doneStateFrameId,
      scene.document.frames[doneStateFrameId]!.copyWith(title: doneStateTitle),
    );
    final todo = scene.object(title: 'Finished thing', duration: '0');
    scene.document = scene.document.put(
      'events',
      todo,
      scene.document.events[todo]!.copyWith(traits: objectKinds['todo']!.traits),
    );
    scene.place(calendar, civil(2026, 8, 18, 9), event: todo);
    scene.join('group:ai', todo);
    scene.join(doneStateFrameId, todo);
    final bench = (await tester.runAsync(() => openEditor(scene.document, label: 'melt')))!;
    addTearDown(() => closeEditor(bench));
    tester.view.physicalSize = const Size(2000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Future<void> pump(String grouping) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: themeDataFor(shipped['paper']!),
          home: Scaffold(
            body: BoardLens(
              todoSceneOf(bench.editor, const [calendar], lens: 'board', view: {'grouping': grouping}),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    // A row's chips repeat a frame's title, so every claim below is about
    // HEADERS: the texts on the header line, which is the topmost line any
    // column title sits on.
    Iterable<Element> headersSaying(String title) {
      double dyOf(Element element) =>
          tester.getTopLeft(find.byElementPredicate((e) => e == element)).dy;
      final all = [...find.text('AI Team').evaluate(), ...find.text(doneStateTitle).evaluate()];
      final line = all.map(dyOf).reduce((a, b) => a < b ? a : b);
      return find.text(title).evaluate().where((element) => (dyOf(element) - line).abs() < 1);
    }

    await pump('frame');
    expect(headersSaying('AI Team'), isNotEmpty, reason: 'every stapled frame columns');
    expect(
      headersSaying(doneStateTitle),
      isNotEmpty,
      reason:
          'ISSUES 9.2: under the FRAME grouping the Done frame did not column -- `stapledFrames` '
          'leaves state frames out, which makes "frame" a filtered grouping and not the whole set.',
    );
    await pump('state');
    expect(headersSaying(doneStateTitle), isNotEmpty, reason: 'the state filter admits state frames');
    expect(
      headersSaying('AI Team'),
      isEmpty,
      reason: 'and nothing else columns: state is frame grouping with a filter, not a second grouping',
    );
  });
}
