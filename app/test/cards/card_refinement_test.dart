// THE CARD SAYS SENTENCES, ONE LINE EACH, AND EDITS EVERY TERM (ISSUES 9.2).
//
// Don's morning on the cards: "the interface on sentences is abysmal -- they
// don't form sentences" (and: "it works, which is more than could be said for
// any previous system"); "the staple cards are so tall that it can be
// overwhelming"; "an ultra long error message about no start or no end and how
// this is okay"; "I don't see a clear way on an event to edit its weight";
// "could it be written as one one-math formula, colour-coded by source";
// "adding an end staple did not adjust the end and duration"; "changing the
// duration's unit keeps the count"; "if I type the name of a note, can I make a
// note?"; "this todo starts at that one's END" on a completed todo -- the done
// instant is not a nameable point; frame-to-frame sentences (time travel) have
// no authoring path.

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a sentence row at rest is one line of prose; the like fold with a count', () {
    fail(
      'ISSUES 9.2: a row is five to eight lines (terms, refusal, coordinate field + help, '
      'fuzziness, rule, unsay) and reads as a chain of pickers in key-words. At rest: one prose '
      'line per sentence, one open row at a time, like sentences folded with a count. Assert an '
      'object with 200 staples renders its sentences region within a screen, two clicks to any.',
    );
  });

  test('the extent note is one line, and affiliations are not contests in it', () {
    fail(
      'ISSUES 9.2: "Nothing says when it ends, which is a legal thing for a record to say" plus '
      'one sentence per whole-ended staple. Say only what is known -- "Starts X. Ends Y." or '
      '"No start said. No end said." -- and show a real contest beside the sentence that caused it.',
    );
  });

  test('the object\'s own weight is an editable term in a composed, colour-coded formula', () {
    fail(
      'ISSUES 9.2: the Display weight row is read-only prose. One line -- base x frame terms -- '
      'each term inked in its frame\'s colour, hover naming the frame, the object\'s own term the '
      'editable one, validated by `validateWeightFormula`. Assert the line and the edit.',
    );
  });

  test('the Duration row shows the derived magnitude when both ends are anchored', () {
    fail(
      'ISSUES 9.2: the row reads the authored `event.duration` even when a start placement and '
      'an end anchor derive the magnitude. Show the derived value labelled as derived, the '
      'authored one as overridden; assert against a seeded start/end pair.',
    );
  });

  test('changing a duration\'s unit keeps the absolute duration, through the frame\'s law', () {
    fail(
      'ISSUES 9.2: `put(amount, name)` carries the count across units. 90 minutes -> hours is '
      '1.5 hours via `unitsPer` of the governing law (a 23-hour day converts as that frame says). '
      'Audit every unit menu beside a magnitude.',
    );
  });

  test('the create door offers every registered kind, not only a frame', () {
    fail(
      'ISSUES 9.2: a name nothing wears becomes a group frame, never a note. Offer "New <kind> '
      '<name>" for every `objectKinds` entry (generative) and "New frame <name>"; a created '
      'object opens in its own card, stapled by the sentence being said.',
    );
  });

  test('a state staple with an instant gives the object a point named by that frame', () {
    fail(
      'ISSUES 9.2 (Don: the follow-up starts at the done todo\'s END): a todo is zero-duration, '
      'so end == start; the completion instant lives on the Done staple\'s `at` and no sentence '
      'can name it. Every state staple with an instant yields a point named by its frame '
      '("the start of this is the DONE of that"); assert it resolves.',
    );
  });

  test('the frame card has a sentences region with the frame as the near end', () {
    fail(
      'ISSUES 9.2: no GUI path authors a frame-to-frame sentence ("10:00 here is 9:30 on Wall '
      'Time"), so no time-travel frame can be made by hand. The frame card grows the object '
      'card\'s sentences region; assert a correspondence staple can be said and projects.',
    );
  });

  test('the frame card\'s weight field reads as an equation, and In Strategic melts into it', () {
    fail(
      'ISSUES 9.2: the weight field was invisible (no border) and read as a readout; the '
      '"In Strategic" three-way is an enum the weight formula already expresses (promote = '
      'w * landmark, demote = w * 0); Zone fill belongs in the trait bundle beside `busy`.',
    );
  });
}
