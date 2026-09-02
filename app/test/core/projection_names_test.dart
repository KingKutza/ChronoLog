// COLUMNS ARE PROJECTIONS, AND PROJECTIONS NAME MORE THAN FRAMES (ISSUES 9.2).
//
// Don: "one column for a frame shows all todos stapled to that frame, another
// all todos stapled to an OBJECT, another only paired todos; or AI Team AND
// Done vs AI Team NOT Done." The algebra exists (or/and/not/xor over frame
// names). The names do not: an object id or a graph predicate is not admitted.

import 'package:chronolog/core/records.dart';
import 'package:test/test.dart';

import '../helpers/projection_scene.dart';

void main() {
  test('a projection may name an object: "stapled to that object" is a term', () {
    final scene = Scene()..calendar('calendar:a');
    final meeting = scene.object(title: 'AI Team meeting', duration: '60');
    final todo = scene.object(title: 'Follow up', duration: '0');
    scene.staple(ends: [ObjectEnd(todo, point: 'start'), ObjectEnd(meeting, point: 'end')]);
    // WORK ITEM (ISSUES 9.2, columns-are-projections): `Projection.parse` binds
    // identifiers to FRAMES only (`frameOf`), and `admits` asks whether a frame
    // is included. There is no seam by which an object id, or a predicate such
    // as "has an object staple", is a name in the algebra. When the seam exists
    // this test asserts that a projection naming `meeting` admits `todo` and
    // rejects an unconnected object, and that `not <object>` is its complement.
    fail(
      'ISSUES 9.2: the projection language admits only frame names. Extend the '
      'binding so an object id ($meeting) and the structural predicates '
      '(has-object-staple) are terms, then assert admits/rejects over a seeded graph here.',
    );
  });
}
