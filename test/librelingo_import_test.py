#!/usr/bin/env python3
"""Unit tests for tool/librelingo_import.py (course-pack-import-plan §4.3)."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT / "tool"))

from librelingo_import import (  # type: ignore
    CODE_RE,
    convert_course,
    fisher_yates,
    parse_skill_phrases,
    parse_skill_words,
    slugify,
    unpack_pack,
    validate_unpacked,
    write_pack,
)


def _write_course(root: Path, skills: dict[str, str], modules: list[str] | None = None) -> Path:
    course_dir = root / "course"
    course_dir.mkdir()
    (course_dir / "course.yaml").write_text(
        """
Course:
  Language:
    Name: Test Language
    IETF BCP 47: test-1
  For speakers of:
    Name: English
  License:
    Name: Attribution-ShareAlike 4.0 International
    Short name: CC BY-SA 4.0
    Link: https://creativecommons.org/licenses/by-sa/4.0/
  Modules:
    - basics
""".strip()
        + "\n",
        encoding="utf-8",
    )
    basics = course_dir / "basics"
    skills_dir = basics / "skills"
    skills_dir.mkdir(parents=True)
    skill_list = "\n".join(f"    - {name}" for name in skills)
    (basics / "module.yaml").write_text(
        f"Module:\n  Name: Basics\n  Skills:\n{skill_list}\n",
        encoding="utf-8",
    )
    for name, body in skills.items():
        (skills_dir / name).write_text(body.strip() + "\n", encoding="utf-8")
        (skills_dir / name.replace(".yaml", ".md")).write_text("ignore me\n", encoding="utf-8")
    return course_dir


def _write_course_flat(root: Path, skills: dict[str, str]) -> Path:
    """Real-repo layout (LibreLingo-ES-from-EN): Modules / Skills / New words
    are top-level siblings of their header blocks, module names carry a
    trailing slash."""
    course_dir = root / "course"
    course_dir.mkdir()
    (course_dir / "course.yaml").write_text(
        """
Course:
  Language:
    Name: Spanish
    IETF BCP 47: es
  For speakers of:
    Name: English
  License:
    Name: Attribution-ShareAlike 4.0 International
    Short name: CC BY-SA 4.0
    Link: https://creativecommons.org/licenses/by-sa/4.0/

Modules:
  - basics/
""".strip()
        + "\n",
        encoding="utf-8",
    )
    basics = course_dir / "basics"
    skills_dir = basics / "skills"
    skills_dir.mkdir(parents=True)
    skill_list = "\n".join(f"  - {name}" for name in skills)
    (basics / "module.yaml").write_text(
        f'Module:\n  Name: "Basics"\n\nSkills:\n{skill_list}\n',
        encoding="utf-8",
    )
    for name, body in skills.items():
        (skills_dir / name).write_text(body.strip() + "\n", encoding="utf-8")
    return course_dir


FLAT_HELLO_SKILL = """
Skill:
  Name: Animals
  Id: 2
  Thumbnails:
    - dog1

New words:
  - Word: perro
    Translation: dog
  - Word: gato
    Translation: cat
  - Word: oso
    Translation: bear
  - Word: leon
    Translation: lion

Phrases:
  - Phrase: Max es un perro
    Translation: Max is a dog

Mini-dictionary:
  Test Language:
    - un: a/an
  English:
    - the:
        - la
        - el
"""


HELLO_SKILL = """
Skill:
  Name: Animals
  Id: 2
  Thumbnails:
    - dog1
  New words:
    - Word: perro
      Synonyms:
        - can
      Translation: dog
      Also accepted:
        - hound
      Images:
        - dog1
    - Word: gato
      Translation: cat
    - Word: oso
      Translation: bear
    - Word: leon
      Translation: lion
  Phrases:
    - Phrase: Max es un perro
      Alternative versions:
        - Max es un can
      Translation: Max is a dog
  Mini-dictionary:
    Test Language:
      - un: a/an
      - es: is
    English:
      - the:
          - la
          - el
"""

PHRASES_SKILL = """
Skill:
  Name: Chips
  Id: chips-test-0
  New words: []
  Phrases:
    - Phrase: Como estas hoy
      Translation: How are you today?
      Alternative versions:
        - Hoy como estas
  Mini-dictionary:
    Test Language:
      - Como: how
      - estas: are
      - hoy: today
    English:
      - How: asd
