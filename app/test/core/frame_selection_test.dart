// Frame selection: ordered ids plus an explicit primary.
//
// The 8.19 field report was that reassigning the leading frame silently dropped
// every companion. So the spec is not a list of scenarios -- it is the four
// invariants, checked after every operation of a RANDOM operation sequence, which
// is the only way to say "no sequence of clicks can break this".

import 'dart:math';

import 'package:chronolog/core/frame_selection.dart';
import 'package:test/test.dart';

import 'corpus.dart';

List<String> _pool(int size) => [for (var i = 0; i < size; i++) 'calendar:$i'];

/// The four invariants, together, after every single operation.
void _holds(FrameSelection selection, String after) {
  final selected = selection.selected();
  expect(selected, isNotEmpty, reason: 'never empty: $after');
  expect(
    selection.primary(),
    isNotNull,
    reason: 'a non-empty selection always leads with something: $after',
  );
  expect(selected, contains(selection.primary()), reason: 'the primary is a member: $after');
  expect(selected.first, selection.primary(), reason: 'primary first: $after');
  expect(selected.toSet(), hasLength(selected.length), reason: 'no duplicates: $after');
  for (final id in selected) {
    expect(selection.isSelected(id), isTrue, reason: after);
  }
  expect(selection.isPrimary(selection.primary()!), isTrue, reason: after);
}

void main() {
  test('random operation sequences: every invariant holds throughout', () {
    for (final seed in seeds(60)) {
      final random = Random(seed);
      final pool = _pool(2 + random.nextInt(6));
      final selection = FrameSelection([pool.first]);
      _holds(selection, 'construction');
      for (var step = 0; step < 30; step++) {
        final id = pool[random.nextInt(pool.length)];
        final before = selection.selected().toSet();
        switch (random.nextInt(4)) {
          case 0:
            selection.toggle(id);
            _holds(selection, 'seed $seed step $step toggle $id');
          case 1:
            selection.setPrimary(id);
            _holds(selection, 'seed $seed step $step setPrimary $id');
            expect(selection.primary(), id, reason: 'setPrimary always lands the marker');
            // MEMBERSHIP IS NEVER REDUCED by moving the marker. This is the
            // 8.19 regression, stated as an invariant.
            expect(
              selection.selected().toSet(),
              containsAll(before),
              reason: 'seed $seed step $step: setPrimary dropped a frame',
            );
          case 2:
            final wanted = [
              for (final candidate in pool)
                if (random.nextBool()) candidate,
            ];
            selection.setSelection(wanted);
            _holds(selection, 'seed $seed step $step setSelection $wanted');
            if (wanted.isEmpty) {
              expect(
                selection.selected().toSet(),
                before,
                reason: 'an empty list is refused outright',
              );
            } else {
              expect(selection.selected().toSet(), wanted.toSet());
            }
          default:
            final valid = [
              for (final candidate in pool)
                if (random.nextBool()) candidate,
            ];
            selection.prune(valid);
            _holds(selection, 'seed $seed step $step prune $valid');
            if (valid.isEmpty) {
              expect(
                selection.selected().toSet(),
                before,
                reason: 'no frames loaded yet is not proof the selection is wrong',
              );
            } else {
              expect(
                selection.selected().every(valid.contains),
                isTrue,
                reason: 'seed $seed step $step',
              );
            }
        }
      }
    }
  });

  test('the last remaining id can never be toggled away', () {
    for (final seed in seeds(20)) {
      final random = Random(seed);
      final pool = _pool(1 + random.nextInt(5));
      final selection = FrameSelection(pool);
      // Toggle everything off, in a random order, as many times as it takes.
      for (var step = 0; step < pool.length * 3; step++) {
        selection.toggle(pool[random.nextInt(pool.length)]);
        _holds(selection, 'seed $seed');
      }
      expect(selection.selected(), isNotEmpty);
    }
  });

  group('ruled anchors', () {
    test('a fresh selection leads with the first id given', () {
      final selection = FrameSelection(['calendar:a', 'calendar:b']);
      expect(selection.primary(), 'calendar:a');
      expect(selection.selected(), ['calendar:a', 'calendar:b']);
    });

    test('an explicit primary wins, but only when it is a member', () {
      expect(FrameSelection(['calendar:a', 'calendar:b'], 'calendar:b').selected(), [
        'calendar:b',
        'calendar:a',
      ]);
      expect(FrameSelection(['calendar:a'], 'calendar:nowhere').primary(), 'calendar:a');
    });

    test('adding a companion never moves the marker', () {
      final selection = FrameSelection(['calendar:a']);
      selection.toggle('calendar:b');
      expect(selection.isSelected('calendar:b'), isTrue);
      expect(selection.primary(), 'calendar:a');
    });

    test('toggling the primary out promotes the id that followed it', () {
      final selection = FrameSelection(['calendar:a', 'calendar:b', 'calendar:c']);
      selection.toggle('calendar:a');
      expect(selection.primary(), 'calendar:b');
      expect(selection.selected().toSet(), {'calendar:b', 'calendar:c'});
    });

    test('toggling out the last-positioned primary wraps to the new first', () {
      final selection = FrameSelection(['calendar:a', 'calendar:b'], 'calendar:b');
      selection.toggle('calendar:b');
      expect(selection.primary(), 'calendar:a');
    });

    test('RULED ANCHOR: setPrimary reassigns the marker, and nothing else', () {
      final selection = FrameSelection(['calendar:a', 'calendar:b', 'calendar:c']);
      selection.setPrimary('calendar:c');
      expect(selection.primary(), 'calendar:c');
      expect(selection.selected().toSet(), {'calendar:a', 'calendar:b', 'calendar:c'});
    });

    test('setPrimary on an outsider adds it rather than replacing', () {
      final selection = FrameSelection(['calendar:a']);
      selection.setPrimary('calendar:b');
      expect(selection.primary(), 'calendar:b');
      expect(selection.isSelected('calendar:a'), isTrue);
    });

    test('setSelection keeps a surviving primary, otherwise the first offered', () {
      final selection = FrameSelection(['calendar:a']);
      selection.setSelection(['calendar:b', 'calendar:a', 'calendar:c']);
      expect(selection.primary(), 'calendar:a');
      selection.setSelection(['calendar:b', 'calendar:c']);
      expect(selection.primary(), 'calendar:b');
    });

    test('prune reassigns a stale primary, and falls back only if it must', () {
      final wide = FrameSelection(['calendar:a', 'calendar:b', 'calendar:c']);
      wide.prune(['calendar:b', 'calendar:c']);
      expect(wide.primary(), 'calendar:b');
      final orphan = FrameSelection(['calendar:a']);
      orphan.prune(['calendar:b', 'calendar:c']);
      expect(orphan.primary(), 'calendar:b');
    });

    test('an empty or blank id is not a selection', () {
      final selection = FrameSelection(['', 'calendar:a', '']);
      expect(selection.selected(), ['calendar:a']);
      selection.toggle('');
      selection.setPrimary('');
      expect(selection.selected(), ['calendar:a']);
    });
  });
}
