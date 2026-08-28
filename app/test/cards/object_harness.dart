// The object-card spec's seams, on top of the shared card harness. Uncounted
// test support: nothing here decides behaviour.
//
// A card lives inside a CardHost, so every case pumps the real host rather than
// a mock -- what the spec exercises is what ships.

import 'package:chronolog/cards/card_factory.dart';
import 'package:chronolog/chrome/controls.dart';
import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/core/coordinate_law.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/era_chain.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/edit/editor.dart';
import 'package:chronolog/session/settings.dart';
import 'package:chronolog/session/view_state.dart';
import 'package:chronolog/stage/tile.dart';
import 'package:chronolog/store/document_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../store/harness.dart';
import 'harness.dart';

typedef CardBench = ({Editor editor, CardFactory factory, Chrome chrome, Settings settings});

/// The bench, with no disk and no clock anyone has to advance.
Future<CardBench> openCards(Document document) async {
  final store = DocumentStore(
    dataRoot: 'memory',
    files: MemoryFiles(),
    scheduler: ManualScheduler(),
    establish: () => document,
  );
  await store.load();
  final settings = chronologSettings();
  final editor = Editor(store, settings: settings.tunable);
  final views = ViewBook();
  final stage = Stage(tunable: settings.tunable, onLens: views.setLens);
  return (
    editor: editor,
    factory: CardFactory(editor, settings, stage),
    chrome: Chrome(settings: settings, stage: stage, views: views, editor: editor),
    settings: settings,
  );
}

/// Pumps [child] inside the scopes a card really lives in.
///
/// A whole [CardShell] wants a BOUNDED height -- it scrolls its own body -- so
/// [shell] hands it one; a bare instrument gets a scroll view instead, so a
/// case can reach a control below the fold.
Future<void> pumpHosted(
  WidgetTester tester,
  CardBench bench,
  Widget child, {
  String klass = 'object',
  String? id,
  String? kind,
  bool shell = false,
}) => pumpCard(
  tester,
  bench.chrome,
  CardHost(
    factory: bench.factory,
    request: (klass: klass, id: id, kind: kind, frameId: null, startDays: null, endDays: null),
    tileId: 'card:$klass:${id ?? kind ?? 'one'}',
    child: shell
        ? SizedBox(height: cardSurface.height, child: child)
        : SingleChildScrollView(child: child),
  ),
);

// --- Laws a card has to speak ----------------------------------------------

CoordinateLaw lawFrom(Json declaration, String frameId) =>
    CoordinateLaw(Declaration.parse(declaration, 'Frame $frameId'), frameId: frameId);

/// The owner's own 8.20 case: "I just swaped both Wall Time and Human time
/// magnitude to Hour:Day:23 ... there still appears to be 24 hours in a day."
const Json twentyThreeHourLadder = {
  'kind': 'nested',
  'baseLevel': 'day',
  'levels': [
    {'name': 'year'},
    {'name': 'day', 'within': 'year', 'radix': '400'},
    {'name': 'hour', 'within': 'day', 'radix': '23'},
    {'name': 'minute', 'within': 'hour', 'radix': '60'},
  ],
};

const List<String> seasonNames = [
  'Ashfall',
  'Ashen',
  'Waking',
  'Bloom',
  'Highsun',
  'Ember',
  'Harvest',
  'Hollow',
];

/// A wholly non-Gregorian ladder with authored value names.
const Json customLadder = {
  'kind': 'nested',
  'baseLevel': 'pulse',
  'levels': [
    {'name': 'epoch'},
    {'name': 'season', 'within': 'epoch', 'radix': '8', 'names': seasonNames},
    {'name': 'pulse', 'within': 'season', 'radix': '8'},
    {'name': 'beat', 'within': 'pulse', 'radix': '8'},
  ],
};

const Json gregorianLadder = {
  'kind': 'gregorian',
  'levels': [
    {'name': 'year'},
    {'name': 'month', 'within': 'year', 'transition': 'gregorian.months'},
    {'name': 'day', 'within': 'month', 'transition': 'gregorian.days'},
    {'name': 'hour', 'within': 'day', 'radix': '24'},
    {'name': 'minute', 'within': 'hour', 'radix': '60'},
  ],
};

final List<Json> bceCeChain = [
  {
    'id': 'era:bce',
    'era': {
      'key': 'BCE',
      'name': 'Before Common Era',
      'direction': 'descending',
      'firstYear': '1',
      'years': 'open',
      'affix': 'suffix',
    },
  },
  {
    'id': 'era:ce',
    'era': {
      'key': 'CE',
      'name': 'Common Era',
      'direction': 'ascending',
      'firstYear': '1',
      'years': 'open',
      'affix': 'suffix',
      'anchor': {'year': '1', 'properYear': '1'},
    },
  },
];

/// An era chain over a ladder: the calendar, one frame per era through `basis`,
/// and a succession staple per boundary.
CoordinateLaw eraLaw(List<Json> eras, Json ladder, String eraId) {
  var document = Document(
    meta: const {'title': 'chain'},
    frames: {
      'frame:chain': Frame(
        id: 'frame:chain',
        title: 'Chain calendar',
        traits: const ['line', 'temporal', 'calendar'],
        extra: {'coordinate': ladder},
      ),
      for (final era in eras)
        '${era['id']}': Frame(
          id: '${era['id']}',
          title: '${(era['era'] as Json)['name']}',
          traits: const ['line', 'temporal', 'era'],
          extra: {'basis': 'frame:chain', 'era': era['era']},
        ),
    },
  );
  for (final (index, era) in eras.indexed) {
    if (index + 1 >= eras.length) continue;
    document = putStaple(
      document,
      id: 'succession:${era['id']}',
      kind: 'succession',
      ends: [StapleEnd.frame('${era['id']}'), StapleEnd.frame('${eras[index + 1]['id']}')],
    ).document;
  }
  return CoordinateLaws(eras: eraLookup(document)).of(document.toJson(), eraId);
}

/// Every law shape a card has to speak, including the two the field reports
/// name by hand: a 23-hour day, and an era chain in both directions.
List<CoordinateLaw> lawsUnderTest() => [
  gregorianLaw,
  lawFrom(twentyThreeHourLadder, 'frame:hour-day-23'),
  lawFrom(customLadder, 'frame:custom'),
  eraLaw(bceCeChain, gregorianLadder, 'era:ce'),
  eraLaw(bceCeChain, gregorianLadder, 'era:bce'),
];
