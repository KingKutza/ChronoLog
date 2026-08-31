// The minimap, drawn: A WAVE, ALWAYS -- IN DUST, WITH COUNTS RIDING ON IT.
//
// NOT A DOT MATRIX, and not a spray either. Don, on what this was always meant
// to be: "the idea was an almost animated waveform in dust or glitter", and on
// what the first build gave him: "it looks more like dirt than a waveform." The
// difference is a continuous curve. The field's bins go through a kernel, the
// smoothed curve is drawn as a soft band under a thin crest line, and the grain
// is placed AGAINST that curve, so the eye reads the shape before the grain.
//
// THE WAVE IS THE LOOK AT EVERY DENSITY (ruled 2026-08-31, from "appears to have
// lost the dust based Density wave, and replaced it with dots" -- "It was good
// now it is misrendering"). The build that drew this had the dust STEP ASIDE
// wherever facts were few enough to count, and dimmed the envelope with them; on
// a real, sparse calendar every neighbourhood is countable, so the whole tile
// became motes with nothing under them. There is no such regime any more: the
// dust is the wave's texture and it is drawn wherever the wave has height.
//
// A COUNT MUST BE ANCHORED (Don, 2026-08-31, correcting the earlier reading of
// his four-dots question: "my question was if we were bothering to render
// countable dots why we weren't anchoring their count to anything obvious").
// Where few enough facts are placed within a neighbourhood, each one ALSO gets a
// MOTE -- one mark per fact, at its own time, sized by its composed display
// weight, and placed ON the crest rather than floating loose in the band. So the
// count means something exactly: that many marks are that many facts. Above the
// threshold there are no motes, because a count nobody can take is noise.
//
// NOTHING MOVES ALONG TIME (ruled 2026-08-28: "the dust shifts right, giving the
// impression that the events are moving"). A grain's place on the time axis is
// fixed. The only motion is brightness, an optional sub-pixel offset ACROSS the
// axis, and the band's slow breathing -- none of which can be read as an event
// going anywhere.
//
// AND NO LOOP. The clock is continuous seconds, never a repeating phase, and
// every grain twinkles at its own offset and its own rate, so nothing resets in
// unison and the motion has no period to see.
//
// TIME RUNS ALONG THE LONG SIDE. The minimap ships in a narrow column beside
// the lens; a time axis across the narrow side has nowhere to be a wave.
//
// GRAIN IS DETERMINISTIC. Positions come from a hash of the bin and the grain's
// own index, not from a random number generator, so the same field draws the
// same dust every frame.
//
// LABELS SIT JUST AFTER THEIR OWN LINE, never centred on it, so the text and the
// boundary it names cannot drift apart.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../core/exact.dart';
import '../law_context.dart';
import '../now.dart';
import '../theme.dart';
import '../tunables.dart';
import 'field.dart';
import 'labels.dart';

/// One grain: where it sits (fixed in time), how bright it is this instant, and
/// whether it is one of the lit few.
typedef Grain = ({Offset at, double alpha, bool lit});

class MinimapPainter extends CustomPainter {
  MinimapPainter({
    required this.field,
    required this.law,
    required this.theme,
    required this.focusDays,
    required this.spanDays,
    required this.nowDays,
    required this.granularity,
    this.tunable,
    this.clock = 0,
    this.frozen = false,
  });

  final MinimapField field;
  final LawContext law;
  final ChronoTheme theme;

  /// The focused view tile's centre and how much of the axis it shows -- the
  /// minimap describes THAT tile, which is what the window box draws.
  final Rational focusDays, spanDays, nowDays;

  /// The label level the focused lens declared. A lens never labels more finely.
  final String granularity;

  final Tunable? tunable;

  /// Seconds since the tile began, continuous and never wrapped: a phase that
  /// returns to zero is a loop, and a loop is visible.
  final double clock;

  /// Held while a pointer is on the tile.
  final bool frozen;

  Size _size = Size.zero;
  List<bool> _regimes = const [];

  double _px(String key) => pixels(tunable, key);

  Rational get _width => field.range.end - field.range.start;

  /// Time runs along the longer side; the wave's amplitude uses the shorter.
  bool get _vertical => _size.height > _size.width;
  double get _length => _vertical ? _size.height : _size.width;
  double get _thickness => _vertical ? _size.width : _size.height;

