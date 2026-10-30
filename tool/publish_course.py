#!/usr/bin/env python3
"""Build a builtin-course ZIP and feed without uploading anything.

The default language follows assets/courses/manifest.json. Artifacts and the
previous local feed live in dist/course-updates/<language>/. Use --previous-feed
to supply the deployed feed on a new machine, and --base-url for Release assets.

    python tool/publish_course.py --bump --notes "课程文案更新"
    python tool/publish_course.py --help
"""

from __future__ import annotations

import argparse
import hashlib
import ipaddress
import json
import os
import re
import subprocess
import sys
import tempfile
import zipfile
from collections.abc import Iterator
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urljoin, urlsplit

ROOT = Path(__file__).resolve().parent.parent
FEED_FORMAT = "turna-course-feed/1"
FEED_NAME = "course-feed.json"
HISTORY_LIMIT = 5
REQUIRED_FILES = ("index.json", "vocab.json", "expressions.json", "grammar_points.json")


class PublishError(Exception):
    """A release cannot be prepared without changing an existing contract."""


def _reject_constant(value: str) -> None:
    raise PublishError(f"Non-standard JSON number: {value}")


def read_object(data: bytes, label: str) -> dict[str, Any]:
    value = json.loads(data.decode("utf-8"), parse_constant=_reject_constant)
    if not isinstance(value, dict):
        raise PublishError(f"{label} must be a JSON object")
    return value


def version_number(value: Any, label: str) -> int:
    if type(value) is not int or value < 0:
        raise PublishError(f"{label} must be a non-negative integer")
    return value


def safe_relative_path(name: str) -> None:
    if (
        "\\" in name
        or ":" in name
        or any(ord(char) < 32 for char in name)
        or any(part in ("", ".", "..") for part in name.split("/"))
    ):
        raise PublishError(f"Invalid relative path: {name!r}")


def safe_json_path(name: str) -> None:
    safe_relative_path(name)
    if not name.endswith(".json"):
        raise PublishError(f"Only JSON files can be published: {name!r}")


def resolve_course(language: str) -> tuple[Path, str]:
    if not re.fullmatch(r"[a-zA-Z0-9_-]+", language):
        raise PublishError("Invalid language code")
    manifest = read_object(
        (ROOT / "assets/courses/manifest.json").read_bytes(), "manifest"
    )
    languages = manifest.get("languages")
    if not isinstance(languages, list):
        raise PublishError("Manifest languages must be a list")
    matches = [
        entry
        for entry in languages
        if isinstance(entry, dict) and entry.get("code") == language
    ]
    if len(matches) != 1:
        raise PublishError(f"Expected one builtin manifest entry for {language}")
    slug = matches[0].get("dir")
    if not isinstance(slug, str) or not re.fullmatch(r"[a-zA-Z0-9_-]+", slug):
        raise PublishError("Manifest course directory must be a simple directory name")
    courses = (ROOT / "assets/courses").resolve()
    course = (courses / slug).resolve()
    if not course.is_relative_to(courses) or not course.is_dir():
        raise PublishError(
            "Manifest course directory is missing or outside assets/courses"
        )
    return course, slug


def capture_course(course: Path) -> dict[str, bytes]:
    """Capture a JSON-only snapshot, rejecting links and unexpected assets."""
    files: dict[str, bytes] = {}
    for path in sorted(course.rglob("*")):
        if path.is_symlink() or (hasattr(path, "is_junction") and path.is_junction()):
            raise PublishError(
                f"Course links are not allowed: {path.relative_to(course)}"
            )
        if not path.resolve().is_relative_to(course):
            raise PublishError("Course entry escapes its root")
        if path.is_dir():
            continue
        name = path.relative_to(course).as_posix()
        safe_json_path(name)
        if not path.is_file():
            raise PublishError(f"Course entry is not a regular file: {name}")
        data = path.read_bytes()
        json.loads(data.decode("utf-8"), parse_constant=_reject_constant)
        files[name] = data
    return files


