// The ToDo lenses' capture and toggle wiring. The renderers
// (src/projections.js) build inert nodes stamped with data attributes; this
// module owns the delegated listeners on #projection, so a re-render never
// orphans a handler and the stub-DOM render harness stays listener-free.
// Capture state lives on `session.todoCapture` -- transient view state,
// never serialized -- so a render mid-typing rebuilds the same text and
// puts focus back where it was.
import { Rational, civilFromDays, daysFromCivil, nowDays } from "../exact.js";
import { toggleTodoCompletion } from "./roster.js";

// PROVISIONAL GRAMMAR, pending Don's delimiter vocabulary. One line, plain
// tokens, order-free:
//   #group     names a group frame by title (first # token wins)
//   @date      names a day: today, tomorrow, +N or +Nd, YYYY-MM-DD,
//              M/D, or M/D/YYYY (first @ token wins)
//   " > "      everything after the first " > " is the note
// Every other word is the title, in the order typed. No token is required;
// a bare line is a title-only ToDo.
export function parseQuickTodo(text) {
  const raw = String(text ?? "").trim();
  if (!raw) return null;
  const [head, ...noteParts] = raw.split(" > ");
  const note = noteParts.join(" > ").trim();
  const titleWords = [];
  let group = "";
  let date = "";
  for (const word of head.trim().split(/\s+/)) {
    if (word.length > 1 && word.startsWith("#") && !group) group = word.slice(1);
    else if (word.length > 1 && word.startsWith("@") && !date) date = word.slice(1);
    else titleWords.push(word);
  }
  const title = titleWords.join(" ").trim();
  if (!title) return null;
  return { title, group, date, note };
}

// The capture grammar's date words, resolved to a universal day ordinal
// (Rational) or null for "not understood" -- never a guessed date. `today`
// is injectable for tests; the default is the real clock's civil day.
export function quickDateDays(text, todayDays = null) {
  const value = String(text ?? "").trim().toLowerCase();
  if (!value) return null;
  const today = todayDays === null ? nowDays().floor() : BigInt(Rational.parse(todayDays).floor());
  if (value === "today") return new Rational(today);
  if (value === "tomorrow") return new Rational(today + 1n);
  const ahead = /^\+(\d+)d?$/.exec(value);
  if (ahead) return new Rational(today + BigInt(ahead[1]));
  const iso = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(value);
  if (iso) {
    try {
      return new Rational(daysFromCivil(BigInt(iso[1]), BigInt(iso[2]), BigInt(iso[3])));
    } catch {
      return null;
    }
  }
  const slash = /^(\d{1,2})\/(\d{1,2})(?:\/(\d{4}))?$/.exec(value);
  if (slash) {
    // Without a year, the date is read in the current civil year -- the
    // capture line is for near work, not history entry.
    const year = slash[3] ? BigInt(slash[3]) : civilFromDays(today).year;
    try {
      return new Rational(daysFromCivil(year, BigInt(slash[1]), BigInt(slash[2])));
    } catch {
      return null;
    }
  }
  return null;
}

function emptyCapture(focus = null) {
  return { text: "", expanded: false, group: "", date: "", note: "", focus };
}

export function createTodoCapture(app, dom) {
  const { projection } = dom;

  function capture() {
    return app.session.todoCapture ||= emptyCapture();
  }

  function commit(parsed) {
    const title = String(parsed?.title || "").trim();
    if (!title) return;
    const dateDays = parsed.date ? quickDateDays(parsed.date) : null;
    const result = app.createQuickTodo({ title, group: parsed.group, dateDays, note: parsed.note });
    if (!result) return;
    if (parsed.date && dateDays === null) {
      app.toast(`Date "${parsed.date}" was not understood; the ToDo anchored to now.`, true);
    }
    if (result.unmatchedGroup) {
      app.toast(`No group titled "${result.unmatchedGroup}" -- the ToDo was created without it.`, true);
    }
    // Enter creates and keeps focus for pouring: the reset names the quick
    // field, and the re-render the transaction schedules puts the caret back.
    app.session.todoCapture = emptyCapture("quick");
  }

  // Typing must survive a render that happens underneath it (autosave, a
  // merge from another window), so every keystroke lands in the session's
  // transient capture state, not only in the soon-to-be-replaced node.
  projection.addEventListener("input", (event) => {
    const target = event.target;
    if (target?.dataset?.quickCapture) capture().text = target.value;
    else if (target?.dataset?.captureField) capture()[target.dataset.captureField] = target.value;
  });

  // The roster rows' check control -- same verb as the dock roster card's.
  projection.addEventListener("change", (event) => {
    const id = event.target?.dataset?.todoToggle;
    if (id) toggleTodoCompletion(app, id);
  });

  projection.addEventListener("keydown", (event) => {
    const target = event.target;
    if (target?.dataset?.quickCapture) {
      const state = capture();
      state.text = target.value;
      if (event.key === "Enter") {
        event.preventDefault();
        const parsed = parseQuickTodo(target.value);
        if (parsed) commit(parsed);
        return;
      }
      // Tab opens the inline standard row -- fields in place, never a dock
      // card -- and walks into its first field.
      if (event.key === "Tab" && !event.shiftKey && !state.expanded) {
        event.preventDefault();
        state.expanded = true;
        state.focus = "group";
        app.scheduleRender();
        return;
      }
      if (event.key === "Escape" && state.expanded) {
        event.preventDefault();
        event.stopPropagation();
        state.expanded = false;
        state.focus = "quick";
        app.scheduleRender();
      }
      return;
    }
    if (!target?.dataset?.captureField) return;
    const state = capture();
    state[target.dataset.captureField] = target.value;
    if (event.key === "Enter") {
      event.preventDefault();
      // The standard row commits the quick line's own tokens too; a field the
      // user filled in wins over the token that named the same thing.
      const parsed = parseQuickTodo(state.text) || { title: "", group: "", date: "", note: "" };
      commit({
        title: parsed.title || state.text.trim(),
        group: state.group.trim() || parsed.group,
        date: state.date.trim() || parsed.date,
        note: state.note.trim() || parsed.note
      });
      return;
    }
    if (event.key === "Escape") {
      // Escape collapses the row; it must not also close the dock, so it
      // stops here.
      event.preventDefault();
      event.stopPropagation();
      state.expanded = false;
      state.focus = "quick";
      app.scheduleRender();
    }
  });

  return {};
}
