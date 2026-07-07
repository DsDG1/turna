# Course Architecture — Extensibility Plan

> Status: planned (7 phases, P1 → P6 with P4 split into P4a/P4b/P4c)
> Owner: languagepart
> Last updated: 2026-07

## 1. Goals

| # | Goal | Why |
|---|---|---|
| G1 | **Scale** to B2-sized courses (≈5000 cards) without UI jank | Current `loadCourse` re-reads the whole JSON on every call |
| G2 | **Lesson types** — 5 distinct types with different structures (Normal/Review/Listening/Reading/Challenge) | Different pedagogical activities need different UIs, not a one-size-fits-all screen |
| G3 | **Mid-insertion** of sections/units/lessons without touching existing files | Today the whole course is one JSON; inserting requires editing the master file |
| G4 | **5-layer hierarchy** with variable counts at every level: `Language → Section → Unit → Lesson (+ internal Stage)` | Matches the actual pedagogical structure |
| G5 | **4-level prereqs** at Section / Unit / Lesson / Stage | Models curriculum gating at every granularity |
| G6 | **Global SRS word review** decoupled from the lesson tree | Word review is a vocabulary drill, not a lesson — different lifecycle, different UI |
| G7 | **Lesson-internal Stages** for unlimited content within one lesson | A lesson can grow to hundreds of interactions; groups give navigation + progress + prereqs |
| G8 | **6 interaction types** including reorder-sentence and translate-sentence (TTS-driven) | Required for listening classes; future-proof for cloze / MCQ / fill-blank |
| G9 | **Pre-recorded audio assets** (`assets/audio/`) | Listening lessons need real audio; runtime TTS adds latency and packaging complexity |
| G10 | **Cloud-ready** content source behind an interface, assets as one impl | Future server-fetched courses, no UI rewrite |
| G11 | **Plugin-friendly** for all abstractions (renderer / source / content) | New types added by 1 class + 1 `@Provides @IntoSet` line, no core changes |
| G12 | **Foldable course tree** with default-expand only the "current progress" path | Avoids overwhelming B2-scale trees |

## 2. Current pain points

| # | Issue | File | Impact at B2 scale |
|---|---|---|---|
| 1 | `loadCourse()` re-reads the full JSON on every navigation | `LanguagePackLoader.kt` | 100-200ms jank on language switch |
| 2 | `SrsCard.front/back: String` — flat text only | `SrsCard.kt` | No way to model audio/image/MCQ/cloze/reorder |
| 3 | One JSON per course (`basics.json` = full tree) | `assets/courses/swahili/basics.json` | Big files, painful diffs, can't insert cleanly |
| 4 | No abstraction for review queue generation | `ReviewViewModel.kt` | Hard to add "quick mixed (20)" or "lapses" modes |
| 5 | `Lesson` is polymorphic (flat or container) | `Lesson.kt` | Single type doing two jobs; mid-insertion is awkward |
| 6 | No "Section" layer — Sections are absent | `Course.kt` | Curriculum needs a grouping layer above Unit |
| 7 | No multi-level prereq — only `Unit.prerequisites` | `Unit.kt` | Lessons/Stage can't depend on other lessons/stages |
| 8 | No lesson-internal grouping | (none) | Long lessons become unbounded `LazyColumn` scroll |
| 9 | No 5 lesson types | (none) | All lessons look identical regardless of pedagogy |
| 10 | Course loading directly hits `Context.assets` | `SwahiliBasicsCoursePack.kt` | Can't swap to network/DB later without rewriting |
| 11 | `ReviewScreen` hard-codes "show front → reveal → 4 buttons" | `ReviewScreen.kt` | No way to render different exercise types |
| 12 | Course tree renders flat; no foldable / drill-down | `CourseTreeScreen.kt` | Useless for B2 with 5+ sections × 20+ units |
| 13 | `SrsCard` lives inside lessons | `SrsCard.kt` | Word review (SRS) and lesson completion are entangled |

## 3. Hierarchy overview

```
Language (enum)
└── LanguagePack          ← 1 per language, returns full Section tree + WordEntry pool from assets
    │
    ├── loadStructure(ctx) → List<Section>          ← course content
    │       └── Section  ← top-level curriculum grouping (e.g. "A1 Basics")
    │           ├── id, name, description
    │           ├── prerequisites: List<String>   ← other section ids
    │           └── units: List<Unit>
    │               └── Unit
    │                   ├── id, name, description
    │                   ├── prerequisites: List<String>
    │                   └── lessons: List<Lesson>
    │                       └── Lesson
    │                           ├── id, name, description
    │                           ├── type: LessonType            ← NORMAL / REVIEW / LISTENING / READING / CHALLENGE
    │                           ├── prerequisites: List<String>
    │                           └── content: LessonContent      ← sealed, 5 variants match LessonType
    │                               ├── NormalContent     (stages: List<Stage<Interaction>>)
    │                               ├── ListeningContent  (audio + stages<Interaction>)
    │                               ├── ReadingContent    (text + stages<ReadingQuestion>)
    │                               ├── ReviewContent     (stages<ReviewItem>)
    │                               └── ChallengeContent  (stages<Interaction>)
    │                                   └── Stage<T>          ← internal grouping, 1 level
    │                                       ├── id, name, description
    │                                       ├── prerequisites: List<String>
    │                                       └── items: List<T>
    │
    └── loadVocab(ctx) → List<WordEntry>              ← global word pool, feeds SRS + ShowWord interactions
```

**Key insight**: `SrsCard` is replaced by `WordEntry` (no lesson coupling). `SrsWord` is the SRS-state carrier for `WordEntry`, used only by the global word-review page. Lesson content is entirely **structured interactions**, not cards.

## 4. Domain models (final)

