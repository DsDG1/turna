#!/usr/bin/env python3
"""Convert a LibreLingo YAML course into a Turna ``.turnapack`` file.

See ``docs/course-pack-import-plan.md`` §3–§4. App-side import never reads
YAML — this tool is the only LibreLingo adapter.

v1 is a JSON document (no media). When image/audio files are found, the
output is a zip (``turnapack/2``) containing ``pack.json`` plus ``media/``.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import random
import re
import sys
import tempfile
import zipfile
from pathlib import Path
from typing import Any

import yaml

CODE_RE = re.compile(r"^[a-z]{2,3}$")
ID_SAFE_RE = re.compile(r"[^a-z0-9-]+")
HYPHEN_RE = re.compile(r"-{2,}")

# Mapping table: LibreLingo skill field names (human YAML keys).
_SKILL_WORDS = "New words"
_SKILL_PHRASES = "Phrases"
_SKILL_DICT = "Mini-dictionary"
_WORD_KEY = "Word"
_PHRASE_KEY = "Phrase"
_TRANSLATION = "Translation"
_SYNONYMS = "Synonyms"
_ALSO_ACCEPTED = "Also accepted"
_ALT_VERSIONS = "Alternative versions"

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".gif"}
AUDIO_EXTS = {".mp3", ".ogg", ".wav", ".m4a", ".aac", ".opus"}
_MEDIA_SIDECAR = "_media"


class MediaLibrary:
    """Index image/audio files by lowercase stem and filename."""

    def __init__(self, roots: list[Path]) -> None:
        self.images: dict[str, Path] = {}
        self.audio: dict[str, Path] = {}
        for root in roots:
            if not root.is_dir():
                continue
            for path in root.rglob("*"):
                if not path.is_file():
                    continue
                ext = path.suffix.lower()
                stem = path.stem.lower()
                name = path.name.lower()
                if ext in IMAGE_EXTS:
                    self.images.setdefault(stem, path)
                    self.images.setdefault(name, path)
                elif ext in AUDIO_EXTS:
                    self.audio.setdefault(stem, path)
                    self.audio.setdefault(name, path)

    def lookup_image(self, keys: list[str]) -> Path | None:
        return self._lookup(self.images, keys)

    def lookup_audio(self, keys: list[str]) -> Path | None:
        return self._lookup(self.audio, keys)

    @staticmethod
    def _lookup(index: dict[str, Path], keys: list[str]) -> Path | None:
        for key in keys:
            text = str(key or "").strip().replace("\\", "/")
            if not text:
                continue
            base = Path(text).name.lower()
            stem = Path(text).stem.lower()
            found = index.get(base) or index.get(stem)
            if found is not None:
                return found
        return None


def packed_media_name(src: Path, used: set[str]) -> str:
    stem = slugify(src.stem) or "media"
    ext = src.suffix.lower()
    candidate = f"{stem}{ext}"
    if candidate not in used:
        return candidate
    digest = hashlib.sha256(str(src).encode("utf-8")).hexdigest()[:8]
    return f"{stem}-{digest}{ext}"


def slugify(text: str) -> str:
    """Lowercase and fold anything outside ``[a-z0-9-]`` to ``-``."""
    folded = ID_SAFE_RE.sub("-", (text or "").strip().lower())
    folded = HYPHEN_RE.sub("-", folded).strip("-")
    return folded or "x"


def prefixed(code: str, kind: str, fragment: str) -> str:
    return f"ll-{code}-{kind}-{fragment}"


def fisher_yates(items: list[str], seed_key: str) -> list[str]:
    """Deterministic Fisher-Yates. Reshuffle once if the result equals input."""
    digest = hashlib.sha256(seed_key.encode("utf-8")).digest()
    seed = int.from_bytes(digest[:8], "big")
    rng = random.Random(seed)
    out = list(items)
    _shuffle(out, rng)
    if out == items and len(out) > 1:
        rng2 = random.Random(seed + 1)
        _shuffle(out, rng2)
    return out


def _shuffle(out: list[str], rng: random.Random) -> None:
    for i in range(len(out) - 1, 0, -1):
        j = rng.randrange(i + 1)
        out[i], out[j] = out[j], out[i]


def load_yaml(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
    if not isinstance(data, dict):
        raise ValueError(f"{path} is not a YAML mapping")
    return data


def _as_list(value: Any) -> list[Any]:
    if value is None:
        return []
    if isinstance(value, list):
        return value
    return [value]


def _string_list(value: Any) -> list[str]:
    out: list[str] = []
    for item in _as_list(value):
        if item is None:
            continue
        if isinstance(item, dict):
            # Some courses write ``- foo: bar`` as a one-key mapping.
            out.extend(str(k) for k in item.keys())
            continue
        text = str(item).strip()
        if text:
            out.append(text)
    return out


def parse_skill_words(skill: dict[str, Any]) -> list[dict[str, Any]]:
    words: list[dict[str, Any]] = []
    for raw in _as_list(skill.get(_SKILL_WORDS)):
        if not isinstance(raw, dict):
            continue
        term = str(raw.get(_WORD_KEY) or "").strip()
        translation = str(raw.get(_TRANSLATION) or "").strip()
        if not term:
            continue
        words.append(
            {
                "term": term,
                "translation": translation,
                "synonyms": _string_list(raw.get(_SYNONYMS)),
                "also_accepted": _string_list(raw.get(_ALSO_ACCEPTED)),
                "images": _string_list(raw.get("Images")),
            }
        )
    return words


def parse_skill_phrases(skill: dict[str, Any]) -> list[dict[str, Any]]:
    phrases: list[dict[str, Any]] = []
    for raw in _as_list(skill.get(_SKILL_PHRASES)):
        if not isinstance(raw, dict):
            continue
        phrase = str(raw.get(_PHRASE_KEY) or "").strip()
        translation = str(raw.get(_TRANSLATION) or "").strip()
        if not phrase:
            continue
        phrases.append(
            {
                "phrase": phrase,
                "translation": translation,
                "alternatives": _string_list(raw.get(_ALT_VERSIONS)),
            }
        )
    return phrases


def parse_mini_dictionary_target(skill: dict[str, Any]) -> list[tuple[str, str]]:
    """Target-language side of Mini-dictionary → (term, translation).

    The source-language direction is discarded (Turna dictionary is global
    on the target side).
    """
    block = skill.get(_SKILL_DICT)
    if not isinstance(block, dict):
        return []
    # Prefer a non-English bucket as the target-language side.
    target_entries: Any = None
    for key, value in block.items():
        if str(key).strip().lower() == "english":
            continue
        target_entries = value
        break
    if target_entries is None:
        return []
    pairs: list[tuple[str, str]] = []
    for item in _as_list(target_entries):
        if isinstance(item, dict):
            for term, meaning in item.items():
                term_s = str(term).strip()
                if not term_s:
                    continue
                if isinstance(meaning, list) and meaning:
                    meaning_s = str(meaning[0]).strip()
                else:
                    meaning_s = str(meaning or "").strip()
                pairs.append((term_s, meaning_s))
        elif isinstance(item, str) and item.strip():
            pairs.append((item.strip(), ""))
    return pairs


class CourseBuilder:
    def __init__(
        self,
        *,
        code: str,
        display_name: str,
        tts_locale: str,
        native_label: str,
        license_info: dict[str, str],
        pack_version: int,
        default_level: str | None,
        signature_chars: str | None,
        media: MediaLibrary | None = None,
    ) -> None:
        if not CODE_RE.fullmatch(code):
            raise ValueError(
                f"language code {code!r} must match ^[a-z]{{2,3}}$ "
                "(pass --code; do not read IETF BCP 47 from course.yaml)"
            )
        self.code = code
        self.display_name = display_name
        self.tts_locale = tts_locale
        self.native_label = native_label
        self.license_info = license_info
        self.pack_version = pack_version
        self.default_level = default_level
        self.signature_chars = signature_chars
        self.media = media or MediaLibrary([])
        self.media_files: dict[str, Path] = {}
        self._media_names: set[str] = set()
        self.words_by_id: dict[str, dict[str, Any]] = {}
        self.expressions_by_id: dict[str, dict[str, Any]] = {}
        self.sections: list[dict[str, Any]] = []
        self._lesson_seq = 0
        self._item_seq = 0

    def word_id(self, term: str) -> str:
        return prefixed(self.code, "w", slugify(term))

    def expression_id(self, phrase: str) -> str:
        return prefixed(self.code, "e", slugify(phrase))

    def next_item_id(self, kind: str) -> str:
        self._item_seq += 1
        return prefixed(self.code, "i", f"{kind}-{self._item_seq}")

    def register_media(self, src: Path) -> str:
        for rel, path in self.media_files.items():
            if path == src:
                return rel
        name = packed_media_name(src, self._media_names)
        self._media_names.add(name)
        rel = f"media/{name}"
        self.media_files[rel] = src
        return rel

    def attach_word_media(self, word: dict[str, Any]) -> None:
        image_keys = list(word.get("images") or [])
        image_path = self.media.lookup_image(image_keys)
        audio_path = self.media.lookup_audio(
            image_keys + [word.get("term") or "", slugify(word.get("term") or "")]
        )
        if image_path is not None:
            word["_image"] = self.register_media(image_path)
        if audio_path is not None:
            word["_audio"] = self.register_media(audio_path)

    def add_word(
        self,
        term: str,
        translation: str,
        *,
        synonyms: list[str] | None = None,
        also_accepted: list[str] | None = None,
        tags: list[str] | None = None,
        image_rel: str | None = None,
        audio_rel: str | None = None,
    ) -> str:
        wid = self.word_id(term)
        if wid in self.words_by_id:
            existing = self.words_by_id[wid]
            if image_rel and not existing.get("_image"):
                existing["_image"] = image_rel
            if audio_rel and not existing.get("_audio"):
                existing["_audio"] = audio_rel
                existing["audioAsset"] = audio_rel
            return wid
        hints = [*(synonyms or []), *(also_accepted or [])]
        entry: dict[str, Any] = {
            "id": wid,
            "term": term,
            "translation": translation,
            "tags": tags or ["noun"],
            "_hints": hints,
        }
        if image_rel:
            entry["_image"] = image_rel
        if audio_rel:
            entry["_audio"] = audio_rel
            entry["audioAsset"] = audio_rel
        self.words_by_id[wid] = entry
        return wid

    def add_expression(
        self,
        phrase: str,
        translation: str,
        *,
        alternatives: list[str] | None = None,
    ) -> str:
        eid = self.expression_id(phrase)
        if eid in self.expressions_by_id:
            return eid
        self.expressions_by_id[eid] = {
            "id": eid,
            "term": phrase,
            "translation": translation,
            "tags": ["phrase"],
            "_hints": list(alternatives or []),
        }
        return eid

    def distractors(
        self, correct: str, *, skill_terms: list[str], limit: int = 3
    ) -> list[str]:
        """Pick unique translations/terms different from [correct]."""
        pool: list[str] = []
        seen = {correct}
        for term in skill_terms:
            if term and term not in seen:
                seen.add(term)
                pool.append(term)
        for word in self.words_by_id.values():
            for candidate in (word["term"], word["translation"]):
                if candidate and candidate not in seen:
                    seen.add(candidate)
                    pool.append(candidate)
        return pool[:limit]

    def multiple_choice(
        self, prompt: str, correct: str, skill_terms: list[str]
    ) -> dict[str, Any] | None:
        distractors = self.distractors(correct, skill_terms=skill_terms)
        if len(distractors) < 3:
            return None
        options = [correct, *distractors[:3]]
        return {
            "runtimeType": "multipleChoice",
            "id": self.next_item_id("mc"),
            "prompt": prompt,
            "options": options,
            "correctIndex": 0,
        }

    def fill_blank(self, term: str, translation: str) -> dict[str, Any]:
        return {
            "runtimeType": "fillBlank",
            "id": self.next_item_id("fb"),
            "sentence": f"_____.",
            "answer": term,
            "hint": translation,
        }

    def show_word(
        self,
        word_id: str,
        term: str,
        translation: str,
        *,
        image_asset: str | None = None,
    ) -> dict[str, Any]:
        item: dict[str, Any] = {
            "runtimeType": "showWord",
            "id": self.next_item_id("sw"),
            "wordId": word_id,
            "context": f"{term} — {translation}",
        }
        if image_asset:
            item["imageAsset"] = image_asset
        return item

    def type_the_word(
        self, word_id: str, term: str, *, audio_asset: str | None = None
    ) -> dict[str, Any]:
        return {
            "runtimeType": "typeTheWord",
            "id": self.next_item_id("ttw"),
            "audioAsset": audio_asset or word_id,
            "prompt": "Type what you hear",
            "expected": term,
        }

    def listen_and_pick(
        self,
        word_id: str,
        term: str,
        skill_terms: list[str],
        *,
        audio_asset: str | None = None,
    ) -> dict[str, Any] | None:
        mc = self.multiple_choice("What did you hear?", term, skill_terms)
        if mc is None:
            return None
        return {
            "runtimeType": "listenAndPick",
            "id": self.next_item_id("lap"),
            "audioAsset": audio_asset or word_id,
            "prompt": mc["prompt"],
            "options": mc["options"],
            "correctIndex": mc["correctIndex"],
        }

    def translate_sentence(
        self, source: str, expected: str, hints: list[str]
    ) -> dict[str, Any]:
        return {
            "runtimeType": "translateSentence",
            "id": self.next_item_id("ts"),
            "source": source,
            "expected": expected,
            "hints": hints,
        }

    def reorder(self, phrase: str, phrase_id: str, chip_pool: list[str]) -> dict[str, Any] | None:
        correct = [tok for tok in phrase.split() if tok]
        if len(correct) < 2:
            return None
        seed_key = f"ll-{self.code}-{phrase_id}"
        scrambled = fisher_yates(correct, seed_key)
        extras: list[str] = []
        for chip in chip_pool:
            if chip and chip not in correct and chip not in extras:
                extras.append(chip)
            if len(extras) >= 2:
                break
        scrambled = scrambled + extras
        return {
            "runtimeType": "reorderSentence",
            "id": self.next_item_id("rs"),
            "scrambled": scrambled,
            "correct": correct,
        }

    def intro_sublesson(
        self,
        word: dict[str, Any],
        skill_terms: list[str],
        *,
        listening: bool,
    ) -> dict[str, Any]:
        self.attach_word_media(word)
        wid = self.add_word(
            word["term"],
            word["translation"],
            synonyms=word.get("synonyms"),
            also_accepted=word.get("also_accepted"),
            image_rel=word.get("_image"),
            audio_rel=word.get("_audio"),
        )
        stored = self.words_by_id[wid]
        audio_rel = stored.get("_audio")
        image_rel = stored.get("_image")
        hints = list(word.get("synonyms") or []) + list(
            word.get("also_accepted") or []
        )
        items: list[dict[str, Any]] = [
            self.show_word(
                wid,
                word["term"],
                word["translation"],
                image_asset=image_rel,
            ),
            self.translate_sentence(
                word["translation"] or word["term"],
                word["term"],
                hints,
            ),
        ]
        mc = self.multiple_choice(
            word["translation"] or word["term"],
            word["term"],
            skill_terms,
        )
        if mc is not None:
            items.append(mc)
        items.append(self.fill_blank(word["term"], word["translation"]))
        if listening:
            lap = self.listen_and_pick(
                wid, word["term"], skill_terms, audio_asset=audio_rel
            )
            items.append(lap or self.type_the_word(wid, word["term"], audio_asset=audio_rel))
        else:
            items.append(
                self.type_the_word(wid, word["term"], audio_asset=audio_rel)
            )
        slug = slugify(word["term"])
        return {
            "id": prefixed(self.code, "sl", slug),
            "name": word["term"],
            "stages": [
                {
                    "id": prefixed(self.code, "st", slug),
                    "name": "Learn & produce",
                    "items": items,
                }
            ],
        }

    def practice_items(
        self,
        phrases: list[dict[str, Any]],
        skill_terms: list[str],
        chip_pool: list[str],
        words: list[dict[str, Any]],
        *,
        listening: bool,
    ) -> list[dict[str, Any]]:
        items: list[dict[str, Any]] = []
        for phrase in phrases:
            eid = self.add_expression(
                phrase["phrase"],
                phrase["translation"],
                alternatives=phrase.get("alternatives"),
            )
            hints = list(phrase.get("alternatives") or [])
            items.append(
                self.translate_sentence(
                    phrase["translation"], phrase["phrase"], hints
                )
            )
            mc = self.multiple_choice(
                phrase["translation"], phrase["phrase"], skill_terms
            )
            if mc is not None:
                items.append(mc)
            reorder = self.reorder(phrase["phrase"], eid, chip_pool)
            if reorder is not None:
                items.append(reorder)
        for word in words:
            self.attach_word_media(word)
            wid = self.add_word(
                word["term"],
                word["translation"],
                synonyms=word.get("synonyms"),
                also_accepted=word.get("also_accepted"),
                image_rel=word.get("_image"),
                audio_rel=word.get("_audio"),
            )
            audio_rel = self.words_by_id[wid].get("_audio")
            if listening:
                lap = self.listen_and_pick(
                    wid, word["term"], skill_terms, audio_asset=audio_rel
                )
                items.append(
                    lap
                    or self.type_the_word(wid, word["term"], audio_asset=audio_rel)
                )
            else:
                items.append(
                    self.type_the_word(wid, word["term"], audio_asset=audio_rel)
                )
        return items

    def add_module(
        self,
        module_name: str,
        skills: list[tuple[str, dict[str, Any]]],
        *,
        index: int,
        total: int,
        prev_section_id: str | None,
    ) -> str | None:
        lessons: list[dict[str, Any]] = []
        prev_lesson: str | None = None
        for skill_key, skill in skills:
            words = parse_skill_words(skill)
            phrases = parse_skill_phrases(skill)
            if not words and not phrases:
                continue
            for pair in parse_mini_dictionary_target(skill):
                self.add_word(pair[0], pair[1], tags=["noun"])
            skill_terms = [w["term"] for w in words] + [p["phrase"] for p in phrases]
            chip_pool = [w["term"] for w in self.words_by_id.values()]
            listening = "listen" in skill_key.lower() or "listen" in str(
                skill.get("Name") or ""
            ).lower()
            self._lesson_seq += 1
            raw_id = skill.get("Id", self._lesson_seq)
            lesson_frag = slugify(str(raw_id))
            lesson_id = prefixed(self.code, "l", lesson_frag)
            use_intro = len(words) >= len(phrases) and bool(words)
            if use_intro:
                sub_lessons = [
                    self.intro_sublesson(w, skill_terms, listening=listening)
                    for w in words
                ]
                if phrases:
                    p_items = self.practice_items(
                        phrases, skill_terms, chip_pool, [], listening=False
                    )
                    if p_items:
                        sub_lessons.append(
                            {
                                "id": prefixed(self.code, "sl", f"{lesson_frag}-phrases"),
                                "name": "Phrases",
                                "stages": [
                                    {
                                        "id": prefixed(
                                            self.code, "st", f"{lesson_frag}-phrases"
                                        ),
                                        "name": "Phrases",
                                        "items": p_items,
                                    }
                                ],
                            }
                        )
                content: dict[str, Any] = {"subLessons": sub_lessons}
                template = "intro"
            else:
                items = self.practice_items(
                    phrases, skill_terms, chip_pool, words, listening=listening
                )
                if not items:
                    continue
                content = {
                    "subLessons": [
                        {
                            "id": prefixed(self.code, "sl", lesson_frag),
                            "name": str(skill.get("Name") or skill_key),
                            "stages": [
                                {
                                    "id": prefixed(self.code, "st", lesson_frag),
                                    "name": str(skill.get("Name") or skill_key),
                                    "prerequisiteStageIds": [],
                                    "items": items,
                                }
                            ],
                        }
                    ],
                }
                template = "practice"
            lesson = {
                "id": lesson_id,
                "name": str(skill.get("Name") or skill_key),
                "description": "",
                "type": "normal",
                "template": template,
                "prerequisiteLessonIds": [prev_lesson] if prev_lesson else [],
                "content": content,
            }
            lessons.append(lesson)
            prev_lesson = lesson_id
        if not lessons:
            return None
        section_id = prefixed(self.code, "s", str(index + 1))
        unit_id = prefixed(self.code, "u", str(index + 1))
        if self.default_level:
            level = self.default_level
        elif total <= 1:
            level = "A1"
        elif index < total / 3:
            level = "A1"
        elif index < 2 * total / 3:
            level = "A2"
        else:
            level = "B1"
        section = {
            "id": section_id,
            "name": module_name,
            "description": module_name,
            "prerequisiteSectionIds": [prev_section_id] if prev_section_id else [],
            "units": [
                {
                    "id": unit_id,
                    "name": module_name,
                    "description": module_name,
                    "prerequisiteUnitIds": [],
                    "lessons": lessons,
                }
            ],
        }
        self.sections.append({"section": section, "level": level, "file": f"sections/{section_id}.json"})
        return section_id

    def to_pack(self) -> dict[str, Any]:
        files: dict[str, Any] = {
            "index.json": {
                "version": 1,
                "language": self.code,
                "displayName": self.display_name,
                "sections": [
                    {
                        "id": item["section"]["id"],
                        "name": item["section"]["name"],
                        "description": item["section"]["description"],
                        "level": item["level"],
                        "prerequisiteSectionIds": item["section"]["prerequisiteSectionIds"],
                        "file": item["file"],
                    }
                    for item in self.sections
                ],
            },
            "vocab.json": {
                "version": 1,
                "language": self.code,
                "words": [
                    {
                        "id": w["id"],
                        "term": w["term"],
                        "translation": w["translation"],
                        "tags": w["tags"],
                        **({"audioAsset": w["audioAsset"]} if w.get("audioAsset") else {}),
                    }
                    for w in self.words_by_id.values()
                ],
            },
            "expressions.json": {
                "version": 4,
                "language": self.code,
                "expressions": [
                    {
                        "id": e["id"],
                        "term": e["term"],
                        "translation": e["translation"],
                        "tags": e["tags"],
                    }
                    for e in self.expressions_by_id.values()
                ],
            },
            "grammar_points.json": {"grammarPoints": []},
        }
        for item in self.sections:
            files[item["file"]] = item["section"]
        language: dict[str, Any] = {
            "code": self.code,
            "displayName": self.display_name,
            "ttsLocale": self.tts_locale,
            "nativeLabel": self.native_label,
        }
        if self.signature_chars:
            language["signatureChars"] = self.signature_chars
        pack: dict[str, Any] = {
            "format": "turnapack/2" if self.media_files else "turnapack/1",
            "packVersion": self.pack_version,
            "language": language,
            "license": self.license_info,
            "files": files,
        }
        if self.media_files:
            pack[_MEDIA_SIDECAR] = {rel: str(path) for rel, path in self.media_files.items()}
        return pack


def convert_course(
    course_dir: Path,
    *,
    code: str,
    display_name: str,
    tts_locale: str,
    pack_version: int = 1,
    default_level: str | None = None,
    signature_chars: str | None = None,
    media_dirs: list[Path] | None = None,
) -> dict[str, Any]:
    course_yaml = load_yaml(course_dir / "course.yaml")
    # test-1 nests content blocks inside the header block (Course/Module/
    # Skill); real courses (ES-from-EN) keep them as top-level siblings with
    # trailing slashes on module names ("basics/"). Merge both shapes.
    course = {**course_yaml, **(course_yaml.get("Course") or {})}
    language_block = course.get("Language") or {}
    native_label = str(
        language_block.get("Name") or display_name
    )
    license_block = course.get("License") or {}
    license_info = {
        "name": str(
            license_block.get("Short name")
            or license_block.get("Name")
            or "CC BY-SA 4.0"
        ),
        "attribution": "LibreLingo community",
        "link": str(
            license_block.get("Link")
            or "https://creativecommons.org/licenses/by-sa/4.0/"
        ),
    }
    # test-1 nests Modules under Course; real courses (ES-from-EN) put it at
    # the top level with trailing slashes ("basics/"). The merge above covers
    # both; the strip keeps module dirs resolvable either way.
    modules = _as_list(course.get("Modules"))
    extra_dirs = [Path(d) for d in (media_dirs or [])]
    media = MediaLibrary(
        extra_dirs
        + [
            course_dir / "images",
            course_dir / "media",
            course_dir / "audio",
        ]
    )
    builder = CourseBuilder(
        code=code,
        display_name=display_name,
        tts_locale=tts_locale,
        native_label=native_label,
        license_info=license_info,
        pack_version=pack_version,
        default_level=default_level,
        signature_chars=signature_chars,
        media=media,
    )
    prev_section: str | None = None
    total = len(modules)
    for index, module_name in enumerate(modules):
        module_dir = course_dir / str(module_name).strip("/")
        module_yaml = load_yaml(module_dir / "module.yaml")
        module = {**module_yaml, **(module_yaml.get("Module") or {})}
        title = str(module.get("Name") or module_name)
        skill_files = _as_list(module.get("Skills"))
        skills: list[tuple[str, dict[str, Any]]] = []
        for skill_file in skill_files:
            name = str(skill_file)
            if not name.endswith(".yaml"):
                name = f"{name}.yaml"
            path = module_dir / "skills" / name
            if not path.is_file():
                continue
            raw = load_yaml(path)
            skills.append((name, {**raw, **(raw.get("Skill") or {})}))
        section_id = builder.add_module(
            title,
            skills,
            index=index,
            total=total,
            prev_section_id=prev_section,
        )
        if section_id:
            prev_section = section_id
    if not builder.sections:
        raise ValueError("course produced no sections (all skills empty?)")
    if not builder.words_by_id:
        raise ValueError("vocab.json is required; course has no words")
    return builder.to_pack()


def unpack_pack(pack: dict[str, Any], dest: Path) -> None:
    dest.mkdir(parents=True, exist_ok=True)
    files = pack.get("files") or {}
    for rel, payload in files.items():
        if rel == _MEDIA_SIDECAR:
            continue
        path = dest / str(rel)
        path.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(payload, str):
            path.write_text(payload, encoding="utf-8")
        else:
            path.write_text(
                json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )


def validate_unpacked(course_dir: Path) -> int:
    tool_dir = Path(__file__).resolve().parent
    if str(tool_dir) not in sys.path:
        sys.path.insert(0, str(tool_dir))
    from course_cli import cmd_validate  # type: ignore

    class _Args:
        def __init__(self, path: Path) -> None:
            self.course_dir = path
            self.format = "text"

    return int(cmd_validate(_Args(course_dir)))


def write_pack(pack: dict[str, Any], out: Path, *, force_zip: bool = False) -> None:
    payload = json.loads(json.dumps(pack))
    media = payload.pop(_MEDIA_SIDECAR, {}) or {}
    out.parent.mkdir(parents=True, exist_ok=True)
    if media or force_zip:
        payload["format"] = "turnapack/2"
        with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED) as zf:
            zf.writestr(
                "pack.json",
                json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
            )
            for rel, src in media.items():
                src_path = Path(src)
                name = str(rel).replace("\\", "/")
                if (
                    not src_path.is_file()
                    or name.startswith("/")
                    or ".." in name.split("/")
                    or not name.startswith("media/")
                ):
                    raise ValueError(f"invalid media entry {name} -> {src}")
                zf.write(src_path, arcname=name)
        return
    payload["format"] = "turnapack/1"
    out.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--course-dir", type=Path, required=True)
    parser.add_argument("--code", required=True, help="Pack language code ([a-z]{2,3})")
    parser.add_argument("--display-name", required=True)
    parser.add_argument("--tts-locale", required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--pack-version", type=int, default=1)
    parser.add_argument("--default-level", default=None)
    parser.add_argument("--signature-chars", default=None)
    parser.add_argument(
        "--media-dir",
        action="append",
        default=[],
        type=Path,
        help="Extra directory of images/audio (repeatable). Also scans "
        "course_dir/images, media, and audio.",
    )
    parser.add_argument(
        "--zip",
        action="store_true",
        help="Write a zip even when no media files were found",
    )
    parser.add_argument(
        "--validate",
        action="store_true",
        help="Unpack and run course_cli.py validate before writing",
    )
    args = parser.parse_args(argv)
    pack = convert_course(
        args.course_dir,
        code=args.code,
        display_name=args.display_name,
        tts_locale=args.tts_locale,
        pack_version=args.pack_version,
        default_level=args.default_level,
        signature_chars=args.signature_chars,
        media_dirs=list(args.media_dir),
    )
    if args.validate:
        with tempfile.TemporaryDirectory(prefix="turnapack-") as tmp:
            unpack_dir = Path(tmp)
            unpack_pack(pack, unpack_dir)
            status = validate_unpacked(unpack_dir)
            if status != 0:
                return status
    write_pack(pack, args.out, force_zip=bool(args.zip))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
