# ChronoLog identity

The ChronoLog mark is an original, repository-native SVG.  It was drawn for
this project and uses no external font, icon library, stock asset, or generated
image.  Its source is `assets/chronolog-mark.svg`; the small inline copy in
`pocket-instrument.html` is deliberately equivalent so the toolbar can inherit
the active theme's ink color.

## Meaning and construction

The outer path is an open temporal frame with explicit endpoints rather than a
closed, universal clock. The shorter blue path is a ledger-like `L` nested in
that frame. The horizontal bar is a **staple**: an authored attachment between
the coordinate frame and its recorded object. The warm central join keeps that
relationship readable at toolbar and favicon scale. It is intentionally not a
clock face, calendar page, or generic checkmark.

The mixed-case wordmark uses the application UI font stack with compact optical
spacing. `Chrono` is the stable field; `Log` takes the current primary color and
slightly heavier weight. This keeps it readable in paper and night themes, in
grayscale, and without a network font dependency.

## Use

- Use the complete inline mark in application chrome.
- Use `assets/chronolog-mark.svg` for favicons and static documents.
- Preserve the title/description when the SVG is reused as an image.
- Do not use the mark to encode event state or frame membership; it identifies
  the instrument, while the visual grammar remains the source of data marks.
