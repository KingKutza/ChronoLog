// The one door onto every editor card.
//
// A card IS a tile: there is no dock, nothing floats, and a card is placed by
// the same rules a lens is. Opening one twice focuses the one already open --
// `Stage.open` is idempotent by id and a card's id is derived from what it
// edits, so two surfaces asking for the same object cannot mint two drafts.
//
// THE BODY SEAM. This factory owns each card's tile identity; a card's BODY is
// registered against its class, so the object cards register themselves here
// and the frame, browser, document, settings and theme bodies are registered by
// whoever builds them. A class nobody registered renders a stated gap rather
// than an empty panel -- refuse loudly, never guess.

import 'package:flutter/material.dart';

import '../core/document.dart';
import '../core/exact.dart';
import '../core/object_kinds.dart';
import '../edit/editor.dart';
import '../host/file_picker.dart';
import '../lens/theme.dart';
import '../session/files.dart';
import '../session/settings.dart';
import '../stage/content.dart';
import '../stage/tile.dart';
import 'card_chrome.dart';
import 'object_card.dart';
import 'settings_words.dart';

/// The numbers the object cards draw with, as expressions in the one math.
/// Disjoint by key from the frame cards' map, so one number has one home.
const Map<String, String> cardTunableDefaults = {
  'card.sigil': '15',
  'card.noteLines': '12',
  'card.pickerWidth': '150',
  'card.pickerHeight': '200',
  // The grab handle on the colour field and the hue track.
  'card.pickerGrip': '12',
  // Overscale: a typeahead never enumerates. It lists this many hits and
  // reports the rest as a lower bound, exactly as a truncated fact window does.
  'card.searchWindow': '12',
  'card.searchScan': '2000',
  // HOW FAR "STAPLED HERE" LOOKS. A neighbourhood is a DISTANCE and the
  // distance is authored (ruled 2026-09-03): one means the things stapled
  // directly to this, two means their neighbours too, and the row offers the
  // number so nobody has to accept the one this file happens to prefer.
  'card.stapledDistance': '1',
  // HOW TALL A REGION OF SENTENCES GETS BEFORE IT SCROLLS ON ITS OWN (ISSUES
  // 9.2: "the staple cards are so tall that it can be overwhelming"). The
  // header stays put; the region below it takes this much room and then rides
  // its own scroll, so two hundred staples cost the same height as two.
  'card.regionHeight': '30 * 16',
};

/// The card layer's WORDS. A chord is not arithmetic and neither is the name of
/// a point, so these ship as text rather than as expressions.
const Map<String, String> cardTextDefaults = {
  // WHICH POINT EACH END OF A NEW OBJECT-TO-OBJECT SENTENCE STARTS AT (ISSUES
  // 9.2, the horde: thirteen todos stapled to a meeting drew nowhere because
  // the + row wrote the whole on both ends). Don's own preference -- this
  // object's start on that one's end -- is one word away in either key.
  'edit.newPointNear': 'start',
  'edit.newPointFar': 'start',
};

/// What a card was asked to edit: its class, the record it names, and the seed
/// a "new" card starts from.
typedef CardRequest = ({
  String klass,
  String? id,
  String? kind,
  String? frameId,
  Rational? startDays,
  Rational? endDays,
});

typedef CardBody = Widget Function(BuildContext context, CardRequest request);

class CardFactory {
  CardFactory(
    this.editor,
    this.settings,
    this.stage, {
    Map<String, CardBody> bodies = const {},
    this.files,
    this.onTheme,
    this.picker,
    this.dataRoot,
  }) : bodies = {...bodies} {
    for (final klass in const ['object', 'newObject']) {
      this.bodies.putIfAbsent(
        klass,
        () =>
            (context, request) => ObjectCard(request: request),
      );
    }
  }

  final Editor editor;
  final Settings settings;
  final Stage stage;

  /// Where the plaintext sidecars live. Absent, a card that needs one says so
  /// rather than reaching for the filesystem itself.
  final SessionFiles? files;

  /// Draw the surface in this palette, now. Apply and Save are separate verbs
  /// (ISSUES 8.17), and this is Apply.
  final void Function(ChronoTheme theme)? onTheme;

  /// The host's file dialog, where the platform has one.
  final FilePicker? picker;

  /// The data directory, for the cards that report or resolve against it.
  final String? dataRoot;

  /// Card bodies by class. Register one and that class stops being a stated gap.
  final Map<String, CardBody> bodies;

  TileSpec objectCard(String objectId) => _card('object', 'Object', id: objectId);

  TileSpec newObjectCard(String kind, {String? frameId, Rational? startDays, Rational? endDays}) =>
      _card(
        'newObject',
        'New ${objectKinds[normalizeObjectKind(kind)]!.label}',
        kind: kind,
        frameId: frameId,
        startDays: startDays,
        endDays: endDays,
        // A new card is one per seed, not one per document: two drag-creates in
        // a row are two objects and want two cards.
        nonce: createId('card'),
      );

  TileSpec frameCard(String frameId) => _card('frame', 'Frame', id: frameId);

  /// A frame that does not exist yet. [kind] is a SEED for the trait bundle the
  /// card opens holding, never a species: absent, the card reads the authored
  /// starting bundle and offers what the document itself exhibits.
  TileSpec newFrameCard({String? kind}) =>
      _card('newFrame', 'New frame', kind: kind, nonce: createId('card'));

  TileSpec framesBrowser() => _card('frames', 'Frames');

  /// THE WHOLE LIST OF WHAT IS STAPLED TO ONE RECORD (ISSUES 9.2). The same
  /// class as the frames browser -- a list of records with a find -- differing
  /// only in which list it is, which is what the request's own id says.
  TileSpec stapledBrowser(String recordId) => _card('frames', 'Stapled here', id: recordId);

