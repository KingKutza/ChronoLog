// Every tunable in the program, as a named setting whose shipped default is an
// expression in the one math. No surface carries a pixel size, a duration, a
// threshold or a snap point as a literal; it names a setting and reads it here.
//
// Two vocabularies, deliberately separate: TUNABLES evaluate through
// `lib/core/math.dart` and answer as exact numbers or truth values; TEXT
// settings are strings that are not arithmetic -- a key binding, a theme name.
// Reading `keys.undo` as algebra would be a category error.
//
// A refused expression never takes effect: the last good value stays and the
// refusal is reported in the law's own vocabulary.

import 'package:flutter/foundation.dart';

import '../core/exact.dart';
import '../core/math.dart';
import '../lens/tunables.dart';

class Settings extends ChangeNotifier {
  Settings({
    List<Map<String, String>> defaults = const [],
    List<Map<String, String>> texts = const [],
  }) {
    for (final map in defaults) {
      shipped.addAll(map);
    }
    for (final map in texts) {
      shippedText.addAll(map);
    }
  }

  final Map<String, String> shipped = {};
  final Map<String, String> shippedText = {};
  final Map<String, String> _overrides = {};
  final Map<String, String> _textOverrides = {};
  final Map<String, Object> _memo = {};

  /// What the last read of the settings file, or the last rejected edit, had
  /// to refuse. Reported, never fatal.
  final List<String> refusals = [];

  Iterable<String> get keys => shipped.keys;

  String expressionOf(String key) => _overrides[key] ?? shipped[key] ?? '';

  /// The evaluated value: a [Rational] or a [bool]. Memoized, and the whole
  /// memo drops on any change -- a settings edit is rare and a stale tunable
  /// is a lie.
  Object? raw(String key) {
    final known = _memo[key];
    if (known != null) return known;
    final source = expressionOf(key);
    if (source.trim().isEmpty) {
      _note('No setting named $key.');
      return null;
    }
    try {
      return _memo[key] = evaluateSource(source, const Env());
    } on MathRefusal catch (refusal) {
      _note('$key: $refusal');
      return null;
    }
  }

  /// A truth value reads as zero or one, so one accessor serves every tunable.
  Rational value(String key) => switch (raw(key)) {
    final Rational number => number,
    true => Rational.one,
    _ => Rational.zero,
  };

  bool flag(String key) => switch (raw(key)) {
    final bool truth => truth,
    final Rational number => !number.isZero,
    _ => false,
  };

  Tunable get tunable => value;

  /// Every setting under a dotted prefix, in key order. The one math has no
  /// lists, so a list of snap points is a family of keys (`stage.snap.1`..)
  /// rather than a list literal hiding in a string.
  List<Rational> series(String prefix) {
    final names = keys.where((key) => key.startsWith(prefix)).toList()..sort();
    return [for (final name in names) value(name)];
  }

  String text(String key) => _textOverrides[key] ?? shippedText[key] ?? '';

  /// Accepts and returns null, or refuses and returns the reason. Validation
  /// is the evaluation itself: an expression that will not read is not stored.
  String? set(String key, String expression) {
    try {
      evaluateSource(expression, const Env());
    } on MathRefusal catch (refusal) {
      return '$refusal';
    }
    _overrides[key] = expression;
    _invalidate();
    return null;
  }

  void setText(String key, String value) {
    _textOverrides[key] = value;
    _invalidate();
  }

  void reset(String key) {
    _overrides.remove(key);
    _textOverrides.remove(key);
    _invalidate();
  }

  /// Only what the user authored: the file records overrides, never the
  /// shipped defaults, so a default that changes reaches an existing install.
  Map<String, Object?> toJson() => {..._overrides, ..._textOverrides};

  /// Reads the settings file. Every key is taken on its own: one refusal costs
  /// that key and nothing else.
  void applyJson(Map<String, Object?> source) {
    refusals.clear();
    _overrides.clear();
    _textOverrides.clear();
    for (final entry in source.entries) {
      final written = '${entry.value}';
      if (shippedText.containsKey(entry.key)) {
        _textOverrides[entry.key] = written;
        continue;
      }
      final refused = set(entry.key, written);
      if (refused != null) _note('${entry.key}: $refused');
    }
    _invalidate();
  }

  void _note(String message) {
    if (!refusals.contains(message)) refusals.add(message);
  }

  void _invalidate() {
    _memo.clear();
    notifyListeners();
  }
}
