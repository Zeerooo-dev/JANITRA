import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'release_version.dart';

class UpdateFailure implements Exception {
  const UpdateFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class InstalledApp {
  const InstalledApp({
    required this.version,
    required this.directory,
    required this.freeBytes,
    this.buildNumber,
  });
  final String version;
  final String directory;
  final int freeBytes;
  final String? buildNumber;
}

class AppRelease {
  const AppRelease({
    required this.version,
    required this.notes,
    required this.url,
    required this.sha256,
    required this.size,
  });
  final ReleaseVersion version;
  final String notes;
  final Uri url;
  final String sha256;
  final int size;
}

abstract class UpdatePlatform {
  Future<InstalledApp> installedApp();
  Future<void> verify(String path, AppRelease release);
  Future<bool> canInstall();
  Future<void> requestInstallPermission();
  Future<void> install(String path, AppRelease release);
}

class AndroidUpdatePlatform implements UpdatePlatform {
  static const channel = MethodChannel('janitra/updates');

  @override
  Future<InstalledApp> installedApp() async {
    final info = (await channel.invokeMapMethod<String, dynamic>('info'))!;
    return InstalledApp(
      version: info['version'] as String,
      directory: info['directory'] as String,
      freeBytes: info['freeBytes'] as int,
      buildNumber: info['buildNumber'] as String?,
    );
  }

  Map<String, Object> _arguments(String path, AppRelease release) => {
    'path': path,
    'sha256': release.sha256,
    'size': release.size,
    'version': release.version.name,
  };

  @override
  Future<void> verify(String path, AppRelease release) =>
      channel.invokeMethod<void>('verify', _arguments(path, release));

  @override
  Future<bool> canInstall() async =>
      await channel.invokeMethod<bool>('canInstall') ?? false;

  @override
  Future<void> requestInstallPermission() =>
      channel.invokeMethod<void>('permission');

  @override
  Future<void> install(String path, AppRelease release) =>
      channel.invokeMethod<void>('install', _arguments(path, release));
}

class ApkUpdater {
  ApkUpdater({
    required this.repository,
    required this.platform,
    http.Client? client,
  }) : _client =
           client ??
           IOClient(
             HttpClient()..connectionTimeout = const Duration(seconds: 15),
           ) {
    if (!RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(repository)) {
      throw ArgumentError.value(repository, 'repository');
    }
  }

  final String repository;
  final UpdatePlatform platform;
  final http.Client _client;
  Future<AppRelease?>? _checking;
  bool _downloading = false;
  static const maxApkSize = 512 * 1024 * 1024;
  static const reserveBytes = 128 * 1024 * 1024;

  void dispose() => _client.close();

  Future<void> rememberPermission(String path, AppRelease release) async {
    final app = await platform.installedApp();
    await File('${app.directory}/pending-install.json').writeAsString(
      jsonEncode({
        'repository': repository,
        'path': path,
        'version': release.version.name,
        'notes': release.notes,
        'url': release.url.toString(),
        'sha256': release.sha256,
        'size': release.size,
        'created': DateTime.now().millisecondsSinceEpoch,
      }),
      flush: true,
    );
  }

  Future<void> clearPendingPermission() async {
    try {
      final app = await platform.installedApp();
      final file = File('${app.directory}/pending-install.json');
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Restored downloads always require a new explicit Install update action.
    }
  }

  Future<(AppRelease, String)?> restorePendingPermission() async {
    try {
      final app = await platform.installedApp();
      final file = File('${app.directory}/pending-install.json');
      if (!await file.exists()) return null;
      if (await file.length() > 128 * 1024) {
        throw const FormatException('Oversized pending record');
      }
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final age =
          DateTime.now().millisecondsSinceEpoch - (data['created'] as int);
      final version = ReleaseVersion.parse(data['version'] as String);
      final path = data['path'] as String;
      final url = Uri.parse(data['url'] as String);
      final digest = data['sha256'] as String;
      final size = data['size'] as int;
      if (data['repository'] != repository ||
          age < 0 ||
          age > const Duration(minutes: 30).inMilliseconds ||
          version.preRelease.isNotEmpty ||
          version.compareTo(ReleaseVersion.parse(app.version)) <= 0 ||
          File(path).parent.path != app.directory ||
          !RegExp(r'^[0-9]+\.apk$')
              .hasMatch(path.split(Platform.pathSeparator).last) ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest) ||
          size <= 0 ||
          size > maxApkSize ||
          url.scheme != 'https' ||
          url.host != 'github.com' ||
          url.port != 443 ||
          url.userInfo.isNotEmpty ||
          url.hasQuery ||
          url.hasFragment ||
          ![
            '/$repository/releases/download/v${version.name}/janitra.apk',
            '/$repository/releases/download/${version.name}/janitra.apk',
          ].contains(url.path)) {
        throw const FormatException('Stale or invalid pending update');
      }
      final release = AppRelease(
        version: version,
        notes: data['notes'] as String,
        url: url,
        sha256: digest,
        size: size,
      );
      await platform.verify(path, release);
      return (release, path);
    } catch (_) {
      await clearPendingPermission();
      return null;
    }
  }

