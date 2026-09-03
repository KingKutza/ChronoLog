// The chrome substrate: what every bar, menu and form is made of.
//
// Don's standing complaint about the old surface was that it read as "a very
// programmer interface — menus take a lot of space with arcane settings that
// render as literals". So there is no raw number field, no comma string and no
// bare record id here: a setting is a NAMED control with a designed body, and a
// formula gets a source field that evaluates as you type and says why when it
// will not. Every size and duration below is read from a named setting.
//
// These are functions rather than widget classes on purpose: a control is a
// shape, not a lifecycle, and the scaffolding of twenty widget classes is
// twenty classes of chaff.

import 'package:flutter/material.dart';

import '../core/exact.dart';
import '../core/math.dart';
import '../edit/editor.dart';
import '../lens/theme.dart';
import '../session/lens_catalog.dart';
import '../session/settings.dart';
import '../session/view_state.dart';
import '../stage/tile.dart';
import 'menus.dart';

/// Chrome numbers, as named settings. Motion lives in the lens defaults (one
/// ratified curve for the whole app), so nothing here restates it.
/// ONE SPACING UNIT (ruled 2026-08-28). Every gap, pad, height and radius below
/// is a multiple of `chrome.unit`, WRITTEN as that multiplication rather than as
/// the number it comes to, so the rhythm is visible in the settings file and
/// moving the unit moves the whole grid. Type is one scale off `chrome.body` by
/// the same rule.
const Map<String, String> chromeTunableDefaults = {
  // Nothing reads this one: it is the grid ITSELF, declared so the settings
  // card can name it and so the suite can hold every spacing below to a whole
  // multiple of it. A number that only a test reads still does a job.
  'chrome.unit': '2',
  'chrome.barHeight': '2 * 16',
  'chrome.gap': '2 * 3',
  'chrome.pad': '2 * 5',
  'chrome.corner': '2 * 3',
  'chrome.hair': '1',
  'chrome.focusRing': '3/2',
  // The least a control may be: a hand's target, not a glyph's box.
  'chrome.hit': '2 * 14',
  'chrome.label': '13 * 6/7',
  'chrome.body': '13',
  'chrome.title': '13 * 8/7',
  'chrome.menuWidth': '2 * 130',
  'chrome.rowHeight': '2 * 14',
  'chrome.labelCap': '28',
  // HOW WIDE A READING MAY GET (ISSUES 9.2: "we need some fixed width or
  // overflow rule for the projecting-frame drop-down so it does not force the
  // lenses to first initials"). A reading is a VALUE, and a value grows with
  // the document; the bar beside it does not. Ten projected frames are a
  // sentence, and a sentence on a bar is capped and read in full in the drop.
  'chrome.readingWidth': '2 * 130',
  'chrome.frameRows': '12',
  // A control is GHOST by default: it earns a ground under the pointer and a
  // tint when it is the one in force. A border on every button is what made the
  // surface read as boxes drawn on boxes.
  'chrome.hoverWash': '1/16',
  'chrome.activeWash': '0.14',
};

/// Chrome text settings: not arithmetic, so not tunables.
const Map<String, String> chromeTextDefaults = {'theme.name': 'paper'};

/// What the chrome is looking at. One object, so no bar plumbs five
/// constructor arguments through three widgets.
class Chrome {
  Chrome({
    required this.settings,
    required this.stage,
    required this.views,
    this.editor,
    this.title = 'ChronoLog',
    this.cards = const {},
    this.viewTile,
    this.openFrame,
    this.openSettings,
    this.onAction,
  });

  final Settings settings;
  final Stage stage;
  final ViewBook views;
  final Editor? editor;
  final String title;

  /// What the document menu can open, by id. The bar opens tiles; it never
  /// holds the form itself.
  final Map<String, TileSpec Function()> cards;

  /// Makes a view tile for a tile id -- supplied by whoever owns the lenses.
  final TileSpec Function(String id)? viewTile;

