// THE DAY-CELL SUBSTRATE: month resolution under any law, the one painter every
// grid lens draws through, and this area's settings.
//
// ONE MONTH GRID (melt of the web build's `monthCard` and `fixedMonthCard`).
// There was a Gregorian month sheet and a second, nearly identical one for
// fixed-radix calendars; they are the same sheet, and the difference between
// them is a question asked of the law. A sheet's column count is what the law
// says a month holds in base units -- 31 where a Gregorian month runs that long,
// 64 on an 8x8x8 calendar -- and never a literal.
//
// REFUSE LOUDLY. A law that declares no month level gets no month sheet and an
// explicit sentence saying so, in its own vocabulary. Inventing twelve months
// for a world that has none is the failure this file exists to avoid.
//
// PER-DAY BUDGET (survey B8, ruling 9). Every date in the range must be
// represented, so the budget is spent per day through `aggregateDensity` rather
// than swallowed by the first busy week, and what does not fit is a LOWER BOUND
// -- "48+" -- never a silent drop.

import 'package:flutter/widgets.dart';

import '../../core/coordinate_entry.dart';
import '../../core/coordinate_law.dart';
import '../../core/exact.dart';
import '../../core/object_kinds.dart';
import '../../core/projection.dart';
import '../../core/strategic_density.dart';
import '../capacity.dart';
import '../color.dart';
import '../display_weight.dart';
import '../facts.dart';
import '../ladder.dart';
import '../law_context.dart';
import '../lens_painter.dart';
import '../marks.dart';
import '../now.dart';
import '../theme.dart';
import '../view_tile.dart';
import '../zones.dart';
import 'intimate.dart';
import 'strategic.dart';
import 'tactical.dart';
import 'wall.dart';

/// Every number the grid lenses draw with. Promotion thresholds are per lens as
/// `promotionOf` expects, and all four lenses' pairs live here together: one
/// number has one home, and Strategic's pair is not a different kind of number
/// for being named by a catalog control as well.
const Map<String, String> gridTunableDefaults = {
  // The rule ladder's own numbers, spread in here: one composed settings map
  // answers for them, and the two-tier rule is one function every surface that
  // rules time asks (`lens/ladder.dart`).
  ...ladderTunableDefaults,
  'grid.header': '18',
  'grid.gutter': '74',
  'grid.pad': '3',
  'grid.rule': '1',
  'grid.chipWidth': '64',
  'grid.chipHeight': '13',
  'grid.chipDepth': '1',
  'grid.nameAt': '54',
  'grid.labelSize': '10',
  'grid.numberSize': '10',
  'grid.numberAt': '22',
  'grid.overflowSize': '9',
  'grid.pipSize': '7',
  'grid.washWeekend': '0.07',
  'grid.washToday': '0.1',
  // The record slash already says "this is behind us"; a wash saying it again
  // is the same claim twice, so it ships off (ruled 2026-08-28).
  'grid.washPast': '0',
  'grid.slashPast': '0.14',
  'grid.washSpectrum': '0.1',
  // The weekend as AUTHORED cycle positions, never a hardcoded Saturday and
  // Sunday: a calendar whose rest days fall elsewhere says so here, and a count
  // of zero is a calendar with no weekend at all.
  'grid.weekendCount': '2',
  'grid.weekend.1': '0',
  'grid.weekend.2': '6',
  // The first column is the weekday cycle's OWN position zero, not a Monday:
  // a calendar whose week starts elsewhere says so by moving this, and nothing
  // here assumes a Gregorian week (ruled 2026-08-28).
  'wall.firstWeekday': '0',
  'intimate.importantAt': '2',
  'intimate.landmarkAt': '4',
  'tactical.importantAt': '2',
  'tactical.landmarkAt': '4',
  'wall.importantAt': '2',
  'wall.landmarkAt': '4',
  'strategic.importantAt': '2',
  'strategic.landmarkAt': '4',
};

/// Each grid lens, into the ONE painter registry the view tile reads. The
/// catalog says what a lens IS; this says what puts it on a canvas.
void registerGridLenses() {
  registerLensPainter('intimate', IntimatePainter.new);
  registerLensPainter('tactical', TacticalPainter.new);
  registerLensPainter('strategic', StrategicPainter.new);
  registerLensPainter('wall', WallPainter.new);
}

// --- Months under any law ----------------------------------------------------

