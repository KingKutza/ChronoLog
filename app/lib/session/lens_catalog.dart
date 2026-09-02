// The lens catalog: what each lens IS and what it affords, as data.
//
// The old surface spent 345 lines of `if (lens === ...)` building its control
// bar. A lens declares its controls here instead; the context bar renders the
// declaration and knows no lens by name. Kinds are strings, not an enum:
// nothing here encodes a right way, and an unfamiliar kind is data a later
// surface may learn to render rather than a crash.

/// One option of a choice control. The FIRST declared option is the default --
/// no shipped ordinal, no default-option setting.
typedef ControlOption = ({String value, String label});

/// A control a lens affords. Positional, because this is a dense table:
/// kind (`toggle` | `choice` | `number` | `action` | `expression`), the
/// view-state key it reads and writes (or an action id), its label, the
/// settings key holding its shipped default, and the law level whose count per
/// day bounds it -- so a 23-hour day offers 23 hours.
class ControlSpec {
  const ControlSpec(
    this.kind,
    this.key,
    this.label, [
    this.setting,
    this.unit,
    this.options = const [],
    this.primary = false,
    this.hint,
    this.floor,
  ]);

  final String kind, key, label;
  final String? setting, unit, hint;

  /// The settings key holding the LEAST this control may be wound down to.
  ///
  /// THE WINDOW NUMBER IS THE ZOOM, AND IT IS CONTINUOUS (ISSUES 9.2, Lines).
  /// A zoom step used to round its result to a whole number and stop at one, so
  /// at a small window a wheel notch was a no-op in both directions -- the
  /// control was dead exactly where it mattered most. A step is a multiplication
  /// now, kept exact, and where it may stop is the lens's own authored number
  /// rather than the integer 1. A control naming none stops at one, which is
  /// what a count of columns or rings means.
  final String? floor;
  final List<ControlOption> options;

  /// True lives on the bar itself; false lives under the one fold.
  final bool primary;
}

/// What a lens is, what it shows, and what it affords. [spanUnit] is the law
/// level the visible span counts in and [spanFormula] a one-math expression
/// over this lens's own view keys -- a month span asks the law what a month is.
class LensSpec {
  const LensSpec(
    this.id,
    this.title,
    this.description, {
    required this.isTimeSurface,
    required this.spanUnit,
    required this.spanFormula,
    this.controls = const [],
    this.scaleKey,
  });

  final String id, title, description, spanUnit, spanFormula;
  final bool isTimeSurface;
  final List<ControlSpec> controls;

  /// The view key a scale gesture (ctrl+wheel, zoom in/out) moves. Absent, the
  /// gesture scales whichever number controls this lens's own span formula
  /// reads -- so Intimate stretches its hour rail while a coarse lens widens
  /// its window, and no surface has to be recognised by name.
  final String? scaleKey;

  /// View key -> the settings key holding its default, derived from the
  /// controls so a lens has one list to keep honest.
  Map<String, String> get viewDefaults => {
    for (final c in controls)
      if (c.setting != null) c.key: c.setting!,
  };
}

const List<ControlOption> _grouping = [
  (value: 'state', label: 'State'),
  (value: 'importance', label: 'Importance'),
  (value: 'container', label: 'Container'),
  (value: 'frame', label: 'Frame'),
];

const ControlSpec _span = ControlSpec('number', 'span', 'Span', 'todo.spanDays', 'day');

/// The shipped lenses, in shipped order. Each lens builder fills its own spec.
final Map<String, LensSpec> lensCatalog = {for (final spec in _shipped) spec.id: spec};

