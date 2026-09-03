// Per-view-tile state, and the book of it that `chronolog.view` holds.
//
// A tile IS a lens (the zoom auto-swap is dead), so the lens id lives here
// beside the projection that lens looks through, where the focus sits, and the
// per-lens map. Nothing here is a filter: what is visible is what the
// projection expression admits.

import 'package:flutter/foundation.dart';

import '../core/coordinate_law.dart';
import '../core/exact.dart';
import '../core/frame_selection.dart';
import '../core/math.dart';
import '../core/projection.dart';
import 'lens_catalog.dart';
import 'point_pick.dart';
import 'settings.dart';

class ViewState {
  ViewState({
    required this.lensId,
    FrameSelection? selection,
    Set<String>? negated,
    this.source = '',
    Rational? focusDays,
    this.sharedFocus = true,
    Map<String, Object?>? view,
  }) : selection = selection ?? FrameSelection(),
       negated = negated ?? {},
       focusDays = focusDays ?? Rational.zero,
       view = view ?? {};

  String lensId;

  /// The plain selection: ordered frames with an explicit primary marker.
  final FrameSelection selection;

  /// Frames the selection projects as NOT terms -- the ruled filter substitute.
  /// `Work not Done` is authored here, never as a show/hide-by-state knob.
  final Set<String> negated;

  /// An authored boolean expression, which wins over the plain selection when
  /// it is set. Empty means the selection speaks.
  String source;

  Rational focusDays;
  bool sharedFocus;

  /// Per-lens view values, by the catalog's own control keys.
  final Map<String, Object?> view;

  LensSpec get spec => lensCatalog[lensId] ?? lensCatalog.values.first;

  /// One identifier per frame for the authored text, from the titles a browser
  /// knows: a frame id is not a legal identifier in the one math.
  static Map<String, String> bindingsFor(Iterable<String> ids, String Function(String) titleOf) {
    final bindings = <String, String>{};
    for (final id in ids) {
      final slug = titleOf(id).replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
      var name = slug.isEmpty || RegExp(r'^\d').hasMatch(slug) ? 'f_$slug' : slug;
      while (bindings.containsKey(name)) {
        name = '${name}_';
      }
      bindings[name] = id;
    }
    return bindings;
  }

  /// The selection rendered as text the author can edit, in the same names.
  static String textFor(Iterable<String> ids, Set<String> negated, Map<String, String> bindings) {
    String nameOf(String id) =>
        bindings.entries.firstWhere((e) => e.value == id, orElse: () => MapEntry(id, id)).key;
    final positive = [
      for (final id in ids)
        if (!negated.contains(id)) nameOf(id),
    ];
    return [
      if (positive.isNotEmpty) positive.join(' or '),
      for (final id in ids)
        if (negated.contains(id)) 'not ${nameOf(id)}',
    ].join(' and ');
  }

  /// The projection this view looks through. The plain selection builds its
  /// tree directly -- OR of the positives, AND NOT for each refused frame -- so
  /// no frame id ever meets a tokenizer.
  Projection projection({Map<String, String> bindings = const {}}) {
    if (source.trim().isNotEmpty) return Projection.parse(source, bindings: bindings);
    final ids = selection.selected();
    final positive = [
      for (final id in ids)
        if (!negated.contains(id)) id,
    ];
    var tree = Projection.of(positive.isEmpty ? ids : positive).expression;
    for (final id in ids.where(negated.contains)) {
      tree = Binary('and', tree, Unary('not', Name(id, 0), 0), 0);
    }
    return Projection(tree);
  }

  Object? read(String key, Settings settings) {
    if (view.containsKey(key)) return view[key];
    final setting = spec.viewDefaults[key];
    if (setting != null) return settings.raw(setting);
    final control = spec.controls.where((entry) => entry.key == key).firstOrNull;
    return control != null && control.options.isNotEmpty ? control.options.first.value : null;
  }

  Rational number(String key, Settings settings) => switch (read(key, settings)) {
    final Rational value => value,
    final String value => rationalOrZero(value),
    true => Rational.one,
    _ => Rational.zero,
  };