```kotlin
// domain/model/LessonType.kt
enum class LessonType { NORMAL, REVIEW, LISTENING, READING, CHALLENGE }

// domain/model/WordEntry.kt
data class WordEntry(
    val id: String,                  // "w-001"
    val term: String,                // "Jambo"
    val translation: String,         // "Hello"
    val pronunciation: String? = null,
    val audioAsset: String? = null,  // "audio/words/jambo.mp3"
    val tags: List<String> = emptyList()
)

// domain/model/Stage.kt
data class Stage<T>(
    val id: String,
    val name: String,                  // "Part 1: 词表"
    val description: String = "",
    val prerequisites: List<String> = emptyList(),   // other stage ids within same lesson
    val items: List<T>
)

// domain/model/Section.kt
data class Section(
    val id: String,
    val name: String,
    val description: String = "",
    val prerequisites: List<String> = emptyList(),   // other section ids
    val units: List<Unit>,
    val cardPool: List<SrsWord> = emptyList()         // global to section; legacy alias for WordEntry.id
)

// domain/model/Unit.kt
data class Unit(
    val id: String,
    val name: String,
    val description: String = "",
    val prerequisites: List<String> = emptyList(),   // other unit ids
    val lessons: List<Lesson>
)

// domain/model/Lesson.kt
data class Lesson(
    val id: String,
    val type: LessonType,
    val name: String,
    val description: String = "",
    val prerequisites: List<String> = emptyList(),   // other lesson ids
    val content: LessonContent
)

// domain/model/LessonContent.kt  (sealed, 5 variants)
sealed class LessonContent {
    data class NormalContent(
        val stages: List<Stage<Interaction>> = emptyList()
    ) : LessonContent()

    data class ListeningContent(
        val audioAsset: String,                       // "audio/lessons/s1-u1-l1.mp3"
        val stages: List<Stage<Interaction>> = emptyList()
    ) : LessonContent()

    data class ReadingContent(
        val text: String,
        val stages: List<Stage<ReadingQuestion>> = emptyList()
    ) : LessonContent()

    data class ReviewContent(
        val stages: List<Stage<ReviewItem>> = emptyList()
    ) : LessonContent()

    data class ChallengeContent(
        val stages: List<Stage<Interaction>> = emptyList()
    ) : LessonContent()
}

// domain/model/Interaction.kt  (sealed, 6 variants)
sealed class Interaction {
    data class ShowWord(
        val wordId: String,                           // references WordEntry.id
        val context: String? = null
    ) : Interaction()

    data class ReorderSentence(
        val audioAsset: String,                       // TTS-generated, in assets/audio/lessons/
        val scrambled: List<String>,                  // shuffled tokens
        val correct: List<String>                     // canonical order
    ) : Interaction()

    data class TranslateSentence(
        val sourceLang: String,
        val targetLang: String,
        val source: String,
        val expected: String,                         // fuzzy match accepted
        val hints: List<String> = emptyList()
    ) : Interaction()

    data class MultipleChoice(
        val prompt: String,
        val options: List<String>,
        val correctIndex: Int
    ) : Interaction()

    data class FillBlank(
        val sentence: String,
        val answer: String,
        val hint: String? = null
    ) : Interaction()

    data class ListenAndPick(
        val audioAsset: String,
        val prompt: String,
        val options: List<String>,
        val correctIndex: Int
    ) : Interaction()
}

// domain/model/ReadingQuestion.kt  (sealed, used only by ReadingContent)
sealed class ReadingQuestion {
    data class MultipleChoice(
        val prompt: String,
        val options: List<String>,
        val correctIndex: Int
    ) : ReadingQuestion()

    data class TrueFalse(
        val statement: String,
        val answer: Boolean
    ) : ReadingQuestion()

    data class ShortAnswer(
        val prompt: String,
        val expectedAnswer: String
    ) : ReadingQuestion()
}

// domain/model/SrsWord.kt   (renamed from SrsCard; key is wordId, not cardId)
data class SrsWord(
    val id: String,                  // == WordEntry.id
    val front: CardContent,          // polymorphic
    val back: CardContent,
    val language: Language,
    val dueAt: Instant,
    val intervalDays: Int = 0,
    val ease: Float = 2.5f,
    val reps: Int = 0,
    val lapses: Int = 0,
    val isLeech: Boolean = false
)
```

**No more `Course` class.** `Section` is the top of the tree.

## 5. Abstractions (8 interfaces, all pluggable via Hilt `@IntoSet` where useful)

### 5.1 `CardContent` — polymorphic prompt/answer

```kotlin
sealed class CardContent {
    abstract val rawText: String            // for TTS + a11y

    data class Text(val text: String) : CardContent()    // current behavior

    // future variants — only the data class + JSON key, no other code changes
    // data class Audio(val audioRef: String, val transcript: String) : CardContent()
    // data class Image(val imageRef: String, val caption: String) : CardContent()
}
```

### 5.2 `ReviewItem` — heterogeneous global-review queue unit

```kotlin
sealed class ReviewItem {
    abstract val id: String
    abstract val estimatedSeconds: Int

    data class TextCard(val word: SrsWord) : ReviewItem() {
        override val id get() = word.id
        override val estimatedSeconds get() = 8
    }
}
```

### 5.3 `CardRenderer` — `@Composable` render per type (global review page)

```kotlin
interface CardRenderer {
    val handlesType: KClass<out ReviewItem>
    @Composable fun renderSide(item: ReviewItem, side: CardSide, onReveal: () -> Unit)
}

@Module @InstallIn(SingletonComponent::class)
object CardRenderers {
    @Provides @IntoSet fun text(): CardRenderer = TextCardRenderer()
}
```

### 5.4 `InteractionRenderer` — `@Composable` render per type (lesson screens)

```kotlin
interface InteractionRenderer {
    val handlesType: KClass<out Interaction>
    @Composable fun Render(
        interaction: Interaction,
        state: InteractionState,
        onComplete: (correct: Boolean) -> Unit
    )
}

@Module @InstallIn(SingletonComponent::class)
object InteractionRenderers {
    @Provides @IntoSet fun showWord()         = ShowWordRenderer()
    @Provides @IntoSet fun reorderSentence()  = ReorderSentenceRenderer()
    @Provides @IntoSet fun translateSentence()= TranslateSentenceRenderer()
    @Provides @IntoSet fun multipleChoice()   = McqRenderer()
    @Provides @IntoSet fun fillBlank()        = FillBlankRenderer()
    @Provides @IntoSet fun listenAndPick()    = ListenAndPickRenderer()
}
```

### 5.5 `ReviewSource` — global word-review queue generation

```kotlin
interface ReviewSource {
    val id: String
    suspend fun items(context: Context, language: Language, now: Instant): List<ReviewItem>
}
```

