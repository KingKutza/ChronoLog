// Pure Dart. Nothing under lib/core/ may import Flutter or a third-party
// package.
//
// ONE PASS. The JavaScript walked `document.relations` in FOUR separate loops
// and built a dozen maps beside them; every one of those maps answers a question
// about the same records, so they are built together here, once. Overscale
// doctrine is the reason the indexes exist at all -- `resolveObjectExtent` runs
// once per object inside fact indexing and recurses through connection chains, so
// "every staple touching this id" has to be O(1) -- and it is also the reason one
// pass matters: a document-wide scan per index, per reindex, per edit is the
// difference between usable and unusable at 500 calendars.
//
// MEMOIZED ENDS. `Relation.ends` re-parses its JSON on every access, so the
// substrate would pay for the parse once per lookup on every derivation that
// reads a connection. [Indexes.endsOf] is the one parse, and every index below
// and every consumer above reads through it.
//
// ONE MEMBERSHIP POOL (R5, ruling: frames are groups). The JavaScript maintained
// two parallel membership indexes -- six maps and eight accessors -- so that
// "group" could mean one thing to the document and another to display. Under the
// ruling that duality is bookkeeping with nothing left to keep: there is one
// pool, no trait gate decides who may have members, and handling is a group
// property a projection interprets. `isOrdinaryGroup`/`isDisplayGroup` have no
// counterpart here.
//
// THE FOUR ROUTES stay distinct because the ruling names them distinctly:
// PLACEMENT is an attachment relation, MEMBERSHIP is a membership relation
// (closed transitively, here), and the two STAPLE routes are read off the staple
// index. Attachment is therefore NOT folded into the membership pool -- it is its
// own route, and folding it in would make every event a member of every calendar
// it sits on and cost a second traversal to undo.

import 'records.dart';
import 'staples.dart';

/// Why a member is in a group.
///
/// RETAINED, never collapsed to a boolean: an inspector has to be able to say
/// "because you wrote this relation" or "because it is inside that group, via
/// this one", and a membership that cannot explain itself is a membership nobody
/// can correct. `kind` is `authored` (a membership relation), `query` (a
/// selector leaf), or `nested` (inherited through `via`).
typedef Provenance = ({String kind, String? relation, String? group, String? via});

List<String> _names(Object? value) => [
  for (final item in value is List ? value : const [])
    if (item is String) item,
];

/// Every index the projection engine reads, built whole from one document.
///
/// Rebuilt rather than patched. The engine is TOLD what changed (see
/// `ProjectionEngine.applyChange`), and what that precision buys is the
/// RECURRENCE caches and the resolved laws -- the expensive derivations. This
/// pass is one walk over the relation map, so rebuilding it is cheaper than
/// proving a patch correct, and a patch that is subtly wrong is a document that
/// quietly disagrees with itself.
class Indexes {
  Indexes(this.document) {
    for (final relation in document.relations.values) {
      // ONE SHAPE, ONE WALK (Don, ruled 2026-09-01). The four record kinds this
      // pass used to branch on are gone: a connection is a staple, and what it
      // SAYS is read off its ends. A record still spelled `attachment`,
      // `membership`, `contains` or `composition` falls through here exactly as
      // any unknown type always has -- inert data, loaded and saved byte for
      // byte, and read by nobody. A document from a prior prebuild starts
      // meaning-fresh rather than being converted by code kept alive for it.
      if (!relation.isStaple) continue;
      for (final end in endsOf(relation)) {
        (_staples[end.id] ??= []).add(relation);
      }
      // WHERE IT PUTS THINGS. A frame end carrying a coordinate places the
      // object ends it is stapled to; the first such claim wins and is not
      // overwritten.
      _placed(relation);
      // AFFILIATION: a frame end that names NO point says the object is
      // somewhere on that sheet and nothing about where. WHICH END IS A FRAME is
      // what makes the group side; no arrow is read, because an identification
      // carries no direction.
      for (final edge in stapledAffiliations(relation)) {
        _edge(edge.frame, edge.object, (
          kind: 'staple',
          relation: relation.id,
          group: edge.frame,
          via: null,
        ));
      }
      // CONTAINMENT: object ends alone, every one of them silent -- the same
      // affiliation sentence with no group side, whose authored ORDER is what
      // the tree reads as held-by.
      for (final edge in stapledContainments(relation)) {
        (_children[edge.parent] ??= <String>{}).add(edge.child);
        (_parents[edge.child] ??= <String>{}).add(edge.parent);
      }
    }
    for (final pattern in document.patterns.values) {
      if (pattern.extra['enabled'] == false) continue;
      final applies = _names(pattern.extra['appliesTo']);
      if (applies.isEmpty) {
        _everywhere.add(pattern);
        continue;
      }
      for (final frameId in applies) {
        (_patterns[frameId] ??= []).add(pattern);
      }
    }
    _selectors();
    // The same total, deterministic order the staple substrate tie-breaks on,
    // applied once here rather than per lookup. It is by relation id and is NOT
    // authoring order: what a tie-break needs is an order identical across
    // reload, journal replay and every window looking at one document.
    for (final bucket in _staples.values) {
      bucket.sort((left, right) => left.id.compareTo(right.id));
    }
  }

