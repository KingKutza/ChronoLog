// The document, settings, theme, boundary and frames-browser cards.
//
// Generation is seeded from the spec seed, so nothing here asserts an arbitrary
// fact: the counts are the generator's own and the properties hold for any of
// them.

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
