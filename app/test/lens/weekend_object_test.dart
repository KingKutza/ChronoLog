// THE WEEKEND IS AN AUTHORED OBJECT, NOT A BELIEF IN A LENS (ISSUES 9.2, Don).
//
// "The grayed weekends on Strategic -- as best as I can tell that is not an
// authored zone event, and it should be. We don't want to encode that sort of
// thing in a lens, otherwise it may break with a non-Gregorian calendar. And even
// with it, it is a less than elegant data model."
//
// Verified: `lens/painters/month_grid.dart` paints a wash where
// `isWeekend(weekdayOf(day))`, reading `grid.weekendCount` + `grid.weekend.1` +
// `grid.weekend.2` -- a count-plus-index pseudo-list, which is an enum wearing
// numbers: two positions, marked by the shipped default, meaning nothing anyone
// said. Strategic, Tactical and Wall draw it together, because they share the
// painter.
//
// THEN DON'S QUESTION SETTLED WHAT A WEEKEND IS: "Three steps back -- what is a
// 'weekend'? Is it a feature of the Gregorian calendar, or a cultural event that
// happens to be ubiquitous?" A CULTURAL EVENT. Two people on the identical
// Gregorian law disagree about which positions are the weekend, so "a property
// of a calendar cannot be something two users of that same calendar answer
// differently." The weekday CYCLE is the law's; the weekend is a SELECTION OF
// POSITIONS in it, asserted by someone -- an authored object over a cycle, held
// in the numbers a person can have many of.
//
// AND THE RULING ON WHAT SHIPS, option (c): "no offer at all, now, and reassess
// when cycles land. So the weekend is authored by the person, once, per
// document -- nothing seeded, nothing offered, nothing in the new-frame flow.
// `createEmptyWorkspaceDocument` keeps 'two structural frames and nothing
// else'." This file was first authored against a SEEDED weekend and asserted one
// in a fresh document; it is re-authored here to the ruling:
//
//   The lens holds no weekend belief: no setting names one, and a fresh document
//   paints no fill on any grid lens.
//   An AUTHORED weekend -- a weekly series on the law's own weekday cycle, zone-
//   handled by its group, in the group's colour -- draws as a zone in that colour
//   on every grid lens, and recolouring it recolours the drawing.
//   A fresh document has neither: no object, no wash.
//   A law with a weekday cycle of another length, or none, gets no weekend it
//   did not author.
//
// NOT IN SCOPE: `grid.washToday` and `grid.washPast` are clock facts,
// `wall.firstWeekday` rotates the layout. They stay. The weekend was the only
// encoded meaning.

import 'dart:math';
import 'dart:ui';

import 'package:chronolog/cards/settings_vocabulary.dart';
import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/projection.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/lens/lens_painter.dart';
import 'package:chronolog/lens/painters/month_grid.dart';
import 'package:chronolog/lens/painters/strategic.dart';
import 'package:chronolog/lens/painters/tactical.dart';
import 'package:chronolog/lens/painters/wall.dart';
import 'package:chronolog/lens/theme.dart';
import 'package:chronolog/lens/zones.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/corpus.dart';
import '../helpers/projection_scene.dart';
import 'painters/grid_scene.dart';

const String wallTime = 'frame:wall-time';
const Size surface = Size(1200, 800);

/// A clock reading far from anything painted, so neither the today wash nor the
/// past slash is in the picture: the only fills left are the ones an object
/// asked for.
final Rational farAway = civilDays(1900, 1, 1);

/// The three grid lenses, as the catalog's own builders. Intimate is a rail, not
/// a sheet, and paints no weekday grid.
const List<({String name, DayGridPainter Function(LensScene) build})> gridLenses = [
  (name: 'tactical', build: TacticalPainter.new),
  (name: 'strategic', build: StrategicPainter.new),
  (name: 'wall', build: WallPainter.new),
];

/// Every FILL the painter drew, and nothing else. A wash, a zone band and a chip
/// are all fills; rules and slashes are strokes. Nothing here interprets: the
/// claim is about whether a coloured area was laid down at all.
class Fills implements Canvas {
  final List<Color> colors = [];

