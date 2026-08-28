// Tactical: rows by columns of consecutive days, centred on the focus.
//
// The weekend comes from the law's WEEKDAY CYCLE, never from a hardcoded
// Saturday and Sunday: a calendar whose rest days fall elsewhere -- or which has
// no week at all -- is drawn as it is declared. When the row is exactly one turn
// of that cycle the grid aligns to the authored first weekday, so the columns
// read as the week they are rather than as an arbitrary seven-day slice.

import 'month_grid.dart';

class TacticalPainter extends DayGridPainter {
  TacticalPainter(super.scene) : super(lens: 'tactical');

  late final List<String>? _weekdays = scene.law.weekdayNames();

  int get _columns => viewCount(scene, 'columns', 'tactical.columns');

  /// The first day drawn: half the grid behind the focus, then backed up to the
  /// authored start of the cycle when a row IS one turn of it.
  late final BigInt firstDay = () {
    final rows = viewCount(scene, 'rows', 'tactical.rows');
    var day = law.dayOf(scene.focusDays) - BigInt.from(rows * _columns ~/ 2);
    final names = _weekdays;
    if (names == null || names.isEmpty || _columns != names.length) return day;
    final want = scene.whole('wall.firstWeekday') % names.length;
    final have = weekdayOf(day);
    return have == null ? day : day - BigInt.from((have - want) % names.length);
  }();

  @override
  List<Heading> get headings {
    final names = _weekdays;
    if (names == null || names.isEmpty || _columns != names.length) return const [];
    return weekdayHeadings(names, scene.whole('wall.firstWeekday') % names.length, initials: true);
  }

  @override
  ({List<GridRow> rows, String? refused}) layout() {
    final rows = viewCount(scene, 'rows', 'tactical.rows');
    final columns = _columns;
    if (rows < 1 || columns < 1) {
      return (rows: const [], refused: 'A grid of $rows by $columns days has no cells to draw.');
    }
    return (
      rows: [
        for (var row = 0; row < rows; row += 1)
          (
            label: dayLabel(scene.law, firstDay + BigInt.from(row * columns)),
            days: [
              for (var column = 0; column < columns; column += 1)
                firstDay + BigInt.from(row * columns + column),
            ],
          ),
      ],
      refused: null,
    );
  }
}
