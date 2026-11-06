from __future__ import annotations

import json
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.course_preview.document import build_document
from src.backend.course_preview.render import render_lesson, render_outline
from src.backend.course_preview.server import create_server
from src.backend.course_preview.store import PreviewStore


def _item(item_id: str, runtime_type: str, **values):
    return {"id": item_id, "runtimeType": runtime_type, **values}


def sample_section() -> dict:
    return {
        "id": "preview-section",
        "name": "问候与点餐",
        "description": "用于网页预览的完整题型样例",
        "words": [{"id": "w-merhaba", "term": "merhaba", "translation": "你好"}],
        "units": [
            {
                "id": "u-intro",
                "name": "入门",
                "lessons": [
                    {
                        "id": "l-intro",
                        "name": "认识问候",
                        "template": "intro",
                        "content": {
                            "subLessons": [
                                {
                                    "id": "sub-1",
                                    "name": "词语与练习",
                                    "stages": [
                                        {
                                            "id": "stage-1",
                                            "items": [
                                                _item("show-1", "showWord", wordId="w-merhaba", context="Merhaba, Ayşe."),
                                                _item(
                                                    "mc-1",
                                                    "multipleChoice",
                                                    prompt="哪一个表示“你好”？",
                                                    options=["merhaba", "ekmek", "su"],
                                                    correctIndex=0,
                                                ),
                                                {
                                                    "runtimeType": "fillBlank",
                                                    "sentence": "___ , nasılsın?",
                                                    "answer": "Merhaba",
                                                },
                                                _item(
                                                    "multi-1",
                                                    "multiSelect",
                                                    prompt="选择问候语",
                                                    options=["merhaba", "güle güle", "ekmek"],
                                                    correctIndices=[0, 1],
                                                ),
                                            ],
                                        }
                                    ],
                                }
                            ]
                        },
                    },
                    {
                        "id": "l-practice",
                        "name": "句子练习",
                        "template": "practice",
                        "content": {
                            "stages": [
                                {
                                    "id": "stage-practice",
                                    "items": [
                                        _item(
                                            "tr-1",
                                            "translateSentence",
                                            source="你好，我叫 Ayşe。",
                                            expected="Merhaba, ben Ayşe.",
                                        ),
                                        _item(
                                            "reorder-1",
                                            "reorderSentence",
                                            scrambled=["Ayşe", "ben", "Merhaba"],
                                            correct=["Merhaba", "ben", "Ayşe"],
                                        ),
                                        _item("read-1", "readAloud", targetText="Merhaba, ben Ayşe."),
                                        _item("card-1", "ankiCard", front="merhaba", back="你好"),
                                        _item(
                                            "html-1",
                                            "ankiHtmlCard",
                                            frontHtml="<b>merhaba</b>",
                                            backHtml="<script>alert('x')</script>你好",
                                        ),
                                    ],
                                }
                            ]
                        },
                    },
                    {
                        "id": "l-listening",
                        "name": "听力",
                        "template": "listening",
                        "content": {
                            "listeningPhases": [
                                {
                                    "id": "phase-1",
                                    "items": [
                                        _item(
                                            "listen-1",
                                            "listenAndPick",
                                            prompt="你听到了什么？",
                                            audioAsset="audio/merhaba.mp3",
                                            options=["merhaba", "tamam"],
                                            correctIndex=1,
                                        ),
                                        _item(
                                            "type-1",
                                            "typeTheWord",
                                            prompt="写下听到的词",
                                            expected="merhaba",
                                        ),
                                        _item(
                                            "only-1",
                                            "listenOnly",
                                            transcript="Merhaba, nasılsın?",
                                        ),
                                    ],
                                }
                            ]
                        },
                    },
                    {
                        "id": "l-reading",
                        "name": "阅读",
                        "template": "reading",
                        "content": {
                            "readingPassage": {
                                "title": "Kafede",
                                "paragraphs": ["Ayşe bir kafeye gider.", "Bir çay ister."],
                            },
                            "stages": [
                                {
                                    "id": "reading-stage",
                                    "items": [
                                        _item(
                                            "rmcq-1",
                                            "readingMcq",
                                            prompt="Ayşe 去了哪里？",
                                            options=["咖啡馆", "学校"],
                                            correctIndex=0,
                                        ),
                                        _item(
                                            "rtf-1",
                                            "readingTrueFalse",
                                            statement="Ayşe 想要茶。",
                                            answer=True,
                                        ),
                                        _item(
                                            "rsa-1",
                                            "readingShortAnswer",
                                            prompt="Ayşe 想要什么？",
                                            expectedAnswer="Bir çay.",
                                        ),
                                    ],
                                }
                            ]
                        },
                    },
                ],
            }
        ],
    }