def inspect_course(files: dict[str, bytes], language: str) -> tuple[int, int]:
    """Check package layout before running the existing course validators."""
    for name in REQUIRED_FILES:
        if name not in files:
            raise PublishError(f"Course is missing {name}")
        read_object(files[name], name)
    index = read_object(files["index.json"], "index.json")
    expressions = read_object(files["expressions.json"], "expressions.json")
    version = version_number(index.get("version"), "index.version")
    expressions_version = version_number(
        expressions.get("version"), "expressions.version"
    )
    if index.get("language", language) != language:
        raise PublishError("Index language does not match the manifest")
    sections = index.get("sections")
    if not isinstance(sections, list) or not sections:
        raise PublishError("Index must contain at least one section")
    seen_paths: set[str] = set()
    for entry in sections:
        if (
            not isinstance(entry, dict)
            or not isinstance(entry.get("id"), str)
            or not entry["id"]
        ):
            raise PublishError("Section index entries need a non-empty id")
        path = entry.get("file")
        if not isinstance(path, str):
            raise PublishError("Section index entries need a file path")
        safe_json_path(path)
        if not path.startswith("sections/") or path in seen_paths:
            raise PublishError(f"Invalid or duplicate section path: {path}")
        seen_paths.add(path)
        if path not in files:
            raise PublishError(f"Missing section JSON: {path}")
        if read_object(files[path], path).get("id") != entry["id"]:
            raise PublishError(f"Section id does not match index: {path}")
    return version, expressions_version


def validate_url(url: Any, *, allow_http: bool) -> str:
    """Allow relative package paths or credential-free HTTPS URLs."""
    if not isinstance(url, str) or not url or any(ord(char) <= 32 for char in url):
        raise PublishError("Package URL must be a non-empty URL without whitespace")
    try:
        parts = urlsplit(url)
        port = parts.port
    except ValueError as error:
        raise PublishError("Malformed package URL") from error
    if (
        parts.username is not None
        or parts.password is not None
        or "?" in url
        or "#" in url
    ):
        raise PublishError(
            "URLs must not contain credentials, query parameters, or fragments"
        )
    if not parts.scheme and not parts.netloc:
        if not parts.path:
            raise PublishError("Package URL must contain a path")
        safe_relative_path(unquote(parts.path))
        return url
    if parts.scheme not in ("https", "http") or not parts.hostname or "\\" in url:
        raise PublishError("Package URL must use HTTPS or a relative package path")
    if port is not None and not 1 <= port <= 65535:
        raise PublishError("Invalid URL port")
    if parts.scheme == "http":
        host = parts.hostname.lower()
        try:
            address = ipaddress.ip_address(host)
            local = address.is_private and not address.is_unspecified
        except ValueError:
            local = host == "localhost" or host.endswith(".local")
        if not allow_http or not local:
            raise PublishError(
                "HTTP requires --allow-http and a loopback/private LAN host"
            )
    return url


def read_previous_feed(
    path: Path, language: str, *, required: bool
) -> dict[str, Any] | None:
    if not path.exists():
        if not required:
            return None
        raise PublishError(f"Previous feed is missing: {path}")
    feed = read_object(path.read_bytes(), "previous feed")
    if feed.get("format") != FEED_FORMAT or feed.get("language") != language:
        raise PublishError("Previous feed format/language does not match this course")
    history = feed.get("history")
    if not isinstance(history, list) or len(history) > HISTORY_LIMIT:
        raise PublishError("Previous feed history must contain at most five releases")
    previous_version: int | None = None
    releases = []
    for entry in [feed.get("latest"), *history]:
        if not isinstance(entry, dict):
            raise PublishError("Previous feed release must be an object")
        version = version_number(entry.get("version"), "feed.version")
        version_number(entry.get("expressionsVersion"), "feed.expressionsVersion")
        if previous_version is not None and version >= previous_version:
            raise PublishError("Previous feed versions must be unique and newest first")
        previous_version = version
        if not isinstance(entry.get("sha256"), str) or not re.fullmatch(
            r"[0-9a-f]{64}", entry["sha256"]
        ):
            raise PublishError("Previous feed has an invalid SHA-256")
        if type(entry.get("sizeBytes")) is not int or entry["sizeBytes"] <= 0:
            raise PublishError("Previous feed has an invalid sizeBytes")
        if not isinstance(entry.get("notes"), str) or not isinstance(
            entry.get("releasedAt"), str
        ):
            raise PublishError("Previous feed notes/releasedAt must be strings")
        released_at = datetime.fromisoformat(entry["releasedAt"].replace("Z", "+00:00"))
        if released_at.utcoffset() is None:
            raise PublishError("Previous feed release time must include a timezone")
        validate_url(entry.get("url"), allow_http=True)
        releases.append(
            {
                key: entry[key]
                for key in (
                    "version",
                    "expressionsVersion",
                    "url",
                    "sha256",
                    "sizeBytes",
                    "releasedAt",
                    "notes",
                )
            }
        )
    return {
        "format": FEED_FORMAT,
        "language": language,
        "latest": releases[0],
        "history": releases[1:],
    }


def next_version(current: int, previous: dict[str, Any] | None, *, bump: bool) -> int:
    if previous is None:
        return current + 1 if bump else current
    last = previous["latest"]["version"]
    if bump and current == last:
        return last + 1
    if current != last + 1:
        raise PublishError(
            f"index.version must be {last + 1} after previous feed v{last}; "
            f"found {current}. Use --bump when the source is still v{last}."
        )
    return current


