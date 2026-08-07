import { FormulaRuntime } from "./formula.js";
import {
  Rational,
  civilFromDays,
  daysFromCivil,
  daysInMonth,
  floorDiv,
  floorMod
} from "./exact.js";
import {
  applyVirtualOverrides,
  coordinateToDays,
  daysToCoordinate,
  durationMagnitude,
  stableVirtualId,
  validateDocument
} from "./model.js";

function rational(value) {
  return Rational.parse(value);
}

function within(value, start, end) {
  const point = rational(value);
  return point.compare(start) >= 0 && point.compare(end) <= 0;
}

function attachmentDay(engine, relation) {
  if (!relation.coordinate) return null;
  return engine.coordinateDays(relation.frame, relation.coordinate);
}

const WEEKDAYS = { SU: 0n, MO: 1n, TU: 2n, WE: 3n, TH: 4n, FR: 5n, SA: 6n };

function weekday(day) {
  return floorMod(BigInt(day) + 4n, 7n);
}

function compactIcsDay(value) {
  const match = /^([+-]?\d{4,})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})Z?)?$/.exec(value || "");
  if (!match) return null;
  const base = new Rational(daysFromCivil(BigInt(match[1]), BigInt(match[2]), BigInt(match[3])));
  if (!match[4]) return base;
  return base
    .add(Rational.parse(match[4]).div(24))
    .add(Rational.parse(match[5]).div(1440))
    .add(Rational.parse(match[6]).div(86400));
}

function occurrenceFacts(engine, pattern, lower, upper) {
  const document = engine.document;
  const relation = document.relations[pattern.templateRelation];
  const event = document.events[pattern.templateEvent];
  if (!relation || !event?.id || !relation.coordinate) return [];
  const base = engine.coordinateDays(relation.frame, relation.coordinate);
  const baseWhole = base.floor();
  const time = base.sub(baseWhole);
  const rule = pattern.rrule || {};
  const frequency = String(rule.FREQ || "").toUpperCase();
  const interval = BigInt(rule.INTERVAL || 1);
  const count = rule.COUNT ? BigInt(rule.COUNT) : null;
  const until = compactIcsDay(rule.UNTIL);
  const excluded = new Set(pattern.exdates || []);
  const days = [];

  const accept = (day, index = null) => {
    if (day.compare(base) < 0 || day.compare(lower) < 0 || day.compare(upper) > 0) return;
    if (until && day.compare(until) > 0) return;
    if (count !== null && index !== null && index >= count) return;
    if (excluded.has(day.toJSON())) return;
    days.push(day);
  };

  if (frequency === "DAILY") {
    let first = lower.sub(base).div(interval).ceil();
    if (first < 0n) first = 0n;
    for (let index = first; ; index += 1n) {
      const day = base.add(index * interval);
      if (day.compare(upper) > 0 || (count !== null && index >= count)) break;
      accept(day, index);
    }
  } else if (frequency === "WEEKLY") {
    const weekStart = floorMod(weekday(baseWhole) - WEEKDAYS.MO, 7n);
    const baseWeek = baseWhole - weekStart;
    const selected = (rule.BYDAY ? rule.BYDAY.split(",") : [])
      .map((token) => WEEKDAYS[token.slice(-2)])
      .filter((value) => value !== undefined);
    if (!selected.length) selected.push(weekday(baseWhole));
    let dayWhole = lower.floor() - 7n;
    const finalWhole = upper.ceil() + 1n;
    for (; dayWhole <= finalWhole; dayWhole += 1n) {
      if (!selected.includes(weekday(dayWhole))) continue;
      const candidateWeekStart = dayWhole - floorMod(weekday(dayWhole) - WEEKDAYS.MO, 7n);
      const weekIndex = floorDiv(candidateWeekStart - baseWeek, 7n);
      if (weekIndex < 0n || floorMod(weekIndex, interval) !== 0n) continue;
      accept(new Rational(dayWhole).add(time));
    }
  } else if (frequency === "MONTHLY") {
    const baseCivil = civilFromDays(baseWhole);
    const lowerCivil = civilFromDays(lower.floor());
    const baseMonth = baseCivil.year * 12n + baseCivil.month - 1n;
    const lowerMonth = lowerCivil.year * 12n + lowerCivil.month - 1n;
    let cycle = floorDiv(lowerMonth - baseMonth, interval);
    if (cycle < 0n) cycle = 0n;
    const monthDays = rule.BYMONTHDAY
      ? rule.BYMONTHDAY.split(",").map((value) => BigInt(value))
      : [baseCivil.day];
    for (;; cycle += 1n) {
      const monthIndex = baseMonth + cycle * interval;
      const year = floorDiv(monthIndex, 12n);
      const month = floorMod(monthIndex, 12n) + 1n;
      const earliest = new Rational(daysFromCivil(year, month, 1n)).add(time);
      if (earliest.compare(upper) > 0) break;
      for (let monthDay of monthDays) {
        const length = BigInt(daysInMonth(year, month));
        if (monthDay < 0n) monthDay = length + monthDay + 1n;
        if (monthDay < 1n || monthDay > length) continue;
        accept(new Rational(daysFromCivil(year, month, monthDay)).add(time), cycle);
      }
    }
  } else if (frequency === "YEARLY") {
    const baseCivil = civilFromDays(baseWhole);
    const lowerCivil = civilFromDays(lower.floor());
    let cycle = floorDiv(lowerCivil.year - baseCivil.year, interval);
    if (cycle < 0n) cycle = 0n;
    for (;; cycle += 1n) {
      const year = baseCivil.year + cycle * interval;
      const month = rule.BYMONTH ? BigInt(rule.BYMONTH.split(",")[0]) : baseCivil.month;
      const dayOfMonth = rule.BYMONTHDAY ? BigInt(rule.BYMONTHDAY.split(",")[0]) : baseCivil.day;
      const yearStart = new Rational(daysFromCivil(year, 1n, 1n)).add(time);
      if (yearStart.compare(upper) > 0) break;
      if (dayOfMonth > BigInt(daysInMonth(year, month))) continue;
      const day = new Rational(daysFromCivil(year, month, dayOfMonth)).add(time);
      if (day.compare(upper) > 0) break;
      accept(day, cycle);
    }
  } else {
    accept(base, 0n);
  }

  return days.map((day) => {
    const virtualId = stableVirtualId(pattern.id, `occurrence-${day.toJSON()}`);
    const virtualEvent = {
      ...structuredClone(event),
      id: virtualId,
      provenance: { kind: "pattern", pattern: pattern.id, key: day.toJSON() }
    };
    const virtualRelation = {
      ...structuredClone(relation),
      id: `${virtualId}/attachment`,
      event: virtualId,
      coordinate: engine.daysCoordinate(relation.frame, day),
      provenance: { kind: "pattern", pattern: pattern.id, key: day.toJSON() }
    };
    return {
      kind: "virtual",
      virtualId,
      event: virtualEvent,
      relation: virtualRelation,
      day: day.toJSON(),
      coordinate: virtualRelation.coordinate
    };
  });
}

