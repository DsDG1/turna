from __future__ import annotations

import sys
import unittest
from pathlib import Path

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from tool.deploy_course_preview import render_caddy_config, systemd_unit


_EXISTING = """turnalangua.xyz, www.turnalangua.xyz {
\troot * /var/www/turnalangua
\ttry_files {path} {path}.html {path}/index.html
\tfile_server
\tencode gzip
}
"""


class CoursePreviewDeployTest(unittest.TestCase):
    def test_caddy_route_preserves_existing_static_site(self) -> None:
        result = render_caddy_config(_EXISTING)

        self.assertIn("handle_path /course-preview/*", result)
        self.assertIn("reverse_proxy 127.0.0.1:8765", result)
        self.assertIn("root * /var/www/turnalangua", result)
        self.assertIn("try_files {path} {path}.html {path}/index.html", result)
        self.assertIn("encode gzip", result)
        self.assertIn("\thandle {", result)

    def test_caddy_update_is_idempotent(self) -> None:
        once = render_caddy_config(_EXISTING)
        twice = render_caddy_config(once)

        self.assertEqual(once, twice)
        self.assertEqual(twice.count("handle_path /course-preview/*"), 1)

    def test_caddy_rejects_unknown_site_shape(self) -> None:
        with self.assertRaises(RuntimeError):
            render_caddy_config("example.test {\n root * /tmp\n}\n")

    def test_systemd_unit_is_localhost_and_least_privilege(self) -> None:
        unit = systemd_unit("https://turnalangua.xyz/course-preview")

        self.assertIn("User=turna-preview", unit)
        self.assertIn("--host 127.0.0.1 --port 8765", unit)
        self.assertIn("ProtectSystem=strict", unit)
        self.assertIn("ReadWritePaths=/var/lib/turna-course-preview", unit)
        self.assertIn("NoNewPrivileges=true", unit)


if __name__ == "__main__":
    unittest.main()
