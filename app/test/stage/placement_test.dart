// Placement rules: same kind tabs together, different kinds split, and an
// overflowing tab container falls through to the next rule.
//
// AND WHERE THE RULE LIST LIVES (ISSUES 9.1, Don's ruling on placement home):
// "File wins; settings edits file. App hot loads file... go back and forth if
// you are that kind of psychopath." The layout file's placement section is the
// one source of truth; the `stage.placement` setting is a read/write VIEW of
// that section, so the same rules can be authored by either road and the two
// cannot disagree. `bindSession` already reads the layout file and watches it,
// so a file that changes on disk arrives here as another `applyJson`.

import 'dart:convert';

import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/stage/layout_tree.dart';
import 'package:chronolog/stage/placement_rules.dart';
import 'package:chronolog/stage/tile.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

TileSpec _spec(String id, {String type = 'view', String klass = 'lens'}) => TileSpec(
  id: id,
  type: type,
  klass: klass,
  title: id,
  build: (context) => const SizedBox.shrink(),
);

Stage _stage({Rational? maxTabs, List<PlacementRule>? rules}) => Stage(
  rules: rules ?? defaultPlacementRules,
  tunable: (key) => switch (key) {
    'stage.maxTabs' => maxTabs ?? Rational.fromInt(6),
    _ => Rational.fromInt(1, 2),
  },
);