def check_builtin_version(
    version: int, current: int, *, previous: dict[str, Any] | None, bump: bool
) -> str | None:
    """Guard a release against the bundled course version.

    ``CourseContentSource`` prefers the bundled assets on a version tie, so a
    package whose version equals ``index.version`` only reaches devices whose
    bundled course is older. That is still a legitimate case (re-releasing an
    already bumped version under a new host), so a tie is a warning, not an
    error. ``next_version`` cannot currently produce ``version < current``;
    the check stays as a guard against future edits to it.
    """
    if version < current:
        raise PublishError(
            f"Release version {version} is older than bundled assets v{current}; "
            "a package that cannot outrank the bundled course is never used."
        )
    if version > current:
        return None
    message = (
        f"warning: package version v{version} equals the bundled assets version. "
        "The content source prefers bundled assets on a tie, so this package only "
        f"reaches devices whose bundled course is older than v{version}."
    )
    if previous is None and not bump:
        message += (
            f" Use --bump to publish v{version + 1}, or ignore this warning when "
            f"re-releasing v{version} under a new host."
        )
    return message


def json_bytes(value: dict[str, Any]) -> bytes:
    return (
        json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n"
    ).encode("utf-8")


def run_validators(snapshot: Path, *, strict: bool) -> None:
    for command in ("validate", "lint"):
        args = [
            sys.executable,
            str(ROOT / "tool/course_cli.py"),
            "--course-dir",
            str(snapshot),
            command,
        ]
        if command == "lint" and strict:
            args.append("--strict")
        print(f"Running course_cli {command} on release snapshot...", flush=True)
        environment = dict(os.environ, PYTHONIOENCODING="utf-8")
        subprocess.run(args, cwd=ROOT, check=True, env=environment)


def build_zip(path: Path, files: dict[str, bytes]) -> None:
    """Write reproducible archive entries with no enclosing directory."""
    with zipfile.ZipFile(
        path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9
    ) as archive:
        for name, data in sorted(files.items()):
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, data, compresslevel=9)
    with zipfile.ZipFile(path) as archive:
        if archive.testzip() is not None:
            raise PublishError("Generated ZIP failed its CRC check")
    with path.open("r+b") as output:
        os.fsync(output.fileno())


def atomic_write(path: Path, data: bytes) -> None:
    descriptor, name = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".tmp", dir=path.parent
    )
    temporary = Path(name)
    try:
        with os.fdopen(descriptor, "wb") as output:
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


@contextmanager
def publish_lock(directory: Path) -> Iterator[None]:
    path = directory / ".publish.lock"
    try:
        descriptor = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError as error:
        raise PublishError(
            f"Publish lock exists: {path}. If the recorded process has exited, remove this lock before retrying."
        ) from error
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as lock:
            lock.write(f"{os.getpid()}\n")
        yield
    finally:
        path.unlink(missing_ok=True)


