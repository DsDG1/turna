"""Pack prefixing, builtin registration, and course-local media paths."""
from __future__ import annotations

import contextlib
import io
import json
import sys
import tempfile
import unittest
import zipfile
from argparse import Namespace
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
_TOOL = _GUI.parent
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))
if str(_TOOL) not in sys.path:
    sys.path.insert(0, str(_TOOL))

import course_cli

from src.backend.course_delivery import (
    DeliveryError,
    deliver_builtin,
    deliver_pack,
    insert_course_asset_lines,
    rewrite_ids,
)
from src.backend.course_media import (
    MediaPathError,
    copy_into_course_media,
    reject_unsafe_media_value,
)


def _write_course(root: Path, *, code: str = "es", section_id: str = "s1") -> None:
    (root / "sections").mkdir(parents=True, exist_ok=True)
    section = {
        "id": section_id,
        "name": "Greetings",
        "description": "hi",
        "prerequisiteSectionIds": [],
        "units": [{
            "id": "u1",
            "name": "Unit",
            "description": "",
            "prerequisiteUnitIds": [],
            "lessons": [{
                "id": "l1",
                "name": "Lesson",
                "description": "",
                "prerequisiteLessonIds": ["l0"],
                "content": {
                    "linkedGrammarPointIds": ["g1"],
                    "stages": [{
                        "id": "st",
                        "items": [{
                            "id": "q1",
                            "runtimeType": "showWord",
                            "wordId": "w1",
                            "audioAsset": "w1",
                            "sourceNoteId": "note-1",
                            "exampleExpressionIds": ["e1"],
                        }],
                    }],
                },
            }],
        }],
    }
    (root / "sections" / "section1.json").write_text(
        json.dumps(section), encoding="utf-8"
    )
    index = {
        "version": 1,
        "language": code,
        "displayName": "Spanish",
        "sections": [{
            "id": section_id,
            "name": "Greetings",
            "description": "hi",
            "level": "A1",
            "prerequisiteSectionIds": [],
            "file": "sections/section1.json",
        }],
    }
    (root / "index.json").write_text(json.dumps(index), encoding="utf-8")
    (root / "vocab.json").write_text(
        json.dumps({"version": 1, "language": code, "words": [
            {"id": "w1", "term": "hola", "translation": "hello"},
        ]}),
        encoding="utf-8",
    )
    (root / "expressions.json").write_text(
        json.dumps({"version": 1, "language": code, "expressions": [
            {"id": "e1", "term": "buenos días", "translation": "good morning"},
        ]}),
        encoding="utf-8",
    )
    (root / "grammar_points.json").write_text(
        json.dumps({"grammarPoints": [{"id": "g1", "title": "Greetings"}]}),
        encoding="utf-8",
    )


