// THE SERIES, AUTHORED FROM THE CARD (ISSUES 8.31, evening, Don entering his
// real calendar).
//
// Two reports, one surface:
//
//   "It did not project out." — "An authored series must project its occurrences
//   immediately over the visible window ... The model's series stack is proven
//   (463+ core tests) — suspect the seam between the edit card and the pattern
//   record." So this drives the REAL card: set repeats-every-day the way a person
//   does, then ask the engine what it projects.
//
//   "when I set lunch to repeats every day I had no clear way to put in an except
//   weekends and holidays." — "the series editor offers exclusion sentences —
//   except members of *Frame* (holidays), except every time that matches
//   (weekends selector) — the same place vocabulary the staple sentence speaks,
//   compiled to the same NOT. No new mechanism; the missing thing is the
//   authoring surface."
//
// Nothing here reaches into the pattern record to set a rule: the point is the
// seam, so the rule is set by tapping what a person taps.

import 'package:chronolog/cards/card_chrome.dart';
import 'package:chronolog/cards/object_card.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/projection.dart';
import 'package:chronolog/core/records.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';
import 'object_harness.dart';

const String _frame = 'frame:wall-time';

/// The day the card is opened over -- a whole day, so "every day" has an obvious
/// answer to check against.
final Rational _start = Rational(daysFromCivil(BigInt.from(2026), 9, 1));

/// Opens the card the way the lens does: a drag-create seed states a placement,
/// so the record commits and the card opens over a placed object.
Future<CardBench> cardOverNewEvent(WidgetTester tester) async {
  final bench = await openCards(createEmptyWorkspaceDocument(now: DateTime.utc(2026, 9, 1)));
  await pumpHosted(
    tester,
    bench,
    ObjectCard(
      request: (
        klass: 'newObject',
        id: null,
        kind: 'event',
        frameId: _frame,
        startDays: _start,
        endDays: null,
      ),
    ),
    klass: 'newObject',
    kind: 'event',
    shell: true,
  );
  await tester.enterText(find.byType(CardField).first, 'Lunch');
  await tester.pump();
  return bench;
}

/// Reaches the repeat control and says "daily" -- through the fold while the
/// card still has one, because what is under test is the repeat, not the layout.
Future<void> setRepeatsDaily(WidgetTester tester) async {
  final fold = find.textContaining('Everything else');
  if (fold.evaluate().isNotEmpty) await tapPart(tester, 'Everything else');
  await tapText(tester, 'never');
  await tapText(tester, 'daily');
}

/// Which whole days the projection puts this object on, over [days] days from
/// the placement.
Set<BigInt> projectedDays(CardBench bench, int days) {
  final result = bench.editor.engine.queryFacts(
    Projection.of([_frame]),
    start: _start,
    end: _start + Rational.fromInt(days),
  );
  return {for (final fact in result.facts) fact.day.floor()};
}

