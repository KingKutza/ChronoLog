// The spec is generative (Don, 2026-08-27): "We should never be testing for a
// specific case, we should be testing for a general case." Every assertion
// below is a property quantified over seeded random generation. The one
// exception is labelled RULED ANCHOR — a correspondence that is asserted law,
// not a derivable property, and therefore cannot be generated.
//
// The seed is fixed so a failure reproduces exactly. Change it only to widen
// coverage deliberately, never to make a red suite green.

import 'dart:math';

import 'package:chronolog/core/exact.dart';
import 'package:test/test.dart';

const specSeed = 20260827;
const iterations = 250;

// --- Generators --------------------------------------------------------------

BigInt _bigInt(Random r, {int digits = 12, bool nonZero = false}) {
  var value = BigInt.zero;
  for (var i = 0; i < digits; i++) {
    value = value * BigInt.from(10) + BigInt.from(r.nextInt(10));
  }
  if (nonZero && value == BigInt.zero) {
    value = BigInt.one;
  }
  return r.nextBool() ? -value : value;
}

Rational _rational(Random r, {int digits = 8}) =>
    Rational(_bigInt(r, digits: digits), _bigInt(r, digits: digits, nonZero: true));

Rational _nonZeroRational(Random r, {int digits = 8}) {
  final value = _rational(r, digits: digits);
  return value.isZero ? Rational.one : value;
}

// Years span BCE through the far future and well past four digits: the JS spec
// exercised -100,000,000 .. 100,000,000, and nothing in the kernel narrows it.
BigInt _year(Random r) => _bigInt(r, digits: const [1, 2, 4, 4, 7, 9, 12][r.nextInt(7)]);

CivilDay _civil(Random r) {
  final year = _year(r);
  final month = 1 + r.nextInt(12);
  return (year: year, month: month, day: 1 + r.nextInt(daysInMonth(year, month)));
}

String _decimalText(Random r, int wholeDigits, int fractionDigits) {
  final text = StringBuffer(r.nextBool() ? '-' : '');
  for (var i = 0; i < wholeDigits; i++) {
    text.write(r.nextInt(10));
  }
  if (fractionDigits > 0) {
    text.write('.');
    for (var i = 0; i < fractionDigits; i++) {
      text.write(r.nextInt(10));
    }
  }
  return text.toString();
}

