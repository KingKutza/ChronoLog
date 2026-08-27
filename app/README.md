# chronolog

The Flutter application. Targets windows, linux, android.

`lib/core/` is pure Dart: no Flutter imports, and no third-party dependency that
reaches a host API. The record types annotate themselves with
`freezed_annotation`, which is annotations only.
Its spec lives in `test/core/` and runs on the Dart VM under `dart test`.

Widget and platform code lives outside `lib/core/` and is tested with
`flutter test`.

## Generated code

`freezed` generates the record types' `==`, `hashCode`, `copyWith` and sealed
subclasses. After editing any file that declares a `part '*.freezed.dart'`:

    dart run build_runner build

`*.freezed.dart` files are BUILD PRODUCTS. They are committed to the tree so a
clean checkout analyzes and tests without a generation step, they are never
edited by hand, and **they are outside the hand-written line budget** — the
codegen ruling counts what a person wrote, not what the builder emitted.

JSON codecs are hand-written, not generated. The document file is the truth, so a
record must preserve fields this build has never heard of, keep them in file
order, and answer null rather than throw when a field is the wrong shape — none
of which a JSON generator does. There is one codec style, and it is visible.
