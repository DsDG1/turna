"""T23: provider and parse errors must be actionable, not raw payloads.

Before this, a 401 surfaced as ``HTTP 401: {"error":{"message":"Incorrect
API key provided"}}`` — English provider text, no hint about what to change —
and a malformed model reply surfaced as the bare decoder message.
"""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.ai.client import describe_http_error, describe_network_error
from src.backend.ai.parse import parse_json_obj


class HttpErrorMappingTest(unittest.TestCase):
    def test_401_points_at_the_api_key(self) -> None:
        msg = describe_http_error(401, '{"error":{"message":"Incorrect API key"}}')
        self.assertIn("API Key", msg)
        self.assertIn("设置", msg)

    def test_403_points_at_model_permissions(self) -> None:
        msg = describe_http_error(403, "forbidden")
        self.assertIn("权限", msg)

    def test_404_points_at_url_or_model(self) -> None:
        msg = describe_http_error(404, "no such model")
        self.assertIn("Base URL", msg)
        self.assertIn("模型名", msg)

    def test_429_mentions_quotas_and_retry(self) -> None:
        msg = describe_http_error(429, "rate limit exceeded")
        self.assertIn("重试", msg)

    def test_quota_wording_beats_the_generic_429_hint(self) -> None:
        msg = describe_http_error(429, "You exceeded your current quota")
        self.assertIn("额度", msg)

    def test_5xx_is_flagged_as_provider_side(self) -> None:
        msg = describe_http_error(503, "service unavailable")
        self.assertIn("503", msg)
        self.assertIn("provider", msg)

    def test_unknown_code_still_reads_as_chinese(self) -> None:
        msg = describe_http_error(418, "teapot")
        self.assertIn("418", msg)

    def test_provider_detail_is_kept_but_shortened(self) -> None:
        detail = json.dumps({"error": {"message": "x" * 500}})
        msg = describe_http_error(400, detail)
        # The provider text survives for support, but it is no longer the
        # headline and it is truncated.
        self.assertIn("provider 返回", msg)
        self.assertLess(len(msg), 300)

    def test_whitespace_in_detail_is_collapsed(self) -> None:
        msg = describe_http_error(400, "a\n\n   b")
        self.assertNotIn("\n", msg)


class NetworkErrorMappingTest(unittest.TestCase):
    def test_timeout_names_the_timeout_setting(self) -> None:
        msg = describe_network_error("timed out")
        self.assertIn("超时", msg)
        self.assertIn("超时时间", msg)

    def test_dns_failure(self) -> None:
        msg = describe_network_error("[Errno -2] Name or service not known")
        self.assertIn("DNS", msg)

    def test_connection_refused(self) -> None:
        msg = describe_network_error("Connection refused")
        self.assertIn("连接被拒绝", msg)

    def test_tls_error(self) -> None:
        msg = describe_network_error("SSL: CERTIFICATE_VERIFY_FAILED")
        self.assertIn("证书", msg)

    def test_unknown_reason_still_reports_the_reason(self) -> None:
        msg = describe_network_error("something odd happened")
        self.assertIn("something odd happened", msg)

    def test_empty_reason_does_not_crash(self) -> None:
        self.assertTrue(describe_network_error(None))


class ParseErrorMappingTest(unittest.TestCase):
    def test_malformed_json_names_the_position_and_the_cause(self) -> None:
        with self.assertRaises(ValueError) as ctx:
            parse_json_obj("not json at all")
        msg = str(ctx.exception)
        self.assertIn("JSON", msg)
        self.assertIn("第 1 行", msg)
        self.assertIn("重试", msg)

    def test_non_dict_top_level_is_explained(self) -> None:
        with self.assertRaises(ValueError) as ctx:
            parse_json_obj("[1, 2, 3]")
        self.assertIn("对象", str(ctx.exception))

    def test_valid_json_still_parses(self) -> None:
        self.assertEqual(parse_json_obj('{"a": 1}'), {"a": 1})


if __name__ == "__main__":
    unittest.main()
