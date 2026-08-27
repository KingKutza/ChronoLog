// Pure Dart. Nothing under lib/core/ may import Flutter or a third-party
// package.
//
// The value codecs of the ICS boundary, and the LAW GATE that decides whether a
// coordinate may become ICS text at all.
//
// GREGORIAN IN, PROJECTIONS OUT. ICS is a ruled LOSSY boundary. What comes in is
// standard civil Gregorian (plus RFC 7529's RSCALE naming another registered
// calendar); what goes out is either a rule ICS can read or a materialized
// projection -- never a frame's own level values dressed up as though they were
// already Gregorian.
//
// WIRE UNITS ARE NOT DOCUMENT LAW. A DURATION's week is always 7*86400 seconds
// and a compact timestamp's hour is always a standard hour, because those are
// the spec's units. A document whose own day is twenty-three hours long does not
// change what somebody else's file said.

import 'coordinate_law.dart';
import 'document.dart' show durationMagnitude;
import 'era_chain.dart' show frameEraContext;
import 'exact.dart';
import 'ics_text.dart';
import 'records.dart';
import 'rrule.dart' show RRule;

/// RFC 5545's own day, read off the REGISTERED standard rather than written as a
/// literal. Every wall-seconds conversion in the boundary goes through this one
/// value, and none of them through a document's own law.
final Rational icsSecondsPerDay = gregorianLaw.unitsPer('second', 'day');

final Rational _twentyFour = Rational.fromInt(24), _sixty = Rational.fromInt(60);

// --- Dates and times --------------------------------------------------------

/// One parsed ICS date or date-time.
///
/// TZID IS AN OPAQUE STRING and nothing here interprets it: no offset is
/// resolved, no DST arithmetic happens, and the same text is echoed back on
/// export. Real timezone semantics are a later ruled design, and pretending to
/// have them would be worse than saying plainly that we do not.
class IcsDate {
  const IcsDate({
    required this.coordinate,
    required this.dateOnly,
    required this.utc,
    this.timeZone,
  });

  final Coordinate coordinate;
  final bool dateOnly;
  final bool utc;
  final String? timeZone;

  /// This instant on the shared exact days axis, read through the REGISTERED
  /// standard -- which is what the wire format's own text means.
  Rational get days => civilCoordinateToDays(coordinate);
}

final RegExp _stamp = RegExp(r'^([+-]?\d{4,})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?$');

/// RFC 5545's compact form, with ONE DELIBERATE DEVIATION: a signed year, and a
/// year of more than four digits, both parse and both re-emit -- so a remote date
/// (`-00440315`, `1000020260806`) survives the round trip instead of being
/// refused at the boundary. `VALUE=DATE` types a value as date-only even when it
/// carries a time, which is what the parameter is for.
IcsDate? parseIcsStamp(String? text, {bool valueDate = false, String? timeZone}) {
  final match = _stamp.firstMatch(text ?? '');
  if (match == null) return null;
  final dateOnly = match[4] == null || valueDate;
  return IcsDate(
    coordinate: Coordinate.of([
      ('year', BigInt.parse(match[1]!)),
      ('month', match[2]),
      ('day', match[3]),
      if (!dateOnly) ...[('hour', match[4]), ('minute', match[5]), ('second', match[6])],
    ]),
    dateOnly: dateOnly,
    utc: match[7] != null,
    timeZone: timeZone,
  );
}

/// One property's value as an instant, with its own typing parameters read off
/// the property. [value] overrides the text for a multi-valued property whose
/// parameters still govern every value -- which is exactly EXDATE.
IcsDate? parseIcsDate(IcsProperty? property, [String? value]) => property == null
    ? null
    : parseIcsStamp(
        value ?? property.value,
        valueDate: property.param('VALUE') == 'DATE',
        timeZone: property.param('TZID'),
      );

String _two(String text) => text.padLeft(2, '0');

/// A coordinate as ICS text. The year is signed and unbounded for the same
/// reason [parseIcsStamp] accepts one.
String coordinateToIcs(Coordinate value, {bool dateOnly = false, bool utc = false}) {
  final year = BigInt.parse(value.value('year', '1970'));
  final signed = '${year.isNegative ? '-' : ''}${year.abs().toString().padLeft(4, '0')}';
  final date = '$signed${_two(value.value('month', '1'))}${_two(value.value('day', '1'))}';
  if (dateOnly) return date;
  return '${date}T${_two(value.value('hour'))}${_two(value.value('minute'))}'
      '${_two(value.value('second'))}${utc ? 'Z' : ''}';
}

