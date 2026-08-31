// A REFUSAL IS NEWS, so it has to arrive like news.
//
// ISSUES (8.31): "a refusal pushed into settings.refusals does not notify
// listeners -- the document card shows a refused move on its next rebuild rather
// than instantly." Every other channel in the settings layer announces itself:
// `set`, `setText`, `reset` and `applyJson` all invalidate and notify. The
// refusals list is the one place a caller writes into and nobody hears, and the
// cards that display refusals (`document_card.dart`, `settings_card.dart`) read
// it on their next build for reasons of their own.
//
// The property, not the site: whatever pushes a refusal, the listeners hear it.

import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/session/settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every way the program pushes a refusal into the settings layer, as the app
/// itself spells them (`app.dart` uses both `onRefusal: settings.refusals.add`
/// and a direct `add`; `applyJson` collects its own).
final Map<String, void Function(Settings settings, String line)> pushes = {
  'the journal report channel (app.dart onRefusal)': (settings, line) =>
      settings.refusals.add(line),
  'a refused save location (app.dart document.saveAt)': (settings, line) =>
      settings.refusals.add('document.saveAt: $line'),
};

void main() {
  test('a refusal pushed into settings.refusals notifies listeners', () {
    for (final entry in pushes.entries) {
      final settings = chronologSettings();
      var beats = 0;
      settings.addListener(() => beats += 1);
      entry.value(settings, 'that location is occupied');
      expect(
        beats,
        greaterThan(0),
        reason:
            'ISSUES (8.31): "a refusal pushed into settings.refusals does not notify '
            'listeners" — via ${entry.key}, the card cannot update instantly because '
            'nothing announced the refusal.',
      );
      expect(settings.refusals, isNotEmpty, reason: 'and it was recorded at all');
    }
  });

  test('a refusal collected by applyJson notifies too, and reads back', () {
    final settings = chronologSettings();
    var beats = 0;
    settings.addListener(() => beats += 1);
    // A key the settings layer cannot evaluate: refused, kept out of effect, and
    // reported. This path already ends in `_invalidate`, so it is the control
    // case -- the one that proves the listener wiring itself is sound.
    settings.applyJson({'card.pad': 'not arithmetic at all'});
    expect(settings.refusals, isNotEmpty);
    expect(beats, greaterThan(0));
  });
}
