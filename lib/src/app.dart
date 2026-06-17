import 'package:cairn/src/shell/app_shell.dart';
import 'package:flutter/material.dart';

/// Root widget for the Cairn application.
class CairnApp extends StatelessWidget {
  /// Creates the root Cairn application widget.
  const CairnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cairn',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const AppShell(),
    );
  }
}
