// Quick capture: one line becomes an object.
//
// RULING (Don, 2026-08-26): `#group` on a miss ASKS, and the match is slightly
// fuzzy so a near-miss offers the existing group instead of failing to it. The
// JavaScript matched on exact equality, reported the miss in a toast, and had
// ALREADY COMMITTED the object by then -- so the ask lands here, before anything
// is written, and [Editor.confirmCapture] is the only thing that writes.
//
// The grammar itself is `capture_grammar.dart`, re-exported so one import
// carries the whole verb.

import '../core/coordinate_law.dart';
import '../core/eras.dart';
import '../core/exact.dart';
import '../core/object_kinds.dart';
import '../core/records.dart';
import '../core/weight.dart';
import '../core/document.dart';
import 'editor.dart';

export 'capture_grammar.dart';

/// A group the line might have meant, and how far off the typing was.
typedef GroupCandidate = ({String id, String title, int distance});

/// The question a capture still has. Nothing has been written.
typedef CaptureAsk = ({String unmatched, List<GroupCandidate> candidates});

/// A capture, ready but unwritten: what the line said, where it would land, and
/// what it still needs answered.
typedef Capture = ({
  QuickTodo line,
  String? frame,
  Rational? at,
  bool dateRefused,
  String? group,
  CaptureAsk? ask,
});

String _titleOf(Frame frame) => (frame.title ?? frame.id).trim();

extension Capturing on Editor {
  /// The group frames a capture may name. State frames are excluded: the state
  /// toggle owns those records, and projecting a state is the ruled filter.
  List<Frame> get captureGroups => [
    for (final frame in document.frames.values)
      if (frame.traits.contains('group') && !isStateFrame(frame)) frame,
  ];

  /// Read a capture line. NOTHING IS WRITTEN. An exact title match, or a prefix
  /// only one group answers to, resolves outright; anything else comes back as
  /// an ask carrying every group within the fuzz, nearest first.
  Capture? captureQuickTodo(String line, {String? frameId, Rational? todayDays}) {
    final parsed = parseQuickTodo(line);
    if (parsed == null) return null;
    // A write must never name a frame the document does not hold: a persisted
    // view may point at one that was deleted, and a first run holds none at all.
    // With no frame the object is a bare float, and its date word is read
    // against the registered standard because there is no other law to read it
    // under -- the relative forms are day counts and hold either way.
    final frame = document.frames.containsKey(frameId) ? frameId : null;
    final law = frame == null ? gregorianLaw : engine.lawOf(frame);
    final at = parsed.date.isEmpty ? null : quickDateDays(parsed.date, law, todayDays ?? nowDays());
    final wanted = parsed.group.trim();
    final match = wanted.isEmpty ? (id: null, ask: null) : _matchGroup(wanted);
    return (
      line: parsed,
      frame: frame,
      at: at,
      dateRefused: parsed.date.isNotEmpty && at == null,
      group: match.id,
      ask: match.ask,
    );
  }

  ({String? id, CaptureAsk? ask}) _matchGroup(String wanted) {
    final want = wanted.toLowerCase();
    final groups = captureGroups;
    final exact = firstMatch(groups, (frame) => _titleOf(frame).toLowerCase() == want);
    if (exact != null) return (id: exact.id, ask: null);
    final prefixed = [
      for (final frame in groups)
        if (_titleOf(frame).toLowerCase().startsWith(want)) frame,
    ];
    if (prefixed.length == 1) return (id: prefixed.single.id, ask: null);
    final fuzz = setting('edit.groupFuzz').floor().toInt();
    final near = <GroupCandidate>[];
    for (final frame in groups) {
      final title = _titleOf(frame);
      final distance = editDistance(want, title.toLowerCase(), fuzz);
      final close = distance <= fuzz || title.toLowerCase().startsWith(want);
      if (close) near.add((id: frame.id, title: title, distance: distance));
    }
    near.sort(
      (left, right) => left.distance != right.distance
          ? left.distance.compareTo(right.distance)
          : left.title.compareTo(right.title),
    );
    return (id: null, ask: (unmatched: wanted, candidates: near));
  }

  /// Write the capture. [groupId] answers its ask -- a chosen existing group, or
  /// null for none. [createGroup] authors the group the line named, which is the
  /// only way a capture ever mints a frame: a typo must never create one, but a
  /// person confirming the name has authored it.
  ///
  /// Answers with the new object's id.
  String confirmCapture(Capture capture, {String? groupId, bool createGroup = false}) {
    final group = groupId ?? capture.group;
    final minted = createGroup && group == null && capture.line.group.trim().isNotEmpty
        ? Frame(
            id: createId('frame'),
            title: capture.line.group.trim(),
            traits: const ['set', 'group'],
            extra: {
              'display': {'weight': defaultWeightForNewFrame('group')?.toJson()},
            },
          )
        : null;
    final held = minted?.id ?? group;
    final definition = objectKinds['todo']!;
    final event = newObject('todo', title: capture.line.title, note: capture.line.note);
    final frame = capture.frame;
    // BORN IN A COLUMN, STAPLED TO THE GROUP, PLACED ON NOTHING (Don, ISSUES
    // 9.2): "If I have a non-time frame as a column and I author a bunch of
    // todos stapled to it, they would only be on that frame. I could leave them
    // there, using the frame as a todo list, or then staple them one by one...
    // to a point or, better, to an event."
    //
    // This wrote TWO connections per capture -- the group staple AND a placement
    // on the board's projected calendar at NOW -- which is how every
    // column-born todo turned up under Wall Time as well, and why a second
    // column appeared to move when it gained its first member. A time SAID is
    // still honoured: the capture line's own date word is an authored position
    // and places the object wherever it lands. Silence is not now.
    final saidWhen = capture.at != null;
    final placed = frame == null || (held != null && !saidWhen)
        ? null
        : placement(event.id, frame, capture.at ?? nowDays(), definition.relationRole);
    final joined = held == null ? null : membership(event.id, held);
    transaction('Create ${definition.label}', (current) {
      var next = current.put('events', event.id, event);
      if (minted != null) next = next.put('frames', minted.id, minted);
      if (placed != null) next = next.put('relations', placed.id, placed);
      if (joined != null) next = next.put('relations', joined.id, joined);
      return next;
    });
    return event.id;
  }
}
