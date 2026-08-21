"""E4/M-01 attachments: pure snapshot helpers + Context injection + routing.

Red line under test (experienceai.md §14.5.3): raw extracted text / base64
never enters the closed snapshot shape.
"""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.experience.attachments import (  # noqa: E402
    ATTACHMENT_KEYS,
    MAX_ATTACHMENTS,
    build_attachment_snapshot,
    format_attachments_line,
    normalize_attachments,
)
from src.backend.experience import build_experience_context, local_suggestions  # noqa: E402
from src.backend.experience.actions import (  # noqa: E402
    DANGEROUS_ACTION_IDS,
    get_action,
)
from src.backend.experience.intent_router import route_intent  # noqa: E402
from tests._qtapp import _App as _TestApp  # noqa: E402

_SECRET_TEXT = "绝密讲义全文-不应出现在快照里"
_SECRET_B64 = "QUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVo="  # gitleaks-style payload


def _rec(name: str, content: dict) -> SimpleNamespace:
    return SimpleNamespace(
        temp_path=Path("/tmp/x"),
        original_name=name,
        content=content,
    )


def _text_rec(name: str = "讲义.pdf", text: str = _SECRET_TEXT) -> SimpleNamespace:
    return _rec(name, {"type": "text", "text": text})


def _image_rec(name: str = "图.png") -> SimpleNamespace:
    return _rec(
        name,
        {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{_SECRET_B64}"}},
    )


def _adapter():
    return SimpleNamespace(
        sections=[],
        vocab=[],
        expressions=[],
        grammar_points=[],
        index={"language": "tr"},
        course_dir=None,
    )


class BuildSnapshotTest(unittest.TestCase):
    def test_kind_detection(self) -> None:
        snaps = build_attachment_snapshot(
            [
                _text_rec("a.pdf", "t1"),
                _text_rec("b.docx", "t2"),
                _text_rec("c.doc", "t3"),
                _text_rec("d.txt", "t4"),
                _text_rec("e.md", "t5"),
                _text_rec("f.xyz", "t6"),
                _image_rec(),
            ]
        )
        kinds = [s["kind"] for s in snaps]
        self.assertEqual(kinds, ["pdf", "word", "word", "text", "text", "other", "image"])

    def test_char_count_text_vs_image(self) -> None:
        snaps = build_attachment_snapshot([_text_rec(text="abcd"), _image_rec()])
        self.assertEqual(snaps[0]["char_count"], 4)
        self.assertEqual(snaps[1]["char_count"], 0)

    def test_ref_id_stable_and_content_derived(self) -> None:
        a = build_attachment_snapshot([_text_rec("x.pdf", text="hello")])
        b = build_attachment_snapshot([_text_rec("y.pdf", text="hello")])
        c = build_attachment_snapshot([_text_rec("x.pdf", text="world")])
        self.assertEqual(a[0]["ref_id"], b[0]["ref_id"])  # same content → same id
        self.assertNotEqual(a[0]["ref_id"], c[0]["ref_id"])
        self.assertTrue(a[0]["ref_id"].startswith("att-"))

    def test_dedup_same_content(self) -> None:
        snaps = build_attachment_snapshot([_text_rec(text="same"), _text_rec("b.pdf", "same")])
        self.assertEqual(len(snaps), 1)

    def test_cap_and_broken_items(self) -> None:
        many = [_text_rec(f"f{i}.pdf", text=f"t{i}") for i in range(MAX_ATTACHMENTS + 10)]
        many.extend([None, object(), _rec("", {"type": "text", "text": "x"})])
        snaps = build_attachment_snapshot(many)
        self.assertEqual(len(snaps), MAX_ATTACHMENTS)

    def test_name_is_basename(self) -> None:
        snaps = build_attachment_snapshot([_text_rec("/home/user/secret/讲义.pdf")])
        self.assertEqual(snaps[0]["name"], "讲义.pdf")

    def test_closed_keys(self) -> None:
        snaps = build_attachment_snapshot([_text_rec()])
        self.assertEqual(set(snaps[0].keys()), ATTACHMENT_KEYS)

    def test_never_raises(self) -> None:
        self.assertEqual(build_attachment_snapshot(None), [])
        self.assertEqual(build_attachment_snapshot("junk"), [])  # type: ignore[arg-type]

    def test_raw_content_never_leaks(self) -> None:
        snaps = build_attachment_snapshot([_text_rec(), _image_rec()])
        blob = json.dumps(snaps, ensure_ascii=False)
        self.assertNotIn(_SECRET_TEXT, blob)
        self.assertNotIn(_SECRET_B64, blob)
        self.assertNotIn("base64", blob)


class NormalizeTest(unittest.TestCase):
    def test_round_trip_and_type_coercion(self) -> None:
        raw = [
            {
                "ref_id": "att-x",
                "name": "a.pdf",
                "kind": "PDF",
                "char_count": "12",
                "preview_hash": "x",
                "source": "workshop",
                "extra_ignored": True,
            }
        ]
        out = normalize_attachments(raw)
        self.assertEqual(len(out), 1)
        self.assertEqual(set(out[0].keys()), ATTACHMENT_KEYS)
        self.assertEqual(out[0]["kind"], "pdf")
        self.assertEqual(out[0]["char_count"], 12)
        self.assertNotIn("extra_ignored", out[0])

    def test_bad_input(self) -> None:
        self.assertEqual(normalize_attachments(None), [])
        self.assertEqual(normalize_attachments("junk"), [])
        self.assertEqual(normalize_attachments([None, 1, {}, {"name": ""}]), [])

    def test_unknown_kind_and_missing_ids(self) -> None:
        out = normalize_attachments([{"name": "a.bin", "kind": "weird"}])
        self.assertEqual(out, [])  # no ref_id/preview_hash → dropped
        out2 = normalize_attachments([{"name": "a.bin", "kind": "weird", "preview_hash": "h1"}])
        self.assertEqual(out2[0]["kind"], "other")
        self.assertEqual(out2[0]["ref_id"], "att-h1")


class FormatLineTest(unittest.TestCase):
    def test_line_with_counts(self) -> None:
        snaps = build_attachment_snapshot(
            [_text_rec("a.pdf", text="t1"), _text_rec("b.pdf", text="t2"), _image_rec()]
        )
        line = format_attachments_line(snaps)
        self.assertIn("附件 3", line)
        self.assertIn("PDF×2", line)
        self.assertIn("图×1", line)

    def test_empty(self) -> None:
        self.assertEqual(format_attachments_line([]), "")
        self.assertEqual(format_attachments_line(None), "")


class ContextAndSuggestionTest(unittest.TestCase):
    def test_context_carries_normalized_attachments(self) -> None:
        ctx = build_experience_context(
            _adapter(),
            include_quality=False,
            include_hygiene=False,
            attachments=[{"name": "a.pdf", "preview_hash": "h", "kind": "pdf", "junk": 1}],
        )
        self.assertEqual(len(ctx.attachments), 1)
        self.assertEqual(set(ctx.attachments[0].keys()), ATTACHMENT_KEYS)

    def test_context_bad_input_safe(self) -> None:
        ctx = build_experience_context(
            _adapter(),
            include_quality=False,
            include_hygiene=False,
            attachments="junk",  # type: ignore[arg-type]
        )
        self.assertEqual(ctx.attachments, [])

    def test_suggestion_p2_with_closed_scope(self) -> None:
        snaps = build_attachment_snapshot([_text_rec(), _image_rec()])
        ctx = build_experience_context(
            _adapter(),
            include_quality=False,
            include_hygiene=False,
            attachments=snaps,
        )
        sugs = local_suggestions(ctx, limit=3)
        hit = [s for s in sugs if s["action_id"] == "attachment.open_in_workshop"]
        self.assertEqual(len(hit), 1)
        self.assertEqual(hit[0]["priority"], 2)
        self.assertIn("2 个附件", hit[0]["title"])
        scope = hit[0]["scope"]
        self.assertEqual(scope["count"], 2)
        self.assertEqual(len(scope["ref_ids"]), 2)
        blob = json.dumps(scope, ensure_ascii=False)
        self.assertNotIn(_SECRET_TEXT, blob)
        self.assertNotIn("讲义", blob)  # scope carries ids/count only, no names

    def test_no_suggestion_without_attachments(self) -> None:
        ctx = build_experience_context(
            _adapter(), include_quality=False, include_hygiene=False
        )
        sugs = local_suggestions(ctx, limit=3)
        self.assertFalse(any(s["action_id"] == "attachment.open_in_workshop" for s in sugs))


class ShellInjectionTest(unittest.TestCase):
    def setUp(self) -> None:
        _TestApp.get()
        from src.application.experience_shell import ExperienceShell

        self.shell = ExperienceShell(debounce_ms=0)
        self.shell.set_adapter(_adapter())

    def test_round_trip_through_rebuild(self) -> None:
        snaps = build_attachment_snapshot([_text_rec()])
        self.shell.set_attachments(snaps)
        ctx = self.shell.rebuild_now()
        self.assertIsNotNone(ctx)
        assert ctx is not None
        self.assertEqual(len(ctx.attachments), 1)
        self.assertEqual(ctx.attachments[0]["name"], "讲义.pdf")

    def test_focus_fast_path_preserves_attachments(self) -> None:
        snaps = build_attachment_snapshot([_text_rec()])
        self.shell.set_attachments(snaps)
        self.shell.rebuild_now()
        self.shell.invalidate_focus()
        ctx = self.shell.context
        self.assertIsNotNone(ctx)
        assert ctx is not None
        self.assertEqual(len(ctx.attachments), 1)

    def test_close_course_clears(self) -> None:
        self.shell.set_attachments(build_attachment_snapshot([_text_rec()]))
        self.shell.rebuild_now()
        self.shell.set_adapter(None)
        self.assertEqual(self.shell._attachments, [])
        self.assertIsNone(self.shell.context)

    def test_set_none_clears(self) -> None:
        self.shell.set_attachments(build_attachment_snapshot([_text_rec()]))
        self.shell.set_attachments(None)
        ctx = self.shell.rebuild_now()
        assert ctx is not None
        self.assertEqual(ctx.attachments, [])


class ContractRoutingTest(unittest.TestCase):
    def test_action_spec_readonly(self) -> None:
        spec = get_action("attachment.open_in_workshop")
        self.assertIsNotNone(spec)
        assert spec is not None
        self.assertTrue(spec.implemented)
        self.assertFalse(spec.needs_confirm)
        self.assertNotIn("attachment.open_in_workshop", DANGEROUS_ACTION_IDS)

    def test_slash_route(self) -> None:
        intent = route_intent("/attachments")
        self.assertIsNotNone(intent)
        assert intent is not None
        self.assertEqual(intent.action_id, "attachment.open_in_workshop")
        self.assertEqual(intent.confidence, 1.0)


if __name__ == "__main__":
    unittest.main()
