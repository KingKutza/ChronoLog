// DONE IS A FRAME LIKE ANY OTHER (ISSUES 9.2, Don's question on Done).
//
// "Why is Done treated special to any other staple? It seems to me like the
// data model does not support different frame types." It does not, and the
// code disobeys it: a hard-coded frame id decides "resolved" at ten sites, and
// two readers return the strings done / closed / open. The rule:
//
//   What "resolved" DOES is the frame's authored handling, never its id. An
//   object in a state frame the person minted reads exactly as one in the
//   shipped Done, when the two frames say the same thing. The ICS boundary's
//   completed-frame is a settings key, not a constant in the engine.

import 'dart:io';
import 'dart:math';

import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/object_kinds.dart';
import 'package:chronolog/edit/gestures.dart';
import 'package:chronolog/lens/display_weight.dart';
import 'package:flutter_test/flutter_test.dart';

import '../edit/harness.dart';

final int runSeed =
    int.tryParse(Platform.environment['CHRONOLOG_SEED'] ?? '') ??
    DateTime.now().microsecondsSinceEpoch;

void main() {
  // ignore: avoid_print
  print('DONE MELT RUN SEED: $runSeed  (set CHRONOLOG_SEED=$runSeed to reproduce)');
  final random = Random(runSeed);

  test('a person-minted state frame that says what Done says reads as Done', () async {
    final bench = await openEditor(createEmptyWorkspaceDocument());
    addTearDown(() => closeEditor(bench));
    final editor = bench.editor;
    final calendar = editor.document.frames.values
        .firstWhere((frame) => frame.traits.contains('temporal'))
        .id;
    final own = 'frame:state-${random.nextInt(1 << 20)}';
    final shipped = editor.createAt(calendar, Rational.fromInt(10), null, kind: 'todo');
    final minted = editor.createAt(calendar, Rational.fromInt(11), null, kind: 'todo');
    editor.toggleState(shipped, doneStateFrameId);
    editor.toggleState(minted, own, title: 'Finished');
    // Both frames now exist and both objects are in exactly one state frame.
    final engine = editor.engine;
    final facts = engine.explicitFacts(calendar);
    final shippedFact = facts.firstWhere((fact) => fact.event.id == shipped);
    final mintedFact = facts.firstWhere((fact) => fact.event.id == minted);
    expect(
      todoState(engine, mintedFact),
      equals(todoState(engine, shippedFact)),
      reason:
          'ISSUES 9.2: `$own` and `$doneStateFrameId` are two state frames saying the same '
          'thing; only the ID differs, and the id decided ("closed" vs "done"). Resolved '
          'is the frame\'s authored handling, read generatively for every state frame.',
    );
  });

  test('the ICS completed-frame is a settings key, not an engine constant', () {
    final settings = chronologSettings();
    expect(
      settings.text('ics.completedFrame'),
      isNotEmpty,
      reason:
          'ISSUES 9.2: VTODO STATUS:COMPLETED must map to SOME frame on import and back on '
          'export -- the one legitimate named default -- as a settings key naming the frame, '
          'defaulting to a frame titled Done minted on first need.',
    );
  });
}