"""

EMPTY_SKILL = """
Skill:
  Name: Continuous
  Id: empty-skill
  New words: []
  Phrases: []
"""


class TestLibrelingoImport(unittest.TestCase):
    def test_code_regex_rejects_test_1_ietf(self) -> None:
        self.assertFalse(CODE_RE.fullmatch("test-1"))
        self.assertTrue(CODE_RE.fullmatch("es"))

    def test_slugify_folds_non_ascii(self) -> None:
        self.assertEqual(slugify("Cómo estás tu?"), "c-mo-est-s-tu")

    def test_fisher_yates_is_deterministic_and_reshuffles_identity(self) -> None:
        tokens = ["a", "b"]
        first = fisher_yates(tokens, "ll-es-e-demo")
        second = fisher_yates(tokens, "ll-es-e-demo")
        self.assertEqual(first, second)
        self.assertEqual(sorted(first), sorted(tokens))

    def test_parse_words_maps_synonyms_and_also_accepted(self) -> None:
        words = parse_skill_words(
            {
                "New words": [
                    {
                        "Word": "perro",
                        "Translation": "dog",
                        "Synonyms": ["can"],
                        "Also accepted": ["hound"],
                        "Images": ["dog1"],
                    }
                ]
            }
        )
        self.assertEqual(words[0]["synonyms"], ["can"])
        self.assertEqual(words[0]["also_accepted"], ["hound"])
        self.assertEqual(words[0]["images"], ["dog1"])

    def test_parse_phrases_maps_alternatives(self) -> None:
        phrases = parse_skill_phrases(
            {
                "Phrases": [
                    {
                        "Phrase": "Max es un perro",
                        "Translation": "Max is a dog",
                        "Alternative versions": ["Max es un can"],
                    }
                ]
            }
        )
        self.assertEqual(phrases[0]["alternatives"], ["Max es un can"])

    def test_convert_real_course_yaml_layout(self) -> None:
        """ES-from-EN shape: header blocks and content are siblings."""
        with tempfile.TemporaryDirectory() as tmp:
            course_dir = _write_course_flat(Path(tmp), {"animals.yaml": FLAT_HELLO_SKILL})
            pack = convert_course(
                course_dir,
                code="es",
                display_name="Spanish",
                tts_locale="es-ES",
            )
            unpacked = Path(tmp) / "unpacked"
            unpack_pack(pack, unpacked)
            self.assertEqual(validate_unpacked(unpacked), 0)
        sections = pack["files"]["index.json"]["sections"]
        self.assertEqual(len(sections), 1)
        words = pack["files"]["vocab.json"]["words"]
        self.assertTrue(any(w["term"] == "perro" for w in words))

    def test_convert_mapping_table_and_prefix(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            course_dir = _write_course(
                Path(tmp),
                {
                    "animals.yaml": HELLO_SKILL,
                    "chips-test-0.yaml": PHRASES_SKILL,
                    "nature.yaml": EMPTY_SKILL,
                },
            )
            pack = convert_course(
                course_dir,
                code="es",
                display_name="Spanish",
                tts_locale="es-ES",
            )
        self.assertEqual(pack["format"], "turnapack/1")
        self.assertEqual(pack["language"]["code"], "es")
        self.assertEqual(pack["language"]["nativeLabel"], "Test Language")
        self.assertEqual(pack["license"]["name"], "CC BY-SA 4.0")
        self.assertEqual(pack["license"]["attribution"], "LibreLingo community")
        words = pack["files"]["vocab.json"]["words"]
        ids = {w["id"] for w in words}
        self.assertTrue(all(i.startswith("ll-es-") for i in ids))
        perro = next(w for w in words if w["term"] == "perro")
        self.assertEqual(perro["id"], "ll-es-w-perro")
        self.assertEqual(perro["translation"], "dog")
        # Mini-dictionary target-language entries merged.
        self.assertIn("ll-es-w-un", ids)
        # Source-language mini-dict direction is dropped (no English "the").
        self.assertFalse(any(w["term"] == "the" for w in words))
        expressions = pack["files"]["expressions.json"]["expressions"]
        self.assertTrue(expressions)
        self.assertTrue(all(e["id"].startswith("ll-es-e-") for e in expressions))
        section = pack["files"]["sections/ll-es-s-1.json"]
        self.assertEqual(section["id"], "ll-es-s-1")
        lessons = section["units"][0]["lessons"]
        lesson_ids = [l["id"] for l in lessons]
        self.assertIn("ll-es-l-2", lesson_ids)
        self.assertIn("ll-es-l-chips-test-0", lesson_ids)
        self.assertNotIn("ll-es-l-empty-skill", lesson_ids)
        animals = next(l for l in lessons if l["id"] == "ll-es-l-2")
        self.assertEqual(animals["template"], "intro")
        ts = [
            item
            for sl in animals["content"]["subLessons"]
            for st in sl["stages"]
            for item in st["items"]
            if item["runtimeType"] == "translateSentence" and item["expected"] == "perro"
        ]
        self.assertEqual(ts[0]["hints"], ["can", "hound"])
        chips = next(l for l in lessons if l["id"] == "ll-es-l-chips-test-0")
        self.assertEqual(chips["template"], "practice")
        items = chips["content"]["subLessons"][0]["stages"][0]["items"]
        kinds = {i["runtimeType"] for i in items}
        self.assertIn("reorderSentence", kinds)
        self.assertIn("translateSentence", kinds)
        reorder = next(i for i in items if i["runtimeType"] == "reorderSentence")
        self.assertEqual(reorder["correct"], "Como estas hoy".split())
        self.assertNotEqual(reorder["scrambled"], reorder["correct"])
        ts_phrase = next(i for i in items if i["runtimeType"] == "translateSentence")
        self.assertEqual(ts_phrase["hints"], ["Hoy como estas"])
        # Images / thumbnails / md files must not produce imageAsset.
        blob = json.dumps(pack)
        self.assertNotIn("imageAsset", blob)
        self.assertNotIn("dog1", blob)

    def test_empty_phrases_still_emit_vocab(self) -> None:
        skill = """
