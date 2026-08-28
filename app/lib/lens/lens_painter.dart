// The painting seam every time lens draws through.
//
// ONE OBJECT KNOWS BOTH DIRECTIONS. The web build re-implemented each lens's
// geometry backwards inside the drag layer, re-hardcoding the same constants a
// second time, which is why a drag-created event landed fifteen minutes from
// where the pointer was. A painter that exposes [unproject] beside [project]
// cannot disagree with itself.
//
// A time lens is a painter; ToDo and Tree lenses are widget trees and say so on
// their catalog entry. The distinction is [isTimeSurface], a property rather
// than a name test, so "a drag onto nothing must never mint an object" is one
// rule and not eight guard clauses.

import 'package:flutter/widgets.dart';

import '../core/coordinate_law.dart';
import '../core/exact.dart';
import '../core/projection.dart';
import 'marks.dart';
import 'theme.dart';
import 'tunables.dart';

export 'marks.dart' show MarkHit;

/// Everything a lens needs to draw one frame, and nothing it could mutate.
///
/// [law] is the PRIMARY frame's own law -- the one axis the surface counts in.
/// A companion frame's facts arrive already resolved to days, never reinterpreted
/// under this law.
@immutable
class LensScene {
  const LensScene({
    required this.engine,
    required this.projection,
    required this.law,
    required this.focusDays,
    required this.view,
    required this.theme,
    required this.nowDays,
    required this.size,
    this.tunable,
    this.selection = const {},
  });

  final ProjectionEngine engine;
  final Projection projection;
  final CoordinateLaw law;

  /// Where the view is centred, exactly, on the shared days axis.
  final Rational focusDays;

  /// This view tile's own per-lens state: span, cycle, mode, whatever its
  /// catalog entry declared. Opaque here on purpose.
  final Map<String, Object?> view;

  final Tunable? tunable;
  final ChronoTheme theme;

  /// Fact identities, so selection survives a re-query and selects ONE
  /// occurrence rather than the whole series.
  final Set<String> selection;

  final Rational nowDays;
  final Size size;

  Rational setting(String key) => tunableFrom(lensTunableDefaults, tunable, key);

  double px(String key) => setting(key).toDouble();

  int whole(String key) => setting(key).round().toInt();

  Object? viewValue(String key) => view[key];

  bool isSelected(Fact fact) => selection.contains(fact.identity);

  LensScene copyWith({
    Rational? focusDays,
    Map<String, Object?>? view,
    Set<String>? selection,
    Rational? nowDays,
    Size? size,
    ChronoTheme? theme,
  }) => LensScene(
    engine: engine,
    projection: projection,
    law: law,
    focusDays: focusDays ?? this.focusDays,
    view: view ?? this.view,
    theme: theme ?? this.theme,
    nowDays: nowDays ?? this.nowDays,
    size: size ?? this.size,
    tunable: tunable,
    selection: selection ?? this.selection,
  );
}

/// What a lens says when it cannot draw the document it was handed: the reason,
/// in the law's own vocabulary. REFUSE LOUDLY -- rendering nothing and saying
/// nothing is indistinguishable from an empty calendar.
typedef LensRefusal = ({String source, String message});

abstract class LensPainter extends CustomPainter {
  LensPainter(this.scene);

  final LensScene scene;

  /// The marks drawn by the last paint, in draw order. Built DURING paint, so
  /// the hit list and the pixels are the same derivation.
  final List<MarkHit> hits = [];

  /// Refusals collected during the last paint. A lens paints them; it never
  /// throws and never invents a coordinate conversion to avoid one.
  final List<LensRefusal> refusals = [];

  /// Every painter here draws a time axis. A roster lens is a widget and never
  /// reaches this class.
  bool get isTimeSurface => true;

  /// Screen point to the exact day it names. Null where the surface has no time
  /// under that point at all -- a gutter, the space outside a ring.
  Rational? unproject(Offset at);

  /// The inverse. Null for a day the surface is not currently showing.
  Offset? project(Rational days);

  /// The mark under a point, topmost first, by real geometry where the mark has
  /// a shape and by bounds where it does not.
  MarkHit? markAt(Offset at) {
    for (final hit in hits.reversed) {
      if (!hit.bounds.inflate(scene.px('lane.gap')).contains(at)) continue;
      if (hit.shape == null || hit.shape!.contains(at)) return hit;
    }
    return null;
  }

  /// The ink ring that marks selection. PURE INK, at two weights: the accent
  /// tint this once carried was still a colour, and colour carries authored
  /// frame and group meaning alone (ruled 2026-08-28).
  void paintSelection(Canvas canvas, Path shape) {
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = scene.px('selection.ring')
      ..color = scene.theme.ink.withValues(alpha: scene.px('selection.ringOpacity'));
    final inner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = scene.px('selection.inner')
      ..color = scene.theme.ink;
    canvas.drawPath(shape, ring);
    canvas.drawPath(shape, inner);
  }

  /// One place every lens says what it could not do. Sits where the surface is
  /// otherwise empty, in the data font, so a refusal never hides behind marks.
  void paintRefusals(Canvas canvas, Size size) {
    if (refusals.isEmpty) return;
    final text = refusals.map((refusal) => '${refusal.source}: ${refusal.message}').join('  ·  ');
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: scene.theme.data.copyWith(color: scene.theme.primary),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: size.width - scene.px('lane.gap') * 2);
    painter.paint(canvas, Offset(scene.px('lane.gap'), scene.px('lane.gap')));
  }

  @override
  bool shouldRepaint(covariant LensPainter old) =>
      old.scene != scene ||
      old.scene.focusDays != scene.focusDays ||
      old.scene.selection != scene.selection;
}
