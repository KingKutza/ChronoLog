// Pure Dart. Nothing under lib/core/ may import Flutter or a third-party
// package.
//
// THE ICS BOUNDARY: file import and file export, and nothing else. No feed
// client, no subscription service, no poller -- "we can import and export but we
// do not need to be beholden while using the app."
//
// THE BOUNDARY IS LOSSY BY RULING: Gregorian in (plus RFC 7529's RSCALE naming
// another registered calendar), rules or projections out. There is NO
// X-CHRONOLOG dialect in either direction. The consequences are named and
// accepted, not hidden:
//
//   * A segmented series exports as PLAIN SIBLING VEVENTs with correct times.
//     Any calendar sees the real meetings; the series IDENTITY is not emitted.
//   * Object anchors and fuzzy spreads have no ICS carrier at all and are not
//     emitted. The DERIVED extent still rides as ordinary DTSTART/DTEND.
//   * A fresh import of an exported file therefore gets correct times and ZERO
//     staples. MEANING IS AUTHORED: a foreign calendar invents no connections.
//
// A FOREIGN X- PROPERTY IS SOMEBODY ELSE'S DIALECT and rides through verbatim,
// which is the opposite of emitting our own.
//
// VTODO IS NOT MAPPED. That mapping is ruled ON HOLD, so a VTODO component is
// retained verbatim exactly as VJOURNAL, VFREEBUSY, VALARM and VTIMEZONE are --
// it survives a round trip untouched and is never turned into an object.
//
// ROUND-TRIP FIDELITY IS RESIDUAL RETENTION, not re-derivation. Every property
// the export regenerates from the model is stripped on the way in; everything
// else is kept as that event's irreducible delta, ONCE PER SOURCE in a shared
// bucket, with each event carrying only `{source, key}`. That de-duplication is
// what keeps a document near one times the imported file instead of twice it.

import 'coordinate_law.dart';
import 'document.dart';
import 'eras.dart' show asList, asMap;
import 'exact.dart';
import 'ics_text.dart';
import 'ics_values.dart';
import 'projection.dart' show ProjectionEngine;
import 'records.dart';
import 'recurrence_end.dart';
import 'rrule.dart' show RRule, compactIcsDay;
import 'staples.dart' show Segment, Staples, isPlacement, startPoint;

export 'ics_text.dart';
export 'ics_values.dart';

// --- The residual store -----------------------------------------------------

/// The properties an export ALWAYS regenerates from the model -- UID and SUMMARY
/// unconditionally, DESCRIPTION and LOCATION set-or-removed either way -- so
/// keeping them in retained storage duplicates data that already lives in the
/// object's payload. Stripping them is what keeps a shared source close to the
/// size of the imported text rather than twice it: one corporate DESCRIPTION can
/// carry kilobytes of HTML per event.
const Set<String> reconstructedProperties = {'UID', 'SUMMARY', 'DESCRIPTION', 'LOCATION'};

/// NUL, the one character RFC 5545 forbids anywhere in a property value -- so no
/// UID can spell a key that is not its own. Named rather than written as a
/// literal: a raw control character sitting in source text is a defect waiting
/// to be pasted somewhere it matters.
final String _keySeparator = String.fromCharCode(0);

/// A stable key for one imported component within its source calendar: the
/// component kind, the UID, and the RECURRENCE-ID (empty for a series master or
/// a plain event) -- exactly the identity RFC 5545 guarantees unique within one
/// calendar, and derivable from the raw component before any record exists.
String eventComponentKey(IcsComponent component) =>
    '${component.name}$_keySeparator${propertyText(component, 'UID') ?? ''}'
    '$_keySeparator${propertyText(component, 'RECURRENCE-ID') ?? ''}';

/// One component's irreducible round-trip delta, AS ICS TEXT.
///
/// Text rather than a second structural encoding: the store then needs no
/// parallel JSON shape to drift from the parser, it costs fewer bytes than the
/// tree it came from, and a retained component comes back through the ONE parser
/// every other reader uses -- which also removes the deep copy the JavaScript
/// needed to keep one export from editing the stored original.
String residualComponentText(IcsComponent component) => serializeComponent(
  IcsComponent(
    component.name,
    properties: [
      for (final item in component.properties)
        if (!reconstructedProperties.contains(item.name)) item,
    ],
    components: component.components,
  ),
);

Json? _sourceBucket(Document document, String? sourceId) =>
    sourceId == null ? null : asMap(asMap(asMap(document.foreign['ics'])?['sources'])?[sourceId]);

