import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:janitra/features/updates/apk_updater.dart';
import 'package:janitra/features/updates/release_version.dart';

import 'support/update_fixtures.dart';

void main() {
  test('semantic ordering handles numbers, prereleases and build metadata', () {
    final versions = [
      '1.0.0-alpha',
      '1.0.0-alpha.1',
      '1.0.0-alpha.beta',
      '1.0.0-beta',
      '1.0.0-beta.2',
      '1.0.0-beta.11',
      '1.0.0-rc.1',
      '1.0.0',
      '1.1.0',
      '1.2.0',
      '1.10.0',
      '2.0.0',
    ];
    for (var i = 1; i < versions.length; i++) {
      expect(
        ReleaseVersion.parse(versions[i])
            .compareTo(ReleaseVersion.parse(versions[i - 1])),
        greaterThan(0),
      );
    }
    expect(
      ReleaseVersion.parse('v1.0.0+26')
          .compareTo(ReleaseVersion.parse('1.0.0+27')),
      0,
    );
    expect(
      ReleaseVersion.parse('1.0.0-9999999999999999999999999')
          .compareTo(ReleaseVersion.parse('1.0.0-beta')),
      lessThan(0),
    );
    for (final invalid in [
      '1.0',
      'v01.0.0',
      '1.0.0-01',
      '1.0.0-',
      '1.0.0 ',
      '1.0.0+',
    ]) {
      expect(() => ReleaseVersion.parse(invalid), throwsFormatException);
    }
  });

  late Directory temp;
  late FakeUpdatePlatform platform;
  late ApkUpdater updater;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('janitra-updater-test');
    platform = FakeUpdatePlatform(temp.path);
    updater = ApkUpdater(
      repository: updateRepository,
      platform: platform,
      client: MockClient((_) async => http.Response('[]', 200)),
    );
  });
  tearDown(() async {
    updater.dispose();
    await temp.delete(recursive: true);
  });

  test('selects newest semantic stable release and actual notes', () async {
    updater = ApkUpdater(
      repository: updateRepository,
      platform: platform,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode([
            releaseJson('1.2.0'),
            releaseJson('1.10.0'),
            releaseJson('3.0.0', draft: true),
            releaseJson('2.0.0-beta', prerelease: true),
            releaseJson('1.0.0'),
          ]),
          200,
        ),
      ),
    );
    final release = (await updater.check())!;
    expect(release.version.name, '1.10.0');
    expect(release.notes, 'Notes for 1.10.0');
  });

  test('ignores missing-hash, duplicate-asset, malformed and foreign releases', () async {
    final noHash = releaseJson('1.1.0');
    (noHash['assets'] as List).single['digest'] = null;
    final foreign = releaseJson('1.2.0');
    (foreign['assets'] as List).single['browser_download_url'] =
        'https://github.com/evil/janitra/releases/download/v1.2.0/janitra.apk';
    final duplicate = releaseJson('1.3.0');
    (duplicate['assets'] as List).add((duplicate['assets'] as List).single);
    updater = ApkUpdater(
      repository: updateRepository,
      platform: platform,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode([
            noHash,
            foreign,
            duplicate,
            releaseJson('invalid'),
            releaseJson('0.9.0'),
          ]),
          200,
        ),
      ),
    );
    expect(await updater.check(), isNull);
  });

  test('concurrent checks share one request', () async {
    var count = 0;
    final response = Completer<http.Response>();
    updater = ApkUpdater(
      repository: updateRepository,
      platform: platform,
      client: MockClient((_) {
        count++;
        return response.future;
      }),
    );
    final a = updater.check();
    final b = updater.check();
    response.complete(http.Response(jsonEncode([releaseJson('1.1.0')]), 200));
    expect(await a, same(await b));
    expect(count, 1);
  });

  test('offline and rate-limit failures remain updater errors', () async {
    updater = ApkUpdater(
      repository: updateRepository,
      platform: platform,
      client: MockClient((_) async => throw const SocketException('offline')),
    );
    await expectLater(updater.check(), throwsA(isA<SocketException>()));
    updater.dispose();
    updater = ApkUpdater(
      repository: updateRepository,
      platform: platform,
      client: MockClient((_) async => http.Response('', 403)),
    );
    await expectLater(updater.check(), throwsA(isA<UpdateFailure>()));
    expect(platform.installed, 0);
  });

  test('no published release is a quiet no-update result', () async {
    updater = ApkUpdater(
      repository: updateRepository,
      platform: platform,
      client: MockClient((_) async => http.Response('', 404)),
    );
    expect(await updater.check(), isNull);
  });

  test('streams real progress and verifies before returning APK', () async {
    updater = ApkUpdater(
      repository: updateRepository,
      platform: platform,
      client: MockClient.streaming(
        (_, _) async => http.StreamedResponse(
          Stream.fromIterable([
            [1, 2],
            [3, 4],
          ]),
          200,
          contentLength: 4,
        ),
      ),
    );
    final progress = <int>[];
    final path = await updater.download(testRelease, (bytes, total) {
      progress.add(bytes);
      expect(total, 4);
    });
    expect(progress, [0, 2, 4]);
    expect(await File(path).readAsBytes(), [1, 2, 3, 4]);
    expect(platform.verified, 1);
    expect(platform.installed, 0);
    expect(temp.listSync().where((f) => f.path.endsWith('.part')), isEmpty);
  });

  test('insufficient storage prevents download', () async {
    platform.freeBytes = 1;
    var requests = 0;
    updater = ApkUpdater(
      repository: updateRepository,
      platform: platform,
      client: MockClient((_) async {
        requests++;
        return http.Response('', 200);
      }),
    );
    await expectLater(
      updater.download(testRelease, (_, _) {}),
      throwsA(isA<UpdateFailure>()),
    );
    expect(requests, 0);
    expect(platform.verified, 0);
  });

  for (final bytes in [
    [1, 2],
    [1, 2, 3, 4, 5],
  ]) {
    test(
      'discards incomplete or oversized download (${bytes.length} bytes)',
      () async {
        updater = ApkUpdater(
          repository: updateRepository,
          platform: platform,
          client: MockClient.streaming(
            (_, _) async => http.StreamedResponse(Stream.value(bytes), 200),
          ),
        );
        await expectLater(
          updater.download(testRelease, (_, _) {}),
          throwsA(isA<UpdateFailure>()),
        );
        expect(temp.listSync(), isEmpty);
        expect(platform.verified, 0);
      },
    );
  }

  test(
    'verification failure removes APK and cannot launch installer',
    () async {
      platform.reject = true;
      updater = ApkUpdater(
        repository: updateRepository,
        platform: platform,
        client: MockClient((_) async => http.Response.bytes([1, 2, 3, 4], 200)),
      );
      await expectLater(
        updater.download(testRelease, (_, _) {}),
        throwsA(isA<PlatformException>()),
      );
      expect(temp.listSync(), isEmpty);
      expect(platform.installed, 0);
    },
  );

  test('foreign and insecure redirects are rejected', () async {
    for (final location in [
      'https://evil.example/janitra.apk',
      'http://github.com/janitra.apk',
      'https://user:pass@github.com/janitra.apk',
    ]) {
      updater = ApkUpdater(
        repository: updateRepository,
        platform: platform,
        client: MockClient(
          (_) async => http.Response('', 302, headers: {'location': location}),
        ),
      );
      await expectLater(
        updater.download(testRelease, (_, _) {}),
        throwsA(isA<UpdateFailure>()),
      );
      expect(platform.verified, 0);
      updater.dispose();
    }
  });

  test('GitHub storage redirects are followed securely', () async {
    var requests = 0;
    updater = ApkUpdater(
      repository: updateRepository,
      platform: platform,
      client: MockClient((request) async {
        requests++;
        expect(request.followRedirects, isFalse);
        return request.url.host == 'github.com'
            ? http.Response(
                '',
                302,
                headers: {
                  'location':
                      'https://release-assets.githubusercontent.com/asset.apk',
                },
              )
            : http.Response.bytes([1, 2, 3, 4], 200);
      }),
    );
    await updater.download(testRelease, (_, _) {});
    expect(requests, 2);
    expect(platform.verified, 1);
  });

  test('concurrent download cannot overwrite APK under verification', () async {
    platform.verification = Completer<void>();
    updater = ApkUpdater(
      repository: updateRepository,
      platform: platform,
      client: MockClient((_) async => http.Response.bytes([1, 2, 3, 4], 200)),
    );
    final first = updater.download(testRelease, (_, _) {});
    await expectLater(
      updater.download(testRelease, (_, _) {}),
      throwsA(isA<UpdateFailure>()),
    );
    platform.verification!.complete();
    await first;
    expect(platform.verified, 1);
  });
}
