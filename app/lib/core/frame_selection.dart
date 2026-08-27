// One ordered set of selected frame ids plus an explicit primary marker.
//
// This is the fix for the 8.19 field report: "when I multi-select frames, the
// highest frame selected acts as the view frame, lower selected frames do not
// overlay" and "the only way to overlay frames is to use the frame dock active
// frame window, not the frames control pane, or in the frame dropdown on the
// command bar, or anywhere else." Two parallel mechanisms used to carry the idea
// -- a session's activeFrame/companionFrames pair, which rendering never read,
// and a leading frame's own `display.overlays`, which was the one field the
// renderer did read. EVERY frame-selection surface reads and writes this one
// class instead.
//
// Selecting or displaying a frame never creates a coordinate mapping, so this
// holds pure view-selection state: no document, no law, no chrome.
//
// Invariants enforced on every operation:
//   - the selection is never empty once at least one id has ever been given;
//   - the primary is always a member of the selection;
//   - [setPrimary] never changes WHICH ids are selected -- it only moves the
//     marker;
//   - [toggle] removing the current primary promotes another selected id, never
//     leaves the selection empty.

class FrameSelection {
  FrameSelection([Iterable<String> ids = const [], String? primary]) {
    _ids = _unique(ids);
    _primary = primary != null && _ids.contains(primary)
        ? primary
        : (_ids.isEmpty ? null : _ids.first);
  }

  late List<String> _ids;
  String? _primary;

  static List<String> _unique(Iterable<String> ids) => {
    for (final id in ids)
      if (id.isNotEmpty) id,
  }.toList();

  /// Primary first, then the rest in the order they were selected. Every
  /// consumer wants this shape, so no call site re-sorts it itself.
  List<String> selected() =>
      _primary == null ? [..._ids] : [_primary!, ..._ids.where((id) => id != _primary)];

  String? primary() => _primary;

  bool isSelected(String id) => _ids.contains(id);

  bool isPrimary(String id) => _primary == id;

  /// Adds an unselected id, or removes a selected one. The last remaining id
  /// cannot be removed -- a control that can select itself into uselessness is a
  /// trap, not a feature.
  void toggle(String id) {
    if (id.isEmpty) return;
    if (!_ids.contains(id)) {
      _ids = [..._ids, id];
      _primary ??= id;
      return;
    }
    if (_ids.length == 1) return;
    final index = _ids.indexOf(id);
    _ids = [
      for (final existing in _ids)
        if (existing != id) existing,
    ];
    // Promote whoever now sits at the removed id's old position -- the "next
    // selected frame" the ruling calls for -- falling back to the new first
    // entry when the removed id was last.
    if (_primary == id) {
      _primary = index < _ids.length ? _ids[index] : _ids.first;
    }
  }

  /// Moves the marker without touching membership. An id outside the current
  /// selection is ADDED first: a surface that offers every frame, not only the
  /// checked ones, means "look at this too, and put it in charge" when one is
  /// picked -- never a silent removal of what was already selected.
  void setPrimary(String id) {
    if (id.isEmpty) return;
    if (!_ids.contains(id)) _ids = [..._ids, id];
    _primary = id;
  }

  /// Bulk replace, from a control reporting its whole checked set at once. The
  /// previous primary stays primary while it survives; otherwise the first id
  /// offered leads, mirroring how a checkbox list is read top to bottom. An
  /// empty list is refused outright -- the same never-empty guarantee [toggle]
  /// enforces one id at a time.
  void setSelection(Iterable<String> ids) {
    final unique = _unique(ids);
    if (unique.isEmpty) return;
    _ids = unique;
    if (_primary == null || !unique.contains(_primary)) _primary = unique.first;
  }

  /// Drops ids that no longer name a real frame -- one can be deleted while
  /// selected. Falls back to an arbitrary valid id only when nothing of the
  /// previous selection survived; an EMPTY valid set leaves the selection
  /// untouched rather than clobbering it against incomplete information, because
  /// a caller with no frames loaded yet is not proof the selection is wrong.
  void prune(Iterable<String> validIds) {
    final valid = {...validIds};
    if (valid.isEmpty) return;
    final survivors = [
      for (final id in _ids)
        if (valid.contains(id)) id,
    ];
    _ids = survivors.isEmpty ? [valid.first] : survivors;
    if (!_ids.contains(_primary)) _primary = _ids.first;
  }
}
