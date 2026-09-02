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
import 'package:flutter/services.dart';

import '../chrome/controls.dart';
import '../chrome/menus.dart';
import '../core/exact.dart';
import '../core/math.dart';
import '../core/object_kinds.dart';
import '../lens/theme.dart';
import '../lens/tunables.dart';
import '../session/settings.dart';
import '../stage/tile.dart';
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
  // How finely a settings number line lands. A rail is not a continuum: it
  // offers this many exact places between the two ends a key states it rides.
  'card.railSteps': '1000',
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
///
/// A REFUSAL IS A THING YOU CAN TOUCH (ISSUES 9.2, Don: "double-clicking an
/// error message should copy it to the clipboard; right now I have no way to
/// interact with them"). Every refusal in every card came through this one call
/// already, so this is where the verbs go and there is no second copy of them.
/// [source] is what the refusal is ABOUT in the person's own vocabulary -- the
/// frame, the pattern, the file, the key -- and it rides with the text onto the
/// clipboard, because a message on its own does not say what it was said of.
/// [others] is what else this surface is refusing right now, so Copy all copies
/// a wall of import warnings in one act instead of forty double-clicks.
Widget cardNote(
  BuildContext context,
  String text, {
  bool refusal = false,
  String? source,
  List<String> others = const [],
}) {
  if (refusal) return Refusal(text: text, source: source, others: others);
  final theme = ChronoTheme.of(context);
  return Container(
    width: double.infinity,
    padding: EdgeInsets.all(cardPx(context, 'card.gap')),
    decoration: BoxDecoration(
      color: theme.paper,
      border: Border(
        left: BorderSide(color: theme.accent, width: ChromeScope.of(context).px('chrome.focusRing')),
      ),
    ),
    child: Text(text, style: bodyStyle(context, color: theme.strong)),
  );
}

/// The refusal text and what it was said of, as ONE piece of writing -- which is
/// what lands on the clipboard, because "DTSTART and DTEND use different time
/// forms" pasted into a message to somebody says nothing about which calendar.
String refusalOnClipboard(String text, String? source) =>
    (source ?? '').trim().isEmpty ? text : '$text\n(about ${source!.trim()})';

/// THE ONE REFUSAL, EVERYWHERE (ISSUES 9.2).
///
/// Refusals were inert on every surface: painted text on a lens with no hit
/// region, a bare `Text` on a card. They are things now, and they wear the same
/// verbs the rest of the surface wears, so nothing about them has to be learned
/// twice:
///
///   * a click SELECTS it -- the ink ring every other selection wears;
///   * a double-click COPIES it, with what it is about;
///   * a right-click offers Copy, Copy all, and Dismiss for this session;
///   * hovering shows the whole of it when the line was truncated.
///
/// Dismissal is FOR THIS SESSION and for this widget only: a refusal is a fact
/// about the document, and a fact does not stop being true because somebody put
/// it away. It comes back the moment the surface says it again.
class Refusal extends StatefulWidget {
  const Refusal({super.key, required this.text, this.source, this.others = const []});

  final String text;

  /// What this refusal is about, in words a person reads -- a frame's title, a
  /// file name, a settings key. Null when the sentence already names it.
  final String? source;

  /// Everything else being refused on this surface right now, for Copy all.
  final List<String> others;

  @override
  State<Refusal> createState() => _RefusalState();
}

class _RefusalState extends State<Refusal> {
  bool _selected = false, _dismissed = false;

  /// A DISMISSAL BELONGS TO THE SENTENCE, NOT TO THE SLOT IT SAT IN. These are
  /// built in a list -- fourteen import warnings, one per row -- and Flutter
  /// reuses the state at each index when the list is replaced. Without this, a
  /// second import would arrive with warnings already put away that nobody had
  /// ever read, and "it comes back the moment the surface says it again" would
  /// be a comment rather than a fact.
  @override
  void didUpdateWidget(Refusal old) {
    super.didUpdateWidget(old);
    if (widget.text == old.text && widget.source == old.source) return;
    setState(() {
      _dismissed = false;
      _selected = false;
    });
  }

  String get _mine => refusalOnClipboard(widget.text, widget.source);

  void _copy(String written) {
    Clipboard.setData(ClipboardData(text: written));
    setState(() => _selected = true);
  }