  /// One point, named the way the wave thinks: how far along time it is, and how
  /// far across the band. Every mark in here is placed through this, so the
  /// orientation lives in one line rather than in every paint.
  Offset _at(double along, double across) =>
      _vertical ? Offset(across, along) : Offset(along, across);

  /// A pointer's place on the time axis. The scrub reads this and nothing else.
  double along(Offset at) => _vertical ? at.dy : at.dx;

  /// Screen point to the exact day it names. This is the scrub.
  Rational unproject(Offset at) {
    if (_length <= 0) return field.range.start;
    final fraction = Rational.parse((along(at) / _length).clamp(0.0, 1.0).toStringAsFixed(12));
    return field.range.start + _width * fraction;
  }

  double? project(Rational days) {
    if (_width <= Rational.zero) return null;
    return ((days - field.range.start) / _width).toDouble() * _length;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _prepare(size);
    if (size.width <= 0 || size.height <= 0) return;
    final axis = _thickness / 2;
    canvas.drawRect(Offset.zero & size, Paint()..color = theme.paper);
    _paintTicks(canvas);
    _paintWave(canvas, axis);
    _paintGrain(canvas, grainsFor(size));
    _paintMotes(canvas, axis);
    _paintWindow(canvas);
    _paintLabels(canvas);
  }

  void _prepare(Size size) {
    _size = size;
    _regimes = _countability();
  }

  /// The wave: a low-alpha band between the mirrored crests, the axis it swings
  /// about, and the thin crest line the grain hangs on.
  ///
  /// ONE RUN, AT ONE WEIGHT, THE WHOLE LENGTH OF THE TILE. The envelope used to
  /// be drawn in runs and dimmed by `minimap.quietScale` wherever the facts were
  /// countable; on a sparse document that is everywhere, and the wave went out.
  /// A wave that disappears when a calendar is quiet is not the look -- a quiet
  /// calendar is a low wave, which is the reading.
  void _paintWave(Canvas canvas, double axis) {
    if (_length <= 0) return;
    canvas.drawLine(
      _at(0, axis),
      _at(_length, axis),
      Paint()
        ..strokeWidth = _px('minimap.axisWidth')
        ..color = theme.muted.withValues(alpha: _px('minimap.baselineOpacity')),
    );
    final upper = <Offset>[], lower = <Offset>[];
    for (var step = 0.0; step <= _length; step += 1) {
      final crest = _crestAt(step);
      upper.add(_at(step, axis - crest));
      lower.add(_at(step, axis + crest));
    }
    if (upper.length < 2) return;
    final band = Path()..addPolygon(upper, false);
    for (final point in lower.reversed) {
      band.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      band..close(),
      Paint()..color = theme.neutral.withValues(alpha: _px('minimap.bandOpacity')),
    );
    final crest = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _px('minimap.crestWidth')
      ..strokeJoin = StrokeJoin.round
      ..color = theme.neutral.withValues(alpha: _px('minimap.crestOpacity'));
    canvas.drawPath(Path()..addPolygon(upper, false), crest);
    canvas.drawPath(Path()..addPolygon(lower, false), crest);
  }