  bool flag(String key, Settings settings) => switch (read(key, settings)) {
    final bool value => value,
    final Rational value => !value.isZero,
    _ => false,
  };

  String choice(String key, Settings settings) => '${read(key, settings) ?? ''}';

  void write(String key, Object? value) => value == null ? view.remove(key) : view[key] = value;

  /// Back to the lens's shipped defaults, without touching the projection or
  /// the focus -- resetting a lens is not losing your place.
  void resetView() => view.clear();

  /// The visible span in days under THIS law: the lens's own formula over its
  /// own view values, times what the law says its unit is worth.
  Rational spanDays(CoordinateLaw law, Settings settings) {
    final unit = law.meanUnitDays(spec.spanUnit) ?? Rational.one;
    try {
      final count = evaluateSource(
        spec.spanFormula,
        Env(
          values: {
            for (final control in spec.controls)
              if (control.kind == 'number' || control.kind == 'toggle')
                control.key: number(control.key, settings),
          },
        ),
      );
      return count is Rational && count > Rational.zero ? count * unit : unit;
    } on MathRefusal {
      return unit;
    }
  }

  /// WHAT WAS SAID, as against where the eye happened to be.
  ///
  /// "A write a GESTURE produced -- pan, zoom, focus, which tile the eye is on
  /// -- is where you are looking rather than what you said ... This also
  /// settles what a named view is: exactly the second category, made durable on
  /// purpose." (Don, the settings-undo ruling.) So a named view is THIS: lens,
  /// projection expression, columns in order with their own expressions, the
  /// lens's own keys -- and never the focus.
  ///
  /// It is [toJson] minus the focus rather than a second serializer, so a named
  /// view and a saved view file cannot drift apart in what they think a view is.
  Map<String, Object?> get said => {...toJson()}..remove('focus');

  Map<String, Object?> toJson() => {
    'lens': lensId,
    'frames': selection.selected(),
    'primary': selection.primary(),
    'negated': negated.toList(),
    if (source.isNotEmpty) 'source': source,
    'focus': focusDays.toJson(),
    'sharedFocus': sharedFocus,
    'view': _copied(view),
  };

  /// A SAVED VIEW IS NOT THE LIVE ONE.
  ///
  /// `toJson` handed out the `view` map ITSELF, so a preset saved from a card
  /// went on tracking the tile it was saved from: every later edit to that
  /// tile's lens keys silently rewrote the already-saved layout, and only a
  /// restart's JSON round trip froze it -- which is exactly why no test that
  /// serialises between writing and reading could ever see it.
  ///
  /// The copy belongs HERE, where the internal map is handed out, and not at
  /// each call site: a caller that has to remember to copy is a caller the next
  /// one forgets. It goes all the way down, because a view value is whatever a
  /// control wrote and nothing says that is a scalar.
  static Map<String, Object?> _copied(Map<String, Object?> map) => {
    for (final entry in map.entries) entry.key: _copiedValue(entry.value),
  };

  static Object? _copiedValue(Object? value) => switch (value) {
    final Map<Object?, Object?> map => {
      for (final entry in map.entries) '${entry.key}': _copiedValue(entry.value),
    },
    final List<Object?> list => [for (final item in list) _copiedValue(item)],
    _ => value,
  };

  static ViewState fromJson(Object? source) {
    final map = source is Map ? source : const {};
    return ViewState(
      lensId: '${map['lens'] ?? lensCatalog.keys.first}',
      selection: FrameSelection(_ids(map['frames']), map['primary']?.toString()),
      negated: _ids(map['negated']).toSet(),
      source: '${map['source'] ?? ''}',
      focusDays: rationalOrZero('${map['focus'] ?? 0}'),
      sharedFocus: map['sharedFocus'] != false,
      // BOTH DIRECTIONS, or the seam is only half closed: a preset applied to a
      // tile must not hand that tile the preset's own nested maps to edit in
      // place. `Map.from` copied the top level and nothing under it.
      view: map['view'] is Map
          ? _copied(Map<String, Object?>.from(map['view'] as Map))
          : null,
    );
  }
}

