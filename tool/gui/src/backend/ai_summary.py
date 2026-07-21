"""Generation-end summary for workshop Review (aiEnhance perception U0).

Pure functions, no Qt. Assembles validate + content_quality + grounded
coverage into a single card model the UI can bind without re-running logic.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from src.backend.ai_bench import count_needs_review, count_placeholders
from src.backend.content_quality import ContentQualityReport, score_section
from src.backend.grounded_stats import draft_coverage

_DIM_SHORT = {
    "coverage": "复现",
    "balance": "题型",
    "distractor": "干扰",
    "level_fit": "难度",
    "audio_ready": "听力",
    "resource_hygiene": "资源",
}


@dataclass
class GenerationSummary:
    """Advisory summary after AI generation (does not gate save/import)."""

    ok: bool
    error_count: int
    warning_count: int
    quality_mean: float | None
    quality_dims: dict[str, float] = field(default_factory=dict)
    quality_badge: str = "ok"
    placeholders: int = 0
    needs_review: int = 0
    grounded_coverage: float | None = None
    usage: dict[str, int] = field(default_factory=dict)
    cache_hit: bool = False
    model_json: str = ""
    mode: str = "fast"  # fast | refine | phased
    top_issues: list[dict[str, Any]] = field(default_factory=list)
    section_name: str = ""
    unit_count: int = 0
    lesson_count: int = 0
    word_count: int = 0


def _count_structural(structural: list[Any] | None) -> tuple[int, int]:
    errors = warnings = 0
    for p in structural or []:
        if isinstance(p, dict):
            level = str(p.get("level") or "error")
        else:
            level = "error"
        if level == "warning":
            warnings += 1
        else:
            errors += 1
    return errors, warnings


def build_generation_summary(
    section: dict[str, Any] | None,
    *,
    level: str = "A1",
    resource_pool: list[dict[str, Any]] | None = None,
    structural: list[Any] | None = None,
    usage: dict[str, int] | None = None,
    cache_hit: bool = False,
    model_json: str = "",
    mode: str = "fast",
    quality_report: ContentQualityReport | None = None,
) -> GenerationSummary:
    """Build a generation summary from a draft section and optional precomputes."""
    err_n, warn_n = _count_structural(structural)
    if not isinstance(section, dict):
        return GenerationSummary(
            ok=False,
            error_count=max(err_n, 1),
            warning_count=warn_n,
            quality_mean=None,
            usage=dict(usage or {}),
            cache_hit=cache_hit,
            model_json=model_json or "",
            mode=mode or "fast",
            top_issues=[{"level": "error", "message": "无有效草稿", "path": ""}],
        )

    report = quality_report or score_section(
        section,
        level=level,
        resource_pool=resource_pool,
        structural_errors=structural or None,
    )
    units = section.get("units") or []
    lessons = 0
    for u in units:
        if isinstance(u, dict):
            lessons += len(u.get("lessons") or [])

    cov_ratio: float | None = None
    if resource_pool:
        cov = draft_coverage(section, resource_pool)
        cov_ratio = float(cov.get("coverage_ratio") or 0.0)

    top = report.to_problem_dicts(max_issues=8)
    # Prefer structural errors first in top_issues when present.
    structural_top: list[dict[str, Any]] = []
    for p in structural or []:
        if not isinstance(p, dict):
            continue
        if p.get("level", "error") != "error":
            continue
        structural_top.append(
            {
                "level": "error",
                "path": p.get("path", ""),
                "message": p.get("message", ""),
            }
        )
        if len(structural_top) >= 5:
            break
    merged_top = structural_top + [t for t in top if t not in structural_top]

    return GenerationSummary(
        ok=err_n == 0,
        error_count=err_n,
        warning_count=warn_n,
        quality_mean=report.mean,
        quality_dims=dict(report.scores),
        quality_badge=report.badge(),
        placeholders=count_placeholders(section),
        needs_review=count_needs_review(section),
        grounded_coverage=cov_ratio,
        usage=dict(usage or {}),
        cache_hit=bool(cache_hit),
        model_json=model_json or "",
        mode=mode or "fast",
        top_issues=merged_top[:12],
        section_name=str(section.get("name") or section.get("id") or ""),
        unit_count=len([u for u in units if isinstance(u, dict)]),
        lesson_count=lessons,
        word_count=len(section.get("words") or []),
    )


def format_summary_card(summary: GenerationSummary) -> str:
    """Multi-line human-readable card for Review / status UI."""
    mode_label = {
        "fast": "快速",
        "refine": "精修",
        "phased": "精修",
    }.get(summary.mode, summary.mode)
    struct = (
        "结构校验通过"
        if summary.ok
        else f"结构校验 {summary.error_count} 错误 / {summary.warning_count} 警告"
    )
    lines = [
        f"【生成摘要】{summary.section_name or '草稿'} · 模式 {mode_label}",
        (
            f"{summary.unit_count} 单元 · {summary.lesson_count} 课时 · "
            f"{summary.word_count} 词 · {struct}"
        ),
    ]
    if summary.quality_mean is not None:
        dim_parts = []
        for dim, score in summary.quality_dims.items():
            label = _DIM_SHORT.get(dim, dim)
            dim_parts.append(f"{label} {score:.2f}")
        lines.append(
            f"内容质量 {summary.quality_mean:.2f}（{summary.quality_badge}）"
            + (f"：{' · '.join(dim_parts)}" if dim_parts else "")
        )
    hygiene_bits = []
    if summary.placeholders:
        hygiene_bits.append(f"[待补]×{summary.placeholders}")
    if summary.needs_review:
        hygiene_bits.append(f"needs-review×{summary.needs_review}")
    if hygiene_bits:
        lines.append("资源卫生：" + " · ".join(hygiene_bits))
    if summary.grounded_coverage is not None:
        lines.append(f"Grounded 覆盖率 {summary.grounded_coverage:.0%}")
    meta = []
    if summary.model_json:
        meta.append(f"模型 {summary.model_json}")
    if summary.cache_hit:
        meta.append("缓存命中")
    usage = summary.usage or {}
    if usage.get("total_tokens") or usage.get("prompt_tokens"):
        total = usage.get("total_tokens") or (
            int(usage.get("prompt_tokens") or 0)
            + int(usage.get("completion_tokens") or 0)
        )
        meta.append(f"tokens≈{total}")
    if meta:
        lines.append(" · ".join(meta))
    if summary.top_issues:
        lines.append("优先关注：")
        for issue in summary.top_issues[:5]:
            msg = str(issue.get("message") or "")
            path = str(issue.get("path") or "")
            prefix = f"{path}: " if path else ""
            lines.append(f"  · {prefix}{msg}")
    lines.append("（质量分为建议性，不阻断导入；写盘仍以结构校验为准）")
    return "\n".join(lines)


def format_ai_status_line(
    *,
    model_json: str = "",
    model_chat: str = "",
    cache_hit: bool | None = None,
    usage: dict[str, int] | None = None,
    mode: str = "",
) -> str:
    """One-line status bar text for workshop / main window."""
    parts: list[str] = []
    if mode:
        parts.append({"fast": "快速", "refine": "精修", "phased": "精修"}.get(mode, mode))
    if model_json:
        parts.append(f"json:{model_json}")
    if model_chat and model_chat != model_json:
        parts.append(f"chat:{model_chat}")
    if cache_hit is True:
        parts.append("缓存✓")
    elif cache_hit is False:
        parts.append("缓存·")
    usage = usage or {}
    total = usage.get("total_tokens")
    if total is None and (usage.get("prompt_tokens") or usage.get("completion_tokens")):
        total = int(usage.get("prompt_tokens") or 0) + int(
            usage.get("completion_tokens") or 0
        )
    if total:
        parts.append(f"{total} tok")
    return " · ".join(parts)
