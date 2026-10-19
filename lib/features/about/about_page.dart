import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../updates/apk_updater.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  late final _app = AndroidUpdatePlatform().installedApp();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('About JANITRA')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Center(child: JanitraLogo()),
        const SizedBox(height: 20),
        Text(
          'JANITRA',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Janitorial workforce management',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        FutureBuilder<InstalledApp>(
          future: _app,
          builder: (context, snapshot) {
            final app = snapshot.data;
            return Text(
              app != null
                  ? 'Version ${app.version}${app.buildNumber == null ? '' : ' (Build ${app.buildNumber})'}'
                  : snapshot.hasError
                  ? 'Version information unavailable'
                  : 'Loading version…',
              textAlign: TextAlign.center,
            );
          },
        ),
        const SizedBox(height: 24),
        Card(
          child: ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Third-party licenses'),
            subtitle: const Text('Open-source libraries and bundled fonts'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'JANITRA',
              applicationIcon: const JanitraLogo(size: 48),
            ),
          ),
        ),
      ],
    ),
  );
}