| id format | scope | size | impl |
|---|---|---|---|
| `due` | all words whose persisted `dueAt <= now` | unbounded | `DueReviewSource` |
| `mixed:N` | `reps >= 1` words (any language) | fixed N, random sample | `MixedReviewSource(N)` |
| `lapses` | words with `lapses > 0` | all | `LapsesReviewSource` |
| `lesson-vocab:<id>` | all words referenced in a lesson's `ShowWord` interactions | all | `LessonVocabReviewSource(id)` |

`ReviewSourceFactory.parse(sourceId: String): ReviewSource` parses the id string.

### 5.6 `LessonRenderer` — composable per `LessonContent` variant

```kotlin
interface LessonRenderer {
    val handlesType: LessonType
    @Composable fun Body(
        lesson: Lesson,
        state: LessonScreenState,
        viewModel: LessonContentViewModel
    )
}

@Module @InstallIn(SingletonComponent::class)
object LessonRenderers {
    @Provides @IntoSet fun normal()    = NormalLessonRenderer()
    @Provides @IntoSet fun review()    = ReviewLessonRenderer()
    @Provides @IntoSet fun listening() = ListeningLessonRenderer()
    @Provides @IntoSet fun reading()   = ReadingLessonRenderer()
    @Provides @IntoSet fun challenge() = ChallengeLessonRenderer()
}
```

### 5.7 `CourseSource` — content backend (cloud-ready)

```kotlin
interface CourseSource {
    suspend fun loadStructure(language: Language): List<Section>
    suspend fun section(language: Language, sectionId: String): Section?
    suspend fun loadVocab(language: Language): List<WordEntry>
}

class AssetsCourseSource(@ApplicationContext private val context: Context) : CourseSource { ... }
// future: NetworkCourseSource fetches from a server and caches
```

`CourseCache` wraps `CourseSource` with an in-memory `ConcurrentHashMap` cache.

### 5.8 `LanguagePack` — single entry point per language

```kotlin
interface LanguagePack {
    val language: Language
    suspend fun loadStructure(context: Context): List<Section>
    suspend fun loadVocab(context: Context): List<WordEntry>
}
```

Adding a new language = 1 class + 1 JSON file + 1 line of Hilt.

## 6. Completion rules (4-level prereq + all-of at every level)

| entity | complete when |
|---|---|
| `Stage<T>.s` (any type) | all its `items` have ids in `completedItemIds(state)` |
| `Lesson.l` (any of 5 types) | **all** its `content.stages` are complete |
| `Unit.u` | **all** its `lessons` are complete |
| `Section.s` | **all** its `units` are complete |

**Unlock rules**:

```
Stage s unlocked = s.prerequisites.all { id => stage(id).complete }
                    AND parentLesson(s).unlocked
Lesson l unlocked = l.prerequisites.all { id => lesson(id).complete }
                    AND parentUnit(l).unlocked
Unit u unlocked   = u.prerequisites.all { id => unit(id).complete }
                    AND parentSection(u).unlocked
Section sec unlocked = sec.prerequisites.all { id => section(id).complete }
```

`ProgressRepository.markStageCompleteIfDone(lesson, stageId, now)` records a single stage's completion. All higher-level completion (lesson / unit / section) is **derived** in `*ProgressView` on each emission — no need to persist container state.

## 7. JSON schemas

### 7.1 File layout

```
assets/
├── courses/
│   └── swahili/
│       ├── index.json
│       ├── s1-basics.json
│       └── s2-grammar.json
├── vocab/
│   └── swahili.json                  ← global word pool
└── audio/
    ├── lessons/
    │   ├── s1-u1-l1.mp3
    │   └── s1-u2-l1.mp3
    └── words/
        ├── w-001.mp3
        └── w-002.mp3
```

### 7.2 `courses/<lang>/index.json`

```json
{
  "id": "sw",
  "language": "sw",
  "name": "Swahili",
  "version": 1,
  "sections": [
    { "id": "s1", "asset": "s1-basics.json" },
    { "id": "s2", "asset": "s2-grammar.json" }
  ]
}
```

### 7.3 Section file (full tree)

```json
{
  "id": "s1",
  "name": "Basics",
  "description": "A1 level",
  "prerequisites": [],
  "units": [
    {
      "id": "u1",
      "name": "Greetings",
      "description": "Hello and goodbye",
      "prerequisites": [],
      "lessons": [
        {
          "id": "u1-l1",
          "type": "NORMAL",
          "name": "Hello",
          "description": "",
          "prerequisites": [],
          "content": {
            "type": "NORMAL",
            "stages": [
              {
                "id": "stage1",
                "name": "Part 1: 词表",
                "description": "Vocabulary intro",
                "prerequisites": [],
                "items": [
                  { "type": "showWord",         "wordId": "w-001" },
                  { "type": "showWord",         "wordId": "w-002" }
                ]
              },
              {
                "id": "stage2",
                "name": "Part 2: 例句",
                "description": "Sentence practice",
                "prerequisites": ["stage1"],
                "items": [
                  { "type": "reorderSentence",
                    "audioAsset": "audio/lessons/u1-l1-s2.mp3",
                    "scrambled": ["Jambo", "rafiki", "yangu"],
                    "correct":   ["Jambo", "rafiki", "yangu"] },
                  { "type": "translateSentence",
                    "sourceLang": "sw", "targetLang": "en",
                    "source": "Jambo rafiki yangu",
                    "expected": "Hello, my friend" }
                ]
              }
            ]
          }
        }
      ]
    }
  ]
}
```

### 7.4 Listening lesson

```json
{
  "id": "u1-l2",
  "type": "LISTENING",
  "name": "Listening drill",
  "prerequisites": [],
  "content": {
    "type": "LISTENING",
    "audioAsset": "audio/lessons/u1-l2.mp3",
    "stages": [
      {
        "id": "s1",
        "name": "听全文回答",
        "items": [
          { "type": "listenAndPick",
            "audioAsset": "audio/lessons/u1-l2.mp3",
            "prompt": "How many speakers?",
            "options": ["1", "2", "3"], "correctIndex": 1 }
        ]
      }
    ]
  }
}
```

### 7.5 Reading lesson