/// One month sheet: where it starts, how many base units it holds, and what its
/// law calls it.
typedef MonthSheet = ({BigInt firstDay, int days, String label});

/// The level a month sheet rows on: the one counting months in a registered
/// calendar, or a level the author actually named `month`.
String? monthLevelOf(CoordinateLaw law) =>
    (law.levels.where((level) => level.transition == 'gregorian.months').firstOrNull ??
            law.level('month'))
        ?.name;

/// The ladder this law executes, root first.
List<Level> ladderOf(CoordinateLaw law) => law.aboveLadder.isEmpty ? law.levels : law.aboveLadder;

/// The lowest legal value of a level: one where the family counts from one, zero
/// everywhere else -- a rule about the family's own defaults, never a list.
int levelFloor(CoordinateLaw law, String name) => law.family?.defaults[name] == '1' ? 1 : 0;

Coordinate _truncated(CoordinateLaw law, Coordinate value, String depth) {
  final kept = <({String level, String value})>[];
  for (final level in ladderOf(law)) {
    if (!value.has(level.name)) break;
    kept.add((level: level.name, value: value.value(level.name)));
    if (level.name == depth) break;
  }
  return Coordinate(kept);
}

String? _eraYear(CoordinateLaw law, Rational days) {
  try {
    return law.formatYearAtDays(days);
  } catch (_) {
    return null;
  }
}

/// How many base units the month starting at [start] holds, read from the picker
/// ladder's own bounded rung -- a leap February answers 29, an authored 64-day
/// month answers 64. Null where the law cannot count them.
int? baseUnitsIn(CoordinateLaw law, Coordinate start) {
  for (final rung in coordinatePickerLadder(law, start)) {
    if (rung.level == law.baseLevel) return rung.bounded ? rung.options.length : null;
  }
  return null;
}

/// [count] month sheets from the month containing [fromDays]. Null when this law
/// declares no months at all -- the caller REFUSES rather than invents one.
List<MonthSheet>? monthSheets(CoordinateLaw law, Rational fromDays, int count) {
  final level = monthLevelOf(law);
  if (level == null || !law.hasMonths()) return null;
  final names = law.namesFor(level) ?? law.monthNames();
  final floor = levelFloor(law, level);
  final sheets = <MonthSheet>[];
  var at = fromDays;
  for (var index = 0; index < count; index += 1) {
    final start = _truncated(law, law.fromDays(at), level);
    if (!start.has(level)) return null;
    final firstDays = law.toDays(start);
    final days = baseUnitsIn(law, start);
    if (days == null || days < 1) return null;
    final ordinal = (int.tryParse(start.value(level)) ?? floor) - floor;
    final named = names != null && ordinal >= 0 && ordinal < names.length
        ? names[ordinal]
        : '$level ${ordinal + floor}';
    final year = _eraYear(law, firstDays);
    sheets.add((
      firstDay: (firstDays / law.baseDays).floor(),
      days: days,
      label: year == null ? named : '$named $year',
    ));
    at = firstDays + Rational.fromInt(days) * law.baseDays;
  }
  return sheets;
}

/// A view value the context bar wrote, or this lens's shipped setting. One
/// reader, so a control the user has never touched and one they have are the
/// same question asked twice.
int viewCount(LensScene scene, String key, String settingKey) => switch (scene.viewValue(key)) {
  final Rational value => value.round().toInt(),
  final num value => value.round(),
  final String value => int.tryParse(value) ?? scene.whole(settingKey),
  _ => scene.whole(settingKey),
};

/// A toggle the view carries, or NULL where the view says nothing about it --
/// which is not "off". A lens whose control has never been touched falls back to
/// its own derivation rather than to a guessed boolean.
bool? viewFlag(LensScene scene, String key) => switch (scene.viewValue(key)) {
  final bool value => value,
  final Rational value => !value.isZero,
  'true' => true,
  'false' => false,
  _ => null,
};

/// What this law calls one day, short: its month name and the day's own number,
/// or the number alone where the law has no months.
String dayLabel(CoordinateLaw law, BigInt day) {
  final at = law.fromDays(Rational(day) * law.baseDays);
  final number = at.value(law.baseLevel, '');
  final level = monthLevelOf(law);
  final names = level == null ? null : (law.namesFor(level) ?? law.monthNames());
  if (level == null || names == null) return number;
  final ordinal =
      (int.tryParse(at.value(level, '')) ?? levelFloor(law, level)) - levelFloor(law, level);
  if (ordinal < 0 || ordinal >= names.length) return number;
  final name = names[ordinal];
  return '${name.length <= 3 ? name : name.substring(0, 3)} $number';
}