  List<MenuRow> _rows() => [
    menuRow('Copy', () => _copy(_mine), hint: 'This refusal and what it is about'),
    menuRow(
      widget.others.isEmpty ? 'Copy all' : 'Copy all — ${widget.others.length + 1}',
      widget.others.isEmpty ? null : () => _copy([_mine, ...widget.others].join('\n\n')),
      hint: 'Every refusal this surface is showing',
    ),
    menuRow(
      'Dismiss for this session',
      () => setState(() => _dismissed = true),
      hint: 'It comes back the moment the surface says it again',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    final chrome = ChromeScope.of(context);
    final theme = ChronoTheme.of(context);
    final tone = theme.primary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _selected = !_selected),
        onDoubleTap: () => _copy(_mine),
        onSecondaryTapUp: (details) => showChronoMenu(context, details.globalPosition, _rows()),
        // THE WHOLE TEXT ON HOVER, for the surfaces that truncate: a banner
        // showing three words of a sentence is a refusal you cannot read.
        child: Tooltip(
          message: _mine,
          triggerMode: TooltipTriggerMode.manual,
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.all(cardPx(context, 'card.gap')),
            decoration: BoxDecoration(
              color: theme.paper,
              border: Border(
                left: BorderSide(color: tone, width: chrome.px('chrome.focusRing')),
                top: _ring(theme, chrome),
                right: _ring(theme, chrome),
                bottom: _ring(theme, chrome),
              ),
            ),
            child: Semantics(
              label: 'Refusal: $_mine',
              child: Text(widget.text, style: bodyStyle(context, color: tone)),
            ),
          ),
        ),
      ),
    );
  }

  /// The selection ring, in the palette and the width every other selection on
  /// the surface uses -- and nothing at all when this one is not selected.
  BorderSide _ring(ChronoTheme theme, Chrome chrome) => _selected
      ? BorderSide(
          color: theme.ink.withValues(alpha: chrome.px('selection.ringOpacity')),
          width: chrome.px('selection.ring'),
        )
      : BorderSide.none;
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
    return SizedBox(
      width: widget.width ?? cardPx(context, 'card.fieldWidth'),
      child: TextField(
        controller: _controller,
        maxLines: widget.lines,
        onChanged: widget.onChanged,
        style: widget.mono ? dataStyle(context) : bodyStyle(context),
        // ONE FIELD CHROME (ISSUES 9.2). This class drew the hairline itself and
        // the one-math box drew nothing; both go through `fieldChrome` now.
        decoration: fieldChrome(
          context,
          hint: widget.hint,
          padding: cardPx(context, 'card.gap') / 2,
        ),
      ),
    );
  }
}

// --- The draft contract -----------------------------------------------------

/// ONE CONTRACT FOR EVERY CARD THAT HOLDS A DRAFT (ISSUES 9.1).
///
/// Don named and coloured a frame and the journal held no `New frame`
/// transaction: "the new-frame card can discard an authored draft with nothing
/// said". The object card had already earned the contract -- a dirty mark, the
/// three verbs once changes exist, and an X that does whatever `card.closeVerb`
/// names -- and the frame card was carrying a bare close beside it. Two cards
/// keeping two promises about the same act is how one of them breaks, so the
/// promise lives here and both cards reference it.
///
/// A NAMED, TOUCHED DRAFT NEVER DIES SILENTLY, whatever door it leaves by: the
/// X, the tab's ×, the tile going away underneath. [keep] is what happens when
/// the setting names a verb no card offers -- the work is kept and the refusal
/// is said, because a draft must not die to a typo in a settings file.
class CardDraft {
  const CardDraft({
    required this.save,
    required this.apply,
    required this.discard,
    required this.keep,
  });

  final VoidCallback save, apply, discard, keep;

  Map<String, VoidCallback> get verbs => {'save': save, 'apply': apply, 'discard': discard};

  /// What the X does, by NAME. The verbs are data and the setting picks one.
  void closeAsNamed(Settings? settings) {
    final named = (settings?.text('card.closeVerb') ?? '').trim().toLowerCase();
    final verb = verbs[named];
    if (verb == null) {
      settings?.refusals.add(
        'card.closeVerb: "$named" is not a verb this card offers'
        ' (${verbs.keys.join(', ')}). The card closed and kept its work.',
      );
      return keep();
    }
    verb();
  }
}

