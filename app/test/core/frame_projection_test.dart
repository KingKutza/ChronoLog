// Cross-frame projection exists ONLY through staples.
//
// The property is checked against a union-find over coordinate spaces: unioning
// the two ends of every frame-to-frame staple and asking whether two frames land
// in one component is an independent implementation of the reachability the
// module walks, so the two agreeing says something.
//
// The refusal half matters as much as the affirmative half: with no staple path,
// nothing projects, and the author is TOLD rather than shown a frame that renders
// nothing.

import 'dart:math';

import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/frame_projection.dart';
import 'package:chronolog/core/records.dart';
import 'package:test/test.dart';

import 'corpus.dart';

/// An invented calendar with its OWN origin -- a frame that names positions on
/// its own axis and relates to nothing else. This is Tamriel.
Json _ownAxis(int index) => {
  'kind': 'nested',
  'levels': [
    {'name': 'age'},
    {'name': 'sky-day', 'within': 'age', 'radix': '${300 + index}'},
  ],
  'origin': {'days': '$index'},
};

Document _frame(
  Document document,
  String id, {
  String? basis,
  String? definition,
  Json? coordinate,
  List<String> traits = const ['line', 'temporal'],
}) => document.put(
  'frames',
  id,
  Frame(
    id: id,
    title: 'Frame $id',
    traits: traits,
    extra: {'basis': ?basis, 'coordinateDefinition': ?definition, 'coordinate': ?coordinate},
  ),
);

Document _frameStaple(Document document, String left, String right, int index) => putStaple(
  document,
  id: 'relation:corr-$index',
  kind: 'correspondence',
  ends: [
    StapleEnd.frame(
      left,
      position: Position.coordinate(const {
        'levels': [
          {'level': 'year', 'value': '2026'},
        ],
      }),
    ),
    StapleEnd.frame(
      right,
      position: Position.coordinate(const {
        'levels': [
          {'level': 'age', 'value': '3'},
        ],
      }),
    ),
  ],
).document;

/// Union-find over coordinate spaces.
class _Sets {
  final Map<String, String> _parent = {};

  String find(String id) {
    final up = _parent[id];
    if (up == null || up == id) return _parent[id] = id;
    return _parent[id] = find(up);
  }

  void union(String left, String right) => _parent[find(left)] = find(right);
}

