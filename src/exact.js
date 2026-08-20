// --- BigInt helpers -------------------------------------------------------

const TEN = 10n;

function absBigInt(value) {
  return value < 0n ? -value : value;
}

function gcd(a, b) {
  a = absBigInt(a);
  b = absBigInt(b);
  while (b) [a, b] = [b, a % b];
  return a || 1n;
}

export function floorDiv(a, b) {
  if (b === 0n) throw new RangeError("Division by zero");
  let quotient = a / b;
  const remainder = a % b;
  if (remainder !== 0n && (remainder < 0n) !== (b < 0n)) quotient -= 1n;
  return quotient;
}

export function floorMod(a, b) {
  return a - floorDiv(a, b) * b;
}

// --- Rational: arbitrary-precision exact fractions -------------------------

export class Rational {
  constructor(numerator, denominator = 1n) {
    let n = typeof numerator === "bigint" ? numerator : BigInt(numerator);
    let d = typeof denominator === "bigint" ? denominator : BigInt(denominator);
    if (d === 0n) throw new RangeError("Division by zero");
    if (d < 0n) {
      n = -n;
      d = -d;
    }
    const divisor = gcd(n, d);
    this.n = n / divisor;
    this.d = d / divisor;
    Object.freeze(this);
  }

  static parse(value) {
    if (value instanceof Rational) return value;
    if (typeof value === "bigint") return new Rational(value);
    if (typeof value === "number") {
      if (!Number.isFinite(value)) throw new TypeError("A rational must be finite");
      return Rational.parse(String(value));
    }
    const text = String(value).trim();
    const fraction = /^([+-]?\d+)\/(\d+)$/.exec(text);
    if (fraction) return new Rational(BigInt(fraction[1]), BigInt(fraction[2]));
    const decimal = /^([+-]?)(\d*)(?:\.(\d*))?(?:[eE]([+-]?\d+))?$/.exec(text);
    if (!decimal || (!decimal[2] && !decimal[3])) throw new TypeError(`Invalid exact number: ${text}`);
    const sign = decimal[1] === "-" ? -1n : 1n;
    const whole = decimal[2] || "0";
    const part = decimal[3] || "";
    const exponent = Number(decimal[4] || 0) - part.length;
    const digits = BigInt((whole + part).replace(/^0+(?=\d)/, "") || "0") * sign;
    return exponent >= 0
      ? new Rational(digits * TEN ** BigInt(exponent))
      : new Rational(digits, TEN ** BigInt(-exponent));
  }

  add(other) {
    const value = Rational.parse(other);
    return new Rational(this.n * value.d + value.n * this.d, this.d * value.d);
  }

  sub(other) {
    const value = Rational.parse(other);
    return new Rational(this.n * value.d - value.n * this.d, this.d * value.d);
  }

  mul(other) {
    const value = Rational.parse(other);
    return new Rational(this.n * value.n, this.d * value.d);
  }

  div(other) {
    const value = Rational.parse(other);
    return new Rational(this.n * value.d, this.d * value.n);
  }

  neg() {
    return new Rational(-this.n, this.d);
  }

  abs() {
    return new Rational(absBigInt(this.n), this.d);
  }

  pow(exponent) {
    const power = typeof exponent === "bigint" ? exponent : BigInt(exponent);
    if (power < 0n) return new Rational(this.d ** -power, this.n ** -power);
    return new Rational(this.n ** power, this.d ** power);
  }

  floor() {
    return floorDiv(this.n, this.d);
  }

  ceil() {
    return -floorDiv(-this.n, this.d);
  }

  mod(other) {
    const value = Rational.parse(other);
    return this.sub(value.mul(this.div(value).floor()));
  }

  compare(other) {
    const value = Rational.parse(other);
    const delta = this.n * value.d - value.n * this.d;
    return delta < 0n ? -1 : delta > 0n ? 1 : 0;
  }

  isZero() {
    return this.n === 0n;
  }

  toNumber() {
    return Number(this.n) / Number(this.d);
  }

  toDecimal(places = 18) {
    const negative = this.n < 0n;
    const numerator = absBigInt(this.n);
    const whole = numerator / this.d;
    let remainder = numerator % this.d;
    if (!remainder) return `${negative ? "-" : ""}${whole}`;
    let digits = "";
    for (let index = 0; index < places && remainder; index += 1) {
      remainder *= 10n;
      digits += remainder / this.d;
      remainder %= this.d;
    }
    return `${negative ? "-" : ""}${whole}.${digits.replace(/0+$/, "") || "0"}`;
  }

