// Pure Dart. Nothing under lib/core/ may import Flutter or a third-party
// package.
//
// RFC 5545's CONTENT-LINE layer, and nothing above it. This file knows about
// unfolding, the 75-BYTE fold, parameter quoting, text escaping and the
// BEGIN/END component tree; it knows nothing about what a VEVENT means. That is
// what lets the whole text half of the boundary be read -- and tested as
// involutions -- with no document anywhere in sight.
//
// THE FOLD IS COUNTED IN BYTES, not characters. RFC 5545 says octets, so a
// three-byte character straddling the limit moves whole to the next line rather
// than being split into an invalid UTF-8 sequence.

import 'dart:convert';

/// An ICS file this parser cannot read as a component tree.
///
/// STRUCTURE is refused; CONTENT never is. A property, a parameter or a value
/// nobody here models rides through verbatim, because it is somebody's data --
/// see `importIcs`, whose complaints are surfaced as warnings rather than thrown.
class IcsRefusal implements Exception {
  const IcsRefusal(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One parameter of a content line. Multi-valued, because RFC 5545 writes
/// `;MEMBER="a","b"` and keeping only the first would lose data.
class IcsParam {
  const IcsParam(this.name, this.values);

  final String name;
  final List<String> values;
}

/// One content line.
///
/// A line with NO COLON AT ALL is not a property: there is no name and value to
/// rebuild it from, so it keeps [raw] and rides back out exactly as written. A
/// malformed marker in somebody's calendar is theirs, and dropping it or
/// inventing a colon for it would both be edits nobody authored.
class IcsProperty {
  const IcsProperty(this.name, {this.params = const [], this.value = '', this.raw});

  final String name;
  final List<IcsParam> params;
  final String value;
  final String? raw;

  bool get verbatim => raw != null;

  /// The first value of the parameter [name], or null -- an absent parameter and
  /// one written empty say the same nothing. Names are matched upper-cased
  /// because RFC 5545 says parameter names are case-insensitive.
  String? param(String name) {
    final upper = name.toUpperCase();
    for (final item in params) {
      if (item.name != upper) continue;
      final first = item.values.isEmpty ? '' : item.values.first;
      return first.isEmpty ? null : first;
    }
    return null;
  }
}

/// A component: its name, its own properties in file order, and its children in
/// file order. Order is data -- it is what a byte-identical re-export rests on.
class IcsComponent {
  IcsComponent(this.name, {List<IcsProperty>? properties, List<IcsComponent>? components})
    : properties = properties ?? <IcsProperty>[],
      components = components ?? <IcsComponent>[];

  final String name;
  final List<IcsProperty> properties;
  final List<IcsComponent> components;
}

/// Splits on [separator] except inside a quoted string. The quote characters
/// themselves stay in the parts; [stripQuotes] takes them off a whole value, so
/// a value that merely CONTAINS a quote keeps it.
List<String> splitOutsideQuotes(String value, String separator) {
  final parts = <String>[];
  final current = StringBuffer();
  var quoted = false;
  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    if (char == '"') quoted = !quoted;
    if (char == separator && !quoted) {
      parts.add(current.toString());
      current.clear();
    } else {
      current.write(char);
    }
  }
  parts.add(current.toString());
  return parts;
}

String stripQuotes(String value) =>
    value.length >= 2 && value.startsWith('"') && value.endsWith('"')
    ? value.substring(1, value.length - 1)
    : value;

int _colonIndex(String line) {
  var quoted = false;
  for (var index = 0; index < line.length; index += 1) {
    if (line[index] == '"') quoted = !quoted;
    if (line[index] == ':' && !quoted) return index;
  }
  return -1;
}

final RegExp _folded = RegExp(r'\n[ \t]');

/// Line folding undone, and both line endings normalised to `\n`. A CRLF file
/// and an LF file are the same file.
String unfoldIcs(String text) =>
    text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').replaceAll(_folded, '');

IcsParam _param(String piece) {
  final equals = piece.indexOf('=');
  if (equals < 0) return IcsParam(piece.toUpperCase(), const ['']);
  return IcsParam(piece.substring(0, equals).toUpperCase(), [
    for (final value in splitOutsideQuotes(piece.substring(equals + 1), ',')) stripQuotes(value),
  ]);
}

IcsProperty parseContentLine(String line) {
  final colon = _colonIndex(line);
  if (colon < 0) return IcsProperty(line.toUpperCase(), raw: line);
  final pieces = splitOutsideQuotes(line.substring(0, colon), ';');
  return IcsProperty(
    pieces.first.toUpperCase(),
    params: [for (final piece in pieces.skip(1)) _param(piece)],
    value: line.substring(colon + 1),
  );
}

/// The whole file as one tree under a synthetic `ROOT`. A BEGIN with no matching
/// END, or an END naming something else, is a refusal: the nesting is the only
/// thing here that cannot be preserved by not understanding it.
IcsComponent parseIcsTree(String text) {
  final root = IcsComponent('ROOT');
  final stack = <IcsComponent>[root];
  for (final line in unfoldIcs(text).split('\n')) {
    if (line.isEmpty) continue;
    final property = parseContentLine(line);
    if (property.name == 'BEGIN') {
      final component = IcsComponent(property.value.toUpperCase());
      stack.last.components.add(component);
      stack.add(component);
    } else if (property.name == 'END') {
      if (stack.length == 1 || stack.last.name != property.value.toUpperCase()) {
        throw IcsRefusal('Mismatched END:${property.value}');
      }
      stack.removeLast();
    } else {
      stack.last.properties.add(property);
    }
  }
  if (stack.length != 1) throw IcsRefusal('Unclosed ${stack.last.name}');
  return root;
}

/// One component, parsed from its own serialized text. This is the whole of how
/// a retained residual comes back: it is STORED AS ICS TEXT, so the store needs
/// no second representation of a component and no deep copy on the way out.
IcsComponent? parseIcsComponent(String? text) {
  if (text == null || text.isEmpty) return null;
  final components = parseIcsTree(text).components;
  return components.isEmpty ? null : components.first;
}

List<IcsProperty> propertiesNamed(IcsComponent component, String name) => [
  for (final property in component.properties)
    if (property.name == name.toUpperCase()) property,
];

IcsProperty? propertyNamed(IcsComponent component, String name) {
  for (final property in component.properties) {
    if (property.name == name.toUpperCase()) return property;
  }
  return null;
}

String? propertyText(IcsComponent component, String name) => propertyNamed(component, name)?.value;

/// The four escapes RFC 5545 defines for TEXT values, undone in ONE pass -- a
/// second pass would turn an authored `\\n` into a newline, which is how a
/// Windows path in a DESCRIPTION comes back mangled.
String unescapeIcsText(String value) => value.replaceAllMapped(
  _escaped,
  (match) => match[1] == 'n' || match[1] == 'N' ? '\n' : match[1]!,
);

final RegExp _escaped = RegExp(r'\\([\\;,nN])');

/// The inverse of [unescapeIcsText] over any text it can produce. The backslash
/// goes first, or every escape this then writes would be escaped again.
String escapeIcsText(String value) => value
    .replaceAll('\\', '\\\\')
    .replaceAll('\n', '\\n')
    .replaceAll(',', '\\,')
    .replaceAll(';', '\\;');

final RegExp _needsQuoting = RegExp('[;:,]');

/// A parameter value is quoted only when it holds a character the grammar reads
/// as punctuation -- so a value that never needed quotes comes back out without
/// them, which is what keeps a re-export byte-identical.
String _paramValue(String value) => _needsQuoting.hasMatch(value) ? '"$value"' : value;

String serializeParams(List<IcsParam> params) =>
    [for (final item in params) ';${item.name}=${item.values.map(_paramValue).join(',')}'].join();

/// RFC 5545's fold: at most 75 OCTETS per line, continuations opening with one
/// space -- which itself counts toward the octets, hence 74 for every line after
/// the first. Characters are never split, so the fold cannot produce invalid
/// UTF-8 no matter where the limit lands inside a multi-byte character.
String foldLine(String line) {
  if (utf8.encode(line).length <= 75) return line;
  final chunks = <String>[];
  var current = StringBuffer();
  var bytes = 0;
  for (final rune in line.runes) {
    final char = String.fromCharCode(rune);
    final length = utf8.encode(char).length;
    if (bytes + length > (chunks.isEmpty ? 75 : 74)) {
      chunks.add(current.toString());
      current = StringBuffer(char);
      bytes = length;
    } else {
      current.write(char);
      bytes += length;
    }
  }
  if (current.isNotEmpty) chunks.add(current.toString());
  return [for (final (index, chunk) in chunks.indexed) index == 0 ? chunk : ' $chunk'].join('\r\n');
}

String serializeComponent(IcsComponent component) => [
  'BEGIN:${component.name}',
  for (final item in component.properties)
    foldLine(
      item.verbatim ? item.raw! : '${item.name}${serializeParams(item.params)}:${item.value}',
    ),
  for (final child in component.components) serializeComponent(child),
  'END:${component.name}',
].join('\r\n');

/// Replaces the FIRST property of this name, in place, or appends when there is
/// none. In place is the whole point: a retained original's own property order
/// is what a byte-identical re-export rests on, and a remove-then-append would
/// shuffle every regenerated property to the end.
void setProperty(
  IcsComponent component,
  String name,
  String value, [
  List<IcsParam> params = const [],
]) {
  final next = IcsProperty(name, params: params, value: value);
  final index = component.properties.indexWhere((item) => item.name == name);
  if (index < 0) {
    component.properties.add(next);
  } else {
    component.properties[index] = next;
  }
}

void removeProperty(IcsComponent component, String name) =>
    component.properties.removeWhere((item) => item.name == name);
