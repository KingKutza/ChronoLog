// Intimate: N DAY COLUMNS side by side, each a continuous vertical surface that
// scrolls THROUGH midnight.
//
// The column count is the lens's own span -- `back + forward + 1` -- clamped to
// what the width can hold at `intimate.minColumnPixels` a column, never below
// one. The hour rail is drawn ONCE, on the left: every column shares the same
// time of day at the same height, because the columns differ by whole days. A
// day boundary is a rule with the closing day named to its left and the opening
// day to its right, drawn where the LAW puts it, in every column.
//
// There is no buffer rail and no rebase. The surface paints the days its
// columns cover; the ~145 lines of the web build's virtual rail existed only to
// keep a DOM edge off-screen and have no successor here.
//
// THE RAIL IS THE LAW'S. Rows come from hours-per-day as declared, so a 23-hour
// day has 23 of them, the clock labels are that law's own, and a frame with no
// clock mapping gets no Now line at all.
//
// ONE TIME, EVERY POSITION (Don, 2026-08-28). A column draws every fact whose
// interval intersects THAT column's visible range. Where two columns are
// showing the same instant -- zoomed out far enough that a column's window runs
// past a whole day -- the same event is drawn in both, hit-tested in both and
// ringed in both. There is no dedupe by fact id here and no column that "owns"
// a day: a coordinate maps to the SET of places that represent it.
//
// MARGINALIA (ROADMAP #2): todos and notes read down the RIGHT edge OF THEIR
// OWN COLUMN, and right-anchoring is not a licence to narrow one -- a lone float
// claims its full column. Lanes key on TEMPORAL OVERLAP ONLY (ruled 8.19 item
// 2) and pack per column; the packer has nothing else to consult.
//
// OVERLAP IS LOCAL (ROADMAP #7): a thirty-minute collision does not lane both
// events full-height. Events stay rectangles; the CONTENDED INTERVAL is what
// gets drawn.
//
// THE WHOLE BLOCK GRABS (ISSUES 9.1, Don: "click on an event or todo and drag
// it, the event does not move -- it drags to create a new event"). A block used
// to record a nine-pixel leading strip as the only region a drag took hold of,
// so a create-drag could pass through an occupied span. But the pointer table
// already answers that -- ALT forces create even over a mark -- and serving it
// twice, invisibly, stole the common gesture. The common gesture gets the common
// verb: a drag that starts anywhere on a block moves it, and creating through an
// occupied span is what wears the modifier. An affordance nine pixels wide,
// unpainted and unhinted, is not an affordance.

import 'package:flutter/widgets.dart';

import '../../core/exact.dart';
import '../../core/object_kinds.dart';
import '../capacity.dart';
import '../color.dart';
import '../display_weight.dart';
import '../facts.dart';
import '../ladder.dart';
import '../lanes.dart';
import '../law_context.dart';
import '../lens_painter.dart';
import '../marks.dart';
import '../now.dart';
import '../view_tile.dart';
import '../zones.dart';
import 'month_grid.dart';

