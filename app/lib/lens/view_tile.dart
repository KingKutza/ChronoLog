// The view tile: one lens, hosted, with the whole pointer vocabulary attached.
//
// A tile IS a lens (the zoom auto-swap is dead), so this builds the scene from
// the tile's own view state and hands it to whichever painter the catalog names.
// Every gesture is resolved through ONE table (`gestures.dart`), and every
// coordinate a gesture writes comes back through the painter's own `unproject`
// -- the eye and the drop cannot disagree, which is the whole fix for the
// fifteen-minute drift (ISSUES 8.26).
//
// BUTTER. Motion is transform-only: a pan moves a `Transform` through a
// ValueNotifier while the painted child widget is untouched, so the lens does
// not repaint until the gesture rests and the focus commits. The ghost is its
// own layer for the same reason. Animated moves retarget rather than queue.

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/coordinate_entry.dart';
import '../core/coordinate_law.dart';
import '../core/exact.dart';
import '../core/projection.dart';
import '../edit/editor.dart';
import '../session/lens_catalog.dart';
import '../session/settings.dart';
import '../session/view_state.dart';
import '../stage/tile.dart';
import 'context_menu.dart';
import 'drag_ghost.dart';
import 'gestures.dart';
import 'law_context.dart';
import 'lens_painter.dart';
import 'theme.dart';
import 'tunables.dart';

/// Everything a hosted surface is looking at, as one value. A record, so adding
/// a seam costs a field and not five constructor arguments in four places.
typedef Surface = ({
  Editor editor,
  Settings settings,
  ViewBook views,
  Stage stage,
  // The card layer is consumed as two openers rather than as its factory: cards
  // already build on the lens vocabulary, so a lens that imported them back
  // would invert the layering for two function calls. The integrator hands over
  // `factory.objectCard` and `factory.frameCard` as tear-offs.
  CardOpener? objectCard,
  CardOpener? frameCard,
});

/// Opens the card for one record, by id.
typedef CardOpener = TileSpec Function(String id);

/// A surface where ONE COORDINATE HAS MORE THAN ONE POSITION (Don, 2026-08-28:
/// "if I have it zoomed and scrolled so the same time is visible in two spots,
/// an event can only appear at one of those spots"). A lens whose window shows
/// the same instant twice draws the mark at every one of them, hit-tests every
/// one of them, and rings every one of them. `project` answers with the first;
/// this answers with all, and the pointer picks the nearest.
///
/// A capability, tested by type -- never a lens recognised by name. Lifting it
/// onto `LensPainter.project` itself is a melt for whoever owns that seam.
abstract interface class ManyPositions {
  List<Offset> projectAll(Rational days);
}

/// Where [days] shows nearest to [at]: the same answer as `project` on a
/// surface that shows a time once, and the right one where it shows it twice.
Offset? projectNear(LensPainter? painter, Rational days, Offset at) {
  final all = painter is ManyPositions ? (painter! as ManyPositions).projectAll(days) : const [];
  if (all.isEmpty) return painter?.project(days);
  var best = all.first;
  for (final point in all) {
    if ((point - at).distanceSquared < (best - at).distanceSquared) best = point;
  }
  return best;
}

/// What a keyboard, a bar or a menu can ask of a view tile. Squad C's keyboard
/// map and context bar dispatch into this rather than reaching into the lens.
abstract class ViewTileController {
  String get tileId;
  Editor get editor;
  Stage get stage;
  CardOpener? get objectCard;
  CardOpener? get frameCard;

  /// The frame every write this surface makes is written ONTO.
  String? get primaryFrame;

  // --- The scene, for a lens that is a widget rather than a painter ---------
  //
  // A painter is handed a [LensScene]; a roster or graph lens builds its own
  // tree and needs the same inputs. They come from HERE rather than through a
  // callback the host has to remember to supply, so both kinds of lens read one
  // description of what the tile is looking at.

  /// Which lens this tile is. A tile IS a lens.
  String get lensId;

  Settings get settings;

  Tunable get tunable;

  /// What this view looks through -- boolean algebra over connections, never a
  /// filter.
  Projection get projection;

  /// Fact identities, so a selection names one occurrence rather than a series.
  Set<String> get selection;

  /// This lens's own view values, by its declared control keys.
  Map<String, Object?> get view;

  Rational get focusDays;

  /// Adds a frame to what this view projects -- what a roster lens offers when
  /// a state change carries an object out of the projected set.
  void project(String frameId);