void main() {
  group('Rational canonical form', () {
    test('every value is stored reduced with a positive denominator', () {
      final r = Random(specSeed);
      for (var i = 0; i < iterations; i++) {
        final value = _rational(r);
        expect(value.d > BigInt.zero, isTrue, reason: '$value');
        expect(value.n.gcd(value.d), BigInt.one, reason: '$value');
      }
    });

    test('scaling numerator and denominator by the same factor is identity', () {
      final r = Random(specSeed);
      for (var i = 0; i < iterations; i++) {
        final n = _bigInt(r, digits: 6);
        final d = _bigInt(r, digits: 6, nonZero: true);
        final k = _bigInt(r, digits: 4, nonZero: true);
        expect(Rational(n * k, d * k), Rational(n, d));
      }
    });

    test('a zero denominator is refused for any numerator', () {
      final r = Random(specSeed);
      for (var i = 0; i < iterations; i++) {
        final n = _bigInt(r, digits: 6);
        expect(() => Rational(n, BigInt.zero), throwsRangeError);
        expect(() => Rational.parse('${n.abs()}/0'), throwsRangeError);
      }
    });
  });

  group('field axioms', () {
    test('addition is invertible: (a + b) - b == a', () {
      final r = Random(specSeed);
      for (var i = 0; i < iterations; i++) {
        final a = _rational(r);
        final b = _rational(r);
        expect((a + b) - b, a);
        expect(a + -a, Rational.zero);
        expect(a + Rational.zero, a);
      }
    });

    test('multiplication is invertible: (a * b) / b == a for b != 0', () {
      final r = Random(specSeed);
      for (var i = 0; i < iterations; i++) {
        final a = _rational(r);
        final b = _nonZeroRational(r);
        expect((a * b) / b, a);
        expect(a * Rational.one, a);
      }
    });

    test('addition and multiplication commute and associate', () {
      final r = Random(specSeed);
      for (var i = 0; i < iterations; i++) {
        final a = _rational(r);
        final b = _rational(r);
        final c = _rational(r);
        expect(a + b, b + a);
        expect(a * b, b * a);
        expect((a + b) + c, a + (b + c));
        expect((a * b) * c, a * (b * c));
      }
    });

    test('multiplication distributes over addition', () {
      final r = Random(specSeed);
      for (var i = 0; i < iterations; i++) {
        final a = _rational(r);
        final b = _rational(r);
        final c = _rational(r);
        expect(a * (b + c), a * b + a * c);
      }
    });

    test('abs is idempotent, non-negative, and magnitude-preserving', () {
      final r = Random(specSeed);
      for (var i = 0; i < iterations; i++) {
        final a = _rational(r);
        expect(a.abs().isNegative, isFalse);
        expect(a.abs().abs(), a.abs());
        expect(a.abs() == a || a.abs() == -a, isTrue);
      }
    });

    test('integer powers agree with repeated multiplication', () {
      final r = Random(specSeed);
      for (var i = 0; i < iterations; i++) {
        final a = _nonZeroRational(r, digits: 3);
        final k = r.nextInt(7);
        var product = Rational.one;
        for (var step = 0; step < k; step++) {
          product = product * a;
        }
        expect(a.pow(k), product);
        expect(a.pow(-k) * a.pow(k), Rational.one);
      }
      expect(_rational(Random(specSeed)).pow(0), Rational.one);
    });
  });

  group('total order', () {
    test('compareTo, the comparison operators, and == all agree', () {
      final r = Random(specSeed);
      for (var i = 0; i < iterations; i++) {
        final a = _rational(r);
        final b = r.nextInt(8) == 0 ? a : _rational(r);
        final order = a.compareTo(b).sign;
        expect(a < b, order < 0);
        expect(a > b, order > 0);
        expect(a <= b, order <= 0);
        expect(a >= b, order >= 0);
        expect(a == b, order == 0);
        expect(b.compareTo(a).sign, -order);
        if (a == b) {
          expect(a.hashCode, b.hashCode);
        }
      }
    });

    test('sorting by compareTo yields a non-decreasing sequence', () {
      final r = Random(specSeed);
      for (var i = 0; i < iterations; i++) {
        final values = List.generate(9, (_) => _rational(r))..sort();
        for (var k = 1; k < values.length; k++) {
          expect(values[k - 1] <= values[k], isTrue);
        }
      }
    });

    test('order is preserved by adding a common term', () {
      final r = Random(specSeed);
      for (var i = 0; i < iterations; i++) {
        final a = _rational(r);
        final b = _rational(r);
        final c = _rational(r);
        expect((a + c).compareTo(b + c).sign, a.compareTo(b).sign);
      }
    });
  });

  group('decimal text', () {
    test('a decimal literal survives parse and format exactly', () {
      final r = Random(specSeed);
      for (var i = 0; i < iterations; i++) {
        final places = r.nextInt(12);
        final text = _decimalText(r, 1 + r.nextInt(9), places);
        final value = Rational.parse(text);
        expect(Rational.parse(value.toDecimal(places)), value, reason: text);
      }
    });

    test('toDecimal truncates toward zero within one unit of the last place', () {
      final r = Random(specSeed);
      for (var i = 0; i < iterations; i++) {
        final value = _rational(r);
        final places = r.nextInt(20);
        final shown = Rational.parse(value.toDecimal(places));
        final bound = Rational(BigInt.one, BigInt.from(10).pow(places));
        expect((value - shown).abs() < bound, isTrue, reason: '$value');
        expect(shown.abs() <= value.abs(), isTrue, reason: '$value');
      }
    });

    test('scientific notation is exact at any exponent a double would flush', () {
      final r = Random(specSeed);
      final ten = Rational(BigInt.from(10));
      for (var i = 0; i < iterations; i++) {
        final digits = _bigInt(r, digits: 1 + r.nextInt(6));
        final exponent = r.nextInt(801) - 400;
        expect(Rational.parse('${digits}e$exponent'), Rational(digits) * ten.pow(exponent));
      }
    });

    // Both accepted shapes require at least one digit in the mantissa, so any
    // string drawn from a digit-free alphabet must be refused whatever its
    // arrangement of signs, separators and exponent markers.
    test('text that names no digits is refused', () {
      final r = Random(specSeed);
      const alphabet = '+-.eE /abcxyz';
      for (var i = 0; i < iterations; i++) {
        final text = StringBuffer();
        for (var k = 0; k < 1 + r.nextInt(7); k++) {
          text.write(alphabet[r.nextInt(alphabet.length)]);
        }
        expect(() => Rational.parse(text.toString()), throwsA(anything), reason: '"$text"');
      }
    });
  });

  group('JSON round trip', () {
    test('parsing a serialized value reproduces it exactly', () {
      final r = Random(specSeed);
      for (var i = 0; i < iterations; i++) {
        final value = _rational(r, digits: 14);
        expect(Rational.parse(value.toJson()), value, reason: value.toJson());
      }
    });

    test('the serialized shape is bare integer iff the denominator is one', () {
      final r = Random(specSeed);
      for (var i = 0; i < iterations; i++) {
        final value = r.nextBool() ? _rational(r) : Rational(_bigInt(r, digits: 6));
        final json = value.toJson();
        expect(json.contains('/'), value.d != BigInt.one, reason: json);
        expect(json, value.toString());
      }
    });
  });

  group('floored division', () {
    test('the division identity holds for every sign combination', () {
      final r = Random(specSeed);
      for (var i = 0; i < iterations; i++) {
        final a = _bigInt(r, digits: 1 + r.nextInt(14));
        final b = _bigInt(r, digits: 1 + r.nextInt(6), nonZero: true);
        expect(floorDiv(a, b) * b + floorMod(a, b), a, reason: '$a / $b');
      }
    });

    test('the remainder takes the sign of the divisor and stays in range', () {
      final r = Random(specSeed);
      for (var i = 0; i < iterations; i++) {
        final a = _bigInt(r, digits: 1 + r.nextInt(14));
        final b = _bigInt(r, digits: 1 + r.nextInt(6), nonZero: true);
        final m = floorMod(a, b);
        expect(m.abs() < b.abs(), isTrue, reason: '$a mod $b = $m');
        if (m != BigInt.zero) {
          expect(m.isNegative, b.isNegative, reason: '$a mod $b = $m');
        }
      }
    });

    test('floorDiv is the floor of the exact quotient', () {
      final r = Random(specSeed);
      for (var i = 0; i < iterations; i++) {
        final a = _bigInt(r, digits: 1 + r.nextInt(14));
        final b = _bigInt(r, digits: 1 + r.nextInt(6), nonZero: true);
        expect((Rational(a) / Rational(b)).floor(), floorDiv(a, b));
      }
    });

    test('dividing by zero is refused for any dividend', () {
      final r = Random(specSeed);
      for (var i = 0; i < iterations; i++) {
        final a = _bigInt(r, digits: 8);
        expect(() => floorDiv(a, BigInt.zero), throwsRangeError);
        expect(() => floorMod(a, BigInt.zero), throwsRangeError);
      }
    });

    test('the Rational remainder is floored the same way', () {
      final r = Random(specSeed);
      for (var i = 0; i < iterations; i++) {
        final a = _rational(r, digits: 5);
        final b = _nonZeroRational(r, digits: 5);
        final m = a % b;
        expect(m.abs() < b.abs(), isTrue, reason: '$a mod $b = $m');
        if (!m.isZero) {
          expect(m.isNegative, b.isNegative, reason: '$a mod $b = $m');
        }
        expect(((a - m) / b).d, BigInt.one, reason: '$a mod $b = $m');
      }
    });

    test('floor, ceil, and round bracket the value correctly', () {
      final r = Random(specSeed);
      final half = Rational(BigInt.one, BigInt.two);
      for (var i = 0; i < iterations; i++) {
        final a = _rational(r);
        final low = Rational(a.floor());
        final high = Rational(a.ceil());
        expect(low <= a, isTrue);
        expect(a <= high, isTrue);
        expect(high - low <= Rational.one, isTrue);
        expect((a - Rational(a.round())).abs() <= half, isTrue);
        final whole = Rational(_bigInt(r, digits: 6));
        expect(Rational(whole.floor()), whole);
        expect(Rational(whole.ceil()), whole);
        expect(Rational(whole.round()), whole);
      }
    });
  });

  group('proleptic Gregorian kernel', () {
    test('RULED ANCHOR: day zero is 1970-01-01', () {
      expect(daysFromCivil(BigInt.from(1970), 1, 1), BigInt.zero);
      expect(civilFromDays(BigInt.zero), (year: BigInt.from(1970), month: 1, day: 1));
    });

    test('civil to days and back is reversible across the whole horizon', () {
      final r = Random(specSeed);
      for (var i = 0; i < iterations; i++) {
        final date = _civil(r);
        final days = daysFromCivil(date.year, date.month, date.day);
        expect(civilFromDays(days), date, reason: '$date');
      }
    });

    test('days to civil and back is reversible for any day ordinal', () {
      final r = Random(specSeed);
      for (var i = 0; i < iterations; i++) {
        final days = _bigInt(r, digits: 1 + r.nextInt(14));
        final date = civilFromDays(days);
        expect(date.month, inInclusiveRange(1, 12));
        expect(date.day, inInclusiveRange(1, daysInMonth(date.year, date.month)));
        expect(daysFromCivil(date.year, date.month, date.day), days);
      }
    });

    test('day ordinals are strictly monotone in calendar order', () {
      final r = Random(specSeed);
      for (var i = 0; i < iterations; i++) {
        final a = _civil(r);
        final b = _civil(r);
        final order = [
          a.year.compareTo(b.year),
          a.month.compareTo(b.month),
          a.day.compareTo(b.day),
        ].firstWhere((step) => step != 0, orElse: () => 0).sign;
        final delta = daysFromCivil(
          a.year,
          a.month,
          a.day,
        ).compareTo(daysFromCivil(b.year, b.month, b.day)).sign;
        expect(delta, order, reason: '$a vs $b');
      }
    });

    test('consecutive day ordinals name consecutive civil days', () {
      final r = Random(specSeed);
      for (var i = 0; i < iterations; i++) {
        final days = _bigInt(r, digits: 1 + r.nextInt(12));
        final today = civilFromDays(days);
        final tomorrow = civilFromDays(days + BigInt.one);
        final rolls = today.day == daysInMonth(today.year, today.month);
        expect(tomorrow.day, rolls ? 1 : today.day + 1, reason: '$today');
        if (!rolls) {
          expect(tomorrow.month, today.month);
          expect(tomorrow.year, today.year);
        }
      }
    });

    test('isLeapYear is exactly the divisibility rule, negative years too', () {
      final r = Random(specSeed);
      for (var i = 0; i < iterations; i++) {
        final year = _year(r);
        final by4 = floorMod(year, BigInt.from(4)) == BigInt.zero;
        final by100 = floorMod(year, BigInt.from(100)) == BigInt.zero;
        final by400 = floorMod(year, BigInt.from(400)) == BigInt.zero;
        expect(isLeapYear(year), by4 && (!by100 || by400), reason: '$year');
      }
    });

    test('a leap year is exactly a 366-day year on the days axis', () {
      final r = Random(specSeed);
      for (var i = 0; i < iterations; i++) {
        final year = _year(r);
        final length = daysFromCivil(year + BigInt.one, 1, 1) - daysFromCivil(year, 1, 1);
        expect(length, BigInt.from(isLeapYear(year) ? 366 : 365), reason: '$year');
      }
    });

    test('daysInMonth sums to the year length and February follows the rule', () {
      final r = Random(specSeed);
      for (var i = 0; i < iterations; i++) {
        final year = _year(r);
        var total = 0;
        for (var month = 1; month <= 12; month++) {
          total += daysInMonth(year, month);
        }
        expect(total, isLeapYear(year) ? 366 : 365, reason: '$year');
        expect(daysInMonth(year, 2), isLeapYear(year) ? 29 : 28);
      }
    });

    test('daysInMonth is the gap between successive first-of-months', () {
      final r = Random(specSeed);
      for (var i = 0; i < iterations; i++) {
        final year = _year(r);
        final month = 1 + r.nextInt(12);
        final nextYear = month == 12 ? year + BigInt.one : year;
        final nextMonth = month == 12 ? 1 : month + 1;
        final gap = daysFromCivil(nextYear, nextMonth, 1) - daysFromCivil(year, month, 1);
        expect(gap, BigInt.from(daysInMonth(year, month)), reason: '$year-$month');
      }
    });

    test('the 400-year era repeats exactly 146097 days', () {
      final r = Random(specSeed);
      for (var i = 0; i < iterations; i++) {
        final date = _civil(r);
        final shifted = daysFromCivil(date.year + BigInt.from(400), date.month, date.day);
        final base = daysFromCivil(date.year, date.month, date.day);
        expect(shifted - base, BigInt.from(146097), reason: '$date');
      }
    });
  });

  group('nowDays', () {
    test('an injected clock decides the ordinal, to the second', () {
      final r = Random(specSeed);
      for (var i = 0; i < iterations; i++) {
        final reading = DateTime(
          1900 + r.nextInt(400),
          1 + r.nextInt(12),
          1 + r.nextInt(28),
          r.nextInt(24),
          r.nextInt(60),
          r.nextInt(60),
        );
        final expected =
            Rational(daysFromCivil(BigInt.from(reading.year), reading.month, reading.day)) +
            Rational.fromInt(reading.hour, 24) +
            Rational.fromInt(reading.minute, 1440) +
            Rational.fromInt(reading.second, 86400);
        expect(nowDays(() => reading), expected, reason: '$reading');
        expect(
          nowDays(() => reading).floor(),
          daysFromCivil(BigInt.from(reading.year), reading.month, reading.day),
        );
      }
    });

    test('a differing seconds component always changes the ordinal', () {
      final r = Random(specSeed);
      for (var i = 0; i < iterations; i++) {
        final second = r.nextInt(59);
        final base = DateTime(2026, 8, 27, r.nextInt(24), r.nextInt(60), second);
        final later = base.add(Duration(seconds: 1 + r.nextInt(59 - second)));
        expect(nowDays(() => base) < nowDays(() => later), isTrue);
      }
    });

    test('the default clock is the host clock', () {
      final before = nowDays(DateTime.now);
      final actual = nowDays();
      final after = nowDays(DateTime.now);
      expect(before <= actual, isTrue);
      expect(actual <= after, isTrue);
    });
  });
}
