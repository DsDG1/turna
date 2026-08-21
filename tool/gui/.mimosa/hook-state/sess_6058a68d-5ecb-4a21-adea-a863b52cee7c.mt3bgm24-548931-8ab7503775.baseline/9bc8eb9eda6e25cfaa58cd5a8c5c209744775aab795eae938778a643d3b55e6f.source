"""Round-trip test: load a course copy, edit section name, save, validate ok."""
from __future__ import annotations

import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))
from tests._course_fixture import copy_turkish_course  # noqa: E402

from src.backend.course_adapter import CourseAdapter  # noqa: E402


class CourseAdapterRoundTripTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="turna_gui_"))
        self.course_dir = self.tmp / "turkish"
        copy_turkish_course(self.course_dir)

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_load_turkish(self) -> None:
        adapter = CourseAdapter()
        adapter.load(self.course_dir)
        self.assertEqual(adapter.index.get("language"), "tr")
        self.assertGreaterEqual(len(adapter.sections), 1)

    def test_save_section_rename_validates(self) -> None:
        adapter = CourseAdapter()
        adapter.load(self.course_dir)
        first = adapter.sections[0]
        sid = first["id"]
        adapter.update_section_meta(sid, "Section 1 (edited)", first.get("description", ""))
        result = adapter.save()
        self.assertTrue(result.ok, f"save failed: {result.message} errors={result.errors}")

        reloaded = CourseAdapter()
        reloaded.load(self.course_dir)
        self.assertEqual(reloaded.find_section(sid)["name"], "Section 1 (edited)")

    def test_save_rollback_on_validation_failure(self) -> None:
        adapter = CourseAdapter()
        adapter.load(self.course_dir)
        first = adapter.sections[0]
        lid = first["units"][0]["lessons"][0]["id"]
        original_content = first["units"][0]["lessons"][0]["content"]
        first["units"][0]["lessons"][0]["content"] = {}
        result = adapter.save()
        self.assertFalse(result.ok, f"expected validation failure, got {result}")
        self.assertGreater(len(result.errors), 0)
        _s, _u, reloaded_lesson = adapter.find_lesson(lid)
        self.assertEqual(reloaded_lesson["content"], original_content)

    def test_merge_section_resources_adds_new_and_skips_existing(self) -> None:
        adapter = CourseAdapter()
        adapter.load(self.course_dir)
        existing_word_id = adapter.vocab[0]["id"] if adapter.vocab else "w-x"
        section = {
            "id": "ai-merge-test",
            "words": [
                {"id": existing_word_id, "term": "dup", "translation": "dup"},
                {"id": "w-ai-new-1", "term": "Merhaba", "translation": "你好"},
            ],
            "expressions": [
                {"id": "e-ai-new-1", "term": "Adım", "translation": "我叫"},
            ],
            "grammarPoints": [],
        }
        before_vocab = len(adapter.vocab)
        added = adapter.merge_section_resources(section)
        self.assertEqual(added["vocab"], 1)
        self.assertEqual(added["expressions"], 1)
        self.assertEqual(added["grammar_points"], 0)
        self.assertEqual(len(adapter.vocab), before_vocab + 1)
        self.assertTrue(any(w["id"] == "w-ai-new-1" for w in adapter.vocab))

    def test_validate_section_json_accepts_self_carried_words(self) -> None:
        adapter = CourseAdapter()
        adapter.load(self.course_dir)
        section = {
            "id": "ai-self-carried",
            "name": "Self carried",
            "words": [{"id": "w-ai-self-1", "term": "Selam", "translation": "你好"}],
            "units": [
                {
                    "id": "ai-self-carried-u1",
                    "lessons": [
                        {
                            "id": "ai-self-carried-u1-l1",
                            "content": {
                                "stages": [
                                    {
                                        "id": "ai-self-carried-u1-l1-st1",
                                        "items": [
                                            {
                                                "runtimeType": "showWord",
                                                "id": "ai-self-carried-u1-l1-st1-i1",
                                                "wordId": "w-ai-self-1",
                                            }
                                        ],
                                    }
                                ]
                            },
                        }
                    ],
                }
            ],
        }
        problems = adapter.validate_section_json(section)
        errors = [p for p in problems if p["level"] == "error"]
        self.assertEqual(
            errors,
            [],
            f"expected no errors for self-carried word, got: {errors}",
        )


class PrereqEditTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="turna_gui_"))
        self.course_dir = self.tmp / "turkish"
        copy_turkish_course(self.course_dir)

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_update_lesson_prereqs_writes_and_persists(self) -> None:
        adapter = CourseAdapter()
        adapter.load(self.course_dir)
        unit = adapter.sections[0]["units"][0]
        lessons = unit["lessons"]
        self.assertGreaterEqual(len(lessons), 2)
        lid = lessons[0]["id"]
        other_lid = lessons[1]["id"]
        adapter.update_lesson_prereqs(lid, [other_lid])
        result = adapter.save()
        self.assertTrue(result.ok, f"save failed: {result.message} errors={result.errors}")

        reloaded = CourseAdapter()
        reloaded.load(self.course_dir)
        _s, _u, reloaded_lesson = reloaded.find_lesson(lid)
        self.assertEqual(reloaded_lesson["prerequisiteLessonIds"], [other_lid])

    def test_section_prereq_options_exclude_self(self) -> None:
        adapter = CourseAdapter()
        adapter.load(self.course_dir)
        sid = adapter.sections[0]["id"]
        options = adapter.section_prereq_options(sid)
        ids = [rid for rid, _label in options]
        self.assertNotIn(sid, ids)
        self.assertGreater(len(ids), 0)

    def test_unit_prereq_options_scoped_to_section(self) -> None:
        adapter = CourseAdapter()
        adapter.load(self.course_dir)
        section1 = adapter.sections[0]
        section1_id = section1["id"]
        unit1 = section1["units"][0]
        unit1_id = unit1["id"]
        scoped_ids = {rid for rid, _label in adapter.unit_prereq_options(section1_id, unit1_id)}

        all_unit_ids_in_section1 = {u["id"] for u in section1.get("units", [])}
        self.assertTrue(scoped_ids.issubset(all_unit_ids_in_section1))
        self.assertNotIn(unit1_id, scoped_ids)

        other_section_unit_ids: set[str] = set()
        for s in adapter.sections[1:]:
            for u in s.get("units", []):
                other_section_unit_ids.add(u["id"])
        self.assertFalse(scoped_ids & other_section_unit_ids)


class ResourceEditTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="turna_gui_"))
        self.course_dir = self.tmp / "turkish"
        copy_turkish_course(self.course_dir)

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_write_files_persists_vocab_edit(self) -> None:
        adapter = CourseAdapter()
        adapter.load(self.course_dir)
        original = adapter.vocab[0]["term"]
        adapter.vocab[0]["term"] = original + "_edited"
        result = adapter.save()
        self.assertTrue(result.ok, f"save failed: {result.message} errors={result.errors}")

        reloaded = CourseAdapter()
        reloaded.load(self.course_dir)
        self.assertEqual(reloaded.vocab[0]["term"], original + "_edited")

    def test_import_csv_merges_and_returns_problems(self) -> None:
        import csv as csv_mod

        adapter = CourseAdapter()
        adapter.load(self.course_dir)
        csv_path = self.tmp / "vocab.csv"
        adapter.export_csv("vocab", csv_path)

        with csv_path.open("r", encoding="utf-8", newline="") as f:
            lines = f.read().splitlines()
        lines.append("w-new,New,New translation,,,noun")
        csv_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

        problems = adapter.import_csv("vocab", csv_path)
        errors = [p for p in problems if p["level"] == "error"]
        self.assertEqual(errors, [], f"unexpected errors: {errors}")
        ids = [w["id"] for w in adapter.vocab]
        self.assertIn("w-new", ids)

        result = adapter.save()
        self.assertTrue(result.ok, f"save failed: {result.message}")
        reloaded = CourseAdapter()
        reloaded.load(self.course_dir)
        self.assertIn("w-new", [w["id"] for w in reloaded.vocab])

    def test_import_csv_blocks_on_error(self) -> None:
        import csv as csv_mod

        adapter = CourseAdapter()
        adapter.load(self.course_dir)
        csv_path = self.tmp / "bad.csv"
        with csv_path.open("w", encoding="utf-8", newline="") as f:
            writer = csv_mod.DictWriter(
                f,
                fieldnames=["id", "term", "translation", "pronunciation", "audioAsset", "tags"],
            )
            writer.writeheader()
            writer.writerow(
                {"id": "w-bad", "term": "", "translation": "x", "tags": ""}
            )
        before = list(adapter.vocab)
        problems = adapter.import_csv("vocab", csv_path)
        self.assertTrue(any(p["level"] == "error" for p in problems))
        self.assertEqual(adapter.vocab, before)

    def test_export_csv_from_memory(self) -> None:
        adapter = CourseAdapter()
        adapter.load(self.course_dir)
        adapter.vocab[0]["term"] = "MEMORY_ONLY_EDIT"
        csv_path = self.tmp / "out.csv"
        adapter.export_csv("vocab", csv_path)
        text = csv_path.read_text(encoding="utf-8")
        self.assertIn("MEMORY_ONLY_EDIT", text)

    def test_delete_resource_entry(self) -> None:
        adapter = CourseAdapter()
        adapter.load(self.course_dir)

        def _collect_refs(obj: Any, acc: set[str]) -> None:
            if isinstance(obj, str):
                if obj.startswith("w-"):
                    acc.add(obj)
            elif isinstance(obj, list):
                for v in obj:
                    _collect_refs(v, acc)
            elif isinstance(obj, dict):
                for v in obj.values():
                    _collect_refs(v, acc)

        referenced: set[str] = set()
        for section in adapter.sections:
            _collect_refs(section, referenced)
        unreferenced = [w["id"] for w in adapter.vocab if w["id"] not in referenced]
        self.assertGreater(
            len(unreferenced), 0, "test fixture needs at least one unreferenced vocab"
        )
        target = unreferenced[0]
        adapter.delete_resource_entry("vocab", target)
        self.assertNotIn(target, [w["id"] for w in adapter.vocab])
        result = adapter.save()
        self.assertTrue(result.ok, f"save failed: {result.message}")
        reloaded = CourseAdapter()
        reloaded.load(self.course_dir)
        self.assertNotIn(target, [w["id"] for w in reloaded.vocab])

    def test_grammar_points_import_preserves_practice_items(self) -> None:
        import json as json_mod

        gp_path = self.course_dir / "grammar_points.json"
        gp_data = json_mod.loads(gp_path.read_text(encoding="utf-8"))
        gp_data["grammarPoints"] = [
            {
                "id": "g-test",
                "title": "Test",
                "explanation": "x",
                "exampleExpressionIds": [],
                "exampleSentenceIds": [],
                "practiceItems": [{"q": "a", "a": "b"}],
            }
        ]
        gp_path.write_text(
            json_mod.dumps(gp_data, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )

        adapter = CourseAdapter()
        adapter.load(self.course_dir)
        csv_path = self.tmp / "g.csv"
        adapter.export_csv("grammar_points", csv_path)
        with csv_path.open("r", encoding="utf-8", newline="") as f:
            lines = f.read().splitlines()
        lines.append("g-test,Test updated,yyy,,")
        csv_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

        problems = adapter.import_csv("grammar_points", csv_path)
        self.assertEqual(
            [p for p in problems if p["level"] == "error"], []
        )
        gp = next(g for g in adapter.grammar_points if g["id"] == "g-test")
        self.assertEqual(gp["practiceItems"], [{"q": "a", "a": "b"}])
        self.assertEqual(gp["title"], "Test updated")


class PublishFlowTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="turna_gui_"))
        self.course_dir = self.tmp / "turkish"
        copy_turkish_course(self.course_dir)

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_detect_changes_after_edit(self) -> None:
        adapter = CourseAdapter()
        adapter.load(self.course_dir)
        adapter.vocab[0]["term"] = "edited"
        changes = adapter.detect_changes()
        self.assertTrue(changes["vocab"])
        self.assertFalse(changes["expressions"])

    def test_version_bump_plan_index_on_section_edit(self) -> None:
        adapter = CourseAdapter()
        adapter.load(self.course_dir)
        cur_version = adapter.index["version"]
        adapter.sections[0]["name"] = "Renamed Section"
        plan = adapter.version_bump_plan()
        self.assertIn("index", plan)
        self.assertEqual(plan["index"], (cur_version, cur_version + 1))
        self.assertNotIn("expressions", plan)

    def test_version_bump_plan_expressions_on_expr_edit(self) -> None:
        adapter = CourseAdapter()
        adapter.load(self.course_dir)
        cur_version = adapter.expressions_version
        adapter.expressions[0]["term"] = "edited expr"
        plan = adapter.version_bump_plan()
        self.assertIn("expressions", plan)
        self.assertEqual(plan["expressions"], (cur_version, cur_version + 1))

    def test_apply_version_bump_persists(self) -> None:
        adapter = CourseAdapter()
        adapter.load(self.course_dir)
        cur_version = adapter.index["version"]
        adapter.sections[0]["name"] = "Renamed Section"
        plan = adapter.version_bump_plan()
        adapter.apply_version_bump(plan)
        result = adapter.save()
        self.assertTrue(result.ok, f"save failed: {result.message}")
        reloaded = CourseAdapter()
        reloaded.load(self.course_dir)
        self.assertEqual(reloaded.index["version"], cur_version + 1)

    def test_release_diff_added_removed(self) -> None:
        adapter = CourseAdapter()
        adapter.load(self.course_dir)

        def _collect_refs(obj: Any, acc: set[str]) -> None:
            if isinstance(obj, str):
                if obj.startswith("w-"):
                    acc.add(obj)
            elif isinstance(obj, list):
                for v in obj:
                    _collect_refs(v, acc)
            elif isinstance(obj, dict):
                for v in obj.values():
                    _collect_refs(v, acc)

        referenced: set[str] = set()
        for section in adapter.sections:
            _collect_refs(section, referenced)
        unreferenced = [w["id"] for w in adapter.vocab if w["id"] not in referenced]
        self.assertGreater(len(unreferenced), 0)
        removed_id = unreferenced[0]
        adapter.delete_resource_entry("vocab", removed_id)
        new_id = adapter.add_resource_entry("vocab")

        diff = adapter.release_diff()
        self.assertIn(removed_id, diff["vocab"]["removed"])
        self.assertIn(new_id, diff["vocab"]["added"])

    def test_audio_manifest_rows_returns_status(self) -> None:
        adapter = CourseAdapter()
        adapter.load(self.course_dir)
        rows = adapter.audio_manifest_rows()
        self.assertIsInstance(rows, list)
        for r in rows:
            self.assertIn("status", r)
            self.assertIn(r["status"], ("present", "missing"))

    def test_release_report_aggregates_all(self) -> None:
        adapter = CourseAdapter()
        adapter.load(self.course_dir)
        adapter.sections[0]["name"] = "Renamed"
        report = adapter.release_report()
        for key in ("changes", "version_bump", "audio_manifest", "diff", "validation"):
            self.assertIn(key, report)
        self.assertTrue(report["changes"]["index"] or report["changes"]["sections"])
        self.assertIn("index", report["version_bump"])
        self.assertIn("ok", report["validation"])

    def test_no_changes_no_bump(self) -> None:
        adapter = CourseAdapter()
        adapter.load(self.course_dir)
        plan = adapter.version_bump_plan()
        self.assertEqual(plan, {})


class InitNewTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="turna_init_"))

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_init_new_creates_course_dir(self) -> None:
        adapter = CourseAdapter()
        course_dir = self.tmp / "new-course"
        adapter.init_new(
            course_dir,
            {
                "display_name": "My Chinese-English Course",
                "language": "en",
                "source_language": "Chinese",
                "section_count": 3,
                "lessons_per_unit": 2,
            },
        )
        self.assertTrue((course_dir / "index.json").exists())
        self.assertTrue((course_dir / "sections" / "section1.json").exists())
        self.assertEqual(adapter.index.get("language"), "en")
        self.assertEqual(len(adapter.sections), 3)
        self.assertIn("w-hello", [w["id"] for w in adapter.vocab])

    def test_is_course_dir(self) -> None:
        adapter = CourseAdapter()
        course_dir = self.tmp / "course"
        adapter.init_new(course_dir, {"language": "en", "section_count": 1})
        self.assertTrue(CourseAdapter.is_course_dir(course_dir))
        self.assertFalse(CourseAdapter.is_course_dir(self.tmp / "missing"))

    def test_init_new_rejects_nonempty_dir(self) -> None:
        adapter = CourseAdapter()
        course_dir = self.tmp / "existing"
        course_dir.mkdir()
        (course_dir / "file.txt").write_text("x", encoding="utf-8")
        with self.assertRaises(FileExistsError):
            adapter.init_new(course_dir, {"language": "en", "section_count": 1})


class ValidateSectionJsonTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="turna_validate_"))
        self.course_dir = self.tmp / "turkish"
        copy_turkish_course(self.course_dir)
        self.adapter = CourseAdapter()
        self.adapter.load(self.course_dir)

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _valid_section(self) -> dict[str, Any]:
        return {
            "id": "ai-travel",
            "name": "AI Travel",
            "description": "",
            "prerequisiteSectionIds": [],
            "units": [
                {
                    "id": "ai-travel-u1",
                    "name": "Unit 1",
                    "description": "",
                    "prerequisiteUnitIds": [],
                    "lessons": [
                        {
                            "id": "ai-travel-u1-l1",
                            "name": "Lesson 1",
                            "description": "",
                            "type": "normal",
                            "template": "intro",
                            "prerequisiteLessonIds": [],
                            "content": {
                                "subLessons": [
                                    {
                                        "id": "ai-travel-u1-l1-sl1",
                                        "name": "Words",
                                        "stages": [
                                            {
                                                "id": "ai-travel-u1-l1-sl1-st1",
                                                "name": "Learn",
                                                "items": [
                                                    {
                                                        "runtimeType": "showWord",
                                                        "id": "sw-1",
                                                        "wordId": "w-merhaba",
                                                        "context": "",
                                                    }
                                                ],
                                            }
                                        ],
                                    }
                                ]
                            },
                        }
                    ],
                }
            ],
        }

    def test_valid_section_returns_empty(self) -> None:
        problems = self.adapter.validate_section_json(self._valid_section())
        self.assertEqual(problems, [])

    def test_missing_units_returns_error(self) -> None:
        section = self._valid_section()
        del section["units"]
        problems = self.adapter.validate_section_json(section)
        self.assertTrue(any("units" in p["message"] for p in problems))

    def test_empty_section_id_returns_error(self) -> None:
        section = self._valid_section()
        section["id"] = ""
        problems = self.adapter.validate_section_json(section)
        self.assertTrue(any("section id" in p["message"] for p in problems))

    def test_duplicate_lesson_id_returns_error(self) -> None:
        section = self._valid_section()
        lesson = section["units"][0]["lessons"][0]
        section["units"][0]["lessons"].append(dict(lesson))
        problems = self.adapter.validate_section_json(section)
        self.assertTrue(
            any("lesson id" in p["message"] and "重复" in p["message"] for p in problems)
        )

    def test_missing_word_id_reference_returns_error(self) -> None:
        section = self._valid_section()
        item = section["units"][0]["lessons"][0]["content"]["subLessons"][0]["stages"][0]["items"][0]
        item["wordId"] = "w-does-not-exist"
        problems = self.adapter.validate_section_json(section)
        self.assertTrue(
            any("missing wordId" in p["message"] or "wordId" in p["message"] for p in problems)
        )

    def test_duplicate_section_id_returns_error(self) -> None:
        section = self._valid_section()
        section["id"] = self.adapter.sections[0]["id"]
        problems = self.adapter.validate_section_json(section)
        self.assertTrue(any(p["path"] == "id" for p in problems))

    def test_check_existing_ids_false_allows_reused_unit_lesson_ids(self) -> None:
        """AI merge paths reuse existing unit/lesson ids on purpose."""
        section = self._valid_section()
        existing_section = self.adapter.sections[0]
        existing_unit = existing_section["units"][0]
        existing_lesson = existing_unit["lessons"][0]
        section["id"] = "ai-edited-section"
        section["units"] = [dict(existing_unit)]
        section["units"][0]["lessons"] = [dict(existing_lesson)]

        problems = self.adapter.validate_section_json(
            section, check_existing_ids=False
        )
        error_messages = [p["message"] for p in problems if p["level"] == "error"]
        self.assertNotIn(
            f"unit id「{existing_unit['id']}」重复或已存在", error_messages
        )
        self.assertNotIn(
            f"lesson id「{existing_lesson['id']}」重复或已存在", error_messages
        )

    def test_check_existing_ids_false_still_catches_local_duplicates(self) -> None:
        section = self._valid_section()
        section["units"].append(dict(section["units"][0]))
        problems = self.adapter.validate_section_json(
            section, check_existing_ids=False
        )
        self.assertTrue(
            any("重复或已存在" in p["message"] for p in problems)
        )

    def test_plan_section_merge_for_new_section_all_add(self) -> None:
        section = self._valid_section()
        plan = self.adapter.plan_section_merge(None, section)
        self.assertIsNone(plan.target_section_id)
        self.assertEqual(len(plan.added_units), len(section["units"]))
        self.assertEqual(plan.replaced_units, [])

    def test_plan_section_merge_detects_replace_and_add(self) -> None:
        existing_section = self.adapter.sections[0]
        existing_unit = existing_section["units"][0]
        existing_lesson = existing_unit["lessons"][0]

        incoming = {
            "id": existing_section["id"],
            "units": [
                {
                    "id": existing_unit["id"],
                    "name": "Updated unit",
                    "lessons": [
                        {
                            "id": existing_lesson["id"],
                            "name": "Updated lesson",
                            "template": "intro",
                            "content": {"subLessons": []},
                        },
                        {
                            "id": "ai-new-lesson",
                            "name": "New lesson",
                            "template": "intro",
                            "content": {"subLessons": []},
                        },
                    ],
                },
                {
                    "id": "ai-new-unit",
                    "name": "New unit",
                    "lessons": [],
                },
            ],
        }
        plan = self.adapter.plan_section_merge(existing_section["id"], incoming)
        self.assertEqual(plan.target_section_id, existing_section["id"])
        self.assertEqual(len(plan.replaced_units), 1)
        self.assertEqual(len(plan.added_units), 1)
        self.assertEqual(
            len(plan.replaced_lessons_by_unit.get(existing_unit["id"], [])),
            1,
        )
        self.assertEqual(
            len(plan.added_lessons_by_unit.get(existing_unit["id"], [])),
            1,
        )


class CourseAdapterResourcePackTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="turna_gui_"))
        self.course_dir = self.tmp / "turkish"
        copy_turkish_course(self.course_dir)
        self.adapter = CourseAdapter()
        self.adapter.load(self.course_dir)

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_export_resource_pack(self) -> None:
        pack_path = self.tmp / "pack.json"
        result = self.adapter.export_resource_pack(pack_path)
        self.assertTrue(result.is_file())
        import json
        data = json.loads(pack_path.read_text(encoding="utf-8"))
        self.assertIn("vocab", data)
        self.assertIn("expressions", data)
        self.assertIn("grammar_points", data)

    def test_import_resource_pack_merge(self) -> None:
        # Export, add a new entry, re-import -> should merge.
        pack_path = self.tmp / "pack.json"
        self.adapter.export_resource_pack(pack_path)
        import json
        data = json.loads(pack_path.read_text(encoding="utf-8"))
        data["vocab"].append({"id": "w_new_pack", "term": "newword", "translation": "新词"})
        pack_path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
        counts = self.adapter.import_resource_pack(pack_path, replace=False)
        self.assertEqual(counts["vocab"], 1)
        ids = [e.get("id") for e in self.adapter.vocab]
        self.assertIn("w_new_pack", ids)

    def test_import_resource_pack_replace(self) -> None:
        pack_path = self.tmp / "pack.json"
        import json
        data = {"vocab": [{"id": "w_only", "term": "only"}], "expressions": [], "grammar_points": []}
        pack_path.write_text(json.dumps(data), encoding="utf-8")
        counts = self.adapter.import_resource_pack(pack_path, replace=True)
        self.assertEqual(counts["vocab"], 1)
        self.assertEqual(len(self.adapter.vocab), 1)
        self.assertEqual(self.adapter.vocab[0]["id"], "w_only")


class CourseAdapterDuplicateTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="turna_gui_"))
        self.course_dir = self.tmp / "turkish"
        copy_turkish_course(self.course_dir)
        self.adapter = CourseAdapter()
        self.adapter.load(self.course_dir)

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_detects_existing_duplicates(self) -> None:
        """The Turkish course has a known cross-table duplicate (nasılsın?)."""
        dupes = self.adapter.detect_duplicates()
        # At least one duplicate should be found.
        self.assertGreaterEqual(len(dupes), 1)
        terms = [d["term"] for d in dupes]
        self.assertIn("nasılsın?", terms)

    def test_detects_cross_table_duplicate(self) -> None:
        # Add a vocab entry and an expression with the same term.
        self.adapter.vocab.append({"id": "w_dupe", "term": "hello", "translation": "你好"})
        self.adapter.expressions.append({"id": "e_dupe", "source": "hello", "translation": "你好"})
        dupes = self.adapter.detect_duplicates()
        self.assertGreaterEqual(len(dupes), 1)
        dupe_terms = [d["term"] for d in dupes]
        self.assertIn("hello", dupe_terms)


class CourseAdapterGitSyncTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="turna_gui_"))
        self.course_dir = self.tmp / "turkish"
        copy_turkish_course(self.course_dir)
        self.adapter = CourseAdapter()
        self.adapter.load(self.course_dir)
        self.git_dir = self.tmp / "gitclone"
        self.git_dir.mkdir()

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_sync_merges_git_into_local(self) -> None:
        import json
        # Git dir has a vocab entry not in local, in the wrapped on-disk format
        # ({"version":1,"language":..,"words":[...]}). Sync must read the list
        # out of the wrapper, not treat the whole object as an empty list.
        git_vocab = {"version": 1, "language": "tr",
                     "words": [{"id": "w_from_git", "term": "gitword", "translation": "git词"}]}
        (self.git_dir / "vocab.json").write_text(
            json.dumps(git_vocab, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        result = self.adapter.sync_resources_with_git(self.git_dir, "tr")
        self.assertIn("vocab", result)
        ids = [e.get("id") for e in self.adapter.vocab]
        self.assertIn("w_from_git", ids)

    def test_sync_writes_back_to_git_preserving_wrapper(self) -> None:
        import json
        # Local has an entry not in git. After sync the git file must still
        # be the wrapped object form with version/language metadata intact
        # (regression guard for B10: previously the wrapper was destroyed
        # and replaced with a bare list).
        self.adapter.vocab.append({"id": "w_local_only", "term": "localword"})
        self.adapter.sync_resources_with_git(self.git_dir, "tr")
        git_data = json.loads((self.git_dir / "vocab.json").read_text(encoding="utf-8"))
        self.assertIsInstance(git_data, dict)
        self.assertEqual(git_data.get("version"), 1)
        self.assertEqual(git_data.get("language"), "tr")
        git_ids = [e.get("id") for e in git_data.get("words", [])]
        self.assertIn("w_local_only", git_ids)

    def test_sync_accepts_legacy_bare_list_git_file(self) -> None:
        import json
        # Backward compat: a legacy bare-list vocab.json (pre-wrapper) must
        # still be merged correctly and rewritten as the wrapped form.
        git_vocab = [{"id": "w_legacy", "term": "legacyword"}]
        (self.git_dir / "vocab.json").write_text(
            json.dumps(git_vocab, ensure_ascii=False), encoding="utf-8"
        )
        self.adapter.sync_resources_with_git(self.git_dir, "tr")
        ids = [e.get("id") for e in self.adapter.vocab]
        self.assertIn("w_legacy", ids)
        git_data = json.loads((self.git_dir / "vocab.json").read_text(encoding="utf-8"))
        self.assertIsInstance(git_data, dict)
        self.assertIn("w_legacy", [e.get("id") for e in git_data.get("words", [])])


if __name__ == "__main__":
    unittest.main()