"""Unit tests for E4MultimodalEngine (Phase 4 Direction 1)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.experience.e4_multimodal_engine import E4MultimodalEngine, GroundedContext


class E4MultimodalEngineTests(unittest.TestCase):
    def setUp(self) -> None:
        self.engine = E4MultimodalEngine()

    def test_extract_grounded_terms(self) -> None:
        text = "Merhaba! Bu bir Türkçe dersi. Elma ve su."
        terms = self.engine.extract_grounded_terms(text)
        self.assertIn("merhaba", terms)
        self.assertIn("türkçe", terms)
        self.assertIn("elma", terms)
        self.assertIn("su", terms)

    def test_build_grounded_context(self) -> None:
        records = [
            {
                "ref_id": "att_01",
                "kind": "text",
                "name": "unit1.txt",
                "content": "Merhaba dünya! Bu elma ve su.",
            },
            {
                "ref_id": "att_02",
                "kind": "audio",
                "name": "greeting.mp3",
                "audio_path": "/path/to/greeting.mp3",
            },
        ]
        ctx = self.engine.build_grounded_context(records)
        self.assertEqual(ctx.ref_ids, ["att_01", "att_02"])
        self.assertIn("merhaba", ctx.grounded_vocab)
        self.assertIn("elma", ctx.grounded_vocab)
        self.assertIn("greeting.mp3", ctx.audio_anchors)
        self.assertEqual(ctx.grounding_score, 1.0)

    def test_evaluate_grounding_fidelity(self) -> None:
        records = [
            {
                "ref_id": "att_01",
                "kind": "text",
                "content": "elma su ekmek",
            }
        ]
        ctx = self.engine.build_grounded_context(records)

        generated_items = [
            {
                "runtimeType": "multipleChoice",
                "expected": "elma",
                "options": ["elma", "su"],
            }
        ]
        fidelity, ungrounded = self.engine.evaluate_grounding_fidelity(generated_items, ctx)
        self.assertEqual(fidelity, 1.0)
        self.assertEqual(ungrounded, [])

        # Add ungrounded term
        generated_items_ungrounded = [
            {
                "runtimeType": "multipleChoice",
                "expected": "araba",
                "options": ["araba", "elma"],
            }
        ]
        fidelity_un, ungrounded_un = self.engine.evaluate_grounding_fidelity(
            generated_items_ungrounded, ctx
        )
        self.assertLess(fidelity_un, 1.0)
        self.assertIn("araba", ungrounded_un)


if __name__ == "__main__":
    unittest.main()
