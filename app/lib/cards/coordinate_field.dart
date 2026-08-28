// THE coordinate field: one variable-precision entry, never a date input beside
// a time input.
//
// Owner's ruling (8.20): "what we want is a single feild (not date time
// seperated) that allows for a variable percision entry, eg. Type month day
// year hour minute second millisecond, or pull a picker that lets you zoom it
// in." DEPTH IS PRECISION, NEVER UNCERTAINTY -- fuzziness is authored by a
// connection's own spread checkbox and is never inferred from how deep somebody
// typed.
//
// Every level name, order, radix, vocabulary and era affix comes from the
// governing frame's own law through `core/coordinate_entry.dart`. Nothing here
// knows what a month is. A refusal is the law's own sentence, shown in place;
// the field never clears what was typed and never guesses a coordinate.

import 'package:flutter/material.dart';

import '../chrome/controls.dart';
import '../chrome/menus.dart';
import '../core/coordinate_entry.dart';
import '../core/coordinate_law.dart';
import '../core/eras.dart';
import '../lens/theme.dart';
import 'card_chrome.dart';

/// The coordinate with [level] set to [picked] and every deeper level dropped.
/// Picking a rung is picking a value and asking the ladder again, which is why
/// stopping partway costs nothing and leaves the coordinate at that depth.
Coordinate coordinateAt(Coordinate value, CoordinateLaw law, String level, String picked) {
  final entries = <LevelEntry>[];
  for (final rung in law.levels) {
    if (rung.name == level) {
      entries.add((level: level, value: picked));
      break;
    }
    final already = firstMatch(value.levels, (entry) => entry.level == rung.name);
    if (already == null) break;
    entries.add(already);
  }
  return Coordinate(entries);
}

/// The canonical text for a coordinate, or empty when it cannot be written: a
/// stored coordinate skipping a level between the root and its own depth is
/// already invalid data, and a blank field states that better than a throw.
String coordinateText(Coordinate? value, CoordinateLaw law) {
  if (value == null || value.levels.isEmpty) return '';
  try {
    return formatCoordinateEntry(value, law);
  } on Object {
    return '';
  }
}

class CoordinateField extends StatefulWidget {
  const CoordinateField({
    super.key,
    required this.law,
    required this.value,
    required this.onChanged,
    this.disabledReason,
  });

  final CoordinateLaw law;
  final Coordinate? value;

  /// The parsed coordinate and the depth the author actually typed. Null means
  /// the field was emptied, which is the legal statement "unstated".
  final void Function(Coordinate? value, String? depth) onChanged;

  /// Why this field cannot be edited, in the caller's own words. A field that
  /// refuses says why rather than greying out in silence.
  final String? disabledReason;

  @override
  State<CoordinateField> createState() => _CoordinateFieldState();
}

class _CoordinateFieldState extends State<CoordinateField> {
  late final TextEditingController _controller = TextEditingController(
    text: coordinateText(widget.value, widget.law),
  );
  String? _refusal;

  @override
  void didUpdateWidget(CoordinateField old) {
    super.didUpdateWidget(old);
    final canonical = coordinateText(widget.value, widget.law);
    // Only when the record moved underneath the field: a reformat must never
    // fight what is being typed.
    if (widget.value != old.value && canonical != _controller.text) {
      _controller.text = canonical;
      _refusal = null;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _read(String text) {
    if (text.trim().isEmpty) {
      setState(() => _refusal = null);
      return widget.onChanged(null, null);
    }
    try {
      final entry = parseCoordinateEntry(text, widget.law);
      setState(() => _refusal = null);
      widget.onChanged(entry.coordinate, entry.depth);
    } on Object catch (refusal) {
      // EVERY refusal reaches the author, in the law's own sentence. A thrown
      // value that is not a LawRefusal still carries text they can act on, and
      // letting one escape would blank the field instead of explaining it.
      setState(() => _refusal = refusalText(refusal));
    }
  }

  /// Writes a picked coordinate back THROUGH THE SAME TEXT the parser reads, so
  /// the picker and the field can never mean two different things.
  void _pick(Coordinate next) {
    final text = coordinateText(next, widget.law);
    _controller.text = text;
    _read(text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChronoTheme.of(context);
    final disabled = widget.disabledReason;
    if (disabled != null) return cardNote(context, disabled);
    final border = OutlineInputBorder(
      borderSide: BorderSide(
        color: _refusal == null ? theme.hair : theme.primary,
        width: ChromeScope.of(context).px('chrome.hair'),
      ),
      borderRadius: BorderRadius.circular(ChromeScope.of(context).px('chrome.corner')),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        cardWrap(context, [
          SizedBox(
            width: cardPx(context, 'card.fieldWidth'),
            child: TextField(
              controller: _controller,
              onChanged: _read,
              style: dataStyle(context),
              decoration: InputDecoration(
                isDense: true,
                hintText: coordinateEntryPlaceholder(widget.law),
                hintStyle: labelStyle(context, color: theme.hair),
                contentPadding: EdgeInsets.all(cardPx(context, 'card.gap') / 2),
                border: border,
                enabledBorder: border,
              ),
            ),
          ),
          ChronoMenu(label: 'Pick', glyph: '⌖', body: (context, close) => _ladder(context)),
        ]),
        cardNote(context, _refusal ?? coordinateEntryHelp(widget.law), refusal: _refusal != null),
      ],
    );
  }

  /// The zoomable picker: one rung per law level, from the root down to the
  /// first level not yet fixed.
  ///
  /// OVERSCALE DOCTRINE. An unbounded rung -- the root, the continuous tail --
  /// has no determinable count, so it offers NO option list at any depth. It
  /// says so and leaves the value to be typed.
  Widget _ladder(BuildContext context) {
    final current = widget.value ?? Coordinate.empty;
    final rungs = coordinatePickerLadder(widget.law, current);
    if (rungs.isEmpty) {
      return cardNote(context, 'This frame declares no coordinate levels to pick.');
    }
    return SizedBox(
      height: cardPx(context, 'card.pickerHeight'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final rung in rungs)
            SizedBox(
              width: cardPx(context, 'card.pickerWidth'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(rung.label, style: labelStyle(context)),
                  Expanded(
                    child: !rung.bounded
                        ? cardNote(context, 'Not countable — type it.')
                        : ListView(
                            children: [
                              for (final option in rung.options)
                                cardLink(
                                  context,
                                  option.value == rung.chosen ? '• ${option.label}' : option.label,
                                  () => _pick(
                                    coordinateAt(current, widget.law, rung.level, option.value),
                                  ),
                                ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
