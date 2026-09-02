// NEW, OPEN, DELETE: THE DOCUMENT HAS DOORS (ISSUES 9.2, Don's first report).
//
// "No clear mechanism to delete all the old data and start a new chronolog --
// I had to follow the path and delete the directory." Don's ruling: New is a
// fresh document at a new location (old files left in place) by default; Open
// reaches another chronolog ("sometimes it makes sense to have two chronologs");
// Delete-all is its own door behind a type-the-word confirmation.

import 'package:chronolog/cards/document_card.dart';
import 'package:chronolog/core/document.dart';
import 'package:flutter_test/flutter_test.dart';

import '../cards/harness.dart';
import '../cards/object_harness.dart';

void main() {
  testWidgets('the document card offers New, Open and Delete-all', (tester) async {
    final bench = (await tester.runAsync(() => openCards(createEmptyWorkspaceDocument())))!;
    await pumpCard(tester, bench.chrome, const DocumentCard());
    expect(
      find.textContaining(RegExp('new chronolog|new document', caseSensitive: false)),
      findsWidgets,
      reason: 'ISSUES 9.2: no door mints an empty document; `relocate` and `replaceDocument` exist unused',
    );
    expect(
      find.textContaining(RegExp(r'\bopen\b', caseSensitive: false)),
      findsWidgets,
      reason: 'ISSUES 9.2: no door opens a different location\'s chronolog',
    );
    expect(
      find.textContaining(RegExp('delete all', caseSensitive: false)),
      findsWidgets,
      reason:
          'ISSUES 9.2 (Don: option b behind a type-the-word popup): a full-deletion door, '
          'explicitly destructive, never silent.',
    );
  });

  test('delete-all requires the typed word and leaves nothing behind', () {
    fail(
      'ISSUES 9.2: no deletion door exists. When it does: the confirmation is typing the '
      'word; on confirmation the snapshot and journal at the data root are gone and the app '
      'stands on an empty document; on any other input nothing changes.',
    );
  });
}
