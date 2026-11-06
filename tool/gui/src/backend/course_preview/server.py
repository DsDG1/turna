from __future__ import annotations

import json
import logging
import time
from collections import defaultdict, deque
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlsplit

from .render import render_catalog, render_course, render_lesson, render_outline
from .store import PreviewStore
from .document import build_document


logger = logging.getLogger(__name__)
_MAX_FORM_BYTES = 16_384


class PreviewHttpServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(
        self,
        address: tuple[str, int],
        store: PreviewStore,
        *,
        public_base: str,
        rate_limit: int = 12,
        rate_window: float = 600.0,
    ) -> None:
        super().__init__(address, PreviewRequestHandler)
        self.store = store
        self.public_base = public_base
        self.base_path = urlsplit(public_base).path.rstrip("/")
        self.rate_limit = rate_limit
        self.rate_window = rate_window
        self.rate_events: dict[str, deque[float]] = defaultdict(deque)


class PreviewRequestHandler(BaseHTTPRequestHandler):
    server: PreviewHttpServer

    def log_message(self, format: str, *args: Any) -> None:
        logger.info("course_preview http " + format, *args)

    def _headers(self, status: int, content_type: str, length: int, *, cache: bool = False) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(length))
        self.send_header("Cache-Control", "public, max-age=300" if cache else "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("X-Robots-Tag", "noindex, nofollow, noarchive")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header(
            "Content-Security-Policy",
            "default-src 'self'; script-src 'none'; style-src 'self'; img-src 'self' data:; "
            "object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'",
        )
        self.end_headers()

    def _bytes(self, value: bytes, status: int = 200, content_type: str = "text/html; charset=utf-8", *, cache: bool = False) -> None:
        self._headers(status, content_type, len(value), cache=cache)
        if self.command != "HEAD":
            self.wfile.write(value)

    def _text(self, message: str, status: int = 200) -> None:
        self._bytes(message.encode("utf-8"), status, "text/plain; charset=utf-8")

    def _json(self, value: Any, status: int = 200) -> None:
        raw = json.dumps(value, ensure_ascii=False).encode("utf-8")
        self._bytes(raw, status, "application/json; charset=utf-8")

    def _redirect(self, location: str) -> None:
        self.send_response(HTTPStatus.SEE_OTHER)
        self.send_header("Location", location)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def _path(self) -> str:
        path = urlsplit(self.path).path
        base = self.server.base_path
        if base and path.startswith(base + "/"):
            path = path[len(base):]
        return path

    def do_HEAD(self) -> None:
        self.do_GET()

    def do_GET(self) -> None:
        try:
            self._get()
        except KeyError:
            self._text("预览不存在。", 404)
        except ValueError as exc:
            self._text(str(exc), 400)
        except (OSError, json.JSONDecodeError):
            logger.exception("course preview GET failed")
            self._text("暂时无法读取预览，请稍后重试。", 500)

    def _get(self) -> None:
        path = self._path()
        if path == "/healthz":
            self._json({"ok": True})
            return
        if path == "/assets/preview.css":
            asset = Path(__file__).with_name("assets") / "preview.css"
            self._bytes(asset.read_bytes(), content_type="text/css; charset=utf-8", cache=True)
            return
        parts = [part for part in path.split("/") if part]
        if not parts:
            self._bytes(render_catalog(self.server.store.courses(), base_path=self.server.base_path).encode("utf-8"))
            return
        if len(parts) == 2 and parts[0] == "c":
            course = self.server.store.course(parts[1])
            self._bytes(render_course(course, base_path=self.server.base_path).encode("utf-8"))
            return
        if len(parts) == 2 and parts[0] == "p":
            preview_id = parts[1]
            meta = self.server.store.meta(preview_id)
            payload = self.server.store.revision(preview_id)
            document = build_document(payload["section"])
            query = parse_qs(urlsplit(self.path).query)
            page = render_outline(
                document,
                meta,
                base_path=self.server.base_path,
                feedback_count=len(self.server.store.feedback(preview_id)),
                saved=query.get("saved") == ["1"],
            )
            self._bytes(page.encode("utf-8"))
            return
        if len(parts) == 4 and parts[0] == "p" and parts[2] == "lesson":
            preview_id = parts[1]
            meta = self.server.store.meta(preview_id)
            payload = self.server.store.revision(preview_id)
            document = build_document(payload["section"])
            lesson = document.lesson(parts[3])
            if lesson is None:
                self._text("课时不存在。", 404)
                return
            query = parse_qs(urlsplit(self.path).query)
            page = render_lesson(
                document,
                lesson,
                meta,
                base_path=self.server.base_path,
                saved=query.get("saved") == ["1"],
            )
            self._bytes(page.encode("utf-8"))
            return
        self._text("没有此页面。", 404)

    def do_POST(self) -> None:
        try:
            self._post()
        except KeyError:
            self._text("预览不存在。", 404)
        except ValueError as exc:
            self._text(str(exc), 400)
        except (OSError, json.JSONDecodeError):
            logger.exception("course preview POST failed")
            self._text("暂时无法保存反馈，请稍后重试。", 500)

    def _post(self) -> None:
        parts = [part for part in self._path().split("/") if part]
        if len(parts) != 3 or parts[0] != "p" or parts[2] != "feedback":
            self._text("没有此页面。", 404)
            return
        preview_id = parts[1]
        content_type = self.headers.get_content_type()
        if content_type != "application/x-www-form-urlencoded":
            self._text("反馈格式不正确。", 415)
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError as exc:
            raise ValueError("请求长度不正确。") from exc
        if length <= 0 or length > _MAX_FORM_BYTES:
            self._text("反馈内容为空或过长。", 413)
            return
        values = parse_qs(
            self.rfile.read(length).decode("utf-8"),
            keep_blank_values=True,
            max_num_fields=20,
        )
        if values.get("website", [""])[0].strip():
            self._redirect(f"{self.server.base_path}/p/{preview_id}/?saved=1")
            return
        if not self._rate_allowed(preview_id):
            self._text("提交太频繁，请稍后再试。", 429)
            return
        try:
            revision = int(values.get("revision", ["0"])[0])
        except ValueError as exc:
            raise ValueError("反馈修订号不正确。") from exc
        item_key = values.get("item_key", [""])[0]
        entry = self.server.store.add_feedback(
            preview_id,
            revision=revision,
            item_key=item_key,
            category=values.get("category", ["other"])[0],
            reviewer=values.get("reviewer", [""])[0],
            message=values.get("message", [""])[0],
        )
        if item_key and entry.get("question"):
            document = build_document(self.server.store.revision(preview_id, revision)["section"])
            item = document.item(item_key)
            if item is not None:
                for lesson in document.lessons:
                    if any(candidate.key == item_key for candidate in lesson.items):
                        self._redirect(
                            f"{self.server.base_path}/p/{preview_id}/lesson/{lesson.ref}?saved=1#{item.anchor}"
                        )
                        return
        self._redirect(f"{self.server.base_path}/p/{preview_id}/?saved=1")

    def _rate_allowed(self, preview_id: str) -> bool:
        now = time.monotonic()
        key = f"{self.client_address[0]}:{preview_id}"
        events = self.server.rate_events[key]
        while events and now - events[0] > self.server.rate_window:
            events.popleft()
        if len(events) >= self.server.rate_limit:
            return False
        events.append(now)
        return True


def create_server(
    host: str,
    port: int,
    store: PreviewStore,
    *,
    public_base: str = "",
    rate_limit: int = 12,
    rate_window: float = 600.0,
) -> PreviewHttpServer:
    return PreviewHttpServer(
        (host, port),
        store,
        public_base=public_base,
        rate_limit=rate_limit,
        rate_window=rate_window,
    )


def run_server(host: str, port: int, store: PreviewStore, *, public_base: str) -> None:
    server = create_server(host, port, store, public_base=public_base)
    logger.info("course preview listening on %s:%s", host, port)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