const Map<String, String> intimateTunableDefaults = {
  'intimate.rail': '46',
  // The narrowest a day may become before the lens shows fewer of them.
  'intimate.minColumnPixels': '180',
  // THE RULE LADDER runs BOTH ways (Don, 2026-08-28) and is TWO-TIER at every
  // rung (Don, 2026-08-31): the surface coarsens as it shrinks and SUBDIVIDES as
  // it grows, and every rung pairs a major with a minor. The rungs are fractions
  // of THIS LAW's hour, so a hundred-minute hour subdivides too; the pairing and
  // the target spacings live in `rule.*` (lens/ladder.dart), because one ladder
  // serves every surface that rules time.
  'intimate.ruleLadderCount': '13',
  // The authored increments, ascending, as fractions of THIS LAW's hour. Below a
  // minute they are the readings a clock face has (5s, 10s, 15s) rather than bare
  // halvings, so the ladder lands on units a person recognises at every zoom;
  // past either end it halves and doubles.
  //
  // WHY THERE IS NO HALF-MINUTE (tuned 2026-08-31, to green "majors 1m / minors
  // 5s"). A rung's major is the FIRST authored increment above the minor that
  // both clears the major spacing and is a whole number of minors. Thirty seconds
  // is six five-second minors, so wherever the five-second minor is the finest
  // that still clears its spacing, the half-minute reaches the major spacing
  // first and takes the tier -- and the minute Don named can never be paired with
  // it at any zoom. Every other named rung holds the pair apart by a factor
  // between two and six, which is what the shipped spacings (8 and 30, a ratio of
  // 3.75) are cut for; only the sub-minute run was crowded. Removing the
  // half-minute leaves 15s as the largest divisor below the minute, and the whole
  // set Don named -- hour/quarter, 15m/5m, 1m/5s -- is reachable.
  'intimate.ruleLadder.01': '1/720',
  'intimate.ruleLadder.02': '1/360',
  'intimate.ruleLadder.03': '1/240',
  'intimate.ruleLadder.04': '1/60',
  'intimate.ruleLadder.05': '1/30',
  'intimate.ruleLadder.06': '1/20',
  'intimate.ruleLadder.07': '1/12',
  'intimate.ruleLadder.08': '1/6',
  'intimate.ruleLadder.09': '1/4',
  // NO HALF HOUR AND NO TWO HOURS (ISSUES 9.1). Don: "by the time it snaps to a
  // new major that major should be a named rung like 10m or 6h -- never a 30m
  // or 2h it holds no opinion about." A rung the lens holds no opinion about is
  // a rung that does not belong on its ladder; with these two gone the pairs it
  // yields to on either side of the hour are 15m/5m below and 3h/1h above, and
  // every rung Don did name stays reachable.
  'intimate.ruleLadder.10': '1',
  'intimate.ruleLadder.11': '3',
  'intimate.ruleLadder.12': '6',
  'intimate.ruleLadder.13': '12',
  // THE PAIR THIS LENS PREFERS, in the hours of the frame's own day: the hour
  // and the quarter its settings have always named. `rule.preference` says how
  // hard it clings to them before yielding to the ladder.
  'intimate.preferMajor': '1',
  'intimate.preferMinor': '1/4',
  // Marginalia: what one float lane wants, and the most of a day the whole of
  // it may claim however many lanes it packs into.
  'intimate.floatWidth': '132',
  'intimate.floatShare': '1/2',
  // HOW FAR PAST THE VIEWPORT THE SURFACE IS DRAWN. A pan transforms the
  // painted scene, so what slides in at the edge has to have been painted: this
  // is the depth of the drag preview, and past it the pan commits and repaints
  // in place.
  //
  // BOTH WAYS (ISSUES 9.1). Sideways used to bleed nothing, on the grounds that
  // a column IS a day and so a sideways pan steps whole columns -- and that is
  // exactly what Don felt as a ratchet with no preview: honesty and smoothness
  // are not a tradeoff, and a surface that cannot show a partial step owes a
  // bleed that makes it showable. Across, the bleed is counted in COLUMNS, since
  // a column is the step; a whole one past each edge is what lets a slide of up
  // to one full day be previewed before it commits.
  'intimate.bleed': '160',
  'intimate.bleedColumns': '1',
  'intimate.labelSize': '10',
  'intimate.titleSize': '11',
  'intimate.pad': '4',
  'intimate.markMinHeight': '13',
  // The block's leading edge. It is no longer what a DRAG takes hold of -- the
  // whole body moves, ruled 9.1 -- and stands as the width of the edge a resize
  // will grab when this lens grows one.
  'intimate.grab': '9',
  'intimate.radius': '4',
  'intimate.fill': '0.12',
  // THE LEFT RULE is what says whose a block is: the authored colour at full
  // strength down its leading edge, with the body a wash of the same colour
  // over paper and the boundary a hairline. A hard border in the full colour
  // all the way round is what made every event read as a grey box.
  'intimate.rule': '3',
  'intimate.edge': '0.3',
  'intimate.timeSize': '9',
  'intimate.midnightRule': '1.6',
  'intimate.hourRule': '1',
  'intimate.washOverlap': '0.14',
  // THE TO-DO LINE (ruled 9.1), the same vocabulary the day sheets draw it in:
  // a sigil at the stapled point, a dotted line running until now, a sigil
  // there. Down a column the line runs down the float's own lane, so which way
  // it leaves the sigil IS overdue-or-upcoming.
  'intimate.washSpectrum': '0.55',
  'intimate.spectrumWidth': '1',
  'intimate.spectrumSigil': '6',
  'intimate.pip': '8',
};

/// The family of ladder rungs, named once so the settings coverage can see it.
const String ruleLadder = 'intimate.ruleLadder.';

/// One drawn block: where it sits, what it is, and how it was weighed.
typedef _Block = ({Segment segment, DisplayWeight weight, Rational start, Rational end});

class IntimatePainter extends LensPainter implements ManyPositions {
  IntimatePainter(super.scene) : law = LawContext(scene.law);

