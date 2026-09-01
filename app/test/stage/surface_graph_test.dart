// FROM ANYWHERE, REACH ANYTHING (ISSUES 9.1, Don, twice ruled).
//
// "Every card that exists in the system — is there a button on another card to
// open it? Green only if the graph is fully connected." And then the
// correction that grew the law: the universe is not the card factory's eight —
// it is EVERY SURFACE: "9 lenses, 3 bars, 1 minimap, an object editor, a frame
// editor, a frames menu, 5–20 settings menus, a document/save menu… 22–37."
// And the ancestor ruling that pinned the mechanism: every content inherits
// one ancestor, "and that ancestor is what our test checks graph connectivity
// against."
//
// So the universe here is [tileContents] after the SHIPPED registration — the
// same call boot makes — and the edges are found by crawling each content's
// real affordances: every tappable pressed (menus opened and their rows
// pressed too), plus one right-click probe for the painter surfaces whose
// verbs live on the context menu, with a lens swap counted as the navigation
// it is. An edge is whatever lands a registered content on the stage through
// the one seam every open goes through.
//
// The settings family shares one body, so ONE representative sub-card is
// crawled for the family's outbound edges and the rest inherit them — while
// every sub-card's INBOUND edge is real, found by pressing the main card's own
// launchers one by one. Stated here, not hidden: it is a runtime budget, not a
// claim that the family differs.
//
// RED: the graph is not fully connected. YELLOW (warned, never failed):
// fewer than two ways in, dead ends, longest traversal over five clicks,
// average over four (Don's bands, plus the butter ruling: "being able to just
// move around the app in a seamless way is important").

import 'dart:math';

import 'package:chronolog/app.dart' show registerShippedLenses;
import 'package:chronolog/cards/card_factory.dart';
import 'package:chronolog/cards/frame_card.dart';
import 'package:chronolog/chrome/controls.dart';
import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/records.dart';
import 'package:chronolog/edit/editor.dart';
import 'package:chronolog/lens/view_tile.dart';
import 'package:chronolog/session/lens_catalog.dart';
import 'package:chronolog/session/view_state.dart';
import 'package:chronolog/stage/content.dart';
import 'package:chronolog/stage/tile.dart';
import 'package:chronolog/store/document_store.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../cards/harness.dart';
import '../store/harness.dart';

typedef GraphBench = ({Editor editor, CardFactory factory, Chrome chrome, Surface surface});

/// The record every lens-swap lands in: a swap is navigation — the box now
/// shows that content — so it is an edge exactly as an open is.
final List<String> swappedTo = [];

/// A fresh bench per crawl, seeded with one frame and one event so record-bound
/// contents have a record, wired exactly as boot wires the real app — the same
/// doors, the same registration.
Future<GraphBench> graphBench() async {
  // The painters, exactly as boot registers them: a lens with no painter
  // renders its stated gap, and a gap has no verbs for the crawl to find.
  registerShippedLenses();
  final store = DocumentStore(
    dataRoot: 'memory',
    files: MemoryFiles(),
    scheduler: ManualScheduler(),
    establish: () => createEmptyWorkspaceDocument().put(
      'frames',
      'frame:work',
      const Frame(id: 'frame:work', title: 'Work', traits: ['set', 'calendar']),
    ),
  );
  await store.load();
  final settings = chronologSettings();
  final editor = Editor(store, settings: settings.tunable);
  // Two events: one placed plainly on wall time, one stapled to the document's
  // FIRST frame — the one a record-bound content samples — so the frame card's
  // "stapled here" door has something real to show the crawl.
  editor.createAt('frame:wall-time', Rational.fromInt(20000), null);
  editor.createAt(
    'frame:wall-time',
    Rational.fromInt(20000),
    null,
    stapledTo: editor.document.frames.keys.first,
  );
  final views = ViewBook()..defaultFrames = ['frame:wall-time'];
  final stage = Stage(
    tunable: settings.tunable,
    settings: settings,
    onLens: (tile, lensId) {
      swappedTo.add('lens:$lensId');
      views.setLens(tile, lensId);
    },
  );
  final factory = CardFactory(editor, settings, stage, bodies: frameCardBodies);
  final surface = (
    editor: editor,
    settings: settings,
    views: views,
    stage: stage,
    objectCard: factory.objectCard,
    frameCard: factory.frameCard,
    settingsCard: factory.settingsCard,
  );
  final chrome = Chrome(
    settings: settings,
    stage: stage,
    views: views,
    editor: editor,
    cards: {
      'document': factory.documentCard,
      'frames': factory.framesBrowser,
      'newFrame': factory.newFrameCard,
      'settings': factory.settingsCard,
      'themes': factory.themesCard,
    },
    viewTile: (id) => viewTileSpec(id, surface),
    openFrame: (id) => stage.open(factory.frameCard(id)),
    openSettings: (area) => stage.open(factory.settingsCard(area: area)),
  );
  tileContents.clear();
  registerShippedContents(factory: factory, surface: surface);
  // A focused view tile, as boot provides one: the bars and the frames
  // surfaces refuse without it, and a refusing content shows the crawl none of
  // its doors.
  // The LAST catalog lens, on purpose: a lens the view is born showing can
  // never be swapped TO, so the born lens would read as unreachable however
  // many chips swap to it — every other lens earns its inbound edge from the
  // view bar, and the born one earns its own from the "open in a new view"
  // rows.
  stage.open(tileContents.values.whereType<LensContent>().last.spec('view:1'));
  return (editor: editor, factory: factory, chrome: chrome, surface: surface);
}

