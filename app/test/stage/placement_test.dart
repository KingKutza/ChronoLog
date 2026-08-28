// Placement rules: same kind tabs together, different kinds split, and an
// overflowing tab container falls through to the next rule.

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
