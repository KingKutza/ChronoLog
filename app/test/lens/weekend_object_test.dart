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
// painter. A calendar with a rest position elsewhere, several, none, or a rest
// that is not a whole day cannot say so, and nothing can give the weekend a
// name, a colour or a magnitude.
//
// The ruling is the one already on the books for the day (`lens/zones.dart`):
// "day start/end is an authored object -- a daily series -- whose handling says
// display-as-zone ... The setting dies." So:
//
//   The weekend is an AUTHORED REPEATING OBJECT over the law's own weekday
//   cycle, zone-handled, with its own colour and weight. The painter learns
//   nothing about weekends. A fresh Gregorian document ships one seeded weekend
//   -- a default a person can read, rename, recolour and unsay, not a lens that
//   knows -- and a law with a weekday cycle of another length, or none, gets no
//   weekend it did not author.
//
// NOT IN SCOPE, and deliberately not swept here: `grid.washToday` and
// `grid.washPast` are clock facts, `wall.firstWeekday` rotates the layout. They
// stay. The weekend was the only encoded meaning.
//
// Nothing here pins which cycle positions the weekend falls on, and nothing
// reads a title: the seeded object is found by the PROPERTY that makes it a
// weekend -- its facts recur on the law's weekday cycle and draw as a zone.

import 'dart:math';
import 'dart:ui';

import 'package:chronolog/cards/settings_vocabulary.dart';
import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/projection.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/edit/editor.dart';
import 'package:chronolog/lens/lens_painter.dart';
import 'package:chronolog/lens/painters/month_grid.dart';
import 'package:chronolog/lens/painters/strategic.dart';
import 'package:chronolog/lens/painters/tactical.dart';
import 'package:chronolog/lens/painters/wall.dart';
import 'package:chronolog/lens/zones.dart';
import 'package:chronolog/store/document_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/corpus.dart';
import '../helpers/projection_scene.dart';
import '../store/harness.dart';
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

/// The seeded weekend, found by what makes it one. Over a window of several
/// cycles the object's facts land on the same cycle positions every turn, on a
/// nonempty PROPER subset of them (a weekend that is every day is a day, and one
/// that is no day is nothing), and each fact draws as a zone.
String? seededWeekend(Document document, {required int cycles}) {
  final engine = ProjectionEngine(document);
  final law = engine.lawOf(wallTime);
  final radix = law.weekdayNames()!.length;
  final from = civilDays(2026, 9, 6);
  final result = engine.queryFacts(
    Projection.of(const [wallTime]),
    start: from,
    end: from + Rational.fromInt(radix * cycles),
  );
  final byObject = <String, Set<int>>{};
  final zoned = <String, bool>{};
  for (final fact in result.facts) {
    final position = law.cycleIndex('weekday', fact.day);
    if (position == null) continue;
    (byObject[fact.event.id] ??= {}).add(position);
    zoned[fact.event.id] = (zoned[fact.event.id] ?? true) && zoneFill(engine, fact, allTunables);
  }
  for (final entry in byObject.entries) {
    final positions = entry.value;
    if (positions.isEmpty || positions.length >= radix) continue;
    // Every turn of the cycle, the same positions: count the facts per position
    // and require one per turn.
    final perPosition = <int, int>{};
    for (final fact in result.facts) {
      if (fact.event.id != entry.key) continue;
      final position = law.cycleIndex('weekday', fact.day)!;
      perPosition[position] = (perPosition[position] ?? 0) + 1;
    }
    if (perPosition.values.every((count) => count == cycles) && zoned[entry.key] == true) {
      return entry.key;
    }
  }
  return null;
}

