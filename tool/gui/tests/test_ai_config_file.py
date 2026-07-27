"""External AI config file import/export and outside-repo policy."""
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.application.settings import Settings
from src.backend import ai_config_file as acf


class AiConfigFilePolicyTest(unittest.TestCase):
    def test_rejects_path_inside_discovered_repo(self) -> None:
        roots = acf.discover_repo_roots()
        if not roots:
            self.skipTest("no git root discovered in this checkout")
        inside = roots[0] / "tool" / "gui" / "fake_ai_config.json"
        ok, msg, resolved = acf.validate_external_path(inside)
        self.assertFalse(ok)
        self.assertIn("仓库", msg)
        self.assertIsNone(resolved)

    def test_accepts_temp_outside_repo(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "ai_config.json"
            ok, msg, resolved = acf.validate_external_path(path)
            self.assertTrue(ok, msg)
            self.assertIsNotNone(resolved)


class AiConfigFileRoundTripTest(unittest.TestCase):
    def test_export_import_round_trip(self) -> None:
        s = Settings(
            ai_provider="deepseek",
            ai_base_url="https://api.example.com/v1",
            ai_api_key="sk-secret-test",
            ai_model="demo-model",
            ai_timeout=90.0,
            ai_temperature=0.2,
            ai_retry_max=2,
            ai_supports_reasoning=True,
            ai_model_chat="chat-m",
            ai_model_json="json-m",
            ai_strict_schema="on",
            ai_cache_enabled=True,
            ai_fill_needs_review=True,
            ai_max_parallel_lessons=3,
            ai_pipeline_default_mode="refine",
        )
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "cfg.json"
            ok, msg = acf.save_file(path, s)
            self.assertTrue(ok, msg)
            raw = json.loads(path.read_text(encoding="utf-8"))
            self.assertEqual(raw["kind"], acf.CONFIG_KIND)
            self.assertEqual(raw["ai"]["api_key"], "sk-secret-test")
            self.assertEqual(raw["ai"]["model"], "demo-model")

            s2 = Settings()
            ok2, msg2 = acf.load_into_settings(path, s2)
            self.assertTrue(ok2, msg2)
            self.assertEqual(s2.ai_api_key, "sk-secret-test")
            self.assertEqual(s2.ai_base_url, "https://api.example.com/v1")
            self.assertEqual(s2.ai_model, "demo-model")
            self.assertEqual(s2.ai_provider, "deepseek")
            self.assertEqual(s2.ai_model_chat, "chat-m")
            self.assertTrue(s2.ai_supports_reasoning)
            self.assertEqual(s2.ai_pipeline_default_mode, "refine")

    def test_flat_hand_edited_document(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "flat.json"
            path.write_text(
                json.dumps(
                    {
                        "base_url": "https://x/v1",
                        "api_key": "k",
                        "model": "m",
                    }
                ),
                encoding="utf-8",
            )
            s = Settings()
            ok, msg = acf.load_into_settings(path, s)
            self.assertTrue(ok, msg)
            self.assertEqual(s.ai_base_url, "https://x/v1")
            self.assertEqual(s.ai_api_key, "k")
            self.assertEqual(s.ai_model, "m")

    def test_settings_persists_path_not_key_in_qsettings_keys(self) -> None:
        """Path flags round-trip; api_key still memory-only in QSettings path."""
        from unittest.mock import MagicMock

        store: dict = {}
        qs = MagicMock()
        qs.value = lambda key, default=None: store.get(key, default)
        qs.contains = lambda key: key in store
        qs.remove = lambda key: store.pop(key, None)
        qs.setValue = lambda key, value: store.__setitem__(key, value)

        s = Settings(
            ai_config_file_path=r"C:\Users\me\.varnamala\ai.json",
            ai_config_file_autoload=True,
            ai_config_file_autosave=False,
            ai_api_key="should-not-persist",
        )
        s.save_to_qsettings(qs)
        self.assertEqual(store.get("ai/config_file_path"), r"C:\Users\me\.varnamala\ai.json")
        self.assertFalse(store.get("ai/config_file_autosave"))
        self.assertNotIn("ai/api_key", store)

        s2 = Settings.load_from_qsettings(qs)
        self.assertEqual(s2.ai_config_file_path, r"C:\Users\me\.varnamala\ai.json")
        self.assertFalse(s2.ai_config_file_autosave)
        self.assertEqual(s2.ai_api_key, "")  # still not from QSettings


if __name__ == "__main__":
    unittest.main()