  /// Opens a frame's own card. Absent, a frame's name in a bar is a label
  /// rather than a link -- stated, never a dead click.
  final void Function(String frameId)? openFrame;

  /// Opens the settings card that governs one surface -- `stage`, `chrome`, a
  /// lens id -- so the settings sub-card is reachable from the surface it acts
  /// on (ISSUES 9.1, Don's ruling on the settings surface). A factory with no
  /// sub-card for that area opens the main settings card; absent entirely, the
  /// menu row SAYS SO rather than sitting there doing nothing.
  final void Function(String area)? openSettings;

  /// A lens's declared action, dispatched by key. Absent, the control says so
  /// rather than pretending to work.
  final void Function(String tileId, String action)? onAction;

  double px(String key) => settings.value(key).toDouble();

  Duration get motion => Duration(milliseconds: settings.value('motion.duration').round().toInt());

  /// The ratified curve, as four named settings rather than a magic string.
  Curve get curve => Cubic(
    px('motion.curve.x1'),
    px('motion.curve.y1'),
    px('motion.curve.x2'),
    px('motion.curve.y2'),
  );

  /// The focused view tile's state, or null when no view tile is on the stage.
  ViewState? get focusedView {
    final id = stage.focusedViewTile;
    return id == null ? null : views.of(id);
  }

  /// Everything a bar redraws for.
  Listenable get pulse => Listenable.merge([settings, views, stage.listenable, editor?.changes]);
}

class ChromeScope extends InheritedWidget {
  const ChromeScope({super.key, required this.chrome, required super.child});

  final Chrome chrome;

  static Chrome of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChromeScope>()!.chrome;

  @override
  bool updateShouldNotify(ChromeScope old) => old.chrome != chrome;
}

TextStyle labelStyle(BuildContext c, {Color? color}) => ChronoTheme.of(c).ui.copyWith(
  fontSize: ChromeScope.of(c).px('chrome.label'),
  color: color ?? ChronoTheme.of(c).strong,
);

TextStyle bodyStyle(BuildContext c, {Color? color}) => ChronoTheme.of(c).ui
    .copyWith(fontSize: ChromeScope.of(c).px('chrome.body'), color: color ?? ChronoTheme.of(c).ink);

TextStyle dataStyle(BuildContext c, {Color? color}) => ChronoTheme.of(c).data
    .copyWith(fontSize: ChromeScope.of(c).px('chrome.body'), color: color ?? ChronoTheme.of(c).ink);

/// The one chip every control wears: GHOST by default -- no border, no ground --
/// taking an ink wash under the pointer and the primary's own tint when it is
/// the choice in force. The label is small and muted; the control sits beside
/// it.
Widget controlChip(
  BuildContext c, {
  String label = '',
  required Widget child,
  VoidCallback? onTap,
  void Function(Offset at)? onMenu,
  bool active = false,
  bool inert = false,
  bool button = false,
  String? hint,
  String? semantics,
}) {
  final chrome = ChromeScope.of(c);
  final theme = ChronoTheme.of(c);
  final live = onTap != null || inert;
  final body = _Chip(
    active: active,
    onTap: onTap,
    onMenu: onMenu,
    button: button,
    semantics: semantics,
    // A chip is a tile's content and a tile is any width, so the chip NARROWS
    // rather than overflowing: the name ellipsizes and the control scrolls
    // inside its own body. Nothing is clipped away silently -- what does not fit
    // is still reachable, which is the same rule the bars follow.
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label.isNotEmpty)
          Flexible(
            child: Padding(
              padding: EdgeInsets.only(right: chrome.px('chrome.gap')),
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: labelStyle(c, color: live ? theme.strong : theme.hair),
              ),
            ),
          ),
        Flexible(
          child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: child),
        ),
      ],
    ),
  );
  // A HINT IS FOR A POINTER. Tooltip arms a long-press of its own by default,
  // which on a touch surface would take the press the tile needs for its handle
  // (ruled 9.1: long-press anywhere in the tile reveals it). Manual leaves the
  // hover trigger exactly as it was and gives the press back to the tile.
  return hint == null
      ? body
      : Tooltip(message: hint, triggerMode: TooltipTriggerMode.manual, child: body);
}