Skill:
  Name: Words only
  Id: words-only
  New words:
    - Word: foo
      Translation: bar
    - Word: baz
      Translation: qux
    - Word: alpha
      Translation: one
    - Word: beta
      Translation: two
  Phrases: []
"""
        with tempfile.TemporaryDirectory() as tmp:
            course_dir = _write_course(Path(tmp), {"words.yaml": skill})
            pack = convert_course(
                course_dir,
                code="es",
                display_name="Spanish",
                tts_locale="es-ES",
            )
        words = pack["files"]["vocab.json"]["words"]
        self.assertGreaterEqual(len(words), 4)
        self.assertEqual(pack["files"]["expressions.json"]["expressions"], [])

    def test_rejects_ietf_as_code(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            course_dir = _write_course(Path(tmp), {"animals.yaml": HELLO_SKILL})
            with self.assertRaises(ValueError):
                convert_course(
                    course_dir,
                    code="test-1",
                    display_name="Nope",
                    tts_locale="es-ES",
                )

    def test_validate_fixture_course(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            course_dir = _write_course(
                Path(tmp),
                {
                    "animals.yaml": HELLO_SKILL,
                    "chips-test-0.yaml": PHRASES_SKILL,
                },
            )
            pack = convert_course(
                course_dir,
                code="es",
                display_name="Spanish",
                tts_locale="es-ES",
            )
            unpacked = Path(tmp) / "unpacked"
            unpack_pack(pack, unpacked)
            self.assertEqual(validate_unpacked(unpacked), 0)

    def test_multiple_choice_skipped_when_pool_under_four(self) -> None:
        skill = """
Skill:
  Name: Tiny
  Id: tiny
  New words:
    - Word: only
      Translation: one
  Phrases: []