/// What `chronolog.view` holds: the per-tile view state, the shared focus, and
/// the lens order and hidden set.
class ViewBook extends ChangeNotifier {
  ViewBook({Rational? sharedFocus}) : sharedFocus = sharedFocus ?? nowDays() {
    // One mode, relayed: a surface already listening to the book to know what
    // it is showing learns that a pick is armed through the same listenable,
    // rather than every tile subscribing to a second one.
    pick.addListener(notifyListeners);
  }

  /// THE ONE POINT-CAPTURE MODE, on the session because a card and a tile both
  /// hold the book. Armed by Pick, answered by whichever surface is clicked.
  final PointPick pick = PointPick();

  @override
  void dispose() {
    pick.removeListener(notifyListeners);
    pick.dispose();
    super.dispose();
  }

  Rational sharedFocus;
  final Map<String, ViewState> views = {};
  List<String> lensOrder = [];
  Set<String> hidden = {};

  /// What a view tile projects before anyone has said otherwise. Set by
  /// whoever knows the document; never guessed from a phantom frame id.
  List<String> defaultFrames = [];

  List<String> get visibleLenses => orderedLenses(lensOrder, hidden);

  ViewState of(String tileId) => views[tileId] ??= ViewState(
    lensId: visibleLenses.first,
    focusDays: sharedFocus,
    selection: FrameSelection(defaultFrames),
  );

  /// SHOW A NAMED VIEW IN ONE TILE: everything [ViewState.said] carries is
  /// adopted and the tile's FOCUS IS LEFT ALONE, because where the eye is
  /// looking is this tile's business and never the board's.
  ///
  /// Replaces rather than mutates, so what lands is exactly what a reload of
  /// the same record would produce -- a named view that showed differently the
  /// second time would not be a named view.
  void showSaid(String tileId, Map<String, Object?> said) {
    final focus = views.containsKey(tileId) ? views[tileId]!.focusDays : sharedFocus;
    views[tileId] = ViewState.fromJson({...said, 'focus': focus.toJson()});
    notifyListeners();
  }

  void setLens(String tileId, String lensId) {
    if (!lensCatalog.containsKey(lensId)) return;
    of(tileId).lensId = lensId;
    notifyListeners();
  }

  /// One focus, or one per view tile: the option the old session carried, kept.
  Rational focusOf(String tileId) => of(tileId).sharedFocus ? sharedFocus : of(tileId).focusDays;

  void setFocus(String tileId, Rational days) {
    final state = of(tileId);
    state.focusDays = days;
    if (state.sharedFocus) sharedFocus = days;
    notifyListeners();
  }

  void setHidden(String lensId, bool value) {
    value ? hidden.add(lensId) : hidden.remove(lensId);
    notifyListeners();
  }

  void touch() => notifyListeners();

  Map<String, Object?> toJson() => {
    'sharedFocus': sharedFocus.toJson(),
    'lensOrder': visibleLenses,
    'hidden': hidden.toList(),
    'views': {for (final entry in views.entries) entry.key: entry.value.toJson()},
  };

  void applyJson(Map<String, Object?> source) {
    sharedFocus = rationalOrZero('${source['sharedFocus'] ?? 0}');
    lensOrder = _ids(source['lensOrder']);
    hidden = _ids(source['hidden']).toSet();
    if (source['views'] is Map) {
      views.clear();
      for (final entry in (source['views'] as Map).entries) {
        views['${entry.key}'] = ViewState.fromJson(entry.value);
      }
    }
    notifyListeners();
  }
}

List<String> _ids(Object? source) => [
  if (source is List)
    for (final id in source) '$id',
];

/// A number the file wrote, or zero: a malformed focus costs the focus, never
/// the file.
Rational rationalOrZero(String source) {
  try {
    return Rational.parse(source);
  } on FormatException {
    return Rational.zero;
  }
}
