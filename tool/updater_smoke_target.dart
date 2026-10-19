// Run only in the isolated package created by build_updater_smoke.py.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:janitra/core/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final directory = await getApplicationSupportDirectory();
  final file = File('${directory.path}/updater-smoke-state.txt');
  final state = await file.exists() ? await file.readAsString() : 'MISSING';
  runApp(
    MaterialApp(
      theme: janitraTheme(),
      home: Scaffold(
        appBar: AppBar(title: const Text('JANITRA Updater Test')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const JanitraLogo(),
              const SizedBox(height: 24),
              const Text('Update installed: 1.1.0+27'),
              Text('Saved state: $state'),
              const Text('Your real JANITRA installation was not changed.'),
            ],
          ),
        ),
      ),
    ),
  );
}