"""
        with tempfile.TemporaryDirectory() as tmp:
            course_dir = _write_course(Path(tmp), {"tiny.yaml": skill})
            pack = convert_course(
                course_dir,
                code="es",
                display_name="Spanish",
                tts_locale="es-ES",
            )
        section = pack["files"]["sections/ll-es-s-1.json"]
        items = [
            item
            for sl in section["units"][0]["lessons"][0]["content"]["subLessons"]
            for st in sl["stages"]
            for item in st["items"]
        ]
        self.assertFalse(any(i["runtimeType"] == "multipleChoice" for i in items))

    def test_images_and_audio_are_packed_into_zip(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            course_dir = _write_course(Path(tmp), {"animals.yaml": HELLO_SKILL})
            images = course_dir / "images"
            images.mkdir()
            (images / "dog1.jpg").write_bytes(b"\xff\xd8\xff\xd9")
            (images / "perro.mp3").write_bytes(b"ID3")
            pack = convert_course(
                course_dir,
                code="es",
                display_name="Spanish",
                tts_locale="es-ES",
            )
            self.assertEqual(pack["format"], "turnapack/2")
            self.assertIn("media/dog1.jpg", pack["_media"])
            self.assertIn("media/perro.mp3", pack["_media"])
            section = pack["files"]["sections/ll-es-s-1.json"]
            show = next(
                item
                for sl in section["units"][0]["lessons"][0]["content"]["subLessons"]
                for st in sl["stages"]
                for item in st["items"]
                if item["runtimeType"] == "showWord" and item["wordId"] == "ll-es-w-perro"
            )
            self.assertEqual(show["imageAsset"], "media/dog1.jpg")
            perro = next(
                w
                for w in pack["files"]["vocab.json"]["words"]
                if w["id"] == "ll-es-w-perro"
            )
            self.assertEqual(perro["audioAsset"], "media/perro.mp3")
            out = Path(tmp) / "course.turnapack"
            write_pack(pack, out)
            self.assertTrue(zipfile.ZipFile(out).namelist())
            names = set(zipfile.ZipFile(out).namelist())
            self.assertIn("pack.json", names)
            self.assertIn("media/dog1.jpg", names)
            self.assertIn("media/perro.mp3", names)
            manifest = json.loads(zipfile.ZipFile(out).read("pack.json"))
            self.assertEqual(manifest["format"], "turnapack/2")
            self.assertNotIn("_media", manifest)


class TestLibreLingoTest1Fixture(unittest.TestCase):
    def test_test1_converts_and_validates_when_present(self) -> None:
        fixture = PROJECT_ROOT / "test" / "fixtures" / "librelingo" / "test-1"
        if not (fixture / "course.yaml").is_file():
            self.skipTest("vendored LibreLingo test-1 course is missing")
        pack = convert_course(
            fixture,
            code="es",
            display_name="Spanish",
            tts_locale="es-ES",
        )
        self.assertEqual(pack["language"]["code"], "es")
        self.assertTrue(pack["files"]["vocab.json"]["words"])
        with tempfile.TemporaryDirectory() as tmp:
            unpacked = Path(tmp) / "unpacked"
            unpack_pack(pack, unpacked)
            self.assertEqual(validate_unpacked(unpacked), 0)


class TestLibreLingoRealCourseFixture(unittest.TestCase):
    """DoD §11: the converter must handle a real course repo, not just test-1.

    Clone shallowly next to the repo to run locally:
    git clone --depth 1 https://github.com/kantord/LibreLingo-ES-from-EN \
        ../LibreLingo-ES-from-EN
    """

    REAL_COURSE = PROJECT_ROOT.parent / "LibreLingo-ES-from-EN" / "course"

    def test_real_es_course_converts_and_validates_when_present(self) -> None:
        if not (self.REAL_COURSE / "course.yaml").is_file():
            self.skipTest("real LibreLingo-ES-from-EN course is not cloned")
        pack = convert_course(
            self.REAL_COURSE,
            code="es",
            display_name="Spanish",
            tts_locale="es-ES",
        )
        sections = pack["files"]["index.json"]["sections"]
        words = pack["files"]["vocab.json"]["words"]
        self.assertGreaterEqual(len(sections), 3)
        self.assertGreaterEqual(len(words), 100)
        with tempfile.TemporaryDirectory() as tmp:
            unpacked = Path(tmp) / "unpacked"
            unpack_pack(pack, unpacked)
            self.assertEqual(validate_unpacked(unpacked), 0)


if __name__ == "__main__":
    unittest.main()
