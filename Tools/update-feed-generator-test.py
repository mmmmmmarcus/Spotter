import copy
import importlib.util
import pathlib
import unittest

spec = importlib.util.spec_from_file_location("generator", pathlib.Path(__file__).resolve().parents[1] / "scripts/generate-update-feed.py")
generator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generator)


def release(version="1.7.16", draft=False, prerelease=False):
    tag = "v" + version
    return {"tag_name": tag, "draft": draft, "prerelease": prerelease,
            "html_url": f"{generator.BASE}/tag/{tag}", "body": "  - A fix.  ",
            "assets": [{"name": f"Spotter-{version}.{suffix}", "state": "uploaded", "size": 100,
                        "browser_download_url": f"{generator.BASE}/download/{tag}/Spotter-{version}.{suffix}"}
                       for suffix in ("zip", "dmg")]}


class FeedTests(unittest.TestCase):
    def test_numeric_order_and_drafts(self):
        result = generator.manifests([release("1.7.9"), release(), release("1.8.0", draft=True)])
        self.assertEqual(result["stable"]["releases"][0]["version"], "1.7.16")
        self.assertEqual(len(result["stable"]["releases"]), 2)
        self.assertEqual(result["beta"]["releases"], [])

    def test_channels(self):
        result = generator.manifests([release(), release("1.8.0-beta.1", prerelease=True)])
        self.assertEqual(result["beta"]["releases"][0]["version"], "1.8.0-beta.1")
        self.assertEqual(result["stable"]["releases"][0]["releaseNotes"], "- A fix.")

    def test_incomplete_newest_must_fail(self):
        newest = release("1.8.0")
        newest["assets"].pop()
        with self.assertRaises(ValueError):
            generator.manifests([newest, release()])

    def test_untrusted_assets_must_fail(self):
        for value in ("https://example.com/evil.zip", "http://github.com/evil", "https://github.com/other/repo"):
            item = release()
            item["assets"][0]["browser_download_url"] = value
            with self.assertRaises(ValueError):
                generator.manifests([item])

    def test_upload_not_complete(self):
        for changes in ({"size": 0}, {"state": "new"}):
            item = release()
            item["assets"][0].update(changes)
            with self.assertRaises(ValueError):
                generator.manifests([item])

    def test_expected_release_required(self):
        generator.manifests([release()], expected="v1.7.16")
        with self.assertRaises(ValueError):
            generator.manifests([release()], expected="v1.7.17")

    def test_no_secret_fields_exported(self):
        item = release()
        item["author"] = {"token": "must-not-be-exported"}
        import json
        self.assertNotIn("must-not-be-exported", json.dumps(generator.manifests([item])))

    def test_channel_tag_mismatch(self):
        with self.assertRaises(ValueError):
            generator.manifests([release(prerelease=True)])

    def test_missing_stable(self):
        with self.assertRaises(ValueError):
            generator.manifests([])

    def test_duplicate_asset(self):
        item = release()
        item["assets"].append(copy.deepcopy(item["assets"][0]))
        with self.assertRaises(ValueError):
            generator.manifests([item])


if __name__ == "__main__":
    unittest.main()
