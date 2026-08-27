// The record types' spec: what survives a load and a save.
//
// The properties here are about PRESERVATION, because that is the whole claim
// the record layer makes. The file is the truth, so a document that goes in must
// come out; an unknown relation type is data, so it must come out unchanged; and
// a staple end must be unable to hold two positions at once, so the test for
// that is a type the compiler refuses rather than an assertion.

import 'dart:convert';

import 'package:chronolog/core/coordinate_law.dart';
import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/exact.dart';
import 'package:chronolog/core/records.dart';
import 'package:test/test.dart';

import 'corpus.dart';

final JsonEncoder _pretty = JsonEncoder.withIndent('  ');

String render(Document document) => _pretty.convert(document.toJson());

Document reload(String text) => Document.fromJson(jsonDecode(text) as Json);

void main() {
  test('a rendered document reloads to a byte-identical rendering', () {
    for (final seed in seeds(40)) {
      final document = Corpus(seed).document();
      final once = render(document);
      expect(render(reload(once)), once, reason: 'seed $seed');
    }
  });

  test('reloading is idempotent as a value, not merely as text', () {
    for (final seed in seeds(40)) {
      final document = Corpus(seed).document();
      expect(reload(render(document)), document, reason: 'seed $seed');
    }
  });

  test('unknown relation types round-trip verbatim, field for field', () {
    var seen = 0;
    for (final seed in seeds(40)) {
      final document = Corpus(seed).document();
      final before = jsonDecode(render(document)) as Json;
      final after = jsonDecode(render(reload(render(document)))) as Json;
      final relations = before['relations'] as Map;
      for (final entry in relations.entries) {
        final type = (entry.value as Map)['type'];
        if (!unknownRelationTypes.contains(type)) continue;
        seen++;
        expect(
          (after['relations'] as Map)[entry.key],
          entry.value,
          reason: 'unknown type $type at seed $seed',
        );
      }
    }
    expect(seen, greaterThan(0), reason: 'the corpus must generate some');
  });

  test('an unfamiliar field on a familiar record is preserved in file order', () {
    const text =
        '{"id":"frame:x","title":"T","traits":["line"],'
        '"x-unheard-of":{"deep":[1,null,true]},"basis":"frame:y"}';
    final frame = Frame.fromJson(jsonDecode(text) as Json);
    expect(frame.basis, 'frame:y');
    expect(jsonEncode(frame.toJson()), text);
  });

  test('a record map key order beyond the named fields is the file\'s', () {
    // `id` and `type` are hoisted to the front, which is where every document
    // the JavaScript wrote already puts them; everything after keeps file order.
    const text = '{"id":"r","type":"wormhole","zeta":1,"alpha":2,"middle":3}';
    expect(jsonEncode(Relation.fromJson(jsonDecode(text) as Json).toJson()), text);
  });

  test('empty collections and a false flag are the only normalization', () {
    // Stated so it cannot drift: an explicitly empty array, an explicitly empty
    // magnitude map, and `suppress: false` are dropped on write. Nothing else is
    // touched, and no absent field is ever written back as a default.
    final frame = Frame.fromJson({'id': 'f', 'traits': const <String>[]});
    expect(frame.toJson(), {'id': 'f'});
    final override = Override.fromJson({
      'id': 'o',
      'virtual': 'p/x',
      'suppress': false,
      'replacements': const <String>[],
    });
    expect(override.toJson(), {'id': 'o', 'virtual': 'p/x'});
  });

  test('a staple end names exactly one thing and at most one position', () {
    final ends = [
      StapleEnd.frame('f', position: const Position.coordinate({'levels': []})),
      const StapleEnd.frame('f'),
      const StapleEnd.object('e', point: 'end'),
      const StapleEnd.series('p'),
    ];
    expect(ends.map((end) => end.id).toList(), ['f', 'f', 'e', 'p']);
    expect(ends.map((end) => end.map).toList(), ['frames', 'frames', 'events', 'patterns']);
    // Every end round-trips through its own JSON.
    for (final end in ends) {
      expect(StapleEnd.tryFrom(end.toJson()), end);
    }
    // An end naming nothing is not an end.
    expect(StapleEnd.tryFrom({'point': 'start'}), isNull);
  });

  test('the four position forms are distinct claims, and each round-trips', () {
    final positions = <Position>[
      const Position.coordinate({'levels': []}),
      const Position.selector({'cycle': 'weekday', 'value': 'Tuesday'}),
      const Position.span({
        'from': {'a': 1},
        'to': {'b': 2},
        'note': 'kept',
      }),
      const Position.authoredVoid(),
    ];
    for (final position in positions) {
      final end = StapleEnd.frame('f', position: position);
      expect(StapleEnd.tryFrom(end.toJson()), end);
    }
    // An authored void is a positive claim, and a different one from silence.
    expect(const Position.authoredVoid() == const Position.coordinate({}), isFalse);
    expect(StapleEnd.tryFrom({'frame': 'f'}), const StapleEnd.frame('f'));
  });

  test('there is one coordinate type, and only a coordinate is one instant', () {
    // The typed accessors reach the coordinate-law layer's own `Coordinate`.
    // Nothing here mints a second coordinate shape, and the raw map stays the
    // stored truth so the round-trip above is unaffected by any of this.
    final instant = Position.coordinate(const {
      'levels': [
        {'level': 'year', 'value': '2026'},
      ],
    });
    expect(instant.coordinate, Coordinate.of(const [('year', '2026')]));
    expect(instant.span, isNull);
    expect(instant.selector, isNull);

    // A selector, a span and a void each answer a different question, so none
    // of them collapses to a single coordinate.
    const selector = Position.selector({'cycle': 'weekday', 'value': 'Tuesday'});
    expect(selector.coordinate, isNull);
    expect(selector.selector, {'cycle': 'weekday', 'value': 'Tuesday'});
    expect(const Position.authoredVoid().coordinate, isNull);

    // A span stores its own raw map, so a field inside it this build has never
    // heard of survives alongside the two coordinates it does read.
    final region = Position.span(const {
      'from': {
        'levels': [
          {'level': 'year', 'value': '2026'},
        ],
      },
      'to': {
        'levels': [
          {'level': 'year', 'value': '2027'},
        ],
      },
      'x-why': 'the storm',
    });
    expect(region.coordinate, isNull);
    expect(region.span!.from, Coordinate.of(const [('year', '2026')]));
    expect(region.span!.to, Coordinate.of(const [('year', '2027')]));
    expect(region.toJson()['span'], containsPair('x-why', 'the storm'));

    // A magnitude reads the same way, and the law layer answers it in days
    // through the seam rather than through a second shape.
    final magnitude = durationMagnitude('90', 'minute');
    expect(magnitude.coordinate, Coordinate.of(const [('minute', '90')]));
    expect(CoordinateLaws().durationDays(magnitude), Rational.parse('1/16'));
    expect(CoordinateLaws().durationDays(null), Rational.zero);
  });

  test('the seven record maps are reachable by name, and only those', () {
    final document = Corpus().document();
    for (final map in recordMaps) {
      expect(document.records(map), isNotNull);
    }
    expect(() => document.records('nonsense'), throwsArgumentError);
    expect(recordMapsTyped, recordMaps.sublist(0, 5));
  });

  test('a put carries the whole record, from a record or from raw JSON', () {
    var document = Corpus().document();
    final frame = document.frames.values.first;
    final renamed = frame.copyWith(title: 'Renamed');
    document = document.put('frames', frame.id, renamed);
    expect(document.frames[frame.id], renamed);
    // A journal replay hands back raw JSON, and means the same thing.
    final replayed = document.put('frames', frame.id, frame.toJson());
    expect(replayed.frames[frame.id], frame);
    expect(document.remove('frames', frame.id).frames.containsKey(frame.id), isFalse);
  });
}
