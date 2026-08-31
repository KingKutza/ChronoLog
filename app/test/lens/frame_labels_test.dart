// ARBITRARY FRAME LABELLING (ISSUES 8.31, "Hour labels and other calendars",
// Don live).
//
// "12 vs 24 hour display — or both, or what have you — must be settable; and the
// frame definition must support arbitrary label setups to enable other calendars.
// Class: how a unit is named and rendered is part of the frame's coordinate
// definition, arbitrary rather than an enumerated 12/24 pair (enum is the enemy);
// 12h and 24h are two trivial authored setups of the general capability, "both" is
// legal, and a frame for another calendar authors its own labeling wholesale."
//
// The declaration ALREADY carries authored value names -- `Level.names`, "authored
// names for this level's values", which is how a month is called Ashfall and a
// weekday is called Batman. The hour is a level like any other, so a frame that
// names its hours is the general capability's smallest instance, and the clock
// label a lens draws is where those names have to arrive.
//
// `LawContext.clockLabel` instead composes one hardcoded presentation: the day's
// own midpoint, an 'a'/'p' suffix, a colon and a two-digit tail. Nothing a frame
// declares can change it, which is the enum in a costume -- one right way to name
// an hour, with the other ways precluded.

import 'package:chronolog/core/coordinate_law.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/lens/law_context.dart';
import 'package:flutter_test/flutter_test.dart';

/// A Gregorian-shaped ladder whose HOUR level carries authored names.
Json ladderNamingHours(List<String> names) => {
  'kind': 'nested',
  'baseLevel': 'day',
  'levels': [
    {'name': 'year'},
    {'name': 'day', 'within': 'year', 'radix': '365'},
    {'name': 'hour', 'within': 'day', 'radix': '${names.length}', 'names': names},
    {'name': 'minute', 'within': 'hour', 'radix': '60'},
  ],
};

CoordinateLaw lawNaming(List<String> names, String id) => CoordinateLaw(
  Declaration.parse(ladderNamingHours(names), 'Frame $id'),
  frameId: id,
);

/// The 24-hour setup, authored: one name per hour of the frame's own day.
List<String> twentyFour = [for (var hour = 0; hour < 24; hour += 1) '${'$hour'.padLeft(2, '0')}:00'];

/// The 12-hour setup, authored over the same ladder: the same capability, a
/// different setup. Neither is a mode the code knows about.
List<String> twelve = [
  for (var hour = 0; hour < 24; hour += 1)
    '${hour % 12 == 0 ? 12 : hour % 12}${hour < 12 ? 'am' : 'pm'}',
];

/// A frame for a calendar that is not ours at all: eight hours, its own words.
const List<String> watches = [
  'Dawnwatch',
  'Firstlight',
  'Highsun',
  'Longshadow',
  'Duskwatch',
  'Firstdark',
  'Deepnight',
  'Lastdark',
];

void main() {
  test('a frame that names its hours is what the clock label reads', () {
    // The ninth hour, on the frame's own ladder.
    for (final setup in [twentyFour, twelve]) {
      final law = lawNaming(setup, 'frame:setup${setup.length}');
      final context = LawContext(law);
      final minutes = Rational.fromInt(9 * 60);
      expect(
        context.clockLabel(minutes),
        setup[9],
        reason:
            'ISSUES (8.31): "how a unit is named and rendered is part of the frame\'s '
            'coordinate definition ... 12h and 24h are two trivial authored setups of '
            'the general capability" — the label ignores the frame\'s authored hour '
            'names and composes one hardcoded reading instead.',
      );
    }
  });

  test('two authored setups over one ladder read differently: labelling is data', () {
    final wide = LawContext(lawNaming(twentyFour, 'frame:24'));
    final short = LawContext(lawNaming(twelve, 'frame:12'));
    final afternoon = Rational.fromInt(15 * 60);
    expect(
      wide.clockLabel(afternoon),
      isNot(short.clockLabel(afternoon)),
      reason:
          'ISSUES (8.31): 12 vs 24 hour display "must be settable" — both setups read '
          'the same, because nothing the frame declares reaches the label.',
    );
  });

  test('a calendar of another world authors its hour names wholesale', () {
    final law = lawNaming(watches, 'frame:otherworld');
    final context = LawContext(law);
    // Its day has eight hours; the third of them is called what its frame says.
    expect(context.hoursPerDay, Rational.fromInt(8), reason: 'the ladder is its own');
    expect(
      context.clockLabel(Rational.fromInt(2 * 60)),
      watches[2],
      reason:
          'ISSUES (8.31): "a frame for another calendar authors its own labeling '
          'wholesale" — the lens says ${context.clockLabel(Rational.fromInt(2 * 60))} '
          'instead.',
    );
  });
}