void main() {
  test('the first of a kind tiles and the second tabs with it', () {
    final stage = _stage()
      ..open(_spec('a'))
      ..open(_spec('b'));
    final parent = parentOf(stage.root, 'b');
    expect(parent?.mode, 'tabs');
    expect(parent?.children.map((child) => child.id), containsAll(['a', 'b']));
  });

  test('a different class splits rather than tabbing', () {
    final stage = _stage()
      ..open(_spec('a'))
      ..open(_spec('card', type: 'card', klass: 'eventEditor'));
    expect(parentOf(stage.root, 'card')?.mode, 'split');
  });

  test('maxTabs overflow falls through to the split rule', () {
    final stage = _stage(maxTabs: Rational.fromInt(2))
      ..open(_spec('a'))
      ..open(_spec('b'))
      ..open(_spec('c'));
    expect(parentOf(stage.root, 'c')?.mode, 'split');
    // The stack stopped growing: it still holds 'a' beside the page 'c' split
    // into, rather than taking a third tab.
    final tabs = parentOf(stage.root, 'a')!;
    expect(tabs.mode, 'tabs');
    expect(tabs.children.length, 2);
  });

  test('a rule whose predicate refuses to read does not place', () {
    final placement = evaluatePlacement(
      const [PlacementRule(action: 'tabWithNewest', predicate: '1 +')],
      tile: TileLeaf('x', type: 'view', klass: 'lens'),
      root: TileLeaf('a', type: 'view', klass: 'lens'),
      openOrder: const ['a'],
    );
    expect(placement, isNull);
  });

  test('a named container takes what is aimed into it', () {
    final stage = _stage(
      rules: const [PlacementRule(type: 'bar', action: 'into', container: 'chrome')],
    );
    stage.root = Branch(
      'root',
      mode: 'split',
      children: [
        Branch(
          'chrome',
          mode: 'split',
          axis: 'column',
          name: 'chrome',
          children: [
            TileLeaf('bar:one', type: 'bar', klass: 'documentBar'),
            TileLeaf('bar:two', type: 'bar', klass: 'viewBar'),
          ],
        ),
        TileLeaf('view:1', type: 'view', klass: 'lens'),
      ],
    );
    stage.open(_spec('bar:three', type: 'bar', klass: 'contextBar'));
    expect(containerNamed(stage.root, 'chrome')!.children.map((c) => c.id), contains('bar:three'));
  });

  test('opening a tile twice is idempotent and closes without a second copy', () {
    final stage = _stage()
      ..open(_spec('a'))
      ..open(_spec('a'));
    expect(leavesOf(stage.root).length, 1);
    stage.close('a');
    expect(stage.root, isNull);
    expect(stage.tiles, isEmpty);
  });

  /// A rule list as a file (or a settings key) carries it: terse, authored by
  /// hand, not the canonical form anything writes back.
  String said(List<Map<String, Object?>> rules) => jsonEncode(rules);

  test('the layout FILE is where placement lives: it answers over the settings key', () {
    final settings = chronologSettings();
    // The settings key says one thing...
    settings.setText(
      'stage.placement',
      said([
        {'action': 'splitFocused', 'axis': 'column'},
      ]),
    );
    final stage = Stage(settings: settings, tunable: settings.tunable);
    addTearDown(stage.dispose);
    // ...and then the file speaks, which is the road `bindSession` takes on
    // load and on every change the watcher sees.
    stage.applyJson({
      'rules': [
        {'action': 'tabWithNeighbor', 'direction': 'up'},
      ],
    });
    expect(
      stage.rules.map((rule) => rule.action).toList(),
      ['tabWithNeighbor'],
      reason:
          'ISSUES (9.1, Don): "file wins" — the layout file\'s placement section is the '
          'home, and the setting is a view of it rather than a rival source.',
    );
    expect(
      stage.rules.single.direction,
      'up',
      reason: 'and every term of the file\'s rule came through, not just its name',
    );
    expect(
      settings.text('stage.placement'),
      stage.placementSource,
      reason:
          'ISSUES (9.1): the app hot loads the file, so the key SAYS what the file says '
          'the moment the file speaks — otherwise the settings card shows a stale list.',
    );
  });

  test('writing the settings key edits the file: the section it writes is the one saved', () {
    final settings = chronologSettings();
    final stage = Stage(settings: settings, tunable: settings.tunable);
    addTearDown(stage.dispose);
    var saved = 0;
    stage.addListener(() => saved += 1);
    settings.setText(
      'stage.placement',
      said([
        {'action': 'tabWithNeighbor', 'direction': 'left'},
        {'action': 'splitFocused', 'axis': 'column'},
      ]),
    );
    expect(
      stage.rules.map((rule) => rule.action).toList(),
      ['tabWithNeighbor', 'splitFocused'],
      reason:
          'ISSUES (9.1, Don): "settings edits file" — writing the key is an edit of the '
          'layout file\'s placement section, not a second place rules can live.',
    );
    final written = stage.toJson()['rules']! as List;
    expect(
      [for (final rule in written) (rule as Map)['action']],
      ['tabWithNeighbor', 'splitFocused'],
      reason: 'and what the layout file is written FROM carries the edit',
    );
    expect(saved, greaterThan(0), reason: 'the stage said so, which is what saves the file');
    expect(
      settings.text('stage.placement'),
      stage.placementSource,
      reason:
          'the key settles on the file\'s canonical form, so a terse authored list comes '
          'back saying every term it actually places by',
    );
  });

  test('a rule list that will not read leaves the file standing, and the key says so', () {
    final settings = chronologSettings();
    final stage = Stage(settings: settings, tunable: settings.tunable);
    addTearDown(stage.dispose);
    final before = stage.placementSource;
    settings.setText('stage.placement', 'not a rule list at all');
    expect(
      stage.placementSource,
      before,
      reason: 'a half-read list would place tiles by a rule nobody wrote',
    );
    expect(
      settings.text('stage.placement'),
      before,
      reason: 'and a key silently disagreeing with the file is the drift this prevents',
    );
  });

  test('the shipped rule list is the shipped authored source, parsed', () {
    final settings = chronologSettings();
    final stage = Stage(settings: settings, tunable: settings.tunable);
    addTearDown(stage.dispose);
    expect(
      stage.rules.map((rule) => rule.toJson()).toList(),
      rulesFromSource(defaultPlacementSource).map((rule) => rule.toJson()).toList(),
      reason: 'the default and the authored form are one list, so they cannot drift',
    );
    expect(rulesFromSource(defaultPlacementSource), isNotEmpty, reason: 'and it reads');
  });

  test('presets round-trip and re-host live tiles', () {
    final stage = _stage()
      ..open(_spec('a'))
      ..open(_spec('card', type: 'card', klass: 'eventEditor'))
      ..savePreset('default');
    final written = stage.toJson();
    final other = _stage()
      ..open(_spec('a'))
      ..open(_spec('card', type: 'card', klass: 'eventEditor'))
      ..applyJson(written);
    expect(other.presets.keys, contains('default'));
    other.applyPreset('default');
    expect(leavesOf(other.root).map((leaf) => leaf.id).toSet(), {'a', 'card'});
  });
}
