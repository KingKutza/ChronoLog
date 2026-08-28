// View state: the projection a plain selection means, the law-aware span, and
// what survives a trip through the view file.

import 'dart:math';

import 'package:chronolog/core/coordinate_law.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/frame_selection.dart';
import 'package:chronolog/core/projection.dart';
import 'package:chronolog/session/lens_catalog.dart';
import 'package:chronolog/session/settings.dart';
import 'package:chronolog/session/view_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/corpus.dart' show seeds;

Settings _settings() => Settings(defaults: const [sessionTunableDefaults]);

CoordinateLaw _wallLaw() =>
    ProjectionEngine(createEmptyWorkspaceDocument()).lawOf('frame:wall-time');

void main() {
  test('a plain selection is the union of its frames, primary first', () {
    for (final seed in seeds(20)) {
      final random = Random(seed);
      final ids = [for (var index = 0; index < 1 + random.nextInt(5); index++) 'frame:$index'];
      final primary = ids[random.nextInt(ids.length)];
      final view = ViewState(lensId: 'intimate', selection: FrameSelection(ids, primary));
      final projection = view.projection();
      expect(projection.primaryFrame, primary);
      expect(projection.frames.toSet(), ids.toSet());
      for (final id in ids) {
        expect(projection.admits((frame) => frame == id), isTrue, reason: 'any connection reveals');
      }
      expect(projection.admits((frame) => false), isFalse);
    }
  });

  test('a NOT term is the filter, and the negated frame stays in the universe', () {
    final view = ViewState(
      lensId: 'list',
      selection: FrameSelection(['frame:work', 'frame:done'], 'frame:work'),
      negated: {'frame:done'},
    );
    final projection = view.projection();
    expect(projection.primaryFrame, 'frame:work');
    expect(projection.frames.toSet(), {'frame:work', 'frame:done'});
    expect(projection.admits((frame) => frame == 'frame:work'), isTrue);
    expect(projection.admits((frame) => frame != 'frame:__none'), isFalse);
    expect(projection.negatedFrames, contains('frame:done'));
  });

  test('an authored expression wins, in the names the browser bound', () {
    final view = ViewState(lensId: 'list', source: 'work and not done');
    final projection = view.projection(
      bindings: const {'work': 'frame:work', 'done': 'frame:done'},
    );
    expect(projection.frames.toSet(), {'frame:work', 'frame:done'});
    expect(projection.admits((frame) => frame == 'frame:work'), isTrue);
  });

  test('the selection renders as text a person can edit back', () {
    final ids = ['frame:work', 'frame:done'];
    final bindings = ViewState.bindingsFor(ids, (id) => id == 'frame:work' ? 'Work' : 'Done');
    expect(ViewState.textFor(ids, {'frame:done'}, bindings), 'Work and not Done');
  });

  test('a month span asks the law, never 30.4375', () {
    final law = _wallLaw();
    final settings = _settings();
    final strategic = ViewState(lensId: 'strategic');
    expect(
      strategic.spanDays(law, settings),
      settings.value('strategic.months') * law.meanMonthDays(),
    );
    final intimate = ViewState(lensId: 'intimate');
    expect(
      intimate.spanDays(law, settings),
      settings.value('intimate.back') + settings.value('intimate.forward') + Rational.one,
    );
  });

  test('a span formula that will not read falls back to one unit, never to zero', () {
    final view = ViewState(lensId: 'tactical', view: {'rows': 'not a number'});
    expect(view.spanDays(_wallLaw(), _settings()) > Rational.zero, isTrue);
  });

  test('a view reset drops the lens values and keeps the projection and focus', () {
    final view = ViewState(
      lensId: 'tactical',
      selection: FrameSelection(['frame:a']),
      focusDays: Rational.fromInt(42),
    )..write('rows', '3');
    expect(view.number('rows', _settings()), Rational.fromInt(3));
    view.resetView();
    expect(view.number('rows', _settings()), _settings().value('tactical.rows'));
    expect(view.focusDays, Rational.fromInt(42));
    expect(view.selection.selected(), ['frame:a']);
  });

  test('a view round-trips through the view file', () {
    final book = ViewBook(sharedFocus: Rational.fromInt(7));
    book.views['view:1'] = ViewState(
      lensId: 'board',
      selection: FrameSelection(['frame:a', 'frame:b'], 'frame:b'),
      negated: {'frame:a'},
      view: {'grouping': 'frame'},
    );
    final written = book.toJson();
    final read = ViewBook()..applyJson(written);
    expect(read.toJson(), written);
    expect(read.views['view:1']!.selection.primary(), 'frame:b');
  });

  test('a lens the user never saw is born visible, after the order they authored', () {
    final book = ViewBook()..lensOrder = ['board', 'list'];
    expect(book.visibleLenses.take(2), ['board', 'list']);
    expect(book.visibleLenses.length, lensCatalog.length);
    book.setHidden('board', true);
    expect(book.visibleLenses, isNot(contains('board')));
    expect(book.visibleLenses.first, 'list');
  });
}
