// One ordered set of selected frame ids plus an explicit primary marker.
//
// This is the fix for the 8.19 field report's item 1: "when I multi-select
// frames, the highest frame selected acts as the view frame, lower selected
// frames do not overlay" and "the only way to overlay frames is to use the
// frame dock active frame window, not the frames control pane, or in the
// frame dropdown on the command bar, or anywhere else." Two parallel
// mechanisms used to carry this idea — session.js's activeFrame/
// companionFrames pair (chrome-only, never consumed by rendering) and
// frames[leadingId].display.overlays (the one field the renderer actually
// read). Every frame-selection surface — the settings-bar Frame dropdown,
// the Frames panel/dock's leading select and companion checkboxes — now
// reads and writes this one class instead. See AGENTS.md's frame model,
// point 4: selecting or displaying a frame never creates a coordinate
// mapping, so this module holds pure view-selection state and no DOM.
//
// Invariants enforced on every operation:
//   - the selection is never empty once at least one id has ever been given;
//   - the primary is always a member of the selection;
//   - reassigning the primary (`setPrimary`) never changes which ids are
//     selected — it only moves the marker;
//   - removing the current primary (`toggle`) promotes another selected id,
//     never leaves the selection empty.
export class FrameSelection {
  constructor(ids = [], primary = null) {
    const unique = [...new Set((Array.isArray(ids) ? ids : []).filter((id) => typeof id === "string" && id))];
    this._ids = unique;
    this._primary = (primary && unique.includes(primary)) ? primary : (unique[0] || null);
  }

  // Primary first, then the rest in the order they were selected. Every
  // consumer (the Frame drop's checked list, the calendar projection's
  // overlay list) wants this shape, so no call site re-sorts it itself.
  selected() {
    if (!this._primary) return [...this._ids];
    return [this._primary, ...this._ids.filter((id) => id !== this._primary)];
  }

  primary() {
    return this._primary;
  }

  isSelected(id) {
    return this._ids.includes(id);
  }

  isPrimary(id) {
    return this._primary === id && id != null;
  }

  // Adds an unselected id, or removes a selected one. The last remaining id
  // cannot be removed — a control that can select itself into uselessness is
  // a trap, not a feature.
  toggle(id) {
    if (typeof id !== "string" || !id) return;
    if (!this._ids.includes(id)) {
      this._ids = [...this._ids, id];
      if (!this._primary) this._primary = id;
      return;
    }
    if (this._ids.length === 1) return;
    const index = this._ids.indexOf(id);
    this._ids = this._ids.filter((existing) => existing !== id);
    if (this._primary === id) {
      // Promote whoever now sits at the removed id's old position — the
      // "next selected frame" the ruling calls for — falling back to the
      // new first entry when the removed id was last.
      this._primary = this._ids[index] ?? this._ids[0];
    }
  }

  // Moves the marker without touching membership. An id outside the current
  // selection is added first — the settings-bar Frame drop and the Frames
  // panel's leading select both offer every frame, not only the ones already
  // checked, and picking one means "look at this too, and put it in charge,"
  // never a silent removal of what was already selected.
  setPrimary(id) {
    if (typeof id !== "string" || !id) return;
    if (!this._ids.includes(id)) this._ids = [...this._ids, id];
    this._primary = id;
  }

  // Bulk replace, e.g. from a multi-checkbox control reporting its whole
  // checked set at once. The previous primary stays primary when it is
  // still present; otherwise the first id offered leads, mirroring how a
  // freshly rendered checkbox list is read top to bottom. An empty list is
  // refused outright — the same never-empty guarantee `toggle` enforces one
  // id at a time.
  setSelection(ids) {
    const unique = [...new Set((Array.isArray(ids) ? ids : []).filter((id) => typeof id === "string" && id))];
    if (!unique.length) return;
    this._ids = unique;
    if (!this._primary || !unique.includes(this._primary)) this._primary = unique[0];
  }

  // Drops ids that no longer name a real frame (one can be deleted while
  // selected). Falls back to an arbitrary valid id only when nothing of the
  // previous selection survived; an empty `validIds` leaves the selection
  // untouched rather than clobbering it against incomplete information (a
  // caller with no frames loaded yet is not proof the selection is wrong).
  prune(validIds) {
    const valid = new Set(Array.isArray(validIds) ? validIds : []);
    if (!valid.size) return;
    const survivors = this._ids.filter((id) => valid.has(id));
    this._ids = survivors.length ? survivors : [[...valid][0]];
    if (!this._ids.includes(this._primary)) this._primary = this._ids[0];
  }
}
