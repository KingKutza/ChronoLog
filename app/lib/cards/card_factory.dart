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
import '../stage/tile.dart';
import 'card_chrome.dart';
import 'object_card.dart';

/// The numbers the object cards draw with, as expressions in the one math.
/// Disjoint by key from the frame cards' map, so one number has one home.
const Map<String, String> cardTunableDefaults = {
  'card.sigil': '15',
  'card.noteLines': '12',
  'card.pickerWidth': '150',
  'card.pickerHeight': '200',
  // Overscale: a typeahead never enumerates. It lists this many hits and
  // reports the rest as a lower bound, exactly as a truncated fact window does.
  'card.searchWindow': '12',
  'card.searchScan': '2000',
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

  TileSpec newFrameCard({String kind = 'calendar'}) =>
      _card('newFrame', 'New frame', kind: kind, nonce: createId('card'));

  TileSpec framesBrowser() => _card('frames', 'Frames');

  TileSpec documentCard() => _card('document', 'Document');

  TileSpec settingsCard() => _card('settings', 'Settings');

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
        child: body == null
            ? Padding(
                padding: EdgeInsets.all(cardPx(context, 'card.pad')),
                child: cardNote(context, 'The $title card has no registered body yet.'),
              )
            : body(context, request),
      ),
    );
  }

  void open(TileSpec spec) => stage.open(spec);
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