  final LawContext law;
  late final ColorCascade cascade = ColorCascade(scene.engine, scene.projection, scene.theme);

  /// Pixels per day of THIS law: an hour's height times however many hours the
  /// law says a day has. The height comes from the VIEW -- the context bar's
  /// row-height control and the shipped default are the same question.
  late final Rational dayPixels =
      Rational.fromInt(viewCount(scene, 'hourPixels', 'intimate.hourPixels')) * law.hoursPerDay;

  /// The top of the FIRST column. Every other column is this plus whole days.
  Rational _top = Rational.zero;
  Rational _visible = Rational.zero;

  /// HOW THE SURFACE IS DIVIDED, derived from the scene rather than assigned
  /// during a paint. The host reads [bleed] to size the box it paints INTO,
  /// which happens before any paint has run, so a bleed measured in columns has
  /// to be answerable from the scene alone.
  late final ({int count, double width, double rail}) _plan = () {
    final rail = scene.px('intimate.rail');
    final area = scene.size.width - rail;
    final least = scene.px('intimate.minColumnPixels');
    final wanted =
        viewCount(scene, 'back', 'intimate.back') +
        viewCount(scene, 'forward', 'intimate.forward') +
        1;
    // WHAT FITS, NEVER FEWER THAN ONE: a window too narrow for the days asked
    // for shows the days it can hold rather than squeezing them to nothing.
    final holds = least <= 0 ? wanted : (area / least).floor();
    final count = wanted < 1 ? 1 : (holds < wanted ? (holds < 1 ? 1 : holds) : wanted);
    return (count: count, width: count <= 0 ? area : area / count, rail: rail);
  }();

  int get _columns => _plan.count;

  double get _columnWidth => _plan.width;

  double get _railWidth => _plan.rail;

  /// How many whole columns are painted past each edge.
  int get _bleedColumns {
    final asked = scene.whole('intimate.bleedColumns');
    return asked < 0 ? 0 : asked;
  }

  /// The first and last column index this surface PAINTS, the bleed included.
  int get _firstPainted => -_bleedColumns;

  int get _lastPainted => _columns - 1 + _bleedColumns;

  /// Pixels to days, EXACTLY: a pan commits what the eye was shown, and a
  /// rounded pixel is a lie of up to half a pixel per gesture.
  Rational _daysOfPixels(num pixels) => dayPixels.isZero
      ? Rational.zero
      : Rational.parse(pixels.toDouble().toStringAsFixed(6)) / dayPixels * law.dayDays;

  /// How far past its own box this surface paints, per axis. Down the rail, a
  /// depth in pixels; across it, whole COLUMNS -- because across, a column is
  /// the step, and a partial step can only be shown where a whole one is drawn.
  @override
  Offset get bleed => Offset(_columnWidth * _bleedColumns, scene.px('intimate.bleed'));

  Rational get _bleedDays => _daysOfPixels(bleed.dy);

  /// THE PAN, as this surface can hold it. Down the rail the focus takes the
  /// whole gesture exactly. Across it a column is a WHOLE DAY of this law, so
  /// the WINDOW can only move in whole columns -- but the EYE is shown the whole
  /// slide, continuously, because a column past each edge is painted and a
  /// transform can slide in pixels that exist (ISSUES 9.1).
  ///
  /// Three answers, one motion: `days` is what the window commits, `shown` is
  /// the continuous slide, `taken` is the part of the slide `days` accounted
  /// for. What was not taken is not lost -- the tile carries it forward as
  /// travel -- which is why this no longer ratchets and no longer snaps.
  ///
  /// Absorbing one column is not a vertical jump: this surface repeats every
  /// (one column right, one day up), so stepping a column and moving the focus a
  /// day are one motion, and the pair below is the algebra of that.
  @override
  PanLanding panLanding(Offset shift) {
    if (dayPixels <= Rational.zero || _columnWidth <= 0) {
      return (days: Rational.zero, shown: Offset.zero, taken: Offset.zero);
    }
    // TRUNCATED, not rounded: a drag shorter than one column has not asked for
    // the next day, and a step that over-delivers is the same lie in miniature.
    final columns = (shift.dx / _columnWidth).truncate();
    final steps = Rational.fromInt(columns);
    return (
      days: -(_daysOfPixels(shift.dy) + steps * law.dayDays),
      shown: shift,
      taken: Offset(columns * _columnWidth, shift.dy),
    );
  }

  Rational _columnTop(int column) => _top + Rational.fromInt(column) * law.dayDays;

  double _left(int column) => _railWidth + column * _columnWidth;