def _repo_with_pubspec(root: Path) -> None:
    courses = root / "assets" / "courses"
    courses.mkdir(parents=True)
    (courses / "manifest.json").write_text(json.dumps({
        "languages": [{
            "code": "tr",
            "displayName": "Turkish",
            "ttsLocale": "tr-TR",
            "dir": "turkish",
            "nativeLabel": "Türkçe öğren",
            "signatureChars": "ğ",
        }],
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (root / "pubspec.yaml").write_text(
        "flutter:\n"
        "  assets:\n"
        "    - assets/courses/\n"
        "    - assets/courses/turkish/\n"
        "    - assets/courses/turkish/sections/\n"
        "    - assets/changelog.md\n",
        encoding="utf-8",
    )


class RewriteIdsTest(unittest.TestCase):
    def test_prefix_is_stable_and_rewrites_references(self) -> None:
        doc = {
            "id": "s1",
            "file": "sections/section1.json",
            "prerequisiteSectionIds": ["s0"],
            "wordId": "w1",
            "exampleExpressionIds": ["e1"],
            "targetGrammarPointIds": ["g1"],
            "audioAsset": "w1",
            "imageAsset": "media/a.png",
            "sourceNoteId": "note-1",
            "items": [{"id": ""}],
        }
        once = rewrite_ids(doc, "es")
        self.assertEqual(once["id"], "ll-es-s1")
        self.assertEqual(once["file"], "sections/section1.json")
        self.assertEqual(once["prerequisiteSectionIds"], ["ll-es-s0"])
        self.assertEqual(once["wordId"], "ll-es-w1")
        self.assertEqual(once["exampleExpressionIds"], ["ll-es-e1"])
        self.assertEqual(once["targetGrammarPointIds"], ["ll-es-g1"])
        self.assertEqual(once["audioAsset"], "ll-es-w1")
        self.assertEqual(once["imageAsset"], "media/a.png")
        self.assertEqual(once["sourceNoteId"], "note-1")
        self.assertEqual(once["items"][0]["id"], "")
        self.assertEqual(rewrite_ids(once, "es"), once)

    def test_collision_of_plain_and_prefixed_ids_fails(self) -> None:
        with self.assertRaises(DeliveryError):
            rewrite_ids({"id": "foo", "child": {"id": "ll-es-foo"}}, "es")


class DeliverPackTest(unittest.TestCase):
    def test_external_pack_prefixes_ids_and_leaves_the_course_alone(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            course = root / "outside"
            _write_course(course)
            _repo_with_pubspec(root / "repo")
            out = root / "spanish.turnapack"
            result = deliver_pack(course, out, repo_root=root / "repo")
            self.assertTrue(result.ok)
            self.assertTrue(out.is_file())
            self.assertFalse(zipfile.is_zipfile(out))
            pack = json.loads(out.read_text(encoding="utf-8"))
            self.assertEqual(pack["format"], "turnapack/1")
            self.assertEqual(pack["language"]["code"], "es")
            self.assertEqual(pack["license"]["name"], "All rights reserved")
            self.assertEqual(pack["license"]["attribution"], "Spanish")
            section = pack["files"]["sections/section1.json"]
            self.assertEqual(section["id"], "ll-es-s1")
            self.assertEqual(pack["files"]["index.json"]["sections"][0]["id"], "ll-es-s1")
            self.assertEqual(
                pack["files"]["index.json"]["sections"][0]["file"],
                "sections/section1.json",
            )
            self.assertEqual(pack["files"]["vocab.json"]["words"][0]["id"], "ll-es-w1")
            item = section["units"][0]["lessons"][0]["content"]["stages"][0]["items"][0]
            self.assertEqual(item["wordId"], "ll-es-w1")
            saved = json.loads((course / "index.json").read_text(encoding="utf-8"))
            self.assertEqual(saved["sections"][0]["id"], "s1")

    def test_builtin_code_is_refused_as_an_external_pack(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            course = root / "outside"
            _write_course(course, code="tr")
            _repo_with_pubspec(root / "repo")
            with self.assertRaises(DeliveryError):
                deliver_pack(course, root / "tr.turnapack", repo_root=root / "repo")

    def test_anki_code_is_refused_without_a_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            course = root / "outside"
            _write_course(course, code="anki")
            with self.assertRaises(DeliveryError):
                deliver_pack(course, root / "anki.turnapack", repo_root=root / "empty-repo")

    def test_media_directory_writes_v2_zip(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            course = root / "outside"
            _write_course(course)
            media = course / "media"
            media.mkdir()
            (media / "a.png").write_bytes(b"png")
            section_path = course / "sections" / "section1.json"
            section = json.loads(section_path.read_text(encoding="utf-8"))
            item = section["units"][0]["lessons"][0]["content"]["stages"][0]["items"][0]
            item["imageAsset"] = "media/a.png"
            section_path.write_text(json.dumps(section), encoding="utf-8")
            out = root / "spanish.turnapack"
            deliver_pack(course, out, repo_root=root / "repo-missing")
            self.assertTrue(zipfile.is_zipfile(out))
            with zipfile.ZipFile(out) as archive:
                names = set(archive.namelist())
            self.assertIn("pack.json", names)
            self.assertIn("media/a.png", names)
            pack = json.loads(zipfile.ZipFile(out).read("pack.json"))
            self.assertEqual(pack["format"], "turnapack/2")


class DeliverBuiltinTest(unittest.TestCase):
    def test_registers_new_language_and_is_idempotent(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            _repo_with_pubspec(repo)
            course = repo / "assets" / "courses" / "spanish"
            _write_course(course, code="es")
            first = deliver_builtin(course, repo)
            self.assertIn("重新构建", first.message)
            manifest = json.loads(
                (repo / "assets" / "courses" / "manifest.json").read_text(encoding="utf-8")
            )
            added = next(item for item in manifest["languages"] if item["code"] == "es")
            self.assertEqual(added["dir"], "spanish")
            self.assertEqual(added["ttsLocale"], "es-ES")
            turkish = next(item for item in manifest["languages"] if item["code"] == "tr")
            self.assertEqual(turkish["dir"], "turkish")
            pubspec = (repo / "pubspec.yaml").read_text(encoding="utf-8")
            self.assertIn("assets/courses/spanish/", pubspec)
            self.assertIn("assets/courses/spanish/sections/", pubspec)
            self.assertIn("assets/courses/spanish/media/", pubspec)
            self.assertEqual(pubspec.count("assets/courses/spanish/"), 3)
            again = (repo / "pubspec.yaml").read_text(encoding="utf-8")
            deliver_builtin(course, repo)
            self.assertEqual((repo / "pubspec.yaml").read_text(encoding="utf-8"), again)

    def test_existing_language_keeps_its_directory(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            _repo_with_pubspec(repo)
            course = repo / "assets" / "courses" / "other"
            _write_course(course, code="tr")
            (course / "index.json").write_text(json.dumps({
                "version": 1,
                "language": "tr",
                "displayName": "Turkish",
                "ttsLocale": "tr-TR",
                "nativeLabel": "Türkçe öğren",
                "signatureChars": "ğ",
                "sections": [],
            }), encoding="utf-8")
            (course / "vocab.json").write_text('{"words": []}', encoding="utf-8")
            deliver_builtin(course, repo)
            manifest = json.loads(
                (repo / "assets" / "courses" / "manifest.json").read_text(encoding="utf-8")
            )
            turkish = next(item for item in manifest["languages"] if item["code"] == "tr")
            self.assertEqual(turkish["dir"], "turkish")
            self.assertEqual(len(manifest["languages"]), 1)

    def test_asset_line_insert_keeps_existing_lines(self) -> None:
        text = (
            "flutter:\n"
            "  assets:\n"
            "    - assets/courses/turkish/\n"
            "    - assets/courses/turkish/sections/\n"
            "    - assets/changelog.md\n"
        )
        updated = insert_course_asset_lines(text, "turkish")
        self.assertIn("    - assets/courses/turkish/media/\n", updated)
        self.assertEqual(updated.count("assets/courses/turkish/"), 3)
        self.assertEqual(insert_course_asset_lines(updated, "turkish"), updated)


class MediaPathTest(unittest.TestCase):
    def test_copy_stores_media_relative_name(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "from disk.png"
            source.write_bytes(b"img")
            course = root / "course"
            course.mkdir()
            stored = copy_into_course_media(course, source)
            self.assertEqual(stored, "media/from_disk.png")
            self.assertEqual((course / "media" / "from_disk.png").read_bytes(), b"img")

    def test_rejects_parent_and_absolute_refs(self) -> None:
        with self.assertRaises(MediaPathError):
            reject_unsafe_media_value("../secret.mp3")
        with self.assertRaises(MediaPathError):
            reject_unsafe_media_value("C:/sounds/a.mp3")
        reject_unsafe_media_value("anki://imp/a.mp3")
        reject_unsafe_media_value("media/a.png")


class MediaLintTest(unittest.TestCase):
    def test_media_ref_is_not_a_missing_listening_id(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            course = Path(tmp)
            sections = course / "sections"
            sections.mkdir()
            media = course / "media"
            media.mkdir()
            (media / "hola.mp3").write_bytes(b"mp3")
            lesson = {
                "id": "l-1", "name": "L1", "type": "normal", "template": "listening",
                "content": {
                    "listeningPhases": [{"id": "lp", "name": "P", "type": "summary", "items": []}],
                    "stages": [{"id": "st", "name": "S", "items": [{
                        "runtimeType": "listenOnly",
                        "id": "i1",
                        "audioAsset": "media/hola.mp3",
                        "transcript": "hola",
                    }]}],
                },
            }
            section = {"id": "s-1", "name": "S", "units": [
                {"id": "u-1", "name": "U", "lessons": [lesson]},
            ]}
            (sections / "s1.json").write_text(json.dumps(section), encoding="utf-8")
            (course / "index.json").write_text(json.dumps({
                "version": 1, "language": "es", "displayName": "Spanish",
                "sections": [{"id": "s-1", "name": "S", "description": "",
                              "prerequisiteSectionIds": [], "file": "sections/s1.json"}],
            }), encoding="utf-8")
            (course / "vocab.json").write_text('{"words": []}', encoding="utf-8")
            (course / "expressions.json").write_text('{"expressions": []}', encoding="utf-8")
            (course / "grammar_points.json").write_text('{"grammarPoints": []}', encoding="utf-8")
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                code = course_cli.cmd_lint(Namespace(course_dir=course, strict=False))
            output = buf.getvalue()
            self.assertNotIn("assets/sounds/listening/media", output)
            self.assertNotIn("Missing audio file", output)
            self.assertEqual(code, 0, output)
            rows = course_cli.build_audio_manifest(course)
            match = next(row for row in rows if row["asset_id"] == "media/hola.mp3")
            self.assertEqual(match["status"], "present")

    def test_turnapack_ref_is_external(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            course = Path(tmp)
            sections = course / "sections"
            sections.mkdir()
            lesson = {
                "id": "l-1", "name": "L1", "type": "normal", "template": "listening",
                "content": {
                    "listeningPhases": [{"id": "lp", "name": "P", "type": "summary", "items": []}],
                    "stages": [{"id": "st", "name": "S", "items": [{
                        "runtimeType": "listenOnly",
                        "id": "i1",
                        "audioAsset": "turnapack://es/hola.mp3",
                    }]}],
                },
            }
            (sections / "s1.json").write_text(json.dumps({
                "id": "s-1", "name": "S", "units": [
                    {"id": "u-1", "name": "U", "lessons": [lesson]},
                ],
            }), encoding="utf-8")
            (course / "index.json").write_text(json.dumps({
                "version": 1, "language": "es", "displayName": "Spanish",
                "sections": [{"id": "s-1", "name": "S", "description": "",
                              "prerequisiteSectionIds": [], "file": "sections/s1.json"}],
            }), encoding="utf-8")
            (course / "vocab.json").write_text('{"words": []}', encoding="utf-8")
            (course / "expressions.json").write_text('{"expressions": []}', encoding="utf-8")
            (course / "grammar_points.json").write_text('{"grammarPoints": []}', encoding="utf-8")
            rows = course_cli.build_audio_manifest(course)
            self.assertFalse(any(row["asset_id"].startswith("turnapack://") for row in rows))


class SectionShellSyncTest(unittest.TestCase):
    def test_save_keeps_index_level_when_body_omits_it(self) -> None:
        from src.backend.course_io import CourseIoService, project_section_shells

        index = {"sections": [{
            "id": "s1",
            "name": "old",
            "description": "old",
            "level": "A1",
            "prerequisiteSectionIds": [],
            "file": "sections/section1.json",
        }]}
        sections = [{
            "id": "s1",
            "name": "Greetings",
            "description": "hi",
            "prerequisiteSectionIds": ["s0"],
        }]
        project_section_shells(index, sections)
        shell = index["sections"][0]
        self.assertEqual(shell["name"], "Greetings")
        self.assertEqual(shell["description"], "hi")
        self.assertEqual(shell["prerequisiteSectionIds"], ["s0"])
        self.assertEqual(shell["level"], "A1")
        sections[0]["level"] = ""
        project_section_shells(index, sections)
        self.assertEqual(index["sections"][0]["level"], "")

        with tempfile.TemporaryDirectory() as tmp:
            course = Path(tmp)
            adapter = type("A", (), {})()
            adapter.course_dir = course
            adapter.index = index
            adapter.sections = sections
            adapter.vocab = []
            adapter.expressions = []
            adapter.grammar_points = []
            adapter.expressions_version = 1
            adapter.section_file = lambda section_id: course / "sections" / "section1.json"
            CourseIoService.write_files_to_dir(adapter, course)
            written = json.loads((course / "index.json").read_text(encoding="utf-8"))
            self.assertEqual(written["sections"][0]["name"], "Greetings")
            self.assertEqual(written["sections"][0]["level"], "")


if __name__ == "__main__":
    unittest.main()
