// THE + ROW SAYS THE WHOLE SENTENCE, POINTS INCLUDED (ISSUES 9.2, the horde).
//
// "I have just stapled a horde of todos to a meeting and I see no sigils, no
// items, no zones, no nothing." Every one of the thirteen staples had
// `point: all` on BOTH ends, because the + row writes `defaultPoint` (the whole)
// on each end and offers no point terms -- so the only sentence it can say
// between two objects is "connected to". Don's rulings: staple is our word
// ("anchor" leaves the shipped list); the point vocabulary is never narrowed by
// the extent's current size and includes the whole; object->object defaults to
// point<->point from two settings keys (`start`/`start`; Don's `start`/`end`
// a setting away).

import 'package:chronolog/cards/staple_editor.dart';
import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/core/staples.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the point vocabulary offers the whole, and is not a written list', () {
    expect(
      extentPoints,
      contains(wholePoint),
      reason:
          'ISSUES 9.2: `extentPoints` is `[start, end, midpoint]` -- a closed list in a card '
          'that omits the ruled default point (the whole). Points are read from the object.',
    );
  });

  test('the shipped verb reads "stapled", never "anchor"', () {
    expect(
      stapleKinds.values.any((kind) => kind.label.toLowerCase().contains('stapled')),
      isTrue,
      reason:
          'ISSUES 9.2 (Don: "Staple is our chosen word"): the shipped default verb reads '
          '"is stapled to"; "Anchors a point" is the code\'s word leaking into the hand.',
    );
  });

  test('the default points of a new object-to-object sentence are settings', () {
    final settings = chronologSettings();
    expect(settings.text('edit.newPointNear'), isNotEmpty, reason: 'ISSUES 9.2: the new object\'s point is a settings key');
    expect(settings.text('edit.newPointFar'), isNotEmpty, reason: 'ISSUES 9.2: the far object\'s point is a settings key');
  });

  test('the + row says the whole sentence from the first keystroke', () {
    // WORK ITEM (ISSUES 9.2): `NewSentence` shows "This [verb] [far end]" and
    // writes both ends with the whole; point terms appear only afterwards on the
    // saved row. When the + row carries every term, this test types a far-end
    // name on an object card, picks it, and asserts the written staple's ends
    // carry the settings' default points -- `start`/`start` shipped -- and that
    // choosing the whole on both ends is one click away and reads "connected to".
    fail(
      'ISSUES 9.2: the + row can only say whole<->whole between two objects. Show every term '
      'from the first keystroke with settings-fed default points, then assert the written ends.',
    );
  });
}