  /// EVERY column whose window holds [days] -- more than one where the columns
  /// overlap in time, which is when the same instant is on screen twice. The
  /// bleed counts: a mark one pixel above the viewport is painted, so it has a
  /// position, and a pan must be able to slide it in.
  List<int> _columnsAt(Rational days) => [
    for (var column = _firstPainted; column <= _lastPainted; column++)
      if (days >= _columnTop(column) - _bleedDays &&
          days <= _columnTop(column) + _visible + _bleedDays)
        column,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    hits.clear();
    refusals.clear();
    if (dayPixels <= Rational.zero) {
      refusals.add((source: 'intimate', message: 'An hour of no height draws no day.'));
      return paintRefusals(canvas, size);
    }
    _visible = _daysOfPixels(size.height);
    final first =
        law.dayOf(scene.focusDays) - BigInt.from(viewCount(scene, 'back', 'intimate.back'));
    final into = scene.focusDays - Rational(law.dayOf(scene.focusDays)) * law.dayDays;
    _top = Rational(first) * law.dayDays + into - _visible / Rational.fromInt(2);
    final window = queryWindow(
      scene,
      start: _columnTop(_firstPainted) - law.dayDays - _bleedDays,
      end: _columnTop(_lastPainted) + _visible + law.dayDays + _bleedDays,
      budget: capacityOf(size.width, size.height, scene.tunable).queryBudget,
      law: law,
    );
    refusals.addAll(window.refusals);
    final all = <_Block>[];
    for (final segments in window.byDay.values) {
      for (final segment in segments) {
        final dayStart = Rational(segment.day) * law.dayDays;
        all.add((
          segment: segment,
          weight: factDisplayWeight(scene, segment.fact, keyPrefix: 'intimate'),
          start: dayStart + law.daysOfMinute(segment.startMinute),
          end: dayStart + law.daysOfMinute(segment.endMinute),
        ));
      }
    }
    _paintRail(canvas, size);
    for (var column = _firstPainted; column <= _lastPainted; column++) {
      final top = _columnTop(column) - _bleedDays,
          bottom = _columnTop(column) + _visible + _bleedDays;
      final blocks = <_Block>[], floats = <_Block>[];
      for (final block in all) {
        // INTERSECTION, not ownership: a fact belongs to every column showing
        // the time it occupies.
        if (block.end < top || block.start > bottom) continue;
        final kind = objectKindForEvent(block.segment.fact.event);
        (kind == 'todo' || kind == 'note' ? floats : blocks).add(block);
      }
      _paintColumn(canvas, size, column, blocks, floats);
    }
    _paintColumnNames(canvas);
    _paintGutter(canvas, size);
    final at = nowIn(law, scene.nowDays);
    for (final column in at == null ? const <int>[] : _columnsAt(at)) {
      final y = _y(column, at!);
      paintNow(
        canvas,
        Offset(_left(column), y),
        Offset(_left(column) + _columnWidth, y),
        scene.theme,
        scene.tunable,
      );
    }
    if (window.silent) {
      refusals.add((source: 'intimate', message: 'Nothing is placed in this window.'));
    }
    paintRefusals(canvas, size);
  }

  /// Where now falls on this surface, or null where this law has no now at all.
  Rational? get nowAt => nowIn(law, scene.nowDays);

  double _y(int column, Rational days) =>
      ((days - _columnTop(column)) / law.dayDays * dayPixels).toDouble();

  /// THE ONE RULE LADDER, run in BOTH directions and TWO-TIER at every rung:
  /// what a major rule spans and what a minor one does, in the hours of this
  /// law. The function is `lens/ladder.dart`'s -- the same one every surface
  /// that rules time asks -- and the rungs are fractions of the law's own hour,
  /// so a hundred-minute hour subdivides too.
  Rung rung(double hourPixels) => rungFor(
    unitPixels: hourPixels,
    minorTarget: ladderPixels(scene.tunable, 'rule.minorSpacing'),
    majorTarget: ladderPixels(scene.tunable, 'rule.majorSpacing'),
    steps: ladderSteps(scene.setting, ruleLadder, 'intimate.ruleLadderCount'),
    extra: lawRungs,
    reach: ladderPixels(scene.tunable, 'rule.extension').round(),
    // THE LENS HAS AN OPINION (ISSUES 9.1): it prefers its named pair hard, and
    // yields only to a rung on its own ladder.
    prefer: (
      major: scene.setting('intimate.preferMajor'),
      minor: scene.setting('intimate.preferMinor'),
    ),
    preference: ladderPixels(scene.tunable, 'rule.preference'),
  );

