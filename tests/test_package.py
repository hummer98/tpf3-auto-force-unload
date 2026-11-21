"""Tests for tools/package.py: python3 -m unittest discover -s tests"""
import os
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "..", "tools"))
import package  # noqa: E402


def write(path, text=""):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


class PackageTest(unittest.TestCase):
    # README, LICENSE, docs/, tests/ and tools/ stay in the repository; the
    # game's validation rejects LICENSE (no allowed extension), so pin what
    # the zip may contain
    def test_release_holds_only_the_mod_files(self):
        names = [name for _, name in package.files_to_pack()]
        for want in ("mod.json", "strings.json", "_metadata/modinfo.json",
                     "_metadata/0.png",
                     "content/gui/hummer_force_unload_default/fud.script.lua",
                     "content/gui/hummer_force_unload_default/fud_core.lua"):
            self.assertIn(want, names)
        for name in names:
            self.assertTrue(name in ("mod.json", "strings.json")
                            or name.startswith(("content/", "_metadata/")),
                            name)

    def test_cover_and_metadata_are_packed_backups_are_not(self):
        with tempfile.TemporaryDirectory() as root:
            for rel in ("mod.json", "strings.json", "content/a.lua",
                        "content/a.lua~", "content/.b.swp",
                        "_metadata/modinfo.json", "_metadata/0.png",
                        "docs/x.md", "LICENSE", "README.md"):
                write(os.path.join(root, rel))
            with mock.patch.object(package, "ROOT", root):
                names = sorted(name for _, name in package.files_to_pack())
        self.assertEqual(names, ["_metadata/0.png", "_metadata/modinfo.json",
                                 "content/a.lua", "mod.json", "strings.json"])

    def test_missing_cover_stops_before_the_tests_run(self):
        # the in-game uploader refuses a mod without a cover
        with tempfile.TemporaryDirectory() as root:
            for rel in ("mod.json", "strings.json", "_metadata/modinfo.json"):
                write(os.path.join(root, rel), "{}")
            with mock.patch.object(package, "ROOT", root), \
                    mock.patch.object(package.subprocess, "run") as run:
                with self.assertRaises(SystemExit) as cm:
                    package.preflight()
            run.assert_not_called()
        self.assertIn("0.png", str(cm.exception.code))


if __name__ == "__main__":
    unittest.main()