  final Document document;

  final Map<String, List<StapleEnd>> _ends = {};
  final Map<String, Relation?> _placement = {};
  final Map<String, List<Relation>> _attachments = {}, _staples = {};
  final Map<String, Set<String>> _framesOf = {}, _children = {}, _parents = {};
  final Map<String, String> _calendarOf = {};
  final Map<String, Map<String, List<Provenance>>> _direct = {};
  final Map<String, Set<String>> _directGroups = {};
  final List<Pattern> _everywhere = [];
  final Map<String, List<Pattern>> _patterns = {};
  final Map<String, Set<String>> _closures = {}, _objects = {};

  /// A group that (transitively) contains itself, reported ONCE. Broken here
  /// rather than unioned forever, and never thrown: the loop is authored data
  /// and the author is the only one who can resolve it.
  final Map<String, String> cycles = {};

  /// This staple's two ends, parsed exactly once per document generation.
  List<StapleEnd> endsOf(Relation relation) => _ends[relation.id] ??= relation.ends;

  void _placed(Relation relation) {
    final event = relation.event;
    if (event == null) return;
    // "Seen, and it has none" is recorded distinctly from "not seen": an object
    // placed purely by a connection has a coordinate-less attachment, and
    // reading that miss as "unplaced" makes it look like it sits nowhere. The
    // first coordinate-carrying attachment wins and is not overwritten.
    if (isPlacement(relation)) {
      _placement[event] ??= relation;
    } else {
      _placement.putIfAbsent(event, () => null);
    }
    final frame = relation.frame;
    if (frame == null) return;
    (_attachments[frame] ??= []).add(relation);
    // PLACED, not merely connected. [framesOf] is what the leaf predicate's
    // "connection is not inclusion" guard reads -- "when the object ALSO has a
    // placement on the asked-about frame, only that placement represents it
    // there" -- so an AFFILIATION must not enter it. A staple that says the
    // object is somewhere on a sheet without saying where places nothing, and
    // reading it as a placement would make the object's own calendar position
    // invisible to the very frame it is affiliated with.
    if (isPlacement(relation)) (_framesOf[event] ??= <String>{}).add(frame);
    if (document.frames[frame]?.traits.contains('calendar') ?? false) {
      _calendarOf.putIfAbsent(event, () => frame);
    }
  }

  void _edge(String group, String member, Provenance because) {
    final inGroup = _direct[group] ??= {};
    (inGroup[member] ??= []).add(because);
    (_directGroups[member] ??= <String>{}).add(group);
  }

  /// THE QUERY SELECTOR AS LEAF PREDICATES (R6). The JavaScript's `ids` /
  /// `traitsAll` / `traitsAny` / `groups` matcher was a second, parallel,
  /// non-composable membership mechanism beside the authored edges. It is a LEAF
  /// now: the test runs here, once per generation, and lands in the same one pool
  /// authored edges land in, so the algebra above has exactly one substrate to
  /// read. The three negation refusals die with it -- `excludeGroups` and
  /// `notGroups` are inert data, because NOT is authored in the expression.
  ///
  /// DEVIATION, with the reason: a selector naming no ids and no traits selects
  /// NOTHING here. The JavaScript's loop had no guard and so matched every event
  /// and every frame in the document, which made `query: {groups: [...]}` -- a
  /// statement purely about nesting -- silently claim every record as a member.
  /// That is a defect, not a ruling: an empty test is not a claim about
  /// everything.
  void _selectors() {
    for (final frame in document.frames.values) {
      final query = obj(frame.extra['query']);
      if (query == null) continue;
      final because = (kind: 'query', relation: null, group: frame.id, via: null);
      for (final nested in _names(query['groups'])) {
        _edge(frame.id, nested, because);
      }
      final wanted = query['ids'] is List ? _names(query['ids']).toSet() : null;
      final all = _names(query['traitsAll']), any = _names(query['traitsAny']);
      if (wanted == null && all.isEmpty && any.isEmpty) continue;
      for (final (id, traits) in [
        for (final event in document.events.values) (event.id, event.traits),
        for (final other in document.frames.values) (other.id, other.traits),
      ]) {
        if (wanted != null && !wanted.contains(id)) continue;
        if (all.any((trait) => !traits.contains(trait))) continue;
        if (any.isNotEmpty && !any.any(traits.contains)) continue;
        _edge(frame.id, id, because);
      }
    }
  }

