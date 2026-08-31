// DAY START/END IS AN AUTHORED OBJECT, NOT A SETTING (ISSUES 8.31, Don live).
//
// "seems like a good setting but I think it is a bad one" — today it is a setting
// with crude hour increments. The ruled shape: "day start/end is an authored
// object — a daily series — whose handling says display-as-zone, capable of all
// the math definition staples give (one-math placements, fuzz, arbitrary points),
// not an hour picker. The setting dies. Class: anything that names a region of
// time is an authored object with display handling; settings hold chrome numbers,
// never calendar facts."
//
// SENTENCES.md says the same in the card's own words: "Day is placed on My
// calendar at every t: 06:30 <= t.time <= 22:00. Day displays as a zone. An
// authored object, not a setting."
//
// So: one case that the setting is gone, and one that the authored object is what
// draws the zone -- which is the half that has to work before the setting can go.

import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/projection.dart';
import 'package:chronolog/lens/painters/intimate.dart';
import 'package:chronolog/lens/zones.dart';
import 'package:chronolog/session/lens_catalog.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/projection_scene.dart';
import 'painters/grid_scene.dart';

final Rational _september = Rational(daysFromCivil(BigInt.from(2026), 9, 1));

/// The authored day, in SENTENCES.md's own example: "Day is placed on My
/// calendar at every t: 06:30 <= t.time <= 22:00. Day displays as a zone." As a
/// daily series with a duration, which is what the model holds today.
String authorTheDay(Scene world, {int month = 9}) {
  final pattern = world.series(
    'calendar:a',
    const {'FREQ': 'DAILY'},
    at: civil(2026, month, 1, 6, 30),
    duration: '930',
  );
  final template = world.document.patterns[pattern]!.templateEvent!;
  world.document = world.document.put(
    'events',
    template,
    world.document.events[template]!.withField('display', const {'zone': true}),
  );
  return template;
}

/// What Intimate draws, by width: the lane each mark was given. With no
/// [objectId] it answers for the SERIES occurrences -- which is how the day
/// object is asked about, its occurrences carrying virtual ids of their own.
List<double> drawnWidths(Scene world, {String? objectId}) {
  final scene = sceneOf(
    world.document,
    const ['calendar:a'],
    view: const {'back': 0, 'forward': 0, 'hourPixels': 24},
  );
  final painter = IntimatePainter(scene);
  render(painter, const Size(960, 720));
  return [
    for (final hit in painter.hits)
      if (objectId == null ? hit.fact.pattern != null : hit.fact.event.id == objectId)
        hit.bounds.width,
  ];
}

void main() {
  test('the day\'s start and end are not settings, and no control picks an hour for them', () {
    final settings = chronologSettings();
    final held = settings.keys
        .where((key) => key.contains('startHour') || key.contains('endHour'))
        .toList();
    expect(
      held,
      isEmpty,
      reason:
          'ISSUES (8.31): "day start/end is an authored object — a daily series — '
          'whose handling says display-as-zone ... The setting dies." These keys still '
          'hold the day: $held',
    );
    final controls = [
      for (final lens in lensCatalog.values)
        for (final control in lens.controls)
          if ((control.setting ?? '').contains('startHour') ||
              (control.setting ?? '').contains('endHour'))
            '${lens.id}.${control.key} (${control.label})',
    ];
    expect(
      controls,
      isEmpty,
      reason:
          'ISSUES (8.31): "today it is a setting with crude hour increments" — the '
          'lens catalog still offers an hour picker for the day: $controls',
    );
  });

  test('an authored daily object with display-as-zone is what names the day', () {
    final world = Scene()..calendar('calendar:a');
    authorTheDay(world);
    final engine = ProjectionEngine(world.document);
    final result = engine.queryFacts(
      Projection.of(['calendar:a']),
      start: _september,
      end: _september + Rational.fromInt(7),
    );
    expect(
      result.facts.map((fact) => fact.day.floor()).toSet().length,
      greaterThanOrEqualTo(7),
      reason: 'a daily object is on every day of the week',
    );
    for (final fact in result.facts) {
      expect(
        zoneFill(engine, fact, null),
        isTrue,
        reason:
            'ISSUES (8.31): the day region is "an authored object ... whose handling '
            'says display-as-zone" — the handling authored on the series template '
            'does not reach its generated occurrences, so the day would draw as a '
            'chip per day instead of a zone.',
      );
    }
  });

  test('the day zone is a REGION: it takes no lane from the day it names', () {
    // A zone is not a chip competing for room -- "one continuous band across the
    // days it covers, rather than a repeated chip". The day object overlaps
    // everything on its day, so if it packed like an event it would push every
    // event of that day into half a column, which is the setting's crude wash
    // replaced by something worse.
    final world = Scene()..calendar('calendar:a');
    final morning = world.object(title: 'Morning');
    world.place('calendar:a', civil(2026, 8, 18, 9), event: morning);
    final alone = drawnWidths(world, objectId: morning);
    expect(alone, isNotEmpty, reason: 'the event is drawn at all');
    authorTheDay(world, month: 8);
    final zone = drawnWidths(world);
    expect(zone, isNotEmpty, reason: 'the day object is on this day, so it is drawn');
    for (final width in zone) {
      expect(
        width,
        greaterThanOrEqualTo(alone.first),
        reason: 'the day zone spans the column it names',
      );
    }
    expect(
      drawnWidths(world, objectId: morning),
      alone,
      reason:
          'ISSUES (8.31): authoring the day cost the day\'s own events their width — '
          'the zone took a lane instead of being the region it is.',
    );
  });
}