  toJSON() {
    return this.d === 1n ? this.n.toString() : `${this.n}/${this.d}`;
  }

  toString() {
    return this.toJSON();
  }
}

export const ZERO = new Rational(0n);
export const ONE = new Rational(1n);

// A fixed, versioned π constant makes range reduction independent of host Math.
export const PI = Rational.parse(
  "3.141592653589793238462643383279502884197169399375105820974944592307816406286"
);
export const TAU = PI.mul(2);

// --- Transcendental functions (fixed-point series, no host Math) ----------

function roundRational(value, decimalPlaces) {
  const rational = Rational.parse(value);
  const scale = TEN ** BigInt(decimalPlaces);
  const scaled = rational.mul(scale);
  const half = new Rational(1n, 2n);
  const rounded = scaled.n < 0n
    ? scaled.sub(half).ceil()
    : scaled.add(half).floor();
  return new Rational(rounded, scale);
}

export function sinExact(value, decimalPlaces = 30) {
  const workingPlaces = decimalPlaces + 8;
  let x = roundRational(Rational.parse(value).mod(TAU), workingPlaces);
  if (x.compare(PI) > 0) x = x.sub(TAU);
  if (x.compare(PI.neg()) < 0) x = x.add(TAU);

  let term = x;
  let sum = x;
  const limit = new Rational(1n, TEN ** BigInt(workingPlaces));
  for (let index = 1n; index < 256n; index += 1n) {
    const divisor = (2n * index) * (2n * index + 1n);
    term = roundRational(term.mul(x).mul(x).div(divisor).neg(), workingPlaces);
    sum = roundRational(sum.add(term), workingPlaces);
    if (term.abs().compare(limit) < 0) break;
  }
  return roundRational(sum, decimalPlaces);
}

export function cosExact(value, decimalPlaces = 30) {
  return sinExact(Rational.parse(value).add(PI.div(2)), decimalPlaces);
}

export function sqrtExact(value, decimalPlaces = 30) {
  const input = Rational.parse(value);
  if (input.compare(0) < 0) throw new RangeError("Square root of a negative value");
  if (input.isZero()) return ZERO;
  const workingPlaces = decimalPlaces + 8;
  const exponent = BigInt(input.n.toString(2).length - input.d.toString(2).length);
  const half = exponent >> 1n;
  let guess = half >= 0n ? new Rational(2n ** half) : new Rational(1n, 2n ** -half);
  const limit = new Rational(1n, TEN ** BigInt(decimalPlaces + 6));
  for (let index = 0; index < 128; index += 1) {
    const next = roundRational(guess.add(input.div(guess)).div(2), workingPlaces);
    if (next.isZero()) return ZERO;
    if (next.sub(guess).abs().compare(limit) < 0) {
      guess = next;
      break;
    }
    guess = next;
  }
  return roundRational(guess, decimalPlaces);
}

// --- Gregorian calendar conversion -----------------------------------------
// Proleptic Gregorian conversion using arbitrary-size integers.
// Day zero is 1970-01-01, but callers never need to expose that implementation origin.
export function daysFromCivil(yearValue, monthValue, dayValue) {
  let year = BigInt(yearValue);
  const month = BigInt(monthValue);
  const day = BigInt(dayValue);
  year -= month <= 2n ? 1n : 0n;
  const era = floorDiv(year, 400n);
  const yearOfEra = year - era * 400n;
  const shiftedMonth = month + (month > 2n ? -3n : 9n);
  const dayOfYear = floorDiv(153n * shiftedMonth + 2n, 5n) + day - 1n;
  const dayOfEra = yearOfEra * 365n + floorDiv(yearOfEra, 4n)
    - floorDiv(yearOfEra, 100n) + dayOfYear;
  return era * 146097n + dayOfEra - 719468n;
}

export function civilFromDays(dayValue) {
  const z = BigInt(dayValue) + 719468n;
  const era = floorDiv(z, 146097n);
  const dayOfEra = z - era * 146097n;
  const yearOfEra = floorDiv(
    dayOfEra - floorDiv(dayOfEra, 1460n) + floorDiv(dayOfEra, 36524n)
      - floorDiv(dayOfEra, 146096n),
    365n
  );
  let year = yearOfEra + era * 400n;
  const dayOfYear = dayOfEra - (
    365n * yearOfEra + floorDiv(yearOfEra, 4n) - floorDiv(yearOfEra, 100n)
  );
  const monthPrime = floorDiv(5n * dayOfYear + 2n, 153n);
  const day = dayOfYear - floorDiv(153n * monthPrime + 2n, 5n) + 1n;
  const month = monthPrime + (monthPrime < 10n ? 3n : -9n);
  year += month <= 2n ? 1n : 0n;
  return { year, month, day };
}