/// The chip's body and its three states. Hover IS a state, so it is a widget
/// with one; and nothing here snaps between states -- every change of ground
/// arrives on the ratified curve (ruled 2026-08-28).
class _Chip extends StatefulWidget {
  const _Chip({
    required this.active,
    required this.onTap,
    this.onMenu,
    this.button = false,
    this.semantics,
    required this.child,
  });

  final bool active;

  /// A control that IS a button says so even when it cannot be pressed right
  /// now: a disabled Undo is still an Undo, and a reader told nothing about it
  /// is told the bar is shorter than it is.
  final bool button;

  final VoidCallback? onTap;

  /// The words for a chip whose visible mark is a GLYPH. A reader is told the
  /// verb; the eye gets the mark. Absent, the chip's own text is the words.
  final String? semantics;

  /// The chip's own right-click, at the point it was pressed. A chip that
  /// offers verbs offers them where the hand already is.
  final void Function(Offset at)? onMenu;

  final Widget child;

  @override
  State<_Chip> createState() => _ChipState();
}

class _ChipState extends State<_Chip> {
  bool _over = false;

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeScope.of(context);
    final theme = ChronoTheme.of(context);
    final hovering = _over && widget.onTap != null;
    final wash = widget.active
        ? theme.primary.withValues(alpha: chrome.px('chrome.activeWash'))
        : (hovering
              ? theme.ink.withValues(alpha: chrome.px('chrome.hoverWash'))
              : const Color(0x00000000));
    final body = AnimatedContainer(
      duration: chrome.motion,
      curve: chrome.curve,
      constraints: BoxConstraints(minHeight: chrome.px('chrome.hit')),
      padding: EdgeInsets.symmetric(horizontal: chrome.px('chrome.pad')),
      decoration: BoxDecoration(
        color: wash,
        border: Border.all(
          color: widget.active ? theme.primary : const Color(0x00000000),
          width: chrome.px('chrome.hair'),
        ),
        borderRadius: BorderRadius.circular(chrome.px('chrome.corner')),
      ),
      child: widget.child,
    );
    final live = widget.onTap != null || widget.onMenu != null;
    if (!live && !widget.button) return body;
    // A CHIP IS A BUTTON AND SAYS SO (ISSUES 9.1, found writing the stage
    // lights). Every chip in the chrome tapped through a bare GestureDetector:
    // invisible to assistive tech and to anything looking for a button. The
    // merge makes the chip ONE node carrying its own words, so what a reader is
    // told and what the eye reads are the same thing -- and the look is
    // untouched, because semantics paint nothing.
    final gestures = !live
        ? body
        : MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _over = true),
            onExit: (_) => setState(() => _over = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              onSecondaryTapUp: widget.onMenu == null
                  ? null
                  : (details) => widget.onMenu!(details.globalPosition),
              child: body,
            ),
          );
    final said = widget.semantics;
    return said == null
        // The chip's own words ARE its name: one node, carrying the text it
        // draws and the flag that says it can be pressed.
        ? MergeSemantics(
            child: Semantics(button: true, enabled: widget.onTap != null, child: gestures),
          )
        // A glyph is not a word. The node says the verb instead of spelling the
        // mark, so a reader is told what the button does.
        : Semantics(
            button: true,
            enabled: widget.onTap != null,
            label: said,
            excludeSemantics: true,
            child: gestures,
          );
  }
}

