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
//
// Nine rulings, nine properties, all asked of the card AS RENDERED through the
// same CardHost a tile gives it, or of the engine where the ruling is engine
// law. Every case is generative over a seed: counts, hours, colours and names
// are drawn, never pinned.
//
// THE ONE CONTRACT this file names that does not exist yet (the state point):
// a state staple carrying an instant GIVES the object a point NAMED BY THAT
// FRAME -- the frame's title as a one-math identifier, lowercased (the same
// slug `ViewState.bindingsFor` makes of a title) -- so "the start of this is
// the done of that" resolves through `resolveObjectExtent` like any other
// point, and a frame titled "Blocked" yields a `blocked` point the same way.
// Nothing else here needs a new name: the rest is what the existing widgets
// show and write.

import 'dart:math';

import 'package:chronolog/cards/coordinate_field.dart';
import 'package:chronolog/cards/frame_card.dart';
import 'package:chronolog/cards/object_card.dart';
import 'package:chronolog/cards/sentence_rows.dart';
import 'package:chronolog/cards/card_chrome.dart';
import 'package:chronolog/chrome/menus.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/object_kinds.dart';
import 'package:chronolog/core/projection.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/lens/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/corpus.dart';
import '../helpers/projection_scene.dart';
import '../lens/painters/grid_scene.dart';
import 'harness.dart';
import 'object_harness.dart';

const String calendar = 'calendar:a';

Future<void> pumpObject(WidgetTester tester, CardBench bench, String id) => pumpHosted(
  tester,
  bench,
  ObjectCard(
    request: (klass: 'object', id: id, kind: null, frameId: null, startDays: null, endDays: null),
  ),
  id: id,
  shell: true,
);

Future<void> pumpFrame(WidgetTester tester, CardBench bench, String id) =>
    pumpHosted(tester, bench, FrameCard(frameId: id), klass: 'frame', id: id, shell: true);

/// A todo, wearing the catalog's own traits for the kind.
String todo(Scene scene, String title) {
  final id = scene.object(title: title, duration: '0');
  scene.document = scene.document.put(
    'events',
    id,
    scene.document.events[id]!.copyWith(traits: objectKinds['todo']!.traits),
  );
  return id;
}

/// A frame's title as the identifier a sentence may say -- the same slug the
/// view's bindings make of a title, lowercased.
String pointNamedBy(String title) => title.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_').toLowerCase();

/// Every colour any RichText on the surface paints a span in.
Set<Color> spanColors(WidgetTester tester) {
  final found = <Color>{};
  void walk(InlineSpan span) {
    final color = span.style?.color;
    if (color != null) found.add(color);
    if (span is TextSpan) {
      for (final child in span.children ?? const <InlineSpan>[]) {
        walk(child);
      }
    }
  }

  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    walk(rich.text);
  }
  return found;
}

