// The entry point, and nothing else. What the program IS lives in `app.dart`,
// where every seam is a parameter and a spec stands the whole thing up in
// memory; a main that assembled anything would be an assembly no test runs.

import 'package:flutter/widgets.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ChronoLogApp());
}
