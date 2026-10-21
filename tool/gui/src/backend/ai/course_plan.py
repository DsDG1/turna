"""Course-level plan generation (P0-2, Qt-free).

A *course plan* is the missing middle layer between "one section" and "a whole
course": it fixes the section ladder, the level progression, the per-section
brief, and a course-wide lexicon with deterministic ids before any section
content is generated.

Design rules:

- The model returns **terms**, never ids. Section ids (``sec-01``) and word ids
  (``w-...``) are assigned locally so two runs over the same plan are stable.
- The plan is validated locally before it is accepted. Structural failures
  (section count, level order, duplicate terms, review-before-introduce) are
  errors; budget drift is a warning.
- The plan never writes course files. It is persisted separately by
  :mod:`src.backend.course_plan_store`; importing remains the existing
  diff/merge flow.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any

from src.backend.ai.client import chat_json
from src.backend.ai.config import SYSTEM_AUTHORING, AiApiConfig, AiCourseSpec
from src.backend.ai.parse import extract_content, parse_json_obj
from src.backend.schema_constants import TemplateType

PLAN_VERSION = 1

CEFR_LEVELS: tuple[str, ...] = ("A1", "A2", "B1", "B2", "C1", "C2")

#: Lesson templates accepted in ``PlanSection.template_mix``. ``mixed`` is a
#: section-level strategy, not a lesson template, and is deliberately excluded.
ALLOWED_TEMPLATES: tuple[str, ...] = (
    TemplateType.INTRO.value,
    TemplateType.PRACTICE.value,
    TemplateType.REVIEW.value,
    TemplateType.LISTENING.value,
    TemplateType.READING.value,
    TemplateType.MASTERY.value,
)

_SLUG_RE = re.compile(r"[^a-z0-9]+")
_TERM_SPLIT_RE = re.compile(r"\s+")


def _now() -> str:
    return datetime.now().isoformat(timespec="seconds")


def _norm_term(term: Any) -> str:
    return _TERM_SPLIT_RE.sub(" ", str(term or "").strip()).casefold()


def _slug(term: Any) -> str:
    slug = _SLUG_RE.sub("-", str(term or "").strip().lower()).strip("-")
    return slug[:32] or "word"


def _as_int(value: Any, default: int, *, low: int, high: int) -> int:
    try:
        number = int(value)
    except (TypeError, ValueError):
        return default
    return max(low, min(high, number))


def _as_list(value: Any) -> list[Any]:
    return list(value) if isinstance(value, (list, tuple)) else []


def _as_text(value: Any) -> str:
    return str(value or "").strip()


@dataclass
class PlanWord:
    """One lexicon entry assigned to exactly one section."""

    id: str
    term: str
    translation: str = ""
    pos: str = ""
    section_id: str = ""

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "term": self.term,
            "translation": self.translation,
            "pos": self.pos,
            "section_id": self.section_id,
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> PlanWord:
        return cls(
            id=str(data.get("id") or ""),
            term=str(data.get("term") or ""),
            translation=str(data.get("translation") or ""),
            pos=str(data.get("pos") or ""),
            section_id=str(data.get("section_id") or ""),
        )


@dataclass
class PlanSection:
    """One section in the course ladder."""

    section_id: str
    name: str
    level: str = "A1"
    description: str = ""
    unit_count: int = 2
    lessons_per_unit: int = 3
    template_mix: list[str] = field(default_factory=list)
    can_do: list[str] = field(default_factory=list)
    brief: str = ""
    new_word_ids: list[str] = field(default_factory=list)
    review_terms: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return {
            "section_id": self.section_id,
            "name": self.name,
            "level": self.level,
            "description": self.description,
            "unit_count": int(self.unit_count),
            "lessons_per_unit": int(self.lessons_per_unit),
            "template_mix": list(self.template_mix),
            "can_do": list(self.can_do),
            "brief": self.brief,
            "new_word_ids": list(self.new_word_ids),
            "review_terms": list(self.review_terms),
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> PlanSection:
        return cls(
            section_id=str(data.get("section_id") or ""),
            name=str(data.get("name") or ""),
            level=str(data.get("level") or "A1"),
            description=str(data.get("description") or ""),
            unit_count=_as_int(data.get("unit_count"), 2, low=1, high=12),
            lessons_per_unit=_as_int(
                data.get("lessons_per_unit"), 3, low=1, high=12
            ),
            template_mix=[str(x) for x in _as_list(data.get("template_mix"))],
            can_do=[str(x) for x in _as_list(data.get("can_do"))],
            brief=str(data.get("brief") or ""),
            new_word_ids=[str(x) for x in _as_list(data.get("new_word_ids"))],
            review_terms=[str(x) for x in _as_list(data.get("review_terms"))],
        )


@dataclass
class CoursePlanSpec:
    """User-facing planning parameters (one dialog form)."""

    language: str = "Turkish"
    source_language: str = "Chinese"
    topic: str = ""
    level_from: str = "A1"
    level_to: str = "A2"
    section_count: int = 6
    lessons_per_section: int = 9
    word_budget: int = 240
    can_do: list[str] = field(default_factory=list)
    constraints: str = ""

    def to_dict(self) -> dict[str, Any]:
        return {
            "language": self.language,
            "source_language": self.source_language,
            "topic": self.topic,
            "level_from": self.level_from,
            "level_to": self.level_to,
            "section_count": int(self.section_count),
            "lessons_per_section": int(self.lessons_per_section),
            "word_budget": int(self.word_budget),
            "can_do": list(self.can_do),
            "constraints": self.constraints,
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any] | None) -> CoursePlanSpec:
        data = data or {}
        return cls(
            language=str(data.get("language") or "Turkish"),
            source_language=str(data.get("source_language") or "Chinese"),
            topic=str(data.get("topic") or ""),
            level_from=_level(data.get("level_from"), "A1"),
            level_to=_level(data.get("level_to"), "A2"),
            section_count=_as_int(data.get("section_count"), 6, low=1, high=24),
            lessons_per_section=_as_int(
                data.get("lessons_per_section"), 9, low=1, high=60
            ),
            word_budget=_as_int(
                data.get("word_budget"), 240, low=0, high=5000
            ),
            can_do=[str(x) for x in _as_list(data.get("can_do"))],
            constraints=str(data.get("constraints") or ""),
        )


@dataclass
class CoursePlan:
    """A persisted course plan: spec + section ladder + lexicon."""

    plan_id: str = ""
    course_dir: str = ""
    version: int = PLAN_VERSION
    title: str = ""
    description: str = ""
    spec: CoursePlanSpec = field(default_factory=CoursePlanSpec)
    sections: list[PlanSection] = field(default_factory=list)
    lexicon: list[PlanWord] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    model: str = ""
    created_at: str = ""
    updated_at: str = ""
    # --- P0-3 runtime metadata (persisted; not part of the LLM contract) ---
    #: 0 means unlimited.
    token_budget: int = 0
    usage_total: int = 0
    #: section_id -> {status: none|draft|imported, usage: int,
    #:                final_section_id: str, updated_at: str}
    progress: dict[str, dict[str, Any]] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return {
            "version": int(self.version),
            "plan_id": self.plan_id,
            "course_dir": self.course_dir,
            "title": self.title,
            "description": self.description,
            "spec": self.spec.to_dict(),
            "sections": [s.to_dict() for s in self.sections],
            "lexicon": [w.to_dict() for w in self.lexicon],
            "warnings": list(self.warnings),
            "model": self.model,
            "created_at": self.created_at,
            "updated_at": self.updated_at,
            "token_budget": int(self.token_budget),
            "usage_total": int(self.usage_total),
            "progress": {
                str(key): dict(value)
                for key, value in self.progress.items()
                if isinstance(value, dict)
            },
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any] | None) -> CoursePlan:
        data = data or {}
        raw_progress = data.get("progress")
        progress = {
            str(key): dict(value)
            for key, value in (raw_progress or {}).items()
            if isinstance(value, dict)
        } if isinstance(raw_progress, dict) else {}
        return cls(
            plan_id=str(data.get("plan_id") or ""),
            course_dir=str(data.get("course_dir") or ""),
            version=_as_int(data.get("version"), PLAN_VERSION, low=1, high=99),
            title=str(data.get("title") or ""),
            description=str(data.get("description") or ""),
            spec=CoursePlanSpec.from_dict(data.get("spec")),
            sections=[
                PlanSection.from_dict(item)
                for item in _as_list(data.get("sections"))
                if isinstance(item, dict)
            ],
            lexicon=[
                PlanWord.from_dict(item)
                for item in _as_list(data.get("lexicon"))
                if isinstance(item, dict)
            ],
            warnings=[str(x) for x in _as_list(data.get("warnings"))],
            model=str(data.get("model") or ""),
            created_at=str(data.get("created_at") or ""),
            updated_at=str(data.get("updated_at") or ""),
            token_budget=_as_int(data.get("token_budget"), 0, low=0, high=10_000_000),
            usage_total=_as_int(data.get("usage_total"), 0, low=0, high=10**12),
            progress=progress,
        )

    @property
    def word_count(self) -> int:
        return len(self.lexicon)

    def section(self, section_id: str) -> PlanSection | None:
        return next(
            (s for s in self.sections if s.section_id == section_id), None
        )

    def words_for(self, section_id: str) -> list[PlanWord]:
        return [w for w in self.lexicon if w.section_id == section_id]


def _level(value: Any, default: str) -> str:
    text = str(value or "").strip().upper()
    return text if text in CEFR_LEVELS else default


def _level_rank(level: str) -> int:
    try:
        return CEFR_LEVELS.index(level)
    except ValueError:
        return 0


# --- prompt -----------------------------------------------------------------


def build_plan_prompt(
    spec: CoursePlanSpec,
    *,
    previous_errors: list[str] | None = None,
) -> str:
    """User prompt for the course outline. Terms only; ids are local."""
    lines = [
        "请为语言课程生成【课程大纲 JSON】。只规划结构与词汇分配，不要写题目内容。",
        "",
        f"目标语言：{spec.language}",
        f"提示语言：{spec.source_language}",
        f"课程主题：{spec.topic or '（未指定，请按语言课程通识主题设计）'}",
        f"等级范围：{spec.level_from} → {spec.level_to}",
        f"章节数：{spec.section_count}",
        f"每章课时数：{spec.lessons_per_section}",
        f"全课程新词预算：约 {spec.word_budget} 个",
    ]
    if spec.can_do:
        lines.append("课程 can-do 目标：")
        lines.extend(f"- {item}" for item in spec.can_do)
    if spec.constraints.strip():
        lines.append("")
        lines.append("## 额外约束")
        lines.append(spec.constraints.strip())

    lines.extend(
        [
            "",
            "输出 JSON 形状（严格，不要 id）：",
            "{",
            '  "title": "课程名",',
            '  "description": "一句话说明",',
            '  "sections": [',
            "    {",
            '      "name": "章节名",',
            '      "description": "一句话说明",',
            '      "level": "A1",',
            '      "unit_count": 2,',
            '      "lessons_per_unit": 3,',
            '      "template_mix": ["intro", "practice"],',
            '      "can_do": ["能问候与自我介绍"],',
            '      "brief": "本节教学重点与编排意图",',
            '      "new_words": [{"term":"...","translation":"...","pos":"noun"}],',
            '      "review_terms": ["前面章节已出现的词"]',
            "    }",
            "  ]",
            "}",
            "",
            "硬性要求：",
            f"1. 恰好 {spec.section_count} 个 section；每个 section 的 level 只能取 A1/A2/B1/B2/C1/C2。",
            "2. 章节 level 必须按输出顺序单调不降，且落在等级范围内。",
            "3. 每个新词在整门课程中只出现一次；复习词必须是**前面章节**已经出现过的词。",
            "4. new_words 总数要接近词预算；每节 8–40 个新词，按等级与课时数控制。",
            "5. template_mix 只能取 intro/practice/listening/reading/review/mastery，至少一种。",
            "6. brief 要写清本节的场景、语法重点、复现哪些旧词；不要写题目。",
            "7. 只返回 JSON，不要 markdown 代码块或解释。",
        ]
    )
    if previous_errors:
        lines.extend(
            [
                "",
                "## 上次输出未通过校验，请修正后重新输出完整 JSON",
                *[f"- {err}" for err in previous_errors[:12]],
            ]
        )
    return "\n".join(lines)


def build_plan_messages(
    spec: CoursePlanSpec,
    *,
    previous_errors: list[str] | None = None,
) -> list[dict[str, Any]]:
    return [
        {"role": "system", "content": SYSTEM_AUTHORING},
        {
            "role": "user",
            "content": build_plan_prompt(spec, previous_errors=previous_errors),
        },
    ]


# --- normalization ----------------------------------------------------------


def _coerce_words(raw_section: dict[str, Any]) -> list[dict[str, str]]:
    out: list[dict[str, str]] = []
    for item in _as_list(raw_section.get("new_words")):
        if isinstance(item, dict):
            term = _as_text(item.get("term") or item.get("word"))
            translation = _as_text(item.get("translation"))
            pos = _as_text(item.get("pos"))
        else:
            term = _as_text(item)
            translation = ""
            pos = ""
        if term:
            out.append({"term": term, "translation": translation, "pos": pos})
    return out


def normalize_plan(
    raw: dict[str, Any],
    spec: CoursePlanSpec,
    *,
    course_dir: str = "",
) -> CoursePlan:
    """Coerce a model payload into a deterministic :class:`CoursePlan`.

    Ids are assigned here, in section order, never trusted from the model.
    Terms that repeat inside one section are kept (so ``validate_plan`` can
    report them) but collapse to one lexicon entry to keep ids unique.
    """
    payload = raw if isinstance(raw, dict) else {}
    raw_sections = payload.get("sections")
    if not isinstance(raw_sections, list) and isinstance(payload.get("course"), dict):
        raw_sections = payload["course"].get("sections")
    raw_sections = raw_sections if isinstance(raw_sections, list) else []

    sections: list[PlanSection] = []
    lexicon: list[PlanWord] = []
    word_index = 0

    for index, raw_section in enumerate(raw_sections, start=1):
        if not isinstance(raw_section, dict):
            continue
        section_id = f"sec-{index:02d}"
        level = _level(raw_section.get("level"), spec.level_from)
        mix = [
            str(t)
            for t in _as_list(raw_section.get("template_mix"))
            if str(t) in ALLOWED_TEMPLATES
        ]
        if not mix:
            mix = [TemplateType.INTRO.value, TemplateType.PRACTICE.value]
        section = PlanSection(
            section_id=section_id,
            name=_as_text(raw_section.get("name")) or f"第 {index} 节",
            level=level,
            description=_as_text(raw_section.get("description")),
            unit_count=_as_int(raw_section.get("unit_count"), 2, low=1, high=12),
            lessons_per_unit=_as_int(
                raw_section.get("lessons_per_unit"), 3, low=1, high=12
            ),
            template_mix=mix,
            can_do=[_as_text(x) for x in _as_list(raw_section.get("can_do")) if _as_text(x)],
            brief=_as_text(raw_section.get("brief")),
        )

        for word in _coerce_words(raw_section):
            term = word["term"]
            word_index += 1
            plan_word = PlanWord(
                id=f"w-{_slug(term)}-{word_index:03d}",
                term=term,
                translation=word["translation"],
                pos=word["pos"],
                section_id=section_id,
            )
            lexicon.append(plan_word)
            section.new_word_ids.append(plan_word.id)

        for term in _as_list(raw_section.get("review_terms")):
            text = _as_text(term)
            if text:
                section.review_terms.append(text)
        sections.append(section)

    plan = CoursePlan(
        course_dir=course_dir,
        title=_as_text(payload.get("title")) or spec.topic or "未命名课程",
        description=_as_text(payload.get("description")),
        spec=spec,
        sections=sections,
        lexicon=lexicon,
        created_at=_now(),
        updated_at=_now(),
    )
    return plan


# --- validation -------------------------------------------------------------


def resolve_review_words(
    plan: CoursePlan, section: PlanSection
) -> tuple[list[PlanWord], list[str]]:
    """Resolve a section's review terms against **earlier** sections only.

    Returns ``(resolved_words, unresolved_terms)``. The plan is not mutated:
    ``review_terms`` stays as the model wrote it, so validation is repeatable.
    """
    by_term: dict[str, PlanWord] = {}
    for prior in plan.sections:
        if prior.section_id == section.section_id:
            break
        for word in plan.words_for(prior.section_id):
            by_term.setdefault(_norm_term(word.term), word)
    resolved: list[PlanWord] = []
    unresolved: list[str] = []
    for term in section.review_terms:
        word = by_term.get(_norm_term(term))
        if word is None:
            unresolved.append(str(term))
        elif word not in resolved:
            resolved.append(word)
    return resolved, unresolved


def _validate_review_terms(plan: CoursePlan) -> list[str]:
    errors: list[str] = []
    for section in plan.sections:
        _resolved, unresolved = resolve_review_words(plan, section)
        if unresolved:
            errors.append(
                f"{section.section_id} 的复习词未在前面章节出现："
                + "、".join(unresolved[:6])
            )
    return errors


def validate_plan(plan: CoursePlan, spec: CoursePlanSpec | None = None) -> list[str]:
    """Return structural errors. Empty list means the plan is usable.

    Budget drift and short ``brief`` are warnings on ``plan.warnings``, not
    errors. Review terms are validated against earlier sections only; the plan
    is not mutated, so the call is repeatable.
    """
    spec = spec or plan.spec
    errors: list[str] = []
    warnings: list[str] = []

    if not plan.sections:
        errors.append("大纲没有任何 section。")
    if spec.section_count > 0 and len(plan.sections) != spec.section_count:
        errors.append(
            f"section 数不符：要求 {spec.section_count}，实际 {len(plan.sections)}。"
        )

    previous_rank = -1
    seen_ids: set[str] = set()
    for index, section in enumerate(plan.sections, start=1):
        if not section.section_id or section.section_id in seen_ids:
            errors.append(f"第 {index} 节缺少唯一 section_id。")
        seen_ids.add(section.section_id)
        if section.section_id != f"sec-{index:02d}":
            errors.append(f"第 {index} 节 id 不是确定性序号（{section.section_id}）。")
        if section.level not in CEFR_LEVELS:
            errors.append(
                f"{section.section_id} 等级非法：{section.level}"
            )
        rank = _level_rank(section.level)
        if rank < previous_rank:
            errors.append(
                f"{section.section_id} 等级倒挂：{section.level} 低于前一节。"
            )
        previous_rank = max(previous_rank, rank)
        if section.unit_count < 1 or section.lessons_per_unit < 1:
            errors.append(f"{section.section_id} 的单元/课时数必须大于 0。")
        if not section.template_mix:
            errors.append(f"{section.section_id} 没有可用 template_mix。")
        bad_templates = [
            t for t in section.template_mix if t not in ALLOWED_TEMPLATES
        ]
        if bad_templates:
            errors.append(
                f"{section.section_id} 含非法模板：{'、'.join(bad_templates)}"
            )
        if not section.name.strip():
            errors.append(f"{section.section_id} 缺少章节名。")
        if not section.brief.strip():
            warnings.append(f"{section.section_id} 的 brief 为空，生成质量可能偏低。")

    # Duplicate terms across the whole course.
    term_sections: dict[str, list[str]] = {}
    for word in plan.lexicon:
        term_sections.setdefault(_norm_term(word.term), []).append(word.section_id)
    duplicates = [
        f"{term}（{'、'.join(sorted(set(ids)))}）"
        for term, ids in term_sections.items()
        if len(ids) > 1
    ]
    if duplicates:
        errors.append("新词在课程内重复：" + "；".join(duplicates[:8]))

    empty_translations = [
        w for w in plan.lexicon if not w.translation.strip()
    ]
    if empty_translations:
        warnings.append(f"{len(empty_translations)} 个新词缺翻译。")

    errors.extend(_validate_review_terms(plan))

    total_words = len(plan.lexicon)
    if spec.word_budget > 0:
        drift = abs(total_words - spec.word_budget)
        allowed = max(12, int(spec.word_budget * 0.12))
        if drift > allowed:
            warnings.append(
                f"新词数 {total_words} 与预算 {spec.word_budget} 偏差较大"
                f"（允许 ±{allowed}）。"
            )
        if total_words == 0:
            errors.append("词预算大于 0，但大纲没有分配任何新词。")

    plan.warnings = warnings
    return errors


# --- generation -------------------------------------------------------------


def generate_course_plan(
    config: AiApiConfig,
    spec: CoursePlanSpec,
    *,
    course_dir: str = "",
    timeout: float = 120.0,
    temperature: float = 0.4,
    max_retries: int = 1,
    cancel_check: Any = None,
    on_chunk: Any = None,
    usage_callback: Any = None,
) -> CoursePlan:
    """Request a plan, normalize it, and retry once with validation feedback.

    Raises ``RuntimeError`` with a user-readable message when the model output
    cannot be normalized or still fails validation after the retries.
    """
    errors: list[str] = []
    last_error = ""
    attempts = max(0, int(max_retries)) + 1
    for _attempt in range(attempts):
        messages = build_plan_messages(spec, previous_errors=errors)
        try:
            body = chat_json(
                config,
                messages,
                temperature=temperature,
                timeout=timeout,
                cancel_check=cancel_check,
                on_chunk=on_chunk,
                usage_callback=usage_callback,
            )
            content = extract_content(body, strip=True)
            raw = parse_json_obj(content)
            plan = normalize_plan(raw, spec, course_dir=course_dir)
            plan.model = config.select_model("json")
            errors = validate_plan(plan, spec)
            if not errors:
                return plan
            last_error = "；".join(errors[:8])
        except ValueError as exc:
            last_error = str(exc)
            errors = [last_error]
    raise RuntimeError(f"课程大纲校验失败：{last_error}")


# --- per-section generation spec -------------------------------------------


def _prior_words(plan: CoursePlan, section_id: str) -> list[PlanWord]:
    ordered: list[PlanWord] = []
    for section in plan.sections:
        if section.section_id == section_id:
            break
        ordered.extend(plan.words_for(section.section_id))
    return ordered


def _pool_entry(word: PlanWord) -> dict[str, Any]:
    return {
        "id": word.id,
        "term": word.term,
        "translation": word.translation,
        "pos": word.pos,
    }


def plan_section_to_spec(
    plan: CoursePlan,
    section_id: str,
    *,
    existing_resources: dict[str, Any] | None = None,
) -> AiCourseSpec:
    """Build the existing section generator's spec for one planned section.

    The pool is *grounded*: the section may only use its assigned new words +
    earlier review words. Previously planned words are also passed as
    ``course_resources`` so the model reuses ids instead of inventing synonyms.
    """
    section = plan.section(section_id)
    if section is None:
        raise KeyError(f"未知 section_id：{section_id}")

    new_words = plan.words_for(section_id)
    review_words, _unresolved = resolve_review_words(plan, section)
    pool = [_pool_entry(w) for w in [*new_words, *review_words]]

    resources = dict(existing_resources or {})
    prior = _prior_words(plan, section_id)
    vocab = [
        item
        for item in (resources.get("vocab") or [])
        if isinstance(item, dict)
    ]
    seen_vocab = {str(item.get("id")) for item in vocab}
    for word in prior:
        if word.id not in seen_vocab:
            vocab.append(_pool_entry(word))
            seen_vocab.add(word.id)
    resources["vocab"] = vocab
    resources.setdefault("expressions", [])
    resources.setdefault("grammarPoints", [])

    template = (
        section.template_mix[0]
        if len(section.template_mix) == 1
        else "mixed"
    )
    can_do = "；".join(section.can_do[:8])
    brief_parts = [
        section.brief.strip(),
        f"本节新词必须来自资源池（{len(new_words)} 个），复习词只做复现练习、不要重新讲解。",
    ]
    if review_words:
        brief_parts.append(
            "需复现的旧词：" + "、".join(w.term for w in review_words[:12])
        )
    if can_do:
        brief_parts.append(f"can-do：{can_do}")
    brief = "\n".join(part for part in brief_parts if part)

    extra = [
        f"课程规划：{plan.title or plan.spec.topic}",
        f"本节是 {section.section_id}（{section.level}）。",
        f"建议课型组合：{'、'.join(section.template_mix)}。",
        "只生成本节内容，不要重复其他章节。",
    ]
    if plan.spec.constraints.strip():
        extra.append(plan.spec.constraints.strip())
    if len(section.template_mix) > 1:
        extra.append(
            "在 units/lessons 间分配上述课型；不要把所有课时做成同一种模板。"
        )

    return AiCourseSpec(
        language=plan.spec.language,
        source_language=plan.spec.source_language,
        topic=f"{section.name}：{section.description}" if section.description else section.name,
        level=section.level,
        unit_count=int(section.unit_count),
        lessons_per_unit=int(section.lessons_per_unit),
        template=template,
        use_genre_batch=False,
        extra_instructions="\n".join(extra),
        course_resources=resources if (vocab or resources.get("expressions")) else None,
        resource_pool=pool or None,
        design_brief=brief,
    )


__all__ = [
    "ALLOWED_TEMPLATES",
    "CEFR_LEVELS",
    "PLAN_VERSION",
    "CoursePlan",
    "CoursePlanSpec",
    "PlanSection",
    "PlanWord",
    "build_plan_messages",
    "build_plan_prompt",
    "generate_course_plan",
    "normalize_plan",
    "plan_section_to_spec",
    "validate_plan",
]