  TileSpec documentCard() => _card('document', 'Document');

  /// The settings family (ISSUES 9.1, Don's ruling). One class, one body: the
  /// main card is the one that names no area, and a sub-card names the area it
  /// governs. Twenty sub-cards are twenty of THESE, not twenty registered
  /// classes -- which surfaces exist is authored data, and a class list would be
  /// exactly the enum the ruling refuses.
  ///
  /// An area no card governs opens the MAIN card and says so, rather than a
  /// blank sub-card claiming to hold settings that are not there.
  TileSpec settingsCard({String? area}) {
    final wanted = area?.trim() ?? '';
    if (wanted.isEmpty) return _card('settings', 'Settings');
    final family = settingsSubCards({...settings.keys, ...settings.shippedText.keys});
    if (!family.any((card) => card.address == wanted)) {
      settings.refusals.add(
        'No settings card governs "$wanted", so the main settings card opened instead.',
      );
      return _card('settings', 'Settings');
    }
    return _card('settings', settingsCardTitle(wanted), kind: wanted);
  }

  TileSpec themesCard() => _card('themes', 'Themes');

  /// Every card is built here, so identity and hosting are stated once.
  TileSpec _card(
    String klass,
    String title, {
    String? id,
    String? kind,
    String? frameId,
    Rational? startDays,
    Rational? endDays,
    String nonce = '',
  }) {
    final request = (
      klass: klass,
      id: id,
      kind: kind,
      frameId: frameId,
      startDays: startDays,
      endDays: endDays,
    );
    final tileId = 'card:$klass:${id ?? kind ?? 'one'}${nonce.isEmpty ? '' : ':$nonce'}';
    final body = bodies[klass];
    return TileSpec(
      id: tileId,
      type: 'card',
      klass: klass,
      title: title,
      build: (context) => CardHost(
        factory: this,
        request: request,
        tileId: tileId,
        // THE BODY IS BUILT BELOW THIS HOST (ISSUES 9.1, "clicking the × of a
        // frame window does not close it"). Invoking `body` with the context
        // this spec was built under resolves `CardHost.of` to whatever host
        // stands ABOVE the tile -- the shell's fallback, whose tileId is empty
        // -- so a card's × called `stage.close('')` and removed nothing. The
        // Builder puts the body's context under the CardHost this factory just
        // made, which is what makes "a card's own host overrides this one" true
        // rather than aspirational, for every body, however it reads its host.
        child: Builder(
          builder: (context) => body == null
              ? Padding(
                  padding: EdgeInsets.all(cardPx(context, 'card.pad')),
                  child: cardNote(context, 'The $title card has no registered body yet.'),
                )
              : body(context, request),
        ),
      ),
    );
  }

  void open(TileSpec spec) => stage.open(spec);

  /// Every card class as a CONTENT (the one ancestor, ruled 2026-09-01), the
  /// settings sub-cards included — one entry per sub-card the authored table
  /// derives, so the connectivity universe holds the whole family by
  /// derivation.
  ///
  /// A record-bound class (the object and frame cards) mints its spec over the
  /// document's own first record; a document with none falls back to the
  /// class's NEW door, so the content is always mintable and never invents a
  /// record the owner did not author.
  List<TileContent> contents() {
    String? anyObject() => editor.document.events.keys.firstOrNull;
    String? anyFrame() => editor.document.frames.keys.firstOrNull;
    return [
      DoorContent('card:object', 'Object', (id) {
        final sample = anyObject();
        return sample == null ? newObjectCard('event') : objectCard(sample);
      }),
      DoorContent('card:newObject', 'New object', (id) => newObjectCard('event')),
      DoorContent('card:frame', 'Frame', (id) {
        final sample = anyFrame();
        return sample == null ? newFrameCard() : frameCard(sample);
      }),
      DoorContent('card:newFrame', 'New frame', (id) => newFrameCard()),
      DoorContent('card:frames', 'Frames', (id) => framesBrowser()),
      DoorContent('card:document', 'Document', (id) => documentCard()),
      DoorContent('card:themes', 'Themes', (id) => themesCard()),
      DoorContent('card:settings', 'Settings', (id) => settingsCard()),
      for (final sub in settingsSubCards({...settings.keys, ...settings.shippedText.keys}))
        DoorContent(
          'card:settings:${sub.address}',
          sub.title,
          (id) => settingsCard(area: sub.address),
        ),
    ];
  }
}

/// What a card is editing, and the doors it can open from where it sits -- read
/// through the tree rather than plumbed through four widget constructors.
class CardHost extends InheritedWidget {
  const CardHost({
    super.key,
    required this.factory,
    required this.request,
    required this.tileId,
    required super.child,
  });

  final CardFactory factory;
  final CardRequest request;
  final String tileId;

  static CardHost of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CardHost>()!;

  /// The host, or null where a card is rendered outside one -- a spec pumping
  /// an instrument on its own, a preview. A door reads this: a card with no
  /// host has nowhere to open a card TO, and says nothing rather than throwing.
  static CardHost? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CardHost>();

  Editor get editor => factory.editor;

  /// Opens or focuses another record's card. THIS is what makes every far end
  /// of a connection navigable rather than a label you cannot follow.
  void openObject(String id) => factory.open(factory.objectCard(id));

  void openFrame(String id) => factory.open(factory.frameCard(id));

  /// Closing settles the draft; discarding is its own undo entry. Nothing asks
  /// first, here or anywhere.
  void close() => factory.stage.close(tileId);

  @override
  bool updateShouldNotify(CardHost old) => old.request != request || old.tileId != tileId;
}