Widget _step(BuildContext c, String glyph, String label, VoidCallback onTap) => Semantics(
  label: label,
  button: true,
  child: InkWell(
    onTap: onTap,
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: ChromeScope.of(c).px('chrome.gap')),
      child: Text(glyph, style: dataStyle(c, color: ChronoTheme.of(c).strong)),
    ),
  ),
);

/// A number with a name and two hairline steppers -- never a bare spinner.
Widget namedNumber(
  BuildContext c,
  String label,
  Rational value,
  void Function(Rational) onChanged, {
  Rational? min,
  Rational? max,
  String? hint,
}) {
  void step(int by) {
    var next = value + Rational.fromInt(by);
    if (min != null && next < min) next = min;
    if (max != null && next > max) next = max;
    onChanged(next);
  }

  return controlChip(
    c,
    label: label,
    hint: hint,
    inert: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _step(c, '−', 'Less $label', () => step(-1)),
        Text(value.toDecimal(2), style: dataStyle(c)),
        _step(c, '+', 'More $label', () => step(1)),
      ],
    ),
  );
}

/// A truth value as a hairline track, not a platform switch.
Widget namedToggle(BuildContext c, String label, bool value, void Function(bool) onChanged) {
  final chrome = ChromeScope.of(c);
  final theme = ChronoTheme.of(c);
  final size = chrome.px('chrome.label');
  return controlChip(
    c,
    label: label,
    active: value,
    onTap: () => onChanged(!value),
    child: AnimatedContainer(
      duration: chrome.motion,
      curve: chrome.curve,
      width: size * 2,
      height: size,
      alignment: value ? Alignment.centerRight : Alignment.centerLeft,
      decoration: BoxDecoration(
        border: Border.all(color: value ? theme.primary : theme.hair),
        borderRadius: BorderRadius.circular(size),
      ),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: value ? theme.primary : theme.hair,
        ),
      ),
    ),
  );
}

/// A choice as a segmented run of names -- the active one carries the ink.
Widget namedChoice(
  BuildContext c,
  String label,
  String value,
  List<ControlOption> options,
  void Function(String) onChanged,
) {
  final chrome = ChromeScope.of(c);
  final theme = ChronoTheme.of(c);
  return controlChip(
    c,
    label: label,
    inert: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final option in options)
          InkWell(
            onTap: () => onChanged(option.value),
            child: AnimatedContainer(
              duration: chrome.motion,
              curve: chrome.curve,
              padding: EdgeInsets.symmetric(horizontal: chrome.px('chrome.gap')),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: option.value == value ? theme.primary : Colors.transparent,
                    width: chrome.px('chrome.focusRing'),
                  ),
                ),
              ),
              child: Text(
                option.label,
                style: bodyStyle(c, color: option.value == value ? theme.ink : theme.strong),
              ),
            ),
          ),
      ],
    ),
  );
}

/// A glyph or word that does something. A disabled one carries its reason.
Widget namedAction(
  BuildContext c,
  String label, {
  String? glyph,
  VoidCallback? onTap,
  void Function(Offset at)? onMenu,
  String? hint,
}) => controlChip(
  c,
  hint: hint ?? label,
  onTap: onTap,
  onMenu: onMenu,
  button: true,
  semantics: glyph == null ? null : label,
  child: Text(
    glyph ?? label,
    // A WORD IS PROSE; a glyph is a mark. The data face carries coordinates,
    // counts and times, and nothing else -- a button that wore it because it
    // was one call away is why the whole chrome came up in a typewriter.
    style: (glyph == null ? bodyStyle : dataStyle)(
      c,
      color: onTap == null ? ChronoTheme.of(c).hair : ChronoTheme.of(c).ink,
    ),
  ),
);

/// One control on a bar: what it is called, the control, and the narrower form
/// it wears when the bar runs out of room. A control that cannot narrow gives
/// no compact form and overflows instead of lying about its size.
typedef BarItem = ({String label, Widget full, Widget compact});

BarItem barItem(String label, Widget full, {Widget? compact}) =>
    (label: label, full: full, compact: compact ?? full);