/// The column headings of a week-wide grid: the authored cycle names from the
/// position the settings start it at, each carrying the cycle index it stands
/// for so the weekend wash never counts columns.
List<Heading> weekdayHeadings(List<String> names, int first, {bool initials = false}) => [
  for (var index = 0; index < names.length; index += 1)
    (
      label: initials
          ? names[(first + index) % names.length].substring(0, 1)
          : names[(first + index) % names.length],
      cycle: (first + index) % names.length,
    ),
];

/// The one label call every lens draws through, clipped to its own box.
///
/// TWO FACES, ONE RULE (ruled 2026-08-28): [data] is the monospace role and is
/// for COORDINATES, COUNTS AND TIMES -- a clock reading, a day number, an "N+"
/// lower bound. Everything a person reads as prose -- a title, a weekday name, a
/// month -- is the humanist face and is the default, because a surface that
/// drew every string as data came up in a typewriter from end to end.
void paintLabel(
  Canvas canvas,
  ChronoTheme theme,
  String text,
  Rect box,
  Color color,
  double size, {
  bool center = false,
  bool data = false,
}) {
  if (text.isEmpty || box.width <= 0) return;
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: (data ? theme.data : theme.ui).copyWith(color: color, fontSize: size),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: box.width);
  painter.paint(canvas, Offset(box.left + (center ? (box.width - painter.width) / 2 : 0), box.top));
}

/// A rule laid on the half-pixel, so a one-device-pixel line lands on one pixel
/// instead of being resolved as two grey ones. Every hairline in every lens goes
/// through this: the blur is a large part of what read as coarse.
double crisp(double at) => at.roundToDouble() + 1 / 2;

/// A flat tint over a region: how a weekend, a spent day, today, a contended
/// interval and a ToDo spectrum all read as ground rather than as marks.
void paintWash(Canvas canvas, Rect box, Color color, double alpha) =>
    canvas.drawRect(box, Paint()..color = color.withValues(alpha: alpha));

/// The mark vocabulary resolved for one fact. Shared, so a cell chip and an
/// Intimate block cannot draw the same object as two different things.
MarkSpec markSpecFor(
  LensScene scene,
  LawContext law,
  Fact fact,
  DisplayWeight weight,
  Color color,
) => MarkSpec(
  sigil: sigilFor(
    authored: authoredSigilOf(scene.engine, fact),
    event: fact.event,
    virtual: fact.virtualId.isNotEmpty,
    succession: false,
    durationDays: scene.engine.eventDurationDays(fact.event),
    dayDays: law.dayDays,
    promoted: weight.promotion != standardWeight,
  ),
  state: weight.state,
  color: color,
  theme: scene.theme,
  bucket: weight.bucket,
  read: scene.tunable,
);

// --- The painter -------------------------------------------------------------

/// One row of the grid: what the gutter calls it, and the day at each column --
/// null for a pad cell, which is a real absence and never day zero.
typedef GridRow = ({String label, List<BigInt?> days});

/// One column heading: its text and the cycle position it stands for, so the
/// weekend wash reads the CYCLE and not the column number.
typedef Heading = ({String label, int? cycle});

/// What a cell draws for one mark.
const String showName = 'name', showPip = 'pip', showNone = 'none';

/// The shared day-cell surface. A subclass says what the rows ARE and how a mark
/// presents; everything else -- the query, the budget, the washes, the zone
/// grammar, the hits, the now marker, the refusals -- happens once, here.
abstract class DayGridPainter extends LensPainter {
  DayGridPainter(super.scene, {required this.lens}) : law = LawContext(scene.law);

  final String lens;
  final LawContext law;
  late final ColorCascade cascade = ColorCascade(scene.engine, scene.projection, scene.theme);

  List<GridRow> rows = const [];
  final Set<BigInt> _spectrum = {};
  double _gutter = 0, _header = 0, _cellWidth = 0, _cellHeight = 0;

  double get cellWidth => _cellWidth;

  /// The rows this lens shows, and a refusal in the law's own words where it
  /// cannot show them.
  ({List<GridRow> rows, String? refused}) layout();

  /// A cell prints the day's own number when there is room for one.
  bool get numbersDays => _cellWidth >= scene.px('grid.numberAt');

