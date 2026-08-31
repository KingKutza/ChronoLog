// The minimap's own shipped defaults, beside the code that reads them.
//
// A WAVE FIRST, DUST SECOND (ruled 2026-08-28, from "it looks more like dirt
// than a waveform"). The numbers that make that true -- how far the kernel
// smooths, how tightly the dust hugs the crest, how much of it glints -- are
// settings like every other number a lens draws with, so the field is tuned in
// `chronolog.settings` rather than recompiled.

/// Every number the minimap draws with. Composed into `lensTunableDefaults`,
/// which the session composes into the one settings map.
const Map<String, String> minimapTunableDefaults = {
  // --- The range, and the bins the field accumulates into --------------------
  'minimap.rangeMultiple': '5',
  'minimap.bandLow': '0.12',
  'minimap.bandHigh': '0.88',
  'minimap.anchorLow': '0.25',
  'minimap.anchorHigh': '0.75',
  'minimap.bins': '288',
  'minimap.busyQuantile': '0.9',
  // The scale ladder, generated: powers of the base interleaved with the
  // half-step multiple is the 1 2 3 4 6 8 12 16 ... sequence, authored as three
  // settings rather than tabulated as twenty numbers nobody can edit.
  'minimap.ladderBase': '2',
  'minimap.ladderHalfStep': '3',
  'minimap.ladderRungs': '20',
  'minimap.particles': '5200',
  'minimap.particleRadius': '0.7',
  'minimap.baselineOpacity': '0.46',

  // --- The labels and the window box ----------------------------------------
  'minimap.labelInset': '3',
  'minimap.labelSize': '9',
  'minimap.windowStroke': '1.25',
  'minimap.focusStroke': '1.4',
  'minimap.budget.hour': '12',
  'minimap.budget.day': '16',
  'minimap.budget.month': '14',
  'minimap.budget.quarter': '18',
  'minimap.budget.fallback': '12',

  // --- The curve ------------------------------------------------------------
  // The kernel is a triangle over this many bins: neighbouring activity adds and
  // the crest saturates, which is what makes the result a wave rather than a
  // comb of spikes.
  //
  // NARROWED FROM ELEVEN (2026-08-31). A sparse calendar's own occupancy is
  // around half its bins -- two events a day, four bins to the day -- and a
  // kernel eleven bins wide sums that straight past saturation: every crest at
  // full reach, from the first event to the last, which is a SLAB and not a
  // wave. Five bins is narrow enough that a day's events read as one swell and
  // the gaps between days read as troughs, at every density.
  'minimap.smooth': '5',
  // Where saturation begins: the kernel ADDS neighbouring activity, and this is
  // the share of the reach one bin's full level claims once summed.
  'minimap.gain': '0.4',
  // The crest's reach, as a share of the half-thickness left after the labels.
  'minimap.amplitude': '0.88',
  'minimap.axisWidth': '0.75',
  'minimap.bandOpacity': '0.18',
  'minimap.crestOpacity': '0.85',
  'minimap.crestWidth': '1.1',
  'minimap.tickWidth': '1',

  // --- The dust -------------------------------------------------------------
  // Depth from the crest is a uniform draw raised to this power: above one it
  // piles the field ONTO the line, so density reads the wave a second time.
  'minimap.spread': '9',
  // How far past the crest a stray grain may fly, in pixels. This is the
  // glitter's halo; without it the crest is a wire rather than a field.
  'minimap.haze': '2.5',
  // Dust is grain, not soot: it reads as a field only while a single grain is
  // faint enough that a hundred of them make the tone.
  'minimap.dustOpacity': '0.42',
  // Grains per square pixel of the dense band. Texture is a DENSITY, so the
  // count follows the area the wave covers; `minimap.particles` is the ceiling.
  'minimap.grainPerPixel': '0.13',
  // The lit fraction and how much larger a lit grain is. A grain NEVER moves
  // along time: a travelling grain says an event moved, and none did.
  //
  // "It may be a bit much, but it is very very cool" (Don, 2026-08-28): the
  // wave and the glitter ride, the motion is calmed. A third fewer grains
  // glint, and both periods are a half again as long.
  'minimap.glint': '0.033',
  'minimap.glintScale': '2',

  // --- The motion, which has no period --------------------------------------
  // One grain's own twinkle period, and how widely the grains' rates differ
  // around it. Rates that differ are rates with no common multiple, so the
  // field never resets in unison and there is no loop to see.
  'minimap.twinkleSeconds': '36',
  'minimap.rateSpread': '0.7',
  // How deeply brightness swings, and how many brightness buckets the draw
  // quantizes to -- thousands of independent twinkles for a handful of calls.
  'minimap.twinkleDepth': '0.45',
  'minimap.twinkleSteps': '5',
  // A sub-pixel wobble ACROSS the axis. Off by default: brightness alone is
  // enough motion, and this is the knob for wanting a little more.
  'minimap.jitter': '0',
  // The band's slow breath, across the axis and uniform along it.
  'minimap.breathe': '0.03',
  'minimap.breatheSeconds': '56',

  // --- The anchored count ----------------------------------------------------
  // Up to this many placed facts within this many pixels, every fact ALSO gets
  // its own mote and the count is READ rather than estimated. Above it there are
  // no motes: a count nobody can take is noise (ruled 2026-08-31).
  //
  // The dust does NOT stand aside for them, and there is no quiet scale on the
  // envelope any more: a sparse calendar is a low wave, not a bare tile with
  // dots on it. The motes ride ON that wave.
  'minimap.countable': '6',
  'minimap.countSpan': '24',
  // A mote's size is its composed display weight, floored at a pixel and capped
  // so one heavy object cannot become a blot. THE SIZE DECIDES THE THRESHOLD as
  // much as the count above does: a mote plus its halo is the ink one fact
  // costs, and the painter admits no more of them into a neighbourhood than fit
  // across it as separate marks.
  'minimap.moteSize': '4',
  'minimap.moteMax': '8',
  'minimap.moteHalo': '1',
  // How far IN FROM THE CREST a mote may be pushed by its own stable hash, as a
  // share of the crest, so near-simultaneous facts stay separable instead of
  // stacking into one dot. At zero every mote sits exactly on the line; at one
  // the band is fair game all the way to the axis.
  'minimap.moteSpread': '0.7',

  // --- The window box -------------------------------------------------------
  'minimap.windowWash': '0.07',
};
