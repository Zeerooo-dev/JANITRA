// Test fixtures replace HTTP only; verification, permission and installer calls are real.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:janitra/core/app_theme.dart';
import 'package:janitra/features/updates/apk_updater.dart';
import 'package:janitra/features/updates/release_version.dart';
import 'package:janitra/features/updates/update_prompt.dart';

const repository = 'Zeerooo-dev/JANITRA';
const expectedHash = String.fromEnvironment('SMOKE_APK_SHA256');
final platform = AndroidUpdatePlatform();
late Uint8List fixture;
late AppRelease release;
late ApkUpdater updater;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final directory = await getApplicationSupportDirectory();
  await File('${directory.path}/updater-smoke-state.txt')
      .writeAsString('Team tab 2 preserved');
  fixture = (await rootBundle.load('assets/updater-smoke/valid.apk')).buffer
      .asUint8List();
  release = AppRelease(
    version: ReleaseVersion.parse('1.1.0'),
    notes: 'Physical-device test fixture.\nTests download progress, APK verification, Android permission and native installation.\nNo public release was published.',
    url: Uri.https(
      'github.com',
      '/$repository/releases/download/v1.1.0/janitra.apk',
    ),
    sha256: expectedHash,
    size: fixture.length,
  );
  updater = ApkUpdater(
    repository: repository,
    platform: platform,
    client: MockClient.streaming((request, _) async {
      if (request.url.host == 'api.github.com') {
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(
              jsonEncode([
                {
                  'tag_name': 'v1.1.0',
                  'draft': false,
                  'prerelease': false,
                  'body': release.notes,
                  'assets': [
                    {
                      'name': 'janitra.apk',
                      'digest': 'sha256:$expectedHash',
                      'size': fixture.length,
                      'browser_download_url': release.url.toString(),
                    },
                  ],
                },
              ]),
            ),
          ),
          200,
        );
      }
      Stream<List<int>> chunks() async* {
        for (var offset = 0; offset < fixture.length; offset += 262144) {
          await Future<void>.delayed(const Duration(milliseconds: 35));
          yield Uint8List.sublistView(
            fixture,
            offset,
            (offset + 262144).clamp(0, fixture.length),
          );
        }
      }

      return http.StreamedResponse(
        chunks(),
        200,
        contentLength: fixture.length,
      );
    }),
  );
  runApp(const SmokeApp());
}

class SmokeApp extends StatefulWidget {
  const SmokeApp({super.key});
  @override
  State<SmokeApp> createState() => _SmokeAppState();
}

class _SmokeAppState extends State<SmokeApp> {
  final navigator = GlobalKey<NavigatorState>();
  String result = 'Team tab 2 preserved';

  Future<void> checks() async {
    setState(() => result = 'Checking native security…');
    try {
      final app = await platform.installedApp();
      final file = File('${app.directory}/123456789.apk');
      await file.writeAsBytes(fixture);
      await platform.verify(file.path, release);
      var rejected = 0;
      Future<void> reject(AppRelease candidate) async {
        try {
          await platform.verify(file.path, candidate);
          throw StateError('Unsafe fixture was accepted');
        } on PlatformException catch (error) {
          if (error.code != 'verification') rethrow;
          rejected++;
        }
      }

      AppRelease candidate({String? hash, String? version, int? size}) =>
          AppRelease(
            version: ReleaseVersion.parse(version ?? '1.1.0'),
            notes: '',
            url: release.url,
            sha256: hash ?? expectedHash,
            size: size ?? fixture.length,
          );
      await reject(candidate(hash: '0' * 64));
      await reject(candidate(version: '1.2.0'));
      await reject(candidate(size: fixture.length - 1));
      await file.delete();
      final changed = Uint8List.fromList(fixture)..[1024] ^= 1;
      await file.writeAsBytes(changed);
      final tamperedHash = (await Sha256().hash(changed)).bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      await reject(candidate(hash: tamperedHash));
      await file.delete();
      final wrongSigner = (await rootBundle.load(
        'assets/updater-smoke/wrong-signer.apk',
      )).buffer.asUint8List();
      await file.writeAsBytes(wrongSigner);
      final wrongHash = (await Sha256().hash(wrongSigner)).bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      await reject(candidate(hash: wrongHash, size: wrongSigner.length));
      await file.delete();
      final online = ApkUpdater(repository: repository, platform: platform);
      try {
        await online.check();
      } finally {
        online.dispose();
      }
      if (mounted) {
        setState(
          () => result =
              'PASS: valid APK accepted; $rejected unsafe APK checks rejected; real GitHub check completed.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => result = 'FAIL: ${error.runtimeType}: $error');
      }
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: navigator,
    theme: janitraTheme(),
    builder: (_, child) => UpdatePromptHost(
      navigatorKey: navigator,
      updater: updater,
      child: child!,
    ),
    home: Scaffold(
      appBar: AppBar(title: const Text('JANITRA Updater Test')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Builder(
          builder: (context) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const JanitraLogo(size: 64),
              const SizedBox(height: 20),
              const Text('Isolated test package; no Supabase account is used.'),
              const SizedBox(height: 16),
              Text(result),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: checks,
                child: const Text('Run safety checks'),
              ),
              TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) =>
                      UpdateDialog(updater: updater, release: release),
                ),
                child: const Text('Show update'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
