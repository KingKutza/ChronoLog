// COPY, CUT, PASTE, DUPLICATE.
//
// WHAT A COPY CARRIES, and it is Don's ruling whole (ISSUES 9.2): "ALL of the
// object's own settings -- properties, traits, magnitudes, colour, kind,
// everything on the record -- and NO staples." His ground for the second half:
// "I cannot think of a clean way to drop staples for linear calendar frames and
// keep the rest that would generalize well to edge cases." So no partition of a
// record's connections into positional and affiliative is attempted here. The
// copy arrives connected to nothing and the paste says the ONE sentence it can
// -- the placement at the drop. Everything else the person re-says on the card,
// where saying it is one click and reading it back is the point.
//
// THE CLIPBOARD IS RECORDS, NOT IDS. What is held is the Event itself, snapshot
// at the moment of the copy: a copy taken and then pasted after the source was
// edited pastes what was copied, and a cut still holds its record after the
// document no longer does. Holding ids would make both of those lies, and would
// make a cut's clipboard point at nothing.
//
// EVERY DOOR IS ONE TRANSACTION, so it is one undo entry and one journal line,
// because each is ONE ACT a person performed. A paste of nine objects is a
// paste, not nine pastes. A cut is a copy and a delete said together and undone
// together: the copy writes nothing, so the entry is the delete's, and the
// delete's inverse restores every staple the cascade took with it -- which is
// what makes "undo the cut" put the thing back where it was rather than beside
// where it was.
//
// A COPY IS NOT AN EDIT. It touches no record, so it pushes no undo entry and
// writes no journal line. Undo after a copy undoes whatever came before it,
// which is what a person means by undo.

import '../core/document.dart';
import '../core/exact.dart';
import '../core/object_kinds.dart';
import '../core/records.dart';
import '../core/staples.dart';
import 'editor.dart';

extension Clipboard on Editor {
  /// Snapshot [ids] onto the clipboard. Writes nothing.
  ///
  /// The order asked for is the order held, and an id the document does not
  /// hold is not held: a selection can outlive a record, and pasting a record
  /// that was never read would paste an invention.
  void copyObjects(Iterable<String> ids) {
    setClipboard([
      for (final id in ids)
        if (document.events[id] case final Event event) event,
    ]);
  }

  /// Copy, then delete -- ONE undo entry.
  ///
  /// The delete goes through the document's own removal, which is what cascades
  /// the staples: a record's connections are not a second thing to clean up,
  /// they are ends naming a record that is gone. That cascade is inside the
  /// transaction, so its inverse is inside the undo, and one step puts the
  /// object back with every sentence that was said about it.
  void cutObjects(Iterable<String> ids) {
    copyObjects(ids);
    final cut = [for (final event in clipboard) event.id];
    if (cut.isEmpty) return;
    transaction(cut.length == 1 ? 'Cut object' : 'Cut ${cut.length} objects', (current) {
      var next = current;
      for (final id in cut) {
        next = next.remove('events', id);
      }
      return next;
    });
  }

  /// Paste every held record onto [frameId] at [atDays]. Answers the new ids.
  ///
  /// WHERE A MULTI-OBJECT PASTE LANDS ITS SECOND OBJECT IS UNRULED -- whether
  /// the selection keeps its relative spacing or every object arrives at the
  /// drop. Nothing is invented while it is open: each pasted record says the one
  /// coordinate the pointer named, which is the claim the gesture actually made,
  /// and a spacing rule can be added later without unsaying it.
  List<String> pasteObjects(String frameId, Rational atDays) =>
      _land('Paste', [for (final event in clipboard) (event: event, frame: frameId, days: atDays)]);

  /// Copy [ids] and paste each beside itself: its own coordinate on its own
  /// frame, moved by `edit.pasteStepDays`. ONE undo entry for the selection.
  ///
  /// The step is what makes a keyboard duplicate visible. Landing the twin
  /// exactly on its source would be a correct paste and an invisible one -- two
  /// marks at one coordinate, which every timed lens draws as one -- so the
  /// keyboard's landing is a step away, and how far is a settings key like every
  /// other number in this area.
  ///
  /// WHERE A SOURCE SITS IS THE EXTENT DERIVATION'S ANSWER, never a placement
  /// record read directly: an object positioned only by a staple to another
  /// object rides that staple and has no placement of its own, and its twin has
  /// to land where the object actually is. An object that resolves nowhere is
  /// duplicated as the record it is, with nothing said about where it sits --
  /// which is what it says about itself.
  List<String> duplicateObjects(Iterable<String> ids) {
    copyObjects(ids);
    final step = setting('edit.pasteStepDays');
    return _land('Duplicate', [
      for (final event in clipboard)
        if (staples.resolveObjectExtent(event.id) case final Extent extent)
          (
            event: event,
            frame: extent.frame ?? '',
            days: (extent.startDays ?? Rational.zero) + step,
          ),
    ]);
  }

  /// The one write both doors share: mint an id per held record, carry every
  /// own field across, and say the single placement each landing names.
  List<String> _land(String verb, List<({Event event, String frame, Rational days})> landings) {
    if (landings.isEmpty) return const [];
    final minted = [
      for (final landing in landings)
        (landing: landing, copy: landing.event.copyWith(id: createId('event'))),
    ];
    transaction(
      minted.length == 1 ? '$verb object' : '$verb ${minted.length} objects',
      (current) {
        var next = current;
        for (final (:landing, :copy) in minted) {
          next = next.put('events', copy.id, copy);
          // NOWHERE IS AN ANSWER. A frame end naming no frame would be a
          // sentence about a sheet that does not exist; the record simply
          // arrives saying nothing about where it sits, exactly as an object
          // whose source said nothing does.
          if (landing.frame.isEmpty) continue;
          final placed = placement(
            copy.id,
            landing.frame,
            landing.days,
            objectKinds[objectKindForEvent(copy)]!.relationRole,
          );
          next = next.put('relations', placed.id, placed);
        }
        return next;
      },
    );
    // A refused transaction wrote nothing, and answering with ids no record
    // wears would have every caller select and scroll to something that is not
    // there. What landed is what is reported.
    return [
      for (final (landing: _, :copy) in minted)
        if (document.events.containsKey(copy.id)) copy.id,
    ];
  }
}
