// The op vocabulary's spec.
//
// Three properties carry the whole contract: an op means the same thing however
// many times it is applied, a document is reproducible from its ops, and a diff
// names exactly the records the edit touched. Everything a journal, an undo
// stack and a sync reconciler need rests on those three.

import 'package:chronolog/core/document.dart';
import 'package:chronolog/core/ops.dart';
import 'package:chronolog/core/records.dart';
import 'package:test/test.dart';

import 'corpus.dart';

Set<String> keysOf(Iterable<Op> ops) => {for (final op in ops) '${op.op} ${op.map}/${op.id}'};

void main() {
  test('applying ops twice lands where applying them once did', () {
    for (final seed in seeds(30)) {
      final corpus = Corpus(seed);
      final document = corpus.document();
      final ops = opsFromMaps(mapSnapshot(const Document()), mapSnapshot(document));
      final once = applyOps(const Document(), ops);
      expect(applyOps(once, ops), once, reason: 'seed $seed');
    }
  });

  test('a document is reproducible from the ops that built it', () {
    for (final seed in seeds(30)) {
      final document = Corpus(seed).document();
      final ops = opsFromMaps(mapSnapshot(const Document()), mapSnapshot(document));
      expect(applyOps(const Document(), ops), document, reason: 'seed $seed');
    }
  });

  test('a replay through raw JSON reproduces the document too', () {
    // What a journal file actually hands back: ops whose values have been
    // through text, so the put has to mean the whole record either way.
    for (final seed in seeds(20)) {
      final document = Corpus(seed).document();
      final ops = opsFromMaps(
        mapSnapshot(const Document()),
        mapSnapshot(document),
      ).map((op) => Op.fromJson(op.toJson())).toList();
      expect(applyOps(const Document(), ops), document, reason: 'seed $seed');
    }
  });

  test('a diff emits exactly the touched records and nothing else', () {
    for (final seed in seeds(30)) {
      final corpus = Corpus(seed);
      final document = corpus.document();
      final before = mapSnapshot(document);

      final event = document.events.values.first;
      final relation = document.relations.values.last;
      final minted = corpus.mint('frame');
      final edited = document
          .put('events', event.id, event.copyWith(payload: {'title': 'v2'}))
          .remove('relations', relation.id)
          .put('frames', minted, Frame(id: minted, traits: const ['set']));

      final ops = opsFromMaps(before, mapSnapshot(edited));
      expect(keysOf(ops), {
        'put events/${event.id}',
        'del relations/${relation.id}',
        'put frames/$minted',
      }, reason: 'seed $seed');
      expect(ops.length, 3, reason: 'no spurious puts: seed $seed');
    }
  });

  test('an untouched document emits no ops at all', () {
    for (final seed in seeds(20)) {
      final document = Corpus(seed).document();
      final snapshot = mapSnapshot(document);
      expect(opsFromMaps(snapshot, mapSnapshot(document)), isEmpty);
      // And a put of an equal value is not an edit either.
      final frame = document.frames.values.first;
      final same = document.put('frames', frame.id, frame.toJson());
      expect(opsFromMaps(snapshot, mapSnapshot(same)), isEmpty, reason: '$seed');
    }
  });

  test('touch is one op, and it is the one every commit carries', () {
    final document = Corpus().document();
    final before = mapSnapshot(document);
    final bumped = touch(document, at: DateTime.utc(2030));
    final ops = opsFromMaps(before, mapSnapshot(bumped));
    expect(keysOf(ops), {'put meta/modified'});
    expect(ops.single.value, '2030-01-01T00:00:00.000Z');
  });

  test('the inverse of a bundle undoes it, and undoing is itself an edit', () {
    for (final seed in seeds(20)) {
      final document = Corpus(seed).document();
      final pattern = document.patterns.values.first;
      final before = mapSnapshot(document);
      final deleted = document.remove('patterns', pattern.id);
      final bundle = bundleOps(before, mapSnapshot(deleted));

      expect(keysOf(bundle.ops), {'del patterns/${pattern.id}'});
      expect(keysOf(bundle.inverseOps), {'put patterns/${pattern.id}'});
      expect(applyOps(deleted, bundle.inverseOps), document, reason: '$seed');
    }
  });

  test('an unknown map or verb is refused by name, never skipped', () {
    const document = Document();
    expect(() => applyOps(document, [putOp('nonsense', 'x', 1)]), throwsArgumentError);
    expect(
      () => applyOps(document, [const Op(op: 'merge', map: 'meta', id: 'x')]),
      throwsArgumentError,
    );
    expect(() => applyOps(document, [putOp('meta', '', 1)]), throwsArgumentError);
  });

  test('an op log keeps one entry per commit, in order, and hands them back', () {
    final log = OpLog();
    log.collect('nothing', const []);
    expect(log.length, 0, reason: 'an empty commit is not a commit');
    log.collect('first', [putOp('meta', 'title', 'a')]);
    log.collect('second', [delOp('meta', 'title'), putOp('meta', 'title', 'b')]);
    expect(log.length, 2);
    expect(log.opCount, 3);

    final drained = log.drain();
    expect(log.length, 0);
    expect(drained.map((entry) => entry.label).toList(), ['first', 'second']);
    // A failed write hands them back at the front, so order survives.
    log.collect('third', [putOp('meta', 'title', 'c')]);
    log.restore(drained);
    expect(log.entries.map((entry) => entry.label).toList(), ['first', 'second', 'third']);
    log.clear();
    expect(log.length, 0);
  });
}