export class ChronologEngine {
  constructor(document, options = {}) {
    this.document = document;
    this.runtime = options.runtime || new FormulaRuntime(options.formula);
    this.compiledPatterns = new Map();
  }

  setDocument(document) {
    this.document = document;
    this.compiledPatterns.clear();
  }

  validate() {
    return validateDocument(this.document);
  }

  patternModule(pattern) {
    const cached = this.compiledPatterns.get(pattern.id);
    if (cached?.source === pattern.source) return cached.module;
    const module = this.runtime.compile(pattern.source);
    this.compiledPatterns.set(pattern.id, { source: pattern.source, module });
    return module;
  }

  matchingPatterns(frameId) {
    return Object.values(this.document.patterns).filter(
      (pattern) => pattern.enabled !== false
        && (!pattern.appliesTo?.length || pattern.appliesTo.includes(frameId))
    );
  }

  coordinateDays(frameId, value) {
    const frame = this.document.frames[frameId];
    const law = frame?.law;
    if (law?.pattern && law.toDays) {
      const pattern = this.document.patterns[law.pattern];
      if (!pattern) throw new Error(`Frame ${frameId} references missing law pattern ${law.pattern}`);
      const output = this.patternModule(pattern).call(law.toDays, [{
        frame: frameId,
        value,
        parameters: law.parameters || {},
        constants: pattern.constants || {}
      }]);
      return rational(output?.days ?? output);
    }
    return coordinateToDays(this.document, frameId, value);
  }

  daysCoordinate(frameId, days) {
    const frame = this.document.frames[frameId];
    const law = frame?.law;
    if (law?.pattern && law.fromDays) {
      const pattern = this.document.patterns[law.pattern];
      if (!pattern) throw new Error(`Frame ${frameId} references missing law pattern ${law.pattern}`);
      const output = this.patternModule(pattern).call(law.fromDays, [{
        frame: frameId,
        days: rational(days).toJSON(),
        parameters: law.parameters || {},
        constants: pattern.constants || {}
      }]);
      if (!output?.levels) throw new TypeError(`Frame law ${law.fromDays} must return a nested coordinate`);
      return output;
    }
    return daysToCoordinate(this.document, frameId, days);
  }