void main() {
  testWidgets('a repeat set on the card reaches the pattern record', (tester) async {
    final bench = await cardOverNewEvent(tester);
    await setRepeatsDaily(tester);
    final patterns = bench.editor.document.patterns.values.toList();
    expect(patterns, hasLength(1), reason: 'saying "daily" mints the pattern');
    final pattern = patterns.single;
    expect(str(obj(pattern.extra['rrule'])?['FREQ']), 'DAILY', reason: 'the rule it was told');
    // REWRITTEN under the ruling of 2026-09-01 (ISSUES 9.1): the card no longer
    // stores the template placement's id, because storing it a second time is
    // what made "minted without it" a reachable silent state at all. What this
    // light asserted -- that the generator can find the placement -- is asserted
    // of the DERIVATION now, which is the one truth.
    expect(
      pattern.extra.containsKey('templateRelation'),
      isFalse,
      reason: 'ruled 2026-09-01: new patterns omit it; the placement is derived',
    );
    expect(
      bench.editor.staples.templatePlacement(pattern)?.frame,
      _frame,
      reason: 'and the derived template placement is the one the card was opened over',
    );
  });

  testWidgets('a daily repeat projects over the visible window, immediately', (tester) async {
    final bench = await cardOverNewEvent(tester);
    await setRepeatsDaily(tester);
    // A property, not a pinned count: every whole day of the window carries an
    // occurrence, because that is what "every day" says.
    for (final window in const [7, 14, 30]) {
      final days = projectedDays(bench, window);
      expect(
        days.length,
        greaterThanOrEqualTo(window),
        reason:
            'ISSUES (8.31, evening, Don live): "It did not project out." Over a '
            '$window-day window a daily series put occurrences on ${days.length} '
            'days.',
      );
    }
  });

  testWidgets('the series editor offers the exclusion sentences', (tester) async {
    await cardOverNewEvent(tester);
    await setRepeatsDaily(tester);
    expect(
      find.textContaining(RegExp('[Ee]xcept')),
      findsWidgets,
      reason:
          'ISSUES (8.31, evening): "when I set lunch to repeats every day I had no '
          'clear way to put in an except weekends and holidays" — the series editor '
          'offers no exclusion sentence at all.',
    );
  });

  testWidgets('an exclusion authored on the card compiles to the ruled NOT', (tester) async {
    final bench = await cardOverNewEvent(tester);
    await setRepeatsDaily(tester);
    // The holiday frame the exclusion would name.
    bench.editor.transaction(
      'Holidays',
      (d) => d.put(
        'frames',
        'frame:holidays',
        Frame(id: 'frame:holidays', title: 'Holidays', traits: const ['set', 'calendar']),
      ),
    );
    await tester.pumpAndSettle();
    final offer = find.textContaining(RegExp('[Ee]xcept'));
    expect(
      offer,
      findsWidgets,
      reason:
          'ISSUES (8.31, evening): the ruled authoring path is "except members of '
          '*Frame* (holidays), except every time that matches (weekends selector)".',
    );
    await tester.tap(offer.first, warnIfMissed: false);
    await tester.pumpAndSettle();
    // What the model already holds: a live reference to another frame's events,
    // read at projection time. The card is supposed to write exactly this.
    final pattern = bench.editor.document.patterns.values.single;
    expect(
      obj(pattern.extra['exclude'])?['frames'],
      contains('frame:holidays'),
      reason: 'the sentence compiles to the live exclusion the projection already reads',
    );
  });

  // THE SELECTOR HALF, END TO END. The frames half is one sentence; "except
  // every time that matches" is the other, and it is only a sentence if the
  // projection reads it. So this authors it through the card's own control and
  // then asks the engine which days the series actually landed on -- a property
  // over the selector's own meaning, not a stored field.
  testWidgets('an authored selector exclusion takes those days out of the projection', (
    tester,
  ) async {
    final bench = await cardOverNewEvent(tester);
    await setRepeatsDaily(tester);
    // The card offers the frame's OWN declared cycles and their own names, so
    // the value is read off the law rather than written down here.
    final law = bench.editor.engine.lawOf(_frame);
    final weekdays = law.weekdayNames()!;
    // Whichever name the value menu is showing is the one "Except these" takes,
    // and the menu opens on the cycle's first name.
    final excluded = weekdays.first;
    await tapText(tester, 'Except these');
    final pattern = bench.editor.document.patterns.values.single;
    final selectors = obj(pattern.extra['exclude'])?['selectors'];
    expect(
      selectors,
      isNotNull,
      reason: 'the selector sentence is carried as open data on the pattern\'s exclude',
    );
    // And it MEANS something: no projected day falls on the excluded name, and
    // the rest of the week still does.
    final days = projectedDays(bench, 30);
    expect(days, isNotEmpty, reason: 'a daily series still projects');
    for (final day in days) {
      expect(
        law.cycleLabel('weekday', Rational(day)),
        isNot(excluded),
        reason:
            'ISSUES (8.31, evening): "except every time that matches" must compile to the '
            'same NOT the frames half does — $excluded is still being projected.',
      );
    }
    expect(
      {for (final day in days) law.cycleLabel('weekday', Rational(day))}.length,
      weekdays.length - 1,
      reason: 'every OTHER day of the cycle survives: the NOT excludes one name, not a week',
    );
  });
}
