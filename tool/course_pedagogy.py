from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass
from typing import Any

MIN_SUB_LESSON_ITEMS = 12
MAX_SUB_LESSON_ITEMS = 15
MIN_NEW_WORD_DISTANCE = 3
REVIEW_POOL_SIZE = 18
REVIEW_MIN_ITEMS = 15
REVIEW_MAX_ITEMS = 16
INTRO_MAX_WORD_MEANING_MCQ = 2
PRACTICE_MAX_WORD_MEANING_MCQ = 0
INTRO_MIN_SENTENCE_RATIO = 0.55
PRACTICE_MIN_SENTENCE_RATIO = 0.80
SPEAK_MIN_SENTENCE_RATIO = 0.75

LEVEL_RULES = {
    "A1": {"new_words": (4, 8), "sentence_words": 8},
    "A2": {"new_words": (6, 12), "sentence_words": 12},
    "B1": {"new_words": (8, 15), "sentence_words": 18},
    "B2": {"new_words": (10, 18), "sentence_words": 24},
    "C1": {"new_words": (10, 20), "sentence_words": 30},
    "C2": {"new_words": (10, 24), "sentence_words": 40},
}

PRODUCTION_TYPES = {
    "fillBlank",
    "translateSentence",
    "reorderSentence",
    "readAloud",
}
CHOICE_TYPES = {"multipleChoice", "listenAndPick", "readingMcq"}
_NON_GRADABLE_TYPES = {"showWord", "listenOnly", "ankiCard", "ankiHtmlCard"}
_LATIN_WORD_RE = re.compile(r"[A-Za-z\u00C0-\u024F\u1E00-\u1EFF]+")
_CJK_RE = re.compile(r"[\u4e00-\u9fff]")
_PUNCT_STRIP_RE = re.compile(r"[.,!?;:\"'’‘“”«»()\[\]{}…—–\-。，！？；：（）【】「」『』]+")
_NON_MEANING_MCQ_MARKERS = ("字母", "拼写", "念什么", "读音", "原本来自", "本义")
_NEGATION_WORDS = {"hayır", "değil", "non", "no"}
_YES_NO_PARTICLES = {"evet", "hayır", "oui", "non", "yes", "no"}
_LISTEN_ORDER_MARKERS = (
    "第",
    "先",
    "后",
    "最后",
    "开头",
    "结尾",
    "Ayşe",
    "Müşteri",
    "店主",
    "店员",
    "顾客",
)


@dataclass(frozen=True)
class PedagogyFinding:
    code: str
    message: str
    severity: str = "warning"


def latin_tokens(text: str) -> list[str]:
    return _LATIN_WORD_RE.findall(text or "")


def target_token_count(text: str) -> int:
    tokens = latin_tokens(text)
    if tokens:
        return len(tokens)
    cleaned = _PUNCT_STRIP_RE.sub(" ", text or "").strip()
    return len([part for part in cleaned.split() if part])


def is_gradable_pedagogy_item(item: dict[str, Any]) -> bool:
    return str(item.get("runtimeType") or "") not in _NON_GRADABLE_TYPES


def _vocab_role_map(vocab: list[dict[str, Any]] | None) -> dict[str, str]:
    roles: dict[str, str] = {}
    if not vocab:
        return roles
    for word in vocab:
        if not isinstance(word, dict):
            continue
        term = str(word.get("term") or "").strip()
        if not term:
            continue
        tags = word.get("tags") or []
        fallback_tag = tags[0] if isinstance(tags, list) and tags else ""
        role = str(word.get("pos") or fallback_tag or "").strip().lower()
        if role:
            roles[term.casefold()] = role
    return roles


def has_unsupported_fill_blank_media(item: dict[str, Any]) -> bool:
    if item.get("runtimeType") != "fillBlank":
        return False
    refs = list(item.get("imageAssets") or []) + list(item.get("audioAssets") or [])
    for ref in refs:
        trimmed = str(ref or "").strip()
        if trimmed and "/" in trimmed and "://" not in trimmed:
            return True
    return False