  /// The transitive membership pool: the LEAST FIXED POINT of positive nesting.
  ///
  /// Positive nesting is monotonic over a finite graph, so repeatedly adding
  /// inherited members terminates at the least fixed point, and a self-edge
  /// becomes a no-op rather than a hang. Provenance travels: an inherited member
  /// records the group it came through, so the chain is explainable.
  late final Map<String, Map<String, List<Provenance>>> members = _close();

  Map<String, Map<String, List<Provenance>>> _close() {
    final closed = {
      for (final entry in _direct.entries)
        entry.key: {
          for (final row in entry.value.entries) row.key: [...row.value],
        },
    };
    var changed = true;
    while (changed) {
      changed = false;
      for (final group in closed.keys.toList()) {
        final inGroup = closed[group]!;
        for (final member in inGroup.keys.toList()) {
          for (final inherited in closed[member]?.keys ?? const <String>[]) {
            if (inGroup.containsKey(inherited)) continue;
            inGroup[inherited] = [(kind: 'nested', relation: null, group: group, via: member)];
            changed = true;
          }
        }
      }
    }
    for (final group in closed.keys) {
      if (closed[group]!.containsKey(group)) {
        cycles[group] =
            'Group $group contains itself; the cycle was broken here rather'
            ' than unioned forever.';
      }
    }
    return closed;
  }

  /// The membership closure read from the member's side, inverted once. Asked
  /// per object inside draw loops, so a scan of every group per lookup is the
  /// difference between usable and unusable at 500 calendars.
  late final Map<String, Set<String>> _groupsOf = () {
    final out = <String, Set<String>>{};
    for (final entry in members.entries) {
      for (final member in entry.value.keys) {
        (out[member] ??= <String>{}).add(entry.key);
      }
    }
    return out;
  }();

  // --- What the engine asks -------------------------------------------------

  /// The object's placement relation, or null.
  ///
  /// A MISS IS THE ANSWER here, and provably so: this pass sees every attachment
  /// relation in the document, so an id it never saw has no attachment at all --
  /// which is exactly "no placement". The substrate's index-or-scan dual path
  /// therefore collapses to one arm with nothing lost.
  Relation? placementOf(String objectId) => _placement[objectId];

  List<Relation> staplesOf(String id) => _staples[id] ?? const [];

  List<Relation> attachmentsOf(String frameId) => _attachments[frameId] ?? const [];

  List<String> framesOf(String eventId) => [...?_framesOf[eventId]];

  String? calendarFrameOf(String eventId) => _calendarOf[eventId];

  List<String> childrenOf(String id) => [...?_children[id]]..sort();

  List<String> parentsOf(String id) => [...?_parents[id]]..sort();

  /// One authored hop upward: the groups this id is a direct member of. Distance
  /// in the connection graph is counted in hops, so the closure above cannot
  /// answer this -- it has already flattened them.
  List<String> directGroupsOf(String id) => [...?_directGroups[id]]..sort();

  /// Every pattern that projects onto this frame. A pattern naming no
  /// `appliesTo` applies everywhere, which is what an imported series does.
  List<Pattern> patternsFor(String frameId) => [..._everywhere, ...?_patterns[frameId]];

  /// The frames whose OWN placements populate this one: itself, plus every frame
  /// transitively inside it. This is the substrate the OR case of the algebra
  /// reads, and the reason a group needs no arithmetic of its own -- each member
  /// resolved under its own law, unioned, never re-resolved under the group's.
  Set<String> frameClosure(String frameId) => _closures[frameId] ??= {
    frameId,
    for (final id in members[frameId]?.keys ?? const <String>[])
      if (document.frames.containsKey(id)) id,
  };

