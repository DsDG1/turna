"""Local /why explanations for validate problems (E1.7 / O-06 / K-02 / K-15).

L-local only — no network. Never mutates validate state or course JSON.

v4.17 K-02: besides structural validate/lint problems, ``why_explain`` now
also covers the 6 content_quality dimensions. Quality issues arrive as
problem dicts produced by ``ContentQualityReport.to_problem_dicts()`` and
carry a ``dimension`` field (path ``quality.{dim}``, message ``[dim] ...``).
Dimension rules are checked after the structural rules and before the generic
fallback, so a tagged quality issue never falls through to ``fallback``.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from src.backend.error_mapper import humanize_problem


@dataclass(frozen=True)
class WhyResult:
    """Human explanation for one problem."""

    summary: str
    detail: str
    action_id: str | None = None
    rule_id: str = ""

    def as_dict(self) -> dict[str, Any]:
        return {
            "summary": self.summary,
            "detail": self.detail,
            "action_id": self.action_id,
            "rule_id": self.rule_id,
        }


# (rule_id, predicate keywords in message+path lower, summary, detail, action)
_RULES: tuple[tuple[str, tuple[str, ...], str, str, str | None], ...] = (
    (
        "dangling_word",
        ("dangling", "missing wordid", "unknown word", "wordid", "word id"),
        "题目引用了不存在的词条",
        "题面里的 wordId 在词库中找不到。请在资源库补词，或改题时从词库重选。"
        "不要手改 id 字符串。",
        "resource.fill_stubs",
    ),
    (
        "dangling_expression",
        ("missing expressionid", "unknown expression", "expressionid"),
        "题目引用了不存在的表达",
        "expressionId 未出现在全局表达列表。请补表达资源或改引用。",
        "resource.fill_stubs",
    ),
    (
        "duplicate_options",
        ("duplicate option", "duplicate options", "options must be unique", "重复选项"),
        "选项重复",
        "选择题的 options 中有相同文案，干扰项无效。请改写干扰项或用芯片「换干扰」。",
        "validate.open_and_fix",
    ),
    (
        "duplicate_id",
        ("duplicate id", "duplicate lesson id", "already exists", "id conflict", "冲突"),
        "存在重复编号",
        "两个节点用了相同 id。校验要求 id 全局/同层唯一。请改名或删除重复项，"
        "切勿让 AI 静默删 id。",
        "validate.open_and_fix",
    ),
    (
        "empty_prompt",
        ("empty prompt", "missing prompt", "prompt is empty", "prompt 为空", "空题干"),
        "题干为空",
        "交互缺少 prompt/sentence 等题面字段。请手填或用题卡芯片让 AI 改写。",
        "lesson.fill_empty",
    ),
    (
        "missing_transcript",
        ("transcript", "listening", "audioasset", "audio asset", "听力题缺少", "听力阶段"),
        "听力材料不完整",
        "听力阶段缺少 transcript 或 audioAsset，或 listening 阶段没有题目。"
        "可用「补全听力缺口」让 AI 生成 audioAsset/transcript（需预览确认）。",
        "listening.fill_gaps",
    ),
    (
        "empty_lesson",
        ("empty lesson", "no items", "no stages", "空课", "content is empty"),
        "课程内容为空",
        "该课没有可用 stages/items。可用「填充空课」生成草稿后再人工审校。",
        "lesson.fill_empty",
    ),
    (
        "unknown_runtime",
        ("runtimeType", "unknown interaction", "unsupported type", "非法题型"),
        "题型不被支持",
        "runtimeType 不在课程契约允许列表中。请改为已知题型，或用编辑器切换题型。",
        "validate.open_and_fix",
    ),
    (
        "placeholder",
        ("[待补]", "needs-review", "placeholder", "待补", "needs_review"),
        "存在待补/待审资源",
        "词条或表达仍是占位文案。可用「清待补」批量补全，再人工核对翻译。",
        "resource.fill_stubs",
    ),
)


# v4.17 K-02: content_quality dimension rules. Keyed by the ``dimension``
# field that ``ContentQualityReport.to_problem_dicts()`` carries. Each rule
# maps to a concrete action_id (reusing existing skills) or None when the
# dimension is advisory-only (coverage -> 手编). Checked after structural
# rules, before the generic fallback.
_DIM_RULES: dict[str, tuple[str, str, str, str | None]] = {
    "coverage": (
        "quality_coverage",
        "词汇覆盖不足",
        "部分词条在非展示型练习里没有被再次用到，复用度偏低。请增加引用这些词的"
        "练习题，或精简词表。属建议性维度，无一键 AI 修复，建议手编补题。",
        None,
    ),
    "balance": (
        "quality_balance",
        "题型配比失衡",
        "该课的题型分布过于单一或与模板建议的题型交集为空。可用「调整题型配比」"
        "让 AI 按配比指令重生成（需预览确认），或手编增补缺失题型。",
        "lesson.balance",
    ),
    "distractor": (
        "quality_distractor",
        "干扰项质量不足",
        "选择题出现重复选项、选项过少或长度差异异常。可在教师模式点「换干扰」"
        "芯片让 AI 强化干扰项（PreviewHost 确认），或手编改写干扰项。",
        "item.distractor_boost",
    ),
    "level_fit": (
        "quality_level_fit",
        "难度与级别不匹配",
        "每课词量或句长超出该 CEFR 级别上限。请拆分长课、精简长句，或运行"
        "「校验并批量修复」让 AI 提议补丁（需预览确认）。",
        "validate.open_and_fix",
    ),
    "audio_ready": (
        "quality_audio_ready",
        "听力材料不完整",
        "听力题缺少 audioAsset/transcript，或听力阶段没有题目。可用「补全听力缺口」"
        "让 AI 生成 audioAsset/transcript（需预览确认）。",
        "listening.fill_gaps",
    ),
    "resource_hygiene": (
        "quality_resource_hygiene",
        "资源卫生不达标",
        "词条/表达存在占位、待审、空翻译或悬空引用。可用「打开资源 · 仅看待补」"
        "定位并人工补全，再运行「清待补」批量修复。",
        "resource.open_hygiene",
    ),
}


def why_explain(problem: dict[str, Any] | None) -> WhyResult:
    """Explain one validate/lint **or** content_quality problem (local only)."""
    if not isinstance(problem, dict):
        return WhyResult(
            summary="无法解释",
            detail="问题对象为空或格式不正确。",
            rule_id="invalid",
        )
    message = str(problem.get("message") or "")
    path = str(problem.get("path") or "")
    blob = f"{message} {path}".lower()
    human = humanize_problem(problem)

    # K-02: a ``dimension`` tag is the authoritative label for a
    # content_quality issue. It wins over structural keyword matching so a
    # quality issue whose message text happens to contain a structural keyword
    # (e.g. "[distractor] duplicate options") is explained as the quality
    # dimension, not mis-routed to a structural rule. Structural validate
    # problems carry no ``dimension`` field, so their behavior is unchanged.
    dim = str(problem.get("dimension") or "")
    if dim and dim in _DIM_RULES:
        rule_id, summary, detail, action = _DIM_RULES[dim]
        return WhyResult(
            summary=summary,
            detail=f"{human}\n\n可能原因：{detail}",
            action_id=action,
            rule_id=rule_id,
        )

    for rule_id, keys, summary, detail, action in _RULES:
        if any(k.lower() in blob for k in keys):
            return WhyResult(
                summary=summary,
                detail=f"{human}\n\n可能原因：{detail}",
                action_id=action,
                rule_id=rule_id,
            )

    level = str(problem.get("level") or "error")
    return WhyResult(
        summary=human if human else "校验未通过",
        detail=(
            f"级别：{level}\n原始信息：{message or '（无 message）'}\n"
            f"路径：{path or '（无 path）'}\n\n"
            "未命中专用规则。请对照 course-layout 契约检查该节点 JSON，"
            "或运行「校验并批量修复」让 AI 提议补丁（需预览确认）。"
        ),
        action_id="validate.open_and_fix",
        rule_id="fallback",
    )


def why_explain_many(
    problems: list[dict[str, Any]] | None, *, limit: int = 20
) -> list[WhyResult]:
    if not problems:
        return []
    out: list[WhyResult] = []
    for p in problems[: max(0, int(limit))]:
        if isinstance(p, dict):
            out.append(why_explain(p))
    return out
