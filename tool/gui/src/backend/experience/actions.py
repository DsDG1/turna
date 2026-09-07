"""Action registry for Experience suggestions (E1).

Pure Python, no Qt. The ``action_id`` namespace matches
``context_bus.local_suggestions``; the UI layer (``app.py``) dispatches
through this registry instead of a hard-coded if-chain. Actions that are
not implemented yet fall back to the E0 navigation placeholder.

红线：所有会产生写操作的 action 都必须 ``needs_confirm=True`` ——
执行路径必须经预览 + 人确认 + undo command，禁止静默写盘。
"""
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class ActionSpec:
    """One executable experience action."""

    action_id: str
    title: str
    implemented: bool = True
    needs_confirm: bool = True
    # C-20 危险 skill 标志：结构重写类动作（整课/整单元重生、批量设型、大纲壳）。
    # 默认 False。语义（v4.69 重定向）：dangerous 不再=「需总开关解锁才能派发」，
    # 而是=「immersive 下参与集合 C 的 auto-vs-confirm 分流」——
    #   * copilot/active：仍受 ``experience_allow_dangerous_skills`` 总开关锁定
    #     （``can_dispatch`` 在非 full-auto 下仍拒），开关开则经既有 confirm 派发；
    #   * immersive：dangerous 派发，C 成员 auto+Undo、非 C dangerous 落
    #     confirm（``is_auto_apply_allowed`` 分流）。
    # 见 ``AUTO_APPLY_DANGEROUS_WHEN_IMMERSIVE``（集合 C）与 ``is_dangerous_skill_allowed``。
    dangerous: bool = False


