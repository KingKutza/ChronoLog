// Every tunable in the program, as a designed control.
//
// The condemned surface, verbatim: "settings rendered as raw literals must
// present as designed controls, arcana out of the primary path". So no key is
// shown as a bare number in a bare box. Each one carries its name in words, a
// control whose SHAPE is read from what the setting's own expression evaluates
// to -- a truth value gets a toggle, a number gets a stepped field -- and a
// reset. The expression itself is the arcanum: it is real, it is editable, and
// it is revealed only when asked for.

import 'package:flutter/material.dart';

import '../chrome/controls.dart';
import '../core/exact.dart';
import '../core/math.dart';
import '../lens/theme.dart';
import 'card_chrome.dart';

/// A dotted key in words: `intimate.hourPixels` reads as "Hour pixels" under
/// the heading "Intimate". A key is never shown as its own label.
String settingLabel(String key) {
  final tail = key.split('.').skip(1).join(' ');
  if (tail.isEmpty) return key;
  final spaced = tail.replaceAllMapped(
    RegExp('([a-z0-9])([A-Z])'),
    (match) => '${match[1]} ${match[2]!.toLowerCase()}',
  );
  return '${spaced[0].toUpperCase()}${spaced.substring(1)}';
}

String settingArea(String key) {
  final area = key.split('.').first;
  return '${area[0].toUpperCase()}${area.substring(1)}';
}

class SettingsCard extends StatefulWidget {
  const SettingsCard({super.key, this.onClose});

  final VoidCallback? onClose;

  @override
  State<SettingsCard> createState() => _SettingsCardState();
}

class _SettingsCardState extends State<SettingsCard> {
  String _find = '';
  final Set<String> _revealed = {};

  Widget _row(BuildContext context, String key) {
    final chrome = ChromeScope.of(context);
    final settings = chrome.settings;
    final theme = ChronoTheme.of(context);
    final source = settings.expressionOf(key);
    final overridden = settings.toJson().containsKey(key);
    // A text setting is not arithmetic -- reading a key binding as algebra is a
    // category error -- so it never reaches the evaluator.
    final text = settings.shippedText.containsKey(key);
    final control = switch (text ? null : settings.raw(key)) {
      final bool truth => namedToggle(
        context,
        settingLabel(key),
        truth,
        (next) => setState(() => settings.set(key, next ? 'true' : 'false')),
      ),
      final Rational number => namedNumber(
        context,
        settingLabel(key),
        number,
        (next) => setState(() => settings.set(key, next.toJson())),
      ),
      _ => controlChip(
        context,
        label: settingLabel(key),
        inert: true,
        child: CardField(
          value: settings.text(key),
          width: cardPx(context, 'card.fieldWidth'),
          onChanged: (text) => settings.setText(key, text),
        ),
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            control,
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
                onTap: () => setState(() => settings.reset(key)),
              ),
          ],
        ),
        if (_revealed.contains(key))
          ExpressionField(
            label: key,
            source: source,
            evaluate: (text) {
              final refused = settings.set(key, text);
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

  @override
  Widget build(BuildContext context) {
    final settings = ChromeScope.of(context).settings;
    final needle = _find.trim().toLowerCase();
    final keys = [
      // Every composed key, and no second list: the shell composes every
      // area's defaults, so restating one area's here could only ever go stale.
      for (final key in {...settings.keys, ...settings.shippedText.keys})
        if (needle.isEmpty ||
            key.toLowerCase().contains(needle) ||
            settingLabel(key).toLowerCase().contains(needle))
          key,
    ]..sort();
    final areas = <String, List<String>>{};
    for (final key in keys) {
      areas.putIfAbsent(settingArea(key), () => []).add(key);
    }
    return CardShell(
      title: 'Settings',
      sigil: '⚙',
      onClose: widget.onClose,
      foldLabel: 'Where these live',
      primary: [
        CardField(
          value: _find,
          width: double.infinity,
          hint: 'Find a setting',
          onChanged: (text) => setState(() => _find = text),
        ),
        for (final area in areas.entries) ...[
          Text(area.key, style: labelStyle(context)),
          for (final key in area.value) _row(context, key),
        ],
      ],
      fold: [
        cardNote(
          context,
          'Every setting is a line in chronolog.settings, written as an'
          ' expression in the one math. Editing the file and editing this card'
          ' are the same authoring path; the file hot-reloads, and a refused'
          ' expression keeps the last good value and says why.',
        ),
      ],
    );
  }
}