/// A coordinate with NO time-of-day rung at all is date-only -- a structural fact
/// about its own level list, and the same test [parseIcsStamp] applies to a
/// timestamp with no `T`.
bool coordinateIsDateOnly(Coordinate value) => !value.has('hour');

/// A wall-clock stamp, from the ONE sanctioned read of host time. Injected by
/// every caller, because a re-export of an unedited document must be byte for
/// byte the previous one and a fresh `DateTime.now()` per call would churn.
String icsTimestamp(DateTime at) {
  final utc = at.toUtc();
  String pad(int value, [int width = 2]) => '$value'.padLeft(width, '0');
  return '${pad(utc.year, 4)}${pad(utc.month)}${pad(utc.day)}'
      'T${pad(utc.hour)}${pad(utc.minute)}${pad(utc.second)}Z';
}

/// THE derivation of a timed value's own parameters, and there is one: a
/// date-only value is typed `VALUE=DATE`, a value in a named zone carries that
/// zone's opaque id back out, and a plain or UTC value needs neither. Every
/// emitted DTSTART, DTEND and EXDATE reads it here rather than spelling its own
/// ternary -- the JavaScript spelled that ternary twice.
List<IcsParam> icsValueParams({bool dateOnly = false, String? timeZone}) {
  if (dateOnly) return _valueDate;
  final zone = timeZone ?? '';
  return zone.isEmpty
      ? const []
      : [
          IcsParam('TZID', [zone]),
        ];
}

const List<IcsParam> _valueDate = [
  IcsParam('VALUE', ['DATE']),
];

// --- Durations --------------------------------------------------------------

final RegExp _duration = RegExp(
  r'^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?)?$',
);

/// RFC 5545's DURATION value type, in WALL SECONDS. A week is always 7*86400, a
/// day 86400, an hour 3600, a minute 60 -- the WIRE FORMAT's units, fixed by the
/// spec. Reading them off a document's law instead would make an imported `PT2H`
/// mean two twenty-thirds of a day on a twenty-three-hour frame, which is not
/// what the file said.
Rational? parseIcsDuration(String? value) {
  final match = _duration.firstMatch(value ?? '');
  if (match == null) return null;
  Rational part(int index, int factor) =>
      Rational.parse(match[index] ?? '0') * Rational.fromInt(factor);
  final total = part(2, 7 * 86400) + part(3, 86400) + part(4, 3600) + part(5, 60) + part(6, 1);
  return match[1] == '-' ? -total : total;
}

// --- Recurrence rules -------------------------------------------------------

/// An RRULE value as its parts by name. Only TOKENIZED: expansion is the
/// projection engine's, and the rule's own text is preserved verbatim beside
/// this, so a part nobody here reads still rides back out.
RRule parseRRule(String value) {
  final rule = <String, String>{};
  for (final part in value.split(';')) {
    if (part.isEmpty) continue;
    final equals = part.indexOf('=');
    // A part with no `=` at all is no rule part. It is kept under its own text
    // with an empty value, so the text survives; the JavaScript's own slice
    // arithmetic ate its last character instead.
    rule[(equals < 0 ? part : part.substring(0, equals)).toUpperCase()] = equals < 0
        ? ''
        : part.substring(equals + 1);
  }
  return rule;
}

String serializeRRule(RRule rrule) =>
    [for (final entry in rrule.entries) '${entry.key}=${entry.value}'].join(';');

/// RFC 7529, and the ONE place RSCALE is normalised.
///
/// A rule counting in the registered `gregory` scale omits the part entirely --
/// RSCALE's own default, and the reason a plain RSCALE-free import re-exports
/// byte-identical. A rule in another REGISTERED scale re-emits it in RFC 7529's
/// canonical upper case, in its own position. A rule naming a calendar nothing
/// here implements passes through EXACTLY AS AUTHORED: this module cannot assert
/// a spelling is spec-correct for a calendar it does not know, and the projection
/// refusal (`unsupportedCalendarScale`) is what tells the author it could not be
/// rendered -- never this function silently rewriting their text.
RRule normalizedRuleForExport(RRule rrule) {
  final requested = rrule['RSCALE'];
  if (requested == null) return rrule;
  final scale = lawForCalendar(requested)?.calendarScale();
  if (scale == null) return rrule;
  if (scale == gregory) {
    return {
      for (final entry in rrule.entries)
        if (entry.key != 'RSCALE') entry.key: entry.value,
    };
  }
  return {
    for (final entry in rrule.entries)
      entry.key: entry.key == 'RSCALE' ? scale.toUpperCase() : entry.value,
  };
}

