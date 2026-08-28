// Settings: the override wins, a refused expression keeps the last good value
// and reports, and a family of keys stands in for the list the math has not got.

import 'package:chronolog/chrome/controls.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/math.dart';
import 'package:chronolog/session/settings.dart';
import 'package:chronolog/stage/stage_widget.dart';
import 'package:flutter_test/flutter_test.dart';

Settings _settings() => Settings(
  defaults: const [chromeTunableDefaults, stageTunableDefaults],
  texts: const [chromeTextDefaults, stageTextDefaults],
);

void main() {
  /// What a shipped expression comes to, read the way the settings layer reads
  /// it. Pinning the NUMBER here would only assert what the map already says,
  /// and would break every time a default is re-tuned.
  Rational shipped(String key) =>
      switch (evaluateSource(_settings().expressionOf(key), const Env())) {
        final Rational number => number,
        final Object? other => throw StateError('$key is $other, not a number'),
      };

  test('a shipped default reads through the one math', () {
    expect(_settings().value('chrome.gap'), shipped('chrome.gap'));
    expect(_settings().value('stage.divider'), shipped('stage.divider'));
    // The chrome rhythm is one unit: every spacing is a multiple of it.
    final unit = _settings().value('chrome.unit');
    for (final key in const ['chrome.gap', 'chrome.pad', 'chrome.barHeight', 'chrome.rowHeight']) {
      expect(shipped(key) % unit, Rational.zero, reason: '$key is off the grid');
    }
  });

  test('an override wins over the default and a reset gives it back', () {
    final settings = _settings();
    expect(settings.set('chrome.gap', '3 * 4'), isNull);
    expect(settings.value('chrome.gap'), Rational.fromInt(12));
    settings.reset('chrome.gap');
    expect(settings.value('chrome.gap'), Rational.fromInt(6));
  });

  test('a refused expression keeps the last good value and says why', () {
    final settings = _settings();
    settings.set('chrome.gap', '9');
    final refusal = settings.set('chrome.gap', '1 +');
    expect(refusal, isNotNull);
    expect(settings.value('chrome.gap'), Rational.fromInt(9));
  });

  test('a bad key in the file costs that key and nothing else', () {
    final settings = _settings();
    settings.applyJson({'chrome.gap': '4', 'chrome.pad': ')('});
    expect(settings.value('chrome.gap'), Rational.fromInt(4));
    expect(settings.value('chrome.pad'), shipped('chrome.pad'));
    expect(settings.refusals, isNotEmpty);
  });

  test('only overrides are written, so a changed default reaches an install', () {
    final settings = _settings();
    settings.set('chrome.gap', '4');
    expect(settings.toJson().keys, ['chrome.gap']);
  });

  test('a family of keys stands in for a list, in key order', () {
    final settings = Settings(
      defaults: const [
        {'rung.1': '1/8', 'rung.2': '1/4', 'rung.3': '1/2'},
      ],
    );
    final rungs = settings.series('rung.');
    expect(rungs.length, 3);
    for (var index = 1; index < rungs.length; index++) {
      expect(rungs[index] > rungs[index - 1], isTrue, reason: 'a family reads in key order');
    }
  });

  test('the stage ships no snap ladder: a divider lands where it was let go', () {
    final settings = _settings();
    expect(settings.series('stage.snap.'), isEmpty, reason: 'snapping is opt-in, not shipped');
    expect(settings.text('stage.snapTo'), 'ratio', reason: 'the shipped snap is the identity');
  });

  test('a truth value reads as a flag and as zero or one', () {
    final settings = Settings(
      defaults: const [
        {'a.flag': 'true'},
      ],
    );
    expect(settings.flag('a.flag'), isTrue);
    expect(settings.value('a.flag'), Rational.one);
    expect(settings.set('a.flag', 'false'), isNull);
    expect(settings.flag('a.flag'), isFalse);
  });

  test('a key nothing declares refuses rather than answering zero silently', () {
    final settings = _settings();
    expect(settings.raw('nothing.here'), isNull);
    expect(settings.refusals.any((message) => message.contains('nothing.here')), isTrue);
  });

  test('a key binding is text, never arithmetic', () {
    final settings = _settings();
    expect(settings.text('theme.name'), 'paper');
    settings.applyJson({'theme.name': 'night'});
    expect(settings.text('theme.name'), 'night');
    expect(settings.refusals, isEmpty);
  });
}