  /// The rungs ABOVE an hour that belong to the LAW rather than to settings: its
  /// day, one turn of its weekday cycle, its month. A week is seven days only
  /// where the law says so, and a law that declares no week contributes none.
  late final List<Rational> lawRungs = () {
    final rungs = <Rational>[law.hoursPerDay];
    final week = scene.law.weekdayNames();
    if (week != null && week.isNotEmpty) {
      rungs.add(law.hoursPerDay * Rational.fromInt(week.length));
    }
    if (law.hasMonths) rungs.add(law.hoursPerDay * scene.law.meanMonthDays());
    return rungs;
  }();

  /// The rung in DAYS of this law, which is what the rail measures in.
  Rung get railRung {
    final ladder = rung((dayPixels / law.hoursPerDay).toDouble());
    return (
      major: law.daysOfMinute(ladder.major * law.minutesPerHour),
      minor: law.daysOfMinute(ladder.minor * law.minutesPerHour),
    );
  }

  /// The rail, drawn ONCE at the left, on the ladder above. Every column shares
  /// these heights, because the columns differ by whole days.
  /// The clock readings the rail collected this paint, drawn once the columns
  /// are down. THE GUTTER IS ON TOP: the column painted past the LEFT edge (the
  /// horizontal bleed, ISSUES 9.1) reaches to the rail's own right edge by
  /// construction -- a column's left is `rail + index * width` and index -1 puts
  /// it there -- so a rail drawn first is a rail with a day's blocks over its
  /// labels. Drawing the gutter after the columns is what keeps the times
  /// readable, and it costs nothing at rest, where nothing is under it.
  final List<({String text, Offset at, Color color})> _gutter = [];

