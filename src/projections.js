import {
  Rational,
  civilFromDays,
  coordinate,
  daysFromCivil,
  daysInMonth,
  daysToCivilCoordinate,
  floorMod,
  formatCivil,
  levelValue
} from "./exact.js";

const SVG_NS = "http://www.w3.org/2000/svg";
const WEEKDAYS = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];
const MONTHS = [
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December"
];

function element(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function svgElement(tag, attributes = {}) {
  const node = document.createElementNS(SVG_NS, tag);
  for (const [name, value] of Object.entries(attributes)) node.setAttribute(name, String(value));
  return node;
}

function calendarFrames(document) {
  return Object.values(document.frames).filter((frame) => frame.traits.includes("calendar"));
}

function groupFrames(document) {
  return Object.values(document.frames).filter((frame) => frame.traits.includes("group"));
}

function factColor(document, fact) {
  if (fact.event.traits?.includes("celestial")) return "#6d63b8";
  const group = Object.values(document.relations).find(
    (relation) => relation.type === "attachment"
      && relation.event === fact.event.id
      && document.frames[relation.frame]?.traits.includes("group")
  );
  if (group) return document.frames[group.frame]?.color || "#2e8b57";
  return "#d4552d";
}

function queryFacts(context, frame, startDays, endDays) {
  const { document, engine } = context;
  return engine.queryFacts({
    frame,
    start: daysToCivilCoordinate(startDays),
    end: daysToCivilCoordinate(endDays)
  });
}

function dayKey(day) {
  return Rational.parse(day).floor().toString();
}

function factsByDay(facts) {
  const map = new Map();
  for (const fact of facts) {
    const key = dayKey(fact.day);
    const list = map.get(key) || [];
    list.push(fact);
    map.set(key, list);
  }
  return map;
}

function eventChip(context, fact, compact = false) {
  const chip = element("button", `event-chip${compact ? " compact" : ""}`);
  chip.type = "button";
  chip.dataset.eventId = fact.event.id;
  if (fact.virtualId) chip.dataset.virtualId = fact.virtualId;
  chip.style.setProperty("--event-color", factColor(context.document, fact));
  chip.textContent = fact.event.payload?.title || "(untitled)";
  chip.title = `${chip.textContent} · ${formatCivil(fact.coordinate, true)}`;
  return chip;
}

function renderErrors(target, result) {
  if (!result.errors?.length) return;
  const error = element("div", "projection-error");
  error.textContent = result.errors.map((item) => `${item.pattern}: ${item.message}`).join(" · ");
  target.append(error);
}

function renderIntimate(target, context) {
  const focus = context.session.currentFocus();
  const firstDay = focus.floor() - 2n;
  const lastDay = firstDay + 4n;
  const result = queryFacts(context, context.session.activeFrame, new Rational(firstDay), new Rational(lastDay + 1n));
  const byDay = factsByDay(result.facts);
  const wrap = element("div", "intimate");
  const focusCoordinate = daysToCivilCoordinate(focus);
  const focusHour = Number(levelValue(focusCoordinate, "hour", "0"));

  const corner = element("div", "intimate-corner", "TIME");
  wrap.append(corner);
  for (let day = firstDay; day <= lastDay; day += 1n) {
    const civil = civilFromDays(day);
    const weekday = Number(floorMod(day + 4n, 7n));
    const header = element(
      "button",
      "intimate-dayhead",
      `${WEEKDAYS[weekday]} ${civil.month}/${civil.day}`
    );
    header.type = "button";
    header.dataset.createDay = day.toString();
    wrap.append(header);
  }

  for (let hour = 0; hour < 24; hour += 1) {
    const label = element("div", `hour-label${hour === focusHour ? " focus" : ""}`);
    label.textContent = `${String(hour).padStart(2, "0")}:00`;
    wrap.append(label);
    for (let day = firstDay; day <= lastDay; day += 1n) {
      const cell = element("div", `hour-cell${hour === focusHour ? " focus" : ""}`);
      cell.dataset.createDay = new Rational(day).add(Rational.parse(hour).div(24)).toJSON();
      const facts = (byDay.get(day.toString()) || []).filter((fact) => {
        const coordinateValue = daysToCivilCoordinate(fact.day);
        return Number(levelValue(coordinateValue, "hour", "0")) === hour;
      });
      for (const fact of facts.slice(0, 3)) cell.append(eventChip(context, fact, true));
      wrap.append(cell);
    }
  }
  target.append(wrap);
  renderErrors(target, result);
}

function renderTactical(target, context) {
  const focusDay = context.session.currentFocus().floor();
  const start = focusDay - 10n;
  const result = queryFacts(context, context.session.activeFrame, new Rational(start), new Rational(start + 21n));
  const byDay = factsByDay(result.facts);
  const grid = element("div", "tactical-grid");
  for (let offset = 0n; offset < 21n; offset += 1n) {
    const day = start + offset;
    const civil = civilFromDays(day);
    const weekday = Number(floorMod(day + 4n, 7n));
    const cell = element("section", `tactical-day${weekday === 0 || weekday === 6 ? " weekend" : ""}`);
    cell.dataset.createDay = day.toString();
    const header = element("header", "day-heading");
    header.append(
      element("span", "weekday", WEEKDAYS[weekday]),
      element("strong", "", `${civil.month}/${civil.day}`),
      element("small", "", civil.year.toString())
    );
    cell.append(header);
    for (const fact of byDay.get(day.toString()) || []) cell.append(eventChip(context, fact));
    grid.append(cell);
  }
  target.append(grid);
  renderErrors(target, result);
}

function addMonths(yearValue, monthValue, offsetValue) {
  const total = BigInt(yearValue) * 12n + BigInt(monthValue) - 1n + BigInt(offsetValue);
  return {
    year: total >= 0n ? total / 12n : (total - 11n) / 12n,
    month: ((total % 12n) + 12n) % 12n + 1n
  };
}

function monthCard(context, year, month, facts, detailed = false) {
  const card = element("section", detailed ? "wall-month" : "strategic-month");
  const heading = element("header", "month-heading");
  heading.append(
    element("strong", "", MONTHS[Number(month) - 1]),
    element("span", "", year.toString())
  );
  card.append(heading);
  const weekdays = element("div", "month-weekdays");
  for (const name of ["M", "T", "W", "T", "F", "S", "S"]) weekdays.append(element("span", "", name));
  card.append(weekdays);
  const grid = element("div", "month-days");
  const first = daysFromCivil(year, month, 1n);
  const lead = Number(floorMod(first + 3n, 7n));
  for (let index = 0; index < lead; index += 1) grid.append(element("div", "month-pad"));
  const totalDays = daysInMonth(year, month);
  for (let day = 1; day <= totalDays; day += 1) {
    const ordinal = daysFromCivil(year, month, BigInt(day));
    const cell = element("div", "month-day");
    cell.dataset.createDay = ordinal.toString();
    cell.append(element("b", "month-number", String(day)));
    const entries = facts.get(ordinal.toString()) || [];
    if (detailed) {
      for (const fact of entries.slice(0, 4)) cell.append(eventChip(context, fact, true));
    } else {
      const pips = element("div", "event-pips");
      for (const fact of entries.slice(0, 8)) {
        const pip = element("button", "event-pip");
        pip.type = "button";
        pip.dataset.eventId = fact.event.id;
        if (fact.virtualId) pip.dataset.virtualId = fact.virtualId;
        pip.style.background = factColor(context.document, fact);
        pip.title = fact.event.payload?.title || "(untitled)";
        pips.append(pip);
      }
      cell.append(pips);
    }
    grid.append(cell);
  }
  card.append(grid);
  return card;
}

function renderStrategic(target, context) {
  const focusCivil = civilFromDays(context.session.currentFocus().floor());
  const firstMonth = addMonths(focusCivil.year, focusCivil.month, -4);
  const lastMonth = addMonths(firstMonth.year, firstMonth.month, 9);
  const start = daysFromCivil(firstMonth.year, firstMonth.month, 1n);
  const end = daysFromCivil(lastMonth.year, lastMonth.month, 1n);
  const result = queryFacts(context, context.session.activeFrame, new Rational(start), new Rational(end));
  const byDay = factsByDay(result.facts);
  const grid = element("div", "strategic-grid");
  for (let index = 0; index < 9; index += 1) {
    const current = addMonths(firstMonth.year, firstMonth.month, index);
    grid.append(monthCard(context, current.year, current.month, byDay, false));
  }
  target.append(grid);
  renderErrors(target, result);
}

function renderCalendar(target, context) {
  if (context.session.scale < 0.55) renderIntimate(target, context);
  else if (context.session.scale < 1.45) renderTactical(target, context);
  else renderStrategic(target, context);
}

function renderWall(target, context) {
  const focus = civilFromDays(context.session.currentFocus().floor());
  const count = context.session.scale < 1 ? 1 : context.session.scale < 1.65 ? 3 : 6;
  const firstMonth = addMonths(focus.year, focus.month, -Math.floor(count / 2));
  const after = addMonths(firstMonth.year, firstMonth.month, count);
  const start = daysFromCivil(firstMonth.year, firstMonth.month, 1n);
  const end = daysFromCivil(after.year, after.month, 1n);
  const result = queryFacts(context, context.session.activeFrame, new Rational(start), new Rational(end));
  const byDay = factsByDay(result.facts);
  const grid = element("div", `wall-grid months-${count}`);
  for (let index = 0; index < count; index += 1) {
    const current = addMonths(firstMonth.year, firstMonth.month, index);
    grid.append(monthCard(context, current.year, current.month, byDay, true));
  }
  target.append(grid);
  renderErrors(target, result);
}

function renderLines(target, context) {
  const frames = calendarFrames(context.document);
  const prime = context.document.frames[context.session.primeFrame] || frames[0];
  const ordered = [prime, ...frames.filter((frame) => frame.id !== prime?.id)].filter(Boolean);
  const window = context.session.window();
  const width = 1200;
  const height = 620;
  const rowY = (index) => ordered.length <= 1
    ? height / 2
    : 70 + index * ((height - 140) / (ordered.length - 1));
  const svg = svgElement("svg", {
    class: "lines-svg",
    viewBox: `0 0 ${width} ${height}`,
    role: "img",
    "aria-label": "Calendar and timeline topology"
  });
  const span = window.end.sub(window.start);
  const positions = new Map();

  ordered.forEach((frame, index) => {
    const y = rowY(index);
    const color = index === 0 ? "#d4552d" : frame.color || ["#2e8b57", "#497bc1", "#8a63c9"][index % 3];
    const line = svgElement("path", {
      d: index === 0
        ? `M 145 ${y} L 1140 ${y}`
        : `M 145 ${y} C 340 ${y}, 360 ${y - 12}, 480 ${y - 12} S 760 ${y + 10}, 1140 ${y}`,
      fill: "none",
      stroke: color,
      "stroke-width": index === 0 ? 5 : 3,
      "stroke-linecap": "round"
    });
    svg.append(line);
    const label = svgElement("text", { x: 24, y: y + 5, fill: color, class: "line-label" });
    label.textContent = `${index === 0 ? "PRIME · " : ""}${frame.title}`;
    svg.append(label);

    const result = queryFacts(context, frame.id, window.start, window.end);
    for (const fact of result.facts) {
      const x = fact.day
        ? 145 + Rational.parse(fact.day).sub(window.start).div(span).toNumber() * 995
        : 145;
      if (x < 140 || x > 1145) continue;
      const stem = svgElement("line", {
        x1: x, y1: y, x2: x, y2: y - 22,
        stroke: factColor(context.document, fact),
        "stroke-width": 1.5
      });
      const dot = svgElement("circle", {
        cx: x, cy: y, r: 6,
        fill: factColor(context.document, fact),
        class: "line-event",
        tabindex: 0
      });
      dot.dataset.eventId = fact.event.id;
      if (fact.virtualId) dot.dataset.virtualId = fact.virtualId;
      const title = svgElement("title");
      title.textContent = fact.event.payload?.title || "(untitled)";
      dot.append(title);
      svg.append(stem, dot);
      const prior = positions.get(fact.event.id);
      if (prior) {
        svg.append(svgElement("path", {
          d: `M ${prior.x} ${prior.y} C ${prior.x} ${(prior.y + y) / 2}, ${x} ${(prior.y + y) / 2}, ${x} ${y}`,
          fill: "none",
          stroke: "#51483d",
          "stroke-width": 1.5,
          "stroke-dasharray": "4 4"
        }));
      } else {
        positions.set(fact.event.id, { x, y });
      }
    }
  });

  for (const relation of Object.values(context.document.relations).filter(
    (item) => item.type === "composition"
  )) {
    const parentIndex = ordered.findIndex((frame) => frame.id === relation.parent);
    const childIndex = ordered.findIndex((frame) => frame.id === relation.child);
    if (parentIndex < 0 || childIndex < 0) continue;
    const y1 = rowY(parentIndex);
    const y2 = rowY(childIndex);
    svg.append(svgElement("path", {
      d: `M 430 ${y1} C 455 ${y1}, 455 ${y2}, 480 ${y2}`,
      fill: "none",
      stroke: "#51483d",
      "stroke-width": 2
    }));
  }
  target.append(svg);
}

function polar(cx, cy, radius, angle) {
  return [cx + Math.cos(angle) * radius, cy + Math.sin(angle) * radius];
}

function renderRadial(target, context) {
  const { session } = context;
  const controls = element("div", "radial-controls");
  const cycles = Object.values(context.document.frames).filter((frame) => frame.traits.includes("cycle"));
  const previous = element("button", "instrument-button", "‹ cycle");
  previous.dataset.action = "previous-cycle";
  const cycleSelect = element("select", "select-control");
  cycleSelect.dataset.cycleSelect = "true";
  cycleSelect.setAttribute("aria-label", "Cycle frame");
  for (const frame of cycles) {
    const option = element("option", "", frame.title);
    option.value = frame.id;
    option.selected = frame.id === session.activeCycle;
    cycleSelect.append(option);
  }
  const mode = element("button", "instrument-button", session.radialMode === "spiral" ? "Spiral" : "Concentric");
  mode.dataset.action = "toggle-radial";
  const next = element("button", "instrument-button", "cycle ›");
  next.dataset.action = "next-cycle";
  controls.append(previous, cycleSelect, mode, next);
  if (session.radialMode === "spiral") {
    for (const [text, action, title] of [
      ["− in", "past-less", "Remove an inward/past turn"],
      ["+ in", "past-more", "Add an inward/past turn"],
      ["− out", "future-less", "Remove an outward/future turn"],
      ["+ out", "future-more", "Add an outward/future turn"]
    ]) {
      const button = element("button", "instrument-button small", text);
      button.dataset.action = action;
      button.title = title;
      controls.append(button);
    }
  }
  target.append(controls);

  const width = 900;
  const height = 720;
  const cx = 450;
  const cy = 360;
  const cycle = session.radialCycle;
  const start = session.radialMode === "spiral"
    ? session.currentFocus().sub(cycle.mul(session.radialPast + 0.5))
    : session.currentFocus().sub(cycle.div(2));
  const end = session.radialMode === "spiral"
    ? session.currentFocus().add(cycle.mul(session.radialFuture + 0.5))
    : session.currentFocus().add(cycle.div(2));
  const result = queryFacts(context, session.activeFrame, start, end);
  const svg = svgElement("svg", {
    class: "radial-svg",
    viewBox: `0 0 ${width} ${height}`,
    role: "img",
    "aria-label": `${session.radialMode} cycle calendar`
  });
  svg.append(svgElement("circle", {
    cx, cy, r: 54, fill: "#f5efe2", stroke: "#bdb19e", "stroke-width": 2
  }));
  const centerLabel = svgElement("text", {
    x: cx, y: cy + 4, "text-anchor": "middle", class: "radial-center"
  });
  centerLabel.textContent = formatCivil(daysToCivilCoordinate(session.currentFocus()));
  svg.append(centerLabel);

  if (session.radialMode === "spiral") {
    const turns = session.radialPast + session.radialFuture + 1;
    const inner = 82;
    const spacing = Math.min(64, 250 / Math.max(turns, 1));
    const samples = Math.max(180, turns * 120);
    let path = "";
    for (let index = 0; index <= samples; index += 1) {
      const progress = index / samples;
      const angle = -Math.PI / 2 + progress * turns * Math.PI * 2;
      const radius = inner + progress * turns * spacing;
      const [x, y] = polar(cx, cy, radius, angle);
      path += `${index ? "L" : "M"}${x.toFixed(2)} ${y.toFixed(2)} `;
    }
    svg.append(svgElement("path", {
      d: path, fill: "none", stroke: "#b7aa96", "stroke-width": 18,
      "stroke-linecap": "round"
    }));
    for (const fact of result.facts) {
      const progress = Rational.parse(fact.day).sub(start).div(end.sub(start)).toNumber();
      const angle = -Math.PI / 2 + progress * turns * Math.PI * 2;
      const radius = inner + progress * turns * spacing;
      const [x, y] = polar(cx, cy, radius, angle);
      const dot = svgElement("circle", {
        cx: x, cy: y, r: 8, fill: factColor(context.document, fact),
        class: "radial-event", tabindex: 0
      });
      dot.dataset.eventId = fact.event.id;
      if (fact.virtualId) dot.dataset.virtualId = fact.virtualId;
      const title = svgElement("title");
      title.textContent = fact.event.payload?.title || "(untitled)";
      dot.append(title);
      svg.append(dot);
    }
  } else {
    const radius = 245;
    for (let ring = 0; ring < Math.max(1, calendarFrames(context.document).length); ring += 1) {
      svg.append(svgElement("circle", {
        cx, cy, r: radius - ring * 24, fill: "none",
        stroke: ring ? "#d4cab9" : "#a99b86",
        "stroke-width": ring ? 10 : 18
      }));
    }
    for (const fact of result.facts) {
      const progress = Rational.parse(fact.day).sub(start).div(cycle).toNumber();
      const angle = -Math.PI / 2 + progress * Math.PI * 2;
      const [x, y] = polar(cx, cy, radius, angle);
      const dot = svgElement("circle", {
        cx: x, cy: y, r: 9, fill: factColor(context.document, fact),
        class: "radial-event", tabindex: 0
      });
      dot.dataset.eventId = fact.event.id;
      if (fact.virtualId) dot.dataset.virtualId = fact.virtualId;
      const title = svgElement("title");
      title.textContent = fact.event.payload?.title || "(untitled)";
      dot.append(title);
      svg.append(dot);
    }
  }
  target.append(svg);
  renderErrors(target, result);
}

export function renderProjection(target, context) {
  target.replaceChildren();
  target.dataset.projection = context.session.projection;
  if (context.session.projection === "calendar") renderCalendar(target, context);
  else if (context.session.projection === "wall") renderWall(target, context);
  else if (context.session.projection === "lines") renderLines(target, context);
  else renderRadial(target, context);
}

export function renderMinimap(target, context) {
  target.replaceChildren();
  const span = Rational.parse(String(context.session.visibleSpan()));
  const outerStart = context.session.currentFocus().sub(span.mul(2.5));
  const outerEnd = context.session.currentFocus().add(span.mul(2.5));
  const result = queryFacts(context, context.session.activeFrame, outerStart, outerEnd);
  const svg = svgElement("svg", {
    viewBox: "0 0 1000 72",
    preserveAspectRatio: "none",
    role: "img",
    "aria-label": "Time minimap"
  });
  svg.dataset.minimapStart = outerStart.toJSON();
  svg.dataset.minimapEnd = outerEnd.toJSON();
  svg.append(svgElement("line", {
    x1: 20, y1: 36, x2: 980, y2: 36,
    stroke: "#b8ab98", "stroke-width": 2
  }));
  for (const fact of result.facts.slice(0, 600)) {
    const x = 20 + Rational.parse(fact.day).sub(outerStart).div(outerEnd.sub(outerStart)).toNumber() * 960;
    svg.append(svgElement("circle", {
      cx: x, cy: 36, r: 2.8, fill: factColor(context.document, fact), opacity: 0.72
    }));
  }
  const viewportStart = context.session.currentFocus().sub(span.div(2));
  const x = 20 + viewportStart.sub(outerStart).div(outerEnd.sub(outerStart)).toNumber() * 960;
  const width = span.div(outerEnd.sub(outerStart)).toNumber() * 960;
  svg.append(svgElement("rect", {
    x, y: 12, width, height: 48, rx: 6,
    fill: "rgba(255,253,247,.48)", stroke: "#2a2620", "stroke-width": 2,
    class: "minimap-window"
  }));
  svg.append(svgElement("line", {
    x1: 500, y1: 6, x2: 500, y2: 66,
    stroke: "#d9482b", "stroke-width": 2
  }));
  target.append(svg);
}

export { calendarFrames, groupFrames };
