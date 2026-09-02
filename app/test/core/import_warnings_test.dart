// AN IMPORT READS IN A SCREEN (ISSUES 9.2, the wall of errors).
//
// "I just imported US Holidays and Work, and got an impressive wall of errors."
// The document card renders every warning as its own note, and the three ICS
// warning sites fire per event, naming events by UID. The rule:
//
//   Warnings are CLASSES WITH COUNTS -- one line per class, expandable to the
//   named events (by title and date) -- so an import of any size reads in a
//   screen. Overscale rule: 500 calendars, one screen.
//
// Generative: a random number of events all sharing one mismatch.

import 'dart:io';
import 'dart:math';

import 'package:chronolog/cards/document_card.dart';
import 'package:chronolog/core/document.dart';
import 'package:test/test.dart';

import '../edit/harness.dart';

final int runSeed =
    int.tryParse(Platform.environment['CHRONOLOG_SEED'] ?? '') ??
    DateTime.now().microsecondsSinceEpoch;

String calendarWith(int events) {
  final buffer = StringBuffer()
    ..writeln('BEGIN:VCALENDAR')
    ..writeln('VERSION:2.0')
    ..writeln('PRODID:-//test//EN')
    ..writeln('X-WR-CALNAME:Work');
  for (var i = 0; i < events; i += 1) {
    final day = (1 + i % 28).toString().padLeft(2, '0');
    buffer
      ..writeln('BEGIN:VEVENT')
      ..writeln('UID:mixed-$i@test')
      ..writeln('SUMMARY:Meeting $i')
      ..writeln('DTSTART;TZID=America/New_York:202609${day}T090000')
      ..writeln('DTEND:202609${day}T140000Z')
      ..writeln('END:VEVENT');
  }
  buffer.writeln('END:VCALENDAR');
  return '$buffer';
}

void main() {
  // ignore: avoid_print
  print('IMPORT WARNINGS RUN SEED: $runSeed  (set CHRONOLOG_SEED=$runSeed to reproduce)');
  final random = Random(runSeed);

  test('N events with one mismatch class yield one warning line, counted', () async {
    final bench = await openEditor(createEmptyWorkspaceDocument());
    addTearDown(() => closeEditor(bench));
    final events = 20 + random.nextInt(40);
    final result = importIcsText(bench.editor, calendarWith(events));
    expect(result.events, hasLength(events), reason: 'every event imports; the boundary is lossless in');
    expect(
      result.warnings.length,
      lessThan(events),
      reason:
          'ISSUES 9.2: $events events sharing ONE mismatch produced ${result.warnings.length} '
          'warnings -- a wall. One line per class with its count, expandable to the named events.',
    );
    expect(
      result.warnings.any((line) => line.contains('$events')),
      isTrue,
      reason: 'the class line carries the count of events it covers',
    );
  });
}
