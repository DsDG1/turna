"""External AI config file (import / export / path policy).

Pure helpers, no Qt. The config file lives **outside the source repository**
and may contain the API key so authors can edit it by hand and keep secrets
off QSettings.

QSettings only remembers the absolute path (+ autoload/autosave flags).
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Mapping

CONFIG_KIND = "varnamala.ai_config"
CONFIG_VERSION = 1

# Closed set of AI fields written to / read from the external file.
_AI_KEYS: tuple[str, ...] = (
    "provider",
    "base_url",
    "api_key",
    "model",
    "model_chat",
    "model_json",
    "timeout",
    "temperature",
    "retry_max",
    "supports_reasoning",
    "strict_schema",
    "cache_enabled",
    "fill_needs_review",
    "max_parallel_lessons",
    "pipeline_default_mode",
)


def discover_repo_roots(*, extra: Path | None = None) -> list[Path]:
    """Best-effort git/repo roots that must not host the config file.

    Walks parents of this package (tool/gui) looking for ``.git``.
    Optionally includes *extra* (e.g. open course dir) when it is under a repo.
    Never raises.
    """
    roots: list[Path] = []
    seen: set[str] = set()

    def _add(p: Path | None) -> None:
        if p is None:
            return
        try:
            r = p.resolve()
            key = str(r)
            if key in seen:
                return
            seen.add(key)
            roots.append(r)
        except Exception:
            pass

    try:
        here = Path(__file__).resolve()
        for parent in [here.parent, *here.parents]:
            try:
                if (parent / ".git").exists():
                    _add(parent)
                    break
            except Exception:
                continue
    except Exception:
        pass

    if extra is not None:
        try:
            cur = Path(extra).resolve()
            for parent in [cur, *cur.parents]:
                try:
                    if (parent / ".git").exists():
                        _add(parent)
                        break
                except Exception:
                    continue
        except Exception:
            pass
    return roots


def is_path_outside_repos(path: str | Path, repo_roots: list[Path] | None = None) -> bool:
    """True when *path* is absolute-resolved and not under any repo root."""
    try:
        p = Path(path).expanduser().resolve()
    except Exception:
        return False
    roots = repo_roots if repo_roots is not None else discover_repo_roots()
    for root in roots:
        try:
            p.relative_to(root.resolve())
            return False
        except ValueError:
            continue
        except Exception:
            continue
    return True


def validate_external_path(
    path: str | Path,
    *,
    repo_roots: list[Path] | None = None,
    must_exist: bool = False,
) -> tuple[bool, str, Path | None]:
    """Validate path for external AI config.

    Returns ``(ok, message, resolved_path_or_none)``. Never raises.
    """
    try:
        raw = str(path or "").strip()
        if not raw:
            return False, "未指定配置文件路径", None
        p = Path(raw).expanduser()
        try:
            resolved = p.resolve()
        except Exception:
            return False, f"无法解析路径：{raw}", None
        roots = repo_roots if repo_roots is not None else discover_repo_roots()
        if not is_path_outside_repos(resolved, roots):
            return (
                False,
                "配置文件必须放在仓库之外（当前路径落在源码/课程仓库内）",
                None,
            )
        if must_exist and not resolved.is_file():
            return False, f"文件不存在：{resolved}", None
        if resolved.exists() and resolved.is_dir():
            return False, "路径是目录，请选择 JSON 文件", None
        return True, "", resolved
    except Exception as exc:
        return False, str(exc), None


def settings_to_ai_dict(settings: Any) -> dict[str, Any]:
    """Extract closed-set AI fields from a Settings-like object."""
    out: dict[str, Any] = {}
    try:
        out = {
            "provider": str(getattr(settings, "ai_provider", "custom") or "custom"),
            "base_url": str(getattr(settings, "ai_base_url", "") or ""),
            "api_key": str(getattr(settings, "ai_api_key", "") or ""),
            "model": str(getattr(settings, "ai_model", "") or ""),
            "model_chat": str(getattr(settings, "ai_model_chat", "") or ""),
            "model_json": str(getattr(settings, "ai_model_json", "") or ""),
            "timeout": float(getattr(settings, "ai_timeout", 120.0) or 120.0),
            "temperature": float(getattr(settings, "ai_temperature", 0.7) or 0.7),
            "retry_max": int(getattr(settings, "ai_retry_max", 1) or 0),
            "supports_reasoning": bool(
                getattr(settings, "ai_supports_reasoning", False)
            ),
            "strict_schema": str(
                getattr(settings, "ai_strict_schema", "auto") or "auto"
            ),
            "cache_enabled": bool(getattr(settings, "ai_cache_enabled", False)),
            "fill_needs_review": bool(
                getattr(settings, "ai_fill_needs_review", False)
            ),
            "max_parallel_lessons": int(
                getattr(settings, "ai_max_parallel_lessons", 1) or 1
            ),
            "pipeline_default_mode": str(
                getattr(settings, "ai_pipeline_default_mode", "fast") or "fast"
            ),
        }
    except Exception:
        return {k: "" for k in _AI_KEYS}
    return out


def build_document(settings: Any) -> dict[str, Any]:
    """Full JSON document for export."""
    return {
        "version": CONFIG_VERSION,
        "kind": CONFIG_KIND,
        "ai": settings_to_ai_dict(settings),
    }


def apply_ai_dict_to_settings(settings: Any, ai: Mapping[str, Any]) -> list[str]:
    """Apply closed-set AI fields onto *settings*. Returns list of applied keys."""
    applied: list[str] = []
    if settings is None or not isinstance(ai, Mapping):
        return applied
    try:
        if "provider" in ai:
            settings.ai_provider = str(ai.get("provider") or "custom")
            applied.append("provider")
        if "base_url" in ai:
            settings.ai_base_url = str(ai.get("base_url") or "")
            applied.append("base_url")
        if "api_key" in ai:
            settings.ai_api_key = str(ai.get("api_key") or "")
            applied.append("api_key")
        if "model" in ai:
            settings.ai_model = str(ai.get("model") or "")
            applied.append("model")
        if "model_chat" in ai:
            settings.ai_model_chat = str(ai.get("model_chat") or "")
            applied.append("model_chat")
        if "model_json" in ai:
            settings.ai_model_json = str(ai.get("model_json") or "")
            applied.append("model_json")
        if "timeout" in ai:
            try:
                settings.ai_timeout = max(
                    5.0, min(600.0, float(ai.get("timeout") or 120.0))
                )
                applied.append("timeout")
            except Exception:
                pass
        if "temperature" in ai:
            try:
                settings.ai_temperature = max(
                    0.0, min(2.0, float(ai.get("temperature") or 0.7))
                )
                applied.append("temperature")
            except Exception:
                pass
        if "retry_max" in ai:
            try:
                settings.ai_retry_max = max(0, min(5, int(ai.get("retry_max") or 0)))
                applied.append("retry_max")
            except Exception:
                pass
        if "supports_reasoning" in ai:
            settings.ai_supports_reasoning = bool(ai.get("supports_reasoning"))
            applied.append("supports_reasoning")
        if "strict_schema" in ai:
            v = str(ai.get("strict_schema") or "auto")
            if v not in {"auto", "on", "off"}:
                v = "auto"
            settings.ai_strict_schema = v
            applied.append("strict_schema")
        if "cache_enabled" in ai:
            settings.ai_cache_enabled = bool(ai.get("cache_enabled"))
            applied.append("cache_enabled")
        if "fill_needs_review" in ai:
            settings.ai_fill_needs_review = bool(ai.get("fill_needs_review"))
            applied.append("fill_needs_review")
        if "max_parallel_lessons" in ai:
            try:
                settings.ai_max_parallel_lessons = max(
                    1, min(8, int(ai.get("max_parallel_lessons") or 1))
                )
                applied.append("max_parallel_lessons")
            except Exception:
                pass
        if "pipeline_default_mode" in ai:
            v = str(ai.get("pipeline_default_mode") or "fast")
            if v not in {"fast", "refine"}:
                v = "fast"
            settings.ai_pipeline_default_mode = v
            applied.append("pipeline_default_mode")
    except Exception:
        return applied
    return applied


def parse_document(data: Any) -> tuple[dict[str, Any] | None, str]:
    """Parse loaded JSON into an ``ai`` dict. Returns (ai_dict, error)."""
    try:
        if not isinstance(data, dict):
            return None, "配置文件根节点必须是 JSON 对象"
        kind = str(data.get("kind") or "")
        if kind and kind != CONFIG_KIND:
            return None, f"未知 kind：{kind}（期望 {CONFIG_KIND}）"
        ai = data.get("ai")
        if ai is None and any(k in data for k in _AI_KEYS):
            # Flat document convenience for hand-edited files
            ai = {k: data[k] for k in _AI_KEYS if k in data}
        if not isinstance(ai, dict):
            return None, "缺少 ai 对象（或扁平字段）"
        return dict(ai), ""
    except Exception as exc:
        return None, str(exc)


def load_file(path: str | Path) -> tuple[dict[str, Any] | None, str]:
    """Load and parse external config. Returns (ai_dict, error)."""
    try:
        ok, msg, resolved = validate_external_path(path, must_exist=True)
        if not ok or resolved is None:
            return None, msg
        text = resolved.read_text(encoding="utf-8")
        data = json.loads(text)
        return parse_document(data)
    except json.JSONDecodeError as exc:
        return None, f"JSON 解析失败：{exc}"
    except Exception as exc:
        return None, str(exc)


def save_file(path: str | Path, settings: Any) -> tuple[bool, str]:
    """Write document from *settings* to *path*. Returns (ok, message)."""
    try:
        ok, msg, resolved = validate_external_path(path, must_exist=False)
        if not ok or resolved is None:
            return False, msg
        resolved.parent.mkdir(parents=True, exist_ok=True)
        doc = build_document(settings)
        text = json.dumps(doc, ensure_ascii=False, indent=2) + "\n"
        resolved.write_text(text, encoding="utf-8")
        return True, str(resolved)
    except Exception as exc:
        return False, str(exc)


def load_into_settings(path: str | Path, settings: Any) -> tuple[bool, str]:
    """Load file and apply AI fields to *settings*."""
    ai, err = load_file(path)
    if ai is None:
        return False, err
    keys = apply_ai_dict_to_settings(settings, ai)
    if not keys:
        return False, "配置文件中没有可识别的 AI 字段"
    return True, f"已加载 {len(keys)} 项：{', '.join(keys)}"
