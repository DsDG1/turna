"""Rule-based intent router for the ⌘K palette (E1, C-05; C-06 async bypass).

Pure Python, no Qt. ``action_id`` uses the same namespace as
``backend.experience.actions``; ``app.*`` ids are built-in window actions
handled by the main window itself (save / undo / help).

This module is the **synchronous** source of truth (slash + keywords). When
local match is empty, C-06 may asynchronously classify via
``backend.experience.intent_llm`` (default off) and only *suggest* candidates
— it never auto-executes and must not override an exact slash hit.

v4.47 conf contract (§8.5):
* exact slash → confidence **1.0** (no S-04)
* keyword / label substring → confidence **0.6** (S-04 for write actions)
* history replay (palette) → **0.6** (set by palette_controller)
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


# Shared confidence for any non-exact (keyword / label) match — keeps S-04 armed.
KEYWORD_CONFIDENCE = 0.6
# Exact slash command confidence.
SLASH_CONFIDENCE = 1.0
# Minimum query length (Unicode code points) for label/cmd substring match.
MIN_LABEL_MATCH_LEN = 2


@dataclass(frozen=True)
class Intent:
    """A routed command: what to run and how to show it."""

    action_id: str
    label: str
    confidence: float = 1.0
    scope: dict[str, Any] = field(default_factory=dict)


# Optional display group prefix for empty-query list (UX F13). Not used in routing.
_GROUP: dict[str, str] = {
    "validate.open_and_fix": "校验",
    "soft.preview_hygiene": "校验",
    "lesson.fill_empty": "填充",
    "resource.fill_stubs": "填充",
    "resource.fill_stubs_batch": "资源",
    "listening.fill_gaps": "听力",
    "listening.transcript_gap": "听力",
    "item.to_listening": "听力",
    "lesson.regenerate": "生成",
    "unit.regenerate": "生成",
    "section.edit": "生成",
    "unit.edit": "生成",
    "lesson.edit": "生成",
    "lesson.balance": "生成",
    "unit.spiral_vocab": "生成",
    "reading.passages_gen": "生成",
    "item.distractor_boost": "题型",
    "item.rewrite": "题型",
    "item.similar": "题型",
    "lesson.batch_set_template": "题型",
    "lesson.batch_regenerate": "生成",
    "unit.batch_regenerate": "生成",
    "resource.open_hygiene": "资源",
    "resource.dedupe_suggest": "资源",
    "resource.align_pos_tags": "资源",
    "resource.batch_polish": "资源",
    "resource.resolve_term_conflicts": "资源",
    "course.compare_sections": "分析",
    "course.outline_shells": "生成",
    "attachment.open_in_workshop": "工坊",
    "textbook.ocr_suggest": "工坊",
    "textbook.open_workshop": "工坊",
    "textbook.import_draft": "工坊",
    "textbook.grounded_fill": "工坊",
    "goal.plan": "Goal",
    "goal.expand": "Goal",
    "goal.run": "Goal",
    "publish.brief": "发布",
    "git.commit_message": "Git",
    "git.explain_diff": "Git",
    "app.screenshot_explain": "只读",
    "app.why": "只读",
    "app.pin": "窗口",
    "app.save": "窗口",
    "app.undo": "窗口",
    "app.help": "窗口",
    "memory.clear_author": "隐私",
}


def _grouped_label(action_id: str, label: str, cmd: str | None = None) -> str:
    g = _GROUP.get(action_id)
    core = f"{label}（{cmd}）" if cmd else label
    return f"【{g}】{core}" if g else core


# (slash command, action_id, display label) — v1 fixed table.
SLASH_COMMANDS: tuple[tuple[str, str, str], ...] = (
    ("/validate", "validate.open_and_fix", "校验并批量修复"),
    ("/fill", "lesson.fill_empty", "填充空课"),
    ("/stubs", "resource.fill_stubs", "清待补词条"),
    ("/listening", "listening.fill_gaps", "补全听力缺口"),
    ("/transcript-gap", "listening.transcript_gap", "补全听力 transcript 缺口"),
    ("/soft", "soft.preview_hygiene", "规则规范化（预览）"),
    ("/resources", "resource.open_hygiene", "打开资源 · 仅看待补"),
    ("/regenerate", "lesson.regenerate", "重生成当前课 / 单元"),
    ("/ai-edit", "lesson.edit", "AI 编辑当前节 / 单元 / 课"),
    ("/balance", "lesson.balance", "调整题型配比"),
    # Honest: opens teacher chip path only (F8).
    ("/distractors", "item.distractor_boost", "强化干扰项（教师芯片 · 需选中题）"),
    ("/to-listening", "item.to_listening", "迁为听力题"),
    ("/similar", "item.similar", "改写为相似题（需选中题）"),
    ("/spiral", "unit.spiral_vocab", "补充词汇螺旋复现"),
    ("/reading-gen", "reading.passages_gen", "生成阅读段落"),
    # F9: multi-select required.
    ("/batch-template", "lesson.batch_set_template", "批量设置课型（需多选课）"),
    ("/batch-regen", "lesson.batch_regenerate", "批量重生成选中课（需多选）"),
    (
        "/unit-batch-regen",
        "unit.batch_regenerate",
        "批量重生成选中单元（需多选）",
    ),
    ("/dedupe", "resource.dedupe_suggest", "查重重复词条"),
    ("/pos-align", "resource.align_pos_tags", "对齐词条词性（POS）"),
    ("/polish", "resource.batch_polish", "批量润色选中词条（需多选）"),
    ("/fill-stubs", "resource.fill_stubs_batch", "AI 补全待补词条（全局资源）"),
    ("/conflicts", "resource.resolve_term_conflicts", "统一词条冲突释义"),
    ("/compare", "course.compare_sections", "对比两节课"),
    ("/outline", "course.outline_shells", "大纲生成课壳（粘贴大纲）"),
    ("/attachments", "attachment.open_in_workshop", "打开工坊 · 查看附件"),
    ("/goal", "goal.plan", "Goal 规划（local / 沙箱）"),
    ("/goal-expand", "goal.expand", "Goal 加深规划"),
    ("/goal-run", "goal.run", "Goal 沙箱预演并合并"),
    ("/publish", "publish.brief", "发布 Brief / 打开发布"),
    ("/commit-message", "git.commit_message", "生成提交信息"),
    ("/explain-diff", "git.explain_diff", "解释 Diff"),
    ("/screenshot-explain", "app.screenshot_explain", "截图解释（只读）"),
    ("/ocr", "textbook.ocr_suggest", "OCR 图片附件"),
    ("/workshop", "textbook.open_workshop", "打开课程工坊"),
    ("/import-draft", "textbook.import_draft", "导入工坊草稿"),
    ("/grounded-fill", "textbook.grounded_fill", "基于附件填充空课"),
    ("/clear-profile", "memory.clear_author", "清除作者画像"),
    ("/why", "app.why", "解释当前校验问题"),
    ("/pin", "app.pin", "钉住 / 取消钉住当前选中"),
    ("/save", "app.save", "保存课程"),
    ("/undo", "app.undo", "撤销"),
    ("/help", "app.help", "命令清单（点击执行）"),
)

_LABELS: dict[str, str] = {action_id: label for _c, action_id, label in SLASH_COMMANDS}

# Free-text keyword rules (substring match, Chinese-first).
# Order matters: more specific phrases before broad ones.
# v4.47 F5: tightened publish/balance; F6: help/attachments/ocr; dedupe to_listening.
_KEYWORDS: tuple[tuple[tuple[str, ...], str], ...] = (
    (("修错", "校验", "修全部", "修复错误"), "validate.open_and_fix"),
    (("空课", "填充空课", "填充"), "lesson.fill_empty"),
    (("打开资源", "资源编辑", "仅看待补"), "resource.open_hygiene"),
    (("清理待补", "补全词条", "待补词条", "待补"), "resource.fill_stubs"),
    # Distinct from the broad「待补」row above: these more-specific phrases route
    # to the FieldPatch batch variant (v4.65). Order keeps「待补」-> fill_stubs.
    # NOTE: any keyword containing「待补」or「补全词条」as a substring still
    # matches the existing fill_stubs row — use batch/global phrasing without
    # those substrings.
    (
        ("批量补齐资源", "全局补齐资源", "批量润色待完善", "fill stubs"),
        "resource.fill_stubs_batch",
    ),
    # Specific before broad「听力」.
    (
        ("迁为听力题", "转听力题", "改成听力题", "to listening", "迁为听力"),
        "item.to_listening",
    ),
    (("听力缺口", "补全听力", "listening"), "listening.fill_gaps"),
    (("听力",), "listening.fill_gaps"),  # broad; conf 0.6 → S-04
    (
        ("transcript 缺口", "缺 transcript", "听力文本缺口", "transcript gap"),
        "listening.transcript_gap",
    ),
    (("规范化", "去空白", "规则清理", "规则规范化"), "soft.preview_hygiene"),
    # unit batch before generic lesson batch before bare「重生成」.
    (
        (
            "批量重生成单元",
            "多单元重生成",
            "批量单元",
            "unit batch regen",
        ),
        "unit.batch_regenerate",
    ),
    (
        ("批量重生成", "多课重生成", "批量 regenerate", "batch regen"),
        "lesson.batch_regenerate",
    ),
    # AI freeform edit (dialog) before bare「重生成」.
    (
        (
            "AI 编辑",
            "ai 编辑",
            "编辑本节",
            "编辑本单元",
            "编辑本课",
            "AI编辑",
        ),
        "lesson.edit",
    ),
    (("重生成", "重新生成", "重写本课", "重写本单元"), "lesson.regenerate"),
    # F5: no bare「配比」— too short / ambiguous.
    (("题型配比", "配比失衡", "题型单一", "调整配比"), "lesson.balance"),
    (("干扰项", "换干扰", "干扰强化"), "item.distractor_boost"),
    (("相似题", "出相似题", "平行题", "similar item"), "item.similar"),
    (("螺旋复现", "词汇螺旋", "未复现词", "spiral"), "unit.spiral_vocab"),
    (("阅读段落", "生成阅读", "补阅读段", "reading passage"), "reading.passages_gen"),
    (("批量课型", "统一课型", "批量设置课型"), "lesson.batch_set_template"),
    (("查重", "重复词条", "重复词", "dedupe"), "resource.dedupe_suggest"),
    (("词性对齐", "POS 对齐", "标签一致", "对齐词性", "align pos"), "resource.align_pos_tags"),
    # V-02: 选中词条批量润色/补全发音；排在「查重」「词性对齐」后。
    (("批量润色", "润色词条", "补全发音", "polish"), "resource.batch_polish"),
    # V-06: 同 term 异译冲突仲裁；排在「查重」后（冲突 ≠ 重复）。
    (("词条冲突", "释义冲突", "冲突仲裁", "统一冲突"), "resource.resolve_term_conflicts"),
    (("对比两节", "比较章节", "章节对比", "对比 section", "compare"), "course.compare_sections"),
    (("大纲", "课程大纲", "大纲生成", "课壳", "outline"), "course.outline_shells"),
    (("目标规划", "goal plan", "课程目标", "一句话目标", "goal"), "goal.plan"),
    (("加深规划", "goal expand", "扩展目标"), "goal.expand"),
    (("目标执行", "goal run", "沙箱合并"), "goal.run"),
    # F5: 「发布」alone kept but with publish/上架; still conf 0.6.
    (("打开发布", "发布 brief", "上架", "publish"), "publish.brief"),
    (("发布",), "publish.brief"),
    (("提交信息", "commit message", "生成提交", "commit"), "git.commit_message"),
    (("解释 diff", "解释改动", "explain diff", "diff 说明"), "git.explain_diff"),
    (("截图解释", "截图说明", "解释截图", "screenshot explain", "截图"), "app.screenshot_explain"),
    # F6 gaps.
    (("附件", "查看附件", "attachments"), "attachment.open_in_workshop"),
    (("OCR", "ocr", "识别文字", "文字识别"), "textbook.ocr_suggest"),
    (("打开工坊", "课程工坊", "open workshop"), "textbook.open_workshop"),
    (("导入草稿", "导入工坊", "教材导入", "import draft"), "textbook.import_draft"),
    (
        ("基于附件填充", "附件填充", "grounded fill", "附件生成空课"),
        "textbook.grounded_fill",
    ),
    (("清除画像", "清空画像", "清除作者画像", "clear profile", "clear author"), "memory.clear_author"),
    (("为什么", "为何", "怎么错", "解释错误"), "app.why"),
    (("钉住", "固定选中"), "app.pin"),
    (("保存",), "app.save"),
    (("撤销",), "app.undo"),
    (("帮助", "命令清单", "help"), "app.help"),
)


def route_intent(text: str) -> Intent | None:
    """Route free text or an exact slash command to a single intent.

    Returns ``None`` when nothing matches with confidence — the UI must
    show a hint rather than executing a guess (融合红线：改错对象).
    """
    t = (text or "").strip()
    if not t:
        return None
    low = t.lower()
    for cmd, action_id, label in SLASH_COMMANDS:
        if low == cmd:
            return Intent(
                action_id=action_id,
                label=label,
                confidence=SLASH_CONFIDENCE,
            )
    for words, action_id in _KEYWORDS:
        # Case-insensitive for Latin keywords (OCR, help, …).
        if any((w in t) or (w.lower() in low) for w in words):
            return Intent(
                action_id=action_id,
                label=_LABELS.get(action_id, action_id),
                confidence=KEYWORD_CONFIDENCE,
            )
    return None


def match_commands(query: str) -> list[Intent]:
    """Rank candidate intents for the palette list while typing.

    Empty query lists the full slash table (grouped labels); ``/`` prefixes
    filter by command (conf 1.0); free text filters by label (conf 0.6) when
    query length ≥ :data:`MIN_LABEL_MATCH_LEN`, else keyword fallback only.
    """
    raw = query or ""
    q = raw.strip().lower()
    if not q:
        return [
            Intent(
                action_id=action_id,
                label=_grouped_label(action_id, label, cmd),
                confidence=SLASH_CONFIDENCE,
            )
            for cmd, action_id, label in SLASH_COMMANDS
        ]
    out: list[Intent] = []
    if q.startswith("/"):
        for cmd, action_id, label in SLASH_COMMANDS:
            if cmd.startswith(q):
                out.append(
                    Intent(
                        action_id=action_id,
                        label=f"{label}（{cmd}）",
                        confidence=SLASH_CONFIDENCE,
                    )
                )
        return out
    # F4: skip broad label substring for 1-char queries (e.g. 「课」).
    if len(q) >= MIN_LABEL_MATCH_LEN:
        for cmd, action_id, label in SLASH_COMMANDS:
            if q in label.lower() or q in cmd:
                out.append(
                    Intent(
                        action_id=action_id,
                        label=label,
                        confidence=KEYWORD_CONFIDENCE,  # F1: was 0.8, S-04 bypass
                    )
                )
        if out:
            return out
    intent = route_intent(raw)
    return [intent] if intent is not None else []