/// The registered kind a stage tile answers to, or null for a tile no content
/// claims. THE derivation the whole file reads edges through.
String? kindOf(GraphBench bench, String tileId) {
  final spec = bench.chrome.stage.tiles[tileId];
  if (spec == null) return null;
  return switch (spec.type) {
    'view' => 'lens:${bench.surface.views.of(tileId).lensId}',
    'minimap' => 'minimap',
    'bar' => 'bar:${spec.klass}',
    'card' when spec.klass == 'settings' =>
      tileId == 'card:settings:one' ? 'card:settings' : tileId,
    'card' => 'card:${spec.klass}',
    _ => null,
  };
}

const CardRequest _shellRequest = (
  klass: '',
  id: null,
  kind: null,
  frameId: null,
  startDays: null,
  endDays: null,
);

Future<void> pumpContent(WidgetTester tester, GraphBench bench, TileSpec spec) => pumpCard(
  tester,
  bench.chrome,
  CardHost(
    factory: bench.factory,
    request: _shellRequest,
    tileId: '',
    child: SizedBox(
      height: cardSurface.height,
      child: Builder(builder: (context) => spec.build(context)),
    ),
  ),
);

Finder tappables() => find.byWidgetPredicate(
  (widget) => widget is InkWell || (widget is GestureDetector && widget.onTap != null),
);