  Future<AppRelease?> check() =>
      _checking ??= _check().whenComplete(() => _checking = null);

  Future<AppRelease?> _check() async {
    final installed = ReleaseVersion.parse(
      (await platform.installedApp()).version,
    );
    final response = await _get(
      Uri.https('api.github.com', '/repos/$repository/releases', {
        'per_page': '100',
      }),
      api: true,
    );
    if (response.statusCode == 404) {
      await response.stream.listen(null).cancel();
      return null;
    }
    if (response.statusCode != 200) {
      await response.stream.listen(null).cancel();
      throw const UpdateFailure(
        'Updates could not be checked. Try again later.',
      );
    }
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 20),
    )) {
      if (bytes.length + chunk.length > 1024 * 1024) {
        throw const UpdateFailure('The update response is too large.');
      }
      bytes.addAll(chunk);
    }
    final releases = jsonDecode(utf8.decode(bytes));
    if (releases is! List) throw const FormatException('Invalid releases');
    AppRelease? newest;
    for (final entry in releases) {
      if (entry is! Map ||
          entry['draft'] != false ||
          entry['prerelease'] != false) {
        continue;
      }
      try {
        final version = ReleaseVersion.parse(entry['tag_name'] as String);
        if (version.preRelease.isNotEmpty ||
            version.compareTo(installed) <= 0) {
          continue;
        }
        final assets = entry['assets'] as List;
        final candidates = assets
            .whereType<Map>()
            .where((a) => a['name'] == 'janitra.apk')
            .toList();
        if (candidates.length != 1) continue;
        final asset = candidates.single;
        final digest = asset['digest'] as String;
        final size = asset['size'] as int;
        final url = Uri.parse(asset['browser_download_url'] as String);
        if (!RegExp(r'^sha256:[0-9a-fA-F]{64}$').hasMatch(digest) ||
            size <= 0 ||
            size > maxApkSize ||
            url.scheme != 'https' ||
            url.host != 'github.com' ||
            url.userInfo.isNotEmpty ||
            url.port != 443 ||
            url.path !=
                '/$repository/releases/download/${entry['tag_name']}/janitra.apk' ||
            url.hasQuery ||
            url.hasFragment) {
          continue;
        }
        final rawNotes = entry['body'] as String? ?? '';
        final notes = rawNotes.length > 16000
            ? '${rawNotes.substring(0, 16000)}\n…'
            : rawNotes;
        final release = AppRelease(
          version: version,
          notes: notes,
          url: url,
          sha256: digest.substring(7).toLowerCase(),
          size: size,
        );
        if (newest == null || version.compareTo(newest.version) > 0) {
          newest = release;
        }
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      }
    }
    return newest;
  }

  Future<http.StreamedResponse> _get(Uri uri, {bool api = false}) async {
    for (var redirects = 0; redirects <= 5; redirects++) {
      if (uri.scheme != 'https' ||
          uri.userInfo.isNotEmpty ||
          uri.port != 443 ||
          !{
            'api.github.com',
            'github.com',
            'release-assets.githubusercontent.com',
            'objects.githubusercontent.com',
          }.contains(uri.host)) {
        throw const UpdateFailure(
          'The download address could not be verified.',
        );
      }
      final abort = Completer<void>();
      final deadline = Timer(
        api ? const Duration(seconds: 45) : const Duration(minutes: 10),
        () {
          if (!abort.isCompleted) abort.complete();
        },
      );
      final request = http.AbortableRequest(
        'GET',
        uri,
        abortTrigger: abort.future,
      )..followRedirects = false;
      request.headers['User-Agent'] = 'JANITRA-Android-Updater';
      request.headers['Accept'] = api
          ? 'application/vnd.github+json'
          : 'application/octet-stream';
      late http.StreamedResponse original;
      try {
        original = await _client
            .send(request)
            .timeout(const Duration(seconds: 20));
      } catch (_) {
        deadline.cancel();
        if (!abort.isCompleted) abort.complete();
        rethrow;
      }
      void finish() {
        deadline.cancel();
        if (!abort.isCompleted) abort.complete();
      }

      final body = Stream<List<int>>.multi((controller) {
        final subscription = original.stream
            .timeout(const Duration(seconds: 25))
            .listen(
              controller.addSync,
              onError: controller.addErrorSync,
              onDone: () {
                finish();
                controller.closeSync();
              },
            );
        controller.onCancel = () {
          finish();
          return subscription.cancel();
        };
      });
      final response = http.StreamedResponse(
        body,
        original.statusCode,
        contentLength: original.contentLength,
        headers: original.headers,
        request: original.request,
      );
      if (![301, 302, 303, 307, 308].contains(response.statusCode)) {
        return response;
      }
      final location = response.headers['location'];
      await response.stream.listen(null).cancel();
      if (location == null) break;
      uri = uri.resolve(location);
    }
    throw const UpdateFailure(
      'Too many redirects while downloading the update.',
    );
  }

  Future<String> download(
    AppRelease release,
    void Function(int received, int total) progress, {
    void Function()? verifying,
  }) async {
    if (_downloading) {
      throw const UpdateFailure('An update is already downloading.');
    }
    _downloading = true;
    File? partial;
    File? apk;
    RandomAccessFile? output;
    var success = false;
    try {
      await clearPendingPermission();
      final app = await platform.installedApp();
      if (app.freeBytes < release.size * 3 + reserveBytes) {
        throw const UpdateFailure(
          'Not enough storage. Free some space and try again.',
        );
      }
      final directory = await Directory(app.directory).create(recursive: true);
      // Only updater cache files are removed; workspace data and sessions are never touched.
      await for (final file in directory.list()) {
        if (file is File &&
            (file.path.endsWith('.part') || file.path.endsWith('.apk'))) {
          await file.delete();
        }
      }
      final name = '${directory.path}/${DateTime.now().microsecondsSinceEpoch}';
      partial = File('$name.part');
      apk = File('$name.apk');
      final response = await _get(release.url);
      if (response.statusCode != 200 ||
          (response.contentLength != null &&
              response.contentLength != release.size)) {
        await response.stream.listen(null).cancel();
        throw const UpdateFailure(
          'The update download is unavailable. Try again later.',
        );
      }
      output = await partial.open(mode: FileMode.write);
      var received = 0;
      final elapsed = Stopwatch()..start();
      progress(0, release.size);
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 25),
      )) {
        received += chunk.length;
        if (received > release.size ||
            elapsed.elapsed > const Duration(minutes: 10)) {
          throw const UpdateFailure(
            'The download could not be completed safely. Try again.',
          );
        }
        await output.writeFrom(chunk);
        progress(received, release.size);
      }
      await output.flush();
      await output.close();
      output = null;
      if (received != release.size) {
        throw const UpdateFailure('The download was interrupted. Try again.');
      }
      await partial.rename(apk.path);
      verifying?.call();
      await platform.verify(apk.path, release);
      success = true;
      return apk.path;
    } on FileSystemException catch (error) {
      if (error.osError?.errorCode == 28) {
        throw const UpdateFailure(
          'Not enough storage. Free some space and try again.',
        );
      }
      throw const UpdateFailure(
        'The update could not be saved. Check available storage.',
      );
    } finally {
      try {
        await output?.close();
      } catch (_) {
        /* Preserve the original failure. */
      }
      for (final file in [partial, if (!success) apk]) {
        try {
          if (file != null && await file.exists()) await file.delete();
        } catch (_) {
          /* Cache cleanup is retried on the next download. */
        }
      }
      _downloading = false;
    }
  }
}