/// What each verb promises, in one wording every card says it in.
const Map<String, String> draftVerbSays = {
  'Save': 'Writes the document and closes this card.',
  'Apply': 'Writes the document and leaves this card open.',
  'Discard': 'Throws this edit session away as its own undo entry. Nothing asks twice.',
};

/// The three verbs, in the card footer. Shown once a draft has been touched --
/// before that there is nothing to write, keep or throw away.
List<Widget> draftActions(BuildContext context, CardDraft draft) => [
  for (final (label, act) in [
    ('Save', draft.save),
    ('Apply', draft.apply),
    ('Discard', draft.discard),
  ])
    namedAction(context, label, hint: draftVerbSays[label], onTap: act),
];

// --- Doors ------------------------------------------------------------------

/// One door: what it is called, why you would take it, and the card it opens.
typedef CardDoor = ({String label, String says, TileSpec Function(CardFactory) opens});

CardDoor cardDoor(String label, String says, TileSpec Function(CardFactory) opens) =>
    (label: label, says: says, opens: opens);

/// THE WAYS ONWARD (ISSUES 9.1, Don's card-graph test and its dead-end band:
/// "moving around the app must be seamless, so every card offers at least one
/// way on"). A card states which doors it wears and nothing else -- where they
/// are drawn, how they are spelled and what happens when there is no host to
/// open anything into is settled once, here.
///
/// Outside a host there is nowhere to open a card TO, so the run draws nothing
/// rather than throwing: an instrument pumped on its own is still an
/// instrument.
Widget cardDoors(BuildContext context, List<CardDoor> doors) {
  final host = CardHost.maybeOf(context);
  if (host == null || doors.isEmpty) return const SizedBox.shrink();
  return cardWrap(context, [
    for (final door in doors)
      namedAction(
        context,
        door.label,
        hint: door.says,
        onTap: () => host.factory.open(door.opens(host.factory)),
      ),
  ]);
}

/// The doors every list of records owes: "every list of things offers to make
/// the thing" (ISSUES 8.31, restated 9.1 for the frames drop). Authoring an
/// object is a DOCUMENT act, not a lens act -- so a blank object card is
/// reachable from the surfaces that hold objects, with its placement region
/// empty and waiting to be said.
List<CardDoor> mintingDoors() => [
  for (final kind in objectKinds.entries)
    cardDoor(
      'New ${kind.value.label.toLowerCase()}',
      'Opens a blank card with its placement region empty and waiting to be '
          'said. Nothing places it until a staple sentence does.',
      (factory) => factory.newObjectCard(kind.key),
    ),
];

/// The one create-frame affordance, shared by every surface that lists frames.
CardDoor newFrameDoor() => cardDoor(
  'New frame',
  'Mints a frame. What it is — structure, grouping, statehood — is authored on '
      'the card that opens.',
  (factory) => factory.newFrameCard(),
);

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
///
/// A REFUSAL IS THE MENU'S ONE SENTENCE (ISSUES 9.1, Don's screenshot walk):
/// "The menus do not render options or the sentence syntax." The hint was
/// stamped onto EVERY row, so a disabled six-row menu read as the same sentence
/// six times with the option labels drowned beside it -- and the sentence, set
/// on one line in a fixed-width menu, overflowed into the striped banner. The
/// menu refuses ONCE, under its rows, in a paragraph that wraps: the rows keep
/// their own words, and the reason is said where a reason belongs.
Widget cardMenu(
  BuildContext context,
  String active,
  Map<String, String> options,
  void Function(String)? onPick, {
  String? hint,
}) {
  final refusal = onPick == null ? hint : null;
  return ChronoMenu(
    label: options[active] ?? active,
    rows: [
      for (final entry in options.entries)
        menuRow(
          entry.value,
          onPick == null ? null : () => onPick(entry.key),
          active: entry.key == active,
        ),
    ],
    body: refusal == null
        ? null
        : (context, close) => Padding(
            padding: EdgeInsets.all(cardPx(context, 'card.gap')),
            // The paragraph WRAPS. A menu is a fixed width and a sentence is
            // however long it needs to be; laying one along a row is what put
            // the refusal off the edge of its own panel.
            child: Text(
              refusal,
              softWrap: true,
              style: labelStyle(context, color: ChronoTheme.of(context).primary),
            ),
          ),
  );
}

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
