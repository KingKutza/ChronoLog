// THE SENTENCES REGION.
//
// ISSUES (9.1, Don's screenshot walk of an event card): "SENTENCES ARE NOT
// EXPOSED. Pulling up an event gives no clear way to add or edit a sentence."
// Finding by finding, and each one is a law here:
//
//   (a) "There is no + to add a sentence. Nor is there a sentence here. There
//       is a weird literal box and drop downs that don't render." So a
//       connection IS a sentence: a run of authored TERMS, read left to right,
//       each one a word you can say again.
//   (c) The Holds / Held-by picker pair "should not be here, it is not a part
//       of the design". Containment is a staple, so it is a sentence in this
//       region like every other -- there is no second widget for it, and
//       nothing here authors a containment RELATION any more.
//   (d) The connect-to typeahead "draws you out of the sentence system". So
//       create-by-typing is folded INTO the sentence: the far end is a term,
//       typing a name nothing wears offers to make it, and the offer is made
//       where the sentence is being said rather than beside it.
//   (7)/(17) "Every end of a staple is an authored term of the sentence, and a
//       term you can read but not re-say makes the row display, not authoring."
//       So re-pointing a placement's frame end RE-FRAMES the object: the
//       coordinate comes along, translated through the two frames' own laws, or
//       the re-saying is REFUSED IN WORDS and nothing moves.
//
// THE VERB IS AUTHORED (ISSUES 9.1, and "staple is metal", 8.31: verbs carry
// zero engine meaning -- no mapping is no enum). The old picker steered every
// new connection to one hardcoded word. Here the verb is a term like any other:
// the offers are the words THIS DOCUMENT's staples already wear, then the words
// the substrate registers a derivation for, and any word at all may be typed. A
// word nothing registers is legal and the row says what it costs -- the
// sentence connects and moves nothing.

import 'package:flutter/material.dart';

import '../chrome/controls.dart';
import '../core/records.dart';
import '../core/staples.dart';
import '../lens/theme.dart';
import 'card_chrome.dart';

/// The words a verb term offers: what this document already says, then what the
/// substrate registers a derivation for. Derived, in that order, so the first
/// offer is a fact about the workspace rather than a word chosen in this file.
List<String> verbOffers(Document document) {
  final said = <String>[];
  for (final relation in document.relations.values) {
    final kind = relation.kind;
    if (relation.isStaple && kind != null && kind.isNotEmpty && !said.contains(kind)) {
      said.add(kind);
    }
  }
  return [
    ...said,
    for (final kind in stapleKinds.keys)
      if (!said.contains(kind)) kind,
  ];
}

/// What a verb costs, in words. A registered word selects a derivation; an
/// authored one selects none, which is legal and is SAID rather than silently
/// doing nothing.
String verbSays(String verb) {
  final registered = stapleKinds[verb];
  if (registered == null) {
    return '"$verb" is a word you wrote. Nothing in the substrate reads it, so '
        'this sentence says the two points are one and moves nothing.';
  }
  return '${registered.label}.'
      '${registered.anchors ? ' It places this object.' : ' It does not place this object.'}';
}

/// A word in a sentence, and the one way any word in any sentence is re-said.
///
/// The term reads as what it is CALLED. Saying it again opens the offers below
/// it: what the document already holds, narrowed by what is typed, plus the
/// offer to MAKE what nothing is called yet. Where the term names a record it
/// also carries the way to that record's own card, because "a staple you can
/// only see from one side is half a record" and a term you can follow but not
/// re-say is display rather than authoring.
class SentenceTerm extends StatefulWidget {
  const SentenceTerm({
    super.key,
    required this.said,
    required this.offers,
    this.onSaid,
    this.refusal,
    this.hint = '',
    this.onOpen,
    this.onCreate,
    this.open = false,
    this.strong = false,
  });

  /// What the term reads as now.
  final String said;

  /// What this term may become, narrowed by what has been typed so far.
  final List<({String value, String label})> Function(String typed) offers;

  /// Says it again. Null means this term cannot be re-said, and [refusal] says
  /// why -- in words, at the term, never as a greyed-out silence.
  final void Function(String value)? onSaid;

