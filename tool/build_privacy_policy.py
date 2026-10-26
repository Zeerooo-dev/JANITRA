"""Generate the public HTML from the app's bundled policy; never deploy it."""
import argparse
import datetime
import html
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def render(data):
    for key in ('application', 'operator', 'effectiveDate', 'updatedDate'):
        value = data.get(key)
        if not isinstance(value, str) or not value.strip() or '[' in value or ']' in value:
            raise ValueError(f'Complete policy publication field: {key}')
    for field in ('effectiveDate', 'updatedDate'):
        datetime.date.fromisoformat(data[field])
    if not data.get('sections'):
        raise ValueError('Policy sections are required')
    esc = html.escape
    parts = []
    for section in data['sections']:
        parts.append(f'<section><h2>{esc(section["title"])}</h2>')
        for paragraph in section.get('paragraphs', []):
            parts.append(f'<p>{esc(paragraph)}</p>')
        if section.get('bullets'):
            parts.append('<ul>' + ''.join(f'<li>{esc(text)}</li>' for text in section['bullets']) + '</ul>')
        parts.append('</section>')
    return f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light dark">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
<title>JANITRA Privacy Policy</title>
<style>
:root{{color-scheme:light dark;--bg:#f6f8fb;--surface:#fff;--ink:#202c39;--accent:#234e70}}
*{{box-sizing:border-box}}body{{margin:0;background:var(--bg);color:var(--ink);font:1rem/1.65 system-ui,sans-serif}}
main{{max-width:52rem;margin:0 auto;padding:clamp(1rem,4vw,2.5rem);overflow-wrap:anywhere}}
h1{{font-size:clamp(1.7rem,5vw,2.4rem);line-height:1.2}}h2{{font-size:1.25rem;line-height:1.35;margin-top:2rem}}
header{{border-bottom:2px solid var(--accent);padding-bottom:1rem}}li{{margin:.7rem 0}}a{{color:var(--accent);text-underline-offset:.2em}}
a:focus-visible{{outline:3px solid var(--accent);outline-offset:4px}}nav{{margin-top:2rem}}footer{{margin-top:2rem;border-top:1px solid var(--accent);padding-top:1rem}}
@media(prefers-color-scheme:dark){{:root{{--bg:#10161f;--surface:#1b222c;--ink:#edf2f8;--accent:#b4d5ed}}}}
@media(forced-colors:active){{header,footer{{border-color:CanvasText}}}}
@media print{{body{{background:white;color:black}}main{{max-width:none}}}}
</style></head><body><main id="top"><header>
<h1>JANITRA Privacy Policy</h1>
<p>Effective date: <time datetime="{esc(data['effectiveDate'])}">{esc(data['effectiveDate'])}</time><br>
Last updated: <time datetime="{esc(data['updatedDate'])}">{esc(data['updatedDate'])}</time></p>
<p>Developer / operator: {esc(data['operator'])}</p>
</header>{''.join(parts)}
<footer><p>Provider information: <a href="https://supabase.com/privacy">Supabase</a>,
<a href="https://policies.google.com/privacy">Google</a>,
<a href="https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement">GitHub</a>.</p>
<p>Philippine privacy rights: <a href="https://privacy.gov.ph/data-subject-rights/">National Privacy Commission</a>.</p>
<a href="#top">Back to top</a></footer></main></body></html>
'''


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    data = json.loads((ROOT / 'assets/privacy/policy.json').read_text())
    output = ROOT / 'docs/privacy/index.html'
    content = render(data)
    if args.check:
        if not output.is_file() or output.read_text() != content:
            raise SystemExit('Public policy differs from bundled policy; run tool/build_privacy_policy.py')
        print('Policy dates/operator are valid and public HTML matches the bundled app policy. Contact/retention readiness is tracked in the verification report.')
    else:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(content)
        print('Generated docs/privacy/index.html. Nothing was published.')