/// The retained delta of one object's ICS origin, looked up through the
/// `{source, key}` reference the object itself carries -- it never holds its own
/// copy of the component.
IcsComponent? retainedComponent(Document document, Event event) {
  final reference = asMap(asMap(event.extra['foreign'])?['ics']);
  final bucket = _sourceBucket(document, str(reference?['source']));
  return parseIcsComponent(str(asMap(bucket?['components'])?[str(reference?['key'])]));
}

// --- Import -----------------------------------------------------------------

/// Two records that may be the same thing, offered for the author to decide.
/// Nothing is merged automatically: MEANING IS AUTHORED.
typedef IcsSuggestion = ({String kind, String uid, List<String> events});

/// What one import came to. [warnings] are SURFACED, NEVER THROWN: a calendar
/// whose EXDATE uses a different time form than its DTSTART still imports, and
/// the author is told the exclusion may not match.
class IcsImport {
  IcsImport({
    required this.document,
    required this.frames,
    required this.events,
    required this.patterns,
    required this.relations,
    required this.suggestions,
    required this.warnings,
  });

  final Document document;
  final List<String> frames, events, patterns, relations, warnings;
  final List<IcsSuggestion> suggestions;
}

/// One VEVENT, normalised: everything the model reads, read once.
class _Entry {
  _Entry(this.component, this.frameId, this.sourceId)
    : uid = propertyText(component, 'UID') ?? createId('ics-uid'),
      start = parseIcsDate(propertyNamed(component, 'DTSTART')),
      end = parseIcsDate(propertyNamed(component, 'DTEND')),
      recurrenceId = parseIcsDate(propertyNamed(component, 'RECURRENCE-ID')),
      rrule = propertyNamed(component, 'RRULE'),
      title = unescapeIcsText(propertyText(component, 'SUMMARY') ?? '(untitled)'),
      categories = [
        for (final part in _splitEscaped(propertyText(component, 'CATEGORIES') ?? ''))
          unescapeIcsText(part),
      ],
      exdates = [
        for (final item in propertiesNamed(component, 'EXDATE'))
          for (final value in item.value.split(','))
            if (parseIcsDate(item, value) case final IcsDate date) date,
      ];

  final IcsComponent component;
  final String frameId, sourceId, uid, title;
  final IcsDate? start, end, recurrenceId;
  final IcsProperty? rrule;
  final List<IcsDate> exdates;
  final List<String> categories;

  Event? event;
  Relation? relation;
  Pattern? pattern;
}

/// Splits on a comma except where it is backslash-escaped, tracking the escape
/// STATE -- so `\\,` is an escaped backslash followed by a real separator, which
/// a bare "not preceded by a backslash" test reads backwards.
List<String> _splitEscaped(String value) {
  if (value.isEmpty) return const [];
  final parts = <String>[];
  final current = StringBuffer();
  var escaped = false;
  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    if (!escaped && char == ',') {
      parts.add(current.toString());
      current.clear();
      continue;
    }
    escaped = !escaped && char == r'\';
    current.write(char);
  }
  return parts..add(current.toString());
}

bool _sameTyping(IcsDate? left, IcsDate? right) =>
    (left?.utc ?? false) == (right?.utc ?? false) && left?.timeZone == right?.timeZone;

/// Whether two TIMED values disagree about their own time form. A date-only
/// value makes no claim about a zone, so it never mismatches.
bool _typingMismatch(IcsDate? date, IcsDate? start) =>
    date != null && start != null && !date.dateOnly && !start.dateOnly && !_sameTyping(date, start);

/// The exact day an occurrence is keyed on. A DATE-ONLY exclusion or
/// RECURRENCE-ID against a TIMED series names the occurrence on that date, so it
/// borrows the series' own time of day -- otherwise it would name midnight and
/// match nothing.
Rational _occurrenceKey(IcsDate date, IcsDate? start) {
  if (!date.dateOnly || start == null || start.dateOnly) return date.days;
  final startDay = start.days;
  return date.days + (startDay - Rational(startDay.floor()));
}

/// An entry's duration in WALL SECONDS: DTSTART to DTEND when both are written,
/// otherwise its own DURATION value. Both are the wire format's own seconds.
Rational _durationSeconds(_Entry entry, List<String> warnings) {
  final start = entry.start, end = entry.end;
  if (start == null || end == null) {
    return parseIcsDuration(propertyText(entry.component, 'DURATION')) ?? Rational.zero;
  }
  if (!start.dateOnly && !end.dateOnly && !_sameTyping(start, end)) {
    warnings.add(
      'Event ${entry.uid}: DTSTART and DTEND use different time zones; '
      'duration is their wall-clock difference',
    );
  }
  return (end.days - start.days) * icsSecondsPerDay;
}

