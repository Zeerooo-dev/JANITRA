"""Build separate on-device test APKs; never install over the user's JANITRA."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

if __name__ == '__main__':
    stage = Path(tempfile.mkdtemp(prefix='janitra-updater-smoke-'))
    shutil.copytree(ROOT, stage, dirs_exist_ok=True, ignore=shutil.ignore_patterns(
        '.git', '.dart_tool', 'build', 'backups', '.gradle', '.kotlin', '.idea', '.agents', '.codex', '.aws',
        'ephemeral', '.symlinks', 'Pods', 'node_modules', 'signing', 'key.properties', 'supabase.json', 'failures'))
    # The isolated build references the existing private key; it never includes it in the APK.
    shutil.copyfile(ROOT/'android/key.properties', stage/'android/key.properties')
    (stage/'android/key.properties').chmod(0o600)
    gradle = stage/'android/app/build.gradle.kts'
    gradle.write_text(gradle.read_text().replace('applicationId = "com.example.janitra"', 'applicationId = "com.example.janitra.updatertest"'))
    manifest = stage/'android/app/src/main/AndroidManifest.xml'
    manifest.write_text(manifest.read_text().replace('android:label="JANITRA"', 'android:label="JANITRA Updater Test"'))
    flutter = os.environ.get('JANITRA_FLUTTER', '/home/zero/development/flutter/bin/flutter')
    subprocess.run([flutter, 'pub', 'get', '--offline'], cwd=stage, check=True)
    base = [flutter, 'build', 'apk', '--release', '--no-pub']
    subprocess.run(base + ['--target=tool/updater_smoke_target.dart', '--build-name=1.1.0', '--build-number=27'], cwd=stage, check=True)
    fixtures = stage/'assets/updater-smoke'
    fixtures.mkdir()
    apk = stage/'build/app/outputs/flutter-apk/app-release.apk'
    shutil.copyfile(apk, fixtures/'valid.apk')
    digest = hashlib.file_digest((fixtures/'valid.apk').open('rb'), 'sha256').hexdigest()
    sdk = Path(os.environ.get('ANDROID_HOME', str(Path.home()/'Android/Sdk')))
    subprocess.run([str(sdk/'build-tools/36.0.0/apksigner'), 'sign', '--ks', str(Path.home()/'.android/debug.keystore'),
        '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', str(fixtures/'wrong-signer.apk'), str(fixtures/'valid.apk')], check=True)
    pubspec = stage/'pubspec.yaml'
    pubspec.write_text(pubspec.read_text().replace('  assets:\n', '  assets:\n    - assets/updater-smoke/valid.apk\n    - assets/updater-smoke/wrong-signer.apk\n'))
    subprocess.run([flutter, 'pub', 'get', '--offline'], cwd=stage, check=True)
    subprocess.run(base + ['--target=tool/updater_smoke.dart', '--build-name=1.0.0', '--build-number=26', '--dart-define=SMOKE_APK_SHA256='+digest], cwd=stage, check=True)
    output = ROOT/'build/updater-device-test'
    output.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(apk, output/'updater-test-host.apk')
    shutil.copyfile(fixtures/'valid.apk', output/'updater-test-target.apk')
    print('Isolated device fixtures:', output)
    print('Temporary build directory:', stage)
    print('Only install package com.example.janitra.updatertest; do not uninstall the real app.')
