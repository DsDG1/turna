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


def _write_course(
    root: Path,
    skills: dict[str, str],
    modules: list[str] | None = None,
    language_name: str = "Test Language",
    source_name: str = "English",
) -> Path:
    course_dir = root / "course"
    course_dir.mkdir()
    (course_dir / "course.yaml").write_text(
        f"""
Course:
  Language:
    Name: {language_name}
    IETF BCP 47: test-1
  For speakers of:
    Name: {source_name}
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


def _write_course_modules(
    root: Path, modules: dict[str, dict[str, str]]
) -> Path:
    """Multi-module variant of _write_course: {module_dir: {skill_file: body}}."""
    course_dir = root / "course"
    course_dir.mkdir()
    module_list = "\n".join(f"    - {name}" for name in modules)
    (course_dir / "course.yaml").write_text(
        f"""
Course:
  Language:
    Name: Test Language
    IETF BCP 47: test-1
  For speakers of:
    Name: English
  Modules:
{module_list}
""".strip()
        + "\n",
        encoding="utf-8",
    )
    for module, skills in modules.items():
        skills_dir = course_dir / module / "skills"
        skills_dir.mkdir(parents=True)
        skill_list = "\n".join(f"    - {name}" for name in skills)
        (course_dir / module / "module.yaml").write_text(
            f"Module:\n  Name: {module}\n  Skills:\n{skill_list}\n",
            encoding="utf-8",
        )
        for name, body in skills.items():
            (skills_dir / name).write_text(body.strip() + "\n", encoding="utf-8")
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

    def test_audio_field_references_attach_hash_named_files(self) -> None:
        # Real LibreLingo courses name audio after hashes and reference the
        # files only through the word's `Audio:` list — term-name matching
        # alone never finds them.
        skill = """
Skill:
  Name: Animals
  Id: 2
  New words:
    - Word: perro
      Translation: dog
      Audio:
        - 9e7dc7f0d0f1.mp3
    - Word: gato
      Translation: cat

Phrases:
  - Phrase: Max es un perro
    Translation: Max is a dog
"""
        with tempfile.TemporaryDirectory() as tmp:
            course_dir = _write_course(Path(tmp), {"animals.yaml": skill})
            audio = course_dir / "audio"
            audio.mkdir()
            (audio / "9e7dc7f0d0f1.mp3").write_bytes(b"ID3")
            (audio / "gato.mp3").write_bytes(b"ID3")
            pack = convert_course(
                course_dir,
                code="es",
                display_name="Spanish",
                tts_locale="es-ES",
            )
            words = {
                w["id"]: w for w in pack["files"]["vocab.json"]["words"]
            }
            self.assertEqual(
                words["ll-es-w-perro"]["audioAsset"],
                "media/9e7dc7f0d0f1.mp3",
            )
            # No Audio field → term-name matching still attaches.
            self.assertEqual(
                words["ll-es-w-gato"]["audioAsset"],
                "media/gato.mp3",
            )

    def test_slug_collisions_get_distinct_word_ids(self) -> None:
        # "más" and "mús" both fold to slug "m-s" — without disambiguation
        # the second word vanished and its sub-lesson taught the first.
        skill = """
Skill:
  Name: Accents
  Id: accents
  New words:
    - Word: más
      Translation: more
    - Word: mús
      Translation: muse
    - Word: gato
      Translation: cat
    - Word: perro
      Translation: dog
  Phrases: []
"""
        with tempfile.TemporaryDirectory() as tmp:
            course_dir = _write_course(Path(tmp), {"a.yaml": skill})
            pack = convert_course(
                course_dir, code="es", display_name="S", tts_locale="es-ES"
            )
            words = {w["term"]: w["id"] for w in pack["files"]["vocab.json"]["words"]}
            self.assertIn("más", words)
            self.assertIn("mús", words)
            self.assertNotEqual(words["más"], words["mús"])
            unpacked = Path(tmp) / "unpacked"
            unpack_pack(pack, unpacked)
            self.assertEqual(validate_unpacked(unpacked), 0)

    def test_slug_collision_across_skills_points_at_right_word(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            course_dir = _write_course(
                Path(tmp),
                {
                    "a.yaml": """
Skill:
  Name: A
  Id: 1
  New words:
    - Word: más
      Translation: more
    - Word: gato
      Translation: cat
    - Word: perro
      Translation: dog
    - Word: oso
      Translation: bear
  Phrases: []
""",
                    "b.yaml": """
Skill:
  Name: B
  Id: 2
  New words:
    - Word: mús
      Translation: muse
    - Word: leon
      Translation: lion
    - Word: tigre
      Translation: tiger
    - Word: lobo
      Translation: wolf
  Phrases: []
""",
                },
            )
            pack = convert_course(
                course_dir, code="es", display_name="S", tts_locale="es-ES"
            )
        words = {w["term"]: w["id"] for w in pack["files"]["vocab.json"]["words"]}
        section = pack["files"]["sections/ll-es-s-1.json"]
        for lesson in section["units"][0]["lessons"]:
            for sub in lesson["content"]["subLessons"]:
                show = next(
                    i for i in sub["stages"][0]["items"]
                    if i["runtimeType"] == "showWord"
                )
                self.assertEqual(show["wordId"], words[sub["name"]])

    def test_non_latin_terms_get_unique_ids(self) -> None:
        # Every CJK term folds to slug "x" — hash suffixes keep them apart.
        skill = """
Skill:
  Name: Kanji
  Id: kanji
  New words:
    - Word: 猫
      Translation: cat
    - Word: 犬
      Translation: dog
    - Word: 鳥
      Translation: bird
    - Word: 魚
      Translation: fish
  Phrases: []
"""
        with tempfile.TemporaryDirectory() as tmp:
            course_dir = _write_course(Path(tmp), {"a.yaml": skill})
            pack = convert_course(
                course_dir, code="ja", display_name="J", tts_locale="ja-JP"
            )
            words = pack["files"]["vocab.json"]["words"]
            self.assertEqual(len(words), 4)
            self.assertEqual(len({w["id"] for w in words}), 4)
            unpacked = Path(tmp) / "unpacked"
            unpack_pack(pack, unpacked)
            self.assertEqual(validate_unpacked(unpacked), 0)

    def test_module_chunks_into_units_beyond_chunk_size(self) -> None:
        # kMaxLessonsPerUnit is 40 — a big module must split into units.
        skills = {
            f"s{i:02d}.yaml": f"""
Skill:
  Name: S{i}
  Id: {i}
  New words:
    - Word: w{i}
      Translation: t{i}
  Phrases: []
"""
            for i in range(45)
        }
        with tempfile.TemporaryDirectory() as tmp:
            course_dir = _write_course(Path(tmp), skills)
            pack = convert_course(
                course_dir, code="es", display_name="S", tts_locale="es-ES"
            )
            section = pack["files"]["sections/ll-es-s-1.json"]
            self.assertEqual(len(section["units"]), 2)
            self.assertEqual(len(section["units"][0]["lessons"]), 30)
            self.assertEqual(len(section["units"][1]["lessons"]), 15)
            unpacked = Path(tmp) / "unpacked"
            unpack_pack(pack, unpacked)
            self.assertEqual(validate_unpacked(unpacked), 0)

    def test_duplicate_skill_ids_get_unique_lesson_ids(self) -> None:
        body = """
Skill:
  Name: X
  Id: 1
  New words:
    - Word: w
      Translation: t
    - Word: w2
      Translation: t2
    - Word: w3
      Translation: t3
    - Word: w4
      Translation: t4
  Phrases: []
"""
        with tempfile.TemporaryDirectory() as tmp:
            course_dir = _write_course_modules(
                Path(tmp), {"m1": {"a.yaml": body}, "m2": {"b.yaml": body}}
            )
            pack = convert_course(
                course_dir, code="es", display_name="S", tts_locale="es-ES"
            )
            lesson_ids = [
                lesson["id"]
                for name, section in pack["files"].items()
                if name.startswith("sections/")
                for unit in section["units"]
                for lesson in unit["lessons"]
            ]
            self.assertEqual(len(lesson_ids), len(set(lesson_ids)))
            unpacked = Path(tmp) / "unpacked"
            unpack_pack(pack, unpacked)
            self.assertEqual(validate_unpacked(unpacked), 0)

    def test_multiple_choice_shuffles_and_never_offers_prompt(self) -> None:
        # "dog" is both a translation (of perro) and a word in the same
        # skill — it must not appear among the options for prompt "dog".
        skill = """
Skill:
  Name: Animals
  Id: animals
  New words:
    - Word: perro
      Translation: dog
    - Word: dog
      Translation: domestic animal
    - Word: gato
      Translation: cat
    - Word: oso
      Translation: bear
    - Word: leon
      Translation: lion
  Phrases:
    - Phrase: el perro come
      Translation: the dog eats
"""
        with tempfile.TemporaryDirectory() as tmp:
            course_dir = _write_course(Path(tmp), {"a.yaml": skill})
            pack = convert_course(
                course_dir, code="es", display_name="S", tts_locale="es-ES"
            )
        section = pack["files"]["sections/ll-es-s-1.json"]
        mcs = [
            item
            for u in section["units"]
            for l in u["lessons"]
            for sl in l["content"]["subLessons"]
            for st in sl["stages"]
            for item in st["items"]
            if item["runtimeType"] in ("multipleChoice", "listenAndPick")
        ]
        self.assertTrue(mcs)
        for item in mcs:
            self.assertNotIn(item["prompt"], item["options"])
        indexes = {item["correctIndex"] for item in mcs}
        self.assertTrue(
            any(i != 0 for i in indexes),
            f"correctIndex stayed 0 for every item: {sorted(indexes)}",
        )

    def test_mini_dictionary_uses_named_target_bucket(self) -> None:
        # Course for Spanish speakers — the "Spanish" bucket is the source
        # side and must not be imported as target vocabulary.
        skill = """
Skill:
  Name: X
  Id: x
  New words:
    - Word: tlhingan
      Translation: klingon
    - Word: maj
      Translation: good
    - Word: qap
      Translation: success
    - Word: ter
      Translation: day
  Phrases: []
  Mini-dictionary:
    Spanish:
      - el: the
    Klingon:
      - jIH: I
"""
        with tempfile.TemporaryDirectory() as tmp:
            course_dir = _write_course(
                Path(tmp),
                {"x.yaml": skill},
                language_name="Klingon",
                source_name="Spanish",
            )
            pack = convert_course(
                course_dir, code="tlh", display_name="K", tts_locale="tlh"
            )
        terms = {w["term"] for w in pack["files"]["vocab.json"]["words"]}
        self.assertIn("jIH", terms)
        self.assertNotIn("el", terms)

    def test_word_without_translation_skips_translation_items(self) -> None:
        skill = """
Skill:
  Name: Loanwords
  Id: loan
  New words:
    - Word: okay
      Translation: okay
    - Word: sí
      Translation: yes
    - Word: no
      Translation: no
    - Word: brandname
  Phrases: []
"""
        with tempfile.TemporaryDirectory() as tmp:
            course_dir = _write_course(Path(tmp), {"a.yaml": skill})
            pack = convert_course(
                course_dir, code="es", display_name="S", tts_locale="es-ES"
            )
            section = pack["files"]["sections/ll-es-s-1.json"]
            sub_by_name = {
                sl["name"]: sl
                for l in section["units"][0]["lessons"]
                for sl in l["content"]["subLessons"]
            }
            bare = sub_by_name["brandname"]
            kinds = {
                i["runtimeType"]
                for st in bare["stages"]
                for i in st["items"]
            }
            self.assertIn("showWord", kinds)
            self.assertNotIn("translateSentence", kinds)
            self.assertNotIn("multipleChoice", kinds)
            # term == translation (loanword) is degenerate too.
            loanword = sub_by_name["okay"]
            self.assertFalse(
                any(
                    i["runtimeType"] == "translateSentence"
                    for st in loanword["stages"]
                    for i in st["items"]
                )
            )
            # A word without a translation must never produce a degenerate
            # copy-the-prompt item anywhere.
            for st in bare["stages"]:
                for item in st["items"]:
                    if item["runtimeType"] == "translateSentence":
                        self.assertNotEqual(item["source"], item["expected"])
            unpacked = Path(tmp) / "unpacked"
            unpack_pack(pack, unpacked)
            self.assertEqual(validate_unpacked(unpacked), 0)

    def test_special_chars_default_signature_chars(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            course_dir = _write_course(Path(tmp), {"a.yaml": HELLO_SKILL})
            yaml_path = course_dir / "course.yaml"
            yaml_path.write_text(
                yaml_path.read_text(encoding="utf-8")
                + '  Special characters:\n    - "á"\n    - "ñ"\n',
                encoding="utf-8",
            )
            pack = convert_course(
                course_dir, code="es", display_name="S", tts_locale="es-ES"
            )
        self.assertEqual(pack["language"]["signatureChars"], "áñ")


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
