// THE SETTINGS FAMILY.
//
// ISSUES (9.1): "The settings card is a long list of barely-labeled literals --
// I don't have the first Idea how to navigate or use that." The card rendered
// every composed key, alphabetically inside areas, each row a terse label over a
// raw value. That is the store's inventory, not a surface a person decides with.
//
// Don's ruling, the same round: settings become a FAMILY of cards. The main card
// carries the most general settings and a button per sub-card; the sub-cards
// carry the rest, cut by the surfaces they govern, and every one of them carries
// a button back. Which keys are general and how the areas cut are themselves
// authored -- `settings.general` is a setting, and the cut is the table in
// `settings_words.dart` -- so no count here is a literal.
//
// AND EVERY ROW SAYS WHAT IT DOES. A label in plain words, an explanation
// underneath, and a control that fits the value's shape WITHOUT EVER CLAMPING
// IT: a truth is a toggle, a choice is a worded choice, and a number that
// ordinarily rides between two ends gets a number line between them, where
// clicking the number itself opens plain entry that takes ANY value. The stated
// range is a guide rail, never a bound. The expression stays one fold down: it
// is real, it is editable, and it is the inspector view rather than the front
// door.

import 'package:flutter/material.dart';

import '../chrome/controls.dart';
import '../core/exact.dart';
import '../core/math.dart';
import '../lens/theme.dart';
import '../session/settings.dart';
import 'card_chrome.dart';
import 'settings_words.dart';

/// A dotted key in words: `intimate.hourPixels` reads as "Hour pixels" under
/// the heading "Intimate". A key is never shown as its own dotted name -- and a
/// key that has been SAID reads in its own authored words instead of this.
String settingLabel(String key) {
  final said = settingSaidOf(key);
  if (said != null) return said.label;
  final tail = key.split('.').skip(1).join(' ');
  if (tail.isEmpty) return key;
  final spaced = tail.replaceAllMapped(
    RegExp('([a-z0-9])([A-Z])'),
    (match) => '${match[1]} ${match[2]!.toLowerCase()}',
  );
  return '${spaced[0].toUpperCase()}${spaced.substring(1)}';
}

/// What this key does, in words, or the empty string for one nothing has said
/// anything about. The wording light refuses that case by name.
String settingSays(String key) => settingSaidOf(key)?.says ?? '';

String settingArea(String key) {
  final area = key.split('.').first;
  return '${area[0].toUpperCase()}${area.substring(1)}';
}

/// The range this key ORDINARILY rides, evaluated, or null where none is
/// stated. Advisory metadata: the rail is drawn here and nothing is bounded by
/// it.
({Rational low, Rational high})? settingRail(String key) {
  final said = settingSaidOf(key);
  if (said == null || !said.railed) return null;
  try {
    final low = evaluateSource(said.low!, const Env());
    final high = evaluateSource(said.high!, const Env());
    if (low is! Rational || high is! Rational || !(low < high)) return null;
    return (low: low, high: high);
  } on MathRefusal {
    return null;
  }
}

/// A NUMBER LINE THAT NEVER CLAMPS (ISSUES 9.1, Don's ruling). The rail runs
/// between the two ends the key states it ordinarily rides; dragging anywhere on
/// it lands there, and CLICKING THE NUMBER opens plain entry that accepts any
/// value at all -- above the rail, below it, or an expression. A value outside
/// the rail is drawn at the rail's end and SAID beside it, so the control never
/// lies about what is stored.
class SettingNumberLine extends StatefulWidget {
  const SettingNumberLine({
    super.key,
    required this.value,
    required this.low,
    required this.high,
    required this.steps,
    required this.onChanged,
    this.written = '',
  });

  final String written;

  /// How finely the rail lands. A rail is a rail and not a continuum: the value
  /// it writes is exact, and this is how many exact places it offers.
  final int steps;
  final Rational value, low, high;
  final void Function(String source) onChanged;

  @override
  State<SettingNumberLine> createState() => _SettingNumberLineState();
}

class _SettingNumberLineState extends State<SettingNumberLine> {
  bool _typing = false;

  double get _share {
    final span = (widget.high - widget.low).toDouble();
    if (span <= 0) return 0;
    final at = (widget.value - widget.low).toDouble() / span;
    return at < 0 ? 0 : (at > 1 ? 1 : at);
  }

