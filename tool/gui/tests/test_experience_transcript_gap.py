"""v4.39 K-17 listening.transcript_gap tests (detector + gaps + fill + routing)."""
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from tests._qtapp import qt_app  # noqa: E402


def _listen_section(*, audio="", transcript="", item_id="i1", template="listening"):
    item = {"id": item_id, "runtimeType": "listenAndPick"}
    if audio:
        item["audioAsset"] = audio
    if transcript:
        item["transcript"] = transcript
    return {
        "id": "s1",
        "level": "A1",
        "words": [],
        "units": [{"id": "u1", "lessons": [
            {"id": "l1", "template": template,
             "content": {"stages": [{"id": "st1", "items": [item]}]}}
        ]}],
    }


class ScoreAudioReadyTest(unittest.TestCase):
    def test_both_absent_is_missing_audio(self) -> None:
        from src.backend.content_quality import score_section

        r = score_section(_listen_section(), level="A1")
        kinds = {str(getattr(i, "gap_kind", "")) for i in r.issues if i.dimension == "audio_ready"}
        self.assertIn("missing_audio", kinds)
        self.assertNotIn("missing_transcript", kinds)

    def test_audio_only_is_missing_transcript(self) -> None:
        from src.backend.content_quality import score_section

        r = score_section(_listen_section(audio="a.mp3"), level="A1")
        kinds = {str(getattr(i, "gap_kind", "")) for i in r.issues if i.dimension == "audio_ready"}
        self.assertIn("missing_transcript", kinds)
        self.assertNotIn("missing_audio", kinds)

    def test_both_present_no_gap(self) -> None:
        from src.backend.content_quality import score_section

        r = score_section(_listen_section(audio="a.mp3", transcript="merhaba"), level="A1")
        assert not [i for i in r.issues if i.dimension == "audio_ready"]

    def test_empty_phase_has_gap_kind(self) -> None:
        from src.backend.content_quality import score_section

        section = {
            "id": "s1", "level": "A1", "words": [],
            "units": [{"id": "u1", "lessons": [
                {"id": "l1", "template": "listening",
                 "content": {"listeningPhases": [{"id": "p1", "items": []}]}}
            ]}],
        }
        r = score_section(section, level="A1")
        kinds = {str(getattr(i, "gap_kind", "")) for i in r.issues if i.dimension == "audio_ready"}
        self.assertIn("empty_phase", kinds)


class ListeningGapsFromReportTest(unittest.TestCase):
    def test_gap_kind_priority_over_item_id(self) -> None:
        from src.backend.experience.context_bus import _listening_gaps_from_report

        report = SimpleNamespace(issues=[
            SimpleNamespace(dimension="audio_ready", lesson_id="l1",
                            item_id="i1", message="m", gap_kind="missing_transcript"),
            SimpleNamespace(dimension="audio_ready", lesson_id="l1",
                            item_id="", message="m", gap_kind="empty_phase"),
            # legacy issue without gap_kind → infer missing_audio (item_id present)
            SimpleNamespace(dimension="audio_ready", lesson_id="l1",
                            item_id="i2", message="m", gap_kind=""),
        ])
        gaps = _listening_gaps_from_report(report, section_id="s1")
        kinds = [g["kind"] for g in gaps]
        self.assertEqual(kinds, ["missing_transcript", "empty_phase", "missing_audio"])
        # closed-set dict shape
        for g in gaps:
            self.assertEqual(set(g.keys()), {"lesson_id", "item_id", "kind", "section_id", "message"})

    def test_other_dimensions_ignored(self) -> None:
        from src.backend.experience.context_bus import _listening_gaps_from_report

        report = SimpleNamespace(issues=[SimpleNamespace(dimension="balance", lesson_id="l1", item_id="i1", message="m", gap_kind="")])
        self.assertEqual(_listening_gaps_from_report(report, section_id="s1"), [])