  queryState({ frame, coordinate, selection = null }) {
    const atDays = this.coordinateDays(frame, coordinate);
    const values = {};
    const errors = [];
    for (const pattern of this.matchingPatterns(frame)) {
      const exportName = pattern.exports?.state;
      if (!exportName) continue;
      try {
        values[pattern.id] = this.patternModule(pattern).call(exportName, [{
          frame,
          atDays: atDays.toJSON(),
          selection,
          constants: pattern.constants || {}
        }]);
      } catch (error) {
        errors.push({ pattern: pattern.id, message: error.message });
      }
    }
    return { frame, coordinate, atDays: atDays.toJSON(), values, errors };
  }

  queryFacts({ frame, start, end, selection = null }) {
    const fromDays = this.coordinateDays(frame, start);
    const toDays = this.coordinateDays(frame, end);
    const lower = fromDays.compare(toDays) <= 0 ? fromDays : toDays;
    const upper = fromDays.compare(toDays) <= 0 ? toDays : fromDays;
    const facts = [];
    const errors = [];
    const nativePatterns = this.matchingPatterns(frame).filter(
      (pattern) => pattern.kind === "ics-rrule"
    );
    const templateRelations = new Set(nativePatterns.map((pattern) => pattern.templateRelation));

    for (const relation of Object.values(this.document.relations)) {
      if (relation.type !== "attachment" || relation.frame !== frame || !relation.coordinate) continue;
      if (templateRelations.has(relation.id)) continue;
      const day = attachmentDay(this, relation);
      if (!day || !within(day, lower, upper)) continue;
      const event = this.document.events[relation.event];
      if (!event) continue;
      facts.push({
        kind: "explicit",
        event,
        relation,
        day: day.toJSON(),
        coordinate: relation.coordinate
      });
    }

    for (const pattern of this.matchingPatterns(frame)) {
      if (pattern.kind === "ics-rrule") {
        try {
          facts.push(...occurrenceFacts(this, pattern, lower, upper));
        } catch (error) {
          errors.push({ pattern: pattern.id, message: error.message });
        }
        continue;
      }
      const exportName = pattern.exports?.facts;
      if (!exportName) continue;
      try {
        const emitted = this.patternModule(pattern).call(exportName, [{
          frame,
          fromDays: lower.toJSON(),
          toDays: upper.toJSON(),
          selection,
          constants: pattern.constants || {}
        }]);
        if (!Array.isArray(emitted)) throw new TypeError("facts export must return a list");
        for (const output of emitted) {
          const virtualId = stableVirtualId(pattern.id, output.key);
          if (output.type === "event") {
            const day = rational(output.day);
            if (!within(day, lower, upper)) continue;
            const event = {
              id: virtualId,
              traits: output.traits || ["event", "generated"],
              magnitudes: output.magnitudes || { duration: durationMagnitude("0") },
              payload: output.payload || { title: output.key },
              provenance: { kind: "pattern", pattern: pattern.id, key: output.key }
            };
            const relation = {
              id: `${virtualId}/attachment`,
              type: "attachment",
              event: virtualId,
              frame: output.frame || pattern.frame || frame,
              role: output.role || "placed",
              coordinate: this.daysCoordinate(output.frame || pattern.frame || frame, day),
              provenance: { kind: "pattern", pattern: pattern.id, key: output.key }
            };
            facts.push({
              kind: "virtual",
              virtualId,
              event,
              relation,
              day: day.toJSON(),
              coordinate: relation.coordinate
            });
          } else if (output.type === "frame") {
            facts.push({
              kind: "virtual",
              virtualId,
              frame: {
                ...structuredClone(output),
                id: virtualId,
                provenance: { kind: "pattern", pattern: pattern.id, key: output.key }
              }
            });
          } else if (output.type === "relation") {
            facts.push({
              kind: "virtual",
              virtualId,
              relation: {
                ...structuredClone(output),
                id: virtualId,
                provenance: { kind: "pattern", pattern: pattern.id, key: output.key }
              }
            });
          }
        }
      } catch (error) {
        errors.push({ pattern: pattern.id, message: error.message });
      }
    }

    const visible = applyVirtualOverrides(this.document, facts)
      .sort((left, right) => rational(left.day || 0).compare(rational(right.day || 0)));
    return {
      frame,
      start,
      end,
      fromDays: lower.toJSON(),
      toDays: upper.toJSON(),
      facts: visible,
      errors
    };
  }
}