```json
{
  "id": "u2-l1",
  "type": "READING",
  "name": "短文阅读",
  "content": {
    "type": "READING",
    "text": "Habari za asubuhi. Mimi ni mwalimu...",
    "stages": [
      {
        "id": "s1",
        "name": "Comprehension",
        "items": [
          { "type": "multipleChoice", "prompt": "作者是谁?", "options": ["老师", "学生", "医生"], "correctIndex": 0 }
        ]
      }
    ]
  }
}
```

### 7.6 `vocab/<lang>.json`

```json
{
  "language": "sw",
  "version": 1,
  "words": [
    { "id": "w-001", "term": "Jambo",     "translation": "Hello",   "audioAsset": "audio/words/w-001.mp3", "tags": ["greeting", "A1"] },
    { "id": "w-002", "term": "Habari",    "translation": "How are you?", "audioAsset": "audio/words/w-002.mp3", "tags": ["greeting", "A1"] }
  ]
}
```

### 7.7 Card content `type` field

```jsonc
// current (only variant implemented)
{ "id": "w-001", "type": "text_text", "front": "Jambo", "back": "Hello" }

// legacy (still accepted)
{ "id": "w-001", "front": "Jambo", "back": "Hello" }
```

## 8. Progress view data model

```kotlin
data class SectionProgressView(
    val section: Section,
    val isComplete: Boolean,
    val isUnlocked: Boolean,
    val isExpanded: Boolean,
    val units: List<UnitProgressView>
)

data class UnitProgressView(
    val unit: Unit,
    val isComplete: Boolean,
    val isUnlocked: Boolean,
    val isExpanded: Boolean,
    val lessons: List<LessonProgressView>
)

data class LessonProgressView(
    val lesson: Lesson,
    val isComplete: Boolean,                    // derived: all stages complete
    val isUnlocked: Boolean,                    // derived: prereqs met
    val isExpanded: Boolean,
    val stages: List<StageProgressView>
)

data class StageProgressView(
    val stage: Stage<*>,
    val isComplete: Boolean,                    // derived
    val isUnlocked: Boolean,                    // derived
    val itemsCompleted: Int,
    val totalItems: Int
)
```

`ProgressRepository.observeStructure(sections: List<Section>): Flow<SectionProgressView>` walks the tree and produces views on every `srs_state` / `stage_progress` change.

`CourseTreeViewModel` holds:
- `expandedIds: MutableStateFlow<Set<String>>` — ids of expanded nodes
- toggle methods: `toggleSection(id)`, `toggleUnit(id)`, `toggleLesson(id)`
- auto-expand the "active path" on first emit if no manual override

## 9. UI

### 9.1 CourseTreeScreen (foldable tree, after P5)

```
COURSE_TREE
┌──────────────────────────────────────────────┐
│  Swahili                                    │
│  5 cards due                                │
│                                              │
│  [ Start due (5) ]        ← source="due"     │
│  [ Quick mixed (20) ]     ← source="mixed:20"│
│  [ Word review ]          ← new tab          │
│                                              │
│  ── Browse all sections ──                   │
│                                              │
│  ▾ Section 1: Basics              ● (done)  │  expanded (active path)
│    ▾ Unit 1: Greetings            ●         │  expanded
│      ▾ Lesson 1: Hello            ●         │  expanded
│        [N]  Part 1: 词表   2/2 ✓             │
│        [N]  Part 2: 例句   2/2 ✓             │
│      ▸ Lesson 2: Listening        ◐         │  collapsed
│        [L]
│    ▸ Unit 2: Politeness           ◐         │  collapsed
│  ▸ Section 2: Daily life          🔒        │  collapsed + locked
│                                              │
│  Legend: [N] Normal  [L] Listening  [R]      │
│          Reading  [C] Challenge  [V] Review  │
└──────────────────────────────────────────────┘
```

**Default expand rule**: the path containing the first incomplete leaf is expanded; everything else is collapsed. User can manually toggle.

**Locked** nodes show a 🔒 badge and are not clickable.

### 9.2 LessonContentScreen (after P6)

```kotlin
@Composable
fun LessonContentScreen(
    courseId: String, sectionId: String, unitId: String, lessonId: String,
    onBack: () -> Unit, onComplete: () -> Unit,
    viewModel: LessonContentViewModel = hiltViewModel()
) {
    val state by viewModel.state.collectAsState()
    when (val content = state.lesson?.content) {
        is NormalContent     -> NormalLessonBody(content, state, viewModel, onBack, onComplete)
        is ListeningContent  -> ListeningLessonBody(content, state, viewModel, onBack, onComplete)
        is ReadingContent    -> ReadingLessonBody(content, state, viewModel, onBack, onComplete)
        is ReviewContent     -> ReviewLessonBody(content, state, viewModel, onBack, onComplete)
        is ChallengeContent  -> ChallengeLessonBody(content, state, viewModel, onBack, onComplete)
        null -> LoadingView()
    }
}
```

**Top bar shows**: lesson name + "Stage 2/5" progress + close button.

**Each body**: renders Stages sequentially. Within a Stage, renders interactions one at a time. On stage complete → auto-advance to next stage (or finish lesson if last).

## 10. Hilt DI (after P6)

```kotlin
@Module @InstallIn(SingletonComponent::class)
abstract class AppModule {
    @Binds @Singleton abstract fun bindSrsEngine(impl: Sm2Engine): SrsEngine
    @Binds @Singleton abstract fun bindTtsEngine(impl: NoOpTtsEngine): TtsEngine
    @Binds @Singleton abstract fun bindLanguagePackRegistry(impl: DefaultLanguagePackRegistry): LanguagePackRegistry
    @Binds @Singleton abstract fun bindCourseSource(impl: AssetsCourseSource): CourseSource
    @Binds @Singleton abstract fun bindAppDatabase(...): AppDatabase
    // DAOs
}

@Module @InstallIn(SingletonComponent::class)
object CardRenderers {
    @Provides @IntoSet fun text(): CardRenderer = TextCardRenderer()
}

@Module @InstallIn(SingletonComponent::class)
object InteractionRenderers {
    @Provides @IntoSet fun showWord()         = ShowWordRenderer()
    @Provides @IntoSet fun reorderSentence()  = ReorderSentenceRenderer()
    @Provides @IntoSet fun translateSentence()= TranslateSentenceRenderer()
    @Provides @IntoSet fun multipleChoice()   = McqRenderer()
    @Provides @IntoSet fun fillBlank()        = FillBlankRenderer()
    @Provides @IntoSet fun listenAndPick()    = ListenAndPickRenderer()
}

@Module @InstallIn(SingletonComponent::class)
object LessonRenderers {
    @Provides @IntoSet fun normal()    = NormalLessonRenderer()
    @Provides @IntoSet fun review()    = ReviewLessonRenderer()
    @Provides @IntoSet fun listening() = ListeningLessonRenderer()
    @Provides @IntoSet fun reading()   = ReadingLessonRenderer()
    @Provides @IntoSet fun challenge() = ChallengeLessonRenderer()
}

@Module @InstallIn(SingletonComponent::class)
object ReviewSources {
    @Provides fun due(): DueReviewSource = DueReviewSource()
    @Provides @IntoSet fun mixed(): MixedReviewSource = MixedReviewSource()
    @Provides @IntoSet fun lapses(): LapsesReviewSource = LapsesReviewSource()
    @Provides @IntoSet fun lessonVocab(): LessonVocabReviewSource = LessonVocabReviewSource()
}

@Module @InstallIn(SingletonComponent::class)
object PackProviders {
    @Provides @IntoSet fun swahiliLanguagePack(p: SwahiliLanguagePack): LanguagePack = p
    // future: @Provides @IntoSet fun hindiLanguagePack(p: HindiLanguagePack) = p
}
```

