#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import subprocess
import sys
import tarfile
import tempfile
from collections.abc import Sequence
from datetime import UTC, datetime
from pathlib import Path


_REPO = Path(__file__).resolve().parents[3]
_GUI = _REPO / "tool" / "gui"
_BEGIN = "# TURNA_COURSE_PREVIEW_BEGIN"
_END = "# TURNA_COURSE_PREVIEW_END"


def render_caddy_config(existing: str) -> str:
    block = (
        f"{_BEGIN}\n"
        "handle_path /course-preview/* {\n"
        "    reverse_proxy 127.0.0.1:8765\n"
        "}\n"
        f"{_END}"
    )
    if _BEGIN in existing and _END in existing:
        start = existing.index(_BEGIN)
        end = existing.index(_END, start) + len(_END)
        return existing[:start] + block + existing[end:]
    site_header = "turnalangua.xyz, www.turnalangua.xyz {"
    if site_header not in existing:
        raise RuntimeError("Caddyfile 中找不到现有 turnalangua.xyz 站点，拒绝自动修改。")
    start = existing.index(site_header)
    opening = existing.index("{", start)
    depth = 0
    closing = -1
    for index in range(opening, len(existing)):
        if existing[index] == "{":
            depth += 1
        elif existing[index] == "}":
            depth -= 1
            if depth == 0:
                closing = index
                break
    if closing < 0:
        raise RuntimeError("Caddyfile 站点块未闭合，拒绝自动修改。")
    body = existing[opening + 1:closing]
    static_lines = []
    other_lines = []
    for line in body.splitlines():
        stripped = line.strip()
        if stripped.startswith(("root ", "try_files ", "file_server")):
            static_lines.append("    " + stripped)
        elif stripped:
            other_lines.append(line)
    if not any(line.strip().startswith("root ") for line in static_lines):
        raise RuntimeError("Caddyfile 静态站点 root 不存在，拒绝自动修改。")
    if not any(line.strip() == "file_server" for line in static_lines):
        raise RuntimeError("Caddyfile 静态站点 file_server 不存在，拒绝自动修改。")
    handle = "\thandle {\n" + "\n".join("    " + line for line in static_lines) + "\n\t}"
    pieces = [block, handle, *other_lines]
    replacement = "\n\n".join(piece.rstrip() for piece in pieces if piece.strip())
    return existing[:opening + 1] + "\n" + replacement + "\n" + existing[closing:]


def systemd_unit(public_base: str) -> str:
    return f"""[Unit]
Description=Turna course previews
After=network.target

[Service]
Type=simple
User=turna-preview
Group=turna-preview
WorkingDirectory=/opt/turna-course-preview/current
Environment=PYTHONUNBUFFERED=1
ExecStart=/usr/bin/env PYTHONPATH=/opt/turna-course-preview /usr/bin/python3 -m src.backend.course_preview.cli --root /var/lib/turna-course-preview --public-base {public_base} serve --host 127.0.0.1 --port 8765
Restart=on-failure
RestartSec=2
UMask=0077
NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
ReadWritePaths=/var/lib/turna-course-preview

[Install]
WantedBy=multi-user.target
"""


