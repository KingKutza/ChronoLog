// A BOARD IS A NAMED SUBTREE, SAVED WHERE LAYOUTS ARE (ISSUES 9.2, Don's rulings).
//
// "I should be able to author boards ... save column layouts and filters, and
// have a few sets I work between." Verified: a view's state lives in the
// session's view file PER VIEW TILE ID -- unnamed, bound to the tile, gone when
// the tile closes. Don's answers: named views live where persistent layouts
// live (the layout file in the data root); presets and boards are one record
// kind -- a named subtree whose leaves are projection tiles (columns) plus the
// lens tunables; a view tile SHOWS a named view.
//
// And the settings-undo ruling frames what a named view IS: "a write a GESTURE
// produced -- pan, zoom, focus, which tile the eye is on -- is where you are
// looking rather than what you said ... This also settles what a named view is:
// exactly the second category, made durable on purpose." So a named view is
// view state -- lens, projection expression, columns in order, the lens's own
// keys -- given a name and written into the layout file, and NOT the focus,
// which is where the eye happened to be.
//
// THE CONTRACT this file names, which does not exist yet -- on the Stage,
// because the Stage is what the layout file holds:
//
//   stage.presets                       -- ONE map, presets and views alike
//   stage.savePreset(name, {ViewBook? views})
//       saves the arrangement AND, when a book is handed in, the view state of
//       every view leaf in it
//   stage.saveView(name, tileId, ViewState state)
//       a one-leaf preset: that tile's view state under a name
//   stage.showView(name, tileId, ViewBook views)
//       the tile now shows the named view -- copies the saved state onto the
//       tile's ViewState (lens, source, selection, negated, view map), leaving
//       its focus alone
//   stage.applyPreset(name, {ViewBook? views})
//       as today, and when a book is handed in restores each view leaf's state
//   stage.toJson() / applyJson()        -- carry all of it, byte for byte
//
// Nothing in the DOCUMENT changes: "the document does not carry them."

import 'dart:convert';

import 'package:chronolog/chrome/shell.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/session/view_state.dart';
import 'package:chronolog/stage/layout_tree.dart';
import 'package:chronolog/stage/tile.dart';
import 'package:flutter/widgets.dart';
import 'package:test/test.dart';

TileSpec spec(String id, {String type = 'view', String klass = 'lens'}) => TileSpec(
  id: id,
  type: type,
  klass: klass,
  title: id,
  build: (_) => const SizedBox.shrink(),
);

/// A view state as the file would hold it, minus where the eye was.
Map<String, Object?> saidOf(ViewState state) => {...state.toJson()}..remove('focus');

/// An authored board: the board lens, an expression over two frames, two
/// columns each its own expression, and one lens key said differently.
ViewState authoredBoard(ViewBook views, String tileId) {
  final state = views.of(tileId);
  state.lensId = 'board';
  state.source = 'AI_Team and not Done';
  state.selection.toggle('frame:ai');
  state.selection.toggle('frame:done');
  state.negated.add('frame:done');
  state.write('grouping', 'frame');
  state.write('columns', ['AI_Team and not Done', 'AI_Team and Done']);
  state.write('span', '30');
  state.focusDays = Rational.fromInt(20500);
  return state;
}

/// The layout file, written and read back: what survives a restart.
Stage reloaded(Stage stage) => Stage(tunable: chronologSettings().tunable)
  ..applyJson(jsonDecode(jsonEncode(stage.toJson())) as Map<String, Object?>);

void main() {
  test('a named view survives its tile and is shown by another', () {
    final settings = chronologSettings();
    final views = ViewBook();
    final stage = Stage(tunable: settings.tunable, onLens: views.setLens);
    stage.open(spec('view:1'));
    final authored = authoredBoard(views, 'view:1');
    final said = saidOf(authored);
    stage.saveView('AI board', 'view:1', authored);
    // The tile goes; the view file's per-tile state goes with it.
    stage.close('view:1');
    views.views.remove('view:1');
    // A restart: the layout file is all that is left.
    final again = reloaded(stage);
    expect(
      again.presets.keys,
      contains('AI board'),
      reason:
          'ISSUES 9.2: views are unnamed per-tile state in the view file; the layout file holds '
          'no named view, so closing the tile loses the board.',
    );
    final fresh = ViewBook();
    again.open(spec('view:2'));
    again.showView('AI board', 'view:2', fresh);
    final shown = fresh.of('view:2');
    expect(
      saidOf(shown),
      equals(said),
      reason:
          'the named view round-trips byte for byte: lens, expression, columns in order with their '
          'own expressions, and the lens keys',
    );
    expect(
      shown.focusDays,
      isNot(equals(authored.focusDays)),
      reason: 'the focus is where the eye was, not what was said; a named view does not carry it',
    );
  });

  test('layout presets and boards are one record kind', () {
    // "Presets and boards are one record kind (named subtrees) in that file." A
    // preset is a named subtree whose leaves are any tiles; a board is one whose
    // leaves are column tiles. One record, two uses: a preset can hold a board's
    // view state, and a saved view is a one-leaf preset that lays out.
    final settings = chronologSettings();
    final views = ViewBook();
    final stage = Stage(tunable: settings.tunable, onLens: views.setLens);
    stage.open(spec('view:1'));
    stage.open(spec('card:a', type: 'card', klass: 'object'));
    stage.open(spec('view:2'));
    final board = saidOf(authoredBoard(views, 'view:1'));
    views.of('view:2').lensId = 'lines';
    views.of('view:2').write('days', '7/2');
    final lines = saidOf(views.of('view:2'));
    stage.savePreset('desk', views: views);
    stage.saveView('AI board', 'view:1', views.of('view:1'));
    expect(
      stage.presets.keys,
      containsAll(['desk', 'AI board']),
      reason: 'ISSUES 9.2: one map holds both; there is no second record kind for a board',
    );
    // Scramble what the tiles show, then the preset brings back both the
    // arrangement and what each tile looked through.
    final again = reloaded(stage);
    final fresh = ViewBook();
    for (final id in ['view:1', 'view:2']) {
      again.open(spec(id));
      fresh.of(id).lensId = 'intimate';
    }
    again.open(spec('card:a', type: 'card', klass: 'object'));
    again.applyPreset('desk', views: fresh);
    expect(leavesOf(again.root).map((leaf) => leaf.id).toSet(), {'view:1', 'card:a', 'view:2'});
    expect(saidOf(fresh.of('view:1')), equals(board), reason: 'the preset restored the board');
    expect(saidOf(fresh.of('view:2')), equals(lines), reason: 'and the Lines tile beside it');
    // And the one-leaf record lays out like any preset: applying the saved view
    // adopts a view tile and shows the board in it.
    final lone = reloaded(stage);
    final book = ViewBook();
    lone.open(spec('view:9'));
    lone.applyPreset('AI board', views: book);
    final adopted = leavesOf(lone.root).where((leaf) => leaf.type == 'view').map((leaf) => leaf.id);
    expect(adopted, hasLength(1), reason: 'a saved view is a one-leaf arrangement');
    expect(
      saidOf(book.of(adopted.single)),
      equals(board),
      reason: 'ISSUES 9.2: a board can be preset -- the one record, used the other way',
    );
  });
}