## 11. Routing

| Route | Nav args | Purpose |
|---|---|---|
| `SPLASH` | — | Flash screen, route based on `onboarding_done` |
| `ONBOARDING` | — | Language picker |
| `COURSE_TREE` | — | 5-layer foldable tree + 3 quick actions |
| `LESSON` | `courseId`, `sectionId`, `unitId`, `lessonId` | Renders one of 5 bodies based on `lesson.type` |
| `WORD_REVIEW` | `source: String` (default "due") | Global SRS over WordEntry pool |

## 12. Files touched

**New files**:

| Path | Purpose |
|---|---|
| `domain/model/CardContent.kt` | sealed class (Text only now) |
| `domain/model/ReviewItem.kt` | sealed class (TextCard only now) |
| `domain/model/Section.kt` | top-level grouping |
| `domain/model/Stage.kt` | lesson-internal grouping |
| `domain/model/LessonContent.kt` | sealed class (5 variants) |
| `domain/model/Interaction.kt` | sealed class (6 variants) |
| `domain/model/ReadingQuestion.kt` | sealed class (3 variants) |
| `domain/model/WordEntry.kt` | global word pool entry |
| `domain/model/StructureView.kt` | progress view tree |
| `domain/card/CardRenderer.kt` | global-review renderer interface |
| `domain/card/TextCardRenderer.kt` | built-in |
| `domain/interaction/InteractionRenderer.kt` | lesson-screen renderer interface |
| `domain/interaction/ShowWordRenderer.kt` | built-in |
| `domain/interaction/ReorderSentenceRenderer.kt` | built-in (new) |
| `domain/interaction/TranslateSentenceRenderer.kt` | built-in (new) |
| `domain/interaction/McqRenderer.kt` | built-in |
| `domain/interaction/FillBlankRenderer.kt` | built-in |
| `domain/interaction/ListenAndPickRenderer.kt` | built-in |
| `domain/lesson/LessonRenderer.kt` | per-type body interface |
| `domain/lesson/NormalLessonRenderer.kt` | built-in |
| `domain/lesson/ReviewLessonRenderer.kt` | built-in |
| `domain/lesson/ListeningLessonRenderer.kt` | built-in |
| `domain/lesson/ReadingLessonRenderer.kt` | built-in |
| `domain/lesson/ChallengeLessonRenderer.kt` | built-in |
| `domain/review/ReviewSource.kt` | queue-source interface |
| `domain/review/ReviewSourceFactory.kt` | parses source id |
| `domain/review/DueReviewSource.kt` | all-due source |
| `domain/review/MixedReviewSource.kt` | random N from `reps >= 1` |
| `domain/review/LapsesReviewSource.kt` | lapses-only source |
| `domain/review/LessonVocabReviewSource.kt` | words from one lesson |
| `domain/course/CourseSource.kt` | content backend interface |
| `domain/course/AssetsCourseSource.kt` | assets impl |
| `domain/course/CourseCache.kt` | in-memory cache |
| `assets/courses/swahili/index.json` | language index |
| `assets/courses/swahili/s1-*.json` | section files |
| `assets/vocab/swahili.json` | global word pool |
| `assets/audio/lessons/*.mp3` | lesson audio (pre-baked) |
| `assets/audio/words/*.mp3` | word audio (pre-baked) |
| `tools/content/import.py` | (already exists, update for Stage schema) |
| `tools/content/validate.py` | (already exists, update for Stage schema) |
| `tools/audio/bake.py` | new — pre-generate mp3 from word/sentence list |
| `docs/course-architecture.md` | this document |

**Modified files**:

| Path | Change |
|---|---|
| `domain/model/SrsCard.kt` | rename to `SrsWord.kt`; `id: String` (= WordEntry.id) |
| `domain/model/Lesson.kt` | add `type: LessonType`, `content: LessonContent`; drop polymorphic |
| `domain/model/Unit.kt` | add `prerequisites: List<String>` |
| `domain/language/LanguagePack.kt` | from marker → `loadStructure(ctx) + loadVocab(ctx)` |
| `domain/language/LanguagePackLoader.kt` | parse 5-layer JSON + Stage + vocab; `parseIndex` / `parseSection` / `parseVocab` |
| `domain/progress/ProgressRepository.kt` | recursive `markStageCompleteIfDone`; `observeStructure`; `observeReviewedWords` |
| `data/local/room/SrsStateEntity.kt` | `cardId: String` → `wordId: String` |
| `data/local/room/StageProgressEntity.kt` | new — `(stageId PK, lessonId, isCompleted, completedAt)` |
| `data/local/room/StageProgressDao.kt` | new — observe/upsert |
| `presentation/wordreview/WordReviewScreen.kt` | new — replaces old ReviewScreen |
| `presentation/wordreview/WordReviewViewModel.kt` | new |
| `presentation/lesson/LessonContentScreen.kt` | new — dispatches by type |
| `presentation/lesson/LessonContentViewModel.kt` | new |
| `presentation/coursetree/CourseTreeViewModel.kt` | `CourseSource` + `CourseCache`; expand/collapse state; auto-expand active path |
| `presentation/coursetree/CourseTreeScreen.kt` | 5-layer foldable; lesson type icons; locked badges; 3 quick actions |
| `presentation/navigation/Route.kt` | add `LESSON`, `WORD_REVIEW`; remove `REVIEW` |
| `presentation/navigation/AppNavigation.kt` | wire new routes |
| `core/di/AppModule.kt` | new `@Provides` for renderers, sources, `CourseSource`; remove `CourseRegistry` |
| `res/values/strings.xml` | new UI strings (lesson buttons, sub-lesson labels, locked badge) |

