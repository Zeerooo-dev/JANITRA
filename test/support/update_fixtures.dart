import 'dart:async';

import 'package:flutter/services.dart';
import 'package:janitra/features/updates/apk_updater.dart';
import 'package:janitra/features/updates/release_version.dart';

class FakeUpdatePlatform implements UpdatePlatform {
  FakeUpdatePlatform(this.directory);
  final String directory;
  int freeBytes = 1024 * 1024 * 1024;
  int verified = 0;
  int installed = 0;
  int settings = 0;
  bool allowed = true;
  bool reject = false;
  Completer<void>? verification;
  @override
  Future<InstalledApp> installedApp() async => InstalledApp(
    version: '1.0.0',
    directory: directory,
    freeBytes: freeBytes,
  );
  @override
  Future<void> verify(String path, AppRelease release) async {
    verified++;
    if (reject) throw PlatformException(code: 'verification');
    await verification?.future;
  }

  @override
  Future<bool> canInstall() async => allowed;
  @override
  Future<void> requestInstallPermission() async {
    settings++;
  }

  @override
  Future<void> install(String path, AppRelease release) async {
    installed++;
  }
}

const updateRepository = 'test/janitra';
final testRelease = AppRelease(
  version: ReleaseVersion.parse('1.1.0'),
  notes: 'Improved schedules and approvals.',
  url: Uri.https(
    'github.com',
    '/$updateRepository/releases/download/v1.1.0/janitra.apk',
  ),
  sha256: '0' * 64,
  size: 4,
);

Map<String, dynamic> releaseJson(
  String version, {
  bool draft = false,
  bool prerelease = false,
}) => {
  'tag_name': 'v$version',
  'draft': draft,
  'prerelease': prerelease,
  'body': 'Notes for $version',
  'assets': [
    <String, dynamic>{
      'name': 'janitra.apk',
      'digest': 'sha256:${'0' * 64}',
      'size': 4,
      'browser_download_url':
          'https://github.com/$updateRepository/releases/download/v$version/janitra.apk',
    },
  ],
};
