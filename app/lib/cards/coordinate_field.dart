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

  /// A FIELD OWNS ITS TEXT WHILE THE HAND IS IN IT (ISSUES 9.2, Don: "editing
  /// the anchor's timestamp by one digit replaces the whole timestamp with that
  /// digit"). Focus is read, not assumed: while this node holds it, nothing
  /// reformats the text and nothing commits.
  final FocusNode _focus = FocusNode();

  /// What was last COMMITTED, so leaving the field commits nothing a second
  /// time. Enter and blur are two doors onto one act, not two acts -- the
  /// journal grew one entry and one undo step per keystroke, and two entries
  /// for one Enter would be the same defect wearing a smaller number.
  ///
  /// Not `late`: a lazy initializer would read the controller at the moment the
  /// first commit ASKED, which is after the typing, and the field would believe
  /// it had already written what the hand just typed.
  String _committed = '';

  String? _refusal;

  @override
  void initState() {
    super.initState();
    _committed = _controller.text;
    _focus.addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(CoordinateField old) {
    super.didUpdateWidget(old);
    final canonical = coordinateText(widget.value, widget.law);
    // Only when the record moved underneath the field, AND never while the hand
    // is in it: a reformat must never fight what is being typed. Assigning the
    // canonical spelling back into a focused controller is exactly how one
    // typed digit became the whole timestamp.
    if (widget.value != old.value && canonical != _controller.text && !_focus.hasFocus) {
      _controller.text = canonical;
      _committed = canonical;
      _refusal = null;
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _focusChanged() {
    if (_focus.hasFocus) return;
    _commit(_controller.text);
    // AND THEN CATCH UP. While the hand held the field, the record may have
    // moved underneath it -- a drag on the lens with the card open -- and
    // `didUpdateWidget` deliberately refused to rewrite the text. Nothing was
    // typed, so there is nothing to lose and a stale spelling to be rid of.
    final canonical = coordinateText(widget.value, widget.law);
    if (_controller.text != _committed || canonical == _controller.text) return;
    setState(() {
      _controller.text = canonical;
      _committed = canonical;
      _refusal = null;
    });
  }

  /// Reads what is written WITHOUT WRITING IT: the refusal is live, because a
  /// sentence about what you are typing is help, and a transaction about what
  /// you are typing is a mess.
  void _preview(String text) {
    if (text.trim().isEmpty) return setState(() => _refusal = null);
    try {
      parseCoordinateEntry(text, widget.law);
      setState(() => _refusal = null);
    } on Object catch (refusal) {
      // EVERY refusal reaches the author, in the law's own sentence. A thrown
      // value that is not a LawRefusal still carries text they can act on, and
      // letting one escape would blank the field instead of explaining it.
      setState(() => _refusal = refusalText(refusal));
    }
  }

  /// THE ONE COMMIT. Enter, blur and a pick all arrive here; text that has
  /// already been committed commits nothing, and text the law refuses commits
  /// nothing and says why.
  void _commit(String text) {
    if (text == _committed) return;
    if (text.trim().isEmpty) {
      _committed = text;
      setState(() => _refusal = null);
      return widget.onChanged(null, null);
    }
    try {
      final entry = parseCoordinateEntry(text, widget.law);
      _committed = text;
      setState(() => _refusal = null);
      widget.onChanged(entry.coordinate, entry.depth);
    } on Object catch (refusal) {
      setState(() => _refusal = refusalText(refusal));
    }
  }

  /// Writes a picked coordinate back THROUGH THE SAME TEXT the parser reads, so
  /// the picker and the field can never mean two different things. A pick is a
  /// deliberate act, so it commits where typing does not.
  void _pick(Coordinate next) {
    final text = coordinateText(next, widget.law);
    _controller.text = text;
    _preview(text);
    _commit(text);
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.disabledReason;
    if (disabled != null) return cardNote(context, disabled);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        cardWrap(context, [
          SizedBox(
            width: cardPx(context, 'card.fieldWidth'),
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              // TYPING IS NOT WRITING. `onChanged` reads for the refusal only;
              // Enter and leaving the field are the doors that commit.
              onChanged: _preview,
              onSubmitted: _commit,
              style: dataStyle(context),
              decoration: fieldChrome(
                context,
                hint: coordinateEntryPlaceholder(widget.law),
                refused: _refusal != null,
                padding: cardPx(context, 'card.gap') / 2,
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