/// Reads one ICS file into a document. Every calendar in the file becomes its own
/// frame; every VEVENT becomes an object, its placement, and -- when it carries an
/// RRULE -- a pattern; a RECURRENCE-ID becomes an override on the series it names.
IcsImport importIcs(String text, Document document, {String label = 'Imported calendar'}) {
  final calendars = [
    for (final component in parseIcsTree(text).components)
      if (component.name == 'VCALENDAR') component,
  ];
  if (calendars.isEmpty) throw const IcsRefusal('No VCALENDAR component found');
  final importer = _Importer(document, label);
  for (final calendar in calendars) {
    importer.calendar(calendar);
  }
  return importer.finish();
}

class _Importer {
  _Importer(this.document, this.label) : boundary = IcsBoundary(document) {
    for (final event in document.events.values) {
      final uid = str(event.payload?['uid']);
      if (uid != null) (existing[uid] ??= []).add(event.id);
    }
  }

  Document document;
  final String label;
  final IcsBoundary boundary;
  final List<String> frames = [], events = [], patterns = [], relations = [], warnings = [];
  final List<IcsSuggestion> suggestions = [];

  /// Every UID already in the document, plus every UID an earlier calendar in
  /// this same import contributed -- read for suggestions BEFORE this calendar's
  /// own events join, so an event never suggests stapling to itself.
  final Map<String, List<String>> existing = {};

  T _put<T extends DocumentRecord>(String map, T record) {
    document = document.put(map, record.id, record);
    return record;
  }

  IcsImport finish() => IcsImport(
    document: touch(document),
    frames: frames,
    events: events,
    patterns: patterns,
    relations: relations,
    suggestions: suggestions,
    warnings: warnings,
  );

  void calendar(IcsComponent calendar) {
    final sourceId = createId('ics-source');
    final name = unescapeIcsText(
      propertyText(calendar, 'X-WR-CALNAME') ?? propertyText(calendar, 'NAME') ?? label,
    );
    final frame = _put(
      'frames',
      Frame(
        id: createId('frame'),
        title: name,
        traits: const ['set', 'calendar'],
        extra: {
          'basis': 'frame:wall-time',
          'codec': {'kind': 'ics', 'source': sourceId},
          'foreign': {
            'ics': {'source': sourceId},
          },
        },
      ),
    );
    frames.add(frame.id);
    final entries = [
      for (final component in calendar.components)
        if (component.name == 'VEVENT') _Entry(component, frame.id, sourceId),
    ];
    _retain(sourceId, name, calendar, entries);

    final byUid = <String, List<_Entry>>{};
    for (final entry in entries) {
      _object(entry);
      events.add(entry.event!.id);
      if (entry.relation != null) relations.add(entry.relation!.id);
      final prior = existing[entry.uid];
      if (prior != null) {
        suggestions.add((kind: 'staple', uid: entry.uid, events: [...prior, entry.event!.id]));
      }
      (byUid[entry.uid] ??= []).add(entry);
    }
    for (final entry in entries) {
      if (entry.rrule != null) _pattern(entry);
    }
    for (final group in byUid.entries) {
      _overrides(group.key, group.value);
    }
    for (final entry in entries) {
      (existing[entry.uid] ??= []).add(entry.event!.id);
    }
  }

  /// The calendar SHELL plus one residual per event, in the shared per-source
  /// bucket. The shell is everything the file said about the calendar itself
  /// minus the VEVENTs the model now carries -- so VTODO, VJOURNAL, VFREEBUSY,
  /// VTIMEZONE and any X- component stay exactly where and as they were.
  void _retain(String sourceId, String name, IcsComponent calendar, List<_Entry> entries) {
    final ics = asMap(document.foreign['ics']) ?? const {};
    final shell = IcsComponent(
      calendar.name,
      properties: calendar.properties,
      components: [
        for (final component in calendar.components)
          if (component.name != 'VEVENT') component,
      ],
    );
    document = document.copyWith(
      foreign: {
        ...document.foreign,
        'ics': {
          ...ics,
          'sources': {
            ...?asMap(ics['sources']),
            sourceId: {
              'id': sourceId,
              'label': name,
              'component': serializeComponent(shell),
              'components': {
                for (final entry in entries)
                  eventComponentKey(entry.component): residualComponentText(entry.component),
              },
            },
          },
        },
      },
    );
  }

