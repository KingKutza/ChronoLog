// The spec of the ICS boundary, as PROPERTIES over seeded random calendars.
//
// Generative doctrine (ruling 7): never validate an arbitrary fact. There is no
// assertion here that the parser handles seventeen properties or that exactly one
// calendar scale is registered -- the properties below hold over whatever the
// grammar draws and whatever the registry currently holds, so the vocabulary can
// grow without rewriting the spec.
//
// EVERY ICS INPUT IS A STRING LITERAL THIS FILE BUILT OR GENERATED. Nothing here
// reads a file from disk: `fixtures/` holds untracked personal calendar data, and
// the suite must never depend on it existing, let alone quote it.
//
// The RULED ANCHORS -- the ones that are decisions rather than derivations -- are
// labelled where they are pinned.

import 'dart:convert';
import 'dart:math';

import 'package:chronolog/core/coordinate_law.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/ics.dart';
import 'package:chronolog/core/projection.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/core/staples.dart';
import 'package:chronolog/core/rrule.dart' show compactIcsDay;
import 'package:chronolog/core/validate.dart';
import 'package:test/test.dart';

import 'corpus.dart' show specSeed;

/// The injected clock. Every DTSTAMP an export mints reads it, which is what
/// makes a re-export comparable at all.
final DateTime clock = DateTime.utc(2026, 8, 7, 12);

Document freshDocument() => createEmptyWorkspaceDocument(now: clock);

const int iterations = 120;

// --- The grammar ------------------------------------------------------------

/// A random ICS file generator.
///
/// [canonical] narrows the grammar to files that are already in the exact shape
/// an export writes -- property order, a present X-WR-CALNAME and DTSTAMP, no
/// DURATION, adjacent and distinct EXDATEs, a unique UID/RECURRENCE-ID pair per
/// component. Inside that shape import-then-export is BYTE-IDENTICAL, which is a
/// far stronger claim than idempotence; outside it, the pipeline still reaches a
/// fixed point after one cycle, which is what the wider grammar pins.
class Calendars {
  Calendars(int seed) : _random = Random(seed);

  final Random _random;
  int _minted = 0;

  bool chance(double odds) => _random.nextDouble() < odds;
  int index(int bound) => _random.nextInt(bound);
  T pick<T>(List<T> from) => from[_random.nextInt(from.length)];

  static const List<String> words = ['status', 'sync', 'review', 'Ops', '1:1', 'retro', 'planning'];

  /// Multi-byte text, on purpose: a two-, three- and four-byte character each
  /// straddle the 75-OCTET fold differently, and a character-counting fold would
  /// pass every ASCII test and split a code point on the first real calendar.
  static const List<String> exotic = [
    'café',
    'naïve',
    '日本の予定',
    'Ωμέγα',
    '🌍 planet',
    'ключ',
    'e\u0301 combining',
  ];

  static const List<String> zones = [
    'Test/Zone',
    'Europe/Berlin',
    'America/New_York',
    'GMT Standard Time',
  ];

  /// Only CANONICAL escapes. A stray backslash before any other character is
  /// preserved verbatim by the escape pass but is not a FIXED POINT of it, so
  /// mixing the two here would turn a round-trip property into a coin flip. The
  /// escape involution over unrestricted text is pinned separately, on raw text
  /// rather than on a file.
  String text({int depth = 0}) {
    final parts = [pick(words)];
    if (chance(0.3)) parts.add(pick(exotic));
    if (chance(0.25)) parts.add(r'a\, b');
    if (chance(0.2)) parts.add(r'semi\; colon');
    if (chance(0.2)) parts.add(r'C:\\new folder');
    if (chance(0.15)) parts.add(r'line\nbreak');
    if (chance(0.2) && depth < 2) parts.add(text(depth: depth + 1));
    return parts.join(' ');
  }

  String longText() => [for (var i = 0; i < 3 + index(7); i++) text()].join(' and then ');

  /// Ordinary years for a recurring event, and for the rest sometimes a SIGNED or
  /// longer-than-four-digit one -- the deliberate RFC deviation that lets a remote
  /// date survive the boundary.
  String year({required bool recurring}) => recurring || chance(0.75)
      ? '${2020 + index(11)}'
      : pick(['-0044', '-1', '0001', '100002026', '12345']);

  String stamp({required bool recurring, required bool dateOnly}) {
    final written = year(recurring: recurring);
    final signed = written.startsWith('-');
    final padded = (signed ? '-' : '') + written.replaceFirst('-', '').padLeft(4, '0');
    final date =
        '$padded${'${1 + index(12)}'.padLeft(2, '0')}${'${1 + index(28)}'.padLeft(2, '0')}';
    if (dateOnly) return date;
    return '${date}T${'${index(24)}'.padLeft(2, '0')}${'${index(60)}'.padLeft(2, '0')}00';
  }

  /// A stamp shifted by whole hours, through the SHARED days axis rather than a
  /// host date, so the arithmetic works for a signed or long year too.
  String shift(String value, int hours) {
    final parsed = parseIcsStamp(value)!;
    final moved = parsed.days + Rational.fromInt(hours, 24);
    return coordinateToIcs(daysToCivilCoordinate(moved), utc: value.endsWith('Z'));
  }

