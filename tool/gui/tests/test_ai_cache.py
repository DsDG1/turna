"""Tests for src/backend/ai_cache.py (第三枪 批次① P6-3)."""
from __future__ import annotations

import json
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import patch

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.ai_cache import (  # noqa: E402
    AiCache,
    _stable_hash,
    get_default_cache,
    set_default_cache,
)


def _msg(role: str, content: str) -> dict:
    return {"role": role, "content": content}


class StableHashTest(unittest.TestCase):
    def test_same_inputs_same_hash(self) -> None:
        h1 = _stable_hash("m", [_msg("user", "hi")], None)
        h2 = _stable_hash("m", [_msg("user", "hi")], None)
        self.assertEqual(h1, h2)

    def test_different_model_different_hash(self) -> None:
        self.assertNotEqual(
            _stable_hash("m1", [_msg("user", "hi")], None),
            _stable_hash("m2", [_msg("user", "hi")], None),
        )

    def test_different_messages_different_hash(self) -> None:
        self.assertNotEqual(
            _stable_hash("m", [_msg("user", "a")], None),
            _stable_hash("m", [_msg("user", "b")], None),
        )

    def test_response_format_affects_hash(self) -> None:
        self.assertNotEqual(
            _stable_hash("m", [_msg("user", "a")], {"type": "json_object"}),
            _stable_hash("m", [_msg("user", "a")], {"type": "json_schema"}),
        )

    def test_message_key_order_does_not_change_hash(self) -> None:
        # Reordering keys inside a message dict must not invalidate the key
        # (because we serialise with sort_keys=True).
        h1 = _stable_hash("m", [{"role": "user", "content": "x"}], None)
        h2 = _stable_hash("m", [{"content": "x", "role": "user"}], None)
        self.assertEqual(h1, h2)

    def test_model_whitespace_ignored(self) -> None:
        self.assertEqual(
            _stable_hash("  m  ", [_msg("user", "a")], None),
            _stable_hash("m", [_msg("user", "a")], None),
        )

    def test_hash_is_hex_sha256(self) -> None:
        h = _stable_hash("m", [_msg("user", "a")], None)
        self.assertEqual(len(h), 64)
        self.assertTrue(all(c in "0123456789abcdef" for c in h))


class AiCacheBasicTest(unittest.TestCase):
    def test_default_disabled_returns_none(self) -> None:
        c = AiCache(enabled=False)
        self.assertIsNone(c.get("m", [_msg("user", "a")], None))
        c.put("m", [_msg("user", "a")], None, {"x": 1})
        self.assertIsNone(c.get("m", [_msg("user", "a")], None))
        self.assertEqual(c.stats().misses, 2)

    def test_hit_after_put(self) -> None:
        c = AiCache(maxsize=4, enabled=True)
        c.put("m", [_msg("user", "a")], None, {"answer": 42})
        self.assertEqual(c.get("m", [_msg("user", "a")], None), {"answer": 42})
        s = c.stats()
        self.assertEqual(s.hits, 1)
        self.assertEqual(s.misses, 0)
        self.assertEqual(s.entries, 1)

    def test_miss_on_unknown_key(self) -> None:
        c = AiCache(maxsize=4, enabled=True)
        self.assertIsNone(c.get("m", [_msg("user", "a")], None))
        self.assertEqual(c.stats().misses, 1)
        self.assertEqual(c.stats().hits, 0)

    def test_lru_eviction(self) -> None:
        c = AiCache(maxsize=2, enabled=True)
        c.put("m", [_msg("user", "a")], None, {"a": 1})
        c.put("m", [_msg("user", "b")], None, {"b": 2})
        # Touch "a" so "b" becomes LRU
        c.get("m", [_msg("user", "a")], None)
        c.put("m", [_msg("user", "c")], None, {"c": 3})
        # "b" should have been evicted
        self.assertIsNone(c.get("m", [_msg("user", "b")], None))
        self.assertEqual(c.get("m", [_msg("user", "a")], None), {"a": 1})
        self.assertEqual(c.get("m", [_msg("user", "c")], None), {"c": 3})

    def test_set_enabled_toggles_runtime(self) -> None:
        c = AiCache(maxsize=4, enabled=True)
        c.put("m", [_msg("user", "a")], None, {"a": 1})
        c.set_enabled(False)
        # Disabled: get returns None even though entry exists
        self.assertIsNone(c.get("m", [_msg("user", "a")], None))
        c.set_enabled(True)
        self.assertEqual(c.get("m", [_msg("user", "a")], None), {"a": 1})

    def test_maxsize_zero_forces_disabled(self) -> None:
        c = AiCache(maxsize=0, enabled=True)
        self.assertFalse(c.enabled)
        c.put("m", [_msg("user", "a")], None, {"a": 1})
        self.assertIsNone(c.get("m", [_msg("user", "a")], None))

    def test_clear_drops_memory_entries(self) -> None:
        c = AiCache(maxsize=4, enabled=True)
        c.put("m", [_msg("user", "a")], None, {"a": 1})
        c.clear()
        self.assertIsNone(c.get("m", [_msg("user", "a")], None))
        self.assertEqual(c.stats().entries, 0)

    def test_make_key_matches_internal(self) -> None:
        c = AiCache(maxsize=4, enabled=True)
        msgs = [_msg("user", "a")]
        rf = {"type": "json_object"}
        public = AiCache.make_key("m", msgs, rf)
        c.put("m", msgs, rf, {"v": 1})
        # The internal key must match the public one
        internal = next(iter(c._mem.keys()))
        self.assertEqual(public, internal)

    def test_stats_returns_snapshot(self) -> None:
        c = AiCache(maxsize=4, enabled=True)
        c.put("m", [_msg("user", "a")], None, {"a": 1})
        c.get("m", [_msg("user", "a")], None)  # hit
        c.get("m", [_msg("user", "b")], None)  # miss
        s = c.stats().as_dict()
        self.assertEqual(s["hits"], 1)
        self.assertEqual(s["misses"], 1)
        self.assertEqual(s["entries"], 1)


