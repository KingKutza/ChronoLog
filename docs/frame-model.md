# General temporal frame model

ChronoLog uses one open, composable record shape instead of a closed frame-type
enumeration. A frame's `traits` describe capabilities such as `calendar`,
`timeline`, `line`, `cycle`, `measure`, `group`, and `importance`; unfamiliar
traits remain valid data. The Frames editor's type selector adds capabilities
and never strips existing ones.

Four concepts remain separate:

1. A **frame or line** owns temporal coordinates.
2. A **unit system** names and nests coordinate levels and defines their
   boundaries.
3. A **coordinate mapping** authors relationships between positions or
   intervals in two frames.
4. A **lens** projects one leading frame and optional display companions; it
   does not create a mapping.

Groups and importance sets organize membership and presentation. A pure group
does not have a basis frame, coordinate definition, period, or implied
conversion. A record with both group and temporal traits may use temporal
fields because the temporal capability is explicit.

## Units and boundaries

An ordinary fixed calendar stores a `coordinate.kind` of `nested`, ordered
named levels, exact whole-number radices, optional names within a parent, an
exact epoch, and the exact length of its smallest unit. The routine editor can
author all of these fields without JSON. Projections read those definitions;
they never substitute Gregorian weekday or month rules.

Irregular or observed cycles use `period.kind: "event-defined"` with an exact
measurement frame and a finite, strictly ordered boundary series. Each adjacent
pair is one actual interval. ChronoLog does not average gaps or extrapolate
beyond the authored series. Formula-driven periods remain advanced data.
Approximate fixed periods must retain `provenance.kind: "approximation"`; an
approximation is never presented as an observed or computed boundary.

## Cross-frame mappings

A `coordinate-mapping` relation names source and target frames and contains one
or more anchors. Each side of an anchor is either a point or an interval using
that frame's nested coordinates. Every anchor declares continuity explicitly,
including discontinuous advancement. Multiple anchors and interval-to-interval
mappings therefore model relationships such as five Earth hours corresponding
to nine Skyland days without redefining either unit system.

Mappings are domain data. Selecting a leading frame, showing a companion, or
placing two records in one group never invents a conversion.

## Migration from prototype documents

`migrateDocument` performs loss-minimizing migration when a `chronolog/1`
document is loaded:

- `basisFrame` becomes `basis`;
- an array-shaped coordinate descriptor becomes
  `coordinate: { kind: "nested", levels: ... }`;
- `cyclePeriodDays` becomes an exact period magnitude marked with approximation
  provenance and `migratedFrom: "cyclePeriodDays"`;
- composable traits and unknown coordinate/period fields are retained.

Existing terrestrial calendars share `line:earth` through
`coordinateDefinition` rather than copying Gregorian data. Existing celestial
cycles retain explicit fixed, event-defined, formula, or approximation
semantics, and Radial refuses to infer a mean period for an unbounded or
irregular cycle. The Skyland fixtures exercise an 8 × 8 × 8 named hierarchy,
non-Gregorian projection, and a discontinuous 5-hour-to-9-day mapping as the
migration/acceptance baseline.
