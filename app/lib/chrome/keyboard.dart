// One keyboard map for the whole surface. Every binding is a SETTING, so a key
// the user wants elsewhere is a line in `chronolog.settings`, not a recompile.
//
// Bindings read as `ctrl+shift+arrowleft`: modifiers first, then one key named
// by its logical name (a letter, a digit, or one of the named keys below).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/exact.dart';
import '../stage/layout_tree.dart';
import 'controls.dart';
import 'menus.dart';
import 'view_bar.dart';

/// The shipped bindings, as text settings rather than tunables: a chord is not
/// arithmetic.
const Map<String, String> chromeKeyDefaults = {
  'keys.undo': 'ctrl+z',
  'keys.redo': 'ctrl+y',
  'keys.save': 'ctrl+s',
  'keys.newView': 'n',
  'keys.closeTile': 'ctrl+w',
  'keys.tabTile': 'ctrl+t',
  'keys.zoomTile': 'ctrl+m',
  'keys.focusLeft': 'alt+arrowleft',
  'keys.focusRight': 'alt+arrowright',
  'keys.focusUp': 'alt+arrowup',
  'keys.focusDown': 'alt+arrowdown',
  'keys.moveLeft': 'ctrl+shift+arrowleft',
  'keys.moveRight': 'ctrl+shift+arrowright',
  'keys.moveUp': 'ctrl+shift+arrowup',
  'keys.moveDown': 'ctrl+shift+arrowdown',
  'keys.panBack': 'arrowleft',
  'keys.panForward': 'arrowright',
  'keys.zoomIn': 'equal',
  'keys.zoomOut': 'minus',
  'keys.delete': 'delete',
  'keys.escape': 'escape',
  'keys.lensDigits': '123456789',
  // MODIFIERS ONLY, because it is a state the hand HOLDS rather than a key it
  // strikes: while it is down every drag bar on the stage is visible, a drag
  // carries its whole collinear run, and a click locks or unlocks that run
  // (ISSUES 9.1, Don's ruling on dividers).
  'keys.alignSeams': 'ctrl',
};

/// Is a modifiers-only chord held right now? A chord naming no modifier is
/// never held -- an empty setting turns the mode off rather than leaving it
/// always on.
bool chordHeld(String binding) {
  final parts = binding.toLowerCase().split('+').where((part) => part.isNotEmpty).toSet();
  if (parts.isEmpty) return false;
  final keys = HardwareKeyboard.instance;
  const held = {
    'ctrl': _isControl,
    'shift': _isShift,
    'alt': _isAlt,
    'meta': _isMeta,
  };
  for (final part in parts) {
    final reads = held[part];
    if (reads == null || !reads(keys)) return false;
  }
  return true;
}

bool _isControl(HardwareKeyboard keys) => keys.isControlPressed;
bool _isShift(HardwareKeyboard keys) => keys.isShiftPressed;
bool _isAlt(HardwareKeyboard keys) => keys.isAltPressed;
bool _isMeta(HardwareKeyboard keys) => keys.isMetaPressed;

const Map<String, LogicalKeyboardKey> _named = {
  'arrowleft': LogicalKeyboardKey.arrowLeft,
  'arrowright': LogicalKeyboardKey.arrowRight,
  'arrowup': LogicalKeyboardKey.arrowUp,
  'arrowdown': LogicalKeyboardKey.arrowDown,
  'delete': LogicalKeyboardKey.delete,
  'escape': LogicalKeyboardKey.escape,
  'equal': LogicalKeyboardKey.equal,
  'minus': LogicalKeyboardKey.minus,
  'tab': LogicalKeyboardKey.tab,
  'enter': LogicalKeyboardKey.enter,
  'space': LogicalKeyboardKey.space,
};

/// A binding string to an activator, or null when nothing names a key.
SingleActivator? activatorFor(String binding) {
  final parts = binding.toLowerCase().split('+').where((part) => part.isNotEmpty).toList();
  if (parts.isEmpty) return null;
  final name = parts.removeLast();
  final key = _named[name] ?? (name.length == 1 ? LogicalKeyboardKey(name.codeUnitAt(0)) : null);
  if (key == null) return null;
  return SingleActivator(
    key,
    control: parts.contains('ctrl'),
    shift: parts.contains('shift'),
    alt: parts.contains('alt'),
    meta: parts.contains('meta'),
  );
}

class ChromeIntent extends Intent {
  const ChromeIntent(this.action);

  final String action;
}

/// Is a field taking keystrokes right now? ONE guard at the dispatcher rather
/// than a condition on every binding: a bare key belongs to whatever is being
/// typed into (Don, 2026-08-28: "I cannot type numbers in the names of events,
/// like '5-min test'"). A chord carrying a modifier cannot be typed at all, so
/// it still fires.
bool typingNow() {
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null) return false;
  return focused.widget is EditableText ||
      focused.findAncestorWidgetOfExactType<EditableText>() != null;
}

/// The binding text an action fires on. The lens digits are ONE setting holding
/// several keys, so every `lensN` reads the same line; nothing else has to know
/// that.
String bindingOf(Chrome chrome, String action) =>
    chrome.settings.text(action.startsWith('lens') ? 'keys.lensDigits' : 'keys.$action');

/// A chord carries a modifier, so a person typing cannot produce it by accident.
bool isChord(String binding) => binding.contains('+');

