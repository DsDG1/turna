"""Course scaffolding and sample data generator.

Provides creation of fresh course projects with sensible initial structures,
vocab, expressions, and grammar points. Decoupled from CourseAdapter.
"""
from __future__ import annotations

import time
from pathlib import Path
from typing import Any, Callable

from src.backend import api
from src.backend.lesson_content import slugify
from src.infrastructure.telemetry import telemetry


class CourseScaffold:
    """Builder for new course directories and sample scaffolds."""

    @staticmethod
    def init_new(
        course_dir: Path,
        meta: dict[str, Any],
        load_fn: Callable[[Path], None] | None = None,
    ) -> None:
        """Create a brand-new sample course directory and optionally load it.

        ``meta`` may contain:
        - display_name (str)
        - language (str, target language code, e.g. "en")
        - source_language (str, e.g. "Chinese", used for sample content only)
        - section_count (int)
        - lessons_per_unit (int)
        """
        course_dir = Path(course_dir)
        start = time.perf_counter()
        if course_dir.exists() and any(course_dir.iterdir()):
            raise FileExistsError(f"目标目录非空，无法初始化：{course_dir}")
        course_dir.mkdir(parents=True, exist_ok=True)
        (course_dir / "sections").mkdir(exist_ok=True)

        language = meta.get("language", "en")
        source_language = meta.get("source_language", "Chinese")
        display_name = meta.get("display_name", "My Chinese-English Course")
        section_count = max(1, min(8, int(meta.get("section_count", 3))))
        lessons_per_unit = max(1, int(meta.get("lessons_per_unit", 3)))

        index = {
            "version": 1,
            "language": language,
            "displayName": display_name,
            "sections": [],
        }
        sections = []
        for i in range(1, section_count + 1):
            sid = f"section{i}"
            section = {
                "id": sid,
                "name": f"Section {i}",
                "description": CourseScaffold.sample_section_description(i, source_language),
                "prerequisiteSectionIds": [f"section{i-1}"] if i > 1 else [],
                "units": [
                    {
                        "id": f"{sid}-u1",
                        "name": "Unit 1",
                        "description": "",
                        "prerequisiteUnitIds": [],
                        "lessons": [],
                    }
                ],
            }
            if i == 1:
                section["units"][0]["lessons"].append(
                    CourseScaffold.build_sample_intro_lesson(source_language, language)
                )
            else:
                for li in range(1, lessons_per_unit + 1):
                    section["units"][0]["lessons"].append(
                        {
                            "id": f"{sid}-u1-l{li}",
                            "name": f"Lesson {li}",
                            "description": "",
                            "type": "normal",
                            "template": "intro",
                            "prerequisiteLessonIds": [],
                            "content": {"subLessons": [], "linkedGrammarPointIds": []},
                        }
                    )
            sections.append(section)
            index["sections"].append(
                {
                    "id": sid,
                    "name": section["name"],
                    "description": section["description"],
                    "level": "A1" if i <= 3 else "A2" if i <= 5 else "B1" if i <= 7 else "B2",
                    "prerequisiteSectionIds": section["prerequisiteSectionIds"],
                    "file": f"sections/{sid}.json",
                }
            )

        api.save_json(course_dir / "index.json", index)
        for section, entry in zip(sections, index["sections"]):
            api.save_json(course_dir / entry["file"], section)
        api.save_json(
            course_dir / "vocab.json",
            {
                "version": 1,
                "language": language,
                "words": CourseScaffold.sample_vocab(language),
            },
        )
        api.save_json(
            course_dir / "expressions.json",
            {
                "version": 1,
                "language": language,
                "expressions": CourseScaffold.sample_expressions(language),
            },
        )
        api.save_json(
            course_dir / "grammar_points.json",
            {"grammarPoints": CourseScaffold.sample_grammar_points(language)},
        )

        if callable(load_fn):
            load_fn(course_dir)

        telemetry.record_duration(
            "repo.init_new",
            (time.perf_counter() - start) * 1000,
            payload={
                "course_dir": str(course_dir),
                "language": language,
                "section_count": meta.get("section_count", 3),
            },
        )

    @staticmethod
    def sample_section_description(index: int, source_language: str) -> str:
        if source_language.lower() in ("chinese", "zh", "zh-cn", "中文"):
            return "示例单元"
        return "Sample section"

    @staticmethod
    def sample_vocab(language: str) -> list[dict[str, Any]]:
        """Return a few casual sample words for the target language."""
        if language.lower() in ("en", "english"):
            words = [
                ("你好", "Hello"),
                ("谢谢", "Thank you"),
                ("再见", "Goodbye"),
                ("水", "Water"),
                ("猫", "Cat"),
            ]
        else:
            words = [
                ("hello", "Hello"),
                ("thank you", "Thank you"),
                ("goodbye", "Goodbye"),
                ("water", "Water"),
                ("cat", "Cat"),
            ]
        return [
            {
                "id": f"w-{slugify(en)}",
                "term": en,
                "translation": zh,
                "pronunciation": None,
                "audioAsset": None,
                "tags": ["sample"],
            }
            for zh, en in words
        ]

    @staticmethod
    def sample_expressions(language: str) -> list[dict[str, Any]]:
        if language.lower() in ("en", "english"):
            items = [
                ("你好，我叫…", "Hello, my name is…"),
                ("谢谢！", "Thank you!"),
                ("再见！", "Goodbye!"),
            ]
        else:
            items = [
                ("Hello, my name is…", "Hello, my name is…"),
                ("Thank you!", "Thank you!"),
                ("Goodbye!", "Goodbye!"),
            ]
        return [
            {
                "id": f"e-{slugify(en)[:20]}",
                "term": en,
                "translation": zh,
                "pronunciation": None,
                "audioAsset": None,
                "tags": ["sample"],
            }
            for zh, en in items
        ]

    @staticmethod
    def sample_grammar_points(language: str) -> list[dict[str, Any]]:
        if language.lower() in ("en", "english"):
            title = "主谓宾语序"
            explanation = "英语基本语序是主语 + 谓语 + 宾语。"
        else:
            title = "Basic word order"
            explanation = "Basic SVO word order."
        return [
            {
                "id": "g-word-order",
                "title": title,
                "explanation": explanation,
                "exampleExpressionIds": [],
                "exampleSentenceIds": [],
                "practiceItems": [],
            }
        ]

    @staticmethod
    def build_sample_intro_lesson(
        source_language: str, target_language: str
    ) -> dict[str, Any]:
        """Build a casual intro lesson using Chinese-English direction."""
        if target_language.lower() in ("en", "english"):
            word = ("你好", "Hello", "nǐ hǎo")
            sentence = ("你好吗？", "How are you?")
        else:
            word = ("Hello", "Hello", "")
            sentence = ("How are you?", "How are you?")

        return {
            "id": "section1-u1-l1",
            "name": "Sample Intro",
            "description": "",
            "type": "normal",
            "template": "intro",
            "prerequisiteLessonIds": [],
            "content": {
                "subLessons": [
                    {
                        "id": "section1-u1-l1-sl1",
                        "name": "Sample words",
                        "stages": [
                            {
                                "id": "section1-u1-l1-sl1-st1",
                                "name": "Learn & produce",
                                "items": [
                                    {
                                        "runtimeType": "showWord",
                                        "id": "sw-hello",
                                        "wordId": "w-hello",
                                        "context": f"{word[1]} — {word[0]}",
                                    },
                                    {
                                        "runtimeType": "translateSentence",
                                        "id": "ts-hello",
                                        "source": word[0],
                                        "expected": word[1],
                                        "hints": [word[1].lower()],
                                    },
                                    {
                                        "runtimeType": "fillBlank",
                                        "id": "fb-hello",
                                        "sentence": f"_____, {sentence[1]}?",
                                        "answer": word[1],
                                        "hint": word[0],
                                    },
                                ],
                            }
                        ],
                    }
                ]
            },
        }
