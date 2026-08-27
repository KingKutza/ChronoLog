// Pure Dart. Nothing under lib/core/ may import Flutter or a third-party
// package. This file is the numeric substrate every document value rests on,
// so no host floating point may enter any operation that decides a value.

// Hoisted: the calendar kernel runs inside occurrence loops at overscale, and
// `BigInt.from` per call would allocate on every iteration.
final BigInt _b4 = BigInt.from(4),
    _b10 = BigInt.from(10),
    _b100 = BigInt.from(100),
    _b400 = BigInt.from(400),
    _b146097 = BigInt.from(146097),
    _b719468 = BigInt.from(719468);

/// Floored division. Dart's `~/` truncates toward zero and its `%` is
/// Euclidean; the calendar kernel and every modular reduction here need
/// floored semantics, so neither built-in can be substituted.
BigInt floorDiv(BigInt a, BigInt b) {
  if (b == BigInt.zero) throw RangeError('Division by zero');
  final quotient = a ~/ b;
  final remainder = a.remainder(b);
  final short = remainder != BigInt.zero && remainder.isNegative != b.isNegative;
  return short ? quotient - BigInt.one : quotient;
}

/// Remainder under floored division: the sign follows `b`, never `a`.
BigInt floorMod(BigInt a, BigInt b) => a - floorDiv(a, b) * b;

/// An exact fraction over arbitrary-precision integers. Immutable, and always
/// stored reduced with a positive denominator, so one value has exactly one
/// representation and structural equality agrees with [compareTo].
class Rational implements Comparable<Rational> {
  final BigInt n;
  final BigInt d;

  Rational._(this.n, this.d);

  factory Rational(BigInt numerator, [BigInt? denominator]) {
    final d = denominator ?? BigInt.one;
    if (d == BigInt.zero) throw RangeError('Division by zero');
    // A negatively signed gcd reduces and moves the sign out of the
    // denominator in one division.
    final g = numerator.gcd(d) * (d.isNegative ? -BigInt.one : BigInt.one);
    return Rational._(numerator ~/ g, d ~/ g);
  }

  factory Rational.fromInt(int numerator, [int denominator = 1]) =>
      Rational(BigInt.from(numerator), BigInt.from(denominator));

  /// Accepts the serialized form (`3`, `-1/4000`) and decimal or scientific
  /// notation. No double is constructed on this path, so `1e-330` parses
  /// exactly where a host float would flush it to zero.
  factory Rational.parse(String text) {
    final source = text.trim();
    final ratio = _fraction.firstMatch(source);
    if (ratio != null) {
      return Rational(BigInt.parse(ratio[1]!), BigInt.parse(ratio[2]!));
    }
    final m = _decimal.firstMatch(source);
    if (m == null || ((m[2] ?? '').isEmpty && (m[3] ?? '').isEmpty)) {
      throw FormatException('Invalid exact number', text);
    }
    final part = m[3] ?? '';
    final sign = m[1] == '-' ? '-' : '';
    final digits = BigInt.parse('$sign${m[2] ?? ''}$part');
    final power = int.parse(m[4] ?? '0') - part.length;
    return power >= 0 ? Rational(digits * _b10.pow(power)) : Rational(digits, _b10.pow(-power));
  }

  static final RegExp _fraction = RegExp(r'^([+-]?\d+)/(\d+)$');
  static final RegExp _decimal = RegExp(r'^([+-]?)(\d*)(?:\.(\d*))?(?:[eE]([+-]?\d+))?$');
  static final RegExp _trailingZeros = RegExp(r'0+$');

  static final Rational zero = Rational(BigInt.zero);
  static final Rational one = Rational(BigInt.one);
  static final Rational _half = Rational(BigInt.one, BigInt.two);

  Rational operator +(Rational o) => Rational(n * o.d + o.n * d, d * o.d);

  Rational operator -(Rational o) => Rational(n * o.d - o.n * d, d * o.d);

  Rational operator *(Rational o) => Rational(n * o.n, d * o.d);

  Rational operator /(Rational o) => Rational(n * o.d, d * o.n);

  // Negation cannot break the invariant, so it skips reduction.
  Rational operator -() => Rational._(-n, d);

  /// Remainder under floored division, matching [floorMod].
  Rational operator %(Rational o) => this - o * Rational((this / o).floor());

  Rational abs() => n.isNegative ? -this : this;

  Rational pow(int exponent) => exponent < 0
      ? Rational(d.pow(-exponent), n.pow(-exponent))
      : Rational(n.pow(exponent), d.pow(exponent));

  BigInt floor() => floorDiv(n, d);

  BigInt ceil() => -floorDiv(-n, d);

  /// Half away from zero: the only rounding the ported substrate used.
  BigInt round() => n.isNegative ? (this - _half).ceil() : (this + _half).floor();

  @override
  int compareTo(Rational o) => (n * o.d).compareTo(o.n * d);