  /// EVERY FRAME THIS OBJECT IS STAPLED TO, HOWEVER AUTHORED.
  ///
  /// "There is no membership, only staples. The only relationship any object or
  /// frame can have to another is a staple." (Don, ruled 2026-09-01, answering
  /// the board report.) The four record kinds this document still stores them in
  /// -- an attachment's frame, a membership edge, a containment parent, an
  /// authored staple's frame end -- are four SPELLINGS of one sentence, and a
  /// reader that counts only one of them makes the others invisible: Don's AI
  /// Tiger Team connection, said by the picker as an anchor staple, could not
  /// column on a board that read memberships alone.
  ///
  /// So this is the ONE read for the question, and it is a READ: nothing is
  /// migrated, every record still loads and saves byte for byte. What a future
  /// melt of the kinds themselves would take is that every writer mints one
  /// staple record and every derivation below reads its ends -- this method is
  /// where that change would land, and the only place, which is the point of
  /// having it.
  ///
  /// Transitive by membership, because a frame inside a frame the object is in
  /// is a frame the object is in; direct by every other route, because a staple
  /// says what it says and nothing more.
  List<String> stapledFrames(String objectId) {
    final found = <String>{
      ...?_framesOf[objectId],
      ...?_parents[objectId],
      for (final staple in staplesOf(objectId))
        for (final end in endsOf(staple))
          if (end is FrameEnd) end.frame,
      ...?_groupsOf[objectId],
    };
    return [
      for (final id in found)
        if (document.frames.containsKey(id)) id,
    ]..sort();
  }

  /// The objects transitively inside this frame by MEMBERSHIP. Their placements
  /// live on whatever frames they are attached to; membership is a connection
  /// route in its own right, so they populate this frame from wherever they sit.
  Set<String> memberObjects(String frameId) => _objects[frameId] ??= {
    for (final id in members[frameId]?.keys ?? const <String>[])
      if (document.events.containsKey(id)) id,
  };
}


// --- Finding a thing by its name --------------------------------------------

/// WHAT A RECORD IS CALLED. One reading, so the find, the picker and the
/// sentence rows cannot disagree about what a thing's name is. A record with no
/// title wears its id, because a nameless row a person cannot pick is worse than
/// an ugly one.
String recordTitle(Object? record) => switch (record) {
  Frame(:final title, :final id) => (title ?? '').trim().isEmpty ? id : title!.trim(),
  Event(:final payload, :final id) =>
    (str(payload?['title']) ?? '').trim().isEmpty ? id : str(payload!['title'])!.trim(),
  _ => '',
};

/// The words of a name, as the find indexes them: lowercased, cut at everything
/// that is not a letter or a digit. Not a language model -- a name is a bag of
/// words and this is the bag.
List<String> titleWords(String title) => [
  for (final word in title.toLowerCase().split(_notWord))
    if (word.isNotEmpty) word,
];

final RegExp _notWord = RegExp('[^a-z0-9]+');

/// One match, with everything the ranking used, so a caller can say WHY this
/// row is first.
typedef TitleHit = ({String id, String label, String kind, int tier, int degree});

/// THE FIND NEVER GOES BLIND (Don, ISSUES 9.2: "How does the staple-to search
/// work with 50 frames, 2k todos and 1200 events? It seems like it would
/// overwhelm fast.").
///
/// It did worse than overwhelm. The picker swept the document linearly, frames
/// then events in map order, and cut the sweep at a RECORD budget -- so at Don's
/// numbers the last twelve hundred objects were never looked at for ANY query
/// and a todo authored late could not be found by its own name. A budget that
/// skips DATA instead of bounding WORK is the shape overscale forbids: "if it is
/// not usable at 500 calendars it is improperly built for 3."
///
/// So the words are INDEXED -- token to ids, once per document generation, where
/// every other index lives -- and the index is consulted IN FULL. What stays
/// bounded is the window a surface draws and the ordering work behind it.
///
/// RANKING, because the window stays small: an exact name beats a word of it,
/// which beats the start of a word, which beats a run of letters inside one; and
/// among equals THE MOST CONNECTED CANDIDATE WINS. The pile is a graph, so
/// project the graph -- a thing already stapled to six others is the thing a
/// person reaching for a name is most likely reaching for, and document order is
/// not a ranking at all.
class TitleIndex {
  TitleIndex(Document document) {
    for (final record in [...document.frames.values, ...document.events.values]) {
      final label = recordTitle(record);
      _titles[record.id] = label;
      _kinds[record.id] = record is Frame ? 'frame' : 'object';
      (_byTitle[label.toLowerCase()] ??= <String>{}).add(record.id);
      for (final word in titleWords(label)) {
        (_byWord[word] ??= <String>{}).add(record.id);
      }
    }
    // GRAPH DEGREE, counted in the same pass every other index is built in: how
    // many connections name this thing at all. An end counted once per staple,
    // so an n-ary staple that names one object twice is still one connection to
    // it.
    for (final relation in document.relations.values) {
      if (!relation.isStaple) continue;
      for (final id in {for (final end in relation.ends) end.id}) {
        _degree[id] = (_degree[id] ?? 0) + 1;
      }
    }
    _words = _byWord.keys.toList()..sort();
  }