  void _object(_Entry entry) {
    final component = entry.component;
    final event = _put(
      'events',
      Event(
        id: createId('event'),
        traits: const ['event'],
        magnitudes: {
          'duration': boundary.magnitudeFromWallSeconds(_durationSeconds(entry, warnings)),
        },
        payload: {
          'title': entry.title,
          'description': unescapeIcsText(propertyText(component, 'DESCRIPTION') ?? ''),
          'location': unescapeIcsText(propertyText(component, 'LOCATION') ?? ''),
          'status': propertyText(component, 'STATUS') ?? '',
          'categories': entry.categories,
          'uid': entry.uid,
        },
        extra: {
          'foreign': {
            'ics': {'source': entry.sourceId, 'key': eventComponentKey(component)},
          },
        },
      ),
    );
    entry.event = event;
    final start = entry.start;
    if (start == null) return;
    entry.relation = _put(
      'relations',
      // THE IMPORT MINTS A STAPLE (ruled 2026-09-01). ICS stays the ruled lossy
      // external dialect; what it lands IN is the one internal shape, so a
      // calendar read off disk and one authored by hand are the same records.
      Relation(
        id: createId('relation'),
        type: 'staple',
        extra: {
          'kind': 'anchor',
          'role': 'placed',
          // TZID rides as an OPAQUE STRING. Nothing resolves an offset from it;
          // export echoes exactly this text back.
          'parameters': {'dateOnly': start.dateOnly, 'utc': start.utc, 'timeZone': start.timeZone},
          'provenance': {'kind': 'ics', 'source': entry.sourceId},
          'ends': [
            ObjectEnd(event.id, point: startPoint).toJson(),
            FrameEnd(
              entry.frameId,
              position: Position.coordinate(start.coordinate.toJson()),
            ).toJson(),
          ],
        },
      ),
    );
  }

  /// One RRULE-bearing entry's pattern. The rule is only TOKENIZED here and its
  /// own text is kept beside the parts, so a part this build cannot project still
  /// rides back out exactly as authored. EXDATE keeps its ORIGINAL TEXT per value
  /// as well as the day it resolves to, which is what lets a re-export restate
  /// the file's own spelling.
  void _pattern(_Entry entry) {
    for (final date in entry.exdates) {
      if (_typingMismatch(date, entry.start)) {
        warnings.add(
          'EXDATE for ${entry.uid} uses a different time form than DTSTART; '
          'the exclusion may not match any occurrence',
        );
      }
    }
    entry.pattern = _put(
      'patterns',
      Pattern(
        id: createId('pattern'),
        language: 'chronolog-ics/1',
        extra: {
          'kind': 'ics-rrule',
          'title': '${entry.title} recurrence',
          'appliesTo': [entry.frameId],
          'frame': entry.frameId,
          'templateEvent': entry.event!.id,
          // NO templateRelation (Don, ruled 2026-09-01). The placement is
          // derivable from the template event, and storing its id a second time
          // is what made "minted without it" a reachable silent state at all.
          // Records that already carry one keep loading byte for byte and are
          // simply not believed: the derivation is the one truth.
          'rrule': parseRRule(entry.rrule!.value),
          'rawRule': entry.rrule!.value,
          'exdates': [for (final date in entry.exdates) _occurrenceKey(date, entry.start).toJson()],
          'exdateProperties': [
            for (final item in propertiesNamed(entry.component, 'EXDATE'))
              {
                'params': [
                  for (final param in item.params) {'name': param.name, 'values': param.values},
                ],
                'values': [
                  for (final value in item.value.split(','))
                    {
                      'value': value,
                      'day': switch (parseIcsDate(item, value)) {
                        final IcsDate date => _occurrenceKey(date, entry.start).toJson(),
                        _ => null,
                      },
                    },
                ],
              },
          ],
          'provenance': {'kind': 'ics', 'source': entry.sourceId, 'uid': entry.uid},
        },
      ),
    );
    patterns.add(entry.pattern!.id);
  }

  /// A RECURRENCE-ID names one occurrence of the series sharing its UID, and the
  /// exception event REPLACES it -- which is a suppression plus a replacement, on
  /// the one virtual-id derivation the whole build shares.
  void _overrides(String uid, List<_Entry> matching) {
    final bases = [
      for (final entry in matching)
        if (entry.pattern != null) entry,
    ];
    final exceptions = [
      for (final entry in matching)
        if (entry.recurrenceId != null) entry,
    ];
    for (final exception in exceptions) {
      if (bases.isEmpty) break;
      final base = bases.first;
      if (_typingMismatch(exception.recurrenceId, base.start)) {
        warnings.add(
          'RECURRENCE-ID for $uid uses a different time form than DTSTART; '
          'the override may not match any occurrence',
        );
      }
      final day = _occurrenceKey(exception.recurrenceId!, base.start).toJson();
      final result = suppressVirtual(
        document,
        stableVirtualId(base.pattern!.id, 'occurrence-$day'),
        replacements: [exception.event!.id],
      );
      final override = result.override;
      document = result.document.put(
        'overrides',
        override.id,
        override.copyWith(
          extra: {
            ...override.extra,
            'provenance': {'kind': 'ics', 'source': exception.sourceId, 'uid': uid},
          },
        ),
      );
    }
    // Several records under one UID with no series and no exception among them is
    // the shape a duplicate import makes. Offered, never merged.
    if (matching.length > 1 && bases.isEmpty && exceptions.isEmpty) {
      suggestions.add((
        kind: 'staple',
        uid: uid,
        events: [for (final entry in matching) entry.event!.id],
      ));
    }
  }
}

