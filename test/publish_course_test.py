#!/usr/bin/env python3
"""Tests for the builtin-course release script.

Every case is offline and never touches the real ``assets/`` tree: the
end-to-end group patches ``publish_course.ROOT`` to a temporary fixture and
stubs ``run_validators`` (course lint needs a full course, which is the
validator's own test surface, not this one).

Not covered here: the CRLF-preserving branch of ``publish`` and real
``course_cli`` execution.
"""

from __future__ import annotations

import contextlib
import io
import json
import os
import sys
import tempfile
import unittest
import zipfile
from argparse import Namespace
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tool"))

import publish_course  # noqa: E402

SHA = "a" * 64


def _feed(version: int, *, history: list[dict] | None = None) -> dict:
    return {
        "format": publish_course.FEED_FORMAT,
        "language": "tr",
        "latest": _release(version),
        "history": history or [],
    }


def _release(version: int, **overrides) -> dict:
    release = {
        "version": version,
        "expressionsVersion": 1,
        "url": f"nouveau-turkish-{version}.zip",
        "sha256": SHA,
        "sizeBytes": 1024,
        "releasedAt": "2026-10-30T00:00:00Z",
        "notes": "note",
    }
    release.update(overrides)
    return release


def _course_files(version: int = 1) -> dict[str, bytes]:
    files = {
        "index.json": {
            "version": version,
            "language": "tr",
            "sections": [{"id": "s-1", "name": "S1", "file": "sections/s1.json"}],
        },
        "vocab.json": {"words": []},
        "expressions.json": {"version": 1, "expressions": []},
        "grammar_points.json": {"grammarPoints": []},
        "sections/s1.json": {"id": "s-1", "name": "S1", "units": []},
    }
    return {name: json.dumps(value).encode("utf-8") for name, value in files.items()}


def _write_fixture(root: Path, version: int = 1) -> Path:
    course = root / "assets/courses/nouveau-turkish"
    for name, data in _course_files(version).items():
        path = course / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    manifest = root / "assets/courses/manifest.json"
    manifest.parent.mkdir(parents=True, exist_ok=True)
    manifest.write_text(
        json.dumps({"languages": [{"code": "tr", "dir": "nouveau-turkish"}]}),
        encoding="utf-8",
    )
    return course


def _args(output: Path, **overrides) -> Namespace:
    values = {
        "language": "tr",
        "output_dir": output,
        "previous_feed": None,
        "base_url": None,
        "allow_http": False,
        "bump": False,
        "notes": "note",
        "strict": False,
    }
    values.update(overrides)
    return Namespace(**values)


class NextVersionTest(unittest.TestCase):
    def test_first_feed_without_bump_keeps_bundled_version(self):
        self.assertEqual(publish_course.next_version(2, None, bump=False), 2)

    def test_first_feed_with_bump_advances_once(self):
        self.assertEqual(publish_course.next_version(2, None, bump=True), 3)

    def test_source_already_advanced_is_accepted(self):
        previous = _feed(4)
        self.assertEqual(publish_course.next_version(5, previous, bump=False), 5)

    def test_bump_advances_a_source_still_at_previous_version(self):
        previous = _feed(4)
        self.assertEqual(publish_course.next_version(4, previous, bump=True), 5)

    def test_skipped_version_is_rejected(self):
        previous = _feed(4)
        with self.assertRaises(publish_course.PublishError) as caught:
            publish_course.next_version(6, previous, bump=False)
        self.assertIn("must be 5", str(caught.exception))


class BuiltinVersionGuardTest(unittest.TestCase):
    def test_older_than_bundled_fails(self):
        with self.assertRaises(publish_course.PublishError) as caught:
            publish_course.check_builtin_version(
                2, 3, previous=None, bump=False
            )
        self.assertIn("older than bundled", str(caught.exception))

    def test_tie_on_first_feed_warns_with_bump_hint(self):
        warning = publish_course.check_builtin_version(
            2, 2, previous=None, bump=False
        )
        self.assertIsNotNone(warning)
        self.assertIn("warning:", warning)
        self.assertIn("--bump", warning)

    def test_tie_after_previous_feed_has_no_bump_hint(self):
        warning = publish_course.check_builtin_version(
            4, 4, previous=_feed(3), bump=False
        )
        self.assertIsNotNone(warning)
        self.assertNotIn("--bump", warning)

    def test_newer_version_is_silent(self):
        self.assertIsNone(
            publish_course.check_builtin_version(3, 2, previous=None, bump=True)
        )