ACTIONS: dict[str, ActionSpec] = {
    "validate.open_and_fix": ActionSpec(
        "validate.open_and_fix", "校验并批量修复"
    ),
    "lesson.fill_empty": ActionSpec("lesson.fill_empty", "填充空课"),
    "resource.fill_stubs": ActionSpec("resource.fill_stubs", "清待补词条"),
    # E2.0 战役：队列对话框 + 定位 / AI 编辑（仍需人确认写盘）。
    "quality.campaign_worst_n": ActionSpec(
        "quality.campaign_worst_n", "低质战役", implemented=True
    ),
    # E2.1 听力缺口：把 content_quality 检测到的 audio_ready 缺口变成可行动建议。
    "listening.fill_gaps": ActionSpec("listening.fill_gaps", "补全听力缺口"),
    # v4.39 K-17：有音频但缺 transcript 的 item 缺口（复用 listening.fill_gaps 填路径，
    # 仅补 transcript，不覆盖已有 audio）。经 SectionDiffView 预览 + MergeAiSectionCommand。
    "listening.transcript_gap": ActionSpec(
        "listening.transcript_gap", "补全听力 transcript 缺口"
    ),
    # v4.12 Skills：包装 Soft 引擎（零 LLM）；显式确认 ≠ 默认开 Soft Autopilot。
    "soft.preview_hygiene": ActionSpec(
        "soft.preview_hygiene", "规则规范化（预览）", needs_confirm=True
    ),
    # v4.12 资源卫生入口：打开资源编辑器并滤到待补（人审，不写盘、不调 LLM）。
    "resource.open_hygiene": ActionSpec(
        "resource.open_hygiene", "打开资源 · 仅看待补", needs_confirm=False
    ),
    # v4.15 K-05：局部重生成。包装 aiEnhance regenerate_*_in_section（保 id
    # splice）；worker + SectionDiffView 确认 + MergeAiSectionCommand（红线：
    # 预览 + 人确认 + undo）。⌘K /regenerate 按当前 selection kind 分发。
    "lesson.regenerate": ActionSpec(
        "lesson.regenerate", "重生成当前课", dangerous=True
    ),
    "unit.regenerate": ActionSpec(
        "unit.regenerate", "重生成当前单元", dangerous=True
    ),
    # v4.61 K-05：包装已有节点 AI 编辑（NodeAiEditDialog + generate_edit）。
    # 写操作 needs_confirm 默认 True；实际预览/确认在对话框与 Undo 路径内。
    "section.edit": ActionSpec("section.edit", "AI 编辑当前节"),
    "unit.edit": ActionSpec("unit.edit", "AI 编辑当前单元"),
    "lesson.edit": ActionSpec("lesson.edit", "AI 编辑当前课"),
    # v4.15 K-10 收编：题级改写经教师芯片路径（PreviewHost Enter 即确认闸，
    # v4.14 已对齐 metrics funnel）；registry 仅作可枚举真源，无新执行路径。
    "item.rewrite": ActionSpec("item.rewrite", "改写当前题（教师芯片）"),
    # v4.62 P2：相似题 — 固定指令走芯片链 request_item_transform（保 id）。
    "item.similar": ActionSpec("item.similar", "改写为相似题"),
    # v4.39 K-13：确定性题型迁移（非听力题→听力题）。复用 switch_runtime_type
    # （保 id、语义字段重映射）+ item_patch_from_replace + ApplyItemPatchCommand。
    # 零 LLM；经确认 + Undo（needs_confirm 红线）。
    "item.to_listening": ActionSpec("item.to_listening", "迁为听力题"),
    # v4.16 K-07：题型配比。local evaluate（零 LLM 判定）→ 确认 →
    # regenerate_lesson_in_section（复用 K-05 引擎 + 配比指令）。
    "lesson.balance": ActionSpec("lesson.balance", "调整题型配比"),
    # v4.16 K-12 收编：干扰强化经教师「换干扰」芯片（指令常量现成，零新逻辑）。
    "item.distractor_boost": ActionSpec(
        "item.distractor_boost", "强化干扰项（教师芯片）"
    ),
    # v4.37 K-08：词汇螺旋。local evaluate_unit_spiral 判定 showWord 引入后
    # 后续课无复现的词 → 确认 → regenerate_lesson_in_section（保 id/词汇/主题，
    # 追加复现题）。经 SectionDiffView 预览 + MergeAiSectionCommand 入 Undo。
    "unit.spiral_vocab": ActionSpec("unit.spiral_vocab", "补充词汇螺旋复现"),
    # v4.39 K-18：阅读空段生成。local evaluate_reading_passage 判定 reading 课
    # readingPassage 空/占位 → 确认 → regenerate_lesson_in_section（reading 指令）。
    "reading.passages_gen": ActionSpec("reading.passages_gen", "生成阅读段落"),
    # v4.20 P11 T-04：多选课时 local 批量设 template（FieldPatch → Batch，零 LLM）。
    "lesson.batch_set_template": ActionSpec(
        "lesson.batch_set_template", "批量设置课型", needs_confirm=True, dangerous=True
    ),
    # v4.57 T-04 AI：多选课顺序 regenerate → LessonPatch 一批一个 Undo。
    "lesson.batch_regenerate": ActionSpec(
        "lesson.batch_regenerate", "批量重生成选中课", needs_confirm=True, dangerous=True
    ),
    # v4.59：多选 unit 顺序 regenerate_unit_in_section → LessonPatch 一批一个 Undo。
    "unit.batch_regenerate": ActionSpec(
        "unit.batch_regenerate", "批量重生成选中单元", needs_confirm=True, dangerous=True
    ),
    # v4.21 K-20：查重建议（local detect_duplicates → 打开资源，不自动删）。
    "resource.dedupe_suggest": ActionSpec(
        "resource.dedupe_suggest", "查重重复词条", needs_confirm=False
    ),
    # K-21：POS 词性对齐。local detect（缺失/无效/冲突）-> LLM 建议单一闭集 pos ->
    # 批量 FieldPatch（每词 pos）+ ApplyBatchPatchCommand（预览/确认/Undo）。保 id。
    "resource.align_pos_tags": ActionSpec(
        "resource.align_pos_tags", "对齐词条词性（POS）"
    ),
    # V-06：vocab↔expression 词条冲突仲裁（同 term 异译）。local detect（零 LLM）
    # -> 确认（列前 12 冲突对，term 仅 UI）-> 二选一统一方向 -> 每侧 FieldPatch
    # (translation) + ApplyBatchPatchCommand（预览/确认/Undo）。保 id；非 dangerous。
    "resource.resolve_term_conflicts": ActionSpec(
        "resource.resolve_term_conflicts", "统一词条冲突释义"
    ),
    # V-02：资源批量补全/润色/发音。选中词条（surface=resources 多选或 scope
    # entries）-> 确认（列前 12 term，仅 UI）-> LLM 只润色白名单字段
    # （translation/pronunciation/pos）-> 每 (id,field) 一个 FieldPatch +
    # ApplyBatchPatchCommand（预览/确认/Undo）。保 id；非 dangerous。
    "resource.batch_polish": ActionSpec(
        "resource.batch_polish", "批量润色选中词条"
    ),
    # v4.65 B1+B2：全局批量「清待补」（FieldPatch 路径）。区别于
    # resource.fill_stubs（whole-section merge）——本 skill 按 stub 谓词
    # （待补/needs-review/auto-fix）扫全局资源池，复用 batch_polish 的 LLM
    # 层填 translation(+pronunciation/pos)，成功后剥 stub 标签；每 (id,field)
    # 一个 FieldPatch + ApplyBatchPatchCommand（预览/确认/Undo）。保 id；非
    # dangerous。
    "resource.fill_stubs_batch": ActionSpec(
        "resource.fill_stubs_batch", "AI 补全待补词条"
    ),
    # v4.26 K-03：两节 local 对比（词重叠/空课/题型），只读零写盘。
    "course.compare_sections": ActionSpec(
        "course.compare_sections", "对比两节课", needs_confirm=False
    ),
    # v4.63 M-02：大纲 bullet -> unit/lesson 壳。零 LLM 确定性解析粘贴的大纲
    # 文本 -> ai_phased.outline_to_section_shell 空壳 -> plan_section_merge 追加
    # 到目标 section（不动已有内容）-> SectionDiffView 确认 + MergeAiSectionCommand
    # 入 Undo。needs_confirm=True（写操作红线）。默认关 experience/outline_shell。
    "course.outline_shells": ActionSpec(
        "course.outline_shells", "大纲生成课壳", needs_confirm=True, dangerous=True
    ),
    # v4.36 E4/M-01：工坊附件摘要进 Context 后的只读导航入口（打开工坊查看
    # 附件；不写树、不调 LLM、无 Guard/Job）。
    "attachment.open_in_workshop": ActionSpec(
        "attachment.open_in_workshop", "打开工坊 · 查看附件", needs_confirm=False
    ),
    # E3-A/B1 C-10/C-11：Goal 规划 / expand / 沙箱清单（默认关）。
    "goal.plan": ActionSpec(
        "goal.plan", "Goal 规划（local）", needs_confirm=False
    ),
    "goal.expand": ActionSpec(
        "goal.expand", "Goal 加深规划（local/可选 LLM）", needs_confirm=False
    ),
    "goal.run": ActionSpec(
        "goal.run", "Goal 沙箱预演并合并", needs_confirm=True
    ),
    # K-04：发布 Brief / 打开发布对话框（结构红仍由发布路径阻断）。
    "publish.brief": ActionSpec(
        "publish.brief", "发布 Brief / 打开发布", needs_confirm=False
    ),
    # K-24：只读 git skill。读当前工作树 diff → request_chat 生成提交信息 / 解释。
    # 不写课程树、不删 id、无 sandbox；结果进只读预览 + 剪贴板。无 dangerous。
    "git.commit_message": ActionSpec(
        "git.commit_message", "生成提交信息", needs_confirm=False
    ),
    "git.explain_diff": ActionSpec(
        "git.explain_diff", "解释 Diff", needs_confirm=False
    ),
    # M-05 (v4.38): 只读截图解释。Qt 内置 grab() 截主窗 → image_url 消息 →
    # request_chat → 只读预览。不写课程树、无 Guard/sandbox/Undo、无 dangerous。
    # 默认关 experience/screenshot_explain（含未保存隐私 + LLM 费用）。
    "app.screenshot_explain": ActionSpec(
        "app.screenshot_explain", "截图解释（只读）", needs_confirm=False
    ),
    # M-03 (v4.40): 只读 OCR 建议链。图片附件本地 OCR（pytesseract+tesseract 懒加载）
    # -> 文本类 AttachmentRecord 回流 M-01 工坊链路。不写课程树、无 Guard/sandbox/Undo、
    # 无 dangerous。默认关 experience/ocr_enabled（读盘+外部进程副效应 + 系统二进制非必装）。
    # OCR 文本/路径不进 Context/telemetry（§14.5.3）。
    "textbook.ocr_suggest": ActionSpec(
        "textbook.ocr_suggest", "OCR 图片附件转文本", needs_confirm=False
    ),
    # K-22 v4.58：工坊 / 草稿导入 / 附件 grounded 填充（包装既有管线，不复制抽取引擎）。
    "textbook.open_workshop": ActionSpec(
        "textbook.open_workshop", "打开课程工坊", needs_confirm=False
    ),
    "textbook.import_draft": ActionSpec(
        "textbook.import_draft", "导入工坊草稿", needs_confirm=True
    ),
    "textbook.grounded_fill": ActionSpec(
        "textbook.grounded_fill", "基于附件填充空课", needs_confirm=True
    ),
    # M-07 (v4.45): 清除跨课作者画像（C-13 AuthorMemory）。不写课程树、无 LLM、
    # 无 Guard。registry needs_confirm=False（非 AI 写树；handler 内仍弹隐私确认，
    # observer/预算不拦）。timeline 只记闭集 scope，不记 style_hints 原文。
    "memory.clear_author": ActionSpec(
        "memory.clear_author", "清除作者画像", needs_confirm=False
    ),
    # app.* —— 主窗内建命令（save / undo / help / pin / why）。它们不是 AI 写树
    # action，而是用户显式点击的窗口命令，故 needs_confirm=False；派发仍在
    # app.py:_on_palette_command 直走，registry 仅作可枚举真源（S-08/S-10 一致性）。
    "app.save": ActionSpec("app.save", "保存课程", needs_confirm=False),
    "app.undo": ActionSpec("app.undo", "撤销", needs_confirm=False),
    # K-25: /help opens clickable tour (help.fix); registry id stays app.help.
    "app.help": ActionSpec("app.help", "命令清单（点击执行）", needs_confirm=False),
    "help.fix": ActionSpec(
        "help.fix", "命令导览（可点执行）", needs_confirm=False
    ),
    "app.pin": ActionSpec("app.pin", "钉住 / 取消钉住", needs_confirm=False),
    "app.why": ActionSpec("app.why", "解释当前校验问题", needs_confirm=False),
}


# ``app.`` 前缀的内建命令不是 AI 写树 action，不受「禁止静默写盘」红线约束。
APP_BUILTIN_PREFIX = "app."


def get_action(action_id: str) -> ActionSpec | None:
    """Look up an action spec; ``None`` when the id is unknown."""
    return ACTIONS.get(str(action_id or ""))


# C-20 危险 skill 派生闭集：标记 dangerous 的 action_id 全集。扩面需同步
# 单测 + 文档（§8.13）。v4.69 起 6 个结构重写类 action 落 dangerous（不再空集）：
# lesson/unit.regenerate、lesson/unit.batch_regenerate、lesson.batch_set_template、
# course.outline_shells。语义见 ActionSpec.dangerous 字段注。
DANGEROUS_ACTION_IDS: frozenset[str] = frozenset(
    aid for aid, spec in ACTIONS.items() if spec.dangerous
)


def is_dangerous(action_id: str) -> bool:
    """True when the action is marked dangerous in the registry."""
    spec = get_action(action_id)
    return bool(spec is not None and spec.dangerous)
