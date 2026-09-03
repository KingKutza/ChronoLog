// WHAT EVERY SETTING IS, IN WORDS.
//
// ISSUES (9.1): "The settings card is a long list of barely-labeled literals --
// I don't have the first Idea how to navigate or use that." The one-math
// settings substrate was the right model; this file is the other half of it.
// Every key the program composes gets a plain-language LABEL and a plain-
// language EXPLANATION saying what the number does and where it acts, plus the
// range it ORDINARILY rides -- advisory metadata, never a bound, so a control
// can be a number line without ever clamping what a person may write.
//
// FAMILIES ARE MELTED, NOT COPIED. Twenty-two promotion thresholds are one
// sentence with the surface named at read time; fifteen ruler rungs are one
// sentence about a rung. A family says the same thing about every member, so
// saying it once is the only way it cannot drift.
//
// WHICH CARD A KEY LIVES ON is authored here too (ISSUES 9.1, Don's ruling:
// "settings become a family of cards ... on the order of twenty sub-cards, cut
// by the surfaces they govern"). An area no card claims gets a card of its own,
// so no key can hide behind an incomplete table.

import 'settings_vocabulary.dart';

/// One setting, said. [low] and [high] are ADVISORY: expressions in the one
/// math naming where this value ordinarily rides, so a rail can be drawn there.
/// Writing outside them is authoring, not an error, and nothing clamps.
class SettingSaid {
  const SettingSaid(this.label, this.says, {this.low, this.high});

  final String label, says;
  final String? low, high;

  bool get railed => low != null && high != null;
}

/// A run of keys that all say the same thing about a different surface. [tail]
/// is the key's tail past its area, with `#` standing for a run of digits and
/// `*` for a run of anything but a dot -- so one entry covers a ladder, and one
/// covers a budget named per format.
class SettingFamily {
  const SettingFamily(this.tail, this.label, this.says, {this.low, this.high});

  final String tail, label, says;
  final String? low, high;
}

/// The surfaces, in the words a person uses for them rather than the prefix the
/// code spells them with.
const Map<String, String> settingAreaNames = {
  'capacity': 'how much fits in a cell',
  'card': 'the cards',
  'chrome': 'the bars',
  'curve': 'the curve view',
  'document': 'the document',
  'edit': 'editing',
  'falloff': 'fading with distance',
  'grid': 'the month grid',
  'ics': 'the calendar boundary',
  'intimate': 'the Intimate lens',
  'keys': 'the keyboard',
  'lane': 'lanes',
  'lines': 'the Lines lens',
  'mark': 'the marks themselves',
  'minimap': 'the minimap',
  'motion': 'how the surface moves',
  'now': 'the now line',
  'pointer': 'the mouse and the wheel',
  'radial': 'the Radial lens',
  'rule': 'rulers',
  'selection': 'what selection looks like',
  'settings': 'these settings cards',
  'spiral': 'the Spiral lens',
  'stage': 'the stage and its windows',
  'strategic': 'the Strategic lens',
  'tactical': 'the Tactical lens',
  'theme': 'the palette',
  'todo': 'the to-do lenses',
  'tree': 'the Tree lens',
  'wall': 'the Wall lens',
  'weight': 'display weight',
  'zone': 'zone fills',
};

/// The sub-cards, and the areas each one governs. Twenty-odd surfaces a person
/// already knows, not thirty prefixes a program spells.
const List<({String title, List<String> areas})> settingsCardTable = [
  (title: 'Cards', areas: ['card']),
  (title: 'The bars', areas: ['chrome']),
  (title: 'The stage', areas: ['stage']),
  // ONE BINDINGS PAGE (ISSUES 9.2, Don: "a manual and a keybindings page...
  // the keybindings page lands next round and must allow resetting"). The
  // pointer chords are bindings exactly as the chords are, so they join the
  // same page rather than sitting on a card of their own -- which is also what
  // makes one Reset all mean the whole vocabulary.
  (title: 'The keyboard and the mouse', areas: ['keys', 'pointer']),
  (title: 'Motion', areas: ['motion']),
  (title: 'The document', areas: ['document']),
  (title: 'The calendar boundary', areas: ['ics']),
  (title: 'Editing', areas: ['edit']),
  (title: 'The minimap', areas: ['minimap']),
  (title: 'The Intimate lens', areas: ['intimate']),
  (title: 'The month grid', areas: ['grid']),
  (title: 'The Lines lens', areas: ['lines']),
  (title: 'The Radial lens', areas: ['radial']),
  (title: 'The Spiral lens', areas: ['spiral']),
  (title: 'The Tree lens', areas: ['tree']),
  (title: 'The curve view', areas: ['curve']),
  (title: 'The Wall lens', areas: ['wall']),
  (title: 'Tactical and Strategic', areas: ['tactical', 'strategic']),
  (title: 'The to-do lenses', areas: ['todo']),
  (title: 'Display weight and fading', areas: ['weight', 'falloff', 'capacity']),
  (title: 'Marks, rulers and lanes', areas: ['mark', 'rule', 'lane', 'now']),
  (title: 'Zones and selection', areas: ['zone', 'selection']),
  (title: 'The palette', areas: ['theme']),
  (title: 'These settings cards', areas: ['settings']),
];

