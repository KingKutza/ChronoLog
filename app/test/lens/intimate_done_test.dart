// A COMPLETED TODO IS STILL A MARK (ISSUES 8.26, "The completed todo is gone in
// Intimate too").
//
// Don's words, whole: "The completed todo is gone in Intimate too." The entry
// left the mechanism unconfirmed and guessed at three -- the item's placement,
// the end staple interaction, or scroll position. Confirmed against THIS
// build's code rather than the guess: nothing on the render path filters by
// state. `todoState` only decorates (`MarkSpec.strike` draws the line through a
// resolved mark and `mark.doneOpacity` fades it), and the population half --
// WHICH entries a lens sees -- became the projection's boolean algebra, union by
// default, which is where the 8.26 List/Board state-gate died (todo_shape.dart
// header). The one remaining suspect was the model: entering Done writes a
// membership to the state frame AND an `end` staple at the completion instant,
// and an instant before the placement, or days after it, could have refused the
// object's extent and dropped the record from `_direct`. Probed over instants
// on every side of the placement: it does not.
//
// So this file states the behaviour Don wants, as the roster already says it
// ("A completed ToDo is still an entry -- completion is a fact about the object,
// never a reason to stop listing it"):
//
//   For a todo placed anywhere on a calendar, entering the resolved state at ANY
//   instant -- before the placement, the same day, or days after -- leaves the
//   todo projected at its placement, drawn by Intimate as a mark whose state is
//   the resolved word, and listed by the roster as completed. Nothing about
//   completion decides visibility; only a projection's authored NOT does.
//
// Generative: seeded placement day and hour, seeded completion instants on
// either side of the placement, seeded painter now. If this file is green the
// 8.26 report is stale in this build and should be marked so in ISSUES.md; if
// it ever goes red, the failure names the seed and the instants that hid the
// mark.

import 'dart:io';
import 'dart:math';

import 'package:chronolog/core/coordinate_law.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/object_kinds.dart';
import 'package:chronolog/edit/gestures.dart';
import 'package:chronolog/lens/display_weight.dart';
import 'package:chronolog/lens/painters/intimate.dart';
import 'package:flutter_test/flutter_test.dart';

import '../edit/harness.dart';
import '../helpers/staple_world.dart';
import 'painters/grid_scene.dart';

final int runSeed =
    int.tryParse(Platform.environment['CHRONOLOG_SEED'] ?? '') ??
    DateTime.now().microsecondsSinceEpoch;

String seeded(String message) => '$message  (set CHRONOLOG_SEED=$runSeed to reproduce)';

/// How many seeded placements are asked. Each opens its own editor.
const int cases = 6;

void main() {
  // ignore: avoid_print
  print('INTIMATE DONE RUN SEED: $runSeed  (set CHRONOLOG_SEED=$runSeed to reproduce)');
  final random = Random(runSeed);

  for (var index = 0; index < cases; index += 1) {
    // The placement, the completion instant and the painter's now are all drawn
    // here, once, so the case name and every reason can say what they were.
    final day = 1 + random.nextInt(28), hour = random.nextInt(24);
    final doneMonth = 8 + random.nextInt(3), doneDay = 1 + random.nextInt(28);
    final doneHour = random.nextInt(24);
    final nowMonth = 8 + random.nextInt(3), nowDay = 1 + random.nextInt(28);

    test(
      'a todo placed 2026-09-$day $hour:00 and completed 2026-$doneMonth-$doneDay $doneHour:00 '
      'is still a mark on Intimate (case $index)',
      () async {
        final bench = await openEditor(
          createEmptyWorkspaceDocument(now: DateTime.utc(2026, 9, 1)),
          label: 'intimate-done-$index',
        );
        addTearDown(() => closeEditor(bench));
        final editor = bench.editor;
        final calendar = editor.document.frames.values
            .firstWhere((frame) => frame.traits.contains('temporal'))
            .id;
        final placed = civilDays(2026, 9, day) + Rational.fromInt(hour, 24);
        final todo = editor.createAt(calendar, placed, null, kind: 'todo');

        // ENTER DONE at a stated instant, which is the one thing the entry's
        // guesses had in common: the end staple lands somewhere other than the
        // placement -- before it, the same day, or well after.
        editor.toggleState(
          todo,
          doneStateFrameId,
          frame: calendar,
          at: Coordinate.fromJson(civil(2026, doneMonth, doneDay, doneHour)),
        );
        expect(
          editor.engine.facts.stateAffiliations(todo),
          isNotEmpty,
          reason: seeded('the premise: the todo entered the state frame'),
        );

        final scene = sceneOf(
          editor.document,
          [calendar],
          focus: placed,
          now: civilDays(2026, nowMonth, nowDay),
        );
        final painter = IntimatePainter(scene);
        render(painter, scene.size);

        final marks = painter.hits.where((hit) => hit.fact.event.id == todo).toList();
        expect(
          marks,
          isNotEmpty,
          reason: seeded(
            'ISSUES 8.26: the completed todo is gone from Intimate. Placed 2026-09-$day '
            '$hour:00, completed 2026-$doneMonth-$doneDay $doneHour:00, now 2026-$nowMonth-'
            '$nowDay -- completion is a fact about the object, never a reason to stop '
            'drawing it.',
          ),
        );
        for (final mark in marks) {
          expect(
            mark.fact.day,
            placed,
            reason: seeded('a completion instant names when the todo finished, not where it sits'),
          );
          expect(
            factDisplayWeight(scene, mark.fact, keyPrefix: 'intimate').state,
            resolvedStateWord,
            reason: seeded('the mark is drawn AS resolved: struck and faded, never hidden'),
          );
        }

        // The roster is the other surface the 8.26 report named ("too"): the
        // same object, the same completion, still an entry.
        final roster = editor.engine.facts.rosterEntries('todo');
        expect(
          roster.where((entry) => entry.id == todo).map((entry) => entry.completed),
          equals([true]),
          reason: seeded('the roster lists the completed todo once, as completed'),
        );
      },
    );
  }
}
