"""Tests for the application settings model."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.application.settings import Settings  # noqa: E402


def _make_qsettings(values: dict | None = None) -> MagicMock:
    """Create a mock QSettings backed by a plain dict."""
    store = dict(values or {})
    qsettings = MagicMock()

    def _value(key: str, default=None):
        return store.get(key, default)

    def _set_value(key: str, value) -> None:
        store[key] = value

    def _contains(key: str) -> bool:
        return key in store

    def _remove(key: str) -> None:
        store.pop(key, None)

    qsettings.value = _value
    qsettings.setValue = _set_value
    qsettings.contains = _contains
    qsettings.remove = _remove
    return qsettings


class SettingsLoadTest(unittest.TestCase):
    def test_defaults_when_empty(self) -> None:
        qs = _make_qsettings({"recent_repos": "[]"})
        settings = Settings.load_from_qsettings(qs)
        self.assertEqual(settings.theme, "dark")
        self.assertEqual(settings.ui_scale_percent, 100)
        self.assertEqual(settings.ai_base_url, "")
        self.assertEqual(settings.ai_api_key, "")
        self.assertEqual(settings.ai_model, "")
        self.assertFalse(settings.auto_save_on_close)
        self.assertEqual(settings.undo_limit, 100)
        self.assertEqual(settings.recent_repos, [])

    def test_loads_legacy_ai_keys(self) -> None:
        qs = _make_qsettings(
            {
                "recent_repos": "[]",
                "ai/base_url": "https://api.example.com/v1",
                "ai/api_key": "sk-test",
                "ai/model": "gpt-test",
            }
        )
        settings = Settings.load_from_qsettings(qs)
        self.assertEqual(settings.ai_base_url, "https://api.example.com/v1")
        # API key is memory-only and must not be loaded from storage.
        self.assertEqual(settings.ai_api_key, "")
        self.assertEqual(settings.ai_model, "gpt-test")
        # Stale API key must be removed from storage.
        self.assertFalse(qs.contains("ai/api_key"))

    def test_clamps_ui_scale(self) -> None:
        qs = _make_qsettings(
            {"recent_repos": "[]", "appearance/ui_scale_percent": 200}
        )
        settings = Settings.load_from_qsettings(qs)
        self.assertEqual(settings.ui_scale_percent, 150)

    def test_clamps_undo_limit(self) -> None:
        qs = _make_qsettings({"recent_repos": "[]", "editor/undo_limit": 5})
        settings = Settings.load_from_qsettings(qs)
        self.assertEqual(settings.undo_limit, 10)

    def test_invalid_theme_defaults_to_dark(self) -> None:
        qs = _make_qsettings({"recent_repos": "[]", "appearance/theme": "neon"})
        settings = Settings.load_from_qsettings(qs)
        self.assertEqual(settings.theme, "dark")

    def test_loads_recent_repos(self) -> None:
        qs = _make_qsettings(
            {"recent_repos": '[{"path": "/tmp/course", "opened_at": "2024-01-01T00:00:00+00:00"}]'}
        )
        settings = Settings.load_from_qsettings(qs)
        self.assertEqual(len(settings.recent_repos), 1)
        self.assertEqual(settings.recent_repos[0]["path"], "/tmp/course")


class SettingsSaveTest(unittest.TestCase):
    def test_persists_all_values(self) -> None:
        qs = _make_qsettings({"recent_repos": "[]"})
        settings = Settings(
            theme="light",
            ui_scale_percent=120,
            ai_base_url="https://x.com",
            ai_api_key="k",
            ai_model="m",
            ai_retry_max=3,
            auto_save_on_close=True,
            undo_limit=50,
            recent_repos=[{"path": "/tmp/c", "opened_at": "2024-01-01T00:00:00+00:00"}],
        )
        settings.save_to_qsettings(qs)

        self.assertEqual(qs.value("appearance/theme"), "light")
        self.assertEqual(qs.value("appearance/ui_scale_percent"), 120)
        self.assertEqual(qs.value("ai/base_url"), "https://x.com")
        # API key must never be persisted.
        self.assertFalse(qs.contains("ai/api_key"))
        self.assertEqual(qs.value("ai/model"), "m")
        self.assertEqual(qs.value("ai/retry_max"), 3)
        self.assertEqual(qs.value("editor/auto_save_on_close"), True)
        self.assertEqual(qs.value("editor/undo_limit"), 50)

    def test_round_trip(self) -> None:
        qs = _make_qsettings({"recent_repos": "[]"})
        original = Settings(
            theme="light",
            ui_scale_percent=130,
            ai_base_url="u",
            ai_api_key="k",
            ai_model="m",
            ai_retry_max=2,
            auto_save_on_close=True,
            undo_limit=250,
            recent_repos=[{"path": "/tmp/x", "opened_at": "2024-02-02T00:00:00+00:00"}],
        )
        original.save_to_qsettings(qs)
        loaded = Settings.load_from_qsettings(qs)
        self.assertEqual(loaded.theme, original.theme)
        self.assertEqual(loaded.ui_scale_percent, original.ui_scale_percent)
        self.assertEqual(loaded.ai_base_url, original.ai_base_url)
        # API key is memory-only and must not survive a round trip.
        self.assertEqual(loaded.ai_api_key, "")
        self.assertEqual(loaded.ai_model, original.ai_model)
        self.assertEqual(loaded.ai_retry_max, original.ai_retry_max)
        self.assertEqual(loaded.auto_save_on_close, original.auto_save_on_close)
        self.assertEqual(loaded.undo_limit, original.undo_limit)
        self.assertEqual(loaded.recent_repos, original.recent_repos)

    def test_ai_retry_max_round_trip(self) -> None:
        qs = _make_qsettings({"recent_repos": "[]", "ai/retry_max": 4})
        loaded = Settings.load_from_qsettings(qs)
        self.assertEqual(loaded.ai_retry_max, 4)
        loaded.save_to_qsettings(qs)
        self.assertEqual(qs.value("ai/retry_max"), 4)

    def test_ai_retry_max_clamped(self) -> None:
        qs_low = _make_qsettings({"recent_repos": "[]", "ai/retry_max": -1})
        self.assertEqual(Settings.load_from_qsettings(qs_low).ai_retry_max, 0)
        qs_high = _make_qsettings({"recent_repos": "[]", "ai/retry_max": 9})
        self.assertEqual(Settings.load_from_qsettings(qs_high).ai_retry_max, 5)

    def test_settings_clone_preserves_ai_retry_max(self) -> None:
        qs = _make_qsettings({"recent_repos": "[]", "ai/retry_max": 3})
        settings = Settings.load_from_qsettings(qs)
        clone = settings.clone()
        self.assertEqual(clone.ai_retry_max, 3)

    def test_loads_new_ai_fields(self) -> None:
        qs = _make_qsettings(
            {
                "recent_repos": "[]",
                "ai/provider": "deepseek",
                "ai/timeout": 60.0,
                "ai/temperature": 0.5,
                "ai/supports_reasoning": True,
            }
        )
        settings = Settings.load_from_qsettings(qs)
        self.assertEqual(settings.ai_provider, "deepseek")
        self.assertEqual(settings.ai_timeout, 60.0)
        self.assertEqual(settings.ai_temperature, 0.5)
        self.assertTrue(settings.ai_supports_reasoning)

    def test_clamps_ai_timeout_and_temperature(self) -> None:
        qs_low = _make_qsettings(
            {"recent_repos": "[]", "ai/timeout": 1.0, "ai/temperature": -0.5}
        )
        s_low = Settings.load_from_qsettings(qs_low)
        self.assertEqual(s_low.ai_timeout, 5.0)
        self.assertEqual(s_low.ai_temperature, 0.0)
        qs_high = _make_qsettings(
            {"recent_repos": "[]", "ai/timeout": 900.0, "ai/temperature": 3.0}
        )
        s_high = Settings.load_from_qsettings(qs_high)
        self.assertEqual(s_high.ai_timeout, 600.0)
        self.assertEqual(s_high.ai_temperature, 2.0)

    def test_invalid_provider_defaults_to_custom(self) -> None:
        qs = _make_qsettings({"recent_repos": "[]", "ai/provider": "evil"})
        self.assertEqual(Settings.load_from_qsettings(qs).ai_provider, "custom")

    def test_persists_new_ai_fields(self) -> None:
        qs = _make_qsettings({"recent_repos": "[]"})
        settings = Settings(
            ai_provider="openai",
            ai_timeout=90.0,
            ai_temperature=0.8,
            ai_supports_reasoning=True,
        )
        settings.save_to_qsettings(qs)
        self.assertEqual(qs.value("ai/provider"), "openai")
        self.assertEqual(qs.value("ai/timeout"), 90.0)
        self.assertEqual(qs.value("ai/temperature"), 0.8)
        self.assertEqual(qs.value("ai/supports_reasoning"), True)

    def test_clone_preserves_new_ai_fields(self) -> None:
        settings = Settings(
            ai_provider="moonshot",
            ai_timeout=45.0,
            ai_temperature=0.3,
            ai_supports_reasoning=False,
        )
        clone = settings.clone()
        self.assertEqual(clone.ai_provider, "moonshot")
        self.assertEqual(clone.ai_timeout, 45.0)
        self.assertEqual(clone.ai_temperature, 0.3)
        self.assertEqual(clone.ai_supports_reasoning, False)


class SettingsRecentRepoTest(unittest.TestCase):
    def test_add_recent_repo_moves_to_top(self) -> None:
        settings = Settings(recent_repos=[{"path": "/b"}, {"path": "/a"}])
        settings.add_recent_repo("/a")
        self.assertEqual(settings.recent_repos[0]["path"], "/a")
        self.assertEqual(len(settings.recent_repos), 2)

    def test_add_recent_repo_caps_at_ten(self) -> None:
        settings = Settings(recent_repos=[{"path": f"/{i}"} for i in range(10)])
        settings.add_recent_repo("/new")
        self.assertEqual(len(settings.recent_repos), 10)
        self.assertEqual(settings.recent_repos[0]["path"], "/new")

    def test_remove_recent_repo(self) -> None:
        settings = Settings(recent_repos=[{"path": "/a"}, {"path": "/b"}])
        settings.remove_recent_repo("/a")
        self.assertEqual(len(settings.recent_repos), 1)
        self.assertEqual(settings.recent_repos[0]["path"], "/b")

    def test_clear_recent_repos(self) -> None:
        settings = Settings(recent_repos=[{"path": "/a"}])
        settings.clear_recent_repos()
        self.assertEqual(settings.recent_repos, [])


class SettingsGitLibraryTest(unittest.TestCase):
    def test_git_defaults_when_empty(self) -> None:
        qs = _make_qsettings({"recent_repos": "[]"})
        settings = Settings.load_from_qsettings(qs)
        self.assertEqual(settings.git_clone_root, "")
        self.assertEqual(settings.git_bin, "")
        self.assertEqual(settings.default_lang_code, "")
        self.assertEqual(settings.lan_default_port, 5000)
        self.assertEqual(settings.lan_bind_address, "0.0.0.0")
        self.assertEqual(settings.lan_token, "")
        self.assertEqual(settings.git_timeout, 60.0)
        self.assertEqual(settings.assets_repo_root, "")

    def test_loads_git_fields(self) -> None:
        qs = _make_qsettings({
            "recent_repos": "[]",
            "git/clone_root": "/tmp/clones",
            "git/bin": "/usr/bin/git",
            "git/default_lang": "tr",
            "git/lan_port": 6000,
            "git/lan_bind": "127.0.0.1",
            "git/lan_token": "tok",
            "git/timeout": 120.0,
            "git/assets_root": "/tmp/assets",
        })
        settings = Settings.load_from_qsettings(qs)
        self.assertEqual(settings.git_clone_root, "/tmp/clones")
        self.assertEqual(settings.git_bin, "/usr/bin/git")
        self.assertEqual(settings.default_lang_code, "tr")
        self.assertEqual(settings.lan_default_port, 6000)
        self.assertEqual(settings.lan_bind_address, "127.0.0.1")
        self.assertEqual(settings.lan_token, "tok")
        self.assertEqual(settings.git_timeout, 120.0)
        self.assertEqual(settings.assets_repo_root, "/tmp/assets")

    def test_persists_git_fields(self) -> None:
        qs = _make_qsettings({"recent_repos": "[]"})
        settings = Settings(
            git_clone_root="/tmp/c",
            git_bin="/usr/bin/git",
            default_lang_code="en",
            lan_default_port=7000,
            lan_bind_address="127.0.0.1",
            lan_token="secret",
            git_timeout=90.0,
            assets_repo_root="/tmp/a",
        )
        settings.save_to_qsettings(qs)
        self.assertEqual(qs.value("git/clone_root"), "/tmp/c")
        self.assertEqual(qs.value("git/bin"), "/usr/bin/git")
        self.assertEqual(qs.value("git/default_lang"), "en")
        self.assertEqual(qs.value("git/lan_port"), 7000)
        self.assertEqual(qs.value("git/lan_bind"), "127.0.0.1")
        self.assertEqual(qs.value("git/lan_token"), "secret")
        self.assertEqual(qs.value("git/timeout"), 90.0)
        self.assertEqual(qs.value("git/assets_root"), "/tmp/a")

    def test_git_fields_round_trip(self) -> None:
        qs = _make_qsettings({"recent_repos": "[]"})
        original = Settings(
            git_clone_root="/tmp/c",
            git_bin="/usr/bin/git",
            default_lang_code="tr",
            lan_default_port=5500,
            lan_bind_address="0.0.0.0",
            lan_token="t",
            git_timeout=45.0,
            assets_repo_root="/tmp/a",
        )
        original.save_to_qsettings(qs)
        loaded = Settings.load_from_qsettings(qs)
        self.assertEqual(loaded.git_clone_root, original.git_clone_root)
        self.assertEqual(loaded.git_bin, original.git_bin)
        self.assertEqual(loaded.default_lang_code, original.default_lang_code)
        self.assertEqual(loaded.lan_default_port, original.lan_default_port)
        self.assertEqual(loaded.lan_bind_address, original.lan_bind_address)
        self.assertEqual(loaded.lan_token, original.lan_token)
        self.assertEqual(loaded.git_timeout, original.git_timeout)
        self.assertEqual(loaded.assets_repo_root, original.assets_repo_root)

    def test_clone_preserves_git_fields(self) -> None:
        settings = Settings(
            git_clone_root="/tmp/c",
            git_bin="/usr/bin/git",
            default_lang_code="tr",
            lan_default_port=5500,
            lan_bind_address="127.0.0.1",
            lan_token="t",
            git_timeout=45.0,
            assets_repo_root="/tmp/a",
        )
        clone = settings.clone()
        self.assertEqual(clone.git_clone_root, "/tmp/c")
        self.assertEqual(clone.git_bin, "/usr/bin/git")
        self.assertEqual(clone.default_lang_code, "tr")
        self.assertEqual(clone.lan_default_port, 5500)
        self.assertEqual(clone.lan_bind_address, "127.0.0.1")
        self.assertEqual(clone.lan_token, "t")
        self.assertEqual(clone.git_timeout, 45.0)
        self.assertEqual(clone.assets_repo_root, "/tmp/a")

    def test_clamps_lan_port(self) -> None:
        qs = _make_qsettings({"recent_repos": "[]", "git/lan_port": 0})
        self.assertEqual(Settings.load_from_qsettings(qs).lan_default_port, 1)
        qs = _make_qsettings({"recent_repos": "[]", "git/lan_port": 99999})
        self.assertEqual(Settings.load_from_qsettings(qs).lan_default_port, 65535)

    def test_clamps_git_timeout(self) -> None:
        qs = _make_qsettings({"recent_repos": "[]", "git/timeout": 1.0})
        self.assertEqual(Settings.load_from_qsettings(qs).git_timeout, 5.0)
        qs = _make_qsettings({"recent_repos": "[]", "git/timeout": 900.0})
        self.assertEqual(Settings.load_from_qsettings(qs).git_timeout, 600.0)


if __name__ == "__main__":
    unittest.main()