  bool operator <(Rational o) => compareTo(o) < 0;

  bool operator <=(Rational o) => compareTo(o) <= 0;

  bool operator >(Rational o) => compareTo(o) > 0;

  bool operator >=(Rational o) => compareTo(o) >= 0;

  @override
  bool operator ==(Object other) => other is Rational && n == other.n && d == other.d;

  @override
  int get hashCode => Object.hash(n, d);

  bool get isZero => n == BigInt.zero;

  bool get isNegative => n.isNegative;

  /// Host float, for pixels only: a result of this must never re-enter
  /// document math.
  double toDouble() => n / d;

  /// Truncates rather than rounds, and drops trailing zeros, so any value
  /// expressible in [places] digits survives a [Rational.parse] round trip.
  String toDecimal([int places = 18]) {
    final sign = n.isNegative ? '-' : '';
    final whole = n.abs() ~/ d;
    var rest = n.abs().remainder(d);
    if (rest == BigInt.zero) return '$sign$whole';
    final digits = StringBuffer();
    for (var i = 0; i < places && rest != BigInt.zero; i++) {
      rest *= _b10;
      digits.write(rest ~/ d);
      rest = rest.remainder(d);
    }
    final tail = digits.toString().replaceAll(_trailingZeros, '');
    return '$sign$whole.${tail.isEmpty ? '0' : tail}';
  }

  /// The persisted form. Documents written by the JavaScript implementation
  /// carry exactly these two shapes, so this string is a compatibility
  /// contract, not a formatting choice.
  String toJson() => d == BigInt.one ? '$n' : '$n/$d';

  @override
  String toString() => toJson();
}

typedef CivilDay = ({BigInt year, int month, int day});

/// Proleptic Gregorian whole-day kernel. Day zero is 1970-01-01; that origin
/// is an implementation detail no caller needs to restate. The 400-year era
/// arithmetic cannot be derived from per-level counts, which is why it lives
/// here and not in a frame's declared law. Only the year is unbounded: every
/// intermediate below is proven non-negative and inside a 400-year era, so
/// `int` division is exactly the floored division the formula requires.
BigInt daysFromCivil(BigInt year, int month, int day) {
  final shifted = month <= 2 ? year - BigInt.one : year;
  final era = floorDiv(shifted, _b400);
  final yearOfEra = (shifted - era * _b400).toInt();
  final monthPrime = month + (month > 2 ? -3 : 9);
  final dayOfYear = (153 * monthPrime + 2) ~/ 5 + day - 1;
  final dayOfEra = yearOfEra * 365 + yearOfEra ~/ 4 - yearOfEra ~/ 100 + dayOfYear;
  return era * _b146097 + BigInt.from(dayOfEra) - _b719468;
}

CivilDay civilFromDays(BigInt days) {
  final z = days + _b719468;
  final era = floorDiv(z, _b146097);
  final dayOfEra = (z - era * _b146097).toInt();
  final yearOfEra = (dayOfEra - dayOfEra ~/ 1460 + dayOfEra ~/ 36524 - dayOfEra ~/ 146096) ~/ 365;
  final dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra ~/ 4 - yearOfEra ~/ 100);
  final monthPrime = (5 * dayOfYear + 2) ~/ 153;
  final day = dayOfYear - (153 * monthPrime + 2) ~/ 5 + 1;
  final month = monthPrime + (monthPrime < 10 ? 3 : -9);
  final carry = month <= 2 ? BigInt.one : BigInt.zero;
  return (year: BigInt.from(yearOfEra) + era * _b400 + carry, month: month, day: day);
}

bool isLeapYear(BigInt year) =>
    floorMod(year, _b4) == BigInt.zero &&
    (floorMod(year, _b100) != BigInt.zero || floorMod(year, _b400) == BigInt.zero);

int daysInMonth(BigInt year, int month) =>
    month == 2 ? (isLeapYear(year) ? 29 : 28) : (const {4, 6, 9, 11}.contains(month) ? 30 : 31);

typedef Clock = DateTime Function();

/// The one sanctioned place where host wall-clock time enters domain math: the
/// only read of "now" anywhere in ChronoLog, converted once into an exact day
/// ordinal on the shared days axis. A caller needing a coarser ordinal
/// truncates this result and must not fork a second helper, because the "no
/// Date arithmetic in domain code" rule only holds while every caller shares
/// this conversion. The 24/1440/86400 below are the host operating system's
/// own civil units — the only units a [DateTime] can report — and are NOT the
/// document's coordinate law; how the resulting ordinal reads as hours is the
/// governing frame's law to decide.
Rational nowDays([Clock? clock]) {
  final now = (clock ?? DateTime.now)();
  final date = daysFromCivil(BigInt.from(now.year), now.month, now.day);
  return Rational(date) +
      Rational.fromInt(now.hour, 24) +
      Rational.fromInt(now.minute, 1440) +
      Rational.fromInt(now.second, 86400);
}
