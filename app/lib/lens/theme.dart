// The 8-field palette (AGENTS.md "Visual grammar") as one Flutter theme
// extension, plus the two font roles.
//
// ONE SOURCE. The palette lived twice in the web build -- `:root` in app.css and
// `THEME_PRESETS` in visual-language.js -- and two sources for one palette can
// only ever disagree. This file is the source; a theme file on disk is the same
// eight fields as JSON.
//
// DERIVED, NOT PICKED, AND AT EQUAL WEIGHT IN BOTH DIRECTIONS. hair / strong /
// faint are paper carried toward ink until each reaches its own CONTRAST RATIO,
// not a fixed mix: a fixed mix on a light ground and the same mix on a dark one
// give lines the eye reads at three times the weight apart, which is exactly how
// a night palette ends up with hairlines that shout. A ratio is what the eye
// measures, so one number describes both themes.
//
// A MAP, NOT EIGHT FIELDS, so adding a ninth role is a name in a list rather
// than nine edits across a constructor, a copy, a lerp and two codecs.
//
// Selection is an INK RING, never a color: color already carries authored frame
// and group meaning and must not be overloaded.

import 'package:flutter/material.dart';

/// The contrast each derived tone holds against paper, as the ratio the eye
/// measures (WCAG's `(L+0.05)` form). A hairline is barely there, secondary
/// text is comfortably readable, and faint is nearly ink.
const double _hairRatio = 1.24, _strongRatio = 4.8, _faintRatio = 8.5;

/// Paper carried toward [toward] until it holds [ratio] against paper. Solved
/// rather than mixed: luminance is not linear in the mix, so the ratio is found
/// by bisection -- ten steps, exact to a thousandth of the way.
Color _atRatio(Color paper, Color toward, double ratio) {
  double contrast(Color of) {
    final (low, high) = (paper.computeLuminance(), of.computeLuminance());
    return low > high ? (low + 0.05) / (high + 0.05) : (high + 0.05) / (low + 0.05);
  }

  if (contrast(toward) <= ratio) return toward;
  var (low, high) = (0.0, 1.0);
  for (var step = 0; step < 10; step += 1) {
    final middle = (low + high) / 2;
    if (contrast(Color.lerp(paper, toward, middle)!) < ratio) {
      low = middle;
    } else {
      high = middle;
    }
  }
  return Color.lerp(paper, toward, (low + high) / 2)!;
}

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

/// The chrome font role and the DATA font role. A coordinate, a count and a
/// time are monospace with TABULAR figures, so a column of numbers lines up;
/// everything a person reads as prose -- a title, a label, a button -- is the
/// humanist sans, and a control that wore the data face because it was quicker
/// is the instance this pair exists to kill.
///
/// Both are host faces, named widest-first per platform. Bundling a family is
/// an asset, not a plugin, and remains open; nothing here needs one to read.
const List<String> uiFontFallback = [
  'Segoe UI Variable Text',
  'Segoe UI',
  'Inter',
  'Noto Sans',
  'DejaVu Sans',
  'Roboto',
];
const List<String> dataFontFallback = [
  'Cascadia Mono',
  'Consolas',
  'SF Mono',
  'Menlo',
  'DejaVu Sans Mono',
  'Roboto Mono',
  'monospace',
];

/// Set once, here: prose breathes at a line and a quarter, data sits tighter
/// because a coordinate is read as one token, and figures are tabular.
const double uiHeight = 1.28, dataHeight = 1.2;

class ChronoTheme extends ThemeExtension<ChronoTheme> {
  ChronoTheme(this.name, this.palette);

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

  /// The three derived tones, each at its own contrast against paper: the
  /// hairline every seam and border is drawn in, the tone secondary text
  /// carries, and the near-ink one.
  late final Color hair = _atRatio(paper, ink, _hairRatio);
  late final Color strong = _atRatio(paper, ink, _strongRatio);
  late final Color faint = _atRatio(paper, ink, _faintRatio);

  /// Neutral ink: what a mark is drawn in when NOTHING is authored. Meaning is
  /// authored, so an unauthored object gets no colour, not an inferred one --
  /// but the neutral is the MUTED ink rather than the full one, because a black
  /// bar is a statement of its own and an unauthored object is making none.
  Color get neutral => muted;

  TextStyle get ui => TextStyle(color: ink, height: uiHeight, fontFamilyFallback: uiFontFallback);

  TextStyle get data => TextStyle(
    color: ink,
    height: dataHeight,
    fontFamilyFallback: dataFontFallback,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

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

/// Warm paper and ink, from the concept image's own ground.
///
/// THE THREE SURFACES ARE ELEVATION, not decoration: `ground` is the desk the
/// stage sits on and shows between tiles, `surface` is what chrome is made of
/// -- bars, strips, controls -- and `paper` is the sheet a lens or a card is
/// drawn on. Three tones a shade apart is what makes a tiling window manager
/// read as arranged rather than as one flat wall with lines ruled on it.
const Map<String, Object?> paperPreset = {
  'name': 'paper',
  'ground': '#ded4c1',
  'surface': '#f1eade',
  'paper': '#fdfaf3',
  // Warm near-black, never #000: the concept image's ink is brown-black and
  // reads as written rather than as printed by a machine.
  'ink': '#33302a',
  'muted': '#6f6759',
  'primary': '#b5452c',
  'secondary': '#2f7a58',
  'accent': '#3f6ea3',
};

/// The dark ground of the origin photograph: luminous lines on near-black, at
/// the saturation a screen can hold all day.
///
/// NOT WHITE ON BLACK (Don, 2026-08-28): "white on black is good for high
/// contrast but not for a pretty GUI." Ink is a warm off-white a step down from
/// paper-white, and the three accents are the photograph's orange, green and
/// violet pulled back from neon -- distinguishable from each other and from the
/// ground without any of them glaring.
const Map<String, Object?> nightPreset = {
  'name': 'night',
  'ground': '#12141a',
  'surface': '#1b1f28',
  'paper': '#232834',
  'ink': '#e2dccf',
  'muted': '#8f8879',
  'primary': '#e8825c',
  'secondary': '#59c295',
  'accent': '#a98ce0',
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
ThemeData themeDataFor(ChronoTheme theme) {
  final dark = theme.ink.computeLuminance() > theme.paper.computeLuminance();
  return ThemeData(
    brightness: dark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: theme.ground,
    // Material's own defaults are the blue-and-ripple look nobody here asked
    // for. The palette answers for every one of them, so no widget in the tree
    // paints a colour this file has not authored.
    colorScheme: ColorScheme(
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: theme.primary,
      onPrimary: theme.paper,
      secondary: theme.secondary,
      onSecondary: theme.paper,
      error: theme.primary,
      onError: theme.paper,
      surface: theme.surface,
      onSurface: theme.ink,
    ),
    canvasColor: theme.paper,
    dividerColor: theme.hair,
    // A ripple is a Material idiom, not this one: hover and press are a tone
    // change on the control itself, eased on the ratified curve.
    splashFactory: NoSplash.splashFactory,
    highlightColor: const Color(0x00000000),
    splashColor: const Color(0x00000000),
    hoverColor: theme.ink.withValues(alpha: 1 / 16),
    focusColor: theme.ink.withValues(alpha: 1 / 12),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: theme.primary,
      selectionColor: theme.primary.withValues(alpha: 1 / 4),
      selectionHandleColor: theme.primary,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: theme.surface,
        border: Border.all(color: theme.hair),
      ),
      textStyle: theme.ui.copyWith(color: theme.ink),
    ),
    extensions: [theme],
  );
}