export function isLeapYear(yearValue) {
  const year = BigInt(yearValue);
  return floorMod(year, 4n) === 0n
    && (floorMod(year, 100n) !== 0n || floorMod(year, 400n) === 0n);
}

export function daysInMonth(yearValue, monthValue) {
  const month = Number(monthValue);
  if (month === 2) return isLeapYear(yearValue) ? 29 : 28;
  return [4, 6, 9, 11].includes(month) ? 30 : 31;
}

// The single sanctioned boundary where host wall-clock time enters domain
// math: this is the one place `new Date()` is read to mean "now" anywhere in
// ChronoLog. It converts that one read into an exact local-civil day ordinal
// (day + hour/minute/second fraction) and never touches `Date` again. AGENTS.md's
// "no Date arithmetic in domain code" rule only holds if every caller shares
// this conversion instead of rebuilding it inline — three call sites once
// duplicated this exact arithmetic (two at minute precision, one at second
// precision); melting them here is what makes the rule enforceable rather
// than aspirational. Do not "fix" this back into per-call-site Date reads.
// Second precision is the canonical one: it is the finer of the two
// precisions that existed, and nothing was found to depend on minute
// truncation (see roster.js/session.js callers). A caller that genuinely
// needs a coarser ordinal should truncate this result explicitly at its own
// call site, not fork a second helper.
// `clock` is an optional injected `Date` (or Date-constructible value) so
// this stays testable without mocking the global `Date`.
// The 24/1440/86400 below are NOT the document's coordinate law and must never
// be melted into it: they are the host operating system's own civil units, the
// only units a `Date` can report. This converts a host reading into a day
// ordinal on the shared days axis; how that ordinal then reads as hours is the
// governing frame's law to decide (src/coordinate-law.js). Same boundary rule as
// ICS: the outside world speaks standard civil time, and conversion happens once
// on the way in.
export function nowDays(clock = new Date()) {
  const date = clock instanceof Date ? clock : new Date(clock);
  return new Rational(daysFromCivil(
    BigInt(date.getFullYear()),
    BigInt(date.getMonth() + 1),
    BigInt(date.getDate())
  ))
    .add(Rational.parse(date.getHours()).div(24))
    .add(Rational.parse(date.getMinutes()).div(1440))
    .add(Rational.parse(date.getSeconds()).div(86400));
}

// --- Nested-coordinate helpers ----------------------------------------------

export function coordinate(levels) {
  return {
    levels: levels
      .filter((entry) => entry.value !== undefined && entry.value !== null)
      .map((entry) => ({ level: String(entry.level), value: String(entry.value) }))
  };
}

export function levelValue(value, name, fallback = "0") {
  const entry = value?.levels?.find((part) => part.level === name);
  return entry ? entry.value : fallback;
}

// Duration magnitudes, nested-coordinate conversion, and the unit ladder that
// used to live here now belong to src/coordinate-law.js: every one of them is a
// question about a FRAME'S DECLARED LAW ("how long is an hour here?"), not a
// question about exact arithmetic, and answering them from a fixed table here is
// what made a frame's levels/radix/transition ladder dead metadata. What remains
// in this module is the arithmetic itself plus the proleptic Gregorian whole-day
// kernel (`daysFromCivil`/`civilFromDays`/`daysInMonth`/`isLeapYear`), which the
// registered Gregorian family calls and nothing else may.
export function formatCivil(value, includeTime = false) {
  const year = levelValue(value, "year", "1970");
  const month = levelValue(value, "month", "1").padStart(2, "0");
  const day = levelValue(value, "day", "1").padStart(2, "0");
  if (!includeTime) return `${year}-${month}-${day}`;
  const hour = levelValue(value, "hour", "0").padStart(2, "0");
  const minute = levelValue(value, "minute", "0").padStart(2, "0");
  const second = levelValue(value, "second", "0").padStart(2, "0");
  return `${year}-${month}-${day} ${hour}:${minute}:${second}`;
}
