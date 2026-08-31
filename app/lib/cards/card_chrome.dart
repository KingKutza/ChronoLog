// The shared card frame, and every number the cards draw with.
//
// A card is a designed instrument, not a dump of the record's fields. The
// standing complaint about the old surface was that it read as "a very
// programmer interface -- menus take a lot of space with a lot of arcane
// settings that render as literals". So every card here wears one frame: a
// header naming what is being edited, a SHORT primary path (what a person
// actually came to say), ONE fold holding everything else, and a footer of
// actions. There is no confirmation dialog: every action is undoable instead.

import 'package:flutter/material.dart';

import '../chrome/controls.dart';
import '../chrome/menus.dart';
import '../core/exact.dart';
import '../core/math.dart';
import '../lens/theme.dart';
import '../lens/tunables.dart';
import '../session/settings.dart';
import 'card_factory.dart';

/// The card layer's numbers, as named settings whose defaults are expressions
/// in the one math. Nothing below is a literal in a widget.
const Map<String, String> frameCardTunableDefaults = {
  'card.pad': '12',
  'card.gap': '8',
  'card.labelWidth': '124',
  // A CARD IS A TILE AND A TILE IS ANY WIDTH (ISSUES 8.31). The label is not a
  // fixed column: it takes its share of the room the tile actually gave, never
  // more than its full width and never less than its floor, and below that the
  // row stacks and then collapses onto the control alone.
  'card.labelShare': '2/5',
  'card.labelMin': '2 * 22',
  'card.controlMin': '2 * 30',
  'card.fieldWidth': '210',
  'card.narrowWidth': '76',
  'card.swatch': '22',
  'card.rowHeight': '30',
  'card.listHeight': '340',
  'card.textLines': '4',
  'card.findRows': '200',
  'document.compactMinutes': '10',
  // The document bar's save control: the lamp's diameter and the gap between
  // the mark, the lamp and the word beside them.
  'document.lamp': '2 * 5',
  'document.saveGap': '2 * 3',
};

/// One card number. The composed settings win when the session knows the key,
/// so a user override in `chronolog.settings` reaches these cards; the shipped
/// map answers on its own until the session composes it.
Rational cardTunable(Settings settings, String key) {
  if (settings.expressionOf(key).isNotEmpty) return settings.value(key);
  // Three shipped maps, ONE reader: the frame cards' numbers, the object cards'
  // numbers, and the lens numbers a card quotes (promotion thresholds). No key
  // is defaulted twice, and a key in no map at all is a refusal naming it
  // rather than a silently substituted zero.
  for (final map in const [frameCardTunableDefaults, cardTunableDefaults, lensTunableDefaults]) {
    if (map.containsKey(key)) return tunableFrom(map, null, key);
  }
  throw MathRefusal('No setting named $key');
}

double cardPx(BuildContext context, String key) =>
    cardTunable(ChromeScope.of(context).settings, key).toDouble();

/// The card frame. [primary] is the short path; [fold] is everything else,
/// behind one disclosure.
class CardShell extends StatefulWidget {
  const CardShell({
    super.key,
    required this.title,
    this.sigil = '',
    this.dirty = false,
    this.onClose,
    this.primary = const [],
    this.fold = const [],
    this.foldLabel = 'Everything else',
    this.footer = const [],
  });

  final String title, sigil, foldLabel;
  final bool dirty;
  final VoidCallback? onClose;
  final List<Widget> primary, fold, footer;

  @override
  State<CardShell> createState() => _CardShellState();
}

class _CardShellState extends State<CardShell> {
  bool _open = false;