  String rule({required bool canonical}) {
    final parts = <String>[];
    // A scale that resolves to the registered Gregorian is OMITTED on export, so
    // it cannot appear in a file that must come back byte for byte.
    if (chance(0.15)) {
      parts.add('RSCALE=${pick(canonical ? unregisteredScales : allScales)}');
    }
    parts.add('FREQ=${pick(const ['DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY'])}');
    if (chance(0.4)) parts.add('INTERVAL=${1 + index(3)}');
    if (chance(0.5)) {
      parts.add('COUNT=${1 + index(8)}');
    } else if (chance(0.4)) {
      parts.add('UNTIL=2027${'${1 + index(12)}'.padLeft(2, '0')}15T235959Z');
    }
    if (chance(0.3)) parts.add('BYDAY=${pick(const ['MO', 'TU,TH', '2TU', '-1FR'])}');
    if (chance(0.2)) parts.add('BYMONTHDAY=${pick(const ['1', '15', '-1', '10,20'])}');
    if (!canonical && chance(0.08)) parts.add(pick(const ['X-BROKEN', 'NONSENSE']));
    return parts.join(';');
  }

  static const List<String> unregisteredScales = ['HEBREW', 'CHINESE', 'islamic-civil', 'dangi'];
  static const List<String> allScales = ['GREGORIAN', 'GREGORY', ...unregisteredScales];

  /// One VEVENT's logical lines. In [canonical] order: everything the export
  /// keeps IN PLACE first, then the properties it regenerates by appending, then
  /// DTSTAMP, then subcomponents -- which is the order a serializer writes.
  List<String> event({
    required bool canonical,
    String? uid,
    String? recurrenceId,
    String? recurrenceParams,
    bool? recurring,
  }) {
    final repeats = recurring ?? chance(0.45);
    final dateOnly = chance(0.2);
    final start = stamp(recurring: repeats, dateOnly: dateOnly);
    final timed = start.contains('T');
    final zone = !dateOnly && timed && chance(0.3) ? pick(zones) : null;
    final params = dateOnly ? ';VALUE=DATE' : (zone == null ? '' : ';TZID=$zone');
    final retained = <String>[];
    if (recurrenceId != null) retained.add('RECURRENCE-ID$recurrenceParams:$recurrenceId');
    retained.add('DTSTART$params:$start');
    // DTEND carries the SAME typing as DTSTART, because the export derives it
    // from the placement's own parameters. A DURATION would be replaced by a
    // DTEND, so a canonical file never writes one.
    if (timed && chance(0.65)) {
      retained.add('DTEND$params:${shift(start, 1 + index(4))}');
    } else if (!canonical && chance(0.3)) {
      retained.add('DURATION:PT${1 + index(4)}H${pick(const ['', '30M'])}');
    }
    if (repeats) {
      retained.add('RRULE:${rule(canonical: canonical)}');
      if (timed && chance(0.35)) {
        // Distinct days, adjacent properties: two EXDATEs naming one day collapse
        // to one on export, and a separated pair is re-inserted together.
        final excluded = <String>{};
        for (var i = 0; i < 1 + index(2); i++) {
          final asDate = chance(0.35);
          final own = asDate ? ';VALUE=DATE' : params;
          final value = asDate
              ? start.substring(0, start.indexOf('T'))
              : shift(start, 24 * (1 + i));
          if (excluded.add(value)) retained.add('EXDATE$own:$value');
        }
      }
    }
    if (chance(0.3)) retained.add('STATUS:${pick(const ['CONFIRMED', 'TENTATIVE', 'CANCELLED'])}');
    if (chance(0.3)) retained.add('CATEGORIES:${pick(words)},${pick(words)}');
    if (chance(0.3)) retained.add('ATTENDEE;CN="Doe, John":mailto:john@spec.test');
    if (chance(0.3)) retained.add('X-FOREIGN-${_minted++}:${text()}');
    if (chance(0.12)) retained.add('X-EVENT-MALFORMED-MARKER');
    // The DEAD DIALECT, generated on purpose: these are somebody's X- properties
    // now and must ride through as verbatim data, minting nothing.
    if (chance(0.1)) {
      retained.add(
        'X-CHRONOLOG-ANCHOR;ID=r1;ROLE=start:${stamp(recurring: true, dateOnly: false)}',
      );
      retained.add('X-CHRONOLOG-SPREAD;ID=r1;BEFORE=1/24:start');
    }
    if (repeats && chance(0.1)) {
      retained.add('X-CHRONOLOG-SERIES:${uid ?? 'unset'}');
      retained.add('X-CHRONOLOG-SEGMENT-INDEX:1');
    }
    // DTSTAMP is RETAINED, so the export writes it back IN PLACE; UID, SUMMARY,
    // DESCRIPTION and LOCATION are stripped as reconstructible and come back
    // APPENDED. A canonical file therefore writes DTSTAMP before them.
    retained.add('DTSTAMP:2026080${1 + index(9)}T010000Z');
    final generated = [
      'UID:${uid ?? 'event-${_minted++}@spec.test'}',
      'SUMMARY:${text()}',
      if (chance(0.5)) 'DESCRIPTION:${longText()}',
      if (chance(0.35)) 'LOCATION:${pick(words)} room',
    ];
    return [
      'BEGIN:VEVENT',
      ...(canonical ? [...retained, ...generated] : _shuffled([...retained, ...generated])),
      if (chance(0.25)) ...const [
        'BEGIN:VALARM',
        'ACTION:DISPLAY',
        'TRIGGER:-PT15M',
        'DESCRIPTION:Reminder',
        'END:VALARM',
      ],
      'END:VEVENT',
    ];
  }

  List<String> _shuffled(List<String> lines) => lines..shuffle(_random);

