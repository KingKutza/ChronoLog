// Quick capture's spec, and the 8.26 ruling that owns it: a `#group` miss ASKS,
// the match is fuzzy, and NOTHING is committed before the answer.

import 'package:chronolog/core/coordinate_law.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/object_kinds.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/core/validate.dart';
import 'package:chronolog/edit/editor.dart';
import 'package:test/test.dart';

import '../helpers/projection_scene.dart';
import 'harness.dart';

const String calendarId = 'calendar:work';

void main() {
  Bench? bench;
  late Editor editor;

  Future<Editor> open({List<String> groups = const []}) async {
    final scene = Scene()..calendar(calendarId);
    for (final title in groups) {
      scene.group('frame:${title.toLowerCase()}', const []);
      scene.document = scene.document.put(
        'frames',
        'frame:${title.toLowerCase()}',
        scene.document.frames['frame:${title.toLowerCase()}']!.copyWith(title: title),
      );
    }
    final opened = await openEditor(scene.document, label: 'capture');
    bench = opened;
    return editor = opened.editor;
  }

  tearDown(() async {
    final open = bench;
    bench = null;
    if (open != null) await closeEditor(open);
  });

  group('grammar', () {
    test('the tokens are order-free and first-token-wins; the rest is the title', () {
      final line = parseQuickTodo('#Home call @tomorrow the #plumber > ring twice > loudly')!;
      expect(line.group, 'Home');
      expect(line.date, 'tomorrow');
      expect(line.title, 'call the #plumber');
      expect(line.note, 'ring twice > loudly');
    });

    test('a bare line is a title, and a line with no title is not an object', () {
      expect(parseQuickTodo('water the plants')!.title, 'water the plants');
      expect(parseQuickTodo('   '), isNull);
      expect(parseQuickTodo('#Home @today'), isNull);
    });

    test('a date is read under the frame law, or refused -- never guessed', () {
      final today = Rational.parse('20000');
      Rational? read(String text, [CoordinateLaw? law]) =>
          quickDateDays(text, law ?? gregorianLaw, today);
      expect(read('today'), today);
      expect(read('tomorrow'), today + Rational.one);
      expect(read('+3'), today + Rational.fromInt(3));
      expect(read('+3d'), today + Rational.fromInt(3));
      expect(read('2026-08-03'), gregorianLaw.toDays(Coordinate.fromJson(civil(2026, 8, 3))));
      expect(read('8/3'), isNotNull, reason: 'the year comes from the law reading today');
      expect(read('whenever'), isNull);
      expect(read('2026-8'), isNull, reason: 'not a form the grammar knows');
    });

    test('a law with no month ladder refuses the calendar forms and keeps the counts', () {
      final invented = CoordinateLaw(Declaration.parse(inventedLaw, 'invented'));
      expect(quickDateDays('2026-08-03', invented, Rational.zero), isNull);
      expect(quickDateDays('+2', invented, Rational.zero), Rational.fromInt(2));
    });
  });

  group('the group ask', () {
    test('an exact title resolves outright and commits with the membership', () async {
      await open(groups: ['Home', 'Work']);
      final capture = editor.captureQuickTodo('#Home call the plumber', frameId: calendarId)!;
      expect(capture.ask, isNull);
      expect(capture.group, 'frame:home');
      final id = editor.confirmCapture(capture);
      // THE SENTENCE, NOT THE SPELLING (Don, ruled 2026-09-01: there is no
      // membership, only staples). The capture says it as a staple now, and the
      // ONE membership reader answers the same as it did for the record --
      // asserting the record type would be asserting the spelling this ruling
      // retired.
      expect(editor.engine.indexes.directGroupsOf(id), contains('frame:home'));
      expect(objectKindForEvent(editor.document.events[id]), 'todo');
      expect(validateDocument(editor.document).errors, isEmpty);
    });

    test('a near miss ASKS, offers the group, and commits NOTHING until answered', () async {
      await open(groups: ['Groceries', 'Work']);
      final before = stateOf(editor.document);
      final capture = editor.captureQuickTodo('#Grocerise milk', frameId: calendarId)!;
      expect(capture.group, isNull);
      expect(capture.ask, isNotNull);
      expect(capture.ask!.unmatched, 'Grocerise');
      expect(capture.ask!.candidates.map((row) => row.title), contains('Groceries'));
      expect(stateOf(editor.document), before, reason: 'the ask wrote nothing');
      expect(editor.canUndo, isFalse);
      final id = editor.confirmCapture(capture, groupId: capture.ask!.candidates.first.id);
      expect(
        editor.engine.indexes.directGroupsOf(id),
        contains(capture.ask!.candidates.first.id),
        reason:
            'ruled 2026-09-01: said as a staple, read by the one membership '
            'reader, the same edge either way',
      );
    });

    test('an unambiguous prefix resolves; an ambiguous one asks', () async {
      await open(groups: ['Groceries', 'Gardening']);
      expect(editor.captureQuickTodo('#Groc milk')!.group, 'frame:groceries');
      final ambiguous = editor.captureQuickTodo('#G milk')!;
      expect(ambiguous.group, isNull);
      expect(ambiguous.ask!.candidates, hasLength(2));
    });

    test('a miss with nothing near still asks, and answering "none" writes no group', () async {
      await open(groups: ['Home']);
      final capture = editor.captureQuickTodo('#Elsewhere wander')!;
      expect(capture.ask!.candidates, isEmpty);
      final id = editor.confirmCapture(capture);
      expect(
        editor.document.relations.values.any(
          (relation) => relation.type == 'membership' && relation.member == id,
        ),
        isFalse,
      );
    });

    test('a group is minted only when the answer says so, never by a typo', () async {
      await open(groups: ['Home']);
      final capture = editor.captureQuickTodo('#Errands post office')!;
      final frames = editor.document.frames.length;
      editor.confirmCapture(capture);
      expect(editor.document.frames.length, frames, reason: 'a miss mints nothing');
      final again = editor.captureQuickTodo('#Errands post office')!;
      editor.confirmCapture(again, createGroup: true);
      final minted = editor.document.frames.values.where((frame) => frame.title == 'Errands');
      expect(minted, hasLength(1));
      expect(minted.single.traits, contains('group'));
      expect(validateDocument(editor.document).errors, isEmpty);
    });

    test('state frames are never offered: the state toggle owns those records', () async {
      await open(groups: ['Done']);
      final scene = editor.document;
      editor.commit(
        'Author a state',
        scene.put(
          'frames',
          doneStateFrameId,
          const Frame(id: doneStateFrameId, title: 'Finished', traits: stateFrameTraits),
        ),
      );
      final capture = editor.captureQuickTodo('#Finished something')!;
      expect(capture.group, isNull);
      expect(capture.ask!.candidates.map((row) => row.id), isNot(contains(doneStateFrameId)));
    });
  });

  test('a capture with an unreadable date is reported, and still lands at now', () async {
    await open();
    final capture = editor.captureQuickTodo('@whenever water the plants', frameId: calendarId)!;
    expect(capture.at, isNull);
    expect(capture.dateRefused, isTrue);
    final id = editor.confirmCapture(capture);
    expect(editor.document.events.containsKey(id), isTrue);
    expect(validateDocument(editor.document).errors, isEmpty);
  });

  test('a phantom frame is never written: capture with no real frame is a bare float', () async {
    await open();
    final capture = editor.captureQuickTodo('call mum', frameId: 'calendar:never-existed')!;
    expect(capture.frame, isNull);
    final id = editor.confirmCapture(capture);
    expect(editor.document.relations.values.where((r) => r.event == id), isEmpty);
    expect(validateDocument(editor.document).errors, isEmpty);
  });

  test('the fuzz is a tunable: at zero, only exact and prefix resolve', () async {
    await open(groups: ['Groceries']);
    final strict = Editor(bench!.store, settings: (key) => Rational.zero);
    final capture = strict.captureQuickTodo('#Grocerise milk')!;
    expect(capture.ask!.candidates, isEmpty);
  });
}