/// One sub-card of the settings family: where it is addressed, what it is
/// called, and which areas it governs.
typedef SettingsSubCard = ({String address, String title, List<String> areas});

/// The whole family, derived: the authored table first, then a card of its own
/// for every area the table never claimed. Nothing composed can go unhoused,
/// and a new area reaches a card the day it ships rather than the day someone
/// remembers to list it.
List<SettingsSubCard> settingsSubCards(Iterable<String> keys) {
  final claimed = <String>{};
  final cards = <SettingsSubCard>[];
  for (final row in settingsCardTable) {
    claimed.addAll(row.areas);
    cards.add((address: row.areas.first, title: row.title, areas: row.areas));
  }
  final loose =
      <String>{
        for (final key in keys)
          if (!claimed.contains(key.split('.').first)) key.split('.').first,
      }.toList()
        ..sort();
  for (final area in loose) {
    cards.add((address: area, title: settingsCardTitle(area), areas: [area]));
  }
  return cards;
}

/// What a sub-card at this address is called. Read by the factory, which names
/// the tile before any document is consulted.
String settingsCardTitle(String address) {
  for (final row in settingsCardTable) {
    if (row.areas.first == address) return row.title;
  }
  final named = settingAreaNames[address];
  if (named == null) return address;
  return '${named[0].toUpperCase()}${named.substring(1)}';
}

/// The families. `#` stands for a run of digits, so one entry covers a ladder.
const List<SettingFamily> settingFamilies = [
  SettingFamily(
    'importantAt',
    'Important at',
    'A mark whose display weight reaches this reads as important here: heavier '
        'ink, and it survives a crowded cell when lighter marks do not.',
    low: '1',
    high: '10',
  ),
  SettingFamily(
    'landmarkAt',
    'Landmark at',
    'A mark whose display weight reaches this reads as a landmark here: the '
        'heaviest reading, and the last thing dropped when room runs out.',
    low: '1',
    high: '10',
  ),
  SettingFamily(
    'ruleLadder.#',
    'Ruler rung',
    'One rung of the ruler ladder, in hours: a spacing the ruler is willing to '
        'settle on. The lens climbs the ladder until a rung fits the room it has.',
  ),
  SettingFamily(
    'budget.*',
    'Label budget',
    'How many labels of this shape the minimap draws across its whole width '
        'before it starts thinning them.',
    low: '4',
    high: '40',
  ),
  SettingFamily(
    'bucket#',
    'Fade step',
    'Where one step of the fade begins, as a share of full nearness: past this, '
        'an item takes the matching step opacity.',
    low: '0',
    high: '1',
  ),
  SettingFamily(
    'opacity#',
    'Fade step opacity',
    'How solid an item is once it has fallen into this step of the fade.',
    low: '0',
    high: '1',
  ),
  SettingFamily(
    'curve.x#',
    'Motion curve handle, across',
    'One horizontal handle of the easing curve every change of ground follows. '
        'Nothing in the program snaps; this is the shape of the arrival.',
    low: '0',
    high: '1',
  ),
  SettingFamily(
    'curve.y#',
    'Motion curve handle, along',
    'One vertical handle of the easing curve every change of ground follows. '
        'Above one it overshoots and settles back.',
    low: '0',
    high: '2',
  ),
];

final RegExp _digits = RegExp(r'\d+');
final RegExp _word = RegExp(r'[^.]+');
final RegExp _holes = RegExp('[#*]');

/// One key, said: its own words where it has them, its family's where it does
/// not. Null for a key nothing has said anything about -- which the wording
/// light refuses by name rather than papering over with the dotted key.
SettingSaid? settingSaidOf(String key) {
  final own = settingVocabulary[key];
  if (own != null) return own;
  final dot = key.indexOf('.');
  if (dot < 0) return null;
  final area = key.substring(0, dot);
  final surface = settingAreaNames[area] ?? area;
  // The whole tail first, then each shorter suffix of it: `todo.board` and
  // `todo.list` promote by the same sentence the eleven other surfaces do, and
  // the sentence is written once.
  final segments = key.split('.').skip(1).toList();
  for (var from = 0; from < segments.length; from += 1) {
    final tail = segments.skip(from).join('.');
    for (final family in settingFamilies) {
      if (!_matches(family.tail, tail)) continue;
      return SettingSaid(
        family.label,
        '${family.says} This one is $surface\'s.',
        low: family.low,
        high: family.high,
      );
    }
  }
  return null;
}

/// Does this key's tail belong to that family? `#` stands for a run of digits
/// and `*` for a run of anything but a dot, so `ruleLadder.#` covers every rung
/// and `budget.*` covers every label format, without either naming one.
bool _matches(String pattern, String tail) {
  if (!pattern.contains(_holes)) return pattern == tail;
  var at = 0, read = 0;
  while (read < pattern.length) {
    final hole = pattern.indexOf(_holes, read);
    final literal = pattern.substring(read, hole < 0 ? pattern.length : hole);
    if (!tail.startsWith(literal, at)) return false;
    at += literal.length;
    if (hole < 0) return at == tail.length;
    final run = (pattern[hole] == '#' ? _digits : _word).matchAsPrefix(tail, at);
    if (run == null) return false;
    at = run.end;
    read = hole + 1;
  }
  return at == tail.length;
}