  /// One whole calendar. Non-VEVENT subcomponents come FIRST, which is where the
  /// retained calendar shell keeps them.
  String calendar({bool canonical = false}) {
    final lines = <String>[
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//Spec//EN',
      if (canonical || chance(0.6)) 'X-WR-CALNAME:${text()}' else if (chance(0.4)) 'NAME:${text()}',
      if (chance(0.25)) 'X-UNUSUAL-CALENDAR:${pick(words)}',
      if (chance(0.12)) 'X-CALENDAR-MALFORMED-MARKER',
      if (chance(0.3)) ...[
        'BEGIN:VTIMEZONE',
        'TZID:${pick(zones)}',
        'X-TZ-DETAIL:keep',
        'END:VTIMEZONE',
      ],
      if (chance(0.2)) ...[
        'BEGIN:VJOURNAL',
        'UID:journal@spec.test',
        'SUMMARY:${text()}',
        'END:VJOURNAL',
      ],
      if (chance(0.15)) ...const ['BEGIN:X-CUSTOM-COMP', 'X-FIELD:keep', 'END:X-CUSTOM-COMP'],
      if (chance(0.15)) ...const [
        'BEGIN:VFREEBUSY',
        'UID:fb@spec.test',
        'FREEBUSY:20260806T090000Z/PT1H',
        'END:VFREEBUSY',
      ],
      // VTODO mapping is ON HOLD, so this must survive exactly as VJOURNAL does.
      if (chance(0.2)) ...[
        'BEGIN:VTODO',
        'UID:todo@spec.test',
        'SUMMARY:${text()}',
        'DTSTAMP:20260807T010000Z',
        if (chance(0.5)) 'COMPLETED:20260806T230000Z',
        'END:VTODO',
      ],
    ];
    String? masterUid;
    String? masterStart;
    String? masterZone;
    for (var i = 0; i < 1 + index(4); i++) {
      final uid = 'event-${_minted++}@spec.test';
      final body = event(canonical: canonical, uid: uid, recurring: i == 0 ? true : null);
      lines.addAll(body);
      if (masterUid == null && body.any((line) => line.startsWith('RRULE:'))) {
        final line = body.firstWhere((item) => item.startsWith('DTSTART'));
        final value = line.substring(line.indexOf(':') + 1);
        if (value.contains('T')) {
          masterUid = uid;
          masterStart = value;
          masterZone = line.contains('TZID=')
              ? line.substring(line.indexOf('TZID=') + 5, line.indexOf(':'))
              : null;
        }
      }
    }
    // A RECURRENCE-ID sibling of a real master, which is the only thing that
    // mints an override. Its own time form is drawn independently, so the
    // mismatch WARNING is generated as often as the clean case.
    if (masterUid != null && chance(0.45)) {
      final asDate = chance(0.3);
      final asUtc = !asDate && chance(0.3);
      lines.addAll(
        event(
          canonical: canonical,
          uid: masterUid,
          recurring: false,
          recurrenceId: asDate
              ? masterStart!.substring(0, masterStart.indexOf('T'))
              : shift(masterStart!, 24) + (asUtc ? 'Z' : ''),
          recurrenceParams: asDate
              ? ';VALUE=DATE'
              : (asUtc || masterZone == null ? '' : ';TZID=$masterZone'),
        ),
      );
    }
    lines.addAll(const ['END:VCALENDAR', '']);
    // Folded through the ONE fold, so a canonical file is byte-comparable against
    // an export that folds the same logical lines the same way. Fold and unfold
    // are pinned as involutions in their own right below.
    return [for (final line in lines) line.isEmpty ? line : foldLine(line)].join('\r\n');
  }
}

/// A description-heavy corporate calendar: the shape that actually triggered the
/// retained-payload blow-up, and therefore the shape the size property measures.
String corporateCalendar(int count) {
  final body =
      '<html><body><div>Teams meeting</div><p>'
      '${'Join the meeting now. Learn more about Teams. ' * 80}</p></body></html>';
  return [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Spec//EN',
    for (var i = 0; i < count; i++) ...[
      'BEGIN:VEVENT',
      'UID:meeting-$i@spec.test',
      'DTSTART:202608${'${10 + i % 15}'.padLeft(2, '0')}T090000Z',
      'DTEND:202608${'${10 + i % 15}'.padLeft(2, '0')}T100000Z',
      'SUMMARY:Status sync $i',
      'DESCRIPTION:$body',
      'LOCATION:Conference Room A',
      'STATUS:CONFIRMED',
      'CATEGORIES:Work,Meetings',
      'ATTENDEE;CN=Alice:mailto:alice$i@spec.test',
      'BEGIN:VALARM',
      'ACTION:DISPLAY',
      'DESCRIPTION:Reminder',
      'TRIGGER:-PT15M',
      'END:VALARM',
      'END:VEVENT',
    ],
    'END:VCALENDAR',
    '',
  ].join('\r\n');
}

// --- Helpers ----------------------------------------------------------------

String exportOf(IcsImport result, {bool withEngine = true}) => exportIcs(
  result.document,
  frame: result.frames.first,
  engine: withEngine ? ProjectionEngine(result.document) : null,
  now: clock,
  productId: '-//Spec//EN',
);

/// Every placement in a document, keyed by the object's own UID, as exact days.
/// The comparison a lossy round trip has to survive: WHEN did it say the thing
/// happens, in a form no spelling difference can disguise.
Map<String, String> placementDays(Document document) => {
  for (final relation in document.relations.values)
    if (isPlacement(relation))
      if (document.events[relation.event] case final Event event)
        '${event.payload?['uid']}': civilCoordinateToDays(Coordinate.fromJson(relation.coordinate))
            .toJson(),
};

List<String> physicalLines(String text) => text.split('\r\n');