class PreviewDocumentTest(unittest.TestCase):
    def test_expands_nested_content_and_answers(self) -> None:
        document = build_document(sample_section())

        self.assertEqual(len(document.lessons), 4)
        self.assertEqual(document.item_count, 15)
        self.assertEqual(document.lessons[0].items[0].prompt, "merhaba — 你好")
        self.assertEqual(document.lessons[0].items[1].answer, "merhaba")
        self.assertEqual(document.lessons[1].items[1].answer, "Merhaba / ben / Ayşe")
        self.assertEqual(document.lessons[2].items[0].answer, "tamam")
        self.assertEqual(document.lessons[3].items[1].answer, "正确")
        self.assertEqual(len(document.lessons[3].context), 3)

    def test_item_keys_and_lesson_refs_survive_reordering(self) -> None:
        first = sample_section()
        second = sample_section()
        lessons = second["units"][0]["lessons"]
        lessons.reverse()
        first_doc = build_document(first)
        second_doc = build_document(second)

        first_keys = {item.key for lesson in first_doc.lessons for item in lesson.items}
        second_keys = {item.key for lesson in second_doc.lessons for item in lesson.items}
        self.assertEqual(first_keys, second_keys)
        self.assertEqual(
            {lesson.lesson_id: lesson.ref for lesson in first_doc.lessons},
            {lesson.lesson_id: lesson.ref for lesson in second_doc.lessons},
        )

    def test_invalid_answers_and_unknown_types_degrade(self) -> None:
        section = sample_section()
        items = section["units"][0]["lessons"][0]["content"]["subLessons"][0]["stages"][0]["items"]
        items[1]["correctIndex"] = 99
        items.append({"runtimeType": "futureType", "prompt": "未来题"})
        document = build_document(section)

        self.assertEqual(document.lessons[0].items[1].answer, "答案配置无效")
        self.assertIn("未知题型", document.lessons[0].items[-1].type_label)

    def test_empty_or_broken_section_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            build_document({"id": "empty", "units": []})
        with self.assertRaises(ValueError):
            build_document({"id": "broken"})

    def test_render_escapes_draft_html_and_builds_feedback_forms(self) -> None:
        section = sample_section()
        lesson_data = section["units"][0]["lessons"][1]
        lesson_data["content"]["stages"][0]["items"][0]["source"] = "<script>alert(1)</script>"
        document = build_document(section)
        store_dir = tempfile.TemporaryDirectory()
        self.addCleanup(store_dir.cleanup)
        meta = PreviewStore(store_dir.name).publish(section)
        page = render_lesson(document, document.lessons[1], meta)
        outline = render_outline(document, meta)

        self.assertNotIn("<script>alert", page)
        self.assertIn("&lt;script&gt;alert(1)&lt;/script&gt;", page)
        self.assertIn("反馈这道题", page)
        self.assertIn("给整节课程留言", outline)
        self.assertIn('method="post"', page)


class PreviewStoreTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.store = PreviewStore(self.tmp.name)

    def test_publish_is_idempotent_and_reloads_after_restart(self) -> None:
        first = self.store.publish(sample_section())
        second = self.store.publish(sample_section(), preview_id=first["preview_id"])
        changed = sample_section()
        changed["name"] = "第二版"
        third = self.store.publish(changed, preview_id=first["preview_id"])
        reopened = PreviewStore(self.tmp.name).meta(first["preview_id"])

        self.assertEqual(first["current_revision"], 1)
        self.assertTrue(second["unchanged"])
        self.assertEqual(second["current_revision"], 1)
        self.assertEqual(third["current_revision"], 2)
        self.assertEqual(reopened["current_revision"], 2)
        self.assertEqual(reopened["title"], "第二版")

    def test_feedback_keeps_question_snapshot_and_old_revision(self) -> None:
        meta = self.store.publish(sample_section())
        document = build_document(sample_section())
        item = document.lessons[0].items[1]
        first = self.store.add_feedback(
            meta["preview_id"],
            revision=1,
            item_key=item.key,
            category="answer",
            reviewer="老师",
            message="这里建议换一个干扰项。",
        )
        changed = sample_section()
        changed["units"][0]["lessons"].pop(1)
        self.store.publish(changed, preview_id=meta["preview_id"])
        self.store.add_feedback(
            meta["preview_id"],
            revision=2,
            message="整节第二版的意见。",
        )
        entries = self.store.feedback(meta["preview_id"])

        self.assertEqual(first["question"]["answer"], "merhaba")
        self.assertEqual([entry["revision"] for entry in entries], [1, 2])
        self.assertEqual(entries[0]["item_key"], item.key)
        self.assertIsNone(entries[1]["question"])

    def test_feedback_validation(self) -> None:
        meta = self.store.publish(sample_section())
        with self.assertRaises(ValueError):
            self.store.add_feedback(meta["preview_id"], revision=1, message="")
        with self.assertRaises(ValueError):
            self.store.add_feedback(meta["preview_id"], revision=1, message="x" * 4001)
        with self.assertRaises(ValueError):
            self.store.add_feedback(meta["preview_id"], revision=1, item_key="bad", message="错路径")
        with self.assertRaises(ValueError):
            self.store.add_feedback(meta["preview_id"], revision=9, message="错版本")
        with self.assertRaises(ValueError):
            self.store.meta("../secret")


class PreviewHttpTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.store = PreviewStore(self.tmp.name)
        self.meta = self.store.publish(sample_section())
        self.server = create_server("127.0.0.1", 0, self.store, public_base="")
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base = f"http://127.0.0.1:{self.server.server_address[1]}"
        self.addCleanup(self._stop)

    def _stop(self) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=3)

    def _url(self, path: str) -> str:
        return f"{self.base}{path}"

    def _get(self, path: str):
        return urllib.request.urlopen(self._url(path), timeout=5)

    def _post(self, preview_id: str, **values) -> object:
        data = urllib.parse.urlencode(values).encode("utf-8")
        request = urllib.request.Request(
            self._url(f"/p/{preview_id}/feedback"),
            data=data,
            method="POST",
        )
        return urllib.request.urlopen(request, timeout=5)

    def test_real_http_preview_and_feedback_roundtrip(self) -> None:
        preview_id = self.meta["preview_id"]
        document = build_document(sample_section())
        lesson = document.lessons[0]
        item = lesson.items[1]
        with self._get("/healthz") as response:
            self.assertEqual(json.load(response), {"ok": True})
        with self._get(f"/p/{preview_id}/") as response:
            outline = response.read().decode("utf-8")
            self.assertEqual(response.headers["Cache-Control"], "no-store")
            self.assertIn("noindex", response.headers["X-Robots-Tag"])
            self.assertIn("script-src 'none'", response.headers["Content-Security-Policy"])
        self.assertIn("认识问候", outline)
        with self._get(f"/p/{preview_id}/lesson/{lesson.ref}") as response:
            page = response.read().decode("utf-8")
        self.assertIn("哪一个表示", page)

        response = self._post(
            preview_id,
            revision="1",
            item_key=item.key,
            category="answer",
            reviewer="网页老师",
            message="请调整这个选项。",
        )
        response.close()
        response = self._post(
            preview_id,
            revision="1",
            category="other",
            reviewer="",
            message="整节再简单一点。",
        )
        response.close()
        entries = self.store.feedback(preview_id)

        self.assertEqual(len(entries), 2)
        self.assertEqual(entries[0]["question"]["key"], item.key)
        self.assertEqual(entries[0]["reviewer"], "网页老师")
        self.assertEqual(entries[1]["message"], "整节再简单一点。")

    def test_course_catalog_links_to_sections_and_keeps_placeholders_offline(self) -> None:
        course = self.store.publish_course(
            {
                "course_id": "demo-course",
                "title": "演示 <script>alert(1)</script>",
                "entries": [
                    {"section_id": "preview-section", "section": sample_section()},
                    {
                        "section_id": "future-section",
                        "name": "后续章节",
                        "section": None,
                    },
                ],
            }
        )
        preview_id = course["entries"][0]["preview_id"]

        with self._get("/") as response:
            catalog = response.read().decode("utf-8")
            self.assertEqual(response.headers["X-Robots-Tag"], "noindex, nofollow, noarchive")
        with self._get("/c/demo-course/") as response:
            outline = response.read().decode("utf-8")
        with self._get(f"/p/{preview_id}/") as response:
            section = response.read().decode("utf-8")

        self.assertIn("演示 &lt;script&gt;alert(1)&lt;/script&gt;", catalog)
        self.assertNotIn("<script>alert(1)</script>", catalog)
        self.assertNotIn(self.meta["preview_id"], catalog)
        self.assertIn(f'/p/{preview_id}/', outline)
        self.assertIn("待施工", outline)
        self.assertIn("后续章节", outline)
        self.assertIn('class="brand" href="/c/demo-course/"', section)
        self.assertIn("课程预览", section)

    def test_http_rejects_bad_requests_and_honeypot_does_not_store(self) -> None:
        preview_id = self.meta["preview_id"]
        with self.assertRaises(urllib.error.HTTPError) as missing:
            self._get("/p/not-a-real-preview/")
        self.assertEqual(missing.exception.code, 400)
        with self.assertRaises(urllib.error.HTTPError) as too_long:
            self._post(preview_id, revision="1", message="x" * 17_000)
        self.assertIn(too_long.exception.code, {400, 413})
        response = self._post(
            preview_id,
            revision="1",
            category="other",
            message="spam",
            website="bot-filled",
        )
        response.close()
        self.assertEqual(self.store.feedback(preview_id), [])

    def test_http_rate_limit(self) -> None:
        self.server.rate_limit = 1
        preview_id = self.meta["preview_id"]
        response = self._post(preview_id, revision="1", message="第一条")
        response.close()
        with self.assertRaises(urllib.error.HTTPError) as limited:
            self._post(preview_id, revision="1", message="第二条")
        self.assertEqual(limited.exception.code, 429)
        self.assertEqual(len(self.store.feedback(preview_id)), 1)


if __name__ == "__main__":
    unittest.main()
