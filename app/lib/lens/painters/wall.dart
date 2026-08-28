// Wall: month sheets laid out in the law's own week.
//
// The first column is the authored cycle position the settings name, the lead
// pad is however many positions the month's first day sits past it, and the
// column headings are the initials of the AUTHORED weekday names -- so a
// calendar with a five-day week called something else gets five columns headed
// by its own letters. A law with no weekday cycle has no week to lay a sheet out
// in, and says so rather than borrowing ours.
//
// Detail is one toggle over the same cells: with it the chips carry names, and
// without it they are pips. Untouched, the cell decides by the room it has.

import '../../core/projection.dart';
import '../display_weight.dart';
import 'month_grid.dart';

class WallPainter extends DayGridPainter {
  WallPainter(super.scene) : super(lens: 'wall');

  late final List<String>? _weekdays = scene.law.weekdayNames();

  int get _first {
    final names = _weekdays;
    return names == null || names.isEmpty ? 0 : scene.whole('wall.firstWeekday') % names.length;
  }

  @override
  List<Heading> get headings {
    final names = _weekdays;
    return names == null || names.isEmpty
        ? const []
        : weekdayHeadings(names, _first, initials: true);
  }

  @override
  String presentationOf(Fact fact, DisplayWeight weight) => switch (viewFlag(scene, 'detail')) {
    true => showName,
    false => showPip,
    _ => super.presentationOf(fact, weight),
  };

  @override
  ({List<GridRow> rows, String? refused}) layout() {
    final names = _weekdays;
    if (names == null || names.isEmpty) {
      return (
        rows: const [],
        refused: 'This frame declares no weekday cycle, so it has no week to lay a sheet out in.',
      );
    }
    final months = viewCount(scene, 'months', 'wall.months');
    if (months < 1) return (rows: const [], refused: 'A wall of $months months has no sheets.');
    final sheets = monthSheets(scene.law, scene.focusDays, months);
    if (sheets == null) {
      return (
        rows: const [],
        refused: 'This frame declares no month level, so it has no month to sheet.',
      );
    }
    final width = names.length;
    final rows = <GridRow>[];
    for (final sheet in sheets) {
      final start = weekdayOf(sheet.firstDay) ?? _first;
      final lead = (start - _first) % width;
      final weeks = ((lead + sheet.days) / width).ceil();
      for (var week = 0; week < weeks; week += 1) {
        rows.add((
          label: week == 0 ? sheet.label : '',
          days: [
            for (var column = 0; column < width; column += 1)
              switch (week * width + column - lead) {
                final index when index >= 0 && index < sheet.days =>
                  sheet.firstDay + BigInt.from(index),
                _ => null,
              },
          ],
        ));
      }
    }
    return (rows: rows, refused: null);
  }
}