def is_ambiguous_fill_blank(
    item: dict[str, Any], role_map: dict[str, str]
) -> bool:
    if item.get("runtimeType") != "fillBlank" or not role_map:
        return False
    choices = [
        str(c).strip() for c in (item.get("choices") or []) if str(c).strip()
    ]
    ans = str(item.get("answer") or "").strip()
    if len(choices) < 2 or not ans:
        return False
    ans_role = role_map.get(ans.casefold(), "")
    if not ans_role:
        return False
    peers = [
        c
        for c in choices
        if c.casefold() != ans.casefold() and role_map.get(c.casefold()) == ans_role
    ]
    if not peers:
        return False
    sentence = str(item.get("sentence") or "")
    if (
        ans.casefold() in _YES_NO_PARTICLES
        and all(p.casefold() in _YES_NO_PARTICLES for p in peers)
        and "?" in sentence
    ):
        return False
    if str(item.get("hint") or "").strip() or _CJK_RE.search(sentence):
        return False
    sent_lower = sentence.casefold()
    sent_words = {t.casefold() for t in latin_tokens(sent_lower)}
    if ans.casefold() in sent_words:
        return False
    return not (
        (sent_words & _NEGATION_WORDS)
        and all(p.casefold() in sent_words for p in peers)
    )


def is_ambiguous_listen_pick(item: dict[str, Any], transcript: str) -> bool:
    if item.get("runtimeType") != "listenAndPick" or not (transcript or "").strip():
        return False
    transcript_lower = transcript.casefold()
    matched = 0
    for opt in item.get("options") or []:
        opt_text = str(opt or "").strip().casefold()
        if not opt_text:
            continue
        if re.search(rf"(?<!\w){re.escape(opt_text)}(?!\w)", transcript_lower):
            matched += 1
    if matched < 2:
        return False
    prompt = str(item.get("prompt") or "")
    return not any(marker in prompt for marker in _LISTEN_ORDER_MARKERS)


def is_pseudo_fill_blank(item: dict[str, Any]) -> bool:
    if item.get("runtimeType") != "fillBlank":
        return False
    sentence = str(item.get("sentence") or "")
    if "___" not in sentence:
        return True
    if re.search(r"[=＝]\s*_+", sentence):
        return True
    context = re.sub(r"_+", " ", sentence)
    return len(latin_tokens(context)) == 0


def is_single_word_meaning_mcq(item: dict[str, Any]) -> bool:
    if item.get("runtimeType") != "multipleChoice":
        return False
    prompt = str(item.get("prompt") or "")
    if any(marker in prompt for marker in _NON_MEANING_MCQ_MARKERS):
        return False
    p_latin = len(latin_tokens(prompt))
    options = [str(opt) for opt in (item.get("options") or [])]
    opt_latin_max = max((len(latin_tokens(opt)) for opt in options), default=0)
    return (p_latin == 1 and opt_latin_max == 0) or (p_latin == 0 and opt_latin_max == 1)


def is_sentence_level_item(item: dict[str, Any]) -> bool:
    if not is_gradable_pedagogy_item(item):
        return False
    rt = str(item.get("runtimeType") or "")
    if rt == "reorderSentence":
        return len(item.get("correct") or []) >= 2
    if rt == "fillBlank":
        if is_pseudo_fill_blank(item):
            return False
        filled = re.sub(r"_+", f" {item.get('answer') or ''} ", str(item.get("sentence") or ""))
        return target_token_count(filled) >= 2
    if rt == "translateSentence":
        return target_token_count(str(item.get("expected") or "")) >= 2
    if rt == "readAloud":
        return target_token_count(str(item.get("targetText") or "")) >= 2
    if rt in {"readingMcq", "readingTrueFalse", "readingShortAnswer"}:
        return True
    if rt in {"multipleChoice", "multiSelect", "listenAndPick"}:
        if rt == "multipleChoice" and is_single_word_meaning_mcq(item):
            return False
        prompt = str(item.get("prompt") or "")
        options = [str(opt) for opt in (item.get("options") or [])]
        return len(latin_tokens(prompt)) >= 2 or any(len(latin_tokens(opt)) >= 2 for opt in options)
    if rt in {"typeTheWord", "dictation"}:
        return target_token_count(str(item.get("expected") or "")) >= 2
    return False


def _item_signature(item: dict[str, Any]) -> tuple[Any, ...]:
    rt = str(item.get("runtimeType") or "")
    stem = (
        item.get("prompt")
        or item.get("sentence")
        or item.get("source")
        or item.get("statement")
        or item.get("targetText")
        or ""
    )
    if rt in CHOICE_TYPES:
        options = item.get("options") or []
        ci = item.get("correctIndex")
        ans: Any = options[ci] if type(ci) is int and 0 <= ci < len(options) else ci
    elif rt == "multiSelect":
        options = item.get("options") or []
        indices = item.get("correctIndices") or []
        ans = tuple(options[i] for i in indices if type(i) is int and 0 <= i < len(options))
    elif rt == "reorderSentence":
        ans = tuple(item.get("correct") or [])
    else:
        ans = item.get("answer") or item.get("expected") or item.get("expectedAnswer") or ""
    return (rt, str(stem).strip(), ans)