class ValidateUrlTest(unittest.TestCase):
    def test_https_absolute_url_passes(self):
        url = "https://example.com/dir/nouveau-turkish-3.zip"
        self.assertEqual(publish_course.validate_url(url, allow_http=False), url)

    def test_relative_package_name_passes(self):
        self.assertEqual(
            publish_course.validate_url("nouveau-turkish-3.zip", allow_http=False),
            "nouveau-turkish-3.zip",
        )

    def test_plain_http_needs_the_switch(self):
        with self.assertRaises(publish_course.PublishError):
            publish_course.validate_url("http://192.168.1.5:8000/a.zip", allow_http=False)

    def test_loopback_http_passes_with_the_switch(self):
        url = "http://127.0.0.1:8000/a.zip"
        self.assertEqual(publish_course.validate_url(url, allow_http=True), url)

    def test_public_http_host_still_fails_with_the_switch(self):
        with self.assertRaises(publish_course.PublishError):
            publish_course.validate_url("http://example.com/a.zip", allow_http=True)

    def test_credentials_query_and_fragment_are_rejected(self):
        for url in (
            "https://user:pass@example.com/a.zip",
            "https://example.com/a.zip?token=1",
            "https://example.com/a.zip#frag",
        ):
            with self.subTest(url=url):
                with self.assertRaises(publish_course.PublishError):
                    publish_course.validate_url(url, allow_http=False)

    def test_traversal_relative_path_is_rejected(self):
        with self.assertRaises(publish_course.PublishError):
            publish_course.validate_url("../a.zip", allow_http=False)

    def test_backslash_is_rejected(self):
        with self.assertRaises(publish_course.PublishError):
            publish_course.validate_url("https://example.com/a\\b.zip", allow_http=False)


class InspectCourseTest(unittest.TestCase):
    def test_minimal_course_reports_both_versions(self):
        self.assertEqual(publish_course.inspect_course(_course_files(3), "tr"), (3, 1))

    def test_missing_required_file_is_rejected(self):
        files = _course_files()
        del files["vocab.json"]
        with self.assertRaises(publish_course.PublishError) as caught:
            publish_course.inspect_course(files, "tr")
        self.assertIn("missing vocab.json", str(caught.exception))

    def test_non_integer_version_is_rejected(self):
        files = _course_files()
        files["index.json"] = json.dumps(
            {"version": "1", "language": "tr", "sections": []}
        ).encode("utf-8")
        with self.assertRaises(publish_course.PublishError) as caught:
            publish_course.inspect_course(files, "tr")
        self.assertIn("non-negative integer", str(caught.exception))

    def test_language_mismatch_is_rejected(self):
        files = _course_files()
        payload = json.loads(files["index.json"])
        payload["language"] = "en"
        files["index.json"] = json.dumps(payload).encode("utf-8")
        with self.assertRaises(publish_course.PublishError) as caught:
            publish_course.inspect_course(files, "tr")
        self.assertIn("language does not match", str(caught.exception))

    def test_section_path_outside_sections_is_rejected(self):
        files = _course_files()
        payload = json.loads(files["index.json"])
        payload["sections"][0]["file"] = "s1.json"
        files["index.json"] = json.dumps(payload).encode("utf-8")
        with self.assertRaises(publish_course.PublishError) as caught:
            publish_course.inspect_course(files, "tr")
        self.assertIn("Invalid or duplicate section path", str(caught.exception))

    def test_section_id_mismatch_is_rejected(self):
        files = _course_files()
        files["sections/s1.json"] = json.dumps({"id": "s-2", "units": []}).encode("utf-8")
        with self.assertRaises(publish_course.PublishError) as caught:
            publish_course.inspect_course(files, "tr")
        self.assertIn("Section id does not match", str(caught.exception))


class ReadPreviousFeedTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory(prefix="turna-feed-")
        self.addCleanup(self._tmp.cleanup)
        self.path = Path(self._tmp.name) / "course-feed.json"

    def _write(self, feed: dict) -> None:
        self.path.write_text(json.dumps(feed), encoding="utf-8")

    def test_missing_feed_is_optional_unless_required(self):
        self.assertIsNone(
            publish_course.read_previous_feed(self.path, "tr", required=False)
        )
        with self.assertRaises(publish_course.PublishError):
            publish_course.read_previous_feed(self.path, "tr", required=True)

    def test_format_and_language_must_match(self):
        self._write({**_feed(2), "language": "en"})
        with self.assertRaises(publish_course.PublishError):
            publish_course.read_previous_feed(self.path, "tr", required=True)

    def test_history_must_be_newest_first(self):
        self._write(_feed(2, history=[_release(2)]))
        with self.assertRaises(publish_course.PublishError) as caught:
            publish_course.read_previous_feed(self.path, "tr", required=True)
        self.assertIn("newest first", str(caught.exception))

    def test_history_is_capped(self):
        history = [_release(8 - index) for index in range(6)]
        self._write(_feed(9, history=history))
        with self.assertRaises(publish_course.PublishError) as caught:
            publish_course.read_previous_feed(self.path, "tr", required=True)
        self.assertIn("at most five", str(caught.exception))

    def test_invalid_sha256_is_rejected(self):
        self._write(_feed(2, history=[]) | {"latest": _release(2, sha256="zz")})
        with self.assertRaises(publish_course.PublishError):
            publish_course.read_previous_feed(self.path, "tr", required=True)

    def test_missing_timezone_is_rejected(self):
        self._write(
            _feed(2) | {"latest": _release(2, releasedAt="2026-10-30T00:00:00")}
        )
        with self.assertRaises(publish_course.PublishError) as caught:
            publish_course.read_previous_feed(self.path, "tr", required=True)
        self.assertIn("timezone", str(caught.exception))

    def test_valid_feed_is_normalized(self):
        self._write(_feed(3, history=[_release(2)]))
        feed = publish_course.read_previous_feed(self.path, "tr", required=True)
        self.assertEqual(feed["latest"]["version"], 3)
        self.assertEqual([entry["version"] for entry in feed["history"]], [2])
        self.assertEqual(
            set(feed), {"format", "language", "latest", "history"}
        )


class CaptureCourseTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory(prefix="turna-capture-")
        self.addCleanup(self._tmp.cleanup)
        self.course = _write_fixture(Path(self._tmp.name))

    def test_snapshot_uses_posix_relative_names(self):
        files = publish_course.capture_course(self.course)
        self.assertIn("sections/s1.json", files)

    def test_non_json_file_is_rejected(self):
        (self.course / "notes.txt").write_text("x", encoding="utf-8")
        with self.assertRaises(publish_course.PublishError) as caught:
            publish_course.capture_course(self.course)
        self.assertIn("Only JSON files", str(caught.exception))

    @unittest.skipIf(os.name == "nt", "creating symlinks needs extra privileges")
    def test_symlink_is_rejected(self):
        target = self.course / "index.json"
        (self.course / "link.json").symlink_to(target)
        with self.assertRaises(publish_course.PublishError) as caught:
            publish_course.capture_course(self.course)
        self.assertIn("links are not allowed", str(caught.exception))