  /// The headings above the columns, or empty for none.
  List<Heading> get headings => const [];

  /// How one mark presents at this weight. The default is what the cell has room
  /// for; Strategic narrows it by authored gate and threshold.
  String presentationOf(Fact fact, DisplayWeight weight) =>
      _cellWidth >= scene.px('grid.nameAt') ? showName : showPip;

  @override
  void paint(Canvas canvas, Size size) {
    hits.clear();
    refusals.clear();
    _spectrum.clear();
    final plan = layout();
    rows = plan.rows;
    if (plan.refused != null) refusals.add((source: lens, message: plan.refused!));
    final days = <BigInt>[
      for (final row in rows)
        for (final day in row.days) ?day,
    ];
    if (days.isEmpty) return paintRefusals(canvas, size);
    _gutter = scene.px('grid.gutter');
    _header = headings.isEmpty ? 0 : scene.px('grid.header');
    final columns = rows.map((row) => row.days.length).reduce((a, b) => a > b ? a : b);
    _cellWidth = (size.width - _gutter) / (columns < 1 ? 1 : columns);
    _cellHeight = (size.height - _header) / rows.length;
    _paintHeadings(canvas, columns);
    final capacity = capacityOf(
      _cellWidth,
      _cellHeight,
      scene.tunable,
      widthKey: 'grid.chipWidth',
      heightKey: 'grid.chipHeight',
      depthKey: 'grid.chipDepth',
    );
    final density = aggregateDensity<Fact>(
      start: Rational(days.reduce((a, b) => a < b ? a : b)),
      end: Rational(days.reduce((a, b) => a > b ? a : b) + BigInt.one),
      perDayBudget: capacity.queryBudget,
      queryDay: _queryDay,
      identify: (fact) => fact.order,
    );
    for (final error in density.errors) {
      refusals.add((source: error.pattern, message: error.message));
    }
    refusals.addAll(companionRefusals(scene.engine, scene.projection));
    final byDay = {for (final day in density.days) day.day: day};
    for (final (index, row) in rows.indexed) {
      _paintGutter(canvas, index, row.label);
      for (final (column, day) in row.days.indexed) {
        if (day == null) continue;
        _paintCell(canvas, cellAt(index, column), day, byDay[day], capacity);
      }
    }
    _paintSpectrum(canvas);
    _paintNow(canvas);
    paintRefusals(canvas, size);
  }

  DayResult<Fact> _queryDay(BigInt day, BigInt after, int budget) {
    final result = scene.engine.queryFacts(
      scene.projection,
      start: Rational(day) * law.dayDays,
      end: Rational(after) * law.dayDays,
      limit: budget,
      includeOverlaps: true,
    );
    return (
      facts: result.facts,
      truncated: result.truncated,
      errors: [for (final error in result.errors) (pattern: error.source, message: error.message)],
    );
  }

  Rect cellAt(int row, int column) => Rect.fromLTWH(
    _gutter + column * _cellWidth,
    _header + row * _cellHeight,
    _cellWidth,
    _cellHeight,
  );

  void _paintHeadings(Canvas canvas, int columns) {
    if (headings.isEmpty) return;
    for (var column = 0; column < columns; column += 1) {
      final heading = headings[column % headings.length];
      _text(
        canvas,
        heading.label,
        Rect.fromLTWH(_gutter + column * _cellWidth, 0, _cellWidth, _header),
        isWeekend(heading.cycle) ? scene.theme.primary : scene.theme.muted,
        'grid.labelSize',
        center: true,
      );
    }
  }

  void _paintGutter(Canvas canvas, int row, String label) {
    if (label.isEmpty || _gutter <= 0) return;
    _text(
      canvas,
      label,
      Rect.fromLTWH(0, _header + row * _cellHeight + scene.px('grid.pad'), _gutter, _cellHeight),
      scene.theme.muted,
      'grid.labelSize',
    );
  }

  /// Is this cycle position one the settings call a weekend?
  bool isWeekend(int? cycle) {
    if (cycle == null) return false;
    for (var index = 1; index <= scene.whole('grid.weekendCount'); index += 1) {
      if (scene.whole('grid.weekend.$index') == cycle) return true;
    }
    return false;
  }

  void _text(
    Canvas canvas,
    String text,
    Rect box,
    Color color,
    String key, {
    bool center = false,
    bool data = false,
  }) =>
      paintLabel(canvas, scene.theme, text, box, color, scene.px(key), center: center, data: data);

