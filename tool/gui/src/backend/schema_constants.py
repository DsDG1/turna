"""Domain schema keys and types for course and lesson models.

Pure-Python module with zero Qt dependencies.
Uses enum.StrEnum so that every constant is an instance of str, seamlessly
interchangeable with string literals in dictionaries, JSON serialization,
and equality comparisons.
"""

from __future__ import annotations

from enum import StrEnum


class ContentKey(StrEnum):
    """Structural container and content keys within lesson definitions."""

    STAGES = "stages"
    SUB_LESSONS = "subLessons"
    LISTENING_PHASES = "listeningPhases"
    READING_PASSAGE = "readingPassage"
    ITEMS = "items"
    PHASE_TYPE = "phaseType"
    TARGET_EXPRESSION_IDS = "targetExpressionIds"
    TARGET_GRAMMAR_POINT_IDS = "targetGrammarPointIds"
    TITLE = "title"
    ID = "id"


class ResourceKey(StrEnum):
    """Resource table identifiers in course content."""

    VOCAB = "vocab"
    EXPRESSIONS = "expressions"
    GRAMMAR = "grammar"
    GRAMMAR_POINTS = "grammar_points"
    LESSONS = "lessons"


class ItemKey(StrEnum):
    """Field keys for interaction item dictionaries."""

    RUNTIME_TYPE = "runtimeType"
    ID = "id"
    PROMPT = "prompt"
    OPTIONS = "options"
    CORRECT_INDEX = "correctIndex"
    CORRECT_INDICES = "correctIndices"
    MIN_SELECTIONS = "minSelections"
    MAX_SELECTIONS = "maxSelections"
    SENTENCE = "sentence"
    ANSWER = "answer"
    HINT = "hint"
    HINTS = "hints"
    SOURCE = "source"
    EXPECTED = "expected"
    EXPECTED_ANSWER = "expectedAnswer"
    STATEMENT = "statement"
    SCRAMBLED = "scrambled"
    CORRECT = "correct"
    TRANSCRIPT = "transcript"
    FRONT = "front"
    BACK = "back"
    FRONT_HTML = "frontHtml"
    BACK_HTML = "backHtml"
    CSS = "css"
    MEDIA_BASE_PATH = "mediaBasePath"
    ALLOW_JS = "allowJs"
    SOURCE_NOTE_ID = "sourceNoteId"
    SOURCE_CARD_ID = "sourceCardId"
    WORD_ID = "wordId"
    GRAMMAR_POINT_ID = "grammarPointId"
    EXPRESSION_ID = "expressionId"
    AUDIO_ASSET = "audioAsset"
    AUDIO_ASSETS = "audioAssets"
    IMAGE_ASSET = "imageAsset"
    IMAGE_ASSETS = "imageAssets"
    CONTEXT = "context"
    TERM = "term"
    TRANSLATION = "translation"
    PRONUNCIATION = "pronunciation"
    EXAMPLE = "example"


class CourseKey(StrEnum):
    """Course structure and metadata dictionary keys."""

    COURSE = "course"
    UNITS = "units"
    LESSONS = "lessons"
    SECTIONS = "sections"
    METADATA = "metadata"
    VERSION = "version"
    TITLE = "title"
    DESCRIPTION = "description"
    ID = "id"
    NAME = "name"
    TEMPLATE = "template"
    CAN_AUTOPILOT = "canAutopilot"
    TAGS = "tags"


class TemplateType(StrEnum):
    """Functional lesson template identifiers (ADR 0021)."""

    INTRO = "intro"
    PRACTICE = "practice"
    REVIEW = "review"
    LISTENING = "listening"
    READING = "reading"
    MASTERY = "mastery"
    LEGACY = "legacy"


class InteractionType(StrEnum):
    """The 14 interaction item runtimeType identifiers."""

    SHOW_WORD = "showWord"
    MULTIPLE_CHOICE = "multipleChoice"
    MULTI_SELECT = "multiSelect"
    FILL_BLANK = "fillBlank"
    TRANSLATE_SENTENCE = "translateSentence"
    LISTEN_AND_PICK = "listenAndPick"
    TYPE_THE_WORD = "typeTheWord"
    LISTEN_ONLY = "listenOnly"
    REORDER_SENTENCE = "reorderSentence"
    READING_MCQ = "readingMcq"
    READING_TRUE_FALSE = "readingTrueFalse"
    READING_SHORT_ANSWER = "readingShortAnswer"
    ANKI_CARD = "ankiCard"
    ANKI_HTML_CARD = "ankiHtmlCard"


class ListeningPhaseType(StrEnum):
    """Phase types for listening template lessons."""

    WORD_PAIRING = "wordPairing"
    DIALOGUE = "dialogue"
    SUMMARY = "summary"


# Module-level shorthand aliases for frequent accesses
KEY_STAGES = ContentKey.STAGES
KEY_SUB_LESSONS = ContentKey.SUB_LESSONS
KEY_LISTENING_PHASES = ContentKey.LISTENING_PHASES
KEY_READING_PASSAGE = ContentKey.READING_PASSAGE
KEY_ITEMS = ContentKey.ITEMS

KEY_VOCAB = ResourceKey.VOCAB
KEY_EXPRESSIONS = ResourceKey.EXPRESSIONS
KEY_GRAMMAR = ResourceKey.GRAMMAR
KEY_GRAMMAR_POINTS = ResourceKey.GRAMMAR_POINTS

KEY_RUNTIME_TYPE = ItemKey.RUNTIME_TYPE
