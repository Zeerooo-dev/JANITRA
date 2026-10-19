"""Fail before upload if tracked source contains private credentials or local data."""
import base64
import json
from pathlib import Path
import re
import subprocess


if __name__ == '__main__':
    files = subprocess.check_output(['git', 'ls-files', '-z']).decode().split('\0')
    patterns = [r'sbp_[A-Za-z0-9]{30,}', r'sb_secret_[A-Za-z0-9_-]{20,}',
                r'gh[pousr]_[A-Za-z0-9]{25,}', r'github_pat_[A-Za-z0-9_]{30,}',
                r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----']
    excluded = re.compile(r'(^|/)(\.aws|\.codex|\.agents|backups|build|\.dart_tool|\.gradle|\.kotlin|\.env[^/]*)(/|$)|'
                          r'(^|/)(key\.properties|local\.properties)$|\.(jks|keystore|apk|aab|db|sqlite3?|dump|p12|pfx)$|'
                          r'^config/(signing/|supabase\.json$)|^supabase/\.temp/')
    failures = []
    for name in filter(None, files):
        path = Path(name)
        if excluded.search(name):
            failures.append(name)
            continue
        data = path.read_bytes().decode('utf-8', errors='replace')
        if any(re.search(pattern, data) for pattern in patterns):
            failures.append(name)
        for token in re.findall(r'eyJ[A-Za-z0-9_-]+\.([A-Za-z0-9_-]+)\.[A-Za-z0-9_-]+', data):
            try:
                claims = json.loads(base64.urlsafe_b64decode(token + '=' * (-len(token) % 4)))
                if claims.get('role') == 'service_role':
                    failures.append(name)
            except (ValueError, UnicodeError):
                continue
    if failures:
        raise SystemExit('Refusing upload; inspect these files without printing their secrets: ' + ', '.join(sorted(set(failures))))
    print(f'Source credential/exclusion check passed for {len(list(filter(None, files)))} tracked files.')
