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

/// How a pan lands: what the view window moves by, what the eye is shown while
/// the gesture is live, and how much of the gesture the movement ACCOUNTED FOR.
///
/// [taken] is the third field because a surface can be honest about a motion it
/// can only commit in steps (ISSUES 9.1, Intimate's ratchet). Sideways, an
/// Intimate column IS a whole day: a half-column slide is real to the eye and
/// unrepresentable in the window, so the landing shows the whole slide, commits
/// the whole columns, and says which pixels the commit answered for. What it did
/// not take stays shown, and nothing is dropped. A surface whose window can hold
/// the entire gesture answers `taken: shift` and behaves exactly as before.
typedef PanLanding = ({Rational days, Offset shown, Offset taken});

/// A bleeding lens, drawn into a canvas that begins at the bleed's own corner.
///
/// A picture records what its BOUNDS hold, so a painter that draws past its
/// viewport is drawing into a region that may never be rasterised -- and a pan
/// can only slide in pixels that exist. This gives the render box the whole
/// bled area and hands the lens back its own viewport coordinates, so nothing a
/// painter does changes and everything it draws past the edge is really there.
class BledPainter extends CustomPainter {
  const BledPainter(this.lens, this.bleed);

  final LensPainter lens;
  final Offset bleed;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(bleed.dx, bleed.dy);
    lens.paint(canvas, Size(size.width - bleed.dx * 2, size.height - bleed.dy * 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant BledPainter old) =>
      old.bleed != bleed || lens.shouldRepaint(old.lens);
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
  ///
  /// THIS IS WHAT A CLICK MEANS -- select, open, the menu, the cursor -- and it
  /// is the WHOLE mark. Don, 2026-08-31: "Clicking, and double clicking on an
  /// event don't open its card, also right clicking does not include an open
  /// card option." One shape was answering two questions: Intimate's blocks
  /// record a narrow grab strip so a create-drag can pass through an occupied
  /// span, and that strip was gating selection too, so a click anywhere but the
  /// leading nine pixels found no mark at all. A drag asks [grabAt]; everything
  /// else asks here.
  MarkHit? markAt(Offset at) => _under(at, (hit) => hit.shape);

  /// The mark a DRAG grabs at a point, which may be a strip of it rather than
  /// its body. A mark that declares no grab is grabbed wherever it is hit, so
  /// this is [markAt] on every surface but the one with a reason to differ.
  MarkHit? grabAt(Offset at) => _under(at, (hit) => hit.grab ?? hit.shape);

  MarkHit? _under(Offset at, Path? Function(MarkHit hit) region) {
    for (final hit in hits.reversed) {
      if (!hit.bounds.inflate(scene.px('lane.gap')).contains(at)) continue;
      final shape = region(hit);
      if (shape == null || shape.contains(at)) return hit;
    }
    return null;
  }

  /// How far past its own box this surface paints, per axis.
  ///
  /// A pan is a live transform of the already-painted scene, so the pixels the
  /// transform slides in have to have been drawn: white space arriving at the
  /// edge during a drag is the painter having covered its viewport and nothing
  /// more. A surface that bleeds may be transformed by up to this much and still
  /// show content; past it the pan COMMITS and the scene is drawn again in the
  /// same place at full fidelity.
  Offset get bleed => Offset.zero;

  /// How a pan of [shift] screen pixels lands on this surface: the focus
  /// movement that realises it, and the pixel offset the eye may be shown while
  /// the gesture is live.
  ///
  /// THE TRANSFORM SHOWS EXACTLY WHAT RELEASE COMMITS (ruled 2026-08-31). Don:
  /// "I drag up and right, and then it snaps back to basically the same
  /// position." A gesture that slides the scene somewhere the window cannot go
  /// is the surface lying about what mouse-up does, so a surface that cannot
  /// pan a component shows no motion in it.
  ///
  /// The default is a surface whose window is one axis of time: the whole
  /// gesture goes to the focus, asked through this painter's own [unproject] so
  /// the arithmetic is right on a ring as well as on a rail, and nothing is
  /// previewed -- the commit is what the eye sees. A surface that CAN preview
  /// says so by declaring a [bleed] and answering with a `shown`.
  PanLanding panLanding(Offset shift) {
    final centre = Offset(scene.size.width / 2, scene.size.height / 2);
    final reach = Offset(scene.size.width / 4, scene.size.height / 4);
    // Asked at a place the surface actually represents. A ring has a HOLE at its
    // centre, and asking a surface about somewhere it draws nothing is how a pan
    // comes back zero and the gesture goes dead.
    for (final probe in [
      centre,
      centre + Offset(reach.dx, 0),
      centre - Offset(reach.dx, 0),
      centre + Offset(0, reach.dy),
      centre - Offset(0, reach.dy),
    ]) {
      final here = unproject(probe), there = unproject(probe - shift);
      if (here == null || there == null) continue;
      return (days: there - here, shown: Offset.zero, taken: shift);
    }
    return (days: Rational.zero, shown: Offset.zero, taken: Offset.zero);
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
