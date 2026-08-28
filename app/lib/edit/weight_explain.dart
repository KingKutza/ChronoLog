// The derivation behind a display weight, for the card's explainer.
//
// Data only: the card renders it. Nothing is recomputed here -- the engine's own
// `weightOf` walks the graph and `composeWeight` folds the blessed order, and a
// second derivation could only disagree with what was drawn. This reads that
// one answer and names each ring.

import '../core/exact.dart';
import '../core/projection.dart';
import '../core/records.dart';
import '../core/weight.dart';
import 'editor.dart';

/// One ring of the chain: what applied, the math it applied as text, and the
/// weight going in and coming out.
typedef WeightRow = ({String id, String title, String formula, Rational from, Rational to});

/// The whole chain. [rows] is in the order it was folded, so a card can read it
/// top to bottom and the arithmetic adds up.
typedef WeightExplanation = ({Rational base, List<WeightRow> rows, Rational weight});

extension WeightExplainer on Editor {
  WeightExplanation explainWeight(
    Fact fact,
    Projection projection, {
    Rational? at,
    Rational? halfDistanceDays,
  }) {
    final derivation = engine.weightOf(
      fact,
      projection,
      at: at,
      halfDistanceDays: halfDistanceDays,
    );
    final base = Rational.one;
    var from = base;
    final rows = <WeightRow>[];
    for (final ring in derivation.rings) {
      rows.add((
        id: ring.id,
        title: ringTitle(ring.id, fact),
        formula: ring.via,
        from: from,
        to: ring.weight,
      ));
      from = ring.weight;
    }
    return (base: base, rows: rows, weight: derivation.weight);
  }

  /// What to call a ring. A frame answers with its own title; the two rings that
  /// are not frames answer with the object's title and the falloff's own name,
  /// so no row in the explainer reads as a bare record id.
  String ringTitle(String id, Fact fact) {
    if (id == ownWeightRing) {
      final title = str(fact.event.payload?['title'])?.trim();
      return title == null || title.isEmpty ? fact.event.id : title;
    }
    if (id == falloffWeightRing) return 'Apparent magnitude';
    return document.frames[id]?.title ?? id;
  }
}
