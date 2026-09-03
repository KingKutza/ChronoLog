// The document, settings, theme, boundary and frames-browser cards.
//
// Generation is seeded, so nothing here asserts an arbitrary fact: the counts
// are the generator's own and the properties hold for any of them. Most cases
// take the spec seed; the two newest take `runSeed`, a fresh seed each run that
// the failure prints back, so a shape only some arrangements have is found
// rather than merely never generated.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:chronolog/cards/boundary_series_editor.dart';
import 'package:chronolog/cards/document_card.dart';
import 'package:chronolog/cards/frames_browser.dart';
import 'package:chronolog/cards/settings_card.dart';
import 'package:chronolog/cards/theme_card.dart';
import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/eras.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/lens/theme.dart';
import 'package:chronolog/session/files.dart';
import 'package:chronolog/session/lens_catalog.dart';
import 'package:chronolog/store/data_dir.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/corpus.dart';
import '../store/harness.dart';
import 'harness.dart';
import 'object_harness.dart';

/// A synthetic calendar. Every value is generated: no real calendar fact
/// reaches this repository.
String icsFor(Random random, int count) => [
  'BEGIN:VCALENDAR',
  'VERSION:2.0',
  'PRODID:-//chronolog spec//EN',
  for (var index = 0; index < count; index++) ...[
    'BEGIN:VEVENT',
    'UID:spec-$index',
    'DTSTART:202603${(1 + random.nextInt(27)).toString().padLeft(2, '0')}T090000Z',
    'DURATION:PT1H',
    'SUMMARY:Generated ${index + 1}',
    'END:VEVENT',
  ],
  'END:VCALENDAR',
  '',
].join('\r\n');

Document _withWorkFrame() => createEmptyWorkspaceDocument().put(
  'frames',
  'frame:work',
  const Frame(id: 'frame:work', title: 'Work', traits: ['set', 'calendar']),
);

/// The run's seed: `CHRONOLOG_SEED` when set, else the clock; every reason
/// that varies with it names it.
final int runSeed =
    int.tryParse(Platform.environment['CHRONOLOG_SEED'] ?? '') ??
    DateTime.now().microsecondsSinceEpoch;

/// A widget wearing exactly these words as its label -- the action row and
/// never the text field a person typed them into.
Finder labelled(String words) =>
    find.byWidgetPredicate((widget) => widget is Text && widget.data == words);

