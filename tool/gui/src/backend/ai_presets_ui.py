"""Shared AI edit instruction presets for Review / Teacher / Fix dialogs.

Pure constants — no Qt. Keep wording stable so telemetry and docs stay aligned.
"""
from __future__ import annotations

# Full instruction lines used when the user clicks a preset chip.
EDIT_PRESETS: tuple[str, ...] = (
    "干扰项加强：选项同词性、近义，避免离谱拼写",
    "补 transcript / 可朗读文本，便于听力与 TTS",
    "统一敬语/通称（A1 可用 sen，礼貌场景 siz）",
    "加强本课新词在练习中的复现",
    "降低句长与生词密度，更贴合当前 CEFR",
    "补全 [待补] / needs-review 词条的 term、translation、pronunciation",
)

# Short labels for compact chip buttons (index-aligned with EDIT_PRESETS).
EDIT_PRESET_LABELS: tuple[str, ...] = (
    "干扰项加强",
    "补 transcript",
    "统一敬语",
    "加强复现",
    "降低难度",
    "清待补",
)

# Teacher-mode shorter chips (legacy-friendly wording).
TEACHER_PRESET_LABELS: tuple[str, ...] = (
    "生成 3 道练习题",
    "降低难度",
    "增加干扰项",
    "改成听力题型",
    "润色题干",
)

TEACHER_PRESET_INSTRUCTIONS: tuple[str, ...] = (
    "生成 3 道相似练习题，保持本课词汇与难度",
    "降低句长与生词密度，更贴合当前 CEFR",
    "干扰项加强：选项同词性、近义，避免离谱拼写",
    "改成适合听力练习的题型，并补 transcript / 可朗读文本",
    "润色题干与选项表述，保持答案与 id 不变",
)

# Item-level chip presets (blueprint cards & form chips).
ITEM_CHIP_LABELS: tuple[str, ...] = (
    "润色",
    "改听力",
    "加干扰",
    "相似",
)

ITEM_CHIP_INSTRUCTIONS: tuple[str, ...] = (
    "润色题干表述，语言自然纯正，保持答案与 id 不变",
    "改成适合听力练习的题型，并补 transcript / 可朗读文本，保持答案与 id 不变",
    "干扰项加强：选项同词性、近义，避免离谱拼写，保持答案与 id 不变",
    "在保留 id、runtimeType 与正确答案语义的前提下，改写成考查点相同的平行相似题：换情境或换说法，勿改题型，勿改 id，勿改正确选项含义。",
)
