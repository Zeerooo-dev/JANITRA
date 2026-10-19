"""One-time Android 9+ bridge from JANITRA's local debug key to its production key.

This never installs or publishes the APK and never uploads the legacy private key.
"""
import argparse
import os
from pathlib import Path
import subprocess


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    values = dict(line.split('=', 1) for line in (root/'android/key.properties').read_text().splitlines() if '=' in line)
    env = os.environ.copy()
    env.update(JANITRA_STORE_PASSWORD=values['storePassword'], JANITRA_KEY_PASSWORD=values['keyPassword'])
    sdk = Path(os.environ.get('ANDROID_HOME', str(Path.home()/'Android/Sdk')))
    signer = str(sdk/'build-tools/36.0.0/apksigner')
    lineage = root/'config/signing/legacy-production.lineage'
    if not lineage.exists():
        subprocess.run([signer, 'rotate', '--out', str(lineage), '--old-signer', '--ks', str(Path.home()/'.android/debug.keystore'),
            '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--set-rollback', 'false',
            '--new-signer', '--ks', values['storeFile'], '--ks-key-alias', values['keyAlias'],
            '--ks-pass', 'env:JANITRA_STORE_PASSWORD', '--key-pass', 'env:JANITRA_KEY_PASSWORD'], env=env, check=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([signer, 'sign', '--ks', values['storeFile'], '--ks-key-alias', values['keyAlias'],
        '--ks-pass', 'env:JANITRA_STORE_PASSWORD', '--key-pass', 'env:JANITRA_KEY_PASSWORD',
        '--lineage', str(lineage), '--rotation-min-sdk-version', '28', '--min-sdk-version', '28',
        '--v1-signing-enabled', 'false', '--v2-signing-enabled', 'false', '--v3-signing-enabled', 'true',
        '--v4-signing-enabled', 'false', '--out', str(args.output), str(args.apk)], env=env, check=True)
    subprocess.run([signer, 'verify', '--min-sdk-version', '28', '--print-certs', str(args.output)], check=True)
    print('Android 9+ transition APK prepared. Android 7/8 require a separate reinstall; do not uninstall automatically.')