class BuildZipTest(unittest.TestCase):
    def _build(self, path: Path) -> bytes:
        publish_course.build_zip(path, _course_files())
        return path.read_bytes()

    def test_archive_is_byte_reproducible(self):
        with tempfile.TemporaryDirectory() as tmp:
            first = self._build(Path(tmp) / "a.zip")
            second = self._build(Path(tmp) / "b.zip")
        self.assertEqual(first, second)

    def test_entries_have_no_enclosing_directory(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "a.zip"
            publish_course.build_zip(path, _course_files())
            with zipfile.ZipFile(path) as archive:
                names = archive.namelist()
        self.assertIn("index.json", names)
        self.assertIn("sections/s1.json", names)
        self.assertEqual(names, sorted(names))


class PublishEndToEndTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory(prefix="turna-publish-")
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)
        self.course = _write_fixture(self.root, version=1)
        self.output = self.root / "dist"
        patcher = mock.patch.object(publish_course, "ROOT", self.root)
        patcher.start()
        self.addCleanup(patcher.stop)
        validators = mock.patch.object(publish_course, "run_validators", lambda *a, **k: None)
        validators.start()
        self.addCleanup(validators.stop)

    def _publish(self, **overrides):
        """Run the real publish flow with stdout kept out of the test log."""
        with contextlib.redirect_stdout(io.StringIO()):
            return publish_course.publish(_args(self.output, **overrides))

    def test_bump_writes_the_new_version_back_into_the_source(self):
        archive, feed_path, release = self._publish(bump=True)
        self.assertEqual(archive.name, "nouveau-turkish-2.zip")
        self.assertEqual(release["version"], 2)
        self.assertEqual(release["url"], "nouveau-turkish-2.zip")
        self.assertEqual(
            json.loads((self.course / "index.json").read_text(encoding="utf-8"))[
                "version"
            ],
            2,
        )
        feed = json.loads(feed_path.read_text(encoding="utf-8"))
        self.assertEqual(feed["latest"]["sha256"], release["sha256"])
        self.assertEqual(feed["latest"]["sizeBytes"], archive.stat().st_size)
        self.assertEqual(feed["history"], [])
        with zipfile.ZipFile(archive) as package:
            index = json.loads(package.read("index.json").decode("utf-8"))
        self.assertEqual(index["version"], 2)

    def test_first_feed_without_bump_warns_and_keeps_the_source(self):
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            archive, _, release = self._publish()
        self.assertEqual(archive.name, "nouveau-turkish-1.zip")
        self.assertEqual(release["version"], 1)
        self.assertIn("warning:", stderr.getvalue())
        self.assertIn("--bump", stderr.getvalue())
        self.assertEqual(
            json.loads((self.course / "index.json").read_text(encoding="utf-8"))[
                "version"
            ],
            1,
        )

    def test_same_version_different_content_is_rejected(self):
        self.output.mkdir(parents=True)
        (self.output / "nouveau-turkish-2.zip").write_bytes(b"not the same package")
        with self.assertRaises(publish_course.PublishError) as caught:
            self._publish(bump=True)
        self.assertIn("already exists", str(caught.exception))

    def test_output_inside_the_course_is_rejected(self):
        with self.assertRaises(publish_course.PublishError) as caught:
            publish_course.publish(_args(self.course, bump=True))
        self.assertIn("outside the source course", str(caught.exception))

    def test_second_release_advances_from_the_local_feed(self):
        self._publish(bump=True)
        archive, feed_path, release = self._publish(bump=True)
        self.assertEqual(release["version"], 3)
        self.assertEqual(archive.name, "nouveau-turkish-3.zip")
        feed = json.loads(feed_path.read_text(encoding="utf-8"))
        self.assertEqual([entry["version"] for entry in feed["history"]], [2])


class MainExitCodeTest(unittest.TestCase):
    def test_publish_error_returns_one(self):
        stderr = io.StringIO()
        with mock.patch.object(
            publish_course, "publish", side_effect=publish_course.PublishError("boom")
        ), contextlib.redirect_stderr(stderr):
            code = publish_course.main(["--output-dir", tempfile.gettempdir()])
        self.assertEqual(code, 1)
        self.assertIn("error: boom", stderr.getvalue())

    def test_success_returns_zero_and_prints_the_tag(self):
        release = _release(2)
        with mock.patch.object(
            publish_course,
            "publish",
            return_value=(Path("a.zip"), Path("course-feed.json"), release),
        ), contextlib.redirect_stdout(io.StringIO()) as stdout:
            code = publish_course.main(["--output-dir", tempfile.gettempdir()])
        self.assertEqual(code, 0)
        self.assertIn("create tag content-tr-v2", stdout.getvalue())

    def test_multiline_notes_are_rejected(self):
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as caught:
                publish_course.main(
                    ["--output-dir", tempfile.gettempdir(), "--notes", "a\nb"]
                )
        self.assertEqual(caught.exception.code, 2)


if __name__ == "__main__":
    unittest.main()
