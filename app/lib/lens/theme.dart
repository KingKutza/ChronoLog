// The 8-field palette (AGENTS.md "Visual grammar") as one Flutter theme
// extension, plus the two font roles.
//
// ONE SOURCE. The palette lived twice in the web build -- `:root` in app.css and
// `THEME_PRESETS` in visual-language.js -- and two sources for one palette can
// only ever disagree. This file is the source; a theme file on disk is the same
// eight fields as JSON.
//
// DERIVED, NOT PICKED. faint / hair / strong are the muted ink mixed toward
// paper by one rule at three strengths, so a new palette needs eight colors and
// gets eleven. Hand-picking three greys per theme is how a night palette ends up
// with hairlines that read at a different weight than the day one's.
//
// A MAP, NOT EIGHT FIELDS, so adding a ninth role is a name in a list rather
// than nine edits across a constructor, a copy, a lerp and two codecs.
//
// Selection is an INK RING, never a color: color already carries authored frame
// and group meaning and must not be overloaded.

import 'package:flutter/material.dart';

/// The mixes that derive the three tones from muted ink toward paper. Muted's
/// own share, so a larger number is a darker tone.
const double _faint = 0.68, _strong = 0.62, _hair = 0.38;

/// The authored roles, in the order a theme editor shows them.
const List<String> themeFields = [
  'ground',
  'surface',
  'paper',
  'ink',
  'muted',
  'primary',
  'secondary',
  'accent',
];

/// The chrome font role and the DATA font role. Every coordinate, label, count
/// and time is monospace; everything a person reads as prose is not.
const List<String> uiFontFallback = ['Avenir Next', 'Segoe UI', 'system-ui'];
const List<String> dataFontFallback = ['SF Mono', 'Menlo', 'Consolas', 'monospace'];

class ChronoTheme extends ThemeExtension<ChronoTheme> {
  const ChronoTheme(this.name, this.palette);

  /// Reads a theme file. A field that is not a six-digit hex colour falls back
  /// to the paper preset's rather than refusing the whole file: a theme is
  /// authored by hand and one bad line must not cost the other seven.
  factory ChronoTheme.fromJson(Map<String, Object?> json) =>
      ChronoTheme(json['name'] is String ? json['name']! as String : 'paper', {
        for (final field in themeFields)
          field: parseColor(json[field]) ?? parseColor(paperPreset[field])!,
      });

  final String name;
  final Map<String, Color> palette;

  Color _at(String field) => palette[field] ?? const Color(0xff000000);

  Color get ground => _at('ground');
  Color get surface => _at('surface');
  Color get paper => _at('paper');
  Color get ink => _at('ink');
  Color get muted => _at('muted');
  Color get primary => _at('primary');
  Color get secondary => _at('secondary');
  Color get accent => _at('accent');

  /// The three derived tones: the tone a secondary mark carries, the hairline,
  /// and the palest rule.
  Color get faint => Color.lerp(paper, muted, _faint)!;
  Color get hair => Color.lerp(paper, muted, _hair)!;
  Color get strong => Color.lerp(paper, muted, _strong)!;

  /// Neutral ink: what a mark is drawn in when NOTHING is authored. Meaning is
  /// authored, so an unauthored object gets no color, not an inferred one.
  Color get neutral => ink;

  TextStyle get ui => TextStyle(color: ink, fontFamilyFallback: uiFontFallback);

  TextStyle get data =>
      TextStyle(color: ink, fontFamily: 'monospace', fontFamilyFallback: dataFontFallback);

  Map<String, Object?> toJson() => {
    'name': name,
    for (final field in themeFields) field: hexOf(_at(field)),
  };

  @override
  ChronoTheme copyWith({String? name, Map<String, Color>? palette}) =>
      ChronoTheme(name ?? this.name, {...this.palette, ...?palette});

  @override
  ChronoTheme lerp(ThemeExtension<ChronoTheme>? other, double t) => other is! ChronoTheme
      ? this
      : ChronoTheme(t < 1 / 2 ? name : other.name, {
          for (final field in themeFields) field: Color.lerp(_at(field), other._at(field), t)!,
        });

  /// The theme in force, or the paper preset for a surface built without one (a
  /// bare widget test, a thumbnail) rather than a null dereference.
  static ChronoTheme of(BuildContext context) =>
      Theme.of(context).extension<ChronoTheme>() ?? shipped['paper']!;
}

/// Warm paper and ink: the concept image's own ground, adopted as the default.
const Map<String, Object?> paperPreset = {
  'name': 'paper',
  'ground': '#ece5d8',
  'surface': '#f7f1e6',
  'paper': '#fffdf7',
  'ink': '#2a2620',
  'muted': '#716657',
  'primary': '#b33b27',
  'secondary': '#2e8b57',
  'accent': '#497bc1',
};

/// The dark cockpit, from the JavaFX scaffold's own palette.
const Map<String, Object?> nightPreset = {
  'name': 'night',
  'ground': '#10131a',
  'surface': '#171b25',
  'paper': '#202735',
  'ink': '#f7f3e8',
  'muted': '#b9b2a6',
  'primary': '#ff8a66',
  'secondary': '#45f0ae',
  'accent': '#d889ff',
};

const Map<String, Map<String, Object?>> shippedPresets = {
  'paper': paperPreset,
  'night': nightPreset,
};

final Map<String, ChronoTheme> shipped = {
  for (final entry in shippedPresets.entries) entry.key: ChronoTheme.fromJson(entry.value),
};

final RegExp _hexPattern = RegExp(r'^#?([0-9a-fA-F]{6})$');

Color? parseColor(Object? value) {
  final match = _hexPattern.firstMatch('${value ?? ''}'.trim());
  return match == null ? null : Color(0xff000000 | int.parse(match[1]!, radix: 16));
}

String hexOf(Color color) {
  String part(double channel) =>
      (channel * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  return '#${part(color.r)}${part(color.g)}${part(color.b)}';
}

/// A Flutter theme carrying one [ChronoTheme]. The stage builds its own
/// `ThemeData`; this is the one place the extension is attached, so no surface
/// has to remember to.
ThemeData themeDataFor(ChronoTheme theme) => ThemeData(
  brightness: theme.ink.computeLuminance() > theme.paper.computeLuminance()
      ? Brightness.dark
      : Brightness.light,
  scaffoldBackgroundColor: theme.ground,
  extensions: [theme],
);
