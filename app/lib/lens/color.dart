// The authored color cascade (AGENTS.md "Visual grammar"), implemented once.
//
// MEANING IS AUTHORED, NEVER INFERRED. No color comes from a trait string, a
// title, an imported category, or a hash of an id. The web build's last two
// inferences died here: `traits.includes("celestial") ? "#6d63b8" : "#d4552d"`
// and the reserved-time title regex. When nothing is authored the answer is
// NEUTRAL INK -- which is honest, and which the sigil already keeps meaningful,
// because shape carries structural role and color never carries it alone.
//
// The four steps, in order:
//   1. an explicit color on the object (the pattern's template for an occurrence);
//   2. a group's color -- a group explicitly in the projection wins, then the
//      group with the most object members, then authored order, then id;
//   3. the temporal frame -- primary first, then the frame supplying this fact,
//      then its other authored attachments;
//   4. neutral ink.
//
// Lens renderers must not choose colors independently. There is one entry point.

import 'package:flutter/widgets.dart';

import '../core/projection.dart';
import '../core/records.dart';
import 'theme.dart';

/// THE colour a record itself authors: an explicit `color`, or one under its
/// `display` handling. Null when the record authors none -- meaning is authored,
/// so an unauthored record gets neutral ink and never an inferred colour.
///
/// One reader for every record in the program: a frame's ink, an object's ink
/// and a node's ink are the same question asked of the same field.
Color? authoredColorOf(Json? extra) =>
    parseColor(extra?['color']) ?? parseColor(obj(extra?['display'])?['color']);

/// Memoizes group sizes for one paint. Group size is the cascade's ordering
/// signal AND the weight fold's tie-break, so counting it once per pass rather
/// than once per mark is what keeps a 500-calendar document drawable.
class ColorCascade {
  ColorCascade(this.engine, this.projection, this.theme);

  final ProjectionEngine engine;
  final Projection projection;
  final ChronoTheme theme;
  final Map<String, int> _sizes = {};

  int sizeOf(String frameId) => _sizes[frameId] ??= engine.indexes.memberObjects(frameId).length;

  /// The source object a fact's color is read from: a generated occurrence has
  /// no authorship of its own, so it wears its template's.
  String sourceOf(Fact fact) => fact.virtualId.isEmpty
      ? fact.event.id
      : engine.document.patterns[fact.pattern]?.templateEvent ?? fact.event.id;

  /// Every frame the object is a member of, transitively -- one authored hop
  /// upward, then every group each of those sits inside. Membership, not
  /// placement: placement is step three's business.
  List<String> groupsOf(String objectId) {
    final found = <String>{};
    for (final direct in engine.indexes.directGroupsOf(objectId)) {
      found.addAll(engine.framesAbove(direct).keys);
    }
    return found.toList();
  }

  Color colorOf(Fact fact) {
    final sourceId = sourceOf(fact);
    final source = engine.document.events[sourceId];
    final own = authoredColorOf(source?.extra) ?? authoredColorOf(fact.event.extra);
    if (own != null) return own;

    final groups = groupsOf(sourceId);
    final candidates = <({String id, Color color, bool named, int size, int order})>[];
    for (final (order, id) in groups.indexed) {
      final color = authoredColorOf(engine.document.frames[id]?.extra);
      if (color == null) continue;
      candidates.add((
        id: id,
        color: color,
        named: projection.frames.contains(id),
        size: sizeOf(id),
        order: order,
      ));
    }
    if (candidates.isNotEmpty) {
      candidates.sort((a, b) {
        if (a.named != b.named) return a.named ? -1 : 1;
        if (a.size != b.size) return b.size.compareTo(a.size);
        return a.order != b.order ? a.order.compareTo(b.order) : a.id.compareTo(b.id);
      });
      return candidates.first.color;
    }

    // Step three, in rank order and deduped, so the frame a person is LOOKING
    // through wins over the one that merely also holds the object.
    final primary = projection.primaryFrame;
    final ranked = <String>{
      ?primary,
      if (fact.relation.frame case final String frame) frame,
      ...engine.indexes.framesOf(sourceId),
    };
    for (final id in ranked) {
      if (groups.contains(id)) continue;
      final color = authoredColorOf(engine.document.frames[id]?.extra);
      if (color != null) return color;
    }
    return theme.neutral;
  }
}
