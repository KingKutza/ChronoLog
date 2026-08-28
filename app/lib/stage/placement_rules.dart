// Where a newly opened tile lands: an ordered rule list, matched top down, each
// rule falling through when it cannot place. Match by type, class, or a
// predicate in the one math; place by tabbing with the newest of a kind,
// splitting the focused tile, or dropping into a named container.
//
// Predicate names are identifier-shaped because the one math tokenizes
// identifiers, not dotted paths: `countOfType`, `countOfClass`, `tabsInTarget`,
// `leaves`.

import '../core/exact.dart';
import '../core/math.dart';
import 'layout_tree.dart';

typedef Placement = ({
  String action,
  String? targetId,
  String axis,
  Rational ratio,
  bool before,
  String? container,
});

class PlacementRule {
  const PlacementRule({
    this.type,
    this.klass,
    this.predicate,
    required this.action,
    this.axis = 'row',
    this.ratio = '1/2',
    this.maxTabs,
    this.container,
    this.before = false,
  });

  /// Null matches anything. [predicate] is a one-math truth expression.
  final String? type, klass, predicate;

  /// `tabWithNewest` | `splitFocused` | `into`.
  final String action;

  final String axis;

  /// One-math expressions, so a rule ships no bare number either.
  final String ratio;
  final String? maxTabs;

  final String? container;
  final bool before;

  Map<String, Object?> toJson() => {
    'action': action,
    'axis': axis,
    'ratio': ratio,
    if (type != null) 'type': type,
    if (klass != null) 'class': klass,
    if (predicate != null) 'predicate': predicate,
    if (maxTabs != null) 'maxTabs': maxTabs,
    if (container != null) 'container': container,
    if (before) 'before': true,
  };

  static PlacementRule? fromJson(Object? source) {
    if (source is! Map || source['action'] == null) return null;
    String? text(String key) => source[key]?.toString();
    return PlacementRule(
      type: text('type'),
      klass: text('class'),
      predicate: text('predicate'),
      action: '${source['action']}',
      axis: text('axis') ?? 'row',
      ratio: text('ratio') ?? '1/2',
      maxTabs: text('maxTabs'),
      container: text('container'),
      before: source['before'] == true,
    );
  }
}

/// Same type and class tabs with the newest of its kind -- the first one of a
/// kind finds no such tile and falls through to the split.
const List<PlacementRule> defaultPlacementRules = [
  PlacementRule(action: 'tabWithNewest', maxTabs: 'stageMaxTabs'),
  PlacementRule(action: 'splitFocused', axis: 'row', ratio: 'stageSplitRatio'),
];

/// The first rule that can place [tile], or null when none can.
Placement? evaluatePlacement(
  List<PlacementRule> rules, {
  required TileLeaf tile,
  required LayoutNode? root,
  String? focusedId,
  List<String> openOrder = const [],
  Map<String, Object> bindings = const {},
}) {
  final leaves = leavesOf(root);
  for (final rule in rules) {
    if (rule.type != null && rule.type != tile.type) continue;
    if (rule.klass != null && rule.klass != tile.klass) continue;
    final target = switch (rule.action) {
      'tabWithNewest' => _newestOfKind(leaves, openOrder, tile),
      'into' => containerNamed(root, rule.container ?? '')?.id,
      // A bar is chrome pinned to an edge and is never split into: a tile with
      // nowhere else to go splits the root instead (ruled 2026-08-28).
      _ =>
        focusedId != null && findNode(root, focusedId) != null
            ? focusedId
            : leaves.where((leaf) => leaf.type == tile.type || leaf.type != 'bar').lastOrNull?.id,
    };
    if (target == null) continue;
    final tabs = tabsAt(root, target);
    final env = Env(
      values: {
        'countOfType': Rational.fromInt(leaves.where((l) => l.type == tile.type).length),
        'countOfClass': Rational.fromInt(leaves.where((l) => l.klass == tile.klass).length),
        'tabsInTarget': Rational.fromInt(tabs),
        'leaves': Rational.fromInt(leaves.length),
        ...bindings,
      },
    );
    if (!_holds(rule.predicate, env)) continue;
    final limit = _number(rule.maxTabs, env);
    final ratio = _number(rule.ratio, env) ?? Rational.fromInt(1, 2);
    if (rule.action == 'tabWithNewest' && limit != null && Rational.fromInt(tabs) >= limit) {
      // A FULL STACK OVERFLOWS BESIDE ITSELF (ruled 2026-08-28). Splitting the
      // target leaf would put the new tile inside whichever page happened to be
      // showing, where nothing says it is there; splitting the STACK puts it
      // where it can be seen. With no stack to split, the rule falls through.
      final stack = tabContainerOf(root, target);
      if (stack == null) continue;
      return (
        action: 'splitFocused',
        targetId: stack,
        axis: rule.axis,
        ratio: ratio,
        before: rule.before,
        container: null,
      );
    }
    return (
      action: rule.action,
      targetId: target,
      axis: rule.axis,
      ratio: ratio,
      before: rule.before,
      container: rule.container,
    );
  }
  return null;
}

String? _newestOfKind(List<TileLeaf> leaves, List<String> openOrder, TileLeaf tile) {
  // A bar is never a tab host, so chrome never tabs with chrome.
  if (tile.type == 'bar') return null;
  final placed = {for (final leaf in leaves) leaf.id: leaf};
  for (final id in openOrder.reversed) {
    final leaf = placed[id];
    if (leaf != null && leaf.id != tile.id && leaf.type == tile.type && leaf.klass == tile.klass) {
      return leaf.id;
    }
  }
  return null;
}

/// A predicate that will not read is a refusal to place, never a silent yes.
bool _holds(String? source, Env env) {
  if (source == null || source.trim().isEmpty) return true;
  try {
    return evaluateSource(source, env) == true;
  } on MathRefusal {
    return false;
  }
}

Rational? _number(String? source, Env env) {
  if (source == null || source.trim().isEmpty) return null;
  try {
    final value = evaluateSource(source, env);
    return value is Rational ? value : null;
  } on MathRefusal {
    return null;
  }
}
