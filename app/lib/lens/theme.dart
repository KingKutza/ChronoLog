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

/// What the eye measures between two tones: WCAG's `(L + 0.05)` ratio, in the
/// one place every ratio in this file is taken.
double contrastBetween(Color a, Color b) {
  final (low, high) = (a.computeLuminance(), b.computeLuminance());
  return low > high ? (low + 0.05) / (high + 0.05) : (high + 0.05) / (low + 0.05);
}

/// [base] carried toward [toward] until it FIRST holds [ratio] against [base].
/// Solved rather than mixed: luminance is not linear in the mix, so the point is
/// found by bisection.
///
/// It answers the near side of the crossing, never the midpoint of the last
/// bracket: a tone that lands a hair UNDER its stated ratio is a tone the eye
/// cannot tell from its ground, which is the whole defect this file's derived
/// tones exist to avoid. The bracket is halved to the limit of a double, so
/// "at least the ratio" and "the ratio" are the same answer to any measurement.
///
/// A [toward] that cannot reach the ratio at all is answered in full -- the
/// furthest this pair of colours can go is the best this pair can do.
Color _atRatio(Color base, Color toward, double ratio) {
  if (contrastBetween(base, toward) <= ratio) return toward;
  var (low, high) = (0.0, 1.0);
  for (var step = 0; step < 60; step += 1) {
    final middle = (low + high) / 2;
    if (middle <= low || middle >= high) break;
    if (contrastBetween(base, Color.lerp(base, toward, middle)!) < ratio) {
      low = middle;
    } else {
      high = middle;
    }
  }
  return Color.lerp(base, toward, high)!;
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

  /// A SURFACE STATES ITS STEP FROM ITS GROUND (ISSUES 9.2, Don: "the paper
  /// colour blending into itself in the area").
  ///
  /// The three surfaces are elevation, and elevation that names a second TOKEN
  /// is only separation while the palette happens to keep those two tokens
  /// apart. Author a flat palette -- ground, surface and paper one colour -- and
  /// every seam in the program vanishes at once, with nothing wrong anywhere.
  ///
  /// So a surface says its RELATION instead: one step above the ground it
  /// actually sits on, and the step is the ground carried toward a pole until it
  /// holds the hairline's own ratio against that ground. The yardstick is the
  /// one the program already ships -- the contrast a hairline holds against
  /// paper -- not a separation invented here.
  ///
  /// ELEVATION IS LIGHTER, as the shipped preset reads it (ground, then surface,
  /// then paper), so the pole is white wherever white has the room. Only a
  /// ground already so near white that lightening cannot reach the ratio steps
  /// DOWN instead: there, one step further up does not exist, and saying so with
  /// a tone the eye can find beats a step nobody can see.
  ///
  /// It is a function of the ground alone, so two surfaces on one ground agree
  /// and three surfaces deep still read as three.
  Color step(Color ground) {
    const white = Color(0xffffffff), black = Color(0xff000000);
    final up = contrastBetween(ground, white) >= _hairRatio;
    return _atRatio(ground, up ? white : black, _hairRatio);
  }

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

/// THE COLOUR NAMES, as data: name and hex, in pairs, in one string.
///
/// ISSUES (8.31, evening): "typing Blue into the text field did nothing either."
/// A person writes a colour the way a person says one, so the reader takes a
/// name as readily as a hex. This is the CSS/X11 vocabulary because it is the
/// one already in everybody's fingers -- a table, not a type: adding a name is
/// two words in a string, and a name nobody knows is simply refused rather than
/// being outside some closed set of legal colours.
const String colorNameTable =
    'aliceblue f0f8ff antiquewhite faebd7 aqua 00ffff aquamarine 7fffd4 azure f0ffff '
    'beige f5f5dc bisque ffe4c4 black 000000 blanchedalmond ffebcd blue 0000ff '
    'blueviolet 8a2be2 brown a52a2a burlywood deb887 cadetblue 5f9ea0 chartreuse 7fff00 '
    'chocolate d2691e coral ff7f50 cornflowerblue 6495ed cornsilk fff8dc crimson dc143c '
    'cyan 00ffff darkblue 00008b darkcyan 008b8b darkgoldenrod b8860b darkgray a9a9a9 '
    'darkgrey a9a9a9 darkgreen 006400 darkkhaki bdb76b darkmagenta 8b008b '
    'darkolivegreen 556b2f darkorange ff8c00 darkorchid 9932cc darkred 8b0000 '
    'darksalmon e9967a darkseagreen 8fbc8f darkslateblue 483d8b darkslategray 2f4f4f '
    'darkslategrey 2f4f4f darkturquoise 00ced1 darkviolet 9400d3 deeppink ff1493 '
    'deepskyblue 00bfff dimgray 696969 dimgrey 696969 dodgerblue 1e90ff firebrick b22222 '
    'floralwhite fffaf0 forestgreen 228b22 fuchsia ff00ff gainsboro dcdcdc '
    'ghostwhite f8f8ff gold ffd700 goldenrod daa520 gray 808080 grey 808080 '
    'green 008000 greenyellow adff2f honeydew f0fff0 hotpink ff69b4 indianred cd5c5c '
    'indigo 4b0082 ivory fffff0 khaki f0e68c lavender e6e6fa lavenderblush fff0f5 '
    'lawngreen 7cfc00 lemonchiffon fffacd lightblue add8e6 lightcoral f08080 '
    'lightcyan e0ffff lightgoldenrodyellow fafad2 lightgray d3d3d3 lightgrey d3d3d3 '
    'lightgreen 90ee90 lightpink ffb6c1 lightsalmon ffa07a lightseagreen 20b2aa '
    'lightskyblue 87cefa lightslategray 778899 lightslategrey 778899 '
    'lightsteelblue b0c4de lightyellow ffffe0 lime 00ff00 limegreen 32cd32 linen faf0e6 '
    'magenta ff00ff maroon 800000 mediumaquamarine 66cdaa mediumblue 0000cd '
    'mediumorchid ba55d3 mediumpurple 9370db mediumseagreen 3cb371 '
    'mediumslateblue 7b68ee mediumspringgreen 00fa9a mediumturquoise 48d1cc '
    'mediumvioletred c71585 midnightblue 191970 mintcream f5fffa mistyrose ffe4e1 '
    'moccasin ffe4b5 navajowhite ffdead navy 000080 oldlace fdf5e6 olive 808000 '
    'olivedrab 6b8e23 orange ffa500 orangered ff4500 orchid da70d6 palegoldenrod eee8aa '
    'palegreen 98fb98 paleturquoise afeeee palevioletred db7093 papayawhip ffefd5 '
    'peachpuff ffdab9 peru cd853f pink ffc0cb plum dda0dd powderblue b0e0e6 '
    'purple 800080 rebeccapurple 663399 red ff0000 rosybrown bc8f8f royalblue 4169e1 '
    'saddlebrown 8b4513 salmon fa8072 sandybrown f4a460 seagreen 2e8b57 seashell fff5ee '
    'sienna a0522d silver c0c0c0 skyblue 87ceeb slateblue 6a5acd slategray 708090 '
    'slategrey 708090 snow fffafa springgreen 00ff7f steelblue 4682b4 tan d2b48c '
    'teal 008080 thistle d8bfd8 tomato ff6347 turquoise 40e0d0 violet ee82ee '
    'wheat f5deb3 white ffffff whitesmoke f5f5f5 yellow ffff00 yellowgreen 9acd32';

/// The table read once, keyed by the name with its spaces and hyphens squeezed
/// out -- "Dark Green", "dark-green" and "darkgreen" are one name written three
/// ways, and a reader that took only the third would be refusing a colour over
/// a space bar.
final Map<String, String> colorNames = () {
  final words = colorNameTable.split(' ');
  return {
    for (var index = 0; index + 1 < words.length; index += 2) words[index]: words[index + 1],
  };
}();

String _squashed(String written) =>
    written.toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');

/// THE one colour reader: a hex, or a name. Null when what was written is not a
/// colour at all, which is a refusal the surface states in words rather than a
/// silently substituted grey (ISSUES 8.31: "a control that accepts input and
/// does nothing is worse than no control").
Color? parseColor(Object? value) {
  final written = '${value ?? ''}'.trim();
  final match = _hexPattern.firstMatch(written) ?? _hexPattern.firstMatch(colorNames[_squashed(written)] ?? '');
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