**Deleted files**:

| Path | Reason |
|---|---|
| `domain/model/SubLesson.kt` | Replaced by Stage |
| `domain/model/Course.kt` | Replaced by Section |
| `domain/language/CoursePack.kt` | Replaced by `LanguagePack.loadStructure` |
| `domain/language/CourseRegistry.kt` | No longer needed |
| `domain/language/DefaultCourseRegistry.kt` | No longer needed |
| `assets/courses/swahili/basics.json` | Replaced by per-section files |
| `presentation/review/ReviewScreen.kt` | Renamed/replaced by `WordReviewScreen` |
| `presentation/review/ReviewViewModel.kt` | Replaced |

## 13. Test count growth

| stage | tests | total |
|---|---|---|
| N1-N2 (current) | 36 | 36 |
| P1 | 0 (import paths only) | 36 |
| P2 | +2-3 (renderer) | 38-39 |
| P3 | +5-7 (sources) | 43-46 |
| P4a | +6-8 (parser + types) | 49-54 |
| P4b | +5-8 (unlock + completion) | 54-62 |
| P4c | +4-6 (loader + cache + vocab) | 58-68 |
| P5 | 0 (UI only) | 58-68 |
| P6 | +10-15 (renderers + bodies) | 68-83 |

## 14. Risk register

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | `SrsWord` rename breaks 9 existing tests | high | medium | P1 keeps JSON parser backward-compat; tests only need import changes |
| R2 | 5 `LessonContent` variants × 6 `Interaction` types = 30 render combinations to maintain | medium | high | Plugin architecture; new combination = 0 changes if both already exist |
| R3 | `Stage<T>` generics break kotlinx.serialization | high | medium | Use 5 concrete Stage data classes (`NormalStage` / `ListeningStage` / `ReadingStage` / `ReviewStage` / `ChallengeStage`), share `Stage` interface |
| R4 | 4-level prereq state machine is complex | medium | medium | UI only shows lock/unlock badges; doesn't force navigation; clear "Complete X first" hints |
| R5 | Pre-baked audio files are large; APK bloat | medium | medium | Compress to opus (~10KB per 30s sentence); group by language; lazy asset loading |
| R6 | ReorderSentence strict matching too unforgiving | medium | low | Default: exact match; future: fuzzy (Levenshtein ≤ 1); per-card `tolerance: Int = 0` field |
| R7 | 5 LessonContentBody screens share boilerplate | high | low | Common scaffold (top bar, stage progress, back button); 5 bodies only differ in inner content |
| R8 | Word review progress state isn't tied to lesson completion | low | low | Word SRS is independent; lessons can mark words "introduced" but don't need to track every rep |
| R9 | 8-day schedule with new lesson type system is large | high | medium | P1-P3 (1.5 days) is decoupled and shippable independently as "polish current state"; P4a-P4c + P5-P6 is the real "course refactor" |
| R10 | Foldable tree default-expand heuristic may surprise users | medium | low | First version: always expand sections with incomplete content; let user manually collapse |

## 15. Backward compatibility

- **JSON**: parser accepts legacy `{front, back}` form alongside new `{type, front, back}` form. New `Section`-based files replace old `basics.json` (asset path change, not format change).
- **API**: `SrsCard` → `SrsWord` rename is *internal*; callers updated atomically. `LanguagePack` interface signature changes (was marker, now has methods); all callers updated atomically.
- **Data**: existing `srs_state` table key renamed `cardId` → `wordId` (migration: SQLite `ALTER TABLE RENAME COLUMN`); `lesson_progress` table unchanged. New `stage_progress` table added.
- **SRS algorithm**: SM-2 unchanged.
- **Routing**: REVIEW route replaced by `LESSON` and `WORD_REVIEW`; callers updated atomically.

## 16. Out of scope (deferred)

- Audio / Image / MultipleChoice / Cloze `CardContent` variants (architecture supports; not implemented)
- `AndroidTtsEngine` real TTS
- Cloud-fetched courses (interface ready; assets-only for now)
- Server-side content management
- Animated transitions between stages
- Course marketplace / community packs
- Section/Unit/Lesson rename / reordering via UI
- Multi-user / sync / account system

## 17. Acceptance

- [ ] P1: `SrsWord` uses `CardContent`; old JSON parses; all 36 tests pass
- [ ] P2: `CardRenderer` interface + 1 built-in; `WordReviewScreen` renders via renderer
- [ ] P3: 4 `ReviewSource` impls; `WordReviewViewModel` reads `source: String`; random mixed review works end-to-end
- [ ] P4a: 5 `LessonType` × 5 `LessonContent` variants; 6 `Interaction`; `Stage<T>`; parser handles all forms
- [ ] P4b: 4-level prereq unlock + all-of completion at every level; `observeStructure` produces full tree view
- [ ] P4c: per-section asset files + `vocab/<lang>.json`; `CourseSource` + `CourseCache`; lazy loading
- [ ] P5: `CourseTreeScreen` 5-layer foldable tree; lesson type icons; locked badges; 3 quick actions
- [ ] P6: 5 `LessonRenderer` bodies; 6 `InteractionRenderer`s; stage-aware navigation; `LESSON` route
- [ ] Final: `assembleDebug` succeeds; 68-83 tests pass; course tree renders; word review works; all 5 lesson types playable end-to-end

## 18. Workload estimate (top-level)

| Phase | Days | Cumulative |
|---|---|---|
| P1 | 0.5 | 0.5 |
| P2 | 0.5 | 1.0 |
| P3 | 0.5 | 1.5 |
| P4a | 2.0 | 3.5 |
| P4b | 1.0 | 4.5 |
| P4c | 0.5 | 5.0 |
| P5 | 0.5 | 5.5 |
| P6 | 2.5 | 8.0 |
| **Total** | **8.0 days** | |

