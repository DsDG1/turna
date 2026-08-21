"""Tests for git_remote_catalog: saved remotes CRUD."""
from __future__ import annotations

import unittest
from unittest.mock import patch

from PySide6.QtCore import QSettings

from src.backend import git_remote_catalog
from src.backend.git_remote_catalog import SavedRemote


class SavedRemoteDataclassTest(unittest.TestCase):
    def test_to_dict_roundtrip(self) -> None:
        r = SavedRemote(name="myrepo", url="https://x.git", local_dir="/tmp/r", lang="tr")
        d = r.to_dict()
        r2 = SavedRemote.from_dict(d)
        self.assertEqual(r2.name, "myrepo")
        self.assertEqual(r2.url, "https://x.git")
        self.assertEqual(r2.local_dir, "/tmp/r")
        self.assertEqual(r2.lang, "tr")

    def test_from_dict_ignores_missing_fields(self) -> None:
        r = SavedRemote.from_dict({"name": "x", "url": "y"})
        self.assertEqual(r.name, "x")
        self.assertEqual(r.url, "y")
        self.assertEqual(r.local_dir, "")
        self.assertEqual(r.lang, "")


class RemoteCatalogCrudTest(unittest.TestCase):
    def setUp(self) -> None:
        QSettings.setDefaultFormat(QSettings.Format.IniFormat)
        QSettings.setPath(QSettings.Format.IniFormat, QSettings.Scope.UserScope, "/tmp/opencode/test-remotes")
        # Start clean.
        from src.backend import git_remote_catalog as grc
        grc.save_remotes([])

    def tearDown(self) -> None:
        from src.backend import git_remote_catalog as grc
        grc.save_remotes([])

    def test_add_and_load(self) -> None:
        r = SavedRemote(name="alpha", url="https://a.git", local_dir="/tmp/a", lang="tr")
        git_remote_catalog.add_remote(r)
        loaded = git_remote_catalog.load_remotes()
        self.assertEqual(len(loaded), 1)
        self.assertEqual(loaded[0].name, "alpha")

    def test_add_dedup_by_name(self) -> None:
        git_remote_catalog.add_remote(SavedRemote(name="beta", url="https://b1.git", local_dir="/d1"))
        git_remote_catalog.add_remote(SavedRemote(name="beta", url="https://b2.git", local_dir="/d2"))
        loaded = git_remote_catalog.load_remotes()
        self.assertEqual(len(loaded), 1)
        self.assertEqual(loaded[0].url, "https://b2.git")

    def test_remove(self) -> None:
        git_remote_catalog.add_remote(SavedRemote(name="gamma", url="https://g.git", local_dir="/g"))
        git_remote_catalog.remove_remote("gamma")
        self.assertEqual(len(git_remote_catalog.load_remotes()), 0)

    def test_update_fields(self) -> None:
        git_remote_catalog.add_remote(SavedRemote(name="delta", url="https://d.git", local_dir="/d", lang=""))
        git_remote_catalog.update_remote("delta", lang="en", local_dir="/new")
        loaded = git_remote_catalog.load_remotes()
        self.assertEqual(loaded[0].lang, "en")
        self.assertEqual(loaded[0].local_dir, "/new")

    def test_rename(self) -> None:
        git_remote_catalog.add_remote(SavedRemote(name="old", url="https://o.git", local_dir="/o"))
        git_remote_catalog.update_remote("old", new_name="new")
        loaded = git_remote_catalog.load_remotes()
        self.assertEqual(loaded[0].name, "new")

    def test_find_by_url(self) -> None:
        git_remote_catalog.add_remote(SavedRemote(name="zeta", url="https://z.git", local_dir="/z"))
        found = git_remote_catalog.find_by_url("https://z.git")
        self.assertIsNotNone(found)
        self.assertEqual(found.name, "zeta")
        self.assertIsNone(git_remote_catalog.find_by_url("https://nope.git"))

    def test_mark_synced_sets_timestamp(self) -> None:
        git_remote_catalog.add_remote(SavedRemote(name="eta", url="https://e.git", local_dir="/e"))
        self.assertEqual(git_remote_catalog.load_remotes()[0].last_synced_at, "")
        git_remote_catalog.mark_synced("eta")
        self.assertNotEqual(git_remote_catalog.load_remotes()[0].last_synced_at, "")

    def test_remotes_sorted_by_name(self) -> None:
        git_remote_catalog.add_remote(SavedRemote(name="zeta", url="https://z.git", local_dir="/z"))
        git_remote_catalog.add_remote(SavedRemote(name="alpha", url="https://a.git", local_dir="/a"))
        loaded = git_remote_catalog.load_remotes()
        self.assertEqual(loaded[0].name, "alpha")
        self.assertEqual(loaded[1].name, "zeta")


if __name__ == "__main__":
    unittest.main()