  bool get _outside => widget.value < widget.low || widget.high < widget.value;

  void _landed(double share) {
    final span = widget.high - widget.low;
    final steps = widget.steps < 1 ? 1 : widget.steps;
    final at =
        widget.low + span * Rational.fromInt((share.clamp(0, 1) * steps).round(), steps);
    widget.onChanged(at.toJson());
  }

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeScope.of(context);
    final theme = ChronoTheme.of(context);
    final rail = SizedBox(
      width: cardPx(context, 'card.fieldWidth'),
      height: chrome.px('chrome.hit'),
      child: LayoutBuilder(
        builder: (context, constraints) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (at) => _landed(at.localPosition.dx / constraints.maxWidth),
          onHorizontalDragUpdate: (at) => _landed(at.localPosition.dx / constraints.maxWidth),
          child: CustomPaint(
            painter: _RailPainter(
              share: _share,
              track: theme.hair,
              ink: _outside ? theme.accent : theme.primary,
              thickness: chrome.px('chrome.hair'),
              grip: chrome.px('chrome.focusRing') * 2,
            ),
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        cardWrap(context, [
          Text(widget.low.toDecimal(2), style: labelStyle(context)),
          rail,
          Text(widget.high.toDecimal(2), style: labelStyle(context)),
          // THE CLICK-THROUGH: the displayed number IS the door to plain entry.
          namedAction(
            context,
            widget.value.toDecimal(3),
            glyph: widget.value.toDecimal(3),
            hint: 'Write any value — the range is a guide rail, not a bound.',
            onTap: () => setState(() => _typing = !_typing),
          ),
        ]),
        if (_outside)
          Text(
            'Outside the range this ordinarily rides. Stored as written.',
            style: labelStyle(context, color: theme.accent),
          ),
        if (_typing)
          CardField(
            value: widget.written,
            mono: true,
            hint: 'any value, or an expression',
            onChanged: widget.onChanged,
          ),
      ],
    );
  }
}

class _RailPainter extends CustomPainter {
  const _RailPainter({
    required this.share,
    required this.track,
    required this.ink,
    required this.thickness,
    required this.grip,
  });

  final double share, thickness, grip;
  final Color track, ink;

  @override
  void paint(Canvas canvas, Size size) {
    final middle = size.height / 2;
    canvas.drawLine(
      Offset(0, middle),
      Offset(size.width, middle),
      Paint()
        ..color = track
        ..strokeWidth = thickness,
    );
    canvas.drawLine(
      Offset(0, middle),
      Offset(size.width * share, middle),
      Paint()
        ..color = ink
        ..strokeWidth = thickness * 2,
    );
    canvas.drawCircle(Offset(size.width * share, middle), grip, Paint()..color = ink);
  }

  @override
  bool shouldRepaint(_RailPainter old) => old.share != share || old.ink != ink;
}

class SettingsCard extends StatefulWidget {
  const SettingsCard({super.key, this.onClose, this.area});

  /// Which sub-card this is. Null is the main card: the general settings and a
  /// button per surface.
  final String? area;

  final VoidCallback? onClose;

  @override
  State<SettingsCard> createState() => _SettingsCardState();
}

class _SettingsCardState extends State<SettingsCard> {
  String _find = '';
  final Set<String> _revealed = {};