Future<void> settle(WidgetTester tester) async {
  for (var frame = 0; frame < 4; frame++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<void> tapNth(WidgetTester tester, int index) async {
  final wells = tappables();
  if (index >= tester.widgetList(wells).length) return;
  try {
    await tester.tap(wells.at(index), warnIfMissed: false);
  } catch (_) {
    // A tap that throws opened nothing; the diff says so.
  }
  await settle(tester);
}

/// One right-click at the pumped surface's centre: the painter lenses keep
/// their verbs on the context menu, and a crawl that never right-clicks would
/// call every one of them a dead end it is not.
Future<void> secondaryProbe(WidgetTester tester) async {
  try {
    await tester.tap(
      find.byType(SizedBox).first,
      warnIfMissed: false,
      buttons: kSecondaryMouseButton,
    );
  } catch (_) {}
  await settle(tester);
}

void main() {
  testWidgets('from anywhere, reach anything: the surface graph is fully connected', (
    tester,
  ) async {
    await graphBench();
    final universe = tileContents.keys.toSet();
    expect(universe.length, greaterThan(20), reason: 'the whole surface count, derived');

    // One representative for the settings family; the rest inherit its
    // outbound edges (one body, one crawl — stated above).
    final family = [
      for (final kind in universe)
        if (kind.startsWith('card:settings:')) kind,
    ]..sort();
    final crawled = [
      for (final kind in universe)
        if (!kind.startsWith('card:settings:') || kind == family.first) kind,
    ];

    final edges = <String, Set<String>>{for (final kind in universe) kind: {}};

    for (final kind in crawled) {
      final bench = await graphBench();
      final content = tileContents[kind]!;
      final stage = bench.chrome.stage;

      Set<String> opened(Set<String> before, List<String> swapsBefore) => {
        for (final id in stage.tiles.keys)
          if (!before.contains(id))
            if (kindOf(bench, id) case final String found) found,
        ...swappedTo.skip(swapsBefore.length),
      };

      final spec = content.spec('probe:${content.kind}');
      // The crawl measures DOORS, not stateful outcomes: a verb pressed in an
      // earlier round (Hide, say) must not erase a later round's doors, so
      // hidden lenses are restored before every pump.
      Future<void> pumpFresh() async {
        for (final lensId in lensCatalog.keys) {
          bench.surface.views.setHidden(lensId, false);
        }
        await pumpContent(tester, bench, spec);
      }

      await pumpFresh();
      const budget = 64;
      final surface = min(tester.widgetList(tappables()).length, budget);

      // Round -1: the right-click probe, then everything it revealed.
      await pumpFresh();
      var before = stage.tiles.keys.toSet();
      var swaps = [...swappedTo];
      await secondaryProbe(tester);
      final revealed = min(tester.widgetList(tappables()).length, budget);
      for (var j = 0; j < revealed; j++) {
        before = stage.tiles.keys.toSet();
        swaps = [...swappedTo];
        await tapNth(tester, j);
        edges[kind]!.addAll(opened(before, swaps));
        if (tester.widgetList(tappables()).length < revealed) await secondaryProbe(tester);
      }

      // Rounds 0..n: every resting tappable, two levels deep.
      for (var i = 0; i < surface; i++) {
        await pumpFresh();
        before = stage.tiles.keys.toSet();
        swaps = [...swappedTo];
        await tapNth(tester, i);
        edges[kind]!.addAll(opened(before, swaps));
        final grown = min(tester.widgetList(tappables()).length, surface + budget);
        for (var j = surface; j < grown; j++) {
          before = stage.tiles.keys.toSet();
          swaps = [...swappedTo];
          await tapNth(tester, j);
          edges[kind]!.addAll(opened(before, swaps));
          if (tester.widgetList(tappables()).length <= surface) await tapNth(tester, i);
        }
      }
      // Round n+1: every WORD the surface wears, pressed once. A control's
      // label is a door, and a detector-centre tap can miss a chip whose ink
      // sits beside its word — the crawl found nine of ten lens chips that way
      // and missed the first, so the words get their own round.
      await pumpFresh();
      final words = <String>{
        for (final text in tester.widgetList<Text>(find.byType(Text)))
          if (text.data case final String data when data.trim().isNotEmpty) data,
      }.take(budget).toList();
      for (final word in words) {
        await pumpFresh();
        before = stage.tiles.keys.toSet();
        swaps = [...swappedTo];
        try {
          await tester.tap(find.text(word).first, warnIfMissed: false);
        } catch (_) {}
        await settle(tester);
        edges[kind]!.addAll(opened(before, swaps));
      }
      edges[kind]!.remove(kind);
    }

    // The family inherits the representative's outbound edges.
    for (final kind in family.skip(1)) {
      edges[kind] = {...edges[family.first]!}..remove(kind);
    }

    // The verdicts: red on disconnection, yellow on fraying (Don's bands).
    final inbound = {
      for (final kind in universe)
        kind: {
          for (final from in universe)
            if (from != kind && edges[from]!.contains(kind)) from,
        },
    };
    final reached = <String>{universe.first};
    for (var grew = true; grew;) {
      grew = false;
      for (final kind in universe) {
        if (reached.contains(kind)) continue;
        final touches =
            edges[kind]!.any(reached.contains) ||
            reached.any((other) => edges[other]!.contains(kind));
        if (touches) {
          reached.add(kind);
          grew = true;
        }
      }
    }
    final orphans = [
      for (final kind in universe)
        if (inbound[kind]!.isEmpty) kind,
    ]..sort();
    final unreachable = [
      for (final kind in universe)
        if (!reached.contains(kind)) kind,
    ]..sort();

    final thin = [
      for (final kind in universe)
        if (inbound[kind]!.length < 2) '$kind (${inbound[kind]!.length} in)',
    ]..sort();
    final deadEnds = [
      for (final kind in universe)
        if (edges[kind]!.where((to) => to != kind).isEmpty) kind,
    ]..sort();
    var longest = 0, total = 0, pairs = 0;
    for (final from in universe) {
      final distance = <String, int>{from: 0};
      var frontier = [from];
      while (frontier.isNotEmpty) {
        final next = <String>[];
        for (final at in frontier) {
          for (final to in edges[at]!) {
            if (distance.containsKey(to)) continue;
            distance[to] = distance[at]! + 1;
            next.add(to);
          }
        }
        frontier = next;
      }
      for (final entry in distance.entries) {
        if (entry.key == from) continue;
        longest = longest < entry.value ? entry.value : longest;
        total += entry.value;
        pairs += 1;
      }
    }
    final average = pairs == 0 ? 0.0 : total / pairs;
    final yellow = [
      if (thin.isNotEmpty) 'fewer than two ways in: ${thin.join(', ')}',
      if (deadEnds.isNotEmpty) 'dead ends (no way onward): ${deadEnds.join(', ')}',
      if (longest > 5) 'longest traversal is $longest clicks (over 5)',
      if (average > 4) 'average traversal is ${average.toStringAsFixed(2)} clicks (over 4)',
    ];
    if (yellow.isNotEmpty) {
      debugPrint('YELLOW — surface graph sturdiness (ISSUES 9.1):\n  ${yellow.join('\n  ')}');
    }

    final found = [
      for (final kind in universe)
        for (final to in edges[kind]!) '$kind -> $to',
    ]..sort();
    expect(
      orphans.isEmpty && unreachable.isEmpty,
      isTrue,
      reason:
          'The surface graph is not fully connected (ISSUES 9.1).\n'
          'No affordance on any other surface opens: ${orphans.join(', ')}.\n'
          'Not reached from ${universe.first}: ${unreachable.join(', ')}.\n'
          'Edges found by the crawl:\n  ${found.join('\n  ')}',
    );
  }, timeout: const Timeout(Duration(minutes: 45)));
}