const List<LensSpec> _shipped = [
  LensSpec(
    'intimate',
    'Intimate',
    'Hour-by-hour continuous scroll — the closest view, a day or a week at a time.',
    isTimeSurface: true,
    spanUnit: 'day',
    spanFormula: 'back + forward + 1',
    scaleKey: 'hourPixels',
    controls: [
      ControlSpec('action', 'zoomOut', 'Zoom out', null, null, [], true),
      ControlSpec('action', 'zoomIn', 'Zoom in', null, null, [], true),
      ControlSpec('number', 'back', 'Days behind', 'intimate.back', 'day'),
      ControlSpec('number', 'forward', 'Days ahead', 'intimate.forward', 'day'),
      ControlSpec('number', 'grain', 'Grain', 'intimate.grain', 'minute'),
      // NO DAY-START / DAY-END PICKER (ruled 2026-08-31): "seems like a good
      // setting but I think it is a bad one." The day is an AUTHORED OBJECT --
      // a daily series whose handling says display-as-zone -- so it is drawn by
      // the same zone painting every other authored region gets, and it carries
      // everything a definition staple can say. A setting here could only ever
      // offer crude hour increments and could never be one.
      ControlSpec('number', 'hourPixels', 'Row height', 'intimate.hourPixels'),
    ],
  ),
  LensSpec(
    'tactical',
    'Tactical',
    'A grid of days — the working week and the weeks around it.',
    isTimeSurface: true,
    spanUnit: 'day',
    spanFormula: 'rows * columns',
    controls: [
      ControlSpec('number', 'rows', 'Rows', 'tactical.rows', null, [], true),
      ControlSpec('number', 'columns', 'Days per row', 'tactical.columns', 'day', [], true),
    ],
  ),
  LensSpec(
    'strategic',
    'Strategic',
    'Months at a glance — density and shape over a season, up to 18 months.',
    isTimeSurface: true,
    spanUnit: 'month',
    spanFormula: 'months',
    controls: [
      ControlSpec('number', 'months', 'Months', 'strategic.months', 'month', [], true),
      ControlSpec('number', 'importantAt', 'Important at', 'strategic.importantAt'),
      ControlSpec('number', 'landmarkAt', 'Landmark at', 'strategic.landmarkAt'),
    ],
  ),
  LensSpec(
    'wall',
    'Wall',
    'A normal wall calendar — month sheets, a quarter or a month at a time.',
    isTimeSurface: true,
    spanUnit: 'month',
    spanFormula: 'months',
    controls: [
      ControlSpec('number', 'months', 'Months', 'wall.months', 'month', [], true),
      ControlSpec('toggle', 'detail', 'Detail', 'wall.detail'),
    ],
  ),
  LensSpec(
    'lines',
    'Lines',
    'Prime Line and Party Lines side by side — one line per group, glyphs along each.',
    isTimeSurface: true,
    spanUnit: 'day',
    spanFormula: 'days',
    controls: [
      ControlSpec('number', 'days', 'Window', 'lines.days', 'day', [], true, null, 'lines.minDays'),
    ],
  ),
  LensSpec(
    'spiral',
    'Spiral',
    'One ring outward per cycle — natural units as ticks, events as arcs across them.',
    isTimeSurface: true,
    spanUnit: 'day',
    spanFormula: '(inward + outward + 1) * cycleDays',
    controls: [
      ControlSpec('number', 'inward', 'Rings inward', 'radial.inward', null, [], true),
      ControlSpec('number', 'outward', 'Rings outward', 'radial.outward', null, [], true),
      ControlSpec('number', 'cycleDays', 'Cycle', 'radial.cycleDays', 'day'),
      ControlSpec('toggle', 'labels', 'Labels', 'radial.labels'),
      ControlSpec('number', 'divisions', 'Ticks', 'radial.divisions'),
      ControlSpec('number', 'majorEvery', 'Major every', 'radial.majorEvery'),
    ],
  ),
  LensSpec(
    'radial',
    'Radial',
    'One cycle, one band per group — events as arcs overlapping around the same circle.',
    isTimeSurface: true,
    spanUnit: 'day',
    spanFormula: 'cycleDays',
    controls: [
      ControlSpec('number', 'cycleDays', 'Cycle', 'radial.cycleDays', 'day', [], true),
      ControlSpec('toggle', 'labels', 'Labels', 'radial.labels', null, [], true),
      ControlSpec('number', 'divisions', 'Ticks', 'radial.divisions'),
      ControlSpec('number', 'majorEvery', 'Major every', 'radial.majorEvery'),
    ],
  ),
  LensSpec(
    'list',
    'List',
    'Capture fast, check off, see the shape — every ToDo in one column.',
    isTimeSurface: false,
    spanUnit: 'day',
    spanFormula: 'span',
    controls: [ControlSpec('choice', 'grouping', 'Group by', null, null, _grouping, true), _span],
  ),
  LensSpec(
    'board',
    'Board',
    'Columns are the grouping — the same ToDos laid out side by side.',
    isTimeSurface: false,
    spanUnit: 'day',
    spanFormula: 'span',
    controls: [ControlSpec('choice', 'grouping', 'Group by', null, null, _grouping, true), _span],
  ),
  LensSpec(
    'tree',
    'Tree',
    'The connection graph whole — objects and frames as nodes, staples, containment and '
        'membership as edges',
    isTimeSurface: false,
    spanUnit: 'day',
    spanFormula: 'span',
    controls: [ControlSpec('number', 'reach', 'Reach', 'tree.reach', null, [], true), _span],
  ),
];

/// Shipped defaults for every lens view key the catalog names.
const Map<String, String> sessionTunableDefaults = {
  'intimate.back': '0',
  'intimate.forward': '2',
  'intimate.grain': '15',
  'intimate.hourPixels': '42',
  'tactical.rows': '5',
  'tactical.columns': '7',
  'strategic.months': '9',
  'wall.months': '3',
  'wall.detail': 'false',
  'lines.days': '14',
  // THE FLOOR OF THE WINDOW, in the span's own unit (ISSUES 9.2). Lines counts
  // in days and its window is its zoom, so how far in it may be wound is a
  // FRACTION of a day and not the whole one an integer step used to stop at.
  // A tenth of a day is a couple of hours across the surface.
  'lines.minDays': '1/10',
  'radial.inward': '1',
  'radial.outward': '1',
  'radial.cycleDays': '7',
  'radial.labels': 'true',
  'radial.divisions': '0',
  'radial.majorEvery': '0',
  'todo.spanDays': '21',
  'tree.reach': '2',
};

/// The user lens order with the catalog's growth folded in: an authored order
/// keeps its positions, a lens never seen is appended after it (born visible),
/// a hidden one stays hidden. Never empty -- a bar with no lens is a trap.
List<String> orderedLenses(Iterable<String> authored, Set<String> hidden) {
  final order = [
    for (final id in authored)
      if (lensCatalog.containsKey(id)) id,
  ];
  order.addAll(lensCatalog.keys.where((id) => !order.contains(id)));
  final visible = [
    for (final id in order)
      if (!hidden.contains(id)) id,
  ];
  return visible.isEmpty ? [order.first] : visible;
}
