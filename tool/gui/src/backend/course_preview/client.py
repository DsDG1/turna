from __future__ import annotations

import json
import subprocess
from typing import Any


class PreviewSyncError(RuntimeError):
    pass


class SshPreviewClient:
    def __init__(
        self,
        ssh_target: str = "turna",
        *,
        remote_root: str = "/opt/turna-course-preview",
        remote_data: str = "/var/lib/turna-course-preview",
        public_base: str = "https://turnalangua.xyz/course-preview",
        service_user: str = "turna-preview",
        timeout: float = 60.0,
    ) -> None:
        self.ssh_target = ssh_target
        self.remote_root = remote_root
        self.remote_data = remote_data
        self.public_base = public_base
        self.service_user = service_user
        self.timeout = timeout

    def _command(self, action: str, *arguments: str) -> list[str]:
        return [
            "ssh",
            "-o",
            "BatchMode=yes",
            "-o",
            "ConnectTimeout=10",
            self.ssh_target,
            "runuser",
            "-u",
            self.service_user,
            "--",
            "/usr/bin/env",
            f"PYTHONPATH={self.remote_root}",
            "/usr/bin/python3",
            "-m",
            "src.backend.course_preview.cli",
            "--root",
            self.remote_data,
            "--public-base",
            self.public_base,
            action,
            *arguments,
        ]

    def _run(self, action: str, *arguments: str, payload: Any = None) -> dict[str, Any]:
        stdin = None
        if payload is not None:
            stdin = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        try:
            result = subprocess.run(
                self._command(action, *arguments),
                input=stdin,
                capture_output=True,
                timeout=self.timeout,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise PreviewSyncError(f"无法连接课程预览服务器：{exc}") from exc
        if result.returncode != 0:
            detail = result.stderr.decode("utf-8", errors="replace").strip()
            if not detail:
                detail = result.stdout.decode("utf-8", errors="replace").strip()
            if len(detail) > 2000:
                detail = detail[-2000:]
            raise PreviewSyncError(detail or f"预览服务返回错误（{result.returncode}）。")
        try:
            value = json.loads(result.stdout.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise PreviewSyncError("预览服务返回了无法识别的响应。") from exc
        if not isinstance(value, dict):
            raise PreviewSyncError("预览服务响应格式不正确。")
        return value

    def publish(self, section: dict[str, Any], preview_id: str = "") -> dict[str, Any]:
        arguments = ["--preview-id", preview_id] if preview_id else []
        return self._run("publish", *arguments, payload=section)

    def publish_course(self, bundle: dict[str, Any]) -> dict[str, Any]:
        return self._run("publish-course", payload=bundle)

    def feedback(self, preview_id: str) -> list[dict[str, Any]]:
        result = self._run("feedback", "--preview-id", preview_id)
        entries = result.get("feedback")
        if not isinstance(entries, list):
            raise PreviewSyncError("预览服务没有返回反馈列表。")
        return [entry for entry in entries if isinstance(entry, dict)]