def _check_container_pedagogy(
    items: list[dict[str, Any]],
    *,
    label: str,
    max_word_mcq: int | None,
    min_sentence_ratio: float | None,
    min_gradable_for_ratio: int,
    findings: list[PedagogyFinding],
    role_map: dict[str, str] | None = None,
    check_choice_ambiguity: bool = True,
) -> None:
    pseudo_ids = [
        str(item.get("id") or "<unknown>")
        for item in items
        if is_pseudo_fill_blank(item)
    ]
    if pseudo_ids:
        findings.append(
            PedagogyFinding(
                "pseudo_fill_blank",
                f"{label} contains pseudo fillBlank item(s) without target-language sentence context: "
                f"{', '.join(pseudo_ids[:3])}",
            )
        )

    unsupported_media_ids = [
        str(item.get("id") or "<unknown>")
        for item in items
        if has_unsupported_fill_blank_media(item)
    ]
    if unsupported_media_ids:
        findings.append(
            PedagogyFinding(
                "fill_blank_unsupported_media",
                f"{label} has fillBlank item(s) with bundled media paths that FillBlankRenderer ignores: "
                f"{', '.join(unsupported_media_ids[:3])}",
            )
        )

    if check_choice_ambiguity and role_map:
        ambiguous_ids = [
            str(item.get("id") or "<unknown>")
            for item in items
            if is_ambiguous_fill_blank(item, role_map)
        ]
        if ambiguous_ids:
            findings.append(
                PedagogyFinding(
                    "ambiguous_fill_blank",
                    f"{label} has fillBlank item(s) where multiple choices fit without context or hint: "
                    f"{', '.join(ambiguous_ids[:3])}",
                )
            )

    if max_word_mcq is not None:
        word_mcqs = [item for item in items if is_single_word_meaning_mcq(item)]
        if len(word_mcqs) > max_word_mcq:
            findings.append(
                PedagogyFinding(
                    "single_word_choice_overload",
                    f"{label} has {len(word_mcqs)} single-word meaning MCQ(s); "
                    f"maximum allowed is {max_word_mcq}",
                )
            )

    if min_sentence_ratio is not None:
        gradable = [item for item in items if is_gradable_pedagogy_item(item)]
        if len(gradable) >= min_gradable_for_ratio:
            sentence_count = sum(1 for item in gradable if is_sentence_level_item(item))
            ratio = sentence_count / len(gradable)
            if ratio < min_sentence_ratio:
                findings.append(
                    PedagogyFinding(
                        "sentence_ratio_low",
                        f"{label} sentence-level ratio is {sentence_count}/{len(gradable)} "
                        f"({ratio:.0%}); minimum target is {min_sentence_ratio:.0%}",
                    )
                )


def lesson_sub_lessons(lesson: dict[str, Any]) -> list[dict[str, Any]]:
    content = lesson.get("content") or {}
    return [entry for entry in content.get("subLessons") or [] if isinstance(entry, dict)]


def sub_lesson_items(sub_lesson: dict[str, Any]) -> list[dict[str, Any]]:
    return [
        item
        for stage in sub_lesson.get("stages") or []
        if isinstance(stage, dict)
        for item in stage.get("items") or []
        if isinstance(item, dict)
    ]


def lesson_items(lesson: dict[str, Any]) -> list[dict[str, Any]]:
    content = lesson.get("content") or {}
    items = [
        item
        for sub_lesson in lesson_sub_lessons(lesson)
        for item in sub_lesson_items(sub_lesson)
    ]
    items.extend(
        item
        for stage in content.get("stages") or []
        if isinstance(stage, dict)
        for item in stage.get("items") or []
        if isinstance(item, dict)
    )
    items.extend(
        item
        for phase in content.get("listeningPhases") or []
        if isinstance(phase, dict)
        for item in phase.get("items") or []
        if isinstance(item, dict)
    )
    return items