  final Map<String, String> _titles = {}, _kinds = {};
  final Map<String, Set<String>> _byTitle = {}, _byWord = {};
  final Map<String, int> _degree = {};
  late final List<String> _words;

  /// How many connections name this thing.
  int degreeOf(String id) => _degree[id] ?? 0;

  /// Every word the index knows that begins with [prefix]. Found by bisecting
  /// the sorted vocabulary rather than walking it, because the vocabulary is the
  /// part that grows with the document.
  Iterable<String> wordsStarting(String prefix) {
    var low = 0, high = _words.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (_words[middle].compareTo(prefix) < 0) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    final found = <String>[];
    for (var index = low; index < _words.length; index += 1) {
      if (!_words[index].startsWith(prefix)) break;
      found.add(_words[index]);
    }
    return found;
  }

  /// The ids this one term matches, each with the best tier it matched at.
  ///
  /// The tiers are asked in order and the FIRST one an id answers wins, because
  /// a better reason to show a row does not stop being the reason when a worse
  /// one also holds.
  Map<String, int> _matches(String term) {
    final found = <String, int>{};
    void offer(int tier, Iterable<String> ids) {
      for (final id in ids) {
        found.putIfAbsent(id, () => tier);
      }
    }

    offer(0, _byTitle[term] ?? const <String>{});
    offer(1, _byWord[term] ?? const <String>{});
    for (final word in wordsStarting(term)) {
      offer(2, _byWord[word]!);
    }
    // A RUN OF LETTERS INSIDE A WORD, over the index's own VOCABULARY and not
    // over the records: the words are deduplicated, so this is the cheap half of
    // what a linear sweep of every title used to cost, and it is complete.
    for (final word in _words) {
      if (word.contains(term)) offer(3, _byWord[word]!);
    }
    return found;
  }

  /// Every id this query reaches, worst tier per id.
  ///
  /// A query of several words is an AND over its words -- "reggie fo" means both
  /// -- and the row's tier is the WORST of them, because a row is only as good a
  /// match as its weakest word.
  Map<String, int> matching(String query) {
    final terms = titleWords(query);
    if (terms.isEmpty) return const {};
    Map<String, int>? standing;
    for (final term in terms) {
      final found = _matches(term);
      if (standing == null) {
        standing = found;
        continue;
      }
      standing.removeWhere((id, _) => !found.containsKey(id));
      for (final id in standing.keys) {
        final tier = found[id]!;
        if (tier > standing[id]!) standing[id] = tier;
      }
    }
    // The whole query said as one name outranks any word-by-word reading of it.
    for (final id in _byTitle[query.trim().toLowerCase()] ?? const <String>{}) {
      if (standing!.containsKey(id)) standing[id] = 0;
    }
    return standing ?? const {};
  }

  String labelOf(String id) => _titles[id] ?? id;
  String kindOf(String id) => _kinds[id] ?? 'object';
}

// MEMOIZED BY DOCUMENT IDENTITY, one entry, exactly as the coordinate laws are:
// a find runs on every keystroke of every open picker and the document it reads
// is immutable, so the index is built once per generation and dropped the moment
// a different document is asked about. One entry rather than a cache, because
// there is one document open and holding the previous generations would hold
// every record they name.
Document? _indexedDocument;
TitleIndex? _titleIndex;

TitleIndex titleIndexOf(Document document) {
  if (!identical(_indexedDocument, document) || _titleIndex == null) {
    _titleIndex = TitleIndex(document);
    _indexedDocument = document;
  }
  return _titleIndex!;
}