  void pan(Rational days);
  void panPixels(Offset delta);
  void zoom(Rational factor);
  void jumpToNow();
  void resetLens();
  void select(String? identity);
  void openSelected();
  void deleteSelected();
  void createHere(String kind, Rational days, {Rational? endDays});

  /// A declared control's action, by key: what a `ControlSpec('action', ...)`
  /// and the keyboard map both send.
  void runAction(String action);
}

/// Live controllers by tile id, so the chrome can reach the focused surface:
/// `chrome.onAction = (tile, action) => viewTileControllers[tile]?.runAction(action)`.
final Map<String, ViewTileController> viewTileControllers = {};

typedef PainterBuilder = LensPainter Function(LensScene scene);

/// A roster lens is a widget tree, not a painter, and gets the controller so it
/// can select and open through the same door the time surfaces use.
typedef LensWidgetBuilder = Widget Function(BuildContext context, ViewTileController tile);

final Map<String, PainterBuilder> lensPainters = {};
final Map<String, LensWidgetBuilder> lensWidgets = {};

void registerLensPainter(String id, PainterBuilder build) => lensPainters[id] = build;

void registerLensWidget(String id, LensWidgetBuilder build) => lensWidgets[id] = build;

/// A refusal, stated where the surface would otherwise be empty. Rendering
/// nothing and saying nothing is indistinguishable from an empty calendar.
Widget statedRefusal(BuildContext context, String message, Tunable? read) {
  final theme = ChronoTheme.of(context);
  return ColoredBox(
    color: theme.paper,
    child: Padding(
      padding: EdgeInsets.all(
        tunableFrom(pointerTunableDefaults, read, 'pointer.refusalPad').toDouble(),
      ),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: theme.data.copyWith(color: theme.strong),
        ),
      ),
    ),
  );
}

class ViewTile extends StatefulWidget {
  const ViewTile({super.key, required this.tileId, required this.surface});

  final String tileId;
  final Surface surface;

  @override
  State<ViewTile> createState() => _ViewTileState();
}

