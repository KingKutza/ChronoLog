// The minimap tile: squad A's particle field, hosted, describing the FOCUSED
// view tile and scrubbing its focus.
//
// THE RANGE FREEZES THE MOMENT A POINTER TOUCHES IT. A field that re-anchors
// mid-drag slides under the pointer and the scrub becomes unusable -- the same
// reason the range has hysteresis at rest. The drift freezes with it.
//
// A press inside the window box GRABS it, keeping the offset it was taken at; a
// press outside JUMPS the focus to the point clicked. One subtraction tells the
// two apart.
//
// THE CLOCK IS CONTINUOUS SECONDS, never a repeating phase. A controller that
// repeats zero to one restarts in unison every cycle, and Don saw exactly that:
// "the motion is good ... the loop is the issue." Held, not reset, while frozen.

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/exact.dart';
import '../../stage/content.dart';
import '../../stage/tile.dart';
import '../gestures.dart';
import '../law_context.dart';
import '../theme.dart';
import '../view_tile.dart';
import 'field.dart';
import 'labels.dart';
import 'painter.dart';

class MinimapTile extends StatefulWidget {
  const MinimapTile({super.key, required this.surface});

  final Surface surface;

  @override
  State<MinimapTile> createState() => _MinimapTileState();
}

class _MinimapTileState extends State<MinimapTile> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);

  /// Seconds of animation, monotone and unwrapped, in its own notifier so a
  /// frame repaints the field without rebuilding the tile around it.
  final ValueNotifier<double> _clock = ValueNotifier<double>(0);
  Duration _elapsed = Duration.zero;
  final Notches _wheel = Notches(), _zoomWheel = Notches();

  MinimapPainter? _painter;
  MinimapRange? _range;
  MinimapField? _field;
  String? _tile;
  Rational _grab = Rational.zero, _span = Rational.one;

  /// HOW BROAD THIS FIELD'S OWN RANGE IS, as a multiple of the shipped one. The
  /// minimap's zoom verb moves THIS (ISSUES 9.1) -- the focused view's window is
  /// what the box on the field draws, and scrubbing it is a different verb.
  Rational _breadth = Rational.one;
  bool _frozen = false, _stale = true;

  @override
  void initState() {
    super.initState();
    _ticker.start();
    widget.surface.editor.changes.addListener(_invalidate);
    widget.surface.views.addListener(_invalidate);
  }

  /// Advances the clock by the frame's own step, and by nothing at all while a
  /// pointer is down: the field holds where it was rather than jumping when the
  /// scrub ends.
  void _tick(Duration elapsed) {
    final step = elapsed - _elapsed;
    _elapsed = elapsed;
    if (_frozen) return;
    _clock.value += step.inMicroseconds / Duration.microsecondsPerSecond;
  }

  @override
  void dispose() {
    widget.surface.editor.changes.removeListener(_invalidate);
    widget.surface.views.removeListener(_invalidate);
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  /// The document or the projection moved: the accumulation is no longer true.
  void _invalidate() => _stale = true;

  double _px(String key) => widget.surface.settings.value(key).toDouble();

  @override
  Widget build(BuildContext context) {
    final surface = widget.surface;
    return ListenableBuilder(
      listenable: Listenable.merge([
        surface.editor.changes,
        surface.views,
        surface.settings,
        surface.stage.listenable,
      ]),
      builder: (context, _) => _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final surface = widget.surface;
    final read = surface.settings.tunable;
    final tile = surface.stage.focusedViewTile;
    final state = tile == null ? null : surface.views.of(tile);
    final frame = state?.selection.primary();
    if (tile == null || state == null || frame == null) {
      return statedRefusal(context, 'No focused view tile is projecting anything.', read);
    }
    final law = surface.editor.engine.lawOf(frame);
    final focus = surface.views.focusOf(tile);
    _span = state.spanDays(law, surface.settings);
    final range = _frozen && _range != null
        ? _range!
        : slideRange(_range, focus, _span * _breadth, read);
    if (_stale || _field == null || range != _range || tile != _tile) {
      _range = range;
      _tile = tile;
      _stale = false;
      _field = accumulate(surface.editor.engine, state.projection(), range, read);
    }
    return Listener(
      onPointerDown: _down,
      onPointerMove: (event) => _scrub(event.localPosition),
      onPointerUp: (_) => setState(() => _frozen = false),
      onPointerCancel: (_) => setState(() => _frozen = false),
      onPointerSignal: _signal,
      child: ValueListenableBuilder<double>(
        valueListenable: _clock,
        builder: (context, clock, _) {
          _painter = MinimapPainter(
            field: _field!,
            law: LawContext(law),
            theme: ChronoTheme.of(context),
            focusDays: focus,
            spanDays: _span,
            nowDays: nowDays(),
            granularity: granularityFor(state.lensId),
            tunable: read,
            clock: clock,
            frozen: _frozen,
          );
          return CustomPaint(painter: _painter, size: Size.infinite);
        },
      ),
    );
  }

  void _down(PointerDownEvent event) {
    final painter = _painter, tile = _tile;
    if (painter == null || tile == null) return;
    final focus = widget.surface.views.focusOf(tile);
    final centre = painter.project(focus);
    // The window box's half-width in pixels IS the projection of half a span.
    final edge = painter.project(focus + _span / Rational.fromInt(2));
    if (centre == null || edge == null) return;
    setState(() {
      _frozen = true;
      // Along the time axis, whichever way it runs -- the painter names its own
      // orientation so the grab test cannot disagree with what was drawn.
      _grab =
          (painter.along(event.localPosition) - centre).abs() <=
              (edge - centre).abs() * _px('pointer.minimapGrab')
          ? focus - painter.unproject(event.localPosition)
          : Rational.zero;
    });
    _scrub(event.localPosition);
  }

  void _scrub(Offset at) {
    final painter = _painter, tile = _tile;
    if (painter == null || tile == null || !_frozen) return;
    widget.surface.views.setFocus(tile, painter.unproject(at) + _grab);
  }

  /// The wheel, answering the WHOLE vocabulary. A surface that cannot honour a
  /// verb refuses in words; it never silently reroutes the gesture into a
  /// different one, which is what the missing ctrl arm was doing -- every
  /// ctrl+wheel fell through to the pan path and nudged the view's focus
  /// (ISSUES 9.1).
  void _signal(PointerSignalEvent event) {
    final tile = _tile;
    if (event is! PointerScrollEvent || tile == null) return;
    final notch = _px('pointer.wheelNotch');
    if (HardwareKeyboard.instance.isControlPressed) return _zoomRange(event, notch);
    final steps = _wheel.take(event.scrollDelta.dy, notch);
    if (steps == 0) return;
    final views = widget.surface.views;
    final step = widget.surface.settings.value('pointer.panStepFraction') * Rational.fromInt(steps);
    views.setFocus(tile, views.focusOf(tile) + _span * step);
  }

  /// Zoom, on this surface, is the breadth of its own range. The direction comes
  /// from the one pointer setting every surface reads, so wheel-up means the
  /// same thing here as it does on a lens.
  void _zoomRange(PointerScrollEvent event, double notch) {
    final settings = widget.surface.settings;
    final direction = settings.value('pointer.zoomDirection').toDouble();
    final steps = _zoomWheel.take(event.scrollDelta.dy * direction, notch);
    if (steps == 0) return;
    final factor = settings.value('minimap.zoomStep');
    var next = _breadth;
    for (var step = 0; step < steps.abs(); step += 1) {
      next = steps < 0 ? next / factor : next * factor;
    }
    final least = settings.value('minimap.breadthMin');
    final most = settings.value('minimap.breadthMax');
    setState(() {
      _breadth = next < least ? least : (next > most ? most : next);
      // The range's width is what changed, so the accumulation over it is no
      // longer the field this tile is holding.
      _stale = true;
    });
  }
}

/// The minimap as a stage tile. Its `type` is `minimap` and nothing else about
/// it is special: it splits, tabs, moves and closes like any other tile.
TileSpec minimapTileSpec(String id, Surface surface) => TileSpec(
  id: id,
  type: 'minimap',
  klass: 'minimap',
  title: 'Minimap',
  build: (_) => MinimapTile(surface: surface),
);

/// The minimap as a CONTENT (the one ancestor, ruled 2026-09-01).
class MinimapContent extends TileContent {
  const MinimapContent(this.surface);

  final Surface surface;

  @override
  String get kind => 'minimap';

  @override
  String get title => 'Minimap';

  @override
  TileSpec spec(String id) => minimapTileSpec(id, surface);
}