void main() {
  test('random staple graphs: projection is exactly reachability', () {
    for (final seed in seeds(60)) {
      final random = Random(seed);
      final count = 3 + random.nextInt(6);
      var document = createEmptyWorkspaceDocument();
      final ids = <String>['frame:wall-time', 'measure:human-time'];
      for (var index = 0; index < count; index++) {
        final id = 'frame:$index';
        // Three kinds of frame: one inheriting a basis (same space as its
        // basis), one defining coordinates through another (same space again),
        // and one with its own authored origin (its own space entirely).
        switch (random.nextInt(3)) {
          case 0:
            document = _frame(
              document,
              id,
              basis: ids[random.nextInt(ids.length)],
              traits: const ['set', 'calendar'],
            );
          case 1:
            document = _frame(document, id, definition: ids[random.nextInt(ids.length)]);
          default:
            document = _frame(document, id, coordinate: _ownAxis(index));
        }
        ids.add(id);
      }
      final edges = <(String, String)>[];
      for (var index = 0; index < random.nextInt(5); index++) {
        final left = ids[random.nextInt(ids.length)];
        final right = ids[random.nextInt(ids.length)];
        if (left == right) continue;
        document = _frameStaple(document, left, right, index);
        edges.add((left, right));
      }
      // A staple that touches only ONE frame relates nothing: it places an
      // object on a frame and says nothing about any other frame.
      document = putStaple(
        document,
        id: 'relation:placement-staple',
        kind: 'anchor',
        ends: [
          StapleEnd.frame(
            ids[random.nextInt(ids.length)],
            position: Position.coordinate(const {'levels': []}),
          ),
          const StapleEnd.object('event:absent', point: 'start'),
        ],
      ).document;

      final projection = FrameProjection(document.toJson());
      // The independent answer: spaces unioned across every frame-frame staple.
      final sets = _Sets();
      for (final id in ids) {
        sets.union(id, projection.coordinateSpaceOf(id));
      }
      for (final (left, right) in edges) {
        sets.union(left, right);
      }
      for (final from in ids) {
        for (final onto in ids) {
          expect(
            projection.framesProject(from, onto),
            sets.find(from) == sets.find(onto),
            reason: 'seed $seed: $from onto $onto',
          );
        }
      }
    }
  });

  test('RULED ANCHOR: an authored origin is not a claim on a shared axis', () {
    // Two invented calendars, each with its own origin, and no staple between
    // them. Nothing anybody authored relates a position on one to a position on
    // the other, so neither may be drawn on the other's axis.
    var document = createEmptyWorkspaceDocument();
    document = _frame(document, 'frame:tamriel', coordinate: _ownAxis(1));
    document = _frame(document, 'frame:nirn', coordinate: _ownAxis(2));
    final projection = FrameProjection(document.toJson());
    expect(projection.framesProject('frame:tamriel', 'frame:nirn'), isFalse);
    expect(projection.framesProject('frame:tamriel', 'frame:wall-time'), isFalse);
    // Sharing a unit LENGTH is not sharing a position: both ladders count days.
    expect(projection.framesProject('frame:nirn', 'measure:human-time'), isFalse);
    // A frame always projects onto itself.
    expect(projection.framesProject('frame:nirn', 'frame:nirn'), isTrue);

    // "The moment we place a staple, wherever it is, everything projects around
    // that."
    final stapled = FrameProjection(
      _frameStaple(document, 'frame:tamriel', 'frame:wall-time', 0).toJson(),
    );
    expect(stapled.framesProject('frame:tamriel', 'frame:wall-time'), isTrue);
    expect(stapled.framesProject('frame:wall-time', 'frame:tamriel'), isTrue);
    // And only around that: Nirn is still unrelated to either.
    expect(stapled.framesProject('frame:nirn', 'frame:tamriel'), isFalse);
  });

  test('a shared coordinate space needs no staple at all', () {
    var document = createEmptyWorkspaceDocument();
    document = _frame(
      document,
      'calendar:work',
      basis: 'frame:wall-time',
      traits: const ['set', 'calendar'],
    );
    document = _frame(
      document,
      'calendar:home',
      basis: 'frame:wall-time',
      traits: const ['set', 'calendar'],
    );
    document = _frame(document, 'frame:derived', definition: 'calendar:work');
    final projection = FrameProjection(document.toJson());
    for (final from in ['calendar:work', 'calendar:home', 'frame:derived']) {
      for (final onto in ['calendar:work', 'calendar:home', 'frame:wall-time']) {
        expect(projection.framesProject(from, onto), isTrue, reason: '$from/$onto');
      }
    }
    expect(
      projection.coordinateSpaceOf('calendar:home'),
      projection.coordinateSpaceOf('frame:derived'),
    );
  });

  test('a staple reaches every frame of the space it lands in', () {
    var document = createEmptyWorkspaceDocument();
    document = _frame(document, 'frame:tamriel', coordinate: _ownAxis(1));
    document = _frame(
      document,
      'calendar:work',
      basis: 'frame:wall-time',
      traits: const ['set', 'calendar'],
    );
    // The staple lands on Wall Time; the work calendar shares its space.
    document = _frameStaple(document, 'frame:tamriel', 'frame:wall-time', 0);
    final projection = FrameProjection(document.toJson());
    expect(projection.framesProject('frame:tamriel', 'calendar:work'), isTrue);
    expect(projection.framesProject('calendar:work', 'frame:tamriel'), isTrue);
  });

  test('RULED ANCHOR: a refusal names both frames and what to do about it', () {
    var document = createEmptyWorkspaceDocument();
    document = _frame(document, 'frame:tamriel', coordinate: _ownAxis(1));
    document = _frame(document, 'frame:nirn', coordinate: _ownAxis(2));
    final projection = FrameProjection(document.toJson());
    final result = projection.projectableFrames([
      'frame:wall-time',
      'frame:tamriel',
      'frame:nirn',
    ], 'frame:wall-time');
    expect(result.projectable, ['frame:wall-time']);
    expect(result.refused.map((row) => row.frame), ['frame:tamriel', 'frame:nirn']);
    for (final row in result.refused) {
      // The author's OWN titles, both of them, never the internal ids.
      expect(row.message, startsWith(document.frames[row.frame]!.title!));
      expect(row.message, contains('Wall time'));
      expect(row.message, contains('no authored correspondence'));
      expect(row.message, contains('Staple a point between them'));
      expect(row.message, isNot(contains('frame:wall-time')));
    }
    // A frame with no title falls back to its id rather than to a blank.
    document = document.put(
      'frames',
      'frame:untitled',
      Frame(id: 'frame:untitled', extra: {'coordinate': _ownAxis(3)}),
    );
    expect(
      FrameProjection(document.toJson())
          .projectableFrames(const ['frame:untitled'], 'frame:wall-time')
          .refused
          .single
          .message,
      startsWith('frame:untitled has no authored correspondence'),
    );
    // The order given is the order kept: a caller's layering is its own.
    expect(
      projection.projectableFrames(const [
        'frame:nirn',
        'frame:wall-time',
      ], 'frame:nirn').projectable,
      ['frame:nirn'],
    );
  });

  test('an unresolvable or unknown frame relates to nothing but itself', () {
    var document = createEmptyWorkspaceDocument();
    // A declaration the law cannot execute: its own space, and no claim on any
    // other. A broken frame must not silently relate to everything.
    document = _frame(
      document,
      'frame:broken',
      coordinate: const {
        'kind': 'nested',
        'levels': [
          {'name': 'year'},
          {'name': 'month', 'within': 'year', 'transition': 'julian.months'},
        ],
      },
    );
    final projection = FrameProjection(document.toJson());
    expect(projection.coordinateSpaceOf('frame:broken'), 'frame:broken');
    expect(projection.coordinateSpaceOf('frame:absent'), 'frame:absent');
    expect(projection.framesProject('frame:broken', 'frame:wall-time'), isFalse);
    expect(projection.framesProject('frame:absent', 'frame:wall-time'), isFalse);
    expect(projection.framesProject('frame:absent', 'frame:absent'), isTrue);
    // An empty id is not a frame, and asking about one is not an error.
    expect(projection.framesProject('', 'frame:wall-time'), isTrue);
  });
}