Future<Editor> editorOver(Document document) async {
  final store = DocumentStore(
    dataRoot: 'memory',
    files: MemoryFiles(),
    scheduler: ManualScheduler(),
    establish: () => document,
  );
  await store.load();
  return Editor(store);
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

  test('a fresh Gregorian document ships one seeded weekend: a zone-handled object recurring '
      'on the law\'s own weekday cycle', () {
    for (final seed in seeds(3)) {
      final random = Random(seed);
      final document = createEmptyWorkspaceDocument(now: DateTime.utc(2026, 9, 1));
      final found = seededWeekend(document, cycles: 2 + random.nextInt(4));
      expect(
        found,
        isNotNull,
        reason:
            'ISSUES 9.2 (seed $seed): "what ships in a fresh document is a seeded weekend object '
            'on the Gregorian law, visible on the card, renameable, recolourable, deletable -- a '
            'default the person can read and unsay, not a lens that knows." No object in the '
            'fresh document recurs on the weekday cycle and draws as a zone.',
      );
      // Nameable: it is an ordinary object in the document, which is what the
      // object card edits -- not a frame, not a setting, not a pattern alone.
      expect(document.events.containsKey(found), isTrue, reason: 'the weekend is an object');
    }
  });

  test('the weekend is what the grid paints, in its own authored colour', () {
    // "its own colour and weight." Meaning is authored: the wash used to be the
    // theme's muted tone, which no one chose. Two different authored colours
    // must paint two different fills; there is no colour the painter picks.
    final document = createEmptyWorkspaceDocument(now: DateTime.utc(2026, 9, 1));
    final weekend = seededWeekend(document, cycles: 2);
    if (weekend == null) {
      fail('ISSUES 9.2: no seeded weekend object to recolour (see the previous case).');
    }
    for (final seed in seeds(3)) {
      final random = Random(seed);
      String hex() =>
          '#${random.nextInt(1 << 24).toRadixString(16).padLeft(6, '0')}';
      final one = hex();
      var other = hex();
      while (other == one) {
        other = hex();
      }
      Document painted(String color) => document.put(
        'events',
        weekend,
        document.events[weekend]!.withField('color', color),
      );
      for (final lens in gridLenses) {
        final first = fillsOf(painted(one), wallTime, lens.build);
        final second = fillsOf(painted(other), wallTime, lens.build);
        expect(first, isNotEmpty, reason: 'the weekend paints on ${lens.name}');
        expect(
          first.toSet(),
          isNot(equals(second.toSet())),
          reason:
              'ISSUES 9.2 (seed $seed): recolouring the weekend object changed nothing on '
              '${lens.name} -- the fill is the lens\'s own tone, not the object\'s authored '
              'colour.',
        );
      }
    }
  });

  test('deleting the seeded weekend leaves no grey anywhere, on every grid lens', () async {
    // The painter knows nothing about weekends: with the object gone there is
    // nothing left to draw, and no fill remains in any cell of any sheet.
    final document = createEmptyWorkspaceDocument(now: DateTime.utc(2026, 9, 1));
    final weekend = seededWeekend(document, cycles: 2);
    final editor = await editorOver(document);
    if (weekend != null) editor.deleteObject(weekend);
    for (final lens in gridLenses) {
      final fills = fillsOf(editor.document, wallTime, lens.build);
      expect(
        fills,
        isEmpty,
        reason:
            'ISSUES 9.2: with no weekend object in the document, ${lens.name} still lays down '
            '${fills.length} fill(s) -- the lens holds the belief "some positions of the weekday '
            'cycle are lesser" on its own.',
      );
    }
    // And the unsaying is undoable like everything else, which is what makes a
    // shipped default safe to delete.
    if (weekend != null) {
      expect(editor.undo(), isTrue);
      expect(editor.document.events.containsKey(weekend), isTrue);
    }
  });

  test('a law with a weekday cycle of another length gets no weekend it did not author', () {
    // "otherwise it may break with a non-Gregorian calendar." A five-day week
    // under an 8x8x8 ladder: the fresh document's weekend is stapled to wall
    // time and says nothing about this frame, so this frame has no weekend --
    // and a painter that greyed position 0 here would be inventing one.
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
    // A world with no week has no weekend. The invented pen-stroke ladder from
    // the staple world has no cycle; the seeded object, stapled to wall time,
    // must not reach it through any route nobody authored.
    final document = createEmptyWorkspaceDocument(now: DateTime.utc(2026, 9, 1)).put(
      'frames',
      'frame:invented',
      const Frame(
        id: 'frame:invented',
        title: 'A curve of handwriting',
        traits: ['line', 'temporal'],
        extra: {'coordinate': inventedLaw},
      ),
    );
    final engine = ProjectionEngine(document);
    expect(engine.lawOf('frame:invented').hasWeekdays(), isFalse);
    final result = engine.queryFacts(
      Projection.of(const ['frame:invented']),
      start: Rational.zero,
      end: Rational.fromInt(64),
    );
    expect(
      result.facts,
      isEmpty,
      reason: 'the fresh document\'s weekend says nothing about a frame with no week',
    );
  });
}
