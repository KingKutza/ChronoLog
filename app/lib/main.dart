import 'package:flutter/material.dart';

void main() => runApp(const ChronoLogApp());

class ChronoLogApp extends StatelessWidget {
  const ChronoLogApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    title: 'ChronoLog',
    home: Scaffold(body: Placeholder()),
  );
}