  /// The header and the footer are the same band, ruled on opposite edges and
  /// standing on `surface` -- chrome's own tone -- so the card's body reads as
  /// the sheet between them.
  Widget _band(BuildContext context, Widget child, {required bool top}) {
    final theme = ChronoTheme.of(context);
    final side = BorderSide(color: theme.hair, width: ChromeScope.of(context).px('chrome.hair'));
    return Container(
      padding: EdgeInsets.all(cardPx(context, 'card.pad')),
      decoration: BoxDecoration(
        color: theme.surface,
        border: top ? Border(top: side) : Border(bottom: side),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeScope.of(context);
    final theme = ChronoTheme.of(context);
    // The tile under this already paints `paper`; a card that painted its own
    // ground a second time is where the three surface roles stopped meaning
    // elevation and started meaning nothing.
    return DecoratedBox(
      decoration: BoxDecoration(color: theme.paper),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _band(
            context,
            Row(
              children: [
                if (widget.sigil.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(right: cardPx(context, 'card.gap')),
                    child: Text(widget.sigil, style: dataStyle(context, color: theme.strong)),
                  ),
                Expanded(
                  child: Text(
                    widget.title,
                    overflow: TextOverflow.ellipsis,
                    style: bodyStyle(context).copyWith(fontSize: chrome.px('chrome.title')),
                  ),
                ),
                if (widget.dirty)
                  Tooltip(
                    message: 'Unsaved edits',
                    child: Text('*', style: dataStyle(context, color: theme.primary)),
                  ),
                if (widget.onClose != null)
                  namedAction(context, 'Close', glyph: '×', onTap: widget.onClose),
              ],
            ),
            top: false,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(cardPx(context, 'card.pad')),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final child in widget.primary) _spaced(context, child),
                  if (widget.fold.isNotEmpty)
                    InkWell(
                      onTap: () => setState(() => _open = !_open),
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: cardPx(context, 'card.gap')),
                        child: Text(
                          '${_open ? '▾' : '▸'}  ${widget.foldLabel}',
                          style: labelStyle(context, color: theme.strong),
                        ),
                      ),
                    ),
                  AnimatedSize(
                    duration: chrome.motion,
                    curve: chrome.curve,
                    alignment: Alignment.topLeft,
                    child: _open
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [for (final child in widget.fold) _spaced(context, child)],
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                ],
              ),
            ),
          ),
          if (widget.footer.isNotEmpty) _band(context, cardWrap(context, widget.footer), top: true),
        ],
      ),
    );
  }
}

Widget _spaced(BuildContext context, Widget child) => Padding(
  padding: EdgeInsets.only(bottom: cardPx(context, 'card.gap')),
  child: child,
);

/// A named row of the primary path: the label reads as a question, the control
/// answers it -- AT WHATEVER WIDTH THE TILE HANDED THE CARD.
///
/// ISSUES (8.31), the same class as the responsive bars: "a card tile narrower
/// than about 200px overflows its RenderFlex -- cardRow pairs the fixed
/// card.labelWidth with a Flexible". A fixed column inside a Row is a claim
/// about space nobody promised. So the row reads the room it was actually given
/// and takes one of three forms, by settings-keyed thresholds and nothing else:
///
///   SHRINK   -- label and control side by side, the label taking its share of
///               the room up to its full width;
///   STACK    -- the label above the control, once a share of the room is too
///               narrow to read as a label;
///   COLLAPSE -- the control alone with the label on its tooltip, once there is
///               not even room for the control beside anything.
///
/// Nothing is clipped and nothing is lost, which is the rule the bars follow.
Widget cardRow(BuildContext context, String label, Widget child) {
  final full = cardPx(context, 'card.labelWidth');
  final least = cardPx(context, 'card.labelMin');
  final control = cardPx(context, 'card.controlMin');
  final share = cardPx(context, 'card.labelShare');
  Widget named(double width) =>
      SizedBox(width: width, child: Text(label, style: labelStyle(context)));
  return LayoutBuilder(
    builder: (context, constraints) {
      final room = constraints.maxWidth;
      // Unbounded is not narrow: a row inside a scrolling run keeps its column.
      if (!room.isFinite) return Row(children: [named(full), Flexible(child: child)]);
      final wanted = room * share;
      final width = wanted > full ? full : wanted;
      if (width >= least && room - width >= control) {
        return Row(children: [named(width), Flexible(child: child)]);
      }
      if (room >= control) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [Text(label, style: labelStyle(context)), child],
        );
      }
      return Tooltip(message: label, child: child);
    },
  );
}

/// The rule between two regions of a card. ISSUES (8.31): "A horizontal rule,
/// then staples" -- the eye's natural path needs one seam, drawn in the ground
/// channel every divider in the program uses.
Widget cardRule(BuildContext context) => Container(
  height: ChromeScope.of(context).px('chrome.hair'),
  color: ChronoTheme.of(context).hair,
);

/// Guidance, or a refusal in the law's own words. A card that cannot do
/// something says so here rather than failing quietly.
Widget cardNote(BuildContext context, String text, {bool refusal = false}) {
  final theme = ChronoTheme.of(context);
  final tone = refusal ? theme.primary : theme.accent;
  return Container(
    width: double.infinity,
    padding: EdgeInsets.all(cardPx(context, 'card.gap')),
    decoration: BoxDecoration(
      color: theme.paper,
      border: Border(
        left: BorderSide(color: tone, width: ChromeScope.of(context).px('chrome.focusRing')),
      ),
    ),
    child: Text(text, style: bodyStyle(context, color: refusal ? tone : theme.strong)),
  );
}