  /// Every grain of dust for this size. THE DUST IS THE WAVE'S TEXTURE, so it is
  /// drawn wherever the wave has height and never steps aside for the motes: a
  /// sparse document is a low wave in dust with a few counted marks riding on
  /// it, not a bare dot matrix (ruled 2026-08-31).
  ///
  /// A grain's place along time is a pure function of its bin and its index,
  /// with no clock in it at all: that is the ruling made mechanical.
  List<Grain> grainsFor(Size size) {
    _prepare(size);
    final bins = _curve.length;
    if (bins == 0 || _length <= 0) return const [];
    // THE GRAIN BUDGET COMES FROM AREA, not from a flat count: dust is a
    // TEXTURE, and a fixed number of grains poured into whatever the wave
    // happens to cover packs a small busy stretch into a solid blot. So the
    // budget is grains per square pixel of the dense band, capped by the count.
    // Breathing is excluded, or the grain count would flicker with the breath.
    final binLength = _length / bins;
    var total = 0.0, area = 0.0;
    for (var bin = 0; bin < bins; bin += 1) {
      total += _curve[bin];
      area += 2 * _curve[bin] * _baseReach * binLength;
    }
    if (total <= 0) return const [];
    final budget = math.min(
      count(tunable, 'minimap.particles'),
      (area * _px('minimap.grainPerPixel')).round(),
    );
    if (budget <= 0) return const [];
    final spread = _px('minimap.spread'), haze = _px('minimap.haze');
    final share = _px('minimap.glint'), depth = _px('minimap.twinkleDepth');
    final jitter = frozen ? 0.0 : _px('minimap.jitter');
    final rate = math.pi * 2 / _px('minimap.twinkleSeconds');
    final spreadOfRates = _px('minimap.rateSpread');
    final dust = _px('minimap.dustOpacity');
    final axis = _thickness / 2;
    final grains = <Grain>[];
    for (var bin = 0; bin < bins; bin += 1) {
      final many = (budget * _curve[bin] / total).round();
      for (var index = 0; index < many; index += 1) {
        final a = _noise(bin, index), b = _noise(bin, index + budget);
        final c = _noise(bin, index + budget * 2), d = _noise(bin, index + budget * 3);
        final step = (bin + a) * binLength;
        // Phase and rate get their OWN noises: taken from the position noise
        // they would make brightness a pattern travelling across the field.
        final phase = _noise(bin, index + budget * 5) * math.pi * 2;
        final own = rate * (1 + spreadOfRates * _noise(bin, index + budget * 6));
        final twinkle = frozen ? 0.0 : math.sin(clock * own + phase);
        // Depth is measured FROM the crest inward: the exponent piles the field
        // onto the line and thins it toward the axis.
        final side = c < 1 / 2 ? -1 : 1;
        final across =
            axis +
            side * (_crestAt(step) * (1 - math.pow(b, spread).toDouble()) + haze * d * d) +
            jitter * twinkle;
        final lit = _noise(bin, index + budget * 4) < share;
        final level = ((lit ? 1 : dust) * (1 + depth * twinkle)).clamp(0.0, 1.0);
        grains.add((at: _at(step, across), alpha: level, lit: lit));
      }
    }
    return grains;
  }

