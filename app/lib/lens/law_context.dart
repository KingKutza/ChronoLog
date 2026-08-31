// ONE LAW READ PER PAINT.
//
// Every unit relationship a surface draws with -- hours in a day, minutes in an
// hour, what a weekday is called, what a month is called, whether there is a now
// at all -- comes from the PRIMARY frame's own declared ladder, asked once here
// and read from here by every helper. Setting hours-per-day to 23 on a frame
// therefore changes the rail, the strides, the durations and the clock labels,
// because all of them ask this object. There is no 24 and no 1440 anywhere in
// the lens layer.
//
// The JavaScript did this with a mutable module global set by two entry points.
// Same rule, made a value.

import '../core/coordinate_law.dart';
import '../core/exact.dart';

class LawContext {
  LawContext(this.law);

  /// The two level names this file asks the law about by name. A ladder that
  /// calls its rungs something else answers through its own declaration; these
  /// are the words the standard ladder uses, in one place rather than in six
  /// call sites.
  static const String hourUnit = 'hour', minuteUnit = 'minute';

  final CoordinateLaw law;

  /// This ladder's own day, composed from its radices. A "day" is whatever its
  /// hours make it, so this is the length everything per-day divides by.
  late final Rational dayDays = law.baseDays;

  late final Rational hoursPerDay = law.unitsPer(hourUnit);
  late final Rational minutesPerDay = law.unitsPer(minuteUnit);
  late final Rational minutesPerHour = law.unitsPer(minuteUnit, hourUnit);

  /// The names this frame AUTHORS for the values of its hour level, or null
  /// where it authors none.
  ///
  /// LABELLING IS PART OF THE COORDINATE DEFINITION (ruled 2026-08-31): "12 vs
  /// 24 hour display -- or both, or what have you -- must be settable; and the
  /// frame definition must support arbitrary label setups to enable other
  /// calendars." A level has always carried authored names for its values --
  /// that is how a month is called Ashfall -- and the hour is a level like any
  /// other, so twelve-hour, twenty-four-hour and another world's eight watches
  /// are three AUTHORED setups of one capability rather than three modes this
  /// file knows about.
  late final List<String>? hourNames = law.namesFor(hourUnit);

  /// Is there a now in this frame at all? A calendar of a world with no relation
  /// to this one has none, and drawing a Now line on it invents a fact.
  late final bool mapsToClock = law.mapsToClock();

  late final bool hasWeekdays = law.hasWeekdays();
  late final bool hasMonths = law.hasMonths();
  late final bool hasEras = law.hasEras();

  /// The whole day an instant falls in, and how far into it -- exact, because a
  /// pixel is the only place a double belongs.
  BigInt dayOf(Rational days) => (days / dayDays).floor();

  Rational minuteOfDay(Rational days) =>
      (days - Rational(dayOf(days)) * dayDays) / dayDays * minutesPerDay;

  Rational daysOfMinute(Rational minutes) => minutes / minutesPerDay * dayDays;

  /// Short forms are DERIVED from the authored name, never a parallel
  /// abbreviation table: an authored weekday unlike "Sunday" must abbreviate too.
  String? weekdayShort(Rational days) {
    final label = law.weekdayLabel(days);
    return label == null ? null : _short(label).toUpperCase();
  }

  String? monthShort(int oneBased) {
    final names = law.monthNames();
    if (names == null || oneBased < 1 || oneBased > names.length) return null;
    return _short(names[oneBased - 1]);
  }

  /// The clock reading of a minute-of-day, in THIS law's hours.
  ///
  /// The frame's OWN names for the hour it lands in, where it authors any: what
  /// the label says is the frame's to declare, and a lens that overrode it would
  /// be encoding one right way to name an hour and precluding every other.
  ///
  /// Where a frame authors no hour names there is nothing to read, so the
  /// reading is COMPOSED from the ladder's own radices, which is the only thing
  /// left to say: a 23-hour day offers 23 hours and its own midpoint, and there
  /// is no AM/PM assumption beyond "the first half of the day and the second".
  String clockLabel(Rational minutes) {
    final perHour = minutesPerHour <= Rational.zero ? BigInt.one : minutesPerHour.round();
    final perDay = hoursPerDay <= Rational.zero ? BigInt.one : hoursPerDay.round();
    final whole = minutes.floor();
    final hour = floorMod(floorDiv(whole, perHour), perDay);
    final minute = floorMod(whole, perHour);
    // The minutes past the named hour, in the same shape either reading uses: a
    // frame names its hours, not every minute inside one.
    final tail = minute == BigInt.zero ? '' : ':${'$minute'.padLeft(2, '0')}';
    final authored = hourNames;
    final index = hour.toInt();
    if (authored != null && index >= 0 && index < authored.length) {
      return '${authored[index]}$tail';
    }
    final half = Rational(perDay) / Rational.fromInt(2);
    final suffix = Rational(hour) < half ? 'a' : 'p';
    final wrapped = Rational(hour) % half;
    final shown = wrapped.isZero ? half.ceil() : wrapped.round();
    return '$shown$tail$suffix';
  }

  /// The era-qualified year at a day, or null where the day falls outside every
  /// era the law declares -- omitted rather than shown with an invented year.
  String? eraYear(Rational days) {
    try {
      return law.formatYearAtDays(days);
    } catch (_) {
      return null;
    }
  }

  static String _short(String name) => name.length <= 3 ? name : name.substring(0, 3);
}