  void _fill(Paint paint) {
    if (paint.style == PaintingStyle.fill && paint.color.a > 0) colors.add(paint.color);
  }

  @override
  void drawRect(Rect rect, Paint paint) => _fill(paint);

  @override
  void drawRRect(RRect rrect, Paint paint) => _fill(paint);

  @override
  void drawPath(Path path, Paint paint) => _fill(paint);

  @override
  void noSuchMethod(Invocation invocation) {}
}

List<Color> fillsOf(Document document, String frame, DayGridPainter Function(LensScene) build) {
  final scene = sceneOf(
    document,
    [frame],
    size: surface,
    focus: civilDays(2026, 9, 15),
    now: farAway,
  );
  final painter = build(scene);
  // Once for the layout, once onto the recorder: the same paint the eye gets.
  render(painter, surface);
  final drawn = Fills();
  painter.paint(drawn, surface);
  return drawn.colors;
}

/// THE PERSON'S OWN WEEKEND: a group that says zone and wears a colour, and a
/// weekly all-day series on the law's weekday cycle whose template is in it.
/// Which positions are the weekend is the author's -- two are drawn here at
/// random, because nothing about the claim depends on which.
({Document document, String group}) authoredWeekend(Random random, String color) {
  final scene = Scene();
  scene.group('group:weekend', const [], extra: {
    'display': {'zone': true},
    'color': color,
  });
  const codes = ['SU', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA'];
  final first = random.nextInt(7);
  final second = (first + 1 + random.nextInt(6)) % 7;
  final pattern = scene.series(
    wallTime,
    {'FREQ': 'WEEKLY', 'BYDAY': '${codes[first]},${codes[second]}'},
    at: civil(2026, 8, 30, 0),
    duration: '${24 * 60}',
  );
  final template = scene.document.patterns[pattern]!.templateEvent!;
  scene.join('group:weekend', template);
  return (document: scene.document, group: 'group:weekend');
}

/// An 8x8x8 calendar carrying an authored FIVE-position weekday cycle: a law
/// with a week, and not ours.
const Json fiveDayWeekLaw = {
  ...eightLaw,
  'cycles': [
    {
      'name': 'weekday',
      'radix': '5',
      'names': ['Ash', 'Bole', 'Cinder', 'Dusk', 'Ember'],
    },
  ],
};

void main() {
  test('no setting holds a weekend: no wash, no count, no indexed position', () {
    // The count-plus-index pseudo-list is an enum wearing numbers. "Any system
    // that encodes a right way does in the same breath preclude other ways."
    // The vocabulary map is swept too, because a setting the card still
    // explains is a setting that still exists to someone.
    final held = {
      for (final key in chronologSettings().keys)
        if (key.toLowerCase().contains('weekend')) key,
      for (final key in gridTunableDefaults.keys)
        if (key.toLowerCase().contains('weekend')) key,
      for (final key in settingVocabulary.keys)
        if (key.toLowerCase().contains('weekend')) key,
    };
    expect(
      held,
      isEmpty,
      reason:
          'ISSUES 9.2: "we don\'t want to encode that sort of thing in a lens." The weekend is '
          'an authored object; the setting dies, as the day\'s did. Still held: $held',
    );
  });

  test('a fresh document has no weekend: no object, and no fill on any grid lens', () {
    // Option (c): "nothing seeded, nothing offered." And the painter knows
    // nothing about weekends: with no object in the document there is nothing to
    // draw, and no fill lands in any cell of any sheet.
    final document = createEmptyWorkspaceDocument(now: DateTime.utc(2026, 9, 1));
    expect(document.events, isEmpty, reason: 'two structural frames and nothing else');
    for (final lens in gridLenses) {
      final fills = fillsOf(document, wallTime, lens.build);
      expect(
        fills,
        isEmpty,
        reason:
            'ISSUES 9.2: with nothing in the document, ${lens.name} still lays down '
            '${fills.length} fill(s) -- the lens holds the belief "some positions of the weekday '
            'cycle are lesser" on its own.',
      );
    }
  });

  test('an authored weekend draws as a zone in its own colour, on every grid lens', () {
    // "The weekend is an AUTHORED OBJECT -- a repeating series over the law's
    // weekday cycle, `display.zone` on its frame, its own colour and weight --
    // and the painter learns nothing about weekends." Meaning is authored: the
    // wash used to be the theme's muted tone, which no one chose. The zone's
    // fill is the one `zoneBand` derives from the authored colour, and two
    // authored colours paint two different fills.
    final theme = shipped['paper']!;
    for (final seed in seeds(3)) {
      final random = Random(seed);
      String hex() => '#${random.nextInt(1 << 24).toRadixString(16).padLeft(6, '0')}';
      final one = hex();
      var other = hex();
      while (other == one) {
        other = hex();
      }
      for (final lens in gridLenses) {
        final first = fillsOf(authoredWeekend(Random(seed), one).document, wallTime, lens.build);
        final second = fillsOf(authoredWeekend(Random(seed), other).document, wallTime, lens.build);
        expect(
          first,
          isNotEmpty,
          reason: 'ISSUES 9.2 (seed $seed): the authored weekend paints nothing on ${lens.name}',
        );
        final expected = zoneBand(
          const Rect.fromLTWH(0, 0, 10, 10),
          parseColor(one)!,
          zoneWhole,
          theme,
          allTunables,
        ).fill.color;
        expect(
          first,
          contains(expected),
          reason:
              'ISSUES 9.2 (seed $seed): ${lens.name} lays no zone fill in the weekend\'s own colour '
              '$one -- the fill is the lens\'s tone, not the object\'s.',
        );
        expect(
          first.toSet(),
          isNot(equals(second.toSet())),
          reason: 'recolouring the weekend object recolours the drawing on ${lens.name}',
        );
      }
    }
  });

  test('a law with a weekday cycle of another length gets no weekend it did not author', () {
    // "otherwise it may break with a non-Gregorian calendar." A five-day week
    // under an 8x8x8 ladder: nobody authored a weekend on this frame, so this
    // frame has no weekend -- and a painter that greyed position 0 here would be
    // inventing one.
    final document = createEmptyWorkspaceDocument(now: DateTime.utc(2026, 9, 1)).put(
      'frames',
      'frame:five',
      const Frame(
        id: 'frame:five',
        title: 'Five-day week',
        traits: ['set', 'calendar'],
        extra: {'coordinate': fiveDayWeekLaw},
      ),
    );
    final engine = ProjectionEngine(document);
    expect(engine.lawOf('frame:five').weekdayNames()?.length, 5, reason: 'the law has a week');
    for (final lens in gridLenses) {
      final scene = sceneOf(document, const ['frame:five'], size: surface, now: farAway);
      final painter = lens.build(scene);
      render(painter, surface);
      final drawn = Fills();
      painter.paint(drawn, surface);
      expect(
        drawn.colors,
        isEmpty,
        reason:
            'ISSUES 9.2: ${lens.name} paints ${drawn.colors.length} fill(s) on a calendar '
            'nobody authored a weekend for.',
      );
    }
  });

  test('a law with no weekday cycle at all projects no weekend', () {
    // A world with no week has no weekend. The invented pen-stroke ladder has no
    // cycle; an authored weekend on wall time must not reach it through any
    // route nobody authored.
    final authored = authoredWeekend(Random(specSeed), '#336699').document.put(
      'frames',
      'frame:invented',
      const Frame(
        id: 'frame:invented',
        title: 'A curve of handwriting',
        traits: ['line', 'temporal'],
        extra: {'coordinate': inventedLaw},
      ),
    );
    final engine = ProjectionEngine(authored);
    expect(engine.lawOf('frame:invented').hasWeekdays(), isFalse);
    final result = engine.queryFacts(
      Projection.of(const ['frame:invented']),
      start: Rational.zero,
      end: Rational.fromInt(64),
    );
    expect(
      result.facts,
      isEmpty,
      reason: 'a weekend authored on wall time says nothing about a frame with no week',
    );
  });
}