class AiCacheDiskTest(unittest.TestCase):
    def test_disk_round_trip_after_restart(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            c1 = AiCache(maxsize=4, disk_dir=tmp, enabled=True)
            c1.put("m", [_msg("user", "a")], None, {"answer": 42})
            self.assertEqual(c1.stats().disk_writes, 1)
            # Simulate a process restart: new cache, same disk_dir
            c2 = AiCache(maxsize=4, disk_dir=tmp, enabled=True)
            self.assertEqual(
                c2.get("m", [_msg("user", "a")], None),
                {"answer": 42},
            )

    def test_disk_file_does_not_contain_api_key_or_messages(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            c = AiCache(maxsize=4, disk_dir=tmp, enabled=True)
            msgs = [_msg("user", "secret-prompt-with-api-key-xyz")]
            c.put("model-x", msgs, None, {"result": "ok"})
            files = list(Path(tmp).glob("*.json"))
            self.assertEqual(len(files), 1)
            raw = files[0].read_text(encoding="utf-8")
            # Only the response body should be present
            self.assertIn('"result":', raw)
            # Neither the model name, nor the prompt content, nor any api key
            # should leak into the cache file.
            self.assertNotIn("model-x", raw)
            self.assertNotIn("secret-prompt", raw)
            self.assertNotIn("api-key", raw)

    def test_clear_disk_removes_files(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            c = AiCache(maxsize=4, disk_dir=tmp, enabled=True)
            c.put("m", [_msg("user", "a")], None, {"a": 1})
            c.put("m", [_msg("user", "b")], None, {"b": 2})
            files_before = list(Path(tmp).glob("*.json"))
            self.assertEqual(len(files_before), 2)
            c.clear_disk()
            files_after = list(Path(tmp).glob("*.json"))
            self.assertEqual(len(files_after), 0)

    def test_disk_corrupt_file_returns_none(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            c1 = AiCache(maxsize=4, disk_dir=tmp, enabled=True)
            c1.put("m", [_msg("user", "a")], None, {"v": 1})
            # Corrupt the cache file
            files = list(Path(tmp).glob("*.json"))
            self.assertEqual(len(files), 1)
            files[0].write_text("{not valid json", encoding="utf-8")
            c2 = AiCache(maxsize=4, disk_dir=tmp, enabled=True)
            self.assertIsNone(c2.get("m", [_msg("user", "a")], None))
            self.assertGreaterEqual(c2.stats().disk_errors, 1)

    def test_disk_dir_created_if_missing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            new_dir = Path(tmp) / "nested" / "cache"
            self.assertFalse(new_dir.exists())
            c = AiCache(maxsize=4, disk_dir=new_dir, enabled=True)
            self.assertTrue(new_dir.exists())
            c.put("m", [_msg("user", "a")], None, {"v": 1})
            self.assertEqual(len(list(new_dir.glob("*.json"))), 1)

    def test_disk_disabled_when_cache_disabled(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            c = AiCache(maxsize=4, disk_dir=tmp, enabled=False)
            self.assertIsNone(c.disk_dir)
            c.put("m", [_msg("user", "a")], None, {"v": 1})
            files = list(Path(tmp).glob("*.json"))
            self.assertEqual(len(files), 0)


class AiCacheThreadSafetyTest(unittest.TestCase):
    def test_concurrent_put_get_no_exception(self) -> None:
        c = AiCache(maxsize=64, enabled=True)
        errors: list[Exception] = []

        def worker(idx: int) -> None:
            try:
                for i in range(50):
                    msgs = [_msg("user", f"q-{idx}-{i}")]
                    c.put(f"m{idx}", msgs, None, {"i": i})
                    c.get(f"m{idx}", msgs, None)
            except Exception as e:  # pragma: no cover - failure surface
                errors.append(e)

        threads = [threading.Thread(target=worker, args=(i,)) for i in range(8)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        self.assertEqual(errors, [])
        # Final entries must not exceed maxsize
        self.assertLessEqual(c.stats().entries, 64)


class DefaultCacheTest(unittest.TestCase):
    def tearDown(self) -> None:
        set_default_cache(None)

    def test_set_and_get_default_cache(self) -> None:
        self.assertIsNone(get_default_cache())
        c = AiCache(maxsize=4, enabled=True)
        set_default_cache(c)
        self.assertIs(get_default_cache(), c)

    def test_set_default_none_clears(self) -> None:
        set_default_cache(AiCache(maxsize=4, enabled=True))
        set_default_cache(None)
        self.assertIsNone(get_default_cache())


if __name__ == "__main__":
    unittest.main()
