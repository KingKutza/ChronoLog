// The drag ghost: what the drop WILL be, drawn while the drag is still live.
//
// ISSUES 8.26: a drag-created event landed fifteen minutes from where the click
// felt like it was, and nothing showed the would-be time. The ruling is either
// land exactly where clicked or snap VISIBLY. This does both at once -- the
// rectangle is drawn at the snapped coordinate and labelled with the same
// coordinate the drop commits, formatted by the frame's own law. The eye and the
// drop read one derivation, so they cannot disagree.
//
// It is its own paint layer above the lens, so a moving ghost repaints a ghost
// and never the surface under it.

import 'package:flutter/widgets.dart';

import 'theme.dart';
import 'tunables.dart';

/// A record, so equality is structural and the layer repaints only when the
/// ghost actually changed.
typedef DragGhost = ({Rect rect, String label, bool creating});

class GhostPainter extends CustomPainter {
  GhostPainter(this.ghost, this.theme, this.tunable);

  final DragGhost? ghost;
  final ChronoTheme theme;
  final Tunable? tunable;

  double _px(String key) => pixels(tunable, key);

  @override
  void paint(Canvas canvas, Size size) {
    final ghost = this.ghost;
    if (ghost == null) return;
    final minimum = _px('pointer.ghostMinimum');
    final rect = Rect.fromLTRB(
      ghost.rect.left,
      ghost.rect.top,
      ghost.rect.right < ghost.rect.left + minimum ? ghost.rect.left + minimum : ghost.rect.right,
      ghost.rect.bottom < ghost.rect.top + minimum ? ghost.rect.top + minimum : ghost.rect.bottom,
    );
    final rounded = RRect.fromRectXY(rect, _px('pointer.ghostCorner'), _px('pointer.ghostCorner'));
    canvas.drawRRect(
      rounded,
      Paint()..color = theme.accent.withValues(alpha: _px('pointer.ghostOpacity')),
    );
    canvas.drawRRect(
      rounded,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _px('pointer.ghostStroke')
        ..color = theme.ink,
    );
    _paintLabel(canvas, size, rect, ghost.label);
  }

  /// The live coordinate, in the data font, on its own paper plate so it stays
  /// readable over whatever the drag crosses. It sits beside the ghost and flips
  /// to the far side rather than leaving the surface.
  void _paintLabel(Canvas canvas, Size size, Rect rect, String label) {
    if (label.isEmpty) return;
    final gap = _px('pointer.ghostLabelGap'), pad = _px('pointer.ghostLabelPad');
    final text = TextPainter(
      text: TextSpan(
        text: label,
        style: theme.data.copyWith(fontSize: _px('pointer.ghostLabelSize'), color: theme.ink),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final wide = text.width + pad * 2;
    final left = rect.right + gap + wide > size.width ? rect.left - gap - wide : rect.right + gap;
    final top = rect.top;
    final plate = Rect.fromLTWH(left, top, wide, text.height + pad * 2);
    canvas.drawRect(plate, Paint()..color = theme.paper);
    canvas.drawRect(
      plate,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _px('mark.stroke')
        ..color = theme.hair,
    );
    text.paint(canvas, Offset(left + pad, top + pad));
  }

  @override
  bool shouldRepaint(covariant GhostPainter old) => old.ghost != ghost || old.theme != theme;
}