/// THE ONE GUARD, AT THE ONE DISPATCHER.
///
/// Declining inside the callback was the defect: a `Shortcuts` map that MATCHES
/// a key consumes the event whether or not the action then does anything, so
/// the character never reached the field (Don, 8.28: "I cannot type numbers in
/// the names of events"; recurred 8.31 on the document name box). An action
/// that is not ENABLED is never invoked and the event is left unhandled, which
/// is the difference between "the chrome chose not to act" and "the chrome
/// never had a claim on this key".
///
/// So: while a field is taking keystrokes, this action is disabled for every
/// bare binding and enabled for every chord. One condition, one place, every
/// binding -- present and future -- covered by it.
class ChromeAction extends Action<ChromeIntent> {
  ChromeAction(this.chrome, this.run);

  final Chrome chrome;
  final Object? Function(Chrome chrome, String action) run;

  @override
  bool isEnabled(ChromeIntent intent) =>
      !typingNow() || isChord(bindingOf(chrome, intent.action));

  @override
  Object? invoke(ChromeIntent intent) => run(chrome, intent.action);
}

/// Wraps the surface in the one map. Nothing below binds a key of its own.
class ChromeKeyboard extends StatelessWidget {
  const ChromeKeyboard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeScope.of(context);
    final shortcuts = <ShortcutActivator, Intent>{};
    for (final key in chromeKeyDefaults.keys) {
      if (key == 'keys.lensDigits') continue;
      // NEVER LAST-WINS (ISSUES 9.2). Two bindings naming one chord used to
      // land in this map one after the other and the second quietly took it;
      // whichever way that fell, one of the two rows on the keyboard page was
      // lying. A contested chord binds NEITHER, and the settings layer says so
      // in prose beside both rows.
      final activator = activatorFor(chrome.settings.binding(key));
      if (activator != null) shortcuts[activator] = ChromeIntent(key.substring('keys.'.length));
    }
    final digits = chrome.settings.text('keys.lensDigits');
    for (final (index, digit) in digits.split('').indexed) {
      final activator = activatorFor(digit);
      if (activator != null) shortcuts[activator] = ChromeIntent('lens$index');
    }
    return Shortcuts(
      shortcuts: shortcuts,
      child: Actions(
        actions: {ChromeIntent: ChromeAction(chrome, _run)},
        // A SCOPE, not a bare focus node: when a field lets go of the keyboard
        // the focus has to land back INSIDE this dispatcher, or the surface
        // would be left with the shortcuts above the primary focus and every
        // bare binding silently dead until something else was clicked.
        child: FocusScope(autofocus: true, child: child),
      ),
    );
  }

  /// What a binding does once [ChromeAction] has let it through. The typing
  /// guard is NOT repeated here: it lives in exactly one place, on the action,
  /// where declining also means not consuming.
  Object? _run(Chrome chrome, String action) {
    final stage = chrome.stage;
    final focused = stage.focusedId;
    final view = stage.focusedViewTile;
    if (action.startsWith('lens')) {
      final index = int.tryParse(action.substring(4)) ?? -1;
      final lenses = chrome.views.visibleLenses;
      if (view != null && index >= 0 && index < lenses.length) {
        stage.swapLens(view, lenses[index]);
      }
      return null;
    }
    switch (action) {
      case 'undo':
        chrome.editor?.undo();
      case 'redo':
        chrome.editor?.redo();
      case 'save':
        chrome.editor?.store.save(force: true);
      case 'newView':
        openViewTile(chrome);
      case 'closeTile':
        // No confirmation: reversibility over interruption.
        if (focused != null) stage.close(focused);
      case 'tabTile':
        _tab(chrome, focused);
      case 'zoomTile':
        if (focused != null) stage.toggleZoom(focused);
      case 'escape':
        closeOpenMenu();
      case 'delete' || 'zoomIn' || 'zoomOut':
        if (view != null) chrome.onAction?.call(view, action);
      case 'panBack' || 'panForward':
        _pan(chrome, view, action == 'panForward');
      default:
        _stageMove(chrome, action);
    }
    return null;
  }

  void _stageMove(Chrome chrome, String action) {
    const directions = {'Left': 'left', 'Right': 'right', 'Up': 'up', 'Down': 'down'};
    for (final entry in directions.entries) {
      if (action == 'focus${entry.key}') chrome.stage.focusDirection(entry.value);
      if (action == 'move${entry.key}') chrome.stage.moveDirection(entry.value);
    }
  }

  /// Tab and untab are one key: a tabbed tile comes out, a lone tile joins its
  /// nearest neighbour.
  void _tab(Chrome chrome, String? focused) {
    if (focused == null) return;
    final parent = parentOf(chrome.stage.root, focused);
    if (parent?.mode == 'tabs') {
      chrome.stage.split(focused, 'row');
      return;
    }
    final neighbour =
        directionalNeighbor(chrome.stage.root, focused, 'right') ??
        directionalNeighbor(chrome.stage.root, focused, 'left');
    if (neighbour != null) chrome.stage.tabUnder(focused, neighbour);
  }

  /// One of the lens's own span units, under the primary frame's law.
  void _pan(Chrome chrome, String? view, bool forward) {
    if (view == null) return;
    final state = chrome.views.of(view);
    final primary = state.projection().primaryFrame;
    final law = primary == null ? null : chrome.editor?.engine.lawOf(primary);
    final step = law?.meanUnitDays(state.spec.spanUnit) ?? Rational.one;
    chrome.views.setFocus(view, chrome.views.focusOf(view) + (forward ? step : -step));
  }
}