def evaluate_lesson_pedagogy(
    lesson: dict[str, Any],
    *,
    level: str = "A1",
    vocab: list[dict[str, Any]] | None = None,
) -> list[PedagogyFinding]:
    findings: list[PedagogyFinding] = []
    lesson_id = str(lesson.get("id") or "<unknown>")
    template = lesson.get("template")
    role_map = _vocab_role_map(vocab)
    if template in {"intro", "practice"}:
        min_ratio = INTRO_MIN_SENTENCE_RATIO if template == "intro" else PRACTICE_MIN_SENTENCE_RATIO
        max_mcq = INTRO_MAX_WORD_MEANING_MCQ if template == "intro" else PRACTICE_MAX_WORD_MEANING_MCQ
        for sub_lesson in lesson_sub_lessons(lesson):
            sub_id = str(sub_lesson.get("id") or "<unknown>")
            items = sub_lesson_items(sub_lesson)
            if not MIN_SUB_LESSON_ITEMS <= len(items) <= MAX_SUB_LESSON_ITEMS:
                findings.append(
                    PedagogyFinding(
                        "sublesson_length",
                        f"SubLesson {sub_id} in lesson {lesson_id} has {len(items)} items; "
                        f"target is {MIN_SUB_LESSON_ITEMS}–{MAX_SUB_LESSON_ITEMS}",
                    )
                )
            introduced: dict[str, int] = {}
            for index, item in enumerate(items):
                if item.get("runtimeType") != "showWord":
                    continue
                word_id = str(item.get("wordId") or "")
                if not word_id or word_id in introduced:
                    continue
                if introduced and index - max(introduced.values()) < MIN_NEW_WORD_DISTANCE:
                    findings.append(
                        PedagogyFinding(
                            "new_word_spacing",
                            f"SubLesson {sub_id} introduces {word_id} fewer than "
                            f"{MIN_NEW_WORD_DISTANCE - 1} items after the previous new word",
                        )
                    )
                introduced[word_id] = index
            if items and not any(item.get("runtimeType") in PRODUCTION_TYPES for item in items):
                findings.append(
                    PedagogyFinding(
                        "production_missing",
                        f"SubLesson {sub_id} has no direct production item",
                    )
                )
            _check_container_pedagogy(
                items,
                label=f"SubLesson {sub_id} in lesson {lesson_id}",
                max_word_mcq=max_mcq,
                min_sentence_ratio=min_ratio,
                min_gradable_for_ratio=8,
                findings=findings,
                role_map=role_map,
                check_choice_ambiguity=True,
            )

    items = lesson_items(lesson)
    if template in {"review", "mastery"}:
        _check_container_pedagogy(
            items,
            label=f"Lesson {lesson_id}",
            max_word_mcq=PRACTICE_MAX_WORD_MEANING_MCQ,
            min_sentence_ratio=PRACTICE_MIN_SENTENCE_RATIO,
            min_gradable_for_ratio=8,
            findings=findings,
            role_map=role_map,
            check_choice_ambiguity=True,
        )
        if template == "review":
            seen_sigs: set[tuple[Any, ...]] = set()
            duplicates = 0
            for item in items:
                sig = _item_signature(item)
                if sig in seen_sigs:
                    duplicates += 1
                else:
                    seen_sigs.add(sig)
            if duplicates:
                findings.append(
                    PedagogyFinding(
                        "duplicate_pool_items",
                        f"Review lesson {lesson_id} has {duplicates} duplicate question(s) in its pool",
                    )
                )
    elif template == "dialogue":
        _check_container_pedagogy(
            items,
            label=f"Lesson {lesson_id}",
            max_word_mcq=PRACTICE_MAX_WORD_MEANING_MCQ,
            min_sentence_ratio=SPEAK_MIN_SENTENCE_RATIO,
            min_gradable_for_ratio=4,
            findings=findings,
            role_map=role_map,
            check_choice_ambiguity=True,
        )
    elif template == "listening":
        _check_container_pedagogy(
            items,
            label=f"Lesson {lesson_id}",
            max_word_mcq=None,
            min_sentence_ratio=None,
            min_gradable_for_ratio=0,
            findings=findings,
            role_map=role_map,
            check_choice_ambiguity=False,
        )
        content = lesson.get("content") or {}
        for phase in content.get("listeningPhases") or []:
            if not isinstance(phase, dict):
                continue
            phase_id = str(phase.get("id") or "<unknown>")
            transcript = str(phase.get("transcript") or "")
            for item in phase.get("items") or []:
                if not isinstance(item, dict):
                    continue
                if is_ambiguous_listen_pick(item, transcript):
                    item_id = str(item.get("id") or "<unknown>")
                    findings.append(
                        PedagogyFinding(
                            "ambiguous_listen_pick",
                            f"Lesson {lesson_id} phase {phase_id} has listenAndPick item "
                            f"{item_id} whose prompt does not disambiguate multiple options "
                            "present in transcript",
                        )
                    )
    elif template == "legacy" and len(items) >= 4 and all(
        item.get("runtimeType") == "readAloud" for item in items
    ):
        _check_container_pedagogy(
            items,
            label=f"Lesson {lesson_id}",
            max_word_mcq=None,
            min_sentence_ratio=SPEAK_MIN_SENTENCE_RATIO,
            min_gradable_for_ratio=4,
            findings=findings,
            role_map=role_map,
            check_choice_ambiguity=True,
        )

    positions = [
        item.get("correctIndex")
        for item in items
        if item.get("runtimeType") in CHOICE_TYPES and type(item.get("correctIndex")) is int
    ]
    if len(positions) >= 3 and len(set(positions)) == 1:
        findings.append(
            PedagogyFinding(
                "answer_position",
                f"Lesson {lesson_id} puts every choice answer at index {positions[0]}",
            )
        )

    rules = LEVEL_RULES.get(str(level).upper(), LEVEL_RULES["A1"])
    introduced_ids = {
        str(item.get("wordId"))
        for item in items
        if item.get("runtimeType") == "showWord" and item.get("wordId")
    }
    maximum_new_words = rules["new_words"][1]
    if template == "intro" and len(introduced_ids) > maximum_new_words:
        findings.append(
            PedagogyFinding(
                "level_word_budget",
                f"Lesson {lesson_id} introduces {len(introduced_ids)} words; "
                f"{level} target maximum is {maximum_new_words}",
            )
        )
    sentence_cap = rules["sentence_words"]
    for item in items:
        if item.get("runtimeType") != "translateSentence":
            continue
        expected = str(item.get("expected") or "")
        if len(expected.split()) > sentence_cap:
            findings.append(
                PedagogyFinding(
                    "level_sentence_length",
                    f"Translation {item.get('id') or '<unknown>'} exceeds the "
                    f"{level} sentence guide of {sentence_cap} words",
                )
            )
    return findings