  /// Grain is drawn in brightness buckets, so thousands of independently
  /// twinkling points still cost a handful of draw calls.
  void _paintGrain(Canvas canvas, List<Grain> grains) {
    final steps = count(tunable, 'minimap.twinkleSteps');
    if (steps <= 0) return;
    final grain = math.max(1.0, _px('minimap.particleRadius') * 2);
    final big = math.max(1.0, grain * _px('minimap.glintScale'));
    final buckets = <int, List<Offset>>{};
    for (final one in grains) {
      final level = (one.alpha * steps).round().clamp(0, steps);
      if (level == 0) continue;
      buckets.putIfAbsent(level * 2 + (one.lit ? 1 : 0), () => <Offset>[]).add(one.at);
    }
    for (final bucket in buckets.entries) {
      canvas.drawPoints(
        ui.PointMode.points,
        bucket.value,
        Paint()
          ..color = theme.neutral.withValues(alpha: (bucket.key >> 1) / steps)
          ..strokeWidth = bucket.key.isOdd ? big : grain
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  /// One mote per placed fact, at its exact time, sized by its composed display
  /// weight -- the ANCHORED COUNT. This is the countable regime, and the count
  /// is the whole of it: that many marks are that many facts.
  ///
  /// A mote RIDES THE WAVE. It sits on the crest at its own time, on the side
  /// its own stable hash picks and as far in from the crest as that hash says,
  /// so a cluster reads as separable marks that still belong to the curve --
  /// never as dots floating free in the band, which is what read as a dot matrix.
  void _paintMotes(Canvas canvas, double axis) {
    final spread = _px('minimap.moteSpread'), base = _px('minimap.moteSize');
    final most = _px('minimap.moteMax');
    final paint = Paint()..color = theme.neutral;
    // A paper ring, so two motes that land on each other are still two.
    final halo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _px('minimap.moteHalo')
      ..color = theme.paper;
    for (final mote in motesFor(_size)) {
      final step = project(mote.day);
      if (step == null || step < 0 || step > _length) continue;
      final depth = mote.hash % 1000 / 1000 * spread;
      final side = (mote.hash ~/ 1000).isEven ? -1 : 1;
      final size = math.min(most, math.max(1.0, base * mote.weight));
      final centre = _at(step, axis + side * _crestAt(step) * (1 - depth));
      canvas.drawCircle(centre, size / 2, halo);
      canvas.drawCircle(centre, size / 2, paint);
    }
  }

  /// The motes this size would draw: one per fact placed in a neighbourhood
  /// countable at this scale. What a spec counts when it asks whether the count
  /// is anchored to the facts.
  List<Mote> motesFor(Size size) {
    _prepare(size);
    return [
      for (var bin = 0; bin < field.bins; bin += 1)
        if (_countable(bin)) ...field.motesAt(bin),
    ];
  }

  void _paintTicks(Canvas canvas) {
    final paint = Paint()
      ..color = theme.hair
      ..strokeWidth = _px('minimap.tickWidth');
    for (final tick in _ticks) {
      final step = project(tick.days);
      if (step == null) continue;
      canvas.drawLine(_at(step, 0), _at(step, _thickness), paint);
    }
  }

  void _paintLabels(Canvas canvas) {
    final inset = _px('minimap.labelInset');
    for (final tick in _ticks) {
      final step = project(tick.days);
      if (step == null) continue;
      final painter = TextPainter(
        text: TextSpan(
          text: tick.text,
          style: theme.data.copyWith(color: theme.muted, fontSize: _px('minimap.labelSize')),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      // The label runs along the time axis, so what has to fit is its extent in
      // that direction: its height when time runs down the column.
      if (step + inset + (_vertical ? painter.height : painter.width) > _length) continue;
      painter.paint(canvas, _at(step + inset, inset));
    }
  }

  /// The window box, the focus line, and the now line. The now line is gated on
  /// the law: a frame with no clock mapping has no now to draw.
  void _paintWindow(Canvas canvas) {
    final half = spanDays / Rational.fromInt(2);
    final from = project(focusDays - half), to = project(focusDays + half);
    if (from != null && to != null) {
      final box = Rect.fromPoints(_at(from, 0), _at(to, _thickness));
      canvas.drawRect(box, Paint()..color = theme.ink.withValues(alpha: _px('minimap.windowWash')));
      canvas.drawRect(
        box,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _px('minimap.windowStroke')
          ..color = theme.ink,
      );
    }
    final focus = project(focusDays);
    if (focus != null) {
      canvas.drawLine(
        _at(focus, 0),
        _at(focus, _thickness),
        Paint()
          ..strokeWidth = _px('minimap.focusStroke')
          ..color = theme.ink,
      );
    }
    final at = nowIn(law, nowDays);
    final step = at == null ? null : project(at);
    if (step != null && step >= 0 && step <= _length) {
      paintNow(canvas, _at(step, 0), _at(step, _thickness), theme, tunable);
    }
  }

  /// Which bins sit in a COUNTABLE neighbourhood: few enough facts placed within
  /// `minimap.countSpan` pixels that every one of them can be its own mote.
  ///
  /// HOW MANY CAN BE COUNTED IS A QUESTION ABOUT INK. A mote is a mark of a known
  /// width, so the most facts a neighbourhood can show as SEPARATE marks is how
  /// many of those marks fit across it. A threshold that let more in would draw a
  /// chain of overlapping dots and call it a count -- which is what a real,
  /// sparse calendar got: at two events a day every neighbourhood passed a
  /// threshold of six in twenty-four pixels, and sixty motes at four pixels apart
  /// are not four dots you can count, they are a dotted line (ruled 2026-08-31,
  /// "render countable dots only if their count is anchored to something
  /// obvious"). Denser than that, the facts are the wave and the dust says so.
  ///
  /// The authored ceiling still binds where it is the lower of the two.
  List<bool> _countability() {
    final bins = field.bins;
    if (bins == 0 || _length <= 0) return const [];
    final pitch = _px('minimap.moteSize') + _px('minimap.moteHalo') * 2;
    final fits = pitch <= 0 ? field.bins : (_px('minimap.countSpan') / pitch).floor();
    final most = math.min(count(tunable, 'minimap.countable'), fits);
    final reach = (_px('minimap.countSpan') / 2 / (_length / bins)).ceil();
    final placed = List.filled(bins + 1, 0), quiet = List.filled(bins + 1, 0);
    for (var bin = 0; bin < bins; bin += 1) {
      placed[bin + 1] = placed[bin] + field.presentAt(bin);
    }
    final loose = List.filled(bins, false);
    for (var bin = 0; bin < bins; bin += 1) {
      loose[bin] =
          placed[math.min(bins, bin + reach + 1)] - placed[math.max(0, bin - reach)] <= most;
      quiet[bin + 1] = quiet[bin] + (loose[bin] ? 1 : 0);
    }
    // A countable bin with a dense one beside it would stripe motes through the
    // middle of a busy week: countable means the WHOLE neighbourhood is, so the
    // dense regime grows over the gaps between one busy hour and the next.
    final firm = List.filled(bins, false);
    for (var bin = 0; bin < bins; bin += 1) {
      final low = math.max(0, bin - reach), high = math.min(bins, bin + reach + 1);
      firm[bin] = quiet[high] - quiet[low] == high - low;
    }
    return firm;
  }

  bool _countable(int bin) => bin < _regimes.length && _regimes[bin];

  /// The field's bins through a triangular kernel. NOT mass-normalized:
  /// neighbouring activity ADDS and the result saturates at the full reach, so a
  /// busy stretch reads busy at a glance and a lone event still stands at its
  /// own height. The gain that sets where saturation begins is authored rather
  /// than an accident of the bin count.
  late final List<double> _curve = _smooth();

  List<double> _smooth() {
    final bins = field.bins;
    final raw = [for (var bin = 0; bin < bins; bin += 1) field.heightAt(bin)];
    final half = count(tunable, 'minimap.smooth') ~/ 2;
    final gain = _px('minimap.gain');
    if (half < 1 || bins == 0) return raw;
    return [for (var bin = 0; bin < bins; bin += 1) _kernel(raw, bin, half, gain)];
  }

  double _kernel(List<double> raw, int bin, int half, double gain) {
    var sum = 0.0;
    for (var step = -half; step <= half; step += 1) {
      final at = bin + step;
      if (at < 0 || at >= raw.length) continue;
      sum += raw[at] * (1 - step.abs() / (half + 1));
    }
    final level = sum * gain;
    return level > 1 ? 1 : level;
  }

  /// The crest's distance from the axis, in pixels, at a point on the time axis.
  /// Interpolated between bins, so the curve is continuous however few bins a
  /// wide range leaves per pixel.
  double _crestAt(double step) {
    final bins = _curve.length;
    if (bins == 0 || _length <= 0) return 0;
    final at = step / _length * bins - 1 / 2;
    final low = at.floor();
    final left = _curve[low.clamp(0, bins - 1)], right = _curve[(low + 1).clamp(0, bins - 1)];
    return (left + (right - left) * (at - low)) * _reach;
  }

  /// How far the crest may reach: the half-thickness left after the label band,
  /// times the authored share of it, breathing slowly. The breath is across the
  /// axis and uniform along it, so it can never read as a shift in time.
  double get _reach {
    final breath = frozen
        ? 0.0
        : math.sin(clock * math.pi * 2 / _px('minimap.breatheSeconds')) * _px('minimap.breathe');
    return _baseReach * (1 + breath);
  }

  /// The reach before the breath. Anything that must not change from one frame
  /// to the next -- the grain budget, and so the grains themselves -- reads it.
  double get _baseReach =>
      math.max(0.0, _thickness / 2 - _px('minimap.labelSize')) * _px('minimap.amplitude');

  late final List<LabelTick> _ticks = labelTicks(
    field.range.start,
    field.range.end,
    granularity,
    law,
    read: tunable,
  );

  /// A stable value in [0,1) for one grain. Deterministic, so the dust does not
  /// reshuffle between frames; cheap, because it runs thousands of times.
  double _noise(int bin, int index) {
    var hash = bin * 0x27d4eb2d + index * 0x165667b1;
    hash ^= hash >> 15;
    hash = (hash * 0x2545f491) & 0x3fffffff;
    hash ^= hash >> 13;
    return (hash & 0xffffff) / 0x1000000;
  }

  @override
  bool shouldRepaint(covariant MinimapPainter old) =>
      old.field != field ||
      old.focusDays != focusDays ||
      old.spanDays != spanDays ||
      old.clock != clock ||
      old.frozen != frozen ||
      old.theme != theme;
}