  void _paintGutter(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTRB(-bleed.dx, -bleed.dy, _railWidth, size.height + bleed.dy),
      Paint()..color = scene.theme.paper,
    );
    for (final label in _gutter) {
      _text(canvas, label.text, label.at, label.color, 'intimate.labelSize', data: true);
    }
  }

  void _paintRail(Canvas canvas, Size size) {
    _gutter.clear();
    final hours = law.hoursPerDay.round().toInt();
    if (hours < 1) return;
    final ladder = railRung;
    final pens = rulePens(scene.theme, scene.tunable);
    final tones = labelTones(scene.theme);
    // NO OFF-HOURS WASH FROM A SETTING (ruled 2026-08-31). Where the working day
    // begins and ends is a CALENDAR FACT, so it is an authored object -- a daily
    // series whose handling says zone -- and it arrives here the way every other
    // authored region does: as facts this lens paints as a band. A document that
    // authors no day object has no day zone, which is the honest first run.
    for (
      var day = law.dayOf(_top - _bleedDays) - BigInt.from(_bleedColumns);
      day <= law.dayOf(_top + _visible + _bleedDays);
      day += BigInt.one
    ) {
      for (var column = _firstPainted; column <= _lastPainted; column++) {
        _paintMidnight(canvas, size, column, day + BigInt.from(column));
      }
    }
    if (ladder.minor <= Rational.zero) return;
    // Only the rules the window actually holds, the bleed included: at a minute
    // a rule, a day has a thousand of them and the screen has sixteen.
    final room = ladderPixels(scene.tunable, 'rule.labelSpacing');
    final minute = law.daysOfMinute(Rational.one);
    final top = _top - _bleedDays, bottom = _top + _visible + _bleedDays;
    final first = (top / ladder.minor).floor(), last = (bottom / ladder.minor).floor();
    for (var index = first; index <= last; index += BigInt.one) {
      final at = Rational(index) * ladder.minor;
      final y = _y(0, at);
      if (y < -bleed.dy || y > size.height + bleed.dy) continue;
      final major = isMajorRule(at, ladder);
      canvas.drawLine(
        Offset(_railWidth, crisp(y)),
        Offset(size.width, crisp(y)),
        major ? pens.major : pens.minor,
      );
      // LABELS FOLLOW THE SAME LADDER: a tier is named where a rule of that tier
      // has room for it, and never below the finest unit this law's clock can
      // read, which would print the same word on every line.
      final step = major ? ladder.major : ladder.minor;
      if (step < minute) continue;
      if ((step / law.dayDays * dayPixels).toDouble() < room) continue;
      _gutter.add((
        text: law.clockLabel(law.minuteOfDay(at)),
        at: Offset(scene.px('intimate.pad'), y),
        color: major ? tones.major : tones.minor,
      ));
    }
    // The seam between one day and the next, drawn as the rule it is. Over the
    // PAINTED range, bleed columns included: a seam that stops at the viewport
    // is a seam that slides in as a missing line.
    for (var column = _firstPainted; column <= _lastPainted + 1; column++) {
      canvas.drawLine(
        Offset(crisp(_left(column)), 0),
        Offset(crisp(_left(column)), size.height),
        Paint()
          ..strokeWidth = scene.px('intimate.hourRule')
          ..color = scene.theme.hair,
      );
    }
  }

  /// WHICH DAY IS THIS COLUMN? A window that never crosses midnight would
  /// otherwise be several unnamed columns of hours. Drawn AFTER the blocks: a
  /// day-long span used to cover the only thing naming the day it covers.
  void _paintColumnNames(Canvas canvas) {
    final pad = scene.px('intimate.pad');
    for (var column = _firstPainted; column <= _lastPainted; column++) {
      _text(
        canvas,
        dayLabel(scene.law, law.dayOf(_columnTop(column) + _visible / Rational.fromInt(2))),
        Offset(_left(column) + pad, pad),
        scene.theme.strong,
        'intimate.labelSize',
        width: _columnWidth - pad * 2,
        data: true,
      );
    }
  }

  /// Midnight in ONE column: one rule, the closing day named to its left and the
  /// opening day to its right. The seam a scroll passes through, drawn as the
  /// boundary it is.
  void _paintMidnight(Canvas canvas, Size size, int column, BigInt day) {
    final y = _y(column, Rational(day) * law.dayDays);
    if (y < -bleed.dy || y > size.height + bleed.dy) return;
    final left = _left(column), right = left + _columnWidth;
    canvas.drawLine(
      Offset(left, crisp(y)),
      Offset(right, crisp(y)),
      Paint()
        ..strokeWidth = scene.px('intimate.midnightRule')
        ..color = scene.theme.strong,
    );
    final pad = scene.px('intimate.pad');
    _text(
      canvas,
      dayLabel(scene.law, day - BigInt.one),
      Offset(left + pad, y - scene.px('intimate.labelSize') - pad),
      scene.theme.muted,
      'intimate.labelSize',
      width: _columnWidth - pad * 2,
      data: true,
    );
    _text(
      canvas,
      dayLabel(scene.law, day),
      Offset(left + pad, y + pad),
      scene.theme.ink,
      'intimate.labelSize',
      width: _columnWidth - pad * 2,
      data: true,
    );
  }

  /// One day: its contended intervals, its timed blocks, its marginalia.
  void _paintColumn(
    Canvas canvas,
    Size size,
    int column,
    List<_Block> blocks,
    List<_Block> floats,
  ) {
    final floatLanes = packLanes([for (final f in floats) (start: f.start, end: f.end)]);
    // A lone float claims its full column width; a crowd of them shares what
    // marginalia is allowed, and the day keeps the rest. Neither eats the other.
    final wanted = scene.px('intimate.floatWidth');
    final most = _columnWidth * scene.px('intimate.floatShare');
    final floatCount = floats.isEmpty ? 0 : floatLanes.count;
    final floatWidth = floatCount == 0
        ? 0.0
        : (wanted * floatCount > most ? most / floatCount : wanted);
    final left = _left(column);
    final floatLeft = left + _columnWidth - floatCount * floatWidth;
    final timedWidth = _columnWidth - floatCount * floatWidth;
    // A ZONE IS A REGION, NOT A CHIP, and that is the whole of what "display as
    // a zone" says: it is drawn behind the day across the whole of it and takes
    // NO LANE. Otherwise an authored day object -- a daily series from half six
    // to ten, which is what names the day now that no setting does -- would
    // overlap everything and push every event of that day into half a column.
    final zoned = [
      for (final block in blocks)
        if (zoneFill(scene.engine, block.segment.fact, scene.tunable)) block,
    ];
    final timed = [
      for (final block in blocks)
        if (!zoneFill(scene.engine, block.segment.fact, scene.tunable)) block,
    ];
    _paintBlocks(
      canvas,
      size,
      column,
      zoned,
      (lanes: List.filled(zoned.length, 0), count: 1),
      left,
      timedWidth,
    );
    _paintOverlap(canvas, column, timed, left, timedWidth);
    _paintBlocks(
      canvas,
      size,
      column,
      timed,
      packLanes([for (final b in timed) (start: b.start, end: b.end)]),
      left,
      timedWidth,
    );
    _paintSpectrum(canvas, column, floats, floatLanes, floatLeft, floatWidth);
    _paintBlocks(canvas, size, column, floats, floatLanes, floatLeft, floatCount * floatWidth);
  }

  /// The contended interval, drawn once for the interval rather than by
  /// deforming the events that share it.
  void _paintOverlap(Canvas canvas, int column, List<_Block> blocks, double left, double width) {
    final edges = <({Rational at, int delta})>[
      for (final block in blocks)
        if (block.end > block.start) ...[(at: block.start, delta: 1), (at: block.end, delta: -1)],
    ]..sort((a, b) => a.at.compareTo(b.at) == 0 ? a.delta - b.delta : a.at.compareTo(b.at));
    var depth = 0;
    Rational? from;
    final alpha = scene.px('intimate.washOverlap');
    for (final edge in edges) {
      if (depth >= 2 && from != null && edge.at > from) {
        paintWash(
          canvas,
          Rect.fromLTRB(left, _y(column, from), left + width, _y(column, edge.at)),
          scene.theme.primary,
          alpha,
        );
      }
      depth += edge.delta;
      from = edge.at;
    }
  }

  /// THE TO-DO LINE: an unresolved float says where it is stapled with a sigil,
  /// and a dotted line runs down its OWN lane until now, ending in a second
  /// sigil (ruled 9.1). It was a wash over the interval; a wash per to-do stacks
  /// into mud at a dozen and is unreadable at a hundred, and overscale is the
  /// stated reason. Never a second event, and never on a resolved object.
  void _paintSpectrum(
    Canvas canvas,
    int column,
    List<_Block> floats,
    Packing packing,
    double left,
    double width,
  ) {
    final at = nowIn(law, scene.nowDays);
    if (at == null || width <= 0) return;
    final bands = laneBands(
      packing.count * width,
      packing.count,
      gap: scene.px('lane.gap'),
      minimum: width,
    );
    final alpha = scene.px('intimate.washSpectrum');
    final size = scene.px('intimate.spectrumSigil');
    final on = scene.px('mark.dotOn'), off = scene.px('mark.dotOff');
    for (final (index, block) in floats.indexed) {
      if (block.weight.state == 'done' || block.weight.state == 'closed') continue;
      final band = bands[packing.lanes[index]];
      final x = left + band.offset + band.size / 2;
      final anchor = Offset(x, _y(column, at < block.start ? block.start : block.end));
      final now = Offset(x, _y(column, at));
      final color = cascade.colorOf(block.segment.fact).withValues(alpha: alpha);
      dashLine(
        canvas,
        anchor,
        now,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = scene.px('intimate.spectrumWidth')
          ..strokeCap = StrokeCap.butt
          ..color = color,
        on,
        off,
      );
      for (final point in [anchor, now]) {
        canvas.drawPath(
          sigilPath('point', Rect.fromCenter(center: point, width: size, height: size)),
          Paint()..color = color,
        );
      }
    }
  }

  void _paintBlocks(
    Canvas canvas,
    Size size,
    int column,
    List<_Block> blocks,
    Packing packing,
    double left,
    double width,
  ) {
    if (blocks.isEmpty || width <= 0) return;
    final ranked = [for (final (index, block) in blocks.indexed) (index: index, block: block)]
      ..sort((a, b) => b.block.weight.weight.compareTo(a.block.weight.weight));
    final admitted = admit(
      ranked,
      capacityOf(width, size.height, scene.tunable),
      queryTruncated: false,
    );
    final bands = laneBands(
      width,
      packing.count,
      gap: scene.px('lane.gap'),
      minimum: scene.px('lane.minWidth'),
    );
    for (final entry in admitted.drawn) {
      _paintBlock(canvas, column, entry.block, bands[packing.lanes[entry.index]], left);
    }
    if (admitted.hidden > 0) {
      _text(
        canvas,
        '${admitted.hidden}+',
        Offset(left, size.height - scene.px('intimate.labelSize')),
        scene.theme.muted,
        'intimate.labelSize',
        width: width,
        data: true,
      );
    }
  }

  void _paintBlock(
    Canvas canvas,
    int column,
    _Block block,
    ({double offset, double size}) band,
    double left,
  ) {
    final fact = block.segment.fact;
    final color = cascade.colorOf(fact);
    final minimum = scene.px('intimate.markMinHeight');
    final top = _y(column, block.start);
    final height = _y(column, block.end) - top;
    final box = Rect.fromLTWH(
      left + band.offset,
      top,
      band.size,
      height < minimum ? minimum : height,
    );
    final zoned = zoneFill(scene.engine, fact, scene.tunable);
    if (zoned) {
      final grammar = zoneBand(box, color, zoneSegment(block.segment), scene.theme, scene.tunable);
      canvas.drawRRect(grammar.shape, grammar.fill);
      canvas.drawRRect(grammar.shape, grammar.edge);
    }
    final rule = zoned ? 0.0 : scene.px('intimate.rule');
    if (!zoned) {
      final shape = RRect.fromRectAndRadius(box, Radius.circular(scene.px('intimate.radius')));
      canvas.drawRRect(
        shape,
        Paint()..color = Color.lerp(scene.theme.paper, color, scene.px('intimate.fill'))!,
      );
      // The left rule, in the authored colour at full strength: the one place a
      // block states whose it is, so the body can stay a wash and the boundary
      // a hairline.
      canvas.save();
      canvas.clipRRect(shape);
      canvas.drawRect(Rect.fromLTWH(box.left, box.top, rule, box.height), Paint()..color = color);
      canvas.restore();
      canvas.drawRRect(
        shape,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = scene.px('mark.stroke')
          ..color = color.withValues(alpha: scene.px('intimate.edge')),
      );
    }
    final spec = markSpecFor(scene, law, fact, block.weight, color);
    final pad = scene.px('intimate.pad'), pip = scene.px('intimate.pip');
    final inset = box.left + rule + pad;
    spec.paint(canvas, Rect.fromLTWH(inset, box.top + pad, pip, pip), fact);
    if (!zoneTitled(zoneSegment(block.segment))) return;
    final title = '${fact.event.payload?['title'] ?? ''}';
    final titleSize = scene.px('intimate.titleSize'), timeSize = scene.px('intimate.timeSize');
    _text(
      canvas,
      title,
      Offset(inset + pad + pip, box.top + pad),
      scene.theme.ink.withValues(alpha: spec.opacity),
      'intimate.titleSize',
      width: box.right - pad - (inset + pad + pip),
    );
    // WHEN, in the data face, once the block is tall enough to say it without
    // crowding the name. A clock reading is a coordinate, not prose.
    if (box.height >= titleSize + timeSize + pad * 3) {
      _text(
        canvas,
        law.clockLabel(law.minuteOfDay(block.start)),
        Offset(inset, box.top + pad + titleSize + pad / 2),
        scene.theme.muted.withValues(alpha: spec.opacity),
        'intimate.timeSize',
        width: box.width - rule - pad * 2,
        data: true,
      );
    }
    final body = Path()..addRect(box);
    if (scene.isSelected(fact)) paintSelection(canvas, Path()..addRect(box));
    // ONE REGION, EVERY VERB (ISSUES 9.1). The body is what a click, a menu, the
    // cursor AND a drag all mean; a null grab says "grabbed wherever it is hit",
    // which is the default every other surface already had. Alt remains the
    // stated way to create THROUGH an occupied span (ROADMAP #7) -- the rare
    // verb wears the modifier, and the common one is just there.
    hits.add((bounds: box, shape: body, grab: null, fact: fact, identity: fact.identity));
  }

  void _text(
    Canvas canvas,
    String text,
    Offset at,
    Color color,
    String key, {
    double? width,
    bool data = false,
  }) => paintLabel(
    canvas,
    scene.theme,
    text,
    Rect.fromLTWH(at.dx, at.dy, width ?? scene.size.width, scene.px(key) * 2),
    color,
    scene.px(key),
    data: data,
  );

  /// The eye and the drop, side by side: every column a day is showing in, and
  /// the day a point in one of them names.
  @override
  List<Offset> projectAll(Rational days) => [
    for (final column in _columnsAt(days)) Offset(_left(column), _y(column, days)),
  ];

  @override
  Offset? project(Rational days) {
    final all = projectAll(days);
    if (all.isNotEmpty) return all.first;
    final column = days < _top ? 0 : _columns - 1;
    return Offset(_left(column), _y(column, days));
  }

  @override
  Rational? unproject(Offset at) {
    if (_columnWidth <= 0) return null;
    // THE GUTTER HAS NO TIME UNDER IT, and that stays true: a drop on the rail
    // is a drop on nothing. Past the LEFT edge of the viewport is different --
    // that is the horizontal bleed, painted and real (ISSUES 9.1) -- so a point
    // there names the column that was drawn there.
    if (at.dx >= 0 && at.dx < _railWidth) return null;
    final raw = ((at.dx - _railWidth) / _columnWidth).floor();
    final column = raw < _firstPainted
        ? _firstPainted
        : (raw > _lastPainted ? _lastPainted : raw);
    return _columnTop(column) + _daysOfPixels(at.dy);
  }
}