void main() {
  group('the document card', () {
    for (final seed in seeds(3)) {
      test('an ICS import is exactly one undoable entry (seed $seed)', () async {
        final random = Random(seed);
        final count = 2 + random.nextInt(5);
        final bench = await openCards(createEmptyWorkspaceDocument());
        final before = bench.editor.history.length;

        final result = importIcsText(bench.editor, icsFor(random, count));

        expect(result.events.length, count);
        expect(bench.editor.history.length, before + 1);
        expect(bench.editor.document.events.length, count);
        expect(bench.editor.undo(), isTrue);
        expect(bench.editor.document.events, isEmpty);
      });
    }

    testWidgets('the card names the document, offers Save now, and shows where ICS crosses', (
      tester,
    ) async {
      final bench = await openCards(createEmptyWorkspaceDocument(title: 'Field notes'));
      await pumpCard(tester, cardChrome(bench.editor), const DocumentCard(root: 'nowhere'));
      expect(find.text('Save now'), findsOneWidget);
      expect(find.textContaining('Field notes'), findsWidgets);
      await tapPart(tester, 'Storage, boundary and layouts');
      expect(
        fieldHinted('nowhere'),
        findsWidgets,
        reason: 'both authored locations -- where it saves, where calendars are -- '
            'hint the data root they fall back to',
      );
    });

    // NOT BUILT (ISSUES.md, 8.31): "a card tile narrower than about 200px
    // overflows its RenderFlex -- cardRow pairs the fixed card.labelWidth (124)
    // with a Flexible". The stage hands a card whatever width is left over, so
    // every width a tile can produce is a width the card must survive. The
    // typing sweep dodged this by zooming its tile; under the NO SKIPS ruling
    // (ISSUES.md, 8.31) the dodged failure gets its own light, and it stays red
    // until the card layout is as space-driven as the bars are.
    testWidgets('a card lays out at every width a tile can hand it', (tester) async {
      final bench = await openCards(createEmptyWorkspaceDocument(title: 'Narrow'));
      for (final width in [600.0, 400.0, 240.0, 180.0, 120.0]) {
        await pumpCard(
          tester,
          cardChrome(bench.editor),
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: const DocumentCard(root: 'nowhere')),
          ),
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'the document card overflowed at ${width}px of tile width',
        );
      }
    });

    // ONE RESOLVER, TWO ARITIES. An unwritten path is the portable fallback; a
    // written one is itself, whitespace and all removed. Generated, so the
    // property is not three remembered strings.
    test('an unwritten path is the fallback; a written one is itself, trimmed', () {
      for (final seed in seeds(24)) {
        final random = Random(seed);
        final blank = ' ' * random.nextInt(4);
        expect(authoredPath(blank, 'C:/app'), 'C:/app');
        expect(authoredPath(null, 'C:/app'), 'C:/app');
        final written = 'D:/feeds/${random.nextInt(1 << 20).toRadixString(36)}';
        expect(authoredPath('$blank$written$blank', 'C:/app'), written);
      }
    });

    // ICS LOCATIONS ARE A LIST (Don, 8.31: "only one such location"). The
    // property is over generated lists of any length, with blank lines and
    // padding thrown in, because a person's typing carries both.
    test('ICS locations are every non-blank line, in order, and never one path', () {
      for (final seed in seeds(24)) {
        final random = Random(seed);
        final wanted = [
          for (var index = 0; index < random.nextInt(6); index += 1)
            'D:/feeds/${random.nextInt(1 << 20).toRadixString(36)}',
        ];
        final typed = [
          for (final path in wanted) ...[
            if (random.nextBool()) ' ' * random.nextInt(3),
            '${' ' * random.nextInt(3)}$path${' ' * random.nextInt(3)}',
          ],
        ].join(random.nextBool() ? '\r\n' : '\n');
        expect(
          authoredPaths(typed, 'C:/app'),
          wanted.isEmpty ? ['C:/app'] : wanted,
          reason: 'every line is a location and no line is lost',
        );
      }
    });

    testWidgets('the card offers a save location, and a picked folder becomes the setting', (
      tester,
    ) async {
      final bench = await openCards(createEmptyWorkspaceDocument(title: 'Field notes'));
      final chrome = cardChrome(bench.editor);
      await pumpCard(
        tester,
        chrome,
        DocumentCard(
          root: 'nowhere',
          // A dialog that ANSWERS. No dialog is raised in a spec; the seam is.
          picker: const AnsweringFilePicker('D:/elsewhere/chronolog.chronolog'),
        ),
      );
      // The save location is on the PRIMARY path, not behind the fold: "I don't
      // appear to be able to set a save location" is a discoverability defect.
      expect(fieldHinted('nowhere'), findsWidgets);
      expect(chrome.settings.text('document.saveAt'), isEmpty, reason: 'beside the app by default');
      await tapText(tester, 'Choose a folder…');
      expect(
        chrome.settings.text('document.saveAt'),
        parentDirectory('D:/elsewhere/chronolog.chronolog'),
        reason: 'the chosen FILE names the folder the document lives in',
      );
      // And back: an empty path is the portable default, reachable in one tap.
      await tapText(tester, 'Beside the app');
      expect(chrome.settings.text('document.saveAt'), isEmpty);
    });

    testWidgets('every ICS location the author writes is offered, not just the first', (
      tester,
    ) async {
      // SYNCHRONOUS I/O ONLY. A widget test runs in a fake-async zone, where an
      // awaited real file operation never completes; the listing this exercises
      // is synchronous anyway, so the setup is too.
      final root = Directory.systemTemp.createTempSync('chronolog-ics-locations-');
      addTearDown(() {
        try {
          root.deleteSync(recursive: true);
        } on FileSystemException {
          // A directory the platform is still holding is cleanup, not a result.
        }
      });
      final places = <String>[];
      for (final area in ['work', 'home', 'shared']) {
        final folder = Directory(storePath(root.path, area))..createSync(recursive: true);
        File(storePath(folder.path, '$area.ics')).writeAsStringSync('');
        places.add(folder.path);
      }
      final bench = await openCards(createEmptyWorkspaceDocument(title: 'Many feeds'));
      final chrome = cardChrome(bench.editor);
      chrome.settings.setText('document.icsPaths', places.join('\n'));
      await pumpCard(tester, chrome, DocumentCard(root: root.path));
      await tapPart(tester, 'Storage, boundary and layouts');
      for (final area in ['work', 'home', 'shared']) {
        expect(
          find.text('Import $area.ics'),
          findsOneWidget,
          reason: 'the $area location is a location like any other',
        );
      }
    });

    test('a folder lists only its .ics files; a path that is not one lists nothing', () async {
      final root = await tempRoot('ics-path');
      addTearDown(() => removeRoot(root));
      for (final name in ['b.ics', 'a.ics', 'notes.md']) {
        await File(storePath(root.path, name)).writeAsString('');
      }
      expect(
        [for (final path in icsFilesIn(root.path)) path.split(Platform.pathSeparator).last],
        ['a.ics', 'b.ics'],
      );
      expect(icsFilesIn(storePath(root.path, 'a.ics')), isEmpty);
    });

    // THE DOOR, NOT THE API (found 9.3). Named views and layout presets are one
    // record kind, and `Stage.savePreset` / `applyPreset` carry the view state
    // only when the book is handed in. session/named_views_test.dart drives
    // that API and hands `views:` in EXPLICITLY, so a caller that omits the
    // optional parameter is invisible to it -- and this card did exactly that:
    // a preset saved here came back as the boxes with every projection silently
    // dropped. So this case walks the door the hand walks -- author a tile, save
    // from the card, scramble, apply from the card -- and asks for what the tile
    // SAID, never where the boxes went. The lens, the projection and the lens's
    // own key are drawn from the seed: the property is that WHATEVER was said
    // comes back, not that one remembered arrangement does.
    testWidgets('a layout saved from the card brings back what its tile looked through', (
      tester,
    ) async {
      final random = Random(runSeed);
      final bench = await openCards(_withWorkFrame());
      final chrome = cardChrome(bench.editor);
      final lenses = lensCatalog.keys.toList();
      final authoredLens = lenses[random.nextInt(lenses.length)];
      final otherLens = lenses[(lenses.indexOf(authoredLens) + 1 + random.nextInt(lenses.length - 1)) %
          lenses.length];
      final days = '${1 + random.nextInt(60)}';
      final tile = chrome.views.of('view:1');
      tile.lensId = authoredLens;
      tile.selection.toggle('frame:work');
      tile.source = 'Work';
      tile.write('days', days);
      // The snapshot is a COPY, as a file would hold it: `said` hands out live
      // maps, and a snapshot that aliases the tile proves nothing about it.
      final said = jsonDecode(jsonEncode(tile.said));
      final name = 'desk-${runSeed.toRadixString(36)}';

      await pumpCard(tester, chrome, const DocumentCard(root: 'nowhere'));
      await tapPart(tester, 'Storage, boundary and layouts');
      await tester.enterText(fieldHinted('name this arrangement'), name);
      await tester.pumpAndSettle();
      await tapText(tester, 'Save layout');
      expect(
        chrome.stage.presets.keys,
        contains(name),
        reason: 'seed $runSeed: the card saved the arrangement under the name typed',
      );

      // Scramble the lens and the projection, so nothing comes back by accident.
      tile.lensId = otherLens;
      tile.selection.toggle('frame:work');
      tile.source = '';
      expect(
        tile.said,
        isNot(equals(said)),
        reason: 'seed $runSeed: the scramble changed what the tile said, or the case proves nothing',
      );
      await tester.pumpAndSettle();

      // Apply FROM THE CARD: its own row for the preset, not the Stage API.
      final row = labelled(name);
      expect(row, findsOneWidget, reason: 'seed $runSeed: the saved layout is offered as a row in the fold');
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row, warnIfMissed: false);
      await tester.pumpAndSettle();

      final shown = chrome.views.of('view:1');
      expect(
        shown.lensId,
        equals(authoredLens),
        reason:
            'seed $runSeed: found 9.3 -- the card called savePreset/applyPreset without the book, so '
            'the tile stayed on "$otherLens" while the boxes came back',
      );
      expect(
        shown.source,
        equals('Work'),
        reason: 'seed $runSeed: the projection is view state and rides with the arrangement',
      );
      expect(
        shown.said,
        equals(said),
        reason: 'seed $runSeed: everything the tile said, byte for byte, and not merely the layout boxes',
      );
    });

    // A SAVED LAYOUT IS A RECORD, NOT A WINDOW ONTO THE LIVE TILE (found 9.3,
    // writing the case above). `ViewState.toJson` hands out `'view': view` --
    // the tile's own map, not a copy -- and `Stage.savePreset` stores that
    // `said` as the preset. So until a restart's JSON round trip happens to
    // freeze it, every later edit to the tile's lens keys edits the saved
    // preset too, and applying it brings back what the tile says NOW rather
    // than what it said when the person saved. session/named_views_test.dart
    // cannot see this: `reloaded()` round-trips the stage through JSON between
    // save and apply. This is the in-session road -- save, change, apply -- and
    // it stays red until a preset is written as a copy.
    testWidgets('a layout saved from the card is not rewritten by later edits to the tile', (
      tester,
    ) async {
      final random = Random(runSeed);
      final bench = await openCards(_withWorkFrame());
      final chrome = cardChrome(bench.editor);
      final lenses = lensCatalog.keys.toList();
      final tile = chrome.views.of('view:1');
      tile.lensId = lenses[random.nextInt(lenses.length)];
      final savedDays = '${1 + random.nextInt(60)}';
      final laterDays = '${61 + random.nextInt(60)}';
      tile.write('days', savedDays);
      final name = 'desk-${runSeed.toRadixString(36)}';

      await pumpCard(tester, chrome, const DocumentCard(root: 'nowhere'));
      await tapPart(tester, 'Storage, boundary and layouts');
      await tester.enterText(fieldHinted('name this arrangement'), name);
      await tester.pumpAndSettle();
      await tapText(tester, 'Save layout');
      final record = jsonDecode(jsonEncode(chrome.stage.presets[name]!.views['view:1']));
      expect(record, isNotNull, reason: 'seed $runSeed: the preset carries the tile\'s view state');

      // A person keeps working: the tile's lens key changes after the save.
      tile.write('days', laterDays);
      expect(
        chrome.stage.presets[name]!.views['view:1'],
        equals(record),
        reason:
            'seed $runSeed: found 9.3 -- the saved preset changed when the tile did. '
            '`ViewState.toJson` hands out the live `view` map and `savePreset` keeps it, so '
            'the record aliases the tile until a JSON round trip copies it.',
      );
      await tester.pumpAndSettle();
      final row = labelled(name);
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(
        chrome.views.of('view:1').view['days'],
        equals(savedDays),
        reason: 'seed $runSeed: applying brings back what was SAVED ($savedDays), not what the tile says now',
      );
    });
  });

  group('the settings card', () {
    testWidgets('a setting reads as words; its expression is arcana, revealed on ask', (
      tester,
    ) async {
      await pumpCard(tester, cardChrome(null), const SettingsCard());
      await tester.enterText(fieldHinted('Find a setting'), 'markWidth');
      await tester.pumpAndSettle();

      expect(find.text('Mark width'), findsOneWidget);
      expect(find.text('capacity.markWidth'), findsNothing);

      await tapText(tester, 'ƒ');
      expect(find.text('capacity.markWidth'), findsOneWidget);
    });

    test('every shipped key reads as words, never as its own dotted name', () {
      final settings = chronologSettings();
      for (final key in settings.keys) {
        final label = settingLabel(key);
        expect(label, isNot(contains('.')), reason: key);
        expect(label[0], label[0].toUpperCase(), reason: key);
      }
    });
  });
  group('the theme card', () {
    testWidgets('Save as writes a NEW theme and leaves the one it came from', (tester) async {
      final store = MemoryFiles();
      final files = SessionFiles('memory', files: store, scheduler: ManualScheduler());
      String? at(String name) {
        final bytes = store.written[storePath('memory', 'themes/$name.json')];
        return bytes == null ? null : utf8.decode(bytes);
      }

      await files.saveNow(files.theme('desk'), {...paperPreset, 'name': 'desk'});
      final before = at('desk');
      expect(before, isNotNull);

      await pumpCard(tester, cardChrome(null), ThemeCard(files: files, names: () => ['desk']));
      await tapText(tester, 'desk');
      await tester.enterText(fieldHinted('new theme name'), 'midnight');
      await tester.pumpAndSettle();
      await tapText(tester, 'Save as');
      await tester.pumpAndSettle();

      expect(jsonDecode(at('midnight')!)['name'], 'midnight');
      expect(at('desk'), before, reason: 'saving as a new name overwrites nothing');
    });

    testWidgets('editing a role applies live and never invents the other seven', (tester) async {
      ChronoTheme? applied;
      await pumpCard(tester, cardChrome(null), ThemeCard(onApply: (theme) => applied = theme));
      await tester.enterText(fieldHolding(hexOf(shipped['paper']!.accent)), '#123456');
      await tester.pumpAndSettle();
      expect(hexOf(applied!.accent), '#123456');
      expect(applied!.palette.length, themeFields.length);
    });
  });

  group('observed boundaries', () {
    for (final seed in seeds(3)) {
      test('a strictly increasing list parses to exactly its lines (seed $seed)', () {
        final random = Random(seed);
        final count = 2 + random.nextInt(6);
        var at = random.nextInt(100);
        final positions = [
          for (var index = 0; index < count; index++) at += 1 + random.nextInt(40),
        ];
        final rows = parseBoundaryList(
          [for (final (index, position) in positions.indexed) 'edge-$index, $position'].join('\n'),
        );
        expect(rows.length, count);
        expect([for (final row in rows) row.at], [for (final position in positions) '$position']);
      });
    }

    test('a line that is not a position refuses with that line named', () {
      expect(
        () => parseBoundaryList('one, 4\ntwo, later\nthree, 9'),
        throwsA(isA<LawRefusal>().having((error) => error.message, 'message', contains('Line 2'))),
      );
    });
  });

  group('the frames browser', () {
    testWidgets('the name is a link and the ring leads', (tester) async {
      final bench = await openCards(_withWorkFrame());
      final chrome = cardChrome(bench.editor);
      String? opened;
      await pumpCard(tester, chrome, FramesBrowser(onOpen: (id) => opened = id));

      await tester.enterText(fieldHinted('Find a frame'), 'wor');
      await tester.pumpAndSettle();
      await tapText(tester, 'Work');
      expect(opened, 'frame:work', reason: 'a row is a link, never an inline editor');

      final view = chrome.focusedView!;
      expect(view.selection.isPrimary('frame:work'), isFalse);
      await tapText(tester, '○');
      expect(
        view.selection.isPrimary('frame:work'),
        isTrue,
        reason: 'picking the ring adds the frame and puts it in charge',
      );
      expect(view.source, isEmpty, reason: 'a row action means the plain selection speaks again');
    });

    testWidgets('an unbased frame says so where it is listed', (tester) async {
      final bench = await openCards(_withWorkFrame());
      await pumpCard(tester, cardChrome(bench.editor), const FramesBrowser());
      expect(find.text('unbased'), findsOneWidget);
    });

    // PULL A FRAME UP AS A COLUMN (ISSUES 9.1: "Board, group by frame -- I see
    // no power to pull up frames ... the chosen-columns half was never built;
    // the frames browser's rows are the natural chooser"). The board's own
    // chooser writes the same key, so this proves the browser's half of it and
    // not a second mechanism beside it.
    testWidgets('a row stands its frame as a column on the focused view', (tester) async {
      final bench = await openCards(_withWorkFrame());
      final chrome = cardChrome(bench.editor);
      await pumpCard(tester, chrome, const FramesBrowser());
      final view = chrome.focusedView!;
      expect(standingColumns(view), isEmpty, reason: 'nothing stands until it is asked to');
      // Narrowed to the one row, because every row wears the same word.
      await tester.enterText(fieldHinted('Find a frame'), 'Work');
      await tester.pumpAndSettle();
      await tapText(tester, 'column');
      expect(
        standingColumns(view),
        contains('frame:work'),
        reason:
            'ISSUES (9.1): a standing column comes from view[\'columns\'], and nothing '
            'wrote that key.',
      );
      // And it is a toggle, not a one-way door: the same row takes it back.
      await tapText(tester, 'column');
      expect(standingColumns(view), isNot(contains('frame:work')));
    });
  });
}
