// The palette, as a card. Eight authored roles; everything else derives.
//
// Two field reports are the shape of this: "Color Themes has no apply button,
// and when I save I can not save as a new named theme but must override a
// existing theme." So APPLY and SAVE are separate verbs -- apply changes what
// the session looks like, save writes a file -- and SAVE AS writes a NEW file
// and leaves the one it came from exactly where it was.
//
// Themes live in `themes/<name>.json`, which makes the file and this card the
// same authoring path.

import 'dart:convert';

import 'package:flutter/material.dart';

import '../chrome/controls.dart';
import '../lens/theme.dart';
import '../session/files.dart';
import '../store/data_dir.dart';
import 'card_chrome.dart';

class ThemeCard extends StatefulWidget {
  const ThemeCard({super.key, this.onClose, this.onApply, this.files, this.names});

  final VoidCallback? onClose;

  /// Makes this palette the one the surface draws in. Absent, `theme.name` in
  /// the settings file is still authored, which is the persistent choice.
  final void Function(ChronoTheme theme)? onApply;

  /// Where `themes/<name>.json` lives. Absent, the app's own data directory.
  final SessionFiles? files;

  /// The theme files that exist, for a spec to answer without waiting.
  final List<String> Function()? names;

  @override
  State<ThemeCard> createState() => _ThemeCardState();
}

class _ThemeCardState extends State<ThemeCard> {
  late final SessionFiles _files = widget.files ?? SessionFiles(resolveDataRoot());
  ChronoTheme? _draft;
  String _saveAs = '';
  String? _note;

  /// The theme files that exist, read ONCE through the session's own listing
  /// seam. No card reaches for dart:io.
  List<String> _onDisk = const [];

  @override
  void initState() {
    super.initState();
    final named = widget.names;
    if (named != null) {
      _onDisk = named();
      return;
    }
    _files.themeNames().then((names) {
      if (mounted) setState(() => _onDisk = names);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _draft ??= ChronoTheme.of(context);
  }

  /// Every theme this workspace can name: the shipped presets, plus every file
  /// in the themes directory.
  List<String> _named() => {...shippedPresets.keys, ..._onDisk}.toList()..sort();

  void _write(String field, String hex) {
    final color = parseColor(hex);
    if (color == null) return;
    setState(() => _draft = _draft!.copyWith(palette: {field: color}));
    widget.onApply?.call(_draft!);
  }

  Future<void> _load(String name) async {
    final shippedSource = shippedPresets[name];
    if (shippedSource != null) {
      setState(() => _draft = ChronoTheme.fromJson(shippedSource));
    } else {
      final text = await _files.theme(name).read();
      if (text == null) return setState(() => _note = 'No theme file named $name.');
      final parsed = jsonDecode(text);
      if (parsed is! Map) return setState(() => _note = '$name is not a theme.');
      setState(() => _draft = ChronoTheme.fromJson(Map<String, Object?>.from(parsed)));
    }
    _apply();
  }

  void _apply() {
    widget.onApply?.call(_draft!);
    ChromeScope.of(context).settings.setText('theme.name', _draft!.name);
    setState(() => _note = 'Applied ${_draft!.name}.');
  }

  Future<void> _save(String name) async {
    final saved = _draft!.copyWith(name: name);
    await _files.ensure();
    await _files.saveNow(_files.theme(name), saved.toJson());
    setState(() {
      _draft = saved;
      _saveAs = '';
      _onDisk = {..._onDisk, name}.toList()..sort();
      _note = 'Saved themes/$name.json.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft!;
    return CardShell(
      title: 'Theme — ${draft.name}',
      sigil: '◨',
      onClose: widget.onClose,
      foldLabel: 'Derived tones, and where themes live',
      primary: [
        cardWrap(context, [
          for (final name in _named())
            namedAction(context, name, hint: 'Load this palette', onTap: () => _load(name)),
        ]),
        for (final field in themeFields)
          cardRow(
            context,
            field,
            colorField(context, hexOf(draft.palette[field]!), (hex) => _write(field, hex)),
          ),
        if (_note != null) cardNote(context, _note!),
      ],
      fold: [
        cardNote(
          context,
          'Eight roles are authored; faint, hairline and strong are the muted'
          ' ink mixed toward paper by one rule, so a new palette needs eight'
          ' colours and gets eleven. Selection is an ink ring, never a colour:'
          ' colour already carries authored frame and group meaning.',
        ),
        cardWrap(context, [
          for (final tone in <(String, Color)>[
            ('faint', draft.faint),
            ('hair', draft.hair),
            ('strong', draft.strong),
          ])
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: cardPx(context, 'card.swatch'),
                  height: cardPx(context, 'card.swatch'),
                  color: tone.$2,
                ),
                SizedBox(width: cardPx(context, 'card.gap')),
                Text(tone.$1, style: labelStyle(context)),
              ],
            ),
        ]),
      ],
      footer: [
        namedAction(context, 'Apply', hint: 'Draw the surface in this palette', onTap: _apply),
        namedAction(
          context,
          'Save',
          hint: 'Write themes/${draft.name}.json',
          onTap: () => _save(draft.name),
        ),
        CardField(
          value: _saveAs,
          hint: 'new theme name',
          onChanged: (text) => setState(() => _saveAs = text),
        ),
        namedAction(
          context,
          'Save as',
          hint: 'Write a NEW theme file and leave this one alone',
          onTap: _saveAs.trim().isEmpty ? null : () => _save(_saveAs.trim()),
        ),
      ],
    );
  }
}