// --- Export -----------------------------------------------------------------

/// Writes one calendar frame as an ICS file.
///
/// [now] is the INJECTED CLOCK every fresh DTSTAMP reads, and the segment UIDs
/// below are derived rather than minted, so re-exporting an unedited document
/// produces byte-for-byte the same file. A random id there would make every sync
/// see every event as changed.
///
/// [engine] is what makes the two derivations that need a projection available:
/// the truncated COUNT of a segment closed by a staple, and -- when a window is
/// given -- the MATERIALIZED OCCURRENCES of any other pattern on this frame,
/// which is the "projections out" arm of the boundary. Without one, an export is
/// still correct, just rule-only.
String exportIcs(
  Document document, {
  required String frame,
  Coordinate? start,
  Coordinate? end,
  ProjectionEngine? engine,
  DateTime? now,
  String productId = '-//Chronolog//Chronolog 1//EN',
}) {
  final calendarFrame = document.frames[frame];
  if (calendarFrame == null) throw IcsRefusal('Unknown calendar frame $frame');
  return _Exporter(
    document,
    engine,
    now ?? DateTime.now().toUtc(),
  ).run(calendarFrame, start, end, productId);
}

class _Exporter {
  _Exporter(this.document, this.engine, this.now) : boundary = IcsBoundary(document);

  final Document document;
  final ProjectionEngine? engine;
  final DateTime now;
  final IcsBoundary boundary;

  late final Staples staples = engine?.staples ?? Staples(document);

  String run(Frame calendarFrame, Coordinate? start, Coordinate? end, String productId) {
    final frame = calendarFrame.id;
    final shell = parseIcsComponent(
      str(
        _sourceBucket(
          document,
          str(asMap(asMap(calendarFrame.extra['foreign'])?['ics'])?['source']),
        )?['component'],
      ),
    );
    final calendar = IcsComponent(
      'VCALENDAR',
      properties:
          shell?.properties ??
          [
            const IcsProperty('VERSION', value: '2.0'),
            IcsProperty('PRODID', value: productId),
            const IcsProperty('CALSCALE', value: 'GREGORIAN'),
          ],
      components: [
        for (final component in shell?.components ?? const <IcsComponent>[])
          if (component.name != 'VEVENT') component,
      ],
    );
    setProperty(calendar, 'X-WR-CALNAME', escapeIcsText(calendarFrame.title ?? ''));

    final patterns = [
      for (final pattern in document.patterns.values)
        if (pattern.kind == 'ics-rrule' && str(pattern.extra['frame']) == frame) pattern,
    ];
    // Which relation IS the template is DERIVED (ISSUES 9.1), not read off the
    // pattern's stored id: a pattern minted without `templateRelation` used to
    // export its template as an ordinary VEVENT with no rule attached, which is
    // the same starvation the projector had, written to a file.
    final templates = {
      for (final pattern in patterns)
        if (staples.templatePlacement(pattern) case final Relation relation) relation.id: pattern,
    };
    // The window is read through THIS frame's own law, not the standard boundary:
    // an edited Wall Time must not have its own export window misread as standard
    // civil time. A series' template relation is always in, whatever the window,
    // because its rule is what describes the occurrences inside it.
    final law = boundary.law(frame);
    final from = start == null || law == null ? null : law.toDays(start);
    final to = end == null || law == null ? null : law.toDays(end);
    for (final relation in document.relations.values) {
      if (!isPlacement(relation) || relation.frame != frame) continue;
      if (!templates.containsKey(relation.id) && from != null && to != null) {
        // A placement with no coordinate at all makes no claim the window can
        // refuse, so it rides -- the same reading the JavaScript's truthiness had.
        final day = relation.coordinate == null
            ? null
            : boundary.days(frame, Coordinate.fromJson(relation.coordinate));
        if (day != null && (day < from || day > to)) continue;
      }
      final event = document.events[relation.event];
      if (event == null) continue;
      final component = _component(event, relation);
      final pattern = templates[relation.id];
      calendar.components.add(component);
      if (pattern != null) _series(calendar, pattern, component, relation);
    }
    _projections(calendar, frame, patterns, start, end);
    return '${serializeComponent(calendar)}\r\n';
  }