## 19. 施工阶段安排 (construction / implementation schedule)

This is the day-by-day execution plan. Each day ends with a verifiable checkpoint. 全部 11 个工作日（含 buffer + 集成测试）。

### Day 1 — P1: CardContent + SrsWord 改名

| 时段 | 工作项 | 文件 |
|---|---|---|
| AM | 加 `CardContent` sealed class（仅 `Text`） | `domain/model/CardContent.kt` (新) |
| AM | `SrsCard.kt` → `SrsWord.kt`（rename + `id: String` 不变，字段加 `front: CardContent` / `back: CardContent`） | `domain/model/SrsWord.kt` (rename) |
| AM | `LanguagePackLoader` 加 `CardContent` 解析；JSON 兼容 `{front,back:string}` 老格式 | `domain/language/LanguagePackLoader.kt` |
| PM | 更新 9 个测试文件的 import 路径 (`SrsCard` → `SrsWord`) | `app/src/test/.../Srs*Test.kt`, `LanguagePackLoaderTest.kt` 等 |
| PM | 加 1 个测试：`CardContent` 解析两种 JSON 形态 | `LanguagePackLoaderTest.kt` |
| 验证 | `./gradlew :app:testDebugUnitTest :app:assembleDebug` 全过；36 个测试 | — |

### Day 2 — P2: ReviewItem + CardRenderer

| 时段 | 工作项 | 文件 |
|---|---|---|
| AM | 加 `ReviewItem` sealed class（仅 `TextCard(word: SrsWord)`） | `domain/model/ReviewItem.kt` (新) |
| AM | 加 `CardRenderer` interface + `TextCardRenderer` 实现 | `domain/card/CardRenderer.kt`, `TextCardRenderer.kt` (新) |
| PM | Hilt `@Provides @IntoSet` 绑定 `TextCardRenderer` | `core/di/AppModule.kt` |
| PM | 现有 `ReviewScreen` 改成"按 `ReviewItem` 类型查 renderer 渲染"（删除 hardcode） | `presentation/review/ReviewScreen.kt` (保留文件名，本阶段不重命名) |
| PM | 加 2-3 个 `TextCardRenderer` 测试 + 1 个 `ReviewScreen` Compose 测试 | — |
| 验证 | 38-39 个测试全过；`assembleDebug` 过 | — |

### Day 3 — P3: ReviewSource + Factory + 路由改

| 时段 | 工作项 | 文件 |
|---|---|---|
| AM | 加 `ReviewSource` interface + 4 个实现 (`DueReviewSource` / `MixedReviewSource` / `LapsesReviewSource` / `LessonVocabReviewSource`) | `domain/review/ReviewSource*.kt` (新) |
| AM | 加 `ReviewSourceFactory.parse(sourceId)` (enum `SourceKind` + sealed result) | `domain/review/ReviewSourceFactory.kt` (新) |
| PM | `Room.SrsStateDao` 加 `observeReviewedWordsByLanguage` 查询（`reps >= 1` 的全集） | `data/local/room/SrsStateDao.kt` |
| PM | `ReviewViewModel` 改：接受 `source: String`，通过 factory 拿 source，再调 `source.items(...)` | `presentation/review/ReviewViewModel.kt` |
| PM | `Route.kt` + `AppNavigation.kt`：REVIEW nav arg 从 `lessonId` 改 `source: String` | `presentation/navigation/*.kt` |
| PM | 加 5-7 个 source 测试 (4 个 impl + factory) | — |
| 验证 | 43-46 个测试全过；`assembleDebug` 过 | — |

### Day 4 — P4a part 1: LessonType + LessonContent sealed

| 时段 | 工作项 | 文件 |
|---|---|---|
| AM | 加 `LessonType` enum (5 个值) | `domain/model/LessonType.kt` (新) |
| AM | 加 `Lesson` 加字段 `type`, `content`；`Lesson` 旧 polymorphic 字段删除 | `domain/model/Lesson.kt` |
| AM | 加 `LessonContent` sealed + 5 个 variants (NormalContent/ListeningContent/ReadingContent/ReviewContent/ChallengeContent) | `domain/model/LessonContent.kt` (新) |
| PM | 5 个 lesson type 的 parser 框架 (skeleton, 暂不解析 items) | `LanguagePackLoader.kt` |
| PM | 5-6 个类型测试 | — |
| 验证 | 49-52 个测试全过 | — |

### Day 5 — P4a part 2: Interaction + Stage + 完整 parser

| 时段 | 工作项 | 文件 |
|---|---|---|
| AM | 加 `Interaction` sealed (6 variants: ShowWord / ReorderSentence / TranslateSentence / MultipleChoice / FillBlank / ListenAndPick) | `domain/model/Interaction.kt` (新) |
| AM | 加 `ReadingQuestion` sealed (3 variants) | `domain/model/ReadingQuestion.kt` (新) |
| AM | 加 `Stage<T>` data class + 5 个 sealed `*Stage` (不用泛型序列化) | `domain/model/Stage.kt` (新) |
| PM | `LanguagePackLoader` 完整实现 5 种 content + 6 种 interaction + 3 种 reading question 的 JSON 解析 | `LanguagePackLoader.kt` |
| PM | 5-7 个 parser 测试 (per content variant) | — |
| 验证 | 54-58 个测试全过 | — |

### Day 6 — P4b: 4 级 prereq + StageProgressEntity

| 时段 | 工作项 | 文件 |
|---|---|---|
| AM | `Unit` / `Lesson` 加 `prerequisites: List<String>` 字段 | `domain/model/{Unit,Lesson}.kt` |
| AM | `Stage` 加 `prerequisites: List<String>` 字段 (Day 5 已有) | — |
| AM | 新 `StageProgressEntity` + `StageProgressDao` | `data/local/room/StageProgressEntity.kt`, `Dao.kt` (新) |
| PM | `ProgressRepository.markStageCompleteIfDone(lesson, stageId, now)` (按 lesson.type 决定完成规则) | `domain/progress/ProgressRepository.kt` |
| PM | `ProgressRepository.observeStructure(sections)`：遍历 tree 产出 `SectionProgressView` 流 | `domain/progress/ProgressRepository.kt` |
| PM | 4 级 prereq unlock 派生 + all-of 完成派生 | `ProgressRepository.kt` |
| PM | 5-8 个 unlock/completion 测试 | — |
| 验证 | 60-66 个测试全过 | — |