  /// One row: the words, the control, and the expression one fold down.
  Widget _row(BuildContext context, String key) {
    final chrome = ChromeScope.of(context);
    final settings = chrome.settings;
    final theme = ChronoTheme.of(context);
    final source = settings.expressionOf(key);
    final overridden = settings.toJson().containsKey(key);
    // A text setting is not arithmetic -- reading a key binding as algebra is a
    // category error -- so it never reaches the evaluator.
    final text = settings.shippedText.containsKey(key);
    final rail = text ? null : settingRail(key);
    final raw = text ? null : settings.raw(key);
    final control = switch (raw) {
      final bool truth => namedToggle(
        context,
        settingLabel(key),
        truth,
        (next) => setState(() => saySetting(context, key, next ? 'true' : 'false')),
      ),
      // THE CONTROL FITS THE VALUE'S SHAPE. A number whose key states where it
      // ordinarily rides gets the line; one that states nothing gets the pair of
      // steppers, which is the honest control for a number with no stated span.
      final Rational number when rail != null => SettingNumberLine(
        value: number,
        low: rail.low,
        high: rail.high,
        steps: cardPx(context, 'card.railSteps').round(),
        written: source,
        onChanged: (written) => setState(() => saySetting(context, key, written)),
      ),
      final Rational number => namedNumber(
        context,
        settingLabel(key),
        number,
        (next) => setState(() => saySetting(context, key, next.toJson())),
      ),
      _ => controlChip(
        context,
        label: settingLabel(key),
        inert: true,
        child: CardField(
          value: settings.text(key),
          width: cardPx(context, 'card.fieldWidth'),
          onChanged: (written) => saySetting(context, key, written),
        ),
      ),
    };
    final says = settingSays(key);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The label stands over the row where the control does not already
        // carry one; a toggle and a stepper name themselves.
        if (rail != null) Text(settingLabel(key), style: bodyStyle(context, color: theme.ink)),
        // WHAT IT DOES AND WHERE IT ACTS, in the open. A row nobody can read is
        // not a row.
        if (says.isNotEmpty) Text(says, style: labelStyle(context, color: theme.strong)),
        Row(
          children: [
            Flexible(child: control),
            SizedBox(width: cardPx(context, 'card.gap')),
            if (!text)
              namedAction(
                context,
                'Show the expression',
                glyph: 'ƒ',
                hint: 'What this setting is written as',
                onTap: () => setState(
                  () => _revealed.contains(key) ? _revealed.remove(key) : _revealed.add(key),
                ),
              ),
            if (overridden)
              namedAction(
                context,
                'Reset ${settingLabel(key)}',
                glyph: '↺',
                hint: 'Back to the shipped default',
                onTap: () => setState(() => unsaySetting(context, key)),
              ),
          ],
        ),
        if (_revealed.contains(key))
          ExpressionField(
            label: key,
            source: source,
            evaluate: (written) {
              final refused = saySetting(context, key, written);
              if (refused != null) throw MathRefusal(refused);
              return '${settings.raw(key)}';
            },
            onChanged: (_) => setState(() {}),
          ),
        if (settings.refusals.any((line) => line.startsWith(key)))
          cardNote(
            context,
            settings.refusals.firstWhere((line) => line.startsWith(key)),
            refusal: true,
          ),
        Divider(height: cardPx(context, 'card.gap'), color: theme.hair),
      ],
    );
  }

  /// The page's own Reset all: how many overrides this card's areas hold, and
  /// the one act that puts them all back. Nothing is offered when nothing is
  /// authored -- a reset over a page of shipped defaults would do nothing and
  /// say it did something.
  Widget _resetPage(BuildContext context, Settings settings, List<String> areas) {
    final prefixes = [for (final area in areas) '$area.'];
    final authored = [
      for (final key in settings.toJson().keys)
        if (prefixes.any(key.startsWith)) key,
    ];
    if (authored.isEmpty) {
      return cardNote(context, 'Nothing on this card is written differently from how it ships.');
    }
    return cardWrap(context, [
      namedAction(
        context,
        'Reset all — ${authored.length} written differently',
        glyph: '↺',
        hint: 'Every setting on this card back to the shipped default',
        onTap: () => setState(() => settings.resetUnder(prefixes)),
      ),
    ]);
  }

  /// Every composed key, and no second list: the shell composes every area's
  /// defaults, so restating one area's here could only ever go stale.
  List<String> _keys(Settings settings) => [
    ...{...settings.keys, ...settings.shippedText.keys},
  ]..sort();

  /// FIND MATCHES THE WORDS (ISSUES 9.1: "find that matches the words, not just
  /// the dotted keys"). A find crosses every card in the family, because the
  /// person doing it is looking for a setting, not for a surface.
  List<String> _found(Settings settings, String needle) => [
    for (final key in _keys(settings))
      if (key.toLowerCase().contains(needle) ||
          settingLabel(key).toLowerCase().contains(needle) ||
          settingSays(key).toLowerCase().contains(needle))
        key,
  ];

  @override
  Widget build(BuildContext context) {
    final settings = ChromeScope.of(context).settings;
    final needle = _find.trim().toLowerCase();
    final area = widget.area;
    final family = settingsSubCards(_keys(settings));
    final mine = area == null
        ? const <String>[]
        : (family.where((card) => card.address == area).firstOrNull?.areas ?? [area]);
    final general = [
      for (final word in settings.text('settings.general').split(RegExp(r'\s+')))
        if (word.trim().isNotEmpty) word.trim(),
    ];
    final title = area == null ? 'Settings' : settingsCardTitle(area);
    return CardShell(
      title: title,
      sigil: '⚙',
      onClose: widget.onClose,
      foldLabel: area == null ? 'Where these live' : 'What this card governs',
      primary: [
        CardField(
          value: _find,
          width: double.infinity,
          hint: 'Find a setting',
          onChanged: (text) => setState(() => _find = text),
        ),
        // REFUSALS ANNOUNCE, and the ones that name no key have nowhere else to
        // be said: a settings file line nobody ships a key for, a settings card
        // asked for a surface no card governs.
        for (final line in settings.refusals)
          if (!_keys(settings).any(line.startsWith)) cardNote(context, line, refusal: true),
        if (needle.isNotEmpty) ...[
          // A find is a find, not a filter of this card: it reaches every
          // setting in the program, wherever it usually lives.
          for (final key in _found(settings, needle)) _row(context, key),
          if (_found(settings, needle).isEmpty)
            cardNote(context, 'Nothing here is called that, and nothing says it.'),
        ] else if (area == null) ...[
          cardNote(
            context,
            'The settings people reach for. Everything else is on the card for '
            'the surface it governs — and the find above reaches all of them.',
          ),
          for (final key in general)
            if (settings.expressionOf(key).isNotEmpty || settings.shippedText.containsKey(key))
              _row(context, key)
            else
              cardNote(
                context,
                'settings.general names "$key", and nothing ships one. Nothing '
                'is shown for it.',
                refusal: true,
              ),
          cardRule(context),
          Text('By what it governs', style: labelStyle(context)),
          // A BUTTON PER SUB-CARD. Derived from the family, so a surface that
          // gains an area gains a button the day it ships.
          cardDoors(context, [
            for (final card in family)
              cardDoor(
                card.title,
                'The settings for ${card.areas.map((a) => settingAreaNames[a] ?? a).join(', ')}.',
                (factory) => factory.settingsCard(area: card.address),
              ),
            cardDoor(
              'The palette',
              'The colours the whole surface is drawn in. Apply is live; Save '
                  'writes a file.',
              (factory) => factory.themesCard(),
            ),
          ]),
        ] else ...[
          // EVERY SUB-CARD CARRIES A BUTTON BACK (ISSUES 9.1) -- AT THE HEAD OF
          // IT. A surface with fifty settings on it is a surface you scroll,
          // and a way back at the bottom of the scroll is a way back you have
          // to go looking for: the door belongs where you arrive.
          cardDoors(context, [
            cardDoor(
              'All settings',
              'Back to the general settings and the rest of the family.',
              (factory) => factory.settingsCard(),
            ),
            cardDoor(
              'The document',
              'What this document is called, and where it saves.',
              (factory) => factory.documentCard(),
            ),
          ]),
          cardRule(context),
          // RESET ALL, FOR THE PAGE (ISSUES 9.2, Don on the keybindings page:
          // it "must allow resetting"). Per-key reset was already on every
          // row; what was missing was the whole page at once, which is the act
          // a person actually wants after an afternoon of moving chords around.
          // It is offered on EVERY sub-card, not just the keyboard's, because a
          // page of settings is a page of settings -- and it says how many
          // overrides it found rather than sitting there as a live button over
          // nothing.
          _resetPage(context, settings, mine),
          for (final key in _keys(settings))
            if (mine.contains(key.split('.').first)) _row(context, key),
        ],
      ],
      fold: [
        cardNote(
          context,
          area == null
              ? 'Every setting is a line in chronolog.settings, written as an'
                    ' expression in the one math. Editing the file and editing'
                    ' this card are the same authoring path; the file'
                    ' hot-reloads, and a refused expression keeps the last good'
                    ' value and says why.'
              : 'This card governs '
                    '${mine.map((a) => settingAreaNames[a] ?? a).join(', ')}. Every'
                    ' value is an expression in the one math, and the range a'
                    ' number line draws is what the setting says it ordinarily'
                    ' rides — never a bound on what you may write.',
        ),
      ],
    );
  }
}