  /// One object as a VEVENT: the retained original with every regenerated
  /// property written back over it IN PLACE, so the file's own property order
  /// survives and a re-export of an unchanged document is byte-identical.
  IcsComponent _component(Event event, Relation? relation) {
    final component = retainedComponent(document, event) ?? IcsComponent('VEVENT');
    final payload = event.payload ?? const <String, Object?>{};
    setProperty(component, 'UID', str(payload['uid']) ?? event.id);
    setProperty(component, 'SUMMARY', escapeIcsText(str(payload['title']) ?? '(untitled)'));
    for (final name in const ['DESCRIPTION', 'LOCATION']) {
      final text = escapeIcsText(str(payload[name.toLowerCase()]) ?? '');
      if (text.isEmpty) {
        removeProperty(component, name);
      } else {
        setProperty(component, name, text);
      }
    }
    final status = str(payload['status']) ?? '';
    if (status.isNotEmpty) setProperty(component, 'STATUS', status);
    final categories = asList(payload['categories']);
    if (categories.isNotEmpty) {
      setProperty(
        component,
        'CATEGORIES',
        [for (final item in categories) escapeIcsText('$item')].join(','),
      );
    }
    if (relation?.coordinate != null) {
      _placement(component, event, relation!);
    }
    if (propertyNamed(component, 'DTSTAMP') == null) {
      setProperty(component, 'DTSTAMP', icsTimestamp(now));
    }
    return component;
  }

  void _placement(IcsComponent component, Event event, Relation relation) {
    final parameters = asMap(relation.extra['parameters']) ?? const {};
    final dateOnly = parameters['dateOnly'] == true;
    final utc = parameters['utc'] == true;
    final params = icsValueParams(dateOnly: dateOnly, timeZone: str(parameters['timeZone']));
    final value = Coordinate.fromJson(relation.coordinate);
    setProperty(
      component,
      'DTSTART',
      coordinateToIcs(
        boundary.boundaryCoordinate(relation.frame, value),
        dateOnly: dateOnly,
        utc: utc,
      ),
      params,
    );
    // The start is read through ITS OWN governing law, never the standard
    // boundary -- an edited hour must not be reinterpreted as a standard hour
    // before DTEND is derived from it. What comes back is an exact day ordinal,
    // which IS law-agnostic, so re-expressing it through the registered boundary
    // afterwards is correct whichever law produced it.
    final seconds = boundary.magnitudeSeconds(event.duration);
    final startDays = boundary.days(relation.frame, value);
    if (seconds <= Rational.zero || startDays == null) return;
    setProperty(
      component,
      'DTEND',
      coordinateToIcs(
        daysToCivilCoordinate(startDays + seconds / icsSecondsPerDay),
        dateOnly: dateOnly,
        utc: utc,
      ),
      params,
    );
    removeProperty(component, 'DURATION');
  }

  /// The rule, its exclusions, and every segment after the first.
  void _series(IcsComponent calendar, Pattern pattern, IcsComponent component, Relation relation) {
    final segments = staples.seriesSegments(pattern);
    final segment = segments.isEmpty ? null : segments.first;
    final rule = normalizedRuleForExport(
      segment == null
          ? _rule(asMap(pattern.extra['rrule']) ?? const {})
          : _boundedRule(pattern, segment, _rule(segment.rule.rrule)),
    );
    setProperty(
      component,
      'RRULE',
      rule.isEmpty ? (str(pattern.extra['rawRule']) ?? '') : serializeRRule(rule),
    );
    _exdates(component, pattern, relation);
    final baseUid = propertyText(component, 'UID') ?? '';
    for (final following in segments.skip(1)) {
      final sibling = _sibling(pattern, following, relation, baseUid);
      if (sibling != null) calendar.components.add(sibling);
    }
  }

  RRule _rule(Json source) => {
    for (final entry in source.entries)
      if (entry.value != null) entry.key: '${entry.value}',
  };