void main() {
  group('content lines', () {
    test('escape and unescape are inverses over random text, in one pass', () {
      final random = Random(specSeed);
      const alphabet = [
        'a',
        'Z',
        '9',
        ' ',
        r'\',
        ';',
        ',',
        '\n',
        ':',
        '"',
        'é',
        '日',
        '🌍',
        'n',
        'N',
      ];
      for (var i = 0; i < iterations; i++) {
        final value = [
          for (var j = 0; j < random.nextInt(40); j++) alphabet[random.nextInt(alphabet.length)],
        ].join();
        expect(unescapeIcsText(escapeIcsText(value)), value, reason: 'round $i: $value');
      }
      // RULED ANCHOR: ONE PASS. A second decode pass would read an authored `\\n`
      // -- a real backslash followed by the letter n -- as a newline, which is how
      // a Windows path in a DESCRIPTION comes back mangled.
      expect(unescapeIcsText(r'C:\\new folder'), r'C:\new folder');
      expect(unescapeIcsText(r'\\n kept'), r'\n kept');
    });

    test('fold and unfold are inverses, and every physical line fits 75 OCTETS', () {
      final random = Random(specSeed + 1);
      final calendars = Calendars(specSeed + 1);
      for (var i = 0; i < iterations; i++) {
        // A logical line built from multi-byte pieces, so the limit lands inside a
        // two-, three- and four-byte character across the run.
        final line = [
          'X-LONG-$i:',
          for (var j = 0; j < 1 + random.nextInt(30); j++)
            random.nextBool() ? calendars.pick(Calendars.exotic) : calendars.pick(Calendars.words),
        ].join(' ');
        final folded = foldLine(line);
        expect(unfoldIcs(folded), line, reason: 'round $i');
        for (final physical in physicalLines(folded)) {
          expect(utf8.encode(physical).length, lessThanOrEqualTo(75), reason: 'round $i');
        }
        // Continuations open with exactly one space, and no character was split:
        // re-decoding the bytes of every physical line is lossless.
        for (final physical in physicalLines(folded).skip(1)) {
          expect(physical.startsWith(' '), isTrue);
          expect(utf8.decode(utf8.encode(physical)), physical);
        }
      }
    });

    test('a content line survives serialize then parse, parameters and all', () {
      final random = Random(specSeed + 2);
      final calendars = Calendars(specSeed + 2);
      for (var i = 0; i < iterations; i++) {
        final params = [
          for (var j = 0; j < random.nextInt(3); j++)
            IcsParam('P$j', [
              for (var k = 0; k < 1 + random.nextInt(2); k++)
                random.nextBool() ? 'Doe, John' : calendars.pick(Calendars.words),
            ]),
        ];
        final property = IcsProperty('X-LINE-$i', params: params, value: calendars.text());
        final line = '${property.name}${serializeParams(property.params)}:${property.value}';
        final parsed = parseContentLine(unfoldIcs(foldLine(line)));
        expect(parsed.name, property.name);
        expect(parsed.value, property.value);
        expect(
          [
            for (final param in parsed.params) [param.name, param.values],
          ],
          [
            for (final param in params) [param.name, param.values],
          ],
        );
      }
    });

    test('a component tree survives serialize then parse', () {
      final calendars = Calendars(specSeed + 3);
      for (var i = 0; i < iterations; i++) {
        final tree = parseIcsTree(calendars.calendar());
        final again = parseIcsTree(serializeComponent(tree.components.first));
        expect(_shape(again.components.first), _shape(tree.components.first));
      }
    });

    test('broken nesting is REFUSED, while broken content is not', () {
      expect(() => parseIcsTree('BEGIN:VCALENDAR\r\nEND:VEVENT\r\n'), throwsA(isA<IcsRefusal>()));
      expect(() => parseIcsTree('BEGIN:VCALENDAR\r\n'), throwsA(isA<IcsRefusal>()));
      // A line with no colon at all is content, not structure: it rides.
      final tree = parseIcsTree('BEGIN:VCALENDAR\r\nX-NO-COLON\r\nEND:VCALENDAR\r\n');
      expect(tree.components.first.properties.single.verbatim, isTrue);
      expect(serializeComponent(tree.components.first), contains('\r\nX-NO-COLON\r\n'));
    });
  });

  group('value codecs', () {
    test('signed and long years round-trip, and agree with the ONE days conversion', () {
      final calendars = Calendars(specSeed + 4);
      for (var i = 0; i < iterations; i++) {
        final dateOnly = calendars.chance(0.4);
        final written = calendars.stamp(recurring: false, dateOnly: dateOnly);
        final parsed = parseIcsStamp(written)!;
        expect(parsed.dateOnly, dateOnly);
        expect(coordinateToIcs(parsed.coordinate, dateOnly: dateOnly), written);
        // MELT: `rrule.dart`'s own [compactIcsDay] is the codebase's ICS-text-to-
        // days conversion. This pins that the structural parse here cannot drift
        // from it -- one meaning, whichever door you come in.
        expect(parsed.days, compactIcsDay(written));
      }
      // RULED ANCHOR: the deliberate RFC deviation. Both of these are outside RFC
      // 5545's four-digit year, and both survive so a remote date can.
      for (final value in const ['-00440315', '1000020260806T000000', '+0044031T']) {
        final parsed = parseIcsStamp(value);
        if (parsed == null) continue;
        expect(
          coordinateToIcs(parsed.coordinate, dateOnly: parsed.dateOnly).length,
          greaterThan(7),
        );
      }
      expect(parseIcsStamp('-00440315')!.coordinate.value('year'), '-44');
      expect(parseIcsStamp('1000020260806')!.coordinate.value('year'), '100002026');
    });

    test('a Z suffix is a flag, and TZID is an OPAQUE string echoed back', () {
      final calendars = Calendars(specSeed + 5);
      for (var i = 0; i < iterations; i++) {
        final zone = calendars.pick(Calendars.zones);
        final line = 'DTSTART;TZID=$zone:20260806T090000';
        final parsed = parseIcsDate(parseContentLine(line))!;
        expect(parsed.timeZone, zone);
        expect(parsed.utc, isFalse);
        expect(serializeParams(icsValueParams(dateOnly: false, timeZone: zone)), ';TZID=$zone');
      }
      expect(parseIcsStamp('20260806T090000Z')!.utc, isTrue);
      // VALUE=DATE types a value date-only even when it carries a time.
      expect(parseIcsStamp('20260806T090000', valueDate: true)!.dateOnly, isTrue);
      expect(serializeParams(icsValueParams(dateOnly: true, timeZone: 'Test/Zone')), ';VALUE=DATE');
    });

    test('DURATION counts WIRE units, never a document law', () {
      final random = Random(specSeed + 6);
      for (var i = 0; i < iterations; i++) {
        final weeks = random.nextInt(4);
        final days = random.nextInt(10);
        final hours = random.nextInt(30);
        final minutes = random.nextInt(100);
        final seconds = random.nextInt(100);
        final negative = random.nextBool();
        final written =
            '${negative ? '-' : ''}P'
            '${weeks > 0 ? '${weeks}W' : ''}${days > 0 ? '${days}D' : ''}'
            'T${hours}H${minutes}M${seconds}S';
        final expected = Rational.fromInt(
          weeks * 7 * 86400 + days * 86400 + hours * 3600 + minutes * 60 + seconds,
        );
        expect(parseIcsDuration(written), negative ? -expected : expected);
      }
      // RULED ANCHOR: a week is ALWAYS 7*86400 and an hour ALWAYS 3600, because
      // those are the spec's units. A document whose own day is twenty-three hours
      // long does not change what somebody else's file said.
      expect(parseIcsDuration('P1W'), Rational.fromInt(604800));
      expect(parseIcsDuration('PT2H'), Rational.fromInt(7200));
      expect(parseIcsDuration('not a duration'), isNull);
    });

    test('RSCALE: the registered default is omitted, an unknown scale rides verbatim', () {
      final calendars = Calendars(specSeed + 7);
      for (var i = 0; i < iterations; i++) {
        final scale = calendars.pick(Calendars.allScales);
        final written = 'RSCALE=$scale;FREQ=YEARLY;COUNT=${1 + calendars.index(5)}';
        final normalized = normalizedRuleForExport(parseRRule(written));
        final resolved = lawForCalendar(scale)?.calendarScale();
        if (resolved == null) {
          // Nothing here may assert a spelling is spec-correct for a calendar it
          // does not implement, so the author's own text survives untouched --
          // position included.
          expect(serializeRRule(normalized), written);
        } else if (resolved == gregory) {
          // RFC 7529's own default, and the reason an RSCALE-free import
          // re-exports byte-identical.
          expect(normalized.containsKey('RSCALE'), isFalse);
          expect(serializeRRule(normalized), 'FREQ=YEARLY;COUNT=${written.split('COUNT=')[1]}');
        } else {
          expect(normalized['RSCALE'], resolved.toUpperCase());
        }
      }
      // Every registered calendar answers one of those two ways, whatever the
      // registry currently holds -- no count of scales is asserted anywhere.
      for (final calendar in registeredCalendars()) {
        final normalized = normalizedRuleForExport(parseRRule('RSCALE=$calendar;FREQ=YEARLY'));
        expect(
          normalized['RSCALE'] == null || normalized['RSCALE'] == calendar.toUpperCase(),
          isTrue,
        );
      }
    });

    test('the law gate lets the standard through and CONVERTS everything else', () {
      expect(isIcsNativeLaw(gregorianLaw), isTrue);
      // An edited hour radix is the owner's own Hour:Day:23. Its level values are
      // NOT Gregorian and must never be formatted as though they were.
      final edited = CoordinateLaw.parse({
        'kind': 'gregorian',
        'levels': [
          {'name': 'year'},
          {'name': 'month', 'within': 'year', 'transition': 'gregorian.months'},
          {'name': 'day', 'within': 'month', 'transition': 'gregorian.days'},
          {'name': 'hour', 'within': 'day', 'radix': '23'},
          {'name': 'minute', 'within': 'hour', 'radix': '60'},
          {'name': 'second', 'within': 'minute', 'radix': '60'},
        ],
      }, frameId: 'edited');
      expect(isIcsNativeLaw(edited), isFalse);
      final document = freshDocument().put(
        'frames',
        'frame:edited',
        Frame(
          id: 'frame:edited',
          title: 'Edited wall time',
          traits: const ['line', 'temporal'],
          extra: {'coordinate': edited.declaration.toJson()},
        ),
      );
      final boundary = IcsBoundary(document);
      final value = Coordinate.of([('year', 2026), ('month', 8), ('day', 6), ('hour', 22)]);
      final crossed = boundary.boundaryCoordinate('frame:edited', value);
      expect(crossed, daysToCivilCoordinate(edited.toDays(value)));
      expect(crossed, isNot(value));
      // A frame under the registered standard passes through UNCHANGED, which is
      // what keeps an ordinary round trip byte-identical.
      expect(boundary.boundaryCoordinate('frame:wall-time', value), value);
    });
  });

  group('import', () {
    test('every random calendar imports to a VALID document, warnings never thrown', () {
      final calendars = Calendars(specSeed + 8);
      var warned = 0;
      for (var i = 0; i < iterations; i++) {
        final source = calendars.calendar();
        final result = importIcs(source, freshDocument(), label: 'Spec');
        final validation = validateDocument(result.document);
        expect(validation.valid, isTrue, reason: 'round $i:\n${validation.errors.join('\n')}');
        if (result.warnings.isNotEmpty) warned += 1;
        // A warning is a SENTENCE about a named event, never a code.
        for (final warning in result.warnings) {
          expect(warning.length, greaterThan(20));
        }
      }
      expect(warned, greaterThan(0), reason: 'the grammar draws mismatched time forms');
    });

    test('a foreign X- property is somebody else\'s dialect and rides verbatim', () {
      final calendars = Calendars(specSeed + 9);
      var carriers = 0;
      for (var i = 0; i < iterations; i++) {
        final source = calendars.calendar();
        final result = importIcs(source, freshDocument(), label: 'Spec');
        final exported = exportOf(result);
        for (final line in physicalLines(source)) {
          final name = line.startsWith('X-') ? line.split(RegExp('[;:]')).first : null;
          if (name == null || name == 'X-WR-CALNAME') continue;
          carriers += 1;
          expect(exported, contains(name), reason: 'round $i lost $name');
        }
        // RULED ANCHOR: the X-CHRONOLOG dialect is DEAD IN BOTH DIRECTIONS. Its
        // properties are data like any other X- property, and reading one mints
        // NO staple -- meaning is authored, never inferred.
        expect(
          result.document.relations.values.where((relation) => relation.isStaple && !isPlacement(relation)),
          isEmpty,
          reason: 'round $i invented a connection',
        );
      }
      expect(carriers, greaterThan(0));
    });

    test('VTODO, VJOURNAL, VFREEBUSY, VALARM and VTIMEZONE are retained VERBATIM', () {
      final calendars = Calendars(specSeed + 10);
      var seen = 0;
      for (var i = 0; i < iterations; i++) {
        final source = calendars.calendar();
        final result = importIcs(source, freshDocument(), label: 'Spec');
        final exported = exportOf(result);
        for (final name in const ['VTODO', 'VJOURNAL', 'VFREEBUSY', 'VALARM', 'VTIMEZONE']) {
          final expectedCount = _occurrences(source, 'BEGIN:$name');
          if (expectedCount > 0) seen += 1;
          expect(_occurrences(exported, 'BEGIN:$name'), expectedCount, reason: 'round $i $name');
        }
        // The mapping is ON HOLD, so nothing here becomes a task.
        expect(
          result.document.events.values.where((event) => event.traits.contains('task')),
          isEmpty,
        );
      }
      expect(seen, greaterThan(0));
    });

    test('EXDATE keeps the file\'s OWN TEXT for every value it still excludes', () {
      final calendars = Calendars(specSeed + 11);
      var checked = 0;
      for (var i = 0; i < iterations; i++) {
        final source = calendars.calendar(canonical: true);
        final result = importIcs(source, freshDocument(), label: 'Spec');
        final exported = exportOf(result);
        for (final line in physicalLines(source)) {
          if (!line.startsWith('EXDATE')) continue;
          checked += 1;
          expect(exported, contains(line), reason: 'round $i lost $line');
        }
        expect(
          _occurrences(exported, 'EXDATE'),
          _occurrences(source, 'EXDATE'),
          reason: 'round $i changed the EXDATE multiplicity',
        );
      }
      expect(checked, greaterThan(0));
    });

    test('the residual store keeps a document near ONE TIMES the imported file', () {
      final source = corporateCalendar(40);
      final result = importIcs(source, freshDocument(), label: 'Work');
      expect(result.events.length, 40);
      final icsBytes = utf8.encode(source).length;
      final documentBytes = utf8.encode(jsonEncode(result.document.toJson())).length;
      // A SIZE property, not a shape assertion: nothing here pins where the
      // retained delta lives, only that it is stored ONCE. A per-event copy of
      // each component put this ratio north of three.
      expect(
        documentBytes,
        lessThan(icsBytes * 3 ~/ 2),
        reason: 'document $documentBytes bytes against ICS $icsBytes bytes',
      );
      // And the export still reconstructs everything, from payload plus delta.
      final exported = exportOf(result);
      expect(_occurrences(exported, 'BEGIN:VEVENT'), 40);
      expect(_occurrences(exported, 'BEGIN:VALARM'), 40);
      expect(exported, contains('ATTENDEE;CN=Alice:mailto:alice0@spec.test'));
      expect(exported, contains('Teams meeting'));
    });

    test('no VCALENDAR is a refusal, not an empty import', () {
      expect(
        () => importIcs('BEGIN:VEVENT\r\nEND:VEVENT\r\n', freshDocument()),
        throwsA(isA<IcsRefusal>()),
      );
    });
  });

  group('export', () {
    test('a canonical file survives import then export BYTE FOR BYTE', () {
      final calendars = Calendars(specSeed + 12);
      for (var i = 0; i < iterations; i++) {
        final source = calendars.calendar(canonical: true);
        final result = importIcs(source, freshDocument(), label: 'Spec');
        expect(exportOf(result), source, reason: 'round $i');
      }
    });

    test('re-exporting an unedited document is byte-identical, and one cycle is a FIXED POINT', () {
      final calendars = Calendars(specSeed + 13);
      for (var i = 0; i < iterations; i++) {
        final source = calendars.calendar();
        final first = importIcs(source, freshDocument(), label: 'Spec');
        final once = exportOf(first);
        // RULED ANCHOR: DTSTAMP comes from an INJECTED clock and a segment UID is
        // DERIVED, so nothing random enters the bytes. A fresh id here would make
        // every sync see every event as changed.
        expect(exportOf(first), once, reason: 'round $i is not idempotent');
        // An engine is only needed for the two derivations that require a
        // projection -- a truncated COUNT and materialized occurrences. A document
        // with neither exports identically without one.
        expect(exportOf(first, withEngine: false), once, reason: 'round $i needed an engine');
        final second = importIcs(once, freshDocument(), label: 'Spec');
        final twice = exportOf(second);
        final third = importIcs(twice, freshDocument(), label: 'Spec');
        expect(exportOf(third), twice, reason: 'round $i has no fixed point');
      }
    });

    test('the RULED LOSS: a re-imported export has correct times and ZERO staples', () {
      final calendars = Calendars(specSeed + 14);
      for (var i = 0; i < iterations; i++) {
        final source = calendars.calendar();
        final first = importIcs(source, freshDocument(), label: 'Spec');
        final again = importIcs(exportOf(first), freshDocument(), label: 'Spec');
        // Times survive exactly -- that is the half of the boundary that is not
        // lossy, and it is pinned as exact days so no spelling can hide a drift.
        expect(placementDays(again.document), placementDays(first.document));
        // Connections do not. "Rules or projections out": there is no carrier for
        // an anchor, a spread or a series identity, so a fresh import invents
        // none. Named, accepted, and pinned rather than left implicit.
        expect(again.document.relations.values.where((r) => r.isStaple && !isPlacement(r)), isEmpty);
        expect(first.document.relations.values.where((r) => r.isStaple && !isPlacement(r)), isEmpty);
      }
    });

    test('a window filters placements without touching a series template', () {
      final source = [
        'BEGIN:VCALENDAR',
        'VERSION:2.0',
        'PRODID:-//Spec//EN',
        'BEGIN:VEVENT',
        'UID:inside@spec.test',
        'DTSTART:20260610T090000Z',
        'SUMMARY:Inside',
        'END:VEVENT',
        'BEGIN:VEVENT',
        'UID:outside@spec.test',
        'DTSTART:20200610T090000Z',
        'SUMMARY:Outside',
        'END:VEVENT',
        'BEGIN:VEVENT',
        'UID:series@spec.test',
        'DTSTART:20200101T090000Z',
        'RRULE:FREQ=YEARLY;COUNT=40',
        'SUMMARY:Long series',
        'END:VEVENT',
        'END:VCALENDAR',
        '',
      ].join('\r\n');
      final result = importIcs(source, freshDocument(), label: 'Spec');
      final windowed = exportIcs(
        result.document,
        frame: result.frames.first,
        engine: ProjectionEngine(result.document),
        now: clock,
        start: Coordinate.of([('year', 2026), ('month', 1), ('day', 1)]),
        end: Coordinate.of([('year', 2026), ('month', 12), ('day', 31)]),
      );
      expect(windowed, contains('inside@spec.test'));
      expect(windowed, isNot(contains('outside@spec.test')));
      // The template of a series whose own start is outside the window still
      // rides: its RULE is what describes the occurrences inside it.
      expect(windowed, contains('series@spec.test'));
      expect(windowed, contains('RRULE:FREQ=YEARLY;COUNT=40'));
    });

    test('COUNT truncation never emits COUNT and UNTIL together', () {
      final calendars = Calendars(specSeed + 15);
      var truncated = 0;
      var bounded = 0;
      for (var i = 0; i < iterations; i++) {
        final counted = calendars.chance(0.5);
        final source = [
          'BEGIN:VCALENDAR',
          'VERSION:2.0',
          'PRODID:-//Spec//EN',
          'BEGIN:VEVENT',
          'UID:series@spec.test',
          'DTSTART:20260105T090000Z',
          if (counted) 'RRULE:FREQ=DAILY;COUNT=${20 + calendars.index(40)}' else 'RRULE:FREQ=DAILY',
          'SUMMARY:Bounded series',
          'END:VEVENT',
          'END:VCALENDAR',
          '',
        ].join('\r\n');
        final imported = importIcs(source, freshDocument(), label: 'Spec');
        final closeDay = 10 + calendars.index(20);
        final placed = putStaple(
          imported.document,
          kind: 'end',
          ends: [
            StapleEnd.series(imported.patterns.first),
            StapleEnd.frame(
              imported.frames.first,
              position: Position.coordinate(
                Coordinate.of([('year', 2026), ('month', 2), ('day', closeDay)]).toJson(),
              ),
            ),
          ],
        );
        final engine = ProjectionEngine(placed.document);
        final exported = exportIcs(
          placed.document,
          frame: imported.frames.first,
          engine: engine,
          now: clock,
        );
        final rule = parseRRule(
          physicalLines(exported).firstWhere((line) => line.startsWith('RRULE:')).substring(6),
        );
        // RULED ANCHOR: RFC 5545 forbids COUNT and UNTIL in one rule. Rather than
        // emit an illegal pair -- or silently drop the staple that closes the
        // segment -- a COUNT-based rule has its COUNT SHRUNK to the occurrences
        // that actually survive.
        expect(
          rule.containsKey('COUNT') && rule.containsKey('UNTIL'),
          isFalse,
          reason: 'round $i emitted $rule',
        );
        final segment = engine.staples
            .seriesSegments(placed.document.patterns[imported.patterns.first]!)
            .first;
        expect(segment.untilDays, isNotNull);
        final surviving = engine
            .queryFrame(
              imported.frames.first,
              start: Rational.parse('0'),
              end: segment.untilDays!,
              applyOverrides: false,
            )
            .facts
            .where((fact) => fact.pattern == imported.patterns.first)
            .length;
        if (counted) {
          truncated += 1;
          expect(rule['COUNT'], '$surviving');
        } else {
          bounded += 1;
          // The staple is separate authored data and is NEVER written back into
          // the rule: the derived stop appears only in the EXPORTED text.
          expect(rule['UNTIL'], isNotNull);
          expect(compactIcsDay(rule['UNTIL'])! <= segment.untilDays!, isTrue);
          expect(
            (placed.document.patterns[imported.patterns.first]!.extra['rrule']! as Map)['UNTIL'],
            isNull,
          );
        }
      }
      expect(truncated, greaterThan(0));
      expect(bounded, greaterThan(0));
    });

    test('a segmented series exports as PLAIN SIBLING VEVENTs with correct times', () {
      final source = [
        'BEGIN:VCALENDAR',
        'VERSION:2.0',
        'PRODID:-//Spec//EN',
        'BEGIN:VEVENT',
        'UID:rob-and-john@spec.test',
        'DTSTART:20260105T090000Z',
        'DTEND:20260105T100000Z',
        'RRULE:FREQ=WEEKLY;BYDAY=MO',
        'SUMMARY:Weekly with John',
        'END:VEVENT',
        'END:VCALENDAR',
        '',
      ].join('\r\n');
      final imported = importIcs(source, freshDocument(), label: 'Spec');
      final inflection = Coordinate.of([('year', 2026), ('month', 3), ('day', 2)]);
      final following = Coordinate.of([
        ('year', 2026),
        ('month', 3),
        ('day', 5),
        ('hour', 14),
        ('minute', 30),
        ('second', 0),
      ]);
      final placed = putStaple(
        imported.document,
        kind: 'inflection',
        ends: [
          StapleEnd.series(imported.patterns.first),
          StapleEnd.frame(
            imported.frames.first,
            position: Position.coordinate(inflection.toJson()),
          ),
        ],
        extra: {
          'payload': {
            'rule': {
              'rrule': {'FREQ': 'WEEKLY', 'BYDAY': 'TH'},
              'coordinate': following.toJson(),
              'frame': imported.frames.first,
            },
          },
        },
      );
      final engine = ProjectionEngine(placed.document);
      final exported = exportIcs(
        placed.document,
        frame: imported.frames.first,
        engine: engine,
        now: clock,
      );
      // RULED ANCHOR: ruling 3. The identity linkage is NOT emitted -- no
      // X-CHRONOLOG property of any kind -- and the second rule rides as an
      // ordinary independent event so any calendar sees the real meetings.
      expect(exported, isNot(contains('X-CHRONOLOG')));
      expect(_occurrences(exported, 'BEGIN:VEVENT'), 2);
      expect(exported, contains('RRULE:FREQ=WEEKLY;BYDAY=TH'));
      expect(exported, contains('DTSTART:20260305T143000'));
      // Correct times: the sibling's own DTEND follows the template's duration.
      expect(exported, contains('DTEND:20260305T153000'));
      // Deterministic: a re-export is byte-identical, so no sync churns.
      expect(
        exportIcs(placed.document, frame: imported.frames.first, engine: engine, now: clock),
        exported,
      );
      // And a fresh import of it gets correct times and NO connection at all.
      final back = importIcs(exported, freshDocument(), label: 'Spec');
      expect(back.events.length, 2);
      expect(back.document.relations.values.where((r) => r.isStaple && !isPlacement(r)), isEmpty);
      expect(
        placementDays(back.document).values,
        contains(civilCoordinateToDays(following).toJson()),
      );
    });

    test('PROJECTIONS OUT: a pattern this calendar cannot state as a rule is materialized', () {
      final source = [
        'BEGIN:VCALENDAR',
        'VERSION:2.0',
        'PRODID:-//Spec//EN',
        'BEGIN:VEVENT',
        'UID:seed@spec.test',
        'DTSTART:20260601T090000Z',
        'DTEND:20260601T093000Z',
        'SUMMARY:Seed',
        'END:VEVENT',
        'END:VCALENDAR',
        '',
      ].join('\r\n');
      final imported = importIcs(source, freshDocument(), label: 'Spec');
      final relation = imported.document.relations[imported.relations.first]!;
      // A generator whose occurrences land on this calendar but which is NOT one
      // of the calendar's own RRULE patterns. That is the seam: a rule this file
      // cannot state gets written out as the concrete events it produces, which is
      // the "projections out" arm of the boundary.
      final withPattern = imported.document.put(
        'patterns',
        'pattern:foreign',
        const Pattern(
          id: 'pattern:foreign',
          language: 'chronolog-ics/1',
          extra: {
            'kind': 'ics-rrule',
            'templateEvent': 'placeholder',
            'templateRelation': 'placeholder',
            'rrule': {'FREQ': 'DAILY', 'COUNT': '4'},
          },
        ),
      );
      final document = withPattern.put(
        'patterns',
        'pattern:foreign',
        withPattern.patterns['pattern:foreign']!
            .withField('templateEvent', relation.event)
            .withField('templateRelation', relation.id),
      );
      expect(validateDocument(document).valid, isTrue);
      final exported = exportIcs(
        document,
        frame: imported.frames.first,
        engine: ProjectionEngine(document),
        now: clock,
        start: Coordinate.of([('year', 2026), ('month', 6), ('day', 1)]),
        end: Coordinate.of([('year', 2026), ('month', 6), ('day', 30)]),
      );
      // The authored placement, plus one plain VEVENT per materialized occurrence.
      expect(_occurrences(exported, 'BEGIN:VEVENT'), 5);
      for (final day in const ['01', '02', '03', '04']) {
        expect(exported, contains('DTSTART:202606${day}T090000Z'));
      }
      // Materialized, not ruled: no RRULE is written for a pattern this calendar
      // does not own.
      expect(exported, isNot(contains('RRULE')));
      // Without a window there is nothing to materialize over, so the export is
      // the authored placement alone -- a projection needs bounds.
      final unbounded = exportIcs(
        document,
        frame: imported.frames.first,
        engine: ProjectionEngine(document),
        now: clock,
      );
      expect(_occurrences(unbounded, 'BEGIN:VEVENT'), 1);
    });

    test('an unknown calendar frame is refused by name', () {
      expect(
        () => exportIcs(freshDocument(), frame: 'frame:nowhere', now: clock),
        throwsA(isA<IcsRefusal>()),
      );
    });
  });
}

/// A component's structure, with no identity in it -- what a serialize/parse round
/// trip has to preserve.
Object _shape(IcsComponent component) => {
  'name': component.name,
  'properties': [
    for (final property in component.properties)
      [
        property.name,
        property.value,
        property.raw,
        [
          for (final param in property.params) [param.name, param.values],
        ],
      ],
  ],
  'components': [for (final child in component.components) _shape(child)],
};

int _occurrences(String haystack, String needle) =>
    needle.isEmpty ? 0 : haystack.split(needle).length - 1;