  void _wash(Canvas canvas, Rect box, Color color, String key) =>
      paintWash(canvas, box, color, scene.px(key));

  int? weekdayOf(BigInt day) => scene.law.cycleIndex('weekday', Rational(day) * law.dayDays);

  /// The two pens, once per paint. Stroked, because a cell is ruled and not
  /// filled; the tones and widths are the ladder's, so a grid and a rail read
  /// the same two tiers.
  late final ({Paint major, Paint minor}) pens = () {
    final pair = rulePens(scene.theme, scene.tunable);
    pair.major.style = PaintingStyle.stroke;
    pair.minor.style = PaintingStyle.stroke;
    return pair;
  }();

  /// Does this day open a turn of the law's own weekday cycle? That boundary is
  /// the major one across a sheet -- the week, where the law declares one.
  bool startsCycle(BigInt day) {
    final names = scene.law.weekdayNames();
    if (names == null || names.isEmpty) return false;
    return weekdayOf(day) == scene.whole('wall.firstWeekday') % names.length;
  }

  /// Does this day open one of this grid's own rows? The row is the coarser unit
  /// every grid lens lays out in -- a week, a month -- read off the layout it
  /// already produced rather than from a lens name.
  bool startsRow(BigInt day) {
    for (final row in rows) {
      if (row.days.isNotEmpty && row.days.first == day) return true;
    }
    return false;
  }

  BigInt? get todayOrdinal => law.mapsToClock ? law.dayOf(scene.nowDays) : null;

  void _paintCell(
    Canvas canvas,
    Rect cell,
    BigInt day,
    DensityDay<Fact>? found,
    Capacity capacity,
  ) {
    final pad = scene.px('grid.pad');
    final start = Rational(day) * law.dayDays;
    final today = todayOrdinal;
    if (isWeekend(weekdayOf(day))) _wash(canvas, cell, scene.theme.muted, 'grid.washWeekend');
    if (today != null && day < today) _wash(canvas, cell, scene.theme.muted, 'grid.washPast');
    if (today != null && day == today) _wash(canvas, cell, scene.theme.accent, 'grid.washToday');
    if (today != null && day < today) {
      // The record slash: a day already spent, struck once across its cell.
      canvas.drawLine(
        cell.bottomLeft,
        cell.topRight,
        Paint()
          ..strokeWidth = scene.px('grid.rule')
          ..color = scene.theme.hair.withValues(alpha: scene.px('grid.slashPast')),
      );
    }
    // TWO TIERS, HERE TOO (ruled 2026-08-31): the cell boundary is the MINOR
    // rule -- a day -- and the coarser unit this grid lays out in carries the
    // MAJOR one, so the sheet never reads as one undifferentiated tone. Which
    // boundary is major comes from the LAW's own cycle, never from a Saturday.
    final ruled = Rect.fromLTRB(
      crisp(cell.left),
      crisp(cell.top),
      crisp(cell.right),
      crisp(cell.bottom),
    );
    canvas.drawRect(ruled, pens.minor);
    if (startsCycle(day)) canvas.drawLine(ruled.topLeft, ruled.bottomLeft, pens.major);
    if (startsRow(day)) canvas.drawLine(ruled.topLeft, ruled.topRight, pens.major);
    var top = cell.top + pad;
    if (numbersDays) {
      _text(
        canvas,
        law.law.fromDays(start).value(law.law.baseLevel, ''),
        Rect.fromLTWH(cell.left + pad, top, cell.width - pad * 2, scene.px('grid.numberSize')),
        today == day ? scene.theme.primary : scene.theme.muted,
        'grid.numberSize',
        data: true,
      );
      top += scene.px('grid.numberSize') + pad;
    }
    if (found == null) return;
    final ranked = <({Fact fact, DisplayWeight weight})>[];
    for (final fact in found.facts) {
      final weight = factDisplayWeight(scene, fact, keyPrefix: lens);
      if (_spectrums(fact, weight)) _reach(day, today);
      if (presentationOf(fact, weight) != showNone) ranked.add((fact: fact, weight: weight));
    }
    ranked.sort((a, b) => b.weight.weight.compareTo(a.weight.weight));
    final admitted = admit(ranked, capacity, queryTruncated: found.truncated);
    final height = scene.px('grid.chipHeight');
    for (final entry in admitted.drawn) {
      if (top + height > cell.bottom - pad) break;
      _paintMark(
        canvas,
        Rect.fromLTWH(cell.left + pad, top, cell.width - pad * 2, height),
        entry.fact,
        entry.weight,
        start,
      );
      top += height + pad;
    }
    final hidden = found.minimum - admitted.drawn.length;
    if (hidden <= 0) return;
    _text(
      canvas,
      '$hidden+',
      Rect.fromLTWH(
        cell.left + pad,
        cell.bottom - scene.px('grid.overflowSize') - pad,
        cell.width - pad * 2,
        scene.px('grid.overflowSize'),
      ),
      scene.theme.muted,
      'grid.overflowSize',
      data: true,
    );
  }

