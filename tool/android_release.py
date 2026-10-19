"""Prepare signed release artifacts without publishing anything."""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def release_version(tag, pubspec):
    match = re.search(r"^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$", pubspec, re.M)
    if not match or not re.fullmatch(r"v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)", tag):
        raise ValueError("Use a stable vMAJOR.MINOR.PATCH tag and a numeric pubspec build number")
    if tag != "v" + match[1] or int(match[2]) < 1:
        raise ValueError("Tag must match pubspec.yaml; increment the build number for every release")
    return match[1], int(match[2])


def configure():
    required = ["ANDROID_KEYSTORE_BASE64", "ANDROID_KEYSTORE_PASSWORD", "ANDROID_KEY_ALIAS",
                "ANDROID_KEY_PASSWORD", "SUPABASE_URL", "SUPABASE_PUBLISHABLE_KEY"]
    if any(not os.environ.get(name) for name in required):
        raise ValueError("Required GitHub Actions secrets are missing")
    folder = ROOT / "config/signing"
    folder.mkdir(mode=0o700, parents=True, exist_ok=True)
    keystore = folder / "release.jks"
    keystore.write_bytes(base64.b64decode(os.environ["ANDROID_KEYSTORE_BASE64"], validate=True))
    keystore.chmod(0o600)
    # Properties values are generated secrets, so reject separators rather than misparse them.
    values = {"storeFile": str(keystore), "storePassword": os.environ["ANDROID_KEYSTORE_PASSWORD"],
              "keyAlias": os.environ["ANDROID_KEY_ALIAS"], "keyPassword": os.environ["ANDROID_KEY_PASSWORD"]}
    if any(re.search(r"[\r\n\\]", value) for value in values.values()):
        raise ValueError("Unsupported signing property value")
    properties = ROOT / "android/key.properties"
    properties.write_text("".join(f"{key}={value}\n" for key, value in values.items()))
    properties.chmod(0o600)
    config = ROOT / "config/supabase.json"
    config.write_text(json.dumps({name: os.environ[name] for name in required[-2:]}))
    config.chmod(0o600)


def package(version, code):
    sdk = Path(os.environ.get("ANDROID_HOME") or os.environ["ANDROID_SDK_ROOT"])
    tools = sdk / "build-tools/36.0.0"
    apk = ROOT / "build/app/outputs/flutter-apk/app-release.apk"
    verification = subprocess.check_output([str(tools / "apksigner"), "verify", "--print-certs", str(apk)], text=True)
    if "Android Debug" in verification:
        raise ValueError("Refusing a debug-signed release")
    badging = subprocess.check_output([str(tools / "aapt"), "dump", "badging", str(apk)], text=True)
    expected = f"package: name='com.example.janitra' versionCode='{code}' versionName='{version}'"
    if expected not in badging:
        raise ValueError("APK package/version differs from the approved source version")
    notes = ROOT / f"docs/releases/v{version}.md"
    if not notes.is_file():
        raise ValueError("Release notes must exist before packaging")
    target = ROOT / "build/release"
    target.mkdir(parents=True, exist_ok=True)
    output = target / "janitra.apk"
    shutil.copyfile(apk, output)
    digest = hashlib.file_digest(output.open("rb"), "sha256").hexdigest()
    (target / "SHA256SUMS").write_text(f"{digest}  janitra.apk\n")
    (target / "release-info.json").write_text(json.dumps({"package": "com.example.janitra", "version": version,
        "versionCode": code, "sha256": digest, "bytes": output.stat().st_size}, indent=2) + "\n")
    shutil.copyfile(notes, target / "CHANGES.md")
    print(verification.strip())
    print(f"Verified {version}+{code}; review artifacts are ready. No release was published.")


if __name__ == "__main__":
    version, code = release_version(os.environ.get("RELEASE_TAG", ""), (ROOT / "pubspec.yaml").read_text())
    if sys.argv[1:] == ["configure"]:
        configure()
    elif sys.argv[1:] == ["package"]:
        package(version, code)
    else:
        raise SystemExit("Use configure or package")