/// A glyph control. One that already wears a glyph has nothing narrower to
/// become; one that wears its name narrows to its own initial.
BarItem barAction(
  BuildContext c,
  String label, {
  String? glyph,
  VoidCallback? onTap,
  String? hint,
}) {
  final full = namedAction(c, label, glyph: glyph, onTap: onTap, hint: hint);
  return (
    label: label,
    full: full,
    compact: glyph != null
        ? full
        : namedAction(
            c,
            label,
            glyph: label.isEmpty ? '.' : label.substring(0, 1),
            onTap: onTap,
            hint: hint,
          ),
  );
}

/// What one layout of a run found out: the width it needed, and which controls
/// it could not fit.
typedef RunFit = ({double required, List<int> folded, List<double> widths});

/// THE ONE BAR LAYOUT (ruled 2026-08-28). Controls lay out from the width the
/// bar actually gets: full labels while they fit, then every control in its
/// compact form, then the ones that still will not fit fold into a menu that
/// holds THE CONTROLS THEMSELVES, so nothing is ever merely clipped away.
/// [pinned] is where the trailing group starts; it stays against the right end
/// and folds last. All three bars wear this -- a bar that patches its own Row
/// is the instance the rule exists to kill.
///
/// Only ONE form of each control is ever in the tree: what the bar shows is
/// what is there, so a control is never found twice by anything looking.
class BarRun extends StatefulWidget {
  const BarRun({super.key, required this.items, this.pinned});

  final List<BarItem> items;
  final int? pinned;

  @override
  State<BarRun> createState() => _BarRunState();
}

class _BarRunState extends State<BarRun> {
  final ValueNotifier<List<int>> _folded = ValueNotifier(const []);
  bool _scheduled = false;

  /// WHICH CONTROLS ARE IN THEIR COMPACT FORM, and only those (ISSUES 9.2: "we
  /// need some fixed width or overflow rule for the projecting-frame drop-down
  /// so it does not force the lenses to first initials"). Compaction used to be
  /// one flag over the whole run, so one wide reading took every lens chip down
  /// to its initial with it. The rule is: give up the WIDEST control first, and
  /// only as many as it takes.
  Set<int> _tight = {};

  /// What each control measured in its FULL form, last time it was in one.
  /// Coming back out of the compact form waits for that much room, so a run
  /// cannot oscillate across the width where the two forms disagree -- and it
  /// is dropped whenever the run itself changes, because a measurement of a run
  /// that no longer exists is not a measurement of this one.
  final Map<int, double> _full = {};

  @override
  void dispose() {
    _folded.dispose();
    super.dispose();
  }

  /// A HYSTERESIS THRESHOLD IS A MEASUREMENT OF SOMETHING (ISSUES 9.1: "the
  /// lens/selector bar went to first letters with plenty of room, and only
  /// expanding and recontracting the tile fixed it"). `_wide` is the width the
  /// FULL run needed, and the full run is never laid out while compact -- so a
  /// bar that measured wide once carried that threshold forever, refusing to
  /// come back for room enough for today's controls but not for a ghost's.
  /// When the thing measured changes, the measurement is void: it is dropped
  /// here and retaken on the next frame, which is the expand-and-recontract
  /// dance done by the bar instead of by the hand.
  @override
  void didUpdateWidget(BarRun old) {
    super.didUpdateWidget(old);
    if (_signature(old) == _signature(widget)) return;
    _tight = {};
    _full.clear();
  }

  /// What the run IS, as far as its width is concerned: which controls, in what
  /// order, and where the trailing group starts.
  static String _signature(BarRun run) =>
      '${run.pinned} ${[for (final item in run.items) item.label].join(' ')}';