  /// THE effective stop of one segment: the earlier of its own written UNTIL and
  /// the staple that closes it, compared as EXACT DAYS -- never as text, because
  /// ICS writes month `01` where an editor writes `1` and comparing two spellings
  /// of one instant is silently wrong. The ICS-text-to-days conversion is
  /// `rrule.dart`'s own [compactIcsDay]; nothing here re-derives it.
  Rational? _effectiveUntil(Segment segment, RRule rule) {
    final written = compactIcsDay(rule['UNTIL']);
    final closed = segment.untilDays;
    if (written == null || closed == null) return written ?? closed;
    return written <= closed ? written : closed;
  }

  /// THE COUNT-versus-UNTIL rule, and there is one -- read by segment zero and by
  /// every following segment alike.
  ///
  /// An end or inflection staple is separate authored data and is NEVER written
  /// back into the rule: the rule keeps saying what it says, and the effective
  /// stop is derived here, at export time. RFC 5545 forbids COUNT and UNTIL in
  /// one rule, so rather than emit an illegal pair (or silently drop the staple),
  /// a COUNT-based rule has its COUNT SHRUNK to however many occurrences the
  /// projection actually produces through the staple. No RRULE math is re-derived
  /// -- the engine is the one authority for "how many occurrences happen".
  RRule _boundedRule(Pattern pattern, Segment segment, RRule rule) {
    if (segment.untilDays == null) return rule;
    if (recurrenceEndMode(rule) == RecurrenceEnd.count) {
      final truncated = _truncatedCount(pattern, segment);
      if (truncated == null) return rule;
      return {
        for (final entry in rule.entries)
          if (entry.key != 'UNTIL') entry.key: entry.value,
        'COUNT': '$truncated',
      };
    }
    final effective = _effectiveUntil(segment, rule);
    final frame = segment.rule.frame ?? str(pattern.extra['frame']);
    final coordinate = effective == null ? null : boundary.law(frame)?.fromDays(effective);
    if (coordinate == null) return rule;
    return {
      ...rule,
      'UNTIL': recurrenceUntilForCoordinate({
        for (final level in coordinate.levels) level.level: level.value,
      }),
    };
  }

  int? _truncatedCount(Pattern pattern, Segment segment) {
    final engine = this.engine;
    final until = segment.untilDays;
    final frame = str(pattern.extra['frame']);
    if (engine == null || until == null || frame == null) return null;
    // DERIVED like every other read of it (ISSUES 9.1): the pattern no longer
    // stores its template placement's id, and a reader that still expected one
    // silently lost the window it counts occurrences in.
    final template = staples.templatePlacement(pattern);
    final lower =
        segment.fromDays ??
        (template?.coordinate == null
            ? null
            : boundary.days(template!.frame, Coordinate.fromJson(template.coordinate)));
    if (lower == null) return null;
    try {
      final result = engine.queryFrame(frame, start: lower, end: until, applyOverrides: false);
      return result.facts.where((fact) => fact.pattern == pattern.id).length;
    } on Object catch (_) {
      return null;
    }
  }

  /// EXDATE, restated in the file's OWN TEXT per value. A value whose day is
  /// still excluded keeps the exact spelling and parameters it arrived with; a day
  /// excluded since the import (or one whose text could not be parsed back) is
  /// written fresh. The rebuilt properties go back at the FIRST original EXDATE's
  /// position, so nothing shuffles.
  void _exdates(IcsComponent component, Pattern pattern, Relation relation) {
    final at = component.properties.indexWhere((item) => item.name == 'EXDATE');
    removeProperty(component, 'EXDATE');
    final rebuilt = <IcsProperty>[];
    final remaining = {for (final day in asList(pattern.extra['exdates'])) '$day'};
    for (final row in asList(pattern.extra['exdateProperties'])) {
      final stored = asMap(row);
      if (stored == null) continue;
      final kept = [
        for (final item in asList(stored['values']))
          if (asMap(item) case final Json value)
            if (value['day'] == null || remaining.contains('${value['day']}')) value,
      ];
      for (final item in kept) {
        remaining.remove('${item['day']}');
      }
      if (kept.isEmpty) continue;
      rebuilt.add(
        IcsProperty(
          'EXDATE',
          params: [
            for (final param in asList(stored['params']))
              IcsParam('${asMap(param)?['name']}', [
                for (final value in asList(asMap(param)?['values'])) '$value',
              ]),
          ],
          value: [for (final item in kept) '${item['value']}'].join(','),
        ),
      );
    }
    if (remaining.isNotEmpty) {
      final parameters = asMap(relation.extra['parameters']) ?? const {};
      final dateOnly = parameters['dateOnly'] == true;
      rebuilt.add(
        IcsProperty(
          'EXDATE',
          params: icsValueParams(dateOnly: dateOnly, timeZone: str(parameters['timeZone'])),
          value: [
            for (final day in remaining)
              coordinateToIcs(
                daysToCivilCoordinate(Rational.parse(day)),
                dateOnly: dateOnly,
                utc: parameters['utc'] == true,
              ),
          ].join(','),
        ),
      );
    }
    component.properties.insertAll(at < 0 ? component.properties.length : at, rebuilt);
  }