/// A read-only run of authored words -- traits, group names -- as chips. Never
/// a comma string.
Widget cardChips(BuildContext context, Iterable<String> words) {
  final chrome = ChromeScope.of(context);
  final theme = ChronoTheme.of(context);
  return cardWrap(context, [
    for (final word in words)
      Container(
        padding: EdgeInsets.symmetric(horizontal: cardPx(context, 'card.gap')),
        decoration: BoxDecoration(
          border: Border.all(color: theme.hair, width: chrome.px('chrome.hair')),
          borderRadius: BorderRadius.circular(chrome.px('chrome.corner')),
        ),
        child: Text(word, style: labelStyle(context)),
      ),
  ]);
}

/// The one plain text entry these cards use: hairline, dense, and monospace
/// wherever the text is data rather than prose.
class CardField extends StatefulWidget {
  const CardField({
    super.key,
    required this.value,
    required this.onChanged,
    this.hint = '',
    this.width,
    this.lines = 1,
    this.mono = false,
  });

  final String value, hint;
  final void Function(String) onChanged;
  final double? width;
  final int lines;
  final bool mono;

  @override
  State<CardField> createState() => _CardFieldState();
}

class _CardFieldState extends State<CardField> {
  late final TextEditingController _controller = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(CardField old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeScope.of(context);
    final theme = ChronoTheme.of(context);
    final border = OutlineInputBorder(
      borderSide: BorderSide(color: theme.hair, width: chrome.px('chrome.hair')),
      borderRadius: BorderRadius.circular(chrome.px('chrome.corner')),
    );
    return SizedBox(
      width: widget.width ?? cardPx(context, 'card.fieldWidth'),
      child: TextField(
        controller: _controller,
        maxLines: widget.lines,
        onChanged: widget.onChanged,
        style: widget.mono ? dataStyle(context) : bodyStyle(context),
        decoration: InputDecoration(
          isDense: true,
          hintText: widget.hint,
          hintStyle: labelStyle(context, color: theme.hair),
          contentPadding: EdgeInsets.all(cardPx(context, 'card.gap') / 2),
          border: border,
          enabledBorder: border,
        ),
      ),
    );
  }
}

// --- Shared instruments (D2a addition) --------------------------------------

/// A run of controls that wraps rather than clipping, vertically centred. The
/// one horizontal grouping these cards use, so no site spells its own spacing.
Widget cardWrap(BuildContext context, List<Widget> children) => Wrap(
  spacing: cardPx(context, 'card.gap'),
  runSpacing: cardPx(context, 'card.gap') / 2,
  crossAxisAlignment: WrapCrossAlignment.center,
  children: children,
);

/// A reference, rendered as what it is CALLED and opening its own card. Never a
/// bare record id, and never a label that cannot be followed: "a staple you can
/// only see from one side is half a record."
Widget cardLink(BuildContext context, String label, VoidCallback? onTap) => InkWell(
  onTap: onTap,
  child: Text(
    label,
    style: bodyStyle(
      context,
      color: onTap == null ? ChronoTheme.of(context).strong : ChronoTheme.of(context).primary,
    ),
  ),
);

/// A choice, through the one menu class. [options] is label by value, so a site
/// states its vocabulary and nothing else; a null [onPick] states the refusal
/// in [hint] rather than greying out in silence.
Widget cardMenu(
  BuildContext context,
  String active,
  Map<String, String> options,
  void Function(String)? onPick, {
  String? hint,
}) => ChronoMenu(
  label: options[active] ?? active,
  rows: [
    for (final entry in options.entries)
      menuRow(
        entry.value,
        onPick == null ? null : () => onPick(entry.key),
        active: entry.key == active,
        hint: hint,
      ),
  ],
);

/// A field paired with the verb that consumes it, clearing itself on use --
/// minting a group, a state, a trait. One shape, so three sites are not three
/// stateful widgets.
class CardCompose extends StatefulWidget {
  const CardCompose({
    super.key,
    required this.hint,
    required this.action,
    required this.onSubmit,
    this.width,
    this.refusal,
  });

  final String hint, action;
  final void Function(String value) onSubmit;
  final double? width;

  /// Why the verb is unavailable while the field is empty, in the card's words.
  final String? refusal;

  @override
  State<CardCompose> createState() => _CardComposeState();
}

class _CardComposeState extends State<CardCompose> {
  String _text = '';