// --- The law gate -----------------------------------------------------------

/// Whether a coordinate under this law is safe to format straight into ICS text.
///
/// It is only safe when the law's OWN reading of year/month/day/hour/minute/
/// second is RFC 5545's: the same calendar family, a month-and-day ladder (not
/// year-plus-day-of-year, which [coordinateToIcs] would misread as a day of the
/// month), and the standard 24/60/60 radices below the date. Anything else -- an
/// edited hour radix, a fixed block, a formula law -- must be CONVERTED at the
/// boundary instead of emitted as though its level values already meant what ICS
/// expects.
bool isIcsNativeLaw(CoordinateLaw law) =>
    law.calendarScale() == gregory &&
    law.has('month') &&
    law.has('day') &&
    law.unitsPer('hour', 'day') == _twentyFour &&
    law.unitsPer('minute', 'hour') == _sixty &&
    law.unitsPer('second', 'minute') == _sixty;

/// One document's law seam for the boundary: which law governs a frame, what a
/// coordinate is worth in exact days, and the two-step wall-seconds conversion
/// in both directions.
///
/// Frames only. Law resolution reads `coordinate`, `coordinateDefinition`,
/// `basis` and `kind` and nothing else, so serialising the relation map to answer
/// a question about frames would be a deep copy for nothing.
class IcsBoundary {
  IcsBoundary(this.document);

  final Document document;

  late final Map<String, Object?> _frames = {
    'frames': {for (final entry in document.frames.entries) entry.key: entry.value.toJson()},
  };

  late final CoordinateLaws laws = CoordinateLaws(
    eras: (_, frameId) => frameEraContext(document, frameId),
  );

  /// A frame's law, or null when its declaration cannot be resolved. Null rather
  /// than a throw: one unresolvable frame must not take a whole export offline.
  CoordinateLaw? law(String? frameId) =>
      frameId == null ? null : laws.attempt(_frames, frameId).resolved;

  /// A coordinate in exact days under its OWN frame's law, or null when either
  /// the law or the value cannot be read.
  Rational? days(String? frameId, Coordinate? value) {
    if (value == null) return null;
    final resolved = law(frameId);
    if (resolved == null) return null;
    try {
      return resolved.toDays(value);
    } on Object catch (_) {
      return null;
    }
  }

  /// THE crossing from "governed by some frame's own law" to "ICS text".
  ///
  /// A coordinate under the registered standard passes through UNCHANGED -- it
  /// already IS ICS's own language, and an existing round trip stays byte
  /// identical. Any other law is resolved to an exact day ordinal through ITS OWN
  /// law and re-expressed through the registered boundary.
  Coordinate boundaryCoordinate(String? frameId, Coordinate value) {
    final resolved = law(frameId);
    if (resolved == null || isIcsNativeLaw(resolved)) return value;
    final ordinal = days(frameId, value);
    return ordinal == null ? value : daysToCivilCoordinate(ordinal);
  }

  /// A document magnitude's worth in WALL SECONDS for the wire. Two exact steps,
  /// never combined: the magnitude's OWN frame law resolves it to days first (two
  /// hours on a twenty-three-hour-day frame is 2/23 of a day), then the
  /// REGISTERED boundary turns those days into the standard seconds DURATION and
  /// DTEND expect.
  Rational magnitudeSeconds(Magnitude? magnitude) =>
      laws.durationDays(magnitude, document: _frames) * icsSecondsPerDay;

  /// The same conversion the other way: wall seconds into the STORING frame's own
  /// magnitude, so a wall hour survives as a wall hour even where that frame's
  /// own second is not one eighty-six-thousand-four-hundredth of its own day.
  Magnitude magnitudeFromWallSeconds(Rational wallSeconds, [String frame = 'measure:human-time']) {
    final law = laws.magnitudeLaw({'frame': frame}, document: _frames);
    final days = wallSeconds / icsSecondsPerDay;
    return durationMagnitude((days * law.unitsPer('second', 'day')).toJson(), 'second', frame);
  }
}
