import copy
import json
import unittest

from build_privacy_policy import ROOT, render


class PolicyTest(unittest.TestCase):
    def setUp(self):
        self.policy = json.loads((ROOT / 'assets/privacy/policy.json').read_text())

    def test_public_page_matches_app_and_has_no_scripts_or_external_assets(self):
        page = render(self.policy)
        self.assertEqual(page, (ROOT / 'docs/privacy/index.html').read_text())
        self.assertIn('lang="en"', page)
        self.assertIn('mailto:jeffirie12@gmail.com', page)
        self.assertIn('prefers-color-scheme:dark', page)
        self.assertNotIn('<script', page)
        self.assertNotIn('<iframe', page)
        self.assertNotIn('[Date', page)

    def test_rejects_incomplete_publication_metadata(self):
        for key in ('operator', 'privacyEmail', 'effectiveDate', 'updatedDate'):
            for value in (None, '', '[Not decided]'):
                changed = copy.deepcopy(self.policy)
                changed[key] = value
                with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                    render(changed)

    def test_escapes_policy_text(self):
        self.policy['sections'][0]['paragraphs'] = ['<script>alert("x")</script>']
        page = render(self.policy)
        self.assertNotIn('<script>', page)
        self.assertIn('&lt;script&gt;', page)


if __name__ == '__main__':
    unittest.main()
