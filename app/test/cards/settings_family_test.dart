// THE SETTINGS FAMILY (ISSUES 9.1, Don's ruling on the settings surface).
//
// "The settings card is a long list of barely-labeled literals -- I don't have
// the first Idea how to navigate or use that." The ruling that answers it has
// four claims a spec can ask about, and every one of them is asked here over
// the WHOLE composed key set rather than over a remembered handful:
//
//   * every key says in words what it does and where it acts, with no key ever
//     shown as its own dotted name;
//   * every key lands on exactly one card of the family, so none can hide;
//   * every sub-card carries a button back, and the main card a launcher out;
//   * the range a control draws is a guide rail and never a bound.

import 'dart:math';

import 'package:chronolog/cards/settings_card.dart';
import 'package:chronolog/cards/settings_vocabulary.dart';
import 'package:chronolog/cards/settings_words.dart';
import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/session/settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/corpus.dart';
import 'harness.dart';
import 'object_harness.dart';

List<String> composedKeys(Settings settings) =>
    [...{...settings.keys, ...settings.shippedText.keys}]..sort();

void main() {
  final settings = chronologSettings();
  final keys = composedKeys(settings);

  test('every setting the program composes is said in plain words', () {
    final unsaid = [
      for (final key in keys)
        if (settingSaidOf(key) == null) key,
    ];
    expect(
      unsaid,
      isEmpty,
      reason:
          'ISSUES (9.1): "settings wording is FULL coverage, every key labeled and '
          'explained in plain language". These keys say nothing about themselves.',
    );
    for (final key in keys) {
      final said = settingSaidOf(key)!;
      expect(said.label.trim(), isNotEmpty, reason: key);
      expect(said.says.trim(), isNotEmpty, reason: '$key has a label and no explanation');
      // A key is never shown as its own dotted name, and a label is a phrase
      // rather than a sentence about one.
      expect(said.label, isNot(contains('.')), reason: key);
      expect(said.label[0], said.label[0].toUpperCase(), reason: key);
      expect(settingLabel(key), said.label, reason: key);
      expect(settingSays(key), said.says, reason: key);
    }
  });

  test('every key lands on exactly one card of the family', () {
    final family = settingsSubCards(keys);
    final housed = <String, List<String>>{};
    for (final card in family) {
      for (final area in card.areas) {
        housed.putIfAbsent(area, () => []).add(card.title);
      }
    }
    for (final key in keys) {
      final area = key.split('.').first;
      expect(
        housed[area],
        hasLength(1),
        reason:
            'ISSUES (9.1): the sub-cards are cut by the surfaces they govern. "$area" is '
            'governed by ${housed[area] ?? 'nothing'}.',
      );
    }
    // The cut is a shape, not a literal: what the test asks is that every card
    // governs something and nothing is governed twice.
    for (final card in family) {
      expect(card.areas, isNotEmpty, reason: '${card.title} governs nothing');
      expect(
        keys.any((key) => card.areas.contains(key.split('.').first)),
        isTrue,
        reason: '${card.title} governs areas no composed key belongs to',
      );
    }
  });

  test('the general settings the front card holds are keys the program ships', () {
    final general = [
      for (final word in settings.text('settings.general').split(RegExp(r'\s+')))
        if (word.trim().isNotEmpty) word.trim(),
    ];
    expect(general, isNotEmpty, reason: 'the front card holds nothing');
    for (final key in general) {
      expect(
        keys,
        contains(key),
        reason: 'settings.general names "$key" and no defaults map ships one',
      );
    }
  });

  // A GUIDE RAIL, NEVER A BOUND (ISSUES 9.1). Generated: for any key that
  // states a range, a value pushed well outside it is stored exactly as
  // written, and the stated range does not move to accommodate it.
  test('a stated range never clamps what may be written', () {
    final railed = [
      for (final key in keys)
        if (settingRail(key) != null) key,
    ];
    expect(railed, isNotEmpty, reason: 'no key states a range, so this proves nothing');
    for (final seed in seeds(8)) {
      final random = Random(seed);
      final fresh = chronologSettings();
      final key = railed[random.nextInt(railed.length)];
      final rail = settingRail(key)!;
      final beyond = rail.high * Rational.fromInt(2 + random.nextInt(20));
      expect(fresh.set(key, beyond.toJson()), isNull, reason: '$key refused $beyond');
      expect(fresh.value(key), beyond, reason: '$key was clamped to its rail');
      expect(settingRail(key), rail, reason: '$key moved its own advisory range');
    }
  });

  testWidgets('the front card launches the family, and a sub-card comes back', (tester) async {
    // Doors need a host to open into, so the card is pumped in the one a tile
    // really gives it.
    final bench = await openCards(createEmptyWorkspaceDocument());
    final family = settingsSubCards(keys);
    await pumpHosted(tester, bench, const SettingsCard(), klass: 'settings', shell: true);
    for (final card in family) {
      expect(
        find.text(card.title),
        findsWidgets,
        reason:
            'ISSUES (9.1): "the main settings card carries the top most GENERAL settings '
            'and a button per sub-card". Nothing on it opens ${card.title}.',
      );
    }
    for (final card in family) {
      await pumpHosted(
        tester,
        bench,
        SettingsCard(area: card.address),
        klass: 'settings',
        kind: card.address,
        shell: true,
      );
      expect(
        find.text('All settings'),
        findsOneWidget,
        reason:
            'ISSUES (9.1): "every sub-card carries a button back to the main settings '
            'card". ${card.title} does not.',
      );
      expect(tester.takeException(), isNull, reason: '${card.title} renders');
    }
  });

  testWidgets('a sub-card shows the settings of the surface it governs, in words', (tester) async {
    final bench = await openCards(createEmptyWorkspaceDocument());
    final family = settingsSubCards(keys);
    for (final card in family) {
      await pumpHosted(
        tester,
        bench,
        SettingsCard(area: card.address),
        klass: 'settings',
        kind: card.address,
        shell: true,
      );
      final mine = [
        for (final key in keys)
          if (card.areas.contains(key.split('.').first)) key,
      ];
      // Its own keys read in words; no key is shown as its own dotted name
      // until the expression is asked for.
      expect(find.text(settingLabel(mine.first)), findsWidgets, reason: card.title);
      expect(find.text(mine.first), findsNothing, reason: 'the dotted key is the arcanum');
    }
  });

  testWidgets('find matches the words, not just the dotted key', (tester) async {
    final bench = await openCards(createEmptyWorkspaceDocument());
    await pumpHosted(tester, bench, const SettingsCard(), klass: 'settings', shell: true);
    // A word that appears in an explanation and in no key name at all.
    const said = 'undoable';
    expect(
      keys.any((key) => key.toLowerCase().contains(said)),
      isFalse,
      reason: 'the needle has to be a word rather than a key fragment',
    );
    final wanted = [
      for (final key in keys)
        if (settingSays(key).toLowerCase().contains(said)) key,
    ];
    expect(wanted, isNotEmpty, reason: 'nothing says it, so this proves nothing');
    await tester.enterText(fieldHinted('Find a setting'), said);
    await tester.pumpAndSettle();
    for (final key in wanted) {
      expect(
        find.text(settingLabel(key)),
        findsWidgets,
        reason:
            'ISSUES (9.1): "find that matches the words, not just the dotted keys" — '
            '$key says it and the find does not offer it.',
      );
    }
  });

  test('a settings area no card governs falls back to the main card, and says so', () {
    final fresh = chronologSettings();
    final family = settingsSubCards(composedKeys(fresh));
    const nowhere = 'nosuchsurface';
    expect(family.any((card) => card.address == nowhere), isFalse);
    // The vocabulary is the arbiter of what a card is CALLED, and it refuses to
    // invent a name for a surface nothing governs.
    expect(settingAreaNames.containsKey(nowhere), isFalse);
    expect(settingsCardTitle(nowhere), nowhere);
  });

  test('the words are melted, not copied: one sentence covers a family', () {
    // Every promotion threshold in the program says the same thing about a
    // different surface. If they were copied, one of them could drift.
    final promoting = [
      for (final key in keys)
        if (key.endsWith('.importantAt')) key,
    ];
    expect(promoting.length, greaterThan(1));
    for (final key in promoting) {
      expect(settingVocabulary.containsKey(key), isFalse, reason: '$key is a copy of the family');
      expect(settingLabel(key), settingLabel(promoting.first));
    }
    // One sentence is not a vaguer sentence: it names the surface it is about,
    // so the surfaces still read apart.
    expect(
      {for (final key in promoting) settingSays(key)}.length,
      greaterThan(1),
      reason: 'the family says the same thing about every surface without naming any',
    );
  });
}