def publish(args: argparse.Namespace) -> tuple[Path, Path, dict[str, Any]]:
    course, slug = resolve_course(args.language)
    output = (
        (args.output_dir or ROOT / "dist/course-updates" / args.language)
        .expanduser()
        .resolve()
    )
    if output.is_relative_to(course):
        raise PublishError("Release output must be outside the source course directory")
    base_url = args.base_url
    if base_url is not None:
        validate_url(base_url, allow_http=args.allow_http)
        if not urlsplit(base_url).scheme:
            raise PublishError("--base-url must be an absolute URL")
    output.mkdir(parents=True, exist_ok=True)
    with publish_lock(output):
        feed_path = output / FEED_NAME
        baseline = (
            args.previous_feed.expanduser().resolve()
            if args.previous_feed
            else feed_path
        )
        previous = read_previous_feed(
            baseline, args.language, required=args.previous_feed is not None
        )
        # Never silently replace a newer local feed with an older external baseline.
        if baseline != feed_path and feed_path.exists():
            local = read_previous_feed(feed_path, args.language, required=True)
            if (
                previous is None
                or local is None
                or local["latest"] != previous["latest"]
            ):
                raise PublishError(
                    "Output feed differs from --previous-feed; use a fresh output directory"
                )
        original = capture_course(course)
        current, expressions_version = inspect_course(original, args.language)
        version = next_version(current, previous, bump=args.bump)
        warning = check_builtin_version(
            version, current, previous=previous, bump=args.bump
        )
        if warning is not None:
            # A tie is legal (re-hosting), so it must not change the exit code.
            print(warning, file=sys.stderr, flush=True)
        files = dict(original)
        if version != current:
            index = read_object(files["index.json"], "index.json")
            index["version"] = version
            files["index.json"] = json_bytes(index)
            if b"\r\n" in original["index.json"]:
                files["index.json"] = files["index.json"].replace(b"\n", b"\r\n")
        archive_name = f"{slug}-{version}.zip"
        archive_path = output / archive_name
        package_url = (
            urljoin(base_url.rstrip("/") + "/", archive_name)
            if base_url
            else archive_name
        )
        validate_url(package_url, allow_http=args.allow_http)
        print(
            f"Course: {args.language} ({slug}), version {current}+{expressions_version} -> {version}+{expressions_version}"
        )
        print(f"Baseline: {baseline if previous else 'none (first feed)'}", flush=True)
        with tempfile.TemporaryDirectory(prefix=".publish-", dir=output) as directory:
            staging = Path(directory)
            snapshot = staging / "course"
            for name, data in files.items():
                destination = snapshot / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(data)
            run_validators(snapshot, strict=args.strict)
            staged_zip = staging / archive_name
            build_zip(staged_zip, files)
            payload = staged_zip.read_bytes()
            release = {
                "version": version,
                "expressionsVersion": expressions_version,
                "url": package_url,
                "sha256": hashlib.sha256(payload).hexdigest(),
                "sizeBytes": len(payload),
                "releasedAt": datetime.now(timezone.utc)
                .isoformat(timespec="seconds")
                .replace("+00:00", "Z"),
                "notes": args.notes,
            }
            history = ([previous["latest"], *previous["history"]] if previous else [])[
                :HISTORY_LIMIT
            ]
            feed = {
                "format": FEED_FORMAT,
                "language": args.language,
                "latest": release,
                "history": history,
            }
            if archive_path.exists() and archive_path.read_bytes() != payload:
                raise PublishError(
                    "An archive with this version already exists with different content"
                )
            if capture_course(course) != original:
                raise PublishError(
                    "Course changed while preparing the release; retry after saving all edits"
                )
            if not archive_path.exists():
                os.replace(staged_zip, archive_path)
            bumped = version != current
            try:
                if bumped:
                    atomic_write(course / "index.json", files["index.json"])
                # The feed is the commit marker: it never references a partial ZIP.
                atomic_write(feed_path, json_bytes(feed))
            except OSError:
                if (
                    bumped
                    and (course / "index.json").read_bytes() == files["index.json"]
                ):
                    atomic_write(course / "index.json", original["index.json"])
                raise
        return archive_path, feed_path, release


def main(argv: list[str] | None = None) -> int:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--language", default="tr", help="Builtin manifest language code (default: tr)"
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        help="Artifact directory (default: dist/course-updates/<language>)",
    )
    parser.add_argument(
        "--previous-feed",
        type=Path,
        help="Explicit deployed feed baseline, for example on a fresh machine",
    )
    parser.add_argument(
        "--base-url",
        help="Public ZIP download directory; default is a relative URL for colocated hosting",
    )
    parser.add_argument(
        "--allow-http",
        action="store_true",
        help="Allow --base-url on a private LAN/loopback HTTP server",
    )
    parser.add_argument(
        "--bump",
        action="store_true",
        help="Advance index.version to previous+1; first feed advances current+1. "
        "Without it a first feed keeps the bundled version, which bundled assets win on a tie.",
    )
    parser.add_argument(
        "--notes",
        default="课程内容更新",
        help="One-line update notes displayed in the app",
    )
    parser.add_argument(
        "--strict", action="store_true", help="Treat course lint warnings as errors"
    )
    args = parser.parse_args(argv)
    if not args.notes.strip() or any(char in args.notes for char in "\r\n"):
        parser.error("--notes must be one non-empty line")
    try:
        archive, feed, release = publish(args)
    except subprocess.CalledProcessError as error:
        print(
            f"error: course validation/lint failed (exit {error.returncode}); release not committed",
            file=sys.stderr,
        )
        return 1
    except (PublishError, OSError, ValueError, zipfile.BadZipFile) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    print(f"\nPrepared locally (not uploaded):\n  ZIP:  {archive}\n  Feed: {feed}")
    print(f"SHA-256: {release['sha256']}\nSize: {release['sizeBytes']} bytes")
    print(
        f"\nGitee / GitHub Release: create tag content-{args.language}-v{release['version']} and upload the ZIP first."
    )
    if args.base_url is None:
        print("Feed uses a relative ZIP URL: host both files in the same directory.")
        print(
            "For Release attachments, prepare with --base-url pointing at the actual ZIP download directory."
        )
    print(
        "Publish course-feed.json at its stable address last; retain archives referenced by history."
    )
    print(f'LAN preview: python -m http.server 8000 --directory "{feed.parent}"')
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