  final String? refusal;
  final String hint;

  /// Follows the term to the record it names.
  final VoidCallback? onOpen;

  /// Makes what nothing is called yet, by the typed name.
  final void Function(String typed)? onCreate;

  /// Starts open -- the term of a sentence that is still being said.
  final bool open;

  /// Reads as the sentence's own subject rather than as one of its words.
  final bool strong;

  @override
  State<SentenceTerm> createState() => _SentenceTermState();
}

class _SentenceTermState extends State<SentenceTerm> {
  late bool _saying = widget.open;
  String _typed = '';

  @override
  Widget build(BuildContext context) {
    final theme = ChronoTheme.of(context);
    final offers = _saying ? widget.offers(_typed) : const <({String value, String label})>[];
    final typed = _typed.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        cardWrap(context, [
          // THE WORD IS THE LINK where it names a record: "a staple you can only
          // see from one side is half a record" (8.20), and following a term to
          // the thing it names is the older promise. Where it names no record --
          // a verb, a point of an extent -- the word IS the re-saying, because
          // there is nowhere else for it to lead.
          if (widget.said.isNotEmpty)
            namedAction(
              context,
              widget.said,
              hint: widget.onOpen != null
                  ? 'Opens what this word names, in its own card.'
                  : (widget.onSaid == null
                        ? (widget.refusal ?? 'This word is not authored here.')
                        : 'Say this again.'),
              onTap: widget.onOpen ??
                  (widget.onSaid == null ? null : () => setState(() => _saying = !_saying)),
            ),
          if (widget.said.isEmpty && widget.onSaid != null)
            namedAction(
              context,
              'Say it',
              glyph: '…',
              hint: 'This word has not been said yet.',
              onTap: () => setState(() => _saying = !_saying),
            ),
          // EVERY TERM CAN BE SAID AGAIN (ISSUES 9.1). A term you can read but
          // not re-say makes the row display rather than authoring -- so where
          // the word itself leads somewhere, this is the door that re-says it.
          if (widget.onOpen != null && widget.said.isNotEmpty)
            namedAction(
              context,
              'Say ${widget.said} again',
              glyph: '✎',
              hint: widget.onSaid == null
                  ? (widget.refusal ?? 'This word is not authored here.')
                  : 'Points this end at something else, and carries what it says along.',
              onTap: widget.onSaid == null ? null : () => setState(() => _saying = !_saying),
            ),
        ]),
        if (_saying && widget.onSaid != null)
          Padding(
            padding: EdgeInsets.only(left: cardPx(context, 'card.gap')),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                CardField(
                  value: _typed,
                  hint: widget.hint,
                  onChanged: (text) => setState(() => _typed = text),
                ),
                cardWrap(context, [
                  for (final offer in offers)
                    namedAction(
                      context,
                      offer.label,
                      onTap: () {
                        widget.onSaid!(offer.value);
                        setState(() {
                          _typed = '';
                          _saying = false;
                        });
                      },
                    ),
                  // A NAME NOTHING WEARS IS AN OFFER, said inside the sentence
                  // rather than in a widget beside it.
                  if (offers.isEmpty && typed.isNotEmpty && widget.onCreate == null)
                    namedAction(
                      context,
                      'Say "$typed"',
                      hint: 'Any word may be said here.',
                      onTap: () {
                        widget.onSaid!(typed);
                        setState(() {
                          _typed = '';
                          _saying = false;
                        });
                      },
                    ),
                  if (typed.isNotEmpty && widget.onCreate != null) ...[
                    if (offers.isEmpty)
                      Text('Nothing here is called that.', style: labelStyle(context)),
                    namedAction(
                      context,
                      'Create "$typed"…',
                      hint: 'Makes it, says it here, and opens its own card.',
                      onTap: () {
                        widget.onCreate!(typed);
                        setState(() {
                          _typed = '';
                          _saying = false;
                        });
                      },
                    ),
                  ],
                ]),
                if (widget.refusal != null)
                  Text(
                    widget.refusal!,
                    style: labelStyle(context, color: theme.accent),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
