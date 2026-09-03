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

import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../core/exact.dart';
import '../core/math.dart';
import '../lens/tunables.dart';

/// A notifier that can be told something DURING a frame.
///
/// A change authored from inside a build -- a card reading a setting that
/// refuses, an edit committed while a widget is laying out -- would mark its own
/// listeners dirty in the middle of the frame, which Flutter refuses outright.
/// The FACT is already true; only the repaint waits for the frame to end.
/// Outside a frame, and in a run with no binding at all, this is an ordinary
/// synchronous notification.
///
/// ONE implementation for every notifier in the program that a build can reach:
/// the settings layer and the edit service both wear it.
mixin FrameSafeNotifier on ChangeNotifier {
  bool _announcing = false;

  @override
  void notifyListeners() {
    if (_phase() != SchedulerPhase.persistentCallbacks) return super.notifyListeners();
    if (_announcing) return;
    _announcing = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _announcing = false;
      if (hasListeners) super.notifyListeners();
    });
  }

  static SchedulerPhase? _phase() {
    try {
      return SchedulerBinding.instance.schedulerPhase;
    } on Object {
      return null;
    }
  }
}

/// A list that ANNOUNCES. A refusal is news, so it has to arrive like news: the
/// cards that display refusals update the moment one is pushed rather than on
/// whatever rebuild happens to come next.
///
/// Every mutation route goes through [length] and `[]=`, which is what
/// [ListBase] builds `add`, `addAll`, `clear` and the rest out of, so no caller
/// can write into it unheard.
class AnnouncedList<T> extends ListBase<T> {
  AnnouncedList(this.onChanged);

  final void Function() onChanged;
  final List<T> _lines = [];

  @override
  int get length => _lines.length;

  @override
  set length(int value) {
    _lines.length = value;
    onChanged();
  }

  @override
  T operator [](int index) => _lines[index];

  @override
  void operator []=(int index, T value) {
    _lines[index] = value;
    onChanged();
  }

  @override
  void add(T element) {
    _lines.add(element);
    onChanged();
  }
}

class Settings extends ChangeNotifier with FrameSafeNotifier {
  Settings({
    List<Map<String, String>> defaults = const [],
    List<Map<String, String>> texts = const [],
    this.exclusive = const [],
  }) {
    for (final map in defaults) {
      shipped.addAll(map);
    }
    for (final map in texts) {
      shippedText.addAll(map);
    }
    _findConflicts();
  }

  /// The families in which no two keys may say the same thing, by prefix.
  ///
  /// TWO BINDINGS ON ONE CHORD IS A REFUSAL, NEVER A LAST-WINS (ISSUES 9.2, the
  /// keybindings page): "a conflict is a refusal shown beside both rows". This
  /// layer knows nothing about what a chord means -- it knows only that within
  /// these families a value is a CLAIM, and two claims on one value is a thing
  /// nobody can have meant. Which families are exclusive is the shell's
  /// statement, so the rule is a shape rather than a special case for keys.
  final List<String> exclusive;

  final Map<String, String> shipped = {};
  final Map<String, String> shippedText = {};
  final Map<String, String> _overrides = {};
  final Map<String, String> _textOverrides = {};
  final Map<String, Object> _memo = {};

  /// What the last read of the settings file, or the last rejected edit, had
  /// to refuse. Reported, never fatal -- and ANNOUNCED, so a card showing a
  /// refusal shows it the instant it is pushed and not on its next rebuild.
  late final List<String> refusals = AnnouncedList<String>(notifyListeners);

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

  /// WHAT IS AUTHORED ON THIS KEY, or null where nothing is.
  ///
  /// The file records only overrides, so the absence of one is a real state and
  /// not the shipped value written down: a changed shipped default must still
  /// reach an install that never touched the key. Undo needs to be able to
  /// restore that absence, so it needs to be able to read it.
  String? overrideOf(String key) => _overrides[key] ?? _textOverrides[key];

  /// Which vocabulary a key belongs to: a tunable is arithmetic, a text setting
  /// is a chord or a name and reading it as algebra would be a category error.
  bool isText(String key) => shippedText.containsKey(key);

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

  /// RESET A WHOLE PAGE (ISSUES 9.2, Don: the keybindings page "must allow
  /// resetting"). Every override under any of [prefixes] goes; a shipped
  /// default was never an override, so nothing here can delete authorship it
  /// did not find. It is one act and it announces once, because a page of
  /// twenty-three chords going back is one thing the person did.
  ///
  /// Returns the keys that actually had something authored on them, so the
  /// surface can say what it undid rather than claiming work it did not do.
  List<String> resetUnder(Iterable<String> prefixes) {
    final gone = [
      for (final key in {..._overrides.keys, ..._textOverrides.keys})
        if (prefixes.any(key.startsWith)) key,
    ]..sort();
    for (final key in gone) {
      _overrides.remove(key);
      _textOverrides.remove(key);
    }
    if (gone.isNotEmpty) _invalidate();
    return gone;
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

  /// Every conflict this layer has said, so a resolved one goes away.
  ///
  /// Recomputed WHOLE on every change rather than patched: a stale refusal
  /// beside a binding somebody already moved is worse than none, and there is
  /// no cheaper honest answer for "who else says this now".
  final Set<String> _conflicts = {};

  void _findConflicts() {
    if (_conflicts.isNotEmpty) {
      final stale = {..._conflicts};
      _conflicts.clear();
      refusals.removeWhere(stale.contains);
    }
    for (final family in exclusive) {
      final claims = <String, List<String>>{};
      for (final key in shippedText.keys) {
        if (!key.startsWith(family)) continue;
        final said = text(key).trim();
        // AN EMPTY BINDING IS A BINDING TURNED OFF, and two things switched off
        // are not two things fighting over one chord.
        if (said.isEmpty) continue;
        claims.putIfAbsent(said, () => []).add(key);
      }
      for (final entry in claims.entries) {
        if (entry.value.length < 2) continue;
        // ONE LINE PER KEY, each naming the others: a refusal is shown beside
        // the row whose name it starts with, so a conflict said once would be
        // said beside one of the two bindings and hidden beside the other.
        for (final key in entry.value) {
          final others = entry.value.where((other) => other != key).join(', ');
          final line =
              '$key: "${entry.key}" is also what $others says. Two bindings on one '
              'chord: neither acts until one of them is written differently.';
          _conflicts.add(line);
          _note(line);
        }
      }
    }
  }

  /// Is this key's binding contested? A contested binding ACTS FOR NOBODY --
  /// the dispatcher binds neither, because picking one would be the last-wins
  /// the refusal exists to refuse.
  bool contested(String key) => _conflicts.any((line) => line.startsWith('$key:'));

  /// A BINDING, AS THE SURFACES READ IT. Exactly [text], except that a
  /// contested one reads as nothing at all -- which is the same thing an empty
  /// binding says, and it is said in one place rather than at every dispatcher
  /// that might otherwise pick a winner of its own.
  String binding(String key) => contested(key) ? '' : text(key);

  void _invalidate() {
    _memo.clear();
    _findConflicts();
    notifyListeners();
  }
}