  /// The ToDo spectrum: an unresolved todo tints the days between now and where
  /// it is stapled, on its own cells and never as a second object. Done and
  /// closed never spectrum -- their state already says what they are.
  bool _spectrums(Fact fact, DisplayWeight weight) =>
      law.mapsToClock &&
      objectKindForEvent(fact.event) == 'todo' &&
      weight.state != 'done' &&
      weight.state != 'closed';

  void _reach(BigInt day, BigInt? today) {
    if (today == null) return;
    for (var at = day < today ? day : today; at <= (day < today ? today : day); at += BigInt.one) {
      _spectrum.add(at);
    }
  }

  void _paintSpectrum(Canvas canvas) {
    for (final (row, line) in rows.indexed) {
      for (final (column, day) in line.days.indexed) {
        if (day == null || !_spectrum.contains(day)) continue;
        _wash(canvas, cellAt(row, column), scene.theme.secondary, 'grid.washSpectrum');
      }
    }
  }

  void _paintMark(Canvas canvas, Rect box, Fact fact, DisplayWeight weight, Rational dayStart) {
    final color = cascade.colorOf(fact);
    final duration = scene.engine.eventDurationDays(fact.event);
    if (zoneFill(scene.engine, fact, scene.tunable)) {
      final band = zoneBand(
        box,
        color,
        zoneSegment((
          fact: fact,
          day: law.dayOf(dayStart),
          startMinute: Rational.zero,
          endMinute: Rational.zero,
          continuation: fact.day < dayStart,
          continuesAfter: fact.day + duration > dayStart + law.dayDays,
        )),
        scene.theme,
        scene.tunable,
      );
      canvas.drawRRect(band.shape, band.fill);
      canvas.drawRRect(band.shape, band.edge);
    }
    final spec = markSpecFor(scene, law, fact, weight, color);
    final pip = scene.px('grid.pipSize');
    final hit = spec.paint(
      canvas,
      Rect.fromLTWH(box.left, box.center.dy - pip / 2, pip, pip),
      fact,
    );
    hits.add((bounds: box, shape: null, grab: null, fact: fact, identity: hit.identity));
    if (scene.isSelected(fact)) paintSelection(canvas, Path()..addRect(box));
    final title = '${fact.event.payload?['title'] ?? ''}';
    if (presentationOf(fact, weight) != showName || title.isEmpty) return;
    _text(
      canvas,
      title,
      Rect.fromLTWH(
        box.left + pip + scene.px('grid.pad'),
        box.top,
        box.width - pip - scene.px('grid.pad'),
        box.height,
      ),
      scene.theme.ink.withValues(alpha: spec.opacity),
      'grid.labelSize',
    );
  }

  void _paintNow(Canvas canvas) {
    final at = nowIn(law, scene.nowDays);
    final point = at == null ? null : project(at);
    if (point == null) return;
    paintNow(canvas, point, point.translate(0, _cellHeight), scene.theme, scene.tunable);
  }

  /// The cell corner of the day [days] falls in. A grid counts whole days, so
  /// this and [unproject] agree to exactly one day.
  @override
  Offset? project(Rational days) {
    final day = law.dayOf(days);
    for (final (row, line) in rows.indexed) {
      final column = line.days.indexOf(day);
      if (column >= 0) return cellAt(row, column).topLeft;
    }
    return null;
  }

  @override
  Rational? unproject(Offset at) {
    if (_cellWidth <= 0 || _cellHeight <= 0) return null;
    final row = ((at.dy - _header) / _cellHeight).floor();
    final column = ((at.dx - _gutter) / _cellWidth).floor();
    if (row < 0 || row >= rows.length || column < 0) return null;
    final line = rows[row].days;
    if (column >= line.length || line[column] == null) return null;
    return Rational(line[column]!) * law.dayDays;
  }
}
