# Public Privacy Policy hosting

The app bundles `assets/privacy/policy.json`. Generate this directory's read-only HTML from that same source:

```sh
python3 tool/build_privacy_policy.py
python3 tool/build_privacy_policy.py --check
python3 tool/test_privacy_policy.py
```

The generator rejects missing contact/operator/date fields and unfinished metadata placeholders. It escapes policy text and adds no scripts, analytics, external fonts, images, forms or login requirement. The page follows the browser's light/dark setting and supports small screens and zoom. A public email link is provided for privacy/account-deletion requests.

## Free GitHub Pages option (not activated)

After the operator reviews the verification report and approves publication, push the reviewed source and choose **Settings → Pages → Deploy from a branch → main → /docs** in the public `Zeerooo-dev/JANITRA` repository. The expected policy URL is:

`https://zeerooo-dev.github.io/JANITRA/privacy/`

This URL is only a proposed hosting location until Pages is enabled and the page returns successfully without authentication. Check it in a signed-out browser, including mobile and light/dark modes, before placing it in Play Console. Only the `index.html` file is needed if a separate Pages site is preferred. No backend or credentials are needed.

The current contact is published with the operator's permission: `jeffirie12@gmail.com`. Effective and last-updated dates are `2026-10-27`; confirm/update them when the policy actually takes effect. The app copy updates with an APK; regenerate the HTML whenever the bundled policy changes.

See `docs/PRIVACY-VERIFICATION-2026-10-27.md` for unresolved retention, controller and account-erasure questions. A prepared policy page does not itself establish Google Play compliance, implement a deletion-request workflow, or change the database's retention behavior. No hosting setting was changed for this implementation.