  /// Reported from layout, applied after the frame: a notifier or a setState
  /// during layout would rebuild the very children being laid out.
  /// Whether this control HAS a narrower form to give. A control that declared
  /// none is handed back its own full form by [barItem], so compacting it would
  /// change nothing -- and a run that spent its one step per frame on it would
  /// never reach the control that could actually make room.
  bool _compactable(int index) =>
      index < widget.items.length &&
      !identical(widget.items[index].full, widget.items[index].compact);

  void _report(RunFit fit, double available) {
    for (var index = 0; index < fit.widths.length; index++) {
      if (!_tight.contains(index)) _full[index] = fit.widths[index];
    }
    var next = _tight;
    if (fit.required > available) {
      // ONE STEP: the widest control still wearing its full form gives that
      // form up. If the run still does not fit, the next frame takes the next
      // widest -- so the bar spends exactly as much of its vocabulary as the
      // room costs, and never a chip more.
      var widest = -1;
      for (var index = 0; index < fit.widths.length; index++) {
        if (_tight.contains(index) || !_compactable(index)) continue;
        if (widest < 0 || fit.widths[index] > fit.widths[widest]) widest = index;
      }
      if (widest >= 0) next = {..._tight, widest};
    } else {
      // Room came back: the first compacted control whose remembered full form
      // fits in it gets its name back, one per frame, by the same rule.
      for (final index in _tight) {
        final full = _full[index];
        if (full == null || fit.required - fit.widths[index] + full > available) continue;
        next = {..._tight}..remove(index);
        break;
      }
    }
    final moved = next.length != _tight.length || !next.containsAll(_tight);
    if (_scheduled || (!moved && _same(fit.folded, _folded.value))) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      _folded.value = fit.folded;
      if (moved) setState(() => _tight = next);
    });
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeScope.of(context);
    final items = widget.items;
    return ClipRect(
      child: CustomMultiChildLayout(
        delegate: _BarRunLayout(
          count: items.length,
          pinned: widget.pinned ?? items.length,
          gap: chrome.px('chrome.gap'),
          report: _report,
        ),
        children: [
          for (final (index, item) in items.indexed)
            LayoutId(id: index, child: _tight.contains(index) ? item.compact : item.full),
          LayoutId(
            id: #more,
            child: ValueListenableBuilder<List<int>>(
              valueListenable: _folded,
              builder: (context, folded, _) => ChronoMenu(
                label: 'More controls',
                glyph: '\u22ef',
                body: (context, close) => Padding(
                  padding: EdgeInsets.all(chrome.px('chrome.pad')),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final index in folded)
                        if (index < items.length)
                          Padding(
                            padding: EdgeInsets.only(bottom: chrome.px('chrome.gap')),
                            child: items[index].full,
                          ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BarRunLayout extends MultiChildLayoutDelegate {
  _BarRunLayout({
    required this.count,
    required this.pinned,
    required this.gap,
    required this.report,
  });

  final int count, pinned;
  final double gap;
  final void Function(RunFit fit, double available) report;

  @override
  void performLayout(Size size) {
    final loose = BoxConstraints.loose(size);
    final sizes = [for (var index = 0; index < count; index++) layoutChild(index, loose)];
    final more = layoutChild(#more, loose);
    var tall = more.height;
    for (final of in sizes) {
      if (of.height > tall) tall = of.height;
    }
    // A BAR THAT IS GIVEN HEIGHT USES IT: the run wraps onto as many rows as
    // the tile actually has, rather than painting one row and a wide emptiness.
    final rows = tall <= 0 ? 1 : (size.height / tall).floor().clamp(1, count + 1);
    final away = Offset(size.width + size.height + 1000, 0);
    double top(int row, Size of) => row * tall + (tall - of.height) / 2;

    /// One arrangement: the trailing group pinned to the right of the first
    /// row, the leading run flowing across the rows, and what would not fit.
    (Map<int, Offset>, List<int>, Offset?) place(bool reserve) {
      final at = <int, Offset>{};
      final folded = <int>[];
      var right = size.width;
      for (var index = count - 1; index >= pinned; index--) {
        if (right - sizes[index].width < 0) {
          folded.add(index);
          continue;
        }
        right -= sizes[index].width;
        at[index] = Offset(right, top(0, sizes[index]));
        right -= gap;
      }
      var row = 0, x = 0.0;
      var full = false;
      for (var index = 0; index < pinned; index++) {
        final limit =
            (row == 0 ? right : size.width) - (reserve && row == rows - 1 ? more.width + gap : 0);
        if (full || (x > 0 && x + sizes[index].width > limit)) {
          row += 1;
          x = 0;
        }
        if (row >= rows || x + sizes[index].width > limit) {
          full = true;
          folded.add(index);
          continue;
        }
        at[index] = Offset(x, top(row, sizes[index]));
        x += sizes[index].width + gap;
      }
      final anchor = folded.isEmpty ? null : Offset(x, top(row >= rows ? rows - 1 : row, more));
      return (at, folded, anchor);
    }

    var (at, folded, anchor) = place(false);
    if (folded.isNotEmpty) (at, folded, anchor) = place(true);
    folded.sort();
    for (var index = 0; index < count; index++) {
      positionChild(index, at[index] ?? away);
    }
    positionChild(#more, anchor ?? away);
    report((
      required: sizes.isEmpty
          ? 0
          : sizes.fold(0.0, (total, of) => total + of.width) + gap * (count - 1),
      folded: folded,
      widths: [for (final of in sizes) of.width],
    ), size.width * rows);
  }

  @override
  bool shouldRelayout(_BarRunLayout old) =>
      old.count != count || old.pinned != pinned || old.gap != gap;
}

/// The one bar body: a hairline-ruled strip carrying one [BarRun]. All three
/// bars wear it, so they read as one instrument -- and none of them can
/// overflow, at any width or any number of lenses.
Widget barShell(BuildContext c, List<BarItem> leading, {List<BarItem> trailing = const []}) {
  final chrome = ChromeScope.of(c);
  final theme = ChronoTheme.of(c);
  // No fixed height: the bar takes the thickness its tile was given and the
  // run reflows into it. It fills or it shrinks; it never paints a wide empty
  // field with three glyphs in the corner (ruled 2026-08-28).
  // THE BAR'S OWN RIGHT-CLICK OPENS THE BAR'S OWN SETTINGS (ISSUES 9.1, Don's
  // ruling on the settings surface): a chip in the run answers first, so this
  // is the surface between and around them.
  return GestureDetector(
    behavior: HitTestBehavior.translucent,
    onSecondaryTapUp: (details) =>
        showChronoMenu(c, details.globalPosition, settingsRows(c, 'chrome', 'The bars')),
    child: Container(
    constraints: BoxConstraints(minHeight: chrome.px('chrome.barHeight')),
    padding: EdgeInsets.symmetric(horizontal: chrome.px('chrome.pad')),
    decoration: BoxDecoration(
      color: theme.surface,
      border: Border(
        bottom: BorderSide(color: theme.hair, width: chrome.px('chrome.hair')),
      ),
    ),
      child: BarRun(items: [...leading, ...trailing], pinned: leading.length),
    ),
  );
}

/// THE SETTINGS DOOR, ON THE SURFACE IT GOVERNS (ISSUES 9.1, Don's ruling on
/// the settings surface): "sub-cards are also launched from right-click context
/// menus at the relevant parts of the app -- the lens's own menu opens that
/// lens's settings card, the stage's opens the stage's". [area] names the
/// surface and [said] is what it is called in words. With no door registered
/// the rows STATE that rather than sitting there dead.
List<MenuRow> settingsRows(BuildContext c, String area, String said) {
  final open = ChromeScope.of(c).openSettings;
  if (open == null) {
    return [menuRow('$said: no settings card is registered to open.', null)];
  }
  return [
    menuRow('$said — settings', () => open(area)),
    // Every sub-card carries a way back to the main card; so does every door
    // into one, or the family is a set of cul-de-sacs.
    menuRow('All settings', () => open('')),
  ];
}

/// ONE FIELD CHROME (ISSUES 9.2, Don, on the weight formula box: "It is a
/// blank text box with a background the same as the window and no border, that
/// is why I did not see it").
///
/// A FIELD LOOKS LIKE A FIELD EVERYWHERE. Three classes drew their own
/// decoration and a fourth drew none, so the one-math entry box was invisible
/// on six surfaces while the card fields beside it wore a hairline. This is the
/// one decoration every text entry in the program goes through -- hairline
/// boundary at rest, the corner radius the rest of the chrome uses, the hint in
/// hair, and the primary's own colour on the border when what is written will
/// not read. A new field class cannot be born borderless, because there is
/// nowhere left to spell a border by hand.
///
/// [padding] is the only thing a site may say for itself: density is what
/// separates a card's field from a bar's, and it is a setting at every caller.
InputDecoration fieldChrome(
  BuildContext c, {
  String hint = '',
  bool refused = false,
  double? padding,
}) {
  final chrome = ChromeScope.of(c);
  final theme = ChronoTheme.of(c);
  final border = OutlineInputBorder(
    borderSide: BorderSide(
      color: refused ? theme.primary : theme.hair,
      width: chrome.px('chrome.hair'),
    ),
    borderRadius: BorderRadius.circular(chrome.px('chrome.corner')),
  );
  return InputDecoration(
    isDense: true,
    hintText: hint,
    hintStyle: labelStyle(c, color: theme.hair),
    contentPadding: EdgeInsets.all(padding ?? chrome.px('chrome.pad') / 2),
    border: border,
    enabledBorder: border,
    // THE FOCUSED FIELD SAYS SO IN THE PALETTE'S OWN VOICE. Material's default
    // focus ring is the framework's blue, which is exactly the seam the theme
    // pass closed everywhere else.
    focusedBorder: OutlineInputBorder(
      borderSide: BorderSide(color: theme.primary, width: chrome.px('chrome.focusRing')),
      borderRadius: BorderRadius.circular(chrome.px('chrome.corner')),
    ),
  );
}

/// A formula, with live evaluation and the refusal in the law's own words.
class ExpressionField extends StatefulWidget {
  const ExpressionField({
    super.key,
    required this.label,
    required this.source,
    required this.onChanged,
    this.evaluate,
  });

  final String label, source;
  final void Function(String) onChanged;

  /// Reads the text and either says what it means or refuses. Defaults to the
  /// one math with an empty environment.
  final String? Function(String source)? evaluate;

  @override
  State<ExpressionField> createState() => _ExpressionFieldState();
}

class _ExpressionFieldState extends State<ExpressionField> {
  late final TextEditingController _controller = TextEditingController(text: widget.source);
  String? _refusal, _reading;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _read(String source) {
    setState(() {
      try {
        final read = widget.evaluate;
        _reading = read == null ? '${evaluateSource(source, const Env())}' : read(source);
        _refusal = null;
      } on MathRefusal catch (refusal) {
        _reading = null;
        _refusal = '$refusal';
      }
    });
    if (_refusal == null) widget.onChanged(source);
  }

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeScope.of(context);
    final theme = ChronoTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        controlChip(
          context,
          label: widget.label,
          inert: true,
          child: SizedBox(
            width: chrome.px('chrome.menuWidth'),
            child: TextField(
              controller: _controller,
              onChanged: _read,
              style: dataStyle(context),
              decoration: fieldChrome(
                context,
                hint: 'An expression in the one math',
                refused: _refusal != null,
              ),
            ),
          ),
        ),
        if (_refusal != null || _reading != null)
          Text(
            _refusal ?? '= $_reading',
            style: labelStyle(context, color: _refusal != null ? theme.primary : theme.strong),
          ),
      ],
    );
  }
}
