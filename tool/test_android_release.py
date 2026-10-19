import unittest
from android_release import release_version


class ReleaseVersionTest(unittest.TestCase):
    def test_valid_version(self):
        self.assertEqual(release_version("v1.10.0", "version: 1.10.0+27\n"), ("1.10.0", 27))

    def test_rejects_mismatched_or_unstable_tag_and_missing_counter(self):
        for tag, version in [("v1.1.0", "1.0.0+26"), ("v1.0.0-rc.1", "1.0.0+26"),
                             ("v01.0.0", "1.0.0+26"), ("v1.0.0", "1.0.0"),
                             ("v1.0.0", "1.0.0+0"), ("v1.0.0\nmalicious", "1.0.0+26")]:
            with self.subTest(tag=tag, version=version), self.assertRaises(ValueError):
                release_version(tag, "version: " + version)


if __name__ == "__main__":
    unittest.main()
