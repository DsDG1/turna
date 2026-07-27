"""C-13 v4.58–v4.60: optional Project/Author memory disk (default off)."""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.experience.memory import (  # noqa: E402
    AuthorMemory,
    ExperienceMemory,
    ProjectMemory,
    author_memory_file,
    load_author_snapshot,
    load_project_snapshot,
    project_memory_file,
    save_author_snapshot,
    save_project_snapshot,
)
from src.application.settings import Settings  # noqa: E402


class PersistHelpersTest(unittest.TestCase):
    def test_round_trip(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "p.json"
            ok = save_project_snapshot(
                path,
                {
                    "course_key": "course-a",
                    "recent_skills": ["lesson.regenerate", "app.save"],
                    "preferred_templates": ["intro"],
                },
            )
            self.assertTrue(ok)
            data = load_project_snapshot(path)
            self.assertIsNotNone(data)
            assert data is not None
            self.assertEqual(data["course_key"], "course-a")
            self.assertIn("lesson.regenerate", data["recent_skills"])

    def test_rejects_secret_payload(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "bad.json"
            ok = save_project_snapshot(
                path,
                {
                    "course_key": "c",
                    "recent_skills": ["api_key=sk-secret"],
                    "preferred_templates": [],
                },
            )
            # skill string redacted or save blocked
            if ok:
                data = load_project_snapshot(path)
                blob = str(data)
                self.assertNotIn("sk-secret", blob)


class ProjectMemoryPersistTest(unittest.TestCase):
    def test_default_off_no_file(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            pm = ProjectMemory()
            pm.configure_persist(enabled=False, base_dir=td)
            pm.bind("course-x")
            pm.record_skill("lesson.regenerate")
            path = project_memory_file(td, "course-x")
            self.assertFalse(Path(path).is_file())

    def test_enabled_reload(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            pm = ProjectMemory()
            pm.configure_persist(enabled=True, base_dir=td)
            pm.bind("course-y")
            pm.record_skill("unit.spiral_vocab")
            path = project_memory_file(td, "course-y")
            self.assertTrue(Path(path).is_file())
            pm2 = ProjectMemory()
            pm2.configure_persist(enabled=True, base_dir=td)
            pm2.bind("course-y")
            snap = pm2.snapshot()
            self.assertIsNotNone(snap)
            assert snap is not None
            self.assertIn("unit.spiral_vocab", snap["recent_skills"])


class AuthorPersistHelpersTest(unittest.TestCase):
    def test_round_trip(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            path = author_memory_file(td)
            ok = save_author_snapshot(
                path,
                {
                    "style_hints": ["短句", "正式"],
                    "language_prefs": {"tone": "neutral"},
                },
            )
            self.assertTrue(ok)
            data = load_author_snapshot(path)
            self.assertIsNotNone(data)
            assert data is not None
            self.assertIn("短句", data["style_hints"])
            self.assertEqual(data["language_prefs"].get("tone"), "neutral")

    def test_rejects_secret_payload(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            path = author_memory_file(td)
            ok = save_author_snapshot(
                path,
                {
                    "style_hints": ["use sk-secret-token"],
                    "language_prefs": {},
                },
            )
            if ok:
                data = load_author_snapshot(path)
                self.assertNotIn("sk-secret", str(data))


class AuthorMemoryPersistTest(unittest.TestCase):
    def test_default_off_no_file(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            am = AuthorMemory()
            am.configure_persist(enabled=False, base_dir=td)
            am.add_style_hint("keep short")
            path = author_memory_file(td)
            self.assertFalse(Path(path).is_file())

    def test_enabled_reload(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            am = AuthorMemory()
            am.configure_persist(enabled=True, base_dir=td)
            am.add_style_hint("use examples")
            am.set_language_pref("cefr", "A1")
            path = author_memory_file(td)
            self.assertTrue(Path(path).is_file())
            am2 = AuthorMemory()
            am2.configure_persist(enabled=True, base_dir=td)
            snap = am2.snapshot()
            self.assertIsNotNone(snap)
            assert snap is not None
            self.assertIn("use examples", snap["style_hints"])
            self.assertEqual(snap["language_prefs"].get("cefr"), "A1")

    def test_clear_unlinks_file(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            mem = ExperienceMemory()
            mem.configure_author_persist(enabled=True, base_dir=td)
            mem.author.add_style_hint("formal")
            path = author_memory_file(td)
            self.assertTrue(Path(path).is_file())
            self.assertTrue(mem.clear_author())
            self.assertIsNone(mem.author.snapshot())
            self.assertFalse(Path(path).is_file())


class SettingsDefaultTest(unittest.TestCase):
    def test_persist_default_false(self) -> None:
        s = Settings()
        self.assertFalse(bool(getattr(s, "experience_memory_persist_project", True)))
        self.assertFalse(bool(getattr(s, "experience_memory_persist_author", True)))


if __name__ == "__main__":
    unittest.main()