class FillListeningGapsTest(unittest.TestCase):
    def _config(self):
        return SimpleNamespace(select_model=lambda kind: "m")

    def test_audio_only_item_collected_and_transcript_filled(self) -> None:
        import src.backend.ai_generator as ai_gen

        from src.backend.ai_generator import fill_listening_gaps

        orig = ai_gen.request_chat

        def fake_chat(config, messages, **kw):
            return {"choices": [{"message": {"content": '{"entries":[{"id":"i1","audioAsset":"NEW","transcript":"merhaba"}]}'}}]}

        ai_gen.request_chat = fake_chat  # type: ignore[assignment]
        try:
            section = _listen_section(audio="a.mp3")  # audio present, transcript absent
            result = fill_listening_gaps(self._config(), section)
            item = result["units"][0]["lessons"][0]["content"]["stages"][0]["items"][0]
            # existing audio NOT overwritten by model's "NEW"
            self.assertEqual(item["audioAsset"], "a.mp3")
            # transcript filled
            self.assertEqual(item["transcript"], "merhaba")
        finally:
            ai_gen.request_chat = orig

    def test_both_absent_item_filled(self) -> None:
        import src.backend.ai_generator as ai_gen

        from src.backend.ai_generator import fill_listening_gaps

        orig = ai_gen.request_chat

        def fake_chat(config, messages, **kw):
            return {"choices": [{"message": {"content": '{"entries":[{"id":"i1","audioAsset":"aud","transcript":"tr"}]}'}}]}

        ai_gen.request_chat = fake_chat  # type: ignore[assignment]
        try:
            section = _listen_section()  # both absent
            result = fill_listening_gaps(self._config(), section)
            item = result["units"][0]["lessons"][0]["content"]["stages"][0]["items"][0]
            self.assertEqual(item["audioAsset"], "aud")
            self.assertEqual(item["transcript"], "tr")
            self.assertEqual(item["id"], "i1")
        finally:
            ai_gen.request_chat = orig


class SuggestionTest(unittest.TestCase):
    def test_transcript_gap_suggestion_only_when_present(self) -> None:
        from src.backend.experience.context_bus import ExperienceContext, local_suggestions

        ctx = ExperienceContext(
            listening_gaps=[
                {"lesson_id": "l1", "item_id": "i1", "kind": "missing_transcript", "section_id": "s1", "message": "m"},
            ],
            lesson_count=1,
        )
        sug = [s for s in local_suggestions(ctx, limit=5) if s["action_id"] == "listening.transcript_gap"]
        self.assertEqual(len(sug), 1)
        self.assertEqual(sug[0]["scope"]["count"], 1)
        # closed-set scope: no transcript/audio raw
        for key in ("audioAsset", "transcript"):
            self.assertNotIn(key, sug[0]["scope"])

    def test_no_suggestion_without_transcript_gap(self) -> None:
        from src.backend.experience.context_bus import ExperienceContext, local_suggestions

        ctx = ExperienceContext(
            listening_gaps=[
                {"lesson_id": "l1", "item_id": "i1", "kind": "missing_audio", "section_id": "s1", "message": "m"},
            ],
            lesson_count=1,
        )
        sug = [s for s in local_suggestions(ctx, limit=5) if s["action_id"] == "listening.transcript_gap"]
        self.assertEqual(sug, [])

    def test_fill_gaps_suggestion_still_present_regression(self) -> None:
        # Regression guard: existing listening.fill_gaps suggestion not broken.
        from src.backend.experience.context_bus import ExperienceContext, local_suggestions

        ctx = ExperienceContext(
            listening_gaps=[
                {"lesson_id": "l1", "item_id": "i1", "kind": "missing_audio", "section_id": "s1", "message": "m"},
            ],
            lesson_count=1,
        )
        ids = [s["action_id"] for s in local_suggestions(ctx, limit=5)]
        self.assertIn("listening.fill_gaps", ids)


class RoutingContractTest(unittest.TestCase):
    def test_slash_exact(self) -> None:
        from src.backend.experience.intent_router import route_intent

        i = route_intent("/transcript-gap")
        self.assertIsNotNone(i)
        self.assertEqual(i.action_id, "listening.transcript_gap")
        self.assertEqual(i.confidence, 1.0)

    def test_keyword(self) -> None:
        from src.backend.experience.intent_router import route_intent

        self.assertEqual(route_intent("transcript 缺口").action_id, "listening.transcript_gap")

    def test_golden_has_transcript_gap(self) -> None:
        import json

        path = Path(__file__).resolve().parent / "ai_goldens" / "intent_routes.json"
        rows = json.loads(path.read_text(encoding="utf-8"))
        self.assertTrue(any(r.get("text") == "/transcript-gap" for r in rows))

    def test_action_spec_needs_confirm_not_dangerous(self) -> None:
        from src.backend.experience import get_action
        from src.backend.experience.actions import DANGEROUS_ACTION_IDS

        spec = get_action("listening.transcript_gap")
        self.assertIsNotNone(spec)
        self.assertTrue(spec.needs_confirm)
        self.assertFalse(spec.dangerous)
        self.assertNotIn("listening.transcript_gap", DANGEROUS_ACTION_IDS)


if __name__ == "__main__":
    unittest.main()