class _ViewTileState extends State<ViewTile>
    with SingleTickerProviderStateMixin
    implements ViewTileController {
  final ValueNotifier<Offset> _panning = ValueNotifier(Offset.zero);
  final ValueNotifier<DragGhost?> _ghost = ValueNotifier(null);
  final ValueNotifier<MouseCursor> _cursor = ValueNotifier(SystemMouseCursors.basic);
  final Notches _wheel = Notches(), _zoomWheel = Notches();

  late final AnimationController _glide = AnimationController(vsync: this)..addListener(_glideTick);

  LensPainter? _painter;
  LawContext? _law;
  Size _size = Size.zero;
  Offset? _downAt;
  String _verb = '';

  /// ONE selection: the mark itself. The scene reads its identity, so selection
  /// survives a re-query and names one occurrence rather than a whole series.
  MarkHit? _grabbed, _selected;
  Duration? _lastClick;
  Offset _lastClickAt = Offset.zero;
  Rational _glideFrom = Rational.zero, _glideTarget = Rational.zero;

  @override
  void initState() {
    super.initState();
    viewTileControllers[widget.tileId] = this;
  }

  @override
  void dispose() {
    if (viewTileControllers[widget.tileId] == this) viewTileControllers.remove(widget.tileId);
    _glide.dispose();
    _panning.dispose();
    _ghost.dispose();
    _cursor.dispose();
    super.dispose();
  }

  // --- What the tile is looking at -------------------------------------------

  @override
  String get tileId => widget.tileId;

  @override
  Editor get editor => widget.surface.editor;

  @override
  Stage get stage => widget.surface.stage;

  @override
  CardOpener? get objectCard => widget.surface.objectCard;

  @override
  CardOpener? get frameCard => widget.surface.frameCard;

  Settings get _settings => widget.surface.settings;

  ViewBook get _views => widget.surface.views;

  ViewState get _state => _views.of(widget.tileId);

  @override
  String? get primaryFrame => _state.selection.primary();

  @override
  String get lensId => _state.lensId;

  @override
  Settings get settings => _settings;

  @override
  Tunable get tunable => _settings.tunable;

  @override
  Projection get projection => _state.projection();

  @override
  Set<String> get selection => {if (_selected != null) _selected!.identity};

  @override
  Map<String, Object?> get view => {
    for (final control in _state.spec.controls) control.key: _state.read(control.key, _settings),
  };

  @override
  Rational get focusDays => _focus;

  /// A row action means the plain selection speaks again, not the text.
  @override
  void project(String frameId) {
    _state.selection.toggle(frameId);
    _state.source = '';
    _views.touch();
  }

  Rational _tune(String key) => _settings.value(key);

  double _px(String key) => _tune(key).toDouble();

  Rational get _focus => _views.focusOf(widget.tileId);

  /// This lens's own value for a control it declares, or null when it declares
  /// no such control -- which is how the wheel and the snap tell a fine surface
  /// from a coarse one without ever testing a lens by name.
  Rational? _control(String key) =>
      _state.spec.controls.any((c) => c.key == key) ? _state.number(key, _settings) : null;

  Rational get _grain {
    final law = _law;
    return law == null ? Rational.zero : grainDays(law, _control('grain'));
  }

  Rational get _span {
    final law = _law;
    return law == null ? Rational.one : _state.spanDays(law.law, _settings);
  }

  // --- Building the surface --------------------------------------------------

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([editor.changes, _views, _settings, stage.listenable]),
    builder: (context, _) => LayoutBuilder(builder: (c, box) => _surface(c, box.biggest)),
  );

  Widget _surface(BuildContext context, Size size) {
    _size = size;
    final spec = _state.spec;
    final roster = lensWidgets[spec.id];
    // A roster lens is not a time surface: a drag here mints nothing, ever.
    if (!spec.isTimeSurface || roster != null) {
      return roster?.call(context, this) ??
          _refuse(context, 'No lens is registered for ${spec.title}.');
    }
    final frame = primaryFrame;
    final build = lensPainters[spec.id];
    final refusal = frame == null
        ? 'Nothing is projected. Choose a frame in the view bar.'
        : build == null
        ? 'No painter is registered for ${spec.title}.'
        : null;
    if (refusal != null) return _refuse(context, refusal);
    final law = editor.engine.lawOf(frame!);
    _law = LawContext(law);
    final painter = build!(_scene(context, size, law));
    _painter = painter;
    return Listener(
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: (_) => _release(),
      onPointerSignal: _signal,
      onPointerHover: _hover,
      child: ValueListenableBuilder<MouseCursor>(
        valueListenable: _cursor,
        builder: (context, cursor, child) => MouseRegion(cursor: cursor, child: child),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRect(
              child: ValueListenableBuilder<Offset>(
                valueListenable: _panning,
                // The painted child is built ONCE and reused: a pan moves the
                // transform above it and repaints nothing.
                child: RepaintBoundary(
                  child: CustomPaint(painter: painter, size: size),
                ),
                builder: (c, offset, child) => Transform.translate(offset: offset, child: child),
              ),
            ),
            ValueListenableBuilder<DragGhost?>(
              valueListenable: _ghost,
              builder: (c, ghost, _) => CustomPaint(
                painter: GhostPainter(ghost, ChronoTheme.of(c), _settings.tunable),
                size: size,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _refuse(BuildContext context, String message) =>
      statedRefusal(context, message, _settings.tunable);

  LensScene _scene(BuildContext context, Size size, CoordinateLaw law) => LensScene(
    engine: editor.engine,
    projection: projection,
    law: law,
    focusDays: focusDays,
    view: view,
    theme: ChronoTheme.of(context),
    nowDays: nowDays(),
    size: size,
    tunable: tunable,
    selection: selection,
  );

  // --- The pointer table -----------------------------------------------------

  void _down(PointerDownEvent event) {
    stage.focus(widget.tileId);
    final keys = HardwareKeyboard.instance;
    final hit = _painter?.markAt(event.localPosition);
    _grabbed = hit;
    _downAt = event.localPosition;
    _verb = pointerVerb(
      buttons: event.buttons,
      shift: keys.isShiftPressed,
      alt: keys.isAltPressed,
      onMark: hit != null,
      timeSurface: true,
    );
    if (_verb != 'menu') return;
    // The app owns this button everywhere, marks included (ISSUES 8.26).
    _release();
    showViewContextMenu(context, event.position, this, hit: hit, at: _daysAt(event.localPosition));
  }

  void _move(PointerMoveEvent event) {
    final from = _downAt;
    if (from == null) return;
    final travel = event.localPosition - from;
    if (_verb == 'pan') {
      _panning.value = travel;
      return;
    }
    if (travel.distance < _px('pointer.dragThreshold')) return;
    _ghost.value = _ghostFor(from, event.localPosition);
  }

  void _up(PointerUpEvent event) {
    final from = _downAt, verb = _verb, grabbed = _grabbed;
    final travel = from == null ? Offset.zero : event.localPosition - from;
    _release();
    if (from == null) return;
    if (verb == 'pan') {
      final days = _daysForPixels(travel);
      return days == null ? null : pan(days);
    }
    if (travel.distance < _px('pointer.dragThreshold')) return _click(event);
    final at = _daysAt(event.localPosition), start = _daysAt(from);
    if (at == null || start == null) return;
    if (verb == 'move' && grabbed != null) {
      editor.moveFact(grabbed.fact, at, timed: _control('grain') != null);
    } else if (verb == 'create') {
      createHere('event', start, endDays: at);
    }
  }

  void _release() {
    _downAt = null;
    _verb = '';
    _grabbed = null;
    _ghost.value = null;
    _panning.value = Offset.zero;
  }

  /// A click is the cheap glance: it selects, and RE-CLICKING THE SELECTED
  /// CLEARS, so a click is its own undo. A second click inside the double-click
  /// window opens the object's card instead.
  ///
  /// The window is measured on the POINTER'S OWN CLOCK (`event.timeStamp`),
  /// never the wall clock: the surface must agree with whatever clock is
  /// driving it, and a wall-clock read is also untestable.
  void _click(PointerUpEvent event) {
    final at = event.localPosition;
    final hit = _painter?.markAt(at);
    final again =
        _lastClick != null &&
        (event.timeStamp - _lastClick!).inMilliseconds < _px('pointer.doubleClickMillis') &&
        (at - _lastClickAt).distance < _px('pointer.dragThreshold');
    _lastClick = event.timeStamp;
    _lastClickAt = at;
    if (again) {
      select(hit?.identity);
      return openSelected();
    }
    select(hit == null || hit.identity == _selected?.identity ? null : hit.identity);
  }

  void _hover(PointerHoverEvent event) =>
      _cursor.value = _painter?.markAt(event.localPosition) == null
      ? SystemMouseCursors.precise
      : SystemMouseCursors.click;

  // --- Wheel -----------------------------------------------------------------

  void _signal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final keys = HardwareKeyboard.instance;
    final notch = _px('pointer.wheelNotch');
    final sideways = keys.isShiftPressed || event.scrollDelta.dx.abs() > event.scrollDelta.dy.abs();
    final raw = keys.isShiftPressed || event.scrollDelta.dx == 0
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    if (keys.isControlPressed) {
      final steps = _zoomWheel.take(-raw, notch);
      return steps == 0 ? null : zoom(_tune('pointer.zoomStep').pow(steps));
    }
    final steps = _wheel.take(raw, notch);
    if (steps == 0) return;
    // A lens with a cycle moves ONE CYCLE per notch, spun rather than jumped.
    final cycle = _control('cycleDays');
    if (cycle != null) return _glideTowards(_focus + cycle * Rational.fromInt(steps));
    // A lens with a grain is a fine surface: down the rail it scrolls
    // continuously, THROUGH midnight, in pixels -- there is no seam to page
    // across -- while ACROSS it the axis is days, and a notch there is one whole
    // day, so a sideways gesture is exactly reversible by making it back.
    final law = _law;
    if (_control('grain') != null && law != null) {
      final days = sideways
          ? law.dayDays * Rational.fromInt(steps)
          : _daysForPixels(Offset(0, -notch * steps));
      return days == null ? null : pan(days);
    }
    pan(_span * _tune('pointer.panStepFraction') * Rational.fromInt(steps));
  }

  // --- Coordinates -----------------------------------------------------------

  /// The exact day under a point, snapped to this lens's own grain. Every write
  /// this surface makes goes through here, so the ghost's label, the drop and
  /// the pixels are one derivation.
  Rational? _daysAt(Offset at) {
    final exact = _painter?.unproject(at);
    return exact == null ? null : snapDays(exact, _grain);
  }

  /// How far the focus must move when the content moves by [delta]. Asked of the
  /// painter, so it is right on a ring as well as on a rail.
  Rational? _daysForPixels(Offset delta) {
    final painter = _painter;
    if (painter == null || _size.isEmpty) return null;
    final centre = Offset(_size.width / 2, _size.height / 2);
    final here = painter.unproject(centre), there = painter.unproject(centre - delta);
    return here == null || there == null ? null : there - here;
  }

  DragGhost? _ghostFor(Offset from, Offset to) {
    final painter = _painter, law = _law, frame = primaryFrame;
    final start = _daysAt(from), end = _daysAt(to);
    if (painter == null || law == null || frame == null || start == null || end == null) {
      return null;
    }
    final anchor = projectNear(painter, start, from) ?? from;
    final head = projectNear(painter, end, to) ?? to;
    final grabbed = _grabbed;
    return (
      rect: _verb == 'move' && grabbed != null
          ? grabbed.bounds.shift(head - anchor)
          : Rect.fromPoints(anchor, head),
      // The live coordinate under the cursor, in the frame's own law.
      label: formatCoordinateEntry(
        Coordinate.fromJson(editor.engine.daysCoordinate(frame, end)),
        law.law,
      ),
      creating: _verb == 'create',
    );
  }

  // --- The controller --------------------------------------------------------

  @override
  void pan(Rational days) => _views.setFocus(widget.tileId, _focus + days);

  @override
  void panPixels(Offset delta) {
    final days = _daysForPixels(delta);
    if (days != null) pan(days);
  }

  /// Zoom means one thing on every surface: more or less time on screen. A lens
  /// that declares a [LensSpec.scaleKey] scales THAT -- Intimate stretches its
  /// hour rail, which shows LESS time as it grows, so the key moves inversely --
  /// and a lens that declares none scales whichever number controls its own span
  /// formula reads. Neither branch tests a lens by name.
  @override
  void zoom(Rational factor) {
    final scale = _state.spec.scaleKey;
    if (scale != null) {
      _grow(scale, Rational.one / factor);
      return _views.touch();
    }
    for (final control in _state.spec.controls) {
      if (control.kind != 'number') continue;
      if (!RegExp('\\b${control.key}\\b').hasMatch(_state.spec.spanFormula)) continue;
      _grow(control.key, factor);
    }
    _views.touch();
  }

  void _grow(String key, Rational by) {
    final next = _state.number(key, _settings) * by;
    _state.write(key, next < Rational.one ? Rational.one : Rational(next.round()));
  }

  /// A law that does not map to a clock HAS NO NOW, so this refuses rather than
  /// inventing a place to jump to.
  @override
  void jumpToNow() {
    if (_law?.mapsToClock == true) _glideTowards(nowDays());
  }

  @override
  void resetLens() {
    _state.resetView();
    _views.touch();
  }

  @override
  void select(String? identity) => setState(
    () => _selected = identity == null
        ? null
        : _painter?.hits.where((hit) => hit.identity == identity).firstOrNull,
  );

  @override
  void openSelected() {
    final hit = _selected, open = objectCard;
    if (hit != null && open != null) stage.open(open(hit.fact.event.id));
  }

  /// Undoable, and no confirmation anywhere: reversibility over interruption.
  @override
  void deleteSelected() {
    final hit = _selected;
    if (hit == null) return;
    editor.deleteObject(hit.fact.event.id);
    select(null);
  }

  @override
  void createHere(String kind, Rational days, {Rational? endDays}) {
    final frame = primaryFrame, open = objectCard;
    if (frame == null) return;
    final id = editor.createAt(frame, days, endDays, kind: kind);
    // The card opens on the new object and holds the draft: a create lands in
    // an editor with the title ready, not on a nameless block.
    if (open != null) stage.open(open(id));
  }

  @override
  void runAction(String action) => switch (action) {
    'zoomIn' => zoom(Rational.one / _tune('pointer.zoomStep')),
    'zoomOut' => zoom(_tune('pointer.zoomStep')),
    'delete' => deleteSelected(),
    'today' => jumpToNow(),
    'reset' => resetLens(),
    _ => null,
  };

  // --- Animated focus: retarget, never queue ---------------------------------

  void _glideTowards(Rational target) {
    _glideFrom = _focus;
    _glideTarget = target;
    _glide.duration = Duration(milliseconds: _tune('motion.duration').round().toInt());
    // Retarget: the run restarts from where the focus IS, so a second notch
    // during a spin redirects it rather than stacking another animation.
    _glide.forward(from: 0);
  }

  void _glideTick() {
    if (!mounted) return;
    final curve = Cubic(
      _px('motion.curve.x1'),
      _px('motion.curve.y1'),
      _px('motion.curve.x2'),
      _px('motion.curve.y2'),
    );
    final progress = Rational.parse(curve.transform(_glide.value).toStringAsFixed(6));
    _views.setFocus(widget.tileId, _glideFrom + (_glideTarget - _glideFrom) * progress);
  }
}

/// The view tile as a stage tile. `type` is `view`, which is the only thing the
/// stage knows about it.
TileSpec viewTileSpec(String id, Surface surface) => TileSpec(
  id: id,
  type: 'view',
  klass: 'lens',
  title: lensCatalog[surface.views.of(id).lensId]?.title ?? 'View',
  build: (_) => ViewTile(tileId: id, surface: surface),
);
