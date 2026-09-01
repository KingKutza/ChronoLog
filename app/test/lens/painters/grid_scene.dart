// Scene support for the grid lenses. Uncounted: it decides nothing, it only
// builds the inputs the specs then make claims about.

import 'dart:ui';

import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/projection.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/edit/editor.dart';
import 'package:chronolog/lens/lens_painter.dart';
import 'package:chronolog/lens/painters/month_grid.dart';
import 'package:chronolog/lens/painters/intimate.dart';
import 'package:chronolog/lens/theme.dart';
import 'package:chronolog/lens/todo/row.dart';
import 'package:chronolog/lens/tunables.dart';
import 'package:chronolog/session/lens_catalog.dart';
import 'package:chronolog/session/settings.dart';

/// Every area's shipped defaults, composed exactly as the session composes them,
/// so a spec reads the same numbers the program does.
Settings allSettings() => Settings(
  defaults: const [
    lensTunableDefaults,
    sessionTunableDefaults,
    gridTunableDefaults,
    intimateTunableDefaults,
    todoTunableDefaults,
    editTunableDefaults,
  ],
);

Tunable get allTunables => allSettings().tunable;

/// An 8x8x8 calendar: eight months of sixty-four days of eight hours, counting
/// in no registered calendar at all.
const Json eightLaw = {
  'kind': 'nested',
  'baseLevel': 'day',
  'levels': [
    {'name': 'year'},
    {
      'name': 'month',
      'within': 'year',
      'radix': '8',
      'names': ['Ka', 'Ta', 'Na', 'Ma', 'Sa', 'Ra', 'La', 'Va'],
    },
    {'name': 'day', 'within': 'month', 'radix': '64'},
    {'name': 'hour', 'within': 'day', 'radix': '8'},
  ],
};

Rational civilDays(int year, int month, int day) =>
    Rational(daysFromCivil(BigInt.from(year), month, day));

LensScene sceneOf(
  Document document,
  List<String> frames, {
  Map<String, Object?> view = const {},
  Size size = const Size(960, 720),
  Rational? focus,
  Rational? now,
  Set<String> selection = const {},
}) {
  final engine = ProjectionEngine(document);
  final at = focus ?? civilDays(2026, 8, 18);
  return LensScene(
    engine: engine,
    projection: Projection.of(frames),
    law: engine.lawOf(frames.first),
    focusDays: at,
    view: view,
    theme: shipped['paper']!,
    nowDays: now ?? at,
    size: size,
    tunable: allTunables,
    selection: selection,
  );
}

/// Paints onto a discarded canvas: the specs read the painter's own hit list and
/// geometry, which are built DURING paint, so nothing has to inspect pixels.
void render(LensPainter painter, Size size) => painter.paint(Canvas(PictureRecorder()), size);

TodoScene todoSceneOf(
  Editor editor,
  List<String> frames, {
  String lens = 'list',
  Map<String, Object?> view = const {},
  Rational? now,
  void Function(String)? onProject,
  void Function(String, Object?)? onView,
}) => TodoScene(
  lens: lens,
  editor: editor,
  projection: Projection.of(frames),
  theme: shipped['paper']!,
  nowDays: now ?? civilDays(2026, 8, 18),
  tunable: allTunables,
  view: view,
  onProject: onProject,
  onView: onView,
);
