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
      expect(fieldHinted('nowhere'), findsOneWidget, reason: 'the path defaults to the data root');
    });

    test('an unwritten ICS path is the data root; a written one is itself', () {
      expect(icsPathOf('', 'C:/app'), 'C:/app');
      expect(icsPathOf('  ', 'C:/app'), 'C:/app');
      expect(icsPathOf(' D:/feeds/work.ics ', 'C:/app'), 'D:/feeds/work.ics');
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
  });
}
