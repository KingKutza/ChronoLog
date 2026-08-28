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
// gets drawn. And a mark's grab shape is a strip at its leading edge, not its
// whole body, so a drag inside an occupied span creates in place instead of
// demanding the occupant be moved away and back.

import 'package:flutter/widgets.dart';

import '../../core/exact.dart';
import '../../core/object_kinds.dart';
import '../capacity.dart';
import '../color.dart';
import '../display_weight.dart';
import '../facts.dart';
import '../lanes.dart';
import '../law_context.dart';
import '../lens_painter.dart';
import '../now.dart';
import '../view_tile.dart';
import '../zones.dart';
import 'month_grid.dart';

const Map<String, String> intimateTunableDefaults = {
  'intimate.rail': '46',
  // The narrowest a day may become before the lens shows fewer of them.
  'intimate.minColumnPixels': '180',
  // THE RULE LADDER runs BOTH ways (Don, 2026-08-28): the surface coarsens as
  // it shrinks and SUBDIVIDES as it grows, so an hour that fills the screen is
  // ruled in halves, quarters and minutes rather than left blank. The rungs are
  // fractions of THIS LAW's hour, so a hundred-minute hour subdivides too.
  'intimate.ruleSpacing': '44',
  'intimate.labelSpacing': '44',
  'intimate.ruleLadderCount': '12',
  'intimate.ruleLadder.01': '1/60',
  'intimate.ruleLadder.02': '1/30',
  'intimate.ruleLadder.03': '1/20',
  'intimate.ruleLadder.04': '1/12',
  'intimate.ruleLadder.05': '1/6',
  'intimate.ruleLadder.06': '1/4',
  'intimate.ruleLadder.07': '1/2',
  'intimate.ruleLadder.08': '1',
  'intimate.ruleLadder.09': '2',
  'intimate.ruleLadder.10': '3',
  'intimate.ruleLadder.11': '6',
  'intimate.ruleLadder.12': '12',
  // Marginalia: what one float lane wants, and the most of a day the whole of
  // it may claim however many lanes it packs into.
  'intimate.floatWidth': '132',
  'intimate.floatShare': '1/2',
  'intimate.labelSize': '10',
  'intimate.titleSize': '11',
  'intimate.pad': '4',
  'intimate.markMinHeight': '13',
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
  'intimate.hourOpacity': '0.5',
  'intimate.washOffHours': '0.05',
  'intimate.washOverlap': '0.14',
  'intimate.washSpectrum': '0.12',
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
  int _columns = 1;
  double _railWidth = 0, _columnWidth = 0;

  Rational _daysOfPixels(num pixels) =>
      dayPixels.isZero ? Rational.zero : Rational.fromInt(pixels.round()) / dayPixels * law.dayDays;

  Rational _columnTop(int column) => _top + Rational.fromInt(column) * law.dayDays;

  double _left(int column) => _railWidth + column * _columnWidth;

  /// EVERY column whose window holds [days] -- more than one where the columns
  /// overlap in time, which is when the same instant is on screen twice.
  List<int> _columnsAt(Rational days) => [
    for (var column = 0; column < _columns; column++)
      if (days >= _columnTop(column) && days <= _columnTop(column) + _visible) column,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    hits.clear();
    refusals.clear();
    if (dayPixels <= Rational.zero) {
      refusals.add((source: 'intimate', message: 'An hour of no height draws no day.'));
      return paintRefusals(canvas, size);
    }
    _railWidth = scene.px('intimate.rail');
    _visible = _daysOfPixels(size.height);
    final area = size.width - _railWidth;
    final least = scene.px('intimate.minColumnPixels');
    final wanted =
        viewCount(scene, 'back', 'intimate.back') +
        viewCount(scene, 'forward', 'intimate.forward') +
        1;
    // WHAT FITS, NEVER FEWER THAN ONE: a window too narrow for the days asked
    // for shows the days it can hold rather than squeezing them to nothing.
    final holds = least <= 0 ? wanted : (area / least).floor();
    _columns = wanted < 1 ? 1 : (holds < wanted ? (holds < 1 ? 1 : holds) : wanted);
    _columnWidth = area / _columns;
    final first =
        law.dayOf(scene.focusDays) - BigInt.from(viewCount(scene, 'back', 'intimate.back'));
    final into = scene.focusDays - Rational(law.dayOf(scene.focusDays)) * law.dayDays;
    _top = Rational(first) * law.dayDays + into - _visible / Rational.fromInt(2);
    final window = queryWindow(
      scene,
      start: _top - law.dayDays,
      end: _columnTop(_columns - 1) + _visible + law.dayDays,
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
    for (var column = 0; column < _columns; column++) {
      final top = _columnTop(column), bottom = top + _visible;
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

  /// THE ONE RULE LADDER, run in BOTH directions: the hours of this law that
  /// one rule should span so that adjacent rules land about
  /// `intimate.ruleSpacing` apart. Rungs are fractions of the law's own hour;
  /// past either end of the ladder it doubles or halves, so there is no zoom at
  /// which the surface stops subdividing or starts drawing a grey block.
  Rational ruleHours(double hourPixels) {
    final target = scene.px('intimate.ruleSpacing');
    if (hourPixels <= 0 || target <= 0) return Rational.one;
    final wanted = Rational.parse((target / hourPixels).toStringAsFixed(9));
    final rungs = <Rational>[];
    for (var rung = 1; rung <= scene.whole('intimate.ruleLadderCount'); rung++) {
      final step = scene.setting('$ruleLadder${'$rung'.padLeft(2, '0')}');
      if (step > Rational.zero) rungs.add(step);
    }
    if (rungs.isEmpty) return Rational.one;
    final two = Rational.fromInt(2);
    for (final step in rungs) {
      if (step < wanted) continue;
      if (step != rungs.first) return step;
      // Below the ladder: halve while a finer rung still clears the target.
      var below = step;
      while (below / two >= wanted) {
        below /= two;
      }
      return below;
    }
    var above = rungs.last;
    while (above < wanted) {
      above *= two;
    }
    return above;
  }

  /// The rail, drawn ONCE at the left, on the ladder above. Every column shares
  /// these heights, because the columns differ by whole days.
  void _paintRail(Canvas canvas, Size size) {
    final hours = law.hoursPerDay.round().toInt();
    if (hours < 1) return;
    final hourPixels = (dayPixels / law.hoursPerDay).toDouble();
    final step = law.daysOfMinute(ruleHours(hourPixels) * law.minutesPerHour);
    final rule = Paint()
      ..strokeWidth = scene.px('intimate.hourRule')
      ..color = scene.theme.hair.withValues(alpha: scene.px('intimate.hourOpacity'));
    final start = viewCount(scene, 'startHour', 'intimate.startHour');
    final end = viewCount(scene, 'endHour', 'intimate.endHour');
    for (var day = law.dayOf(_top); day <= law.dayOf(_top + _visible); day += BigInt.one) {
      final dayStart = Rational(day) * law.dayDays;
      if (start < end) {
        final off = scene.px('intimate.washOffHours');
        final wide = scene.theme.muted;
        paintWash(
          canvas,
          Rect.fromLTRB(_railWidth, _y(0, dayStart), size.width, _y(0, dayStart + _hour(start))),
          wide,
          off,
        );
        paintWash(
          canvas,
          Rect.fromLTRB(
            _railWidth,
            _y(0, dayStart + _hour(end)),
            size.width,
            _y(0, dayStart + law.dayDays),
          ),
          wide,
          off,
        );
      }
      for (var column = 0; column < _columns; column++) {
        _paintMidnight(canvas, size, column, day + BigInt.from(column));
      }
    }
    if (step <= Rational.zero) return;
    // Only the rules the window actually holds: at a minute a rule, a day has
    // a thousand of them and the screen has sixteen.
    final spacing = (step / law.dayDays * dayPixels).toDouble();
    final every = spacing <= 0 ? 1 : (scene.px('intimate.labelSpacing') / spacing).ceil();
    final first = (_top / step).floor(), last = ((_top + _visible) / step).floor();
    for (var index = first; index <= last; index += BigInt.one) {
      final at = Rational(index) * step;
      final y = _y(0, at);
      if (y < 0 || y > size.height) continue;
      canvas.drawLine(Offset(_railWidth, crisp(y)), Offset(size.width, crisp(y)), rule);
      if (index % BigInt.from(every < 1 ? 1 : every) != BigInt.zero) continue;
      _text(
        canvas,
        law.clockLabel(law.minuteOfDay(at)),
        Offset(scene.px('intimate.pad'), y),
        scene.theme.muted,
        'intimate.labelSize',
        data: true,
      );
    }
    // The seam between one day and the next, drawn as the rule it is.
    for (var column = 1; column < _columns; column++) {
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
    for (var column = 0; column < _columns; column++) {
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

  Rational _hour(int hour) => law.daysOfMinute(law.minutesPerHour * Rational.fromInt(hour));

  /// Midnight in ONE column: one rule, the closing day named to its left and the
  /// opening day to its right. The seam a scroll passes through, drawn as the
  /// boundary it is.
  void _paintMidnight(Canvas canvas, Size size, int column, BigInt day) {
    final y = _y(column, Rational(day) * law.dayDays);
    if (y < 0 || y > size.height) return;
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
    _paintOverlap(canvas, column, blocks, left, timedWidth);
    _paintBlocks(
      canvas,
      size,
      column,
      blocks,
      packLanes([for (final b in blocks) (start: b.start, end: b.end)]),
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

  /// The ToDo spectrum: an unresolved float tints its OWN lane from now to where
  /// it is stapled -- never a second event, and never on a resolved object.
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
    for (final (index, block) in floats.indexed) {
      if (block.weight.state == 'done' || block.weight.state == 'closed') continue;
      final band = bands[packing.lanes[index]];
      final top = at < block.start ? at : block.end;
      final low = at < block.start ? block.start : at;
      paintWash(
        canvas,
        Rect.fromLTRB(
          left + band.offset,
          _y(column, top),
          left + band.offset + band.size,
          _y(column, low),
        ),
        scene.theme.secondary,
        alpha,
      );
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
    // THE GRAB STRIP: the block's leading edge is what a drag moves. Its body is
    // empty to the pointer, which is what lets a create-drag pass through an
    // occupied span (ROADMAP #7).
    final grab = Path()
      ..addRect(Rect.fromLTWH(box.left, box.top, scene.px('intimate.grab'), box.height));
    if (scene.isSelected(fact)) paintSelection(canvas, Path()..addRect(box));
    hits.add((bounds: box, shape: grab, fact: fact, identity: fact.identity));
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
    if (at.dx < _railWidth || _columnWidth <= 0) return null;
    final raw = ((at.dx - _railWidth) / _columnWidth).floor();
    final column = raw < 0 ? 0 : (raw >= _columns ? _columns - 1 : raw);
    return _columnTop(column) + _daysOfPixels(at.dy);
  }
}