  @override
  Widget build(BuildContext context) => cardWrap(context, [
    CardField(
      value: _text,
      hint: widget.hint,
      width: widget.width,
      onChanged: (text) => setState(() => _text = text),
    ),
    namedAction(
      context,
      widget.action,
      hint: _text.trim().isEmpty ? widget.refusal : null,
      onTap: _text.trim().isEmpty
          ? null
          : () {
              widget.onSubmit(_text.trim());
              setState(() => _text = '');
            },
    ),
  ]);
}

/// A colour as a swatch beside the words that name it. The ONE colour control:
/// a frame's ink and a theme's role are the same act, so they are the same
/// widget. An empty value is an inheritance, not a colour.
///
/// ISSUES (8.31, evening): "clicking the gray box did not launch a color picker
/// and typing Blue into the text field did nothing either ... A control that
/// accepts input and does nothing is worse than no control." So the swatch is a
/// button onto a picker, the field reads a NAME as readily as a hex, and text
/// that is not a colour is refused here, in words, instead of being written to
/// the record as though it were one.
Widget colorField(
  BuildContext context,
  String value,
  void Function(String) onChanged, {
  String hint = 'inherited',
}) => ColorField(value: value, onChanged: onChanged, hint: hint);

class ColorField extends StatefulWidget {
  const ColorField({
    super.key,
    required this.value,
    required this.onChanged,
    this.hint = 'inherited',
  });

  final String value, hint;
  final void Function(String) onChanged;

  @override
  State<ColorField> createState() => _ColorFieldState();
}

class _ColorFieldState extends State<ColorField> {
  bool _picking = false;

  /// What the picker OFFERS, as an authored list of colour names -- a text
  /// setting, so a person who wants another palette writes one. The field still
  /// takes any name or hex the reader knows; this is the short way in.
  List<String> _palette(BuildContext context) => [
    for (final word in ChromeScope.of(context).settings.text('card.palette').split(RegExp(r'\s+')))
      if (word.trim().isNotEmpty) word.trim(),
  ];

  Widget _swatch(BuildContext context, Color color, String said, VoidCallback onTap) => Semantics(
    label: said,
    button: true,
    child: Tooltip(
      message: said,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: cardPx(context, 'card.swatch'),
            height: cardPx(context, 'card.swatch'),
            color: color,
          ),
        ),
      ),
    ),
  );

  void _pick(String written) {
    widget.onChanged(written);
    setState(() => _picking = false);
  }

  @override
  Widget build(BuildContext context) {
    final written = widget.value.trim();
    final read = parseColor(written);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _swatch(
              context,
              read ?? ChronoTheme.of(context).hair,
              'Pick a colour',
              () => setState(() => _picking = !_picking),
            ),
            SizedBox(width: cardPx(context, 'card.gap')),
            Flexible(
              child: CardField(
                value: widget.value,
                mono: true,
                hint: widget.hint,
                onChanged: (text) {
                  widget.onChanged(text);
                  setState(() {});
                },
              ),
            ),
          ],
        ),
        if (written.isNotEmpty && read == null)
          cardNote(
            context,
            '"$written" is not a colour. Write a name — blue, dark green,'
            ' rebeccapurple — or a hex like #3f6ea3. Nothing is stored as a'
            ' colour until it reads as one.',
            refusal: true,
          ),
        if (_picking)
          cardWrap(context, [
            for (final name in _palette(context))
              _swatch(
                context,
                parseColor(name) ?? ChronoTheme.of(context).hair,
                name,
                () => _pick(name),
              ),
            namedAction(
              context,
              'Inherit',
              hint: 'No colour of its own — the group and frame cascade speaks.',
              onTap: () => _pick(''),
            ),
          ]),
      ],
    );
  }
}

/// A named text row -- a label and the field that answers it. The commonest
/// shape on any card, spelled once.
Widget cardTextRow(
  BuildContext context,
  String label,
  String value,
  void Function(String) onChanged, {
  String hint = '',
  double? width,
  bool mono = false,
  int lines = 1,
}) => cardRow(
  context,
  label,
  CardField(
    value: value,
    hint: hint,
    width: width,
    mono: mono,
    lines: lines,
    onChanged: onChanged,
  ),
);

/// A named choice row: the vocabulary is the argument, so no site spells a
/// control's shape. "Enum is the enemy" -- the options are data.
/// [options] is label by value, so a site states its vocabulary as data.
Widget cardChoiceRow(
  BuildContext context,
  String label,
  String value,
  Map<String, String> options,
  void Function(String) onChanged,
) => cardRow(
  context,
  label,
  namedChoice(context, '', value, [
    for (final entry in options.entries) (value: entry.key, label: entry.value),
  ], onChanged),
);