  /// One following segment as a PLAIN SIBLING VEVENT.
  ///
  /// RFC 5545 has no concept of a series whose rule changes part-way through, and
  /// the dialect that used to carry the linkage is dead. So each segment after the
  /// first is emitted as an ordinary independent event with its own correct
  /// DTSTART, DTEND, RRULE and EXDATEs. Hiding them would be data loss; the
  /// identity is simply not emitted, which is the named loss of the ruled
  /// boundary. The UID is DERIVED from the base UID and the segment's own index so
  /// a re-export is byte-identical -- it is a UID, not a dialect, and nothing
  /// reads it back as identity.
  IcsComponent? _sibling(Pattern pattern, Segment segment, Relation template, String baseUid) {
    final base = segment.rule.baseCoordinate;
    if (base == null || baseUid.isEmpty) return null;
    final coordinate = Coordinate.fromJson(base);
    final event = document.events[pattern.templateEvent];
    final payload = event?.payload ?? const <String, Object?>{};
    final component = IcsComponent('VEVENT');
    setProperty(component, 'UID', '$baseUid-segment-${segment.index}');
    setProperty(component, 'SUMMARY', escapeIcsText(str(payload['title']) ?? '(untitled)'));
    for (final name in const ['DESCRIPTION', 'LOCATION']) {
      final text = escapeIcsText(str(payload[name.toLowerCase()]) ?? '');
      if (text.isNotEmpty) setProperty(component, name, text);
    }
    final parameters = asMap(template.extra['parameters']) ?? const {};
    final dateOnly = coordinateIsDateOnly(coordinate);
    final utc = parameters['utc'] == true;
    final params = icsValueParams(dateOnly: dateOnly, timeZone: str(parameters['timeZone']));
    final frame = segment.rule.frame ?? str(pattern.extra['frame']);
    setProperty(
      component,
      'DTSTART',
      coordinateToIcs(boundary.boundaryCoordinate(frame, coordinate), dateOnly: dateOnly, utc: utc),
      params,
    );
    // A following rule's own magnitude governs ITS occurrences; absent, the
    // template's duration does.
    final magnitude = segment.rule.magnitude;
    final seconds = boundary.magnitudeSeconds(
      magnitude == null ? event?.duration : Magnitude.fromJson(magnitude),
    );
    final startDays = boundary.days(frame, coordinate);
    if (seconds > Rational.zero && startDays != null) {
      setProperty(
        component,
        'DTEND',
        coordinateToIcs(
          daysToCivilCoordinate(startDays + seconds / icsSecondsPerDay),
          dateOnly: dateOnly,
          utc: utc,
        ),
        params,
      );
    }
    setProperty(
      component,
      'RRULE',
      serializeRRule(
        normalizedRuleForExport(_boundedRule(pattern, segment, _rule(segment.rule.rrule))),
      ),
    );
    // A following segment's exclusions are ChronoLog-authored and have no prior
    // ICS text to preserve, so they are written fresh.
    if (segment.rule.exdates.isNotEmpty) {
      component.properties.add(
        IcsProperty(
          'EXDATE',
          params: params,
          value: [
            for (final day in segment.rule.exdates)
              coordinateToIcs(
                daysToCivilCoordinate(Rational.parse('$day')),
                dateOnly: dateOnly,
                utc: utc,
              ),
          ].join(','),
        ),
      );
    }
    setProperty(component, 'DTSTAMP', icsTimestamp(now));
    return component;
  }

  /// PROJECTIONS OUT: the occurrences of any pattern on this frame that is NOT one
  /// of the RRULE patterns already exported as rules, materialized as plain
  /// VEVENTs. A rule ICS cannot express is not withheld -- it is written out as
  /// the concrete events it produces.
  void _projections(
    IcsComponent calendar,
    String frame,
    List<Pattern> exported,
    Coordinate? start,
    Coordinate? end,
  ) {
    final engine = this.engine;
    if (engine == null || start == null || end == null) return;
    final ruled = {for (final pattern in exported) pattern.id};
    for (final fact in engine.queryFrame(frame, start: start.toJson(), end: end.toJson()).facts) {
      if (fact.kind != 'virtual' || ruled.contains(fact.pattern)) continue;
      calendar.components.add(_component(fact.event, fact.relation));
    }
  }
}