### Day 7 — P4c: 资产文件 + WordEntry + CourseSource

| 时段 | 工作项 | 文件 |
|---|---|---|
| AM | 加 `WordEntry` 数据类 | `domain/model/WordEntry.kt` (新) |
| AM | `LanguagePackLoader.parseVocab(raw)` 解析 `assets/vocab/<lang>.json` | `LanguagePackLoader.kt` |
| AM | 写 `assets/courses/swahili/index.json` + 把 `basics.json` 拆为 `s1-*.json` + `s2-*.json`（含 stage 嵌套 JSON） | `assets/courses/swahili/*.json` |
| AM | 写 `assets/vocab/swahili.json` (5 个示例词) | `assets/vocab/swahili.json` (新) |
| PM | 加 `CourseSource` interface + `AssetsCourseSource` 实现 | `domain/course/CourseSource.kt`, `AssetsCourseSource.kt` (新) |
| PM | 加 `CourseCache` 内存缓存 (ConcurrentHashMap) | `domain/course/CourseCache.kt` (新) |
| PM | `LanguagePack` 改：从 marker → `loadStructure()` + `loadVocab()` | `domain/language/LanguagePack.kt` |
| PM | Hilt 注入 `CourseSource` + `CourseCache`；删 `CourseRegistry` 引用 | `core/di/AppModule.kt` |
| PM | 4-6 个 loader/cache/vocab 测试 | — |
| 验证 | 64-72 个测试全过 | — |

### Day 8 — P5: CourseTree 5 层 foldable

| 时段 | 工作项 | 文件 |
|---|---|---|
| AM | `CourseTreeViewModel` 加 `expandedIds: MutableStateFlow<Set<String>>` + toggle methods | `presentation/coursetree/CourseTreeViewModel.kt` |
| AM | 默认展开"active path" 算法（找第一个未完成 leaf 的父链） | `CourseTreeViewModel.kt` |
| PM | `CourseTreeScreen` 改 foldable 5 层 tree + lesson type 图标 (`[N]` `[L]` `[R]` `[C]` `[V]`) + 锁徽章 | `presentation/coursetree/CourseTreeScreen.kt` |
| PM | 加 3 个 quick action 按钮: `Start due (5)` / `Quick mixed (20)` / `Word review` | `CourseTreeScreen.kt` |
| PM | 新 strings.xml 字段 | `res/values/strings.xml` |
| 验证 | `assembleDebug` 过；UI 在 preview 工具能渲染 | — |

### Day 9 — P6 part 1: InteractionRenderer × 6

| 时段 | 工作项 | 文件 |
|---|---|---|
| AM | 加 `InteractionRenderer` interface | `domain/interaction/InteractionRenderer.kt` (新) |
| AM | 实现 6 个 renderer: `ShowWordRenderer` / `McqRenderer` / `FillBlankRenderer` (复用现有 widget) | 3 个文件 |
| PM | 实现新 renderer: `ReorderSentenceRenderer` (drag-and-drop tokens, 匹配后标绿) | 新文件 |
| PM | 实现 `TranslateSentenceRenderer` (input field + 模糊匹配校验 + hints 按钮) | 新文件 |
| PM | 实现 `ListenAndPickRenderer` (audio play button + MCQ 选项) | 新文件 |
| PM | 6 个 renderer 单元测试 | — |
| 验证 | 70-78 个测试全过；6 个 renderer 在 Compose preview 能渲染 | — |

### Day 10 — P6 part 2: LessonContentBody × 5

| 时段 | 工作项 | 文件 |
|---|---|---|
| AM | 加 `LessonRenderer` interface + 5 个 LessonType 的 renderer (`NormalLessonRenderer` / `ReviewLessonRenderer` / `ListeningLessonRenderer` / `ReadingLessonRenderer` / `ChallengeLessonRenderer`) | 6 个文件 |
| AM | 抽公共 `LessonScaffold` (top bar: lesson name + "Stage 2/5" + close 按钮) | `presentation/lesson/CommonScaffold.kt` (新) |
| PM | `LessonContentScreen` 顶层 + `when (type)` 分发到 5 个 body | `presentation/lesson/LessonContentScreen.kt` (新) |
| PM | `LessonContentViewModel` (state machine: stage-by-stage, item-by-item, 推进 + 完成判定) | `LessonContentViewModel.kt` (新) |
| PM | 路由 `LESSON` 接 4 个 nav args (`courseId`, `sectionId`, `unitId`, `lessonId`) | `Route.kt`, `AppNavigation.kt` |
| PM | 5 个 body 单元测试 (state machine 推进 + 边界) | — |
| 验证 | 75-83 个测试全过 | — |

### Day 11 — 集成测试 + bug fixing

| 时段 | 工作项 |
|---|---|
| AM | 跑全测试套件：`.gradlew :app:testDebugUnitTest`；记录任何失败 |
| AM | 跑构建：`.gradlew :app:assembleDebug`；fix 任何编译/链接错误 |
| PM | 装到模拟器/真机：spash → onboarding → 选 swahili → course tree → 5 种 lesson 各跑一遍 |
| PM | 修复 device smoke test 暴露的 bug (按优先级) |
| PM | 更新 `README.md` 反映新架构 + 5 lesson type 示例 |
| 验收 | 全部测试 + 5 种 lesson 端到端可玩 + `assembleDebug` 通过 |

### 风险缓冲

如果某天延误：
- Day 1-3 已 shippable（不依赖 lesson 重构）→ 可先 merge
- Day 4-6 重型阶段；如遇 P4a 解析问题，可拆为 2 个 PR（P4a-types / P4a-parser）
- Day 9-10 是 UI 重头，可用 Compose preview 工具减少设备调试时间

### 并行化建议（如果人手 ≥ 2）

- Dev A: Day 1-7 (后端 + 模型 + parser + Room)
- Dev B: Day 8-10 (UI + 渲染器 + 屏)
- Day 11: 共同集成测试

但需要提前对齐 `Interaction` 数据类签名（Day 1 完成）和 `LessonContent` sealed 结构（Day 4 完成）后再分头。

