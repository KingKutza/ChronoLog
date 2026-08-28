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
  // --- The curve ------------------------------------------------------------
  // The kernel is a triangle over this many bins: neighbouring activity adds and
  // the crest saturates, which is what makes the result a wave rather than a
  // comb of spikes.
  'minimap.smooth': '11',
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
  'minimap.glint': '0.05',
  'minimap.glintScale': '2',

  // --- The motion, which has no period --------------------------------------
  // One grain's own twinkle period, and how widely the grains' rates differ
  // around it. Rates that differ are rates with no common multiple, so the
  // field never resets in unison and there is no loop to see.
  'minimap.twinkleSeconds': '24',
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
  'minimap.breatheSeconds': '37',

  // --- Countable versus dense -----------------------------------------------
  // Up to this many placed facts within this many pixels, every fact is drawn
  // as its own mote and the count is READ rather than estimated. Above it they
  // coalesce into dust under the same envelope.
  'minimap.countable': '6',
  'minimap.countSpan': '24',
  // The envelope steps back where motes are talking, so four marks are not
  // swamped by the band that describes them.
  'minimap.quietScale': '0.3',
  // A mote's size is its composed display weight, floored at a pixel and capped
  // so one heavy object cannot become a blot.
  'minimap.moteSize': '6',
  'minimap.moteMax': '12',
  'minimap.moteHalo': '1.5',
  // How far across the axis a mote may be pushed by its own stable hash, so
  // near-simultaneous facts stay separable instead of stacking into one dot.
  'minimap.moteSpread': '14',

  // --- The window box -------------------------------------------------------
  'minimap.windowWash': '0.07',
};