_REMOTE_SETUP = r'''
import base64
import json
import os
import shutil
import subprocess
import sys
import tarfile
import time
import urllib.request
from pathlib import Path

payload = json.loads(base64.b64decode(sys.argv[1]))
release = payload["release"]
archive = Path(payload["archive"])
archive.write_bytes(base64.b64decode(payload["archive_data"]))
public_base = payload["public_base"]
root = Path("/opt/turna-course-preview")
release_dir = root / "releases" / release
current = root / "current"
data_dir = Path("/var/lib/turna-course-preview")
unit_path = Path("/etc/systemd/system/turna-course-preview.service")
caddy_path = Path("/etc/caddy/Caddyfile")
candidate = Path("/etc/caddy/Caddyfile.turna-preview-candidate")
backup_dir = Path("/etc/caddy/backups/turna-course-preview") / release
backup_dir.mkdir(parents=True, exist_ok=True)
caddy_backup = backup_dir / "Caddyfile"
unit_backup = backup_dir / "turna-course-preview.service"
previous_unit = unit_path.read_text(encoding="utf-8") if unit_path.exists() else None
previous_current = current.resolve() if current.exists() else None
caddy_installed = False
service_changed = False
log_path = backup_dir / "deploy.log"


def log(message):
    with log_path.open("a", encoding="utf-8") as handle:
        handle.write(message + "\n")


log("archive decoded")


def run(*args):
    try:
        result = subprocess.run(args, check=False, capture_output=True, text=True, timeout=45)
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError(f"command timed out: {' '.join(args)}") from exc
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "unknown error").strip()
        raise RuntimeError(f"{' '.join(args)}: {detail}")
    return result


def atomic_text(path, value):
    temporary = path.with_name(path.name + ".turna-preview-tmp")
    temporary.write_text(value, encoding="utf-8")
    os.replace(temporary, path)


def atomic_link(path, target):
    temporary = path.with_name(path.name + ".turna-preview-tmp")
    if temporary.exists() or temporary.is_symlink():
        temporary.unlink()
    temporary.symlink_to(target)
    os.replace(temporary, path)


def health(url):
    last = None
    for _ in range(20):
        try:
            with urllib.request.urlopen(url, timeout=3) as response:
                if response.status == 200:
                    return
        except Exception as exc:
            last = exc
        time.sleep(0.5)
    raise RuntimeError(f"health check failed: {url}: {last}")


def rollback():
    if caddy_installed:
        shutil.copy2(caddy_backup, caddy_path)
        run("systemctl", "reload", "caddy")
    if previous_unit is None:
        subprocess.run(("systemctl", "disable", "--now", "turna-course-preview.service"), capture_output=True)
        unit_path.unlink(missing_ok=True)
    else:
        atomic_text(unit_path, previous_unit)
    if previous_current is not None:
        atomic_link(current, previous_current)
    run("systemctl", "daemon-reload")
    if previous_unit is not None and previous_current is not None:
        run("systemctl", "restart", "turna-course-preview.service")


try:
    log("backing up Caddy")
    shutil.copy2(caddy_path, caddy_backup)
    if previous_unit is not None:
        shutil.copy2(unit_path, unit_backup)
    atomic_text(candidate, payload["caddy_config"])
    log("formatting Caddy candidate")
    run("caddy", "fmt", "--overwrite", str(candidate))
    log("validating Caddy candidate")
    run("caddy", "validate", "--config", str(candidate))

    log("creating service user and data directory")
    result = subprocess.run(("id", "-u", "turna-preview"), capture_output=True, text=True)
    if result.returncode != 0:
        run("useradd", "--system", "--home", "/nonexistent", "--shell", "/usr/sbin/nologin", "turna-preview")
    data_dir.mkdir(parents=True, exist_ok=True)
    run("chown", "-R", "turna-preview:turna-preview", str(data_dir))
    run("chmod", "700", str(data_dir))
    log("extracting release")
    release_dir.mkdir(parents=True, exist_ok=False)
    with tarfile.open(archive, "r:gz") as bundle:
        bundle.extractall(release_dir, filter="data")
    for directory, _, files in os.walk(release_dir):
        os.chmod(directory, 0o755)
        for name in files:
            os.chmod(Path(directory) / name, 0o644)
    log("activating release and writing unit")
    atomic_link(current, release_dir)
    src_link = root / "src"
    if not src_link.exists() and not src_link.is_symlink():
        src_link.symlink_to("current/src")
    atomic_text(unit_path, payload["service_unit"])
    run("chown", "root:root", str(unit_path))
    run("chmod", "644", str(unit_path))
    service_changed = True
    run("systemctl", "daemon-reload")
    run("systemctl", "enable", "turna-course-preview.service")
    log("restarting preview service")
    run("systemctl", "restart", "turna-course-preview.service")
    log("checking local health")
    health("http://127.0.0.1:8765/healthz")

    log("installing Caddy config")
    os.replace(candidate, caddy_path)
    caddy_installed = True
    run("systemctl", "reload", "caddy")
    log("checking public preview health")
    health(public_base + "/healthz")
    log("checking existing homepage")
    health("https://turnalangua.xyz/")
    log("success")
    print(json.dumps({"ok": True, "release": release, "health": public_base + "/healthz"}, ensure_ascii=False))
except Exception as exc:
    log("failure: " + type(exc).__name__)
    try:
        if service_changed or caddy_installed:
            rollback()
    finally:
        candidate.unlink(missing_ok=True)
    raise
'''


def _run(command: list[str], *, stdin: str | None = None, check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        command,
        input=stdin,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
        timeout=240,
    )
    if check and result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        raise RuntimeError(detail or f"命令失败：{command[0]}")
    return result


def _archive(target: Path, release: str) -> None:
    files = [_GUI / "src" / "__init__.py", _GUI / "src" / "backend" / "__init__.py"]
    package = _GUI / "src" / "backend" / "course_preview"
    files.extend(path for path in package.rglob("*") if path.is_file() and "__pycache__" not in path.parts)
    with tarfile.open(target, "w:gz") as bundle:
        for path in sorted(files):
            bundle.add(path, arcname=path.relative_to(_GUI))


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="部署 Turna 课程网页预览到 VPS")
    parser.add_argument("--ssh-target", default="turna")
    parser.add_argument("--public-base", default="https://turnalangua.xyz/course-preview")
    args = parser.parse_args(argv)
    stamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
    try:
        with tempfile.TemporaryDirectory(prefix="turna-course-preview-") as temporary:
            archive = Path(temporary) / "preview.tar.gz"
            _archive(archive, stamp)
            digest = hashlib.sha256(archive.read_bytes()).hexdigest()[:10]
            release = f"{stamp}-{digest}"
            remote_archive = f"/tmp/turna-course-preview-{release}.tar.gz"
            print("[1/4] 读取并生成 Caddy 候选配置…", flush=True)
            caddy = _run([
                "ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10",
                args.ssh_target, "cat", "/etc/caddy/Caddyfile",
            ]).stdout
            config = render_caddy_config(caddy)
            print("[2/4] 准备纯 SSH 传输包…", flush=True)
            archive_data = base64.b64encode(archive.read_bytes()).decode("ascii")
            payload = {
                "release": release,
                "archive": remote_archive,
                "public_base": args.public_base.rstrip("/"),
                "caddy_config": config,
                "service_unit": systemd_unit(args.public_base.rstrip("/")),
            }
            try:
                encoded_payload = base64.b64encode(
                    json.dumps(payload).encode("utf-8")
                ).decode("ascii")
                marker = "payload = json.loads(base64.b64decode(sys.argv[1]))"
                remote_script = _REMOTE_SETUP.replace(
                    marker,
                    marker + f"\npayload[\"archive_data\"] = {archive_data!r}",
                )
                print("[3/4] 上传代码、启动服务并执行健康检查…", flush=True)
                result = _run(
                    [
                        "ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10",
                        args.ssh_target, "python3", "-", encoded_payload,
                    ],
                    stdin=remote_script,
                )
                sys.stdout.write(result.stdout)
            finally:
                print("[4/4] 清理上传临时包…", flush=True)
                _run([
                    "ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10",
                    args.ssh_target, "rm", "-f", remote_archive,
                ], check=False)
        return 0
    except (OSError, RuntimeError, subprocess.SubprocessError) as exc:
        print(f"部署失败：{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