def arrange_choice(
    options: list[str],
    correct_index: int,
    *,
    seed: str,
    preferred_index: int,
) -> tuple[list[str], int]:
    if not options or not 0 <= correct_index < len(options):
        raise ValueError("options and correctIndex must describe one correct option")
    target = preferred_index % len(options)
    correct = options[correct_index]
    distractors = [option for index, option in enumerate(options) if index != correct_index]
    if distractors:
        digest = hashlib.sha256(seed.encode("utf-8")).digest()
        shift = digest[0] % len(distractors)
        distractors = distractors[shift:] + distractors[:shift]
    arranged = list(distractors)
    arranged.insert(target, correct)
    return arranged, target


def phase_two_prompt_block() -> str:
    return (
        "Phase Two 教学配方（硬约束）：\n"
        f"1. 每个独立子课 {MIN_SUB_LESSON_ITEMS}–{MAX_SUB_LESSON_ITEMS} 个 items；"
        "不要把一个词拆成一个三题子课。\n"
        "2. 以真实句子的直接运用为主，展示、识别和产出交错；"
        "每个子课至少包含 fillBlank / translateSentence / reorderSentence 之一。\n"
        f"3. 严控孤立单词选义单选：intro 每子课最多 {INTRO_MAX_WORD_MEANING_MCQ} 道，"
        "practice / review / mastery / dialogue 不出孤立单词选义题。\n"
        "4. 禁止「词 = _____」等号式伪填空；fillBlank 必须是目标语句或双轮对话中的真实语境挖空。\n"
        f"5. 句子级可作答题占比底线：intro ≥ {INTRO_MIN_SENTENCE_RATIO:.0%}，"
        f"practice / review / mastery ≥ {PRACTICE_MIN_SENTENCE_RATIO:.0%}，"
        f"dialogue / 开口 ≥ {SPEAK_MIN_SENTENCE_RATIO:.0%}；复习题池禁止重复题。\n"
        f"6. 两个首次新词之间至少隔 {MIN_NEW_WORD_DISTANCE - 1} 个 items，禁止连续甩词卡。\n"
        "7. 单选与多选的正确选项位置要分散，并同步重算 correctIndex/correctIndices。\n"
        "8. 教学说明使用中文；复习只使用前置课已经学过的词和结构。\n"
        f"9. 随机复习使用平铺 stages + reviewPolicy，题池约 {REVIEW_POOL_SIZE} 题，"
        f"每次抽 {REVIEW_MIN_ITEMS}–{REVIEW_MAX_ITEMS} 题，不与 subLessons 混用。\n"
        "10. 自读唯一解检验：逐个代入 fillBlank 候选词与选择题选项，确认仅有唯一答案在语法搭配或上下句语境中成立；"
        "fillBlank 不挂 assets/ 图片，多词听力 listenAndPick 须指明第几个词或说话人。"
    )
