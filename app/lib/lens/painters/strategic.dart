// Strategic: one row per month of the law's own month level, one column per base
// unit that month can hold.
//
// The column count is the LAW's -- 31 where a Gregorian month runs that long, 64
// on an 8x8x8 calendar -- and short months pad, because the deliberate shape is
// the lens's identity: a season's topology, every date represented, nothing
// reflowed. A law with no month level gets a refusal, not an invented year.
//
// THREE-WAY PRESENTATION, and the AUTHORED GATE OUTRANKS DERIVED WEIGHT
// (survey B7): `display.strategic` on any frame bearing on the object says show
// or hide outright; otherwise a landmark carries its name, and everything else a
// pip. Importance never HIDES an object -- it only decides how loudly it speaks.
//
// `strategicMode` does not exist. The signal/blocks/all triple was a second
// mechanism for what the promotion thresholds already say.

import '../../core/exact.dart';
import '../../core/projection.dart';
import '../../core/records.dart';
import '../display_weight.dart';
import 'month_grid.dart';

class StrategicPainter extends DayGridPainter {
  StrategicPainter(super.scene) : super(lens: 'strategic');

  final Map<String, String?> _gates = {};

  @override
  ({List<GridRow> rows, String? refused}) layout() {
    final months = viewCount(scene, 'months', 'strategic.months');
    if (months < 1) return (rows: const [], refused: 'A season of $months months has no rows.');
    final back = scene.law.meanMonthDays() * Rational.fromInt(months ~/ 2);
    final sheets = monthSheets(scene.law, scene.focusDays - back, months);
    if (sheets == null) {
      return (
        rows: const [],
        refused: 'This frame declares no month level, so it has no months to row.',
      );
    }
    final columns = sheets.map((sheet) => sheet.days).reduce((a, b) => a > b ? a : b);
    return (
      rows: [
        for (final sheet in sheets)
          (
            label: sheet.label,
            days: [
              for (var index = 0; index < columns; index += 1)
                index < sheet.days ? sheet.firstDay + BigInt.from(index) : null,
            ],
          ),
      ],
      refused: null,
    );
  }

  /// The authored show/hide, read off every frame bearing on the object exactly
  /// as the zone grammar reads its own -- handling is a group property.
  String? _gate(Fact fact) => _gates[fact.event.id] ??= () {
    for (final id in <String>{
      if (fact.relation.frame case final String frame) frame,
      ...scene.engine.modifyingFrames(fact.event.id).keys,
    }) {
      final authored = obj(scene.engine.document.frames[id]?.extra['display'])?['strategic'];
      if (authored is String && authored.isNotEmpty) return authored;
      if (authored is bool) return authored ? 'show' : 'hide';
    }
    return null;
  }();

  @override
  String presentationOf(Fact fact, DisplayWeight weight) => switch (_gate(fact)) {
    'hide' => showNone,
    'show' => super.presentationOf(fact, weight),
    _ => weight.promotion == landmarkWeight ? super.presentationOf(fact, weight) : showPip,
  };
}