void main() {
  for (final seed in seeds(3)) {
    testWidgets('a sentence row at rest is one line of prose; the like fold with a count '
        '(seed $seed)', (tester) async {
      // "At rest a sentence is one line -- the prose sentence and its sigil,
      // nothing else; the coordinate field, fuzziness, rule and unsay appear only
      // for the row that is OPEN." And: "sentences with the same shape and
      // far-end KIND fold into one line with a count -- '13 todos start at the
      // end of this' -- expanding to the list on click."
      final random = Random(seed);
      final scene = Scene()..calendar(calendar);
      final meeting = scene.object(title: 'AI Team meeting', duration: '60');
      scene.place(calendar, civil(2026, 9, 3, 14), event: meeting);
      final count = 5 + random.nextInt(11);
      final titles = <String>[];
      for (var index = 0; index < count; index += 1) {
        final title = 'Follow up ${index + 1} of $seed';
        titles.add(title);
        scene.staple(
          kind: 'anchor',
          ends: [ObjectEnd(todo(scene, title), point: 'start'), ObjectEnd(meeting, point: 'end')],
        );
      }
      final bench = (await tester.runAsync(() => openCards(scene.document)))!;
      await pumpObject(tester, bench, meeting);
      expect(
        find.byType(CoordinateField),
        findsNothing,
        reason:
            'ISSUES 9.2: at rest no row is open, so no coordinate field, no help line and no '
            'picker is on the card -- "five to eight lines per sentence at rest" is the report.',
      );
      expect(find.byType(Fuzziness), findsNothing, reason: 'fuzziness belongs to the open row only');
      final rows = find.byType(SentenceRow).evaluate().length;
      expect(
        rows,
        lessThan(count),
        reason:
            'ISSUES 9.2: $count like sentences rendered as $rows rows. Sentences of one shape '
            'and one far-end kind fold into ONE line with a count.',
      );
      // The count beside the kind it counts ("13 todos ..."), so a clock reading
      // in the extent note ("14:00") is never mistaken for the fold.
      final fold = find.descendant(
        of: find.byType(StapleEditor),
        matching: find.textContaining(RegExp('\\b$count\\s+todo', caseSensitive: false)),
      );
      expect(fold, findsWidgets, reason: 'the fold says how many it holds');
      // Two clicks to any: one on the fold opens the list, and every member is
      // then a row of its own to click.
      await tester.tap(fold.first, warnIfMissed: false);
      await tester.pumpAndSettle();
      for (final title in titles) {
        expect(
          find.textContaining(title),
          findsWidgets,
          reason: 'ISSUES 9.2: "every sentence remains reachable in at most two clicks"',
        );
      }
    });

    testWidgets('the extent note is one line, and affiliations are not contests in it '
        '(seed $seed)', (tester) async {
      // "The note says only what is known: 'Starts <when>. Ends <when>.' or 'No
      // start said. No end said.' -- one line -- and a REAL contest appears as
      // its own short refusal beside the sentence that caused it." And: "'which
      // is a legal thing for a record to say' is the card reassuring the person
      // about the model -- cut."
      final random = Random(seed);
      final scene = Scene()..calendar(calendar);
      final note = scene.object(title: 'The mail from Reggie', duration: '0');
      for (var index = 0; index < 1 + random.nextInt(4); index += 1) {
        scene.group('group:$index', [note]);
      }
      final bench = (await tester.runAsync(() => openCards(scene.document)))!;
      await pumpObject(tester, bench, note);
      for (final commentary in const ['legal thing', 'claimed by', 'resolves nowhere', 'Read from']) {
        expect(
          find.textContaining(commentary),
          findsNothing,
          reason:
              'ISSUES 9.2: "$commentary" is commentary or a misclassified contest. An '
              'affiliation claims no point, so it cannot fail to resolve one, and the note '
              'reassures nobody about the model.',
        );
      }
      expect(find.textContaining('No start said'), findsOneWidget);
      expect(find.textContaining('No end said'), findsOneWidget);
      expect(
        find.byType(Refusal),
        findsNothing,
        reason: 'an object with only affiliations carries zero contests',
      );
    });

    testWidgets('the object\'s own weight is an editable term in a composed, colour-coded '
        'formula (seed $seed)', (tester) async {
      // "The row shows the composed formula as ONE line, each term inked in ITS
      // FRAME'S authored colour ... and the object's own term is the one editable
      // term in that line." The paragraph of sentences becomes the hover.
      final random = Random(seed);
      String hex() => '#${random.nextInt(1 << 24).toRadixString(16).padLeft(6, '0')}';
      final one = hex();
      var other = hex();
      while (other == one) {
        other = hex();
      }
      final own = '${2 + random.nextInt(7)}';
      final scene = Scene()..calendar(calendar);
      final event = scene.object(title: 'Standup', duration: '45');
      scene.document = scene.document.put(
        'events',
        event,
        scene.document.events[event]!.withField('display', {'weight': own}),
      );
      scene.place(calendar, civil(2026, 9, 3, 9), event: event);
      scene.group('group:red', [event], weight: 'w * 2', extra: {'color': one});
      scene.group('group:blue', [event], weight: 'w + 1', extra: {'color': other});
      final bench = (await tester.runAsync(() => openCards(scene.document)))!;
      bench.chrome.views.of('view:1').selection.toggle('group:red');
      bench.chrome.views.of('view:1').selection.toggle('group:blue');
      await pumpObject(tester, bench, event);
      final colors = spanColors(tester);
      for (final authored in [one, other]) {
        expect(
          colors,
          contains(parseColor(authored)),
          reason:
              'ISSUES 9.2: no term of the weight line is inked in $authored -- the frame\'s '
              'authored colour is what names it everywhere else, so it names its term here.',
        );
      }
      expect(
        find.textContaining('which takes it from'),
        findsNothing,
        reason: 'the paragraph of sentences is the hover, not the surface',
      );
      final term = fieldHolding(own);
      expect(
        term,
        findsOneWidget,
        reason:
            'ISSUES 9.2: the object\'s own weight ($own) is the one editable term; the row was '
            'read-only prose with no field.',
      );
      final edited = '${int.parse(own) + 1}';
      await tester.enterText(term, edited);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      if (find.text('Save').evaluate().isNotEmpty) await tapText(tester, 'Save');
      final written = obj(bench.editor.document.events[event]!.extra['display'])?['weight'];
      expect(
        '$written',
        equals(edited),
        reason: 'the term writes `display.weight`, the ring the engine already reads first',
      );
    });

    testWidgets('the Duration row shows the derived magnitude when both ends are anchored, says '
        'it is derived, and touching it mints no competing truth (seed $seed)', (tester) async {
      // Don, still open: "The start and end staple author duration bug is still
      // not fixed." The card reads the STORED magnitude and falls back to zero;
      // the engine derives the magnitude between two anchors and flags it
      // (`derivedMagnitude: true`), and the card never asks. Three properties:
      //   the row shows the REAL duration (today a false zero);
      //   the row says WHICH it is -- derived, the authored number overridden;
      //   touching the row must not silently store a second duration beside the
      //   two staples that already say it -- a contest created by the surface.
      final random = Random(seed);
      final hours = 1 + random.nextInt(8);
      final scene = Scene()..calendar(calendar);
      final event = scene.object(title: 'Workshop', duration: '30');
      scene.place(calendar, civil(2026, 9, 3, 9), event: event);
      scene.staple(
        kind: 'anchor',
        ends: [
          ObjectEnd(event, point: 'end'),
          FrameEnd(calendar, position: Position.coordinate(civil(2026, 9, 3, 9 + hours))),
        ],
      );
      final engine = ProjectionEngine(scene.document);
      final extent = engine.staples.resolveObjectExtent(event);
      expect(extent.derivedMagnitude, isTrue, reason: 'the engine derives the magnitude already');
      expect(extent.magnitudeDays, equals(Rational.fromInt(hours, 24)));
      final bench = (await tester.runAsync(() => openCards(scene.document)))!;
      final stored = bench.editor.document.events[event]!.duration;
      await pumpObject(tester, bench, event);
      final row = find.ancestor(of: find.text('Duration'), matching: find.byType(LayoutBuilder)).first;
      expect(
        find.descendant(of: row, matching: find.textContaining(RegExp('derived', caseSensitive: false))),
        findsWidgets,
        reason: 'ISSUES 9.2: the row read the AUTHORED 30 and never the derived extent',
      );
      expect(
        find.descendant(of: row, matching: find.textContaining(RegExp('\\b(${hours * 60}|$hours)\\b'))),
        findsWidgets,
        reason: 'the derived value -- $hours hours -- is the number on the row',
      );
      expect(
        find.descendant(of: row, matching: find.textContaining(RegExp('overridden', caseSensitive: false))),
        findsWidgets,
        reason: 'the authored number is shown as what it is',
      );
      // Touching the row, the way a person correcting a wrong-looking number
      // would, writes NO stored duration: editing a derived duration means
      // moving an end or deliberately replacing the derivation, and plain typing
      // is neither.
      final fields = find.descendant(of: row, matching: find.byType(TextField));
      if (fields.evaluate().isNotEmpty) {
        await tester.enterText(fields.first, '${hours * 60 + 15}');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        if (find.text('Save').evaluate().isNotEmpty) await tapText(tester, 'Save');
      }
      expect(
        bench.editor.document.events[event]!.duration,
        equals(stored),
        reason:
            'ISSUES 9.2: touching the derived row stored a duration beside the two staples that '
            'already say it -- a competing truth the surface minted, not the person.',
      );
    });

    testWidgets('changing a duration\'s unit keeps the absolute duration, through the frame\'s law '
        '(seed $seed)', (tester) async {
      // Ruled and still unfixed: the unit menu's handler is `(name) => put(amount,
      // name)`, carrying the COUNT across verbatim, so 90 minutes becomes 90
      // hours. "The conversion goes through the governing frame's own law
      // (`unitsPer`), never a constant." A constant would pass a Gregorian-only
      // case, so the laws here are a 23-hour day AND the invented pen-stroke
      // ladder, whose stroke is eight steps and relates to no Earth unit at all.
      final random = Random(seed);
      final k = 1 + random.nextInt(3);
      // The invented law FIRST: it is the case a constant could never pass.
      final laws = <({String frame, String from, String to, void Function(Scene) build, Json at})>[
        (
          frame: 'frame:invented',
          from: 'step',
          to: 'stroke',
          build: (scene) =>
              scene.frame('frame:invented', const ['line', 'temporal'], const {'coordinate': inventedLaw}),
          at: stroke(3, 1),
        ),
        (
          frame: 'calendar:short',
          from: 'hour',
          to: 'day',
          build: (scene) => scene.calendar('calendar:short', hoursPerDay: 23),
          at: civil(2026, 9, 3, 9),
        ),
      ];
      for (final law in laws) {
        final scene = Scene();
        law.build(scene);
        final per = ProjectionEngine(scene.document).lawOf(law.frame).unitsPer(law.from, law.to);
        expect(per, greaterThan(Rational.one), reason: '${law.frame}: ${law.to}s are made of ${law.from}s');
        final event = scene.object(
          title: 'Expedition',
          duration: (Rational.fromInt(k) * per).toJson(),
          unit: law.from,
        );
        scene.place(law.frame, law.at, event: event);
        final bench = (await tester.runAsync(() => openCards(scene.document)))!;
        await pumpObject(tester, bench, event);
        final menu = find.byWidgetPredicate((widget) => widget is ChronoMenu && widget.label == law.from);
        expect(menu, findsOneWidget, reason: '${law.frame}: the unit menu wears the current unit');
        await tester.ensureVisible(menu);
        await tester.tap(menu);
        await tester.pumpAndSettle();
        await tester.tap(find.text(law.to).last);
        await tester.pumpAndSettle();
        if (find.text('Save').evaluate().isNotEmpty) await tapText(tester, 'Save');
        final level = bench.editor.document.events[event]!.duration!.coordinate.levels.first;
        expect(level.level, law.to, reason: '${law.frame}: the unit changed');
        expect(
          Rational.parse(level.value),
          equals(Rational.fromInt(k)),
          reason:
              'ISSUES 9.2 (${law.frame}): ${Rational.fromInt(k) * per} ${law.from}s became '
              '"${level.value} ${law.to}" -- the COUNT carried across. Under this law a ${law.to} is '
              '$per ${law.from}s, so that is $k ${law.to}s, and the absolute length is what survives.',
        );
      }
    });

    testWidgets('the create door offers every registered kind, not only a frame (seed $seed)', (
      tester,
    ) async {
      // "The create door offers every kind the registry knows -- 'New frame
      // <name>', and 'New <kind> <name>' for each entry in `objectKinds` --
      // generative, never a written list -- and a created object opens in its
      // own card, stapled by the sentence being said."
      final random = Random(seed);
      final kinds = objectKinds.keys.toList();
      final chosen = kinds[random.nextInt(kinds.length)];
      final name = 'Zephyr $seed';
      final scene = Scene()..calendar(calendar);
      final host = scene.object(title: 'Chase the rubric', duration: '0');
      scene.place(calendar, civil(2026, 9, 3, 9), event: host);
      final bench = (await tester.runAsync(() => openCards(scene.document)))!;
      await pumpObject(tester, bench, host);
      // The FAR term's field, by the hint it wears -- once the row shows every
      // term from the first keystroke, the first field may be the near point.
      final field = find.descendant(
        of: find.byType(NewSentence),
        matching: find.byWidgetPredicate(
          (widget) => widget is TextField && (widget.decoration?.hintText ?? '').contains('frame or an object'),
        ),
      );
      expect(field, findsWidgets, reason: 'the + row has a far term to type into');
      await tester.enterText(field.first, name);
      await tester.pumpAndSettle();
      expect(find.textContaining(RegExp('New frame', caseSensitive: false)), findsWidgets);
      for (final kind in objectKinds.values) {
        expect(
          find.textContaining(RegExp('New ${kind.label}', caseSensitive: false)),
          findsWidgets,
          reason:
              'ISSUES 9.2: a name nothing wears offered only a frame; "New ${kind.label} $name" '
              'is owed for every catalog row.',
        );
      }
      final tiles = bench.factory.stage.tiles.keys.toSet();
      await tester.tap(
        find.textContaining(RegExp('New ${objectKinds[chosen]!.label}', caseSensitive: false)).first,
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      final document = bench.editor.document;
      final minted = document.events.values
          .where((event) => event.payload?['title'] == name)
          .toList();
      expect(minted, hasLength(1), reason: 'one $chosen named $name was made');
      expect(objectKindForEvent(minted.single), chosen, reason: 'wearing the catalog\'s traits');
      final connected = ProjectionEngine(document)
          .connectionsOf(host)
          .any((edge) => edge.from == minted.single.id || edge.to == minted.single.id);
      expect(connected, isTrue, reason: 'stapled by the sentence being said');
      expect(
        bench.factory.stage.tiles.keys.toSet().difference(tiles),
        isNotEmpty,
        reason: 'the created object opens in its own card',
      );
    });

    test('a state staple with an instant gives the object a point named by that frame '
        '(seed $seed)', () {
      // Don: the follow-up starts at the done todo's END. A todo is zero-duration,
      // so end == start; the instant he means lives on the state staple's own
      // coordinate. "A state staple carrying an instant GIVES the object a point
      // named by that frame -- 'the start of this is the DONE of that' --
      // generative over every state frame with an instant, so a frame titled
      // 'Blocked' yields a 'blocked' point the same way."
      final random = Random(seed);
      final title = ['Done', 'Blocked', 'Shipped', 'Waiting on Reggie'][random.nextInt(4)];
      final hour = 10 + random.nextInt(9);
      final scene = Scene()..calendar(calendar);
      final first = todo(scene, 'Ask Reggie');
      scene.place(calendar, civil(2026, 9, 3, 9), event: first);
      scene.frame('frame:state', stateFrameTraits);
      scene.document = scene.document.put(
        'frames',
        'frame:state',
        scene.document.frames['frame:state']!.copyWith(title: title),
      );
      scene.join('frame:state', first);
      scene.staple(
        kind: 'end',
        ends: [
          ObjectEnd(first, point: 'end'),
          FrameEnd(calendar, position: Position.coordinate(civil(2026, 9, 3, hour))),
        ],
      );
      final second = todo(scene, 'Chase Reggie');
      scene.staple(
        kind: 'anchor',
        ends: [ObjectEnd(second, point: 'start'), ObjectEnd(first, point: pointNamedBy(title))],
      );
      final engine = ProjectionEngine(scene.document);
      final extent = engine.staples.resolveObjectExtent(second);
      expect(
        extent.startDays,
        equals(civilDays(2026, 9, 3) + Rational.fromInt(hour, 24)),
        reason:
            'ISSUES 9.2: "the start of this is the ${pointNamedBy(title)} of that" resolved to '
            '${extent.startDays} (${extent.source}). The instant on the state staple is a point '
            'of the object, named by the frame that carries it.',
      );
    });
  }

  testWidgets('overscale: an object with 200 staples renders its sentences region within a screen '
      'at rest', (tester) async {
    // "Red light, generative: an object with 200 staples renders its sentences
    // region in under a screen at rest and every sentence remains reachable in
    // at most two clicks." Overscale is a design requirement: "if it is not
    // usable at 500 calendars it is improperly built for 3."
    final scene = Scene()..calendar(calendar);
    final meeting = scene.object(title: 'The all-hands', duration: '60');
    scene.place(calendar, civil(2026, 9, 3, 14), event: meeting);
    for (var index = 0; index < 200; index += 1) {
      scene.staple(
        kind: 'anchor',
        ends: [ObjectEnd(todo(scene, 'Action $index'), point: 'start'), ObjectEnd(meeting, point: 'end')],
      );
    }
    final bench = (await tester.runAsync(() => openCards(scene.document)))!;
    await pumpObject(tester, bench, meeting);
    expect(
      tester.getSize(find.byType(StapleEditor)).height,
      lessThanOrEqualTo(cardSurface.height),
      reason:
          'ISSUES 9.2: "the staple cards are so tall that it can be overwhelming" -- 200 like '
          'sentences at rest must fold into a region a screen holds.',
    );
  });

  testWidgets('the frame card has a sentences region with the frame as the near end', (
    tester,
  ) async {
    // "The frame card grows the same SENTENCES REGION the object card has (the
    // edit card IS sentences, 8.31 -- one card class), with the frame as the
    // near end: basis, correspondence points, era stapling and affiliation all
    // as sentences; the + row offers frame coordinates on both ends." So a
    // time-travel frame can be said by hand, and one that already exists reads.
    final scene = Scene()..calendar(calendar);
    scene.frame('frame:travel', const ['set', 'calendar'], const {'basis': 'frame:wall-time'});
    scene.document = scene.document.put(
      'frames',
      'frame:travel',
      scene.document.frames['frame:travel']!.copyWith(title: 'Traveller'),
    );
    scene.staple(
      kind: 'correspondence',
      ends: [
        FrameEnd('frame:travel', position: Position.coordinate(civil(2026, 9, 3, 10))),
        FrameEnd('frame:wall-time', position: Position.coordinate(civil(2026, 9, 3, 9, 30))),
      ],
    );
    final wallTitle = scene.document.frames['frame:wall-time']!.title!;
    final bench = (await tester.runAsync(() => openCards(scene.document)))!;
    await pumpFrame(tester, bench, 'frame:travel');
    expect(
      find.descendant(of: find.byType(FrameCard), matching: find.byType(NewSentence)),
      findsOneWidget,
      reason:
          'ISSUES 9.2: no GUI path authors a frame-to-frame sentence ("10:00 here is 9:30 on '
          'Wall Time"). The frame card grows the + row with the frame as the near end.',
    );
    final rows = find.descendant(of: find.byType(FrameCard), matching: find.byType(SentenceRow));
    expect(rows, findsWidgets, reason: 'the correspondence already said reads as a sentence');
    expect(
      find.descendant(of: rows, matching: find.textContaining(wallTitle)),
      findsWidgets,
      reason: 'and names its far frame by title',
    );
  });

  testWidgets('the frame card\'s weight field reads as an equation, and In Strategic melts into '
      'it', (tester) async {
    // "The row reads as an equation with the authored term visibly editable --
    // `w × 1.5` in the data face, the input caret in it -- and its label says
    // what it is: 'Members weigh'." And: "'In Strategic -- by weight / promote /
    // demote' is an ENUM deciding display where the weight formula already says
    // everything it says -- promote IS `w * <landmark>` and demote IS `w * 0` --
    // so it melts into the weight term and the three-way goes; Zone fill ...
    // belongs in the frame's trait BUNDLE beside `busy`, not as a per-frame
    // tri-state row."
    final scene = Scene()..calendar(calendar);
    scene.group(
      'group:holidays',
      const [],
      weight: 'w * 1.5',
      extra: const {
        'display': {'strategic': 'show', 'zone': true},
      },
    );
    final bench = (await tester.runAsync(() => openCards(scene.document)))!;
    await pumpFrame(tester, bench, 'group:holidays');
    // The handling sits under the card's one fold; open it the way a hand does.
    if (find.textContaining('Structure, handling').evaluate().isNotEmpty) {
      await tapPart(tester, 'Structure, handling');
    }
    expect(
      fieldHolding('w * 1.5'),
      findsOneWidget,
      reason:
          'ISSUES 9.2: the weight field "reads as a READOUT, not as the place the algebra is '
          'written" -- the authored term is the text in the field.',
    );
    expect(find.textContaining('Members weigh'), findsWidgets, reason: 'the label says what it is');
    for (final gone in const ['In Strategic', 'promote', 'demote', 'Zone fill']) {
      expect(
        find.textContaining(gone),
        findsNothing,
        reason:
            'ISSUES 9.2: "$gone" is a per-frame choice row the weight term or the trait bundle '
            'already says. Enum is the enemy.',
      );
    }
  });
}
