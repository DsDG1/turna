# 03. 领域层（Domain Layer）

> 路径：`lib/domain/`
>
> 领域层定义核心数据模型（`@freezed`）和 Repository 接口，**不依赖**任何 Flutter UI、Drift 数据库细节或第三方实现。下层 `data/` 实现这些接口，向上提供数据。

---

## 3.1 课程模型层次

课程模型采用 **6 级层次结构**，每一级都是一个独立 Freezed 数据类：

```
Section          ← 顶层分组（如 "A1 Basics"）
  └─ Unit        ← 中层分组（如 "Greetings"）
       └─ Lesson ← 一节课
            └─ LessonContent ← 课的内容体
                 ├─ stages        (legacy / review / mastery / reading)
                 ├─ subLessons    (intro / practice)
                 ├─ listeningPhases (listening)
                 └─ readingPassage (reading)
                       └─ Stage    ← 一组 Interaction
                            └─ Interaction ← 一道题（13 种题型之一）
```

完整层级树：

```
Section (e.g., "Section 1 — A1 Basics")
└── Unit (e.g., "Unit 1 — Greetings")
    └── Lesson (e.g., "s1-l2 — Greetings")
        └── LessonContent
            └── Stage (e.g., "stage-intro")
                └── Interaction (e.g., MultipleChoice, FillBlank, ...)
```

---

## 3.2 核心数据类一览

| 类 | 文件 | 说明 |
|---|---|---|
| [`Section`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/section.dart) | [`section.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/section.dart) | 顶层课程分组，含 CEFR level + 前置依赖 |
| [`Unit`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/unit.dart) | [`unit.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/unit.dart) | 中层分组，含前置 Unit 依赖 |
| [`Lesson`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/lesson.dart) | [`lesson.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/lesson.dart) | 一节课，含 `LessonType` 与 `LessonTemplate` |
| [`LessonContent`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/lesson_content.dart) | [`lesson_content.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/lesson_content.dart) | 课的内容体（联合型结构） |
| [`Stage`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/stage.dart) | [`stage.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/stage.dart) | 一组 Interaction |
| [`SubLesson`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/sub_lesson.dart) | [`sub_lesson.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/sub_lesson.dart) | intro/practice 课的子课 |
| [`ListeningPhase`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/listening_phase.dart) | [`listening_phase.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/listening_phase.dart) | 听力课的三段式（wordPairing/dialogue/summary） |
| [`ReadingPassage`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/reading_passage.dart) | [`reading_passage.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/reading_passage.dart) | 阅读课的结构化篇章 |
| [`Interaction`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/interaction.dart) | [`interaction.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/interaction.dart) | **sealed union**：13 种题型 |
| [`WordEntry`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/word_entry.dart) | [`word_entry.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/word_entry.dart) | 全局词汇池 |
| [`Expression`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/expression.dart) | [`expression.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/expression.dart) | 多词表达/短语 |
| [`GrammarPoint`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/grammar_point.dart) | [`grammar_point.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/grammar_point.dart) | 语法点（含解释 + practice items） |
| [`SrsWord`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/srs_word.dart) | [`srs_word.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/srs_word.dart) | 间隔重复状态（FSRS + SM-2 字段） |
| [`LessonWordLink`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/lesson_word_link.dart) | [`lesson_word_link.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/lesson_word_link.dart) | 词汇/表达首次出现的 Lesson 链接 |
| [`MistakeEntry`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/mistake_entry.dart) | [`mistake_entry.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/mistake_entry.dart) | 错题记录（含原始 Interaction 快照） |

---

## 3.3 Section — 顶层课程分组

[`Section`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/section.dart) 代表一个完整的课程分段，对应一个 CEFR 等级或一组相关单元。

```dart
@freezed
abstract class Section with _$Section {
  const factory Section({
    required String id,
    required String name,
    @Default('') String description,
    String? level,                                  // 'A1' | 'A2' | 'B1' | 'B2'
    @Default(<String>[]) List<String> prerequisiteSectionIds,
    required List<Unit> units,
  }) = _Section;

  factory Section.fromJson(Map<String, dynamic> json) =>
      _$SectionFromJson(json);
}
```

**关键字段**：
- `level`：CEFR 等级（`A1` / `A2` / `B1` / `B2`）；为空表示未知
- `prerequisiteSectionIds`：解锁本 Section 所需的前置 Section id 列表
- `units`：当前 Section 包含的 Unit 列表（`sectionShells()` 返回时为空）

---

## 3.4 Unit — 中层分组

[`Unit`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/unit.dart) 是 Section 内的语义主题分组（如 "Greetings"）。

```dart
@freezed
abstract class Unit with _$Unit {
  const factory Unit({
    required String id,
    required String name,
    @Default('') String description,
    @Default(<String>[]) List<String> prerequisiteUnitIds,
    required List<Lesson> lessons,
  }) = _Unit;

  factory Unit.fromJson(Map<String, dynamic> json) => _$UnitFromJson(json);
}
```

---

## 3.5 Lesson — 一节课

[`Lesson`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/lesson.dart) 是学习的最小可执行单元，由类型（`LessonType`，仅展示用）和模板（`LessonTemplate`，决定内容形状）共同决定渲染。

```dart
enum LessonType {
  normal, listening, reading, review, challenge,
}

enum LessonTemplate {
  intro, listening, practice, reading, review, mastery, legacy,
}

@freezed
abstract class Lesson with _$Lesson {
  const factory Lesson({
    required String id,
    required String name,
    @Default('') String description,
    @Default(LessonType.normal) LessonType type,           // 展示用
    @Default(LessonTemplate.legacy) LessonTemplate template, // 决定内容
    @Default(<String>[]) List<String> prerequisiteLessonIds,
    required LessonContent content,
  }) = _Lesson;

  /// 渲染器可直接遍历的扁平 Stage 列表
  List<Stage> get flattenedStages;
}
```

### 3.5.1 `LessonType` vs `LessonTemplate`

| 维度 | `LessonType` | `LessonTemplate` |
|---|---|---|
| 用途 | 课程树图标/颜色 | 内容形状 + 渲染策略 |
| 取值 | 5 种（normal/listening/reading/review/challenge） | 7 种（含 `legacy`） |
| 影响 | 仅 UI 展示 | 决定 `flattenedStages` 怎么算 |

### 3.5.2 `flattenedStages`

将模板特定的内容形状展平为渲染器可遍历的 `List<Stage>`：

| `template` | `flattenedStages` 来源 |
|---|---|
| `legacy` / `normal` / `review` / `mastery` | `content.stages` |
| `intro` / `practice` | 展平 `content.subLessons[*].stages`，id 加上 `sub-` 前缀 |
| `listening` | 展平 `content.listeningPhases`，id 加上 `lp-` 前缀 |
| `reading` | `content.stages`（passage 单独渲染） |

---

## 3.6 LessonContent — 联合型内容体

[`LessonContent`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/lesson_content.dart) 是一个联合型结构，不同模板使用不同字段：

```dart
@freezed
abstract class LessonContent with _$LessonContent {
  const factory LessonContent({
    @Default(<Stage>[]) List<Stage> stages,             // legacy/review/mastery/reading
    @Default(<SubLesson>[]) List<SubLesson> subLessons, // intro/practice
    @Default(<ListeningPhase>[]) List<ListeningPhase> listeningPhases, // listening
    ReadingPassage? readingPassage,                     // reading
    @Default('') String passage,                        // legacy compat
    String? audioAsset,                                 // legacy single-audio
    @Default(<String>[]) List<String> linkedGrammarPointIds,
  }) = _LessonContent;
}
```

不同字段可以并存（向前兼容），但每个 template 只用其对应字段。

---

## 3.7 Interaction — 13 种题型 sealed union

[`Interaction`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/interaction.dart) 是 **sealed union**，每种题型是一个独立 factory。

> ⚠️ **关键**：`@Freezed(fromJson: true, toJson: true)` 必须显式声明，因为 freezed 2.x 仅在 `fromJson` factory 表达式体时自动开启 JSON。`Interaction.fromJson` 用 try/catch 兜底未知 `runtimeType` → 哨兵 ShowWord，避免崩溃。

```dart
@Freezed(fromJson: true, toJson: true)
sealed class Interaction with _$Interaction {
  /// 1. showWord — 形式 + 意义 + 音频
  const factory Interaction.showWord({
    @Default('') String id,
    required String wordId,
    String? context,
    String? grammarPointId,
    String? expressionId,
  }) = ShowWord;

  /// 2. multipleChoice — 单选
  const factory Interaction.multipleChoice({
    @Default('') String id,
    required String prompt,
    required List<String> options,
    required int correctIndex,
    String? imageAsset,
    @Default(<String>[]) List<String> audioAssets,
    String? grammarPointId,
  }) = MultipleChoice;

  /// 3. multiSelect — 多选
  const factory Interaction.multiSelect({
    @Default('') String id,
    required String prompt,
    required List<String> options,
    required List<int> correctIndices,
    @Default(1) int minSelections,
    @Default(2147483647) int maxSelections,
    String? imageAsset,
    String? grammarPointId,
  }) = MultiSelect;

  /// 4. fillBlank — 完形填空
  const factory Interaction.fillBlank({
    @Default('') String id,
    required String sentence,
    required String answer,
    String? hint,
    @Default(<String>[]) List<String> audioAssets,
    @Default(<String>[]) List<String> imageAssets,
    String? grammarPointId,
  }) = FillBlank;

  /// 5. translateSentence — 翻译句子
  const factory Interaction.translateSentence({
    @Default('') String id,
    required String source,
    required String expected,
    @Default(<String>[]) List<String> hints,
    String? grammarPointId,
  }) = TranslateSentence;

  /// 6. listenAndPick — 听后选择
  const factory Interaction.listenAndPick({
    @Default('') String id,
    required String audioAsset,
    required String prompt,
    required List<String> options,
    required int correctIndex,
    String? grammarPointId,
  }) = ListenAndPick;

  /// 7. typeTheWord — 听音拼写
  const factory Interaction.typeTheWord({
    @Default('') String id,
    required String audioAsset,
    required String prompt,
    required String expected,
    String? grammarPointId,
  }) = TypeTheWord;

  /// 8. listenOnly — 纯听输入（不评分）
  const factory Interaction.listenOnly({
    @Default('') String id,
    String? audioAsset,
    @Default('') String transcript,
    @Default('Listen to the summary') String prompt,
    String? grammarPointId,
  }) = ListenOnly;

  /// 9. reorderSentence — 乱序组句
  const factory Interaction.reorderSentence({
    @Default('') String id,
    required List<String> scrambled,
    required List<String> correct,
    String? grammarPointId,
  }) = ReorderSentence;

  /// 10. readingMcq — 阅读单选
  const factory Interaction.readingMcq({...}) = ReadingMcq;

  /// 11. readingTrueFalse — 阅读判断
  const factory Interaction.readingTrueFalse({...}) = ReadingTrueFalse;

  /// 12. readingShortAnswer — 阅读简答
  const factory Interaction.readingShortAnswer({...}) = ReadingShortAnswer;

  /// 13. ankiCard — Anki 翻卡（无语言语义）
  const factory Interaction.ankiCard({
    @Default('') String id,
    required String front,
    required String back,
    @Default(<String>[]) List<String> audioAssets,
    @Default(<String>[]) List<String> imageAssets,
    String? hint,
    String? sourceNoteId,
  }) = AnkiCard;
}
```

**通用字段**：
- `id`：每道题稳定 id，用于追踪状态；空时 fallback 为 `legacy-$index`
- `grammarPointId`：错题 → 语法复习 跨路由
- `audioAssets` / `imageAssets`：可选提示侧媒体（如 `anki://<importId>/<file>` 引用 Anki deck 资源）

**每种题型对应一个 Renderer**，通过 GetIt 注册到 [`renderer_module.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/di/renderer_module.dart)，详见 [06-views-layer.md](./06-views-layer.md)。

---

## 3.8 WordEntry — 全局词汇池

[`WordEntry`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/word_entry.dart) 是与 Lesson **解耦**的全局词汇条目。`showWord` interaction 通过 `wordId` 引用：

```dart
@freezed
abstract class WordEntry with _$WordEntry {
  const factory WordEntry({
    required String id,
    required String term,
    required String translation,
    String? pronunciation,
    String? audioAsset,
    @Default(<String>[]) List<String> tags,
  }) = _WordEntry;
}
```

---

## 3.9 Expression — 多词表达

[`Expression`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/expression.dart) 是多词表达/短语，与 WordEntry 分离，因为：
- 独立的 SRS 状态
- 独立的首次出现 Lesson 链接
- 独立的 TTS 播放

```dart
@freezed
abstract class Expression with _$Expression {
  const factory Expression({
    required String id,
    required String term,
    required String translation,
    String? pronunciation,
    String? audioAsset,
    @Default(<String>[]) List<String> tags,
  }) = _Expression;
}
```

---

## 3.10 GrammarPoint — 语法点

[`GrammarPoint`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/grammar_point.dart) 可以独立进入 SRS 复习队列，并与 Expression / Sentence 关联：

```dart
@freezed
abstract class GrammarPoint with _$GrammarPoint {
  const factory GrammarPoint({
    required String id,
    required String title,
    @Default('') String explanation,
    @Default(<String>[]) List<String> exampleExpressionIds,
    @Default(<String>[]) List<String> exampleSentenceIds,
    @Default(<Interaction>[]) List<Interaction> practiceItems,
  }) = _GrammarPoint;
}
```

`practiceItems` 是 JSON 序列化时通过自定义 `_practiceItemsFromJson` 解析为 `List<Interaction>`。

---

## 3.11 SrsWord — 间隔重复状态

[`SrsWord`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/srs_word.dart) 是单词或表达式的 SRS 状态。

```dart
enum SrsItemType { word, expression }

@freezed
abstract class SrsWord with _$SrsWord {
  const factory SrsWord({
    required String wordId,
    required DateTime dueAt,
    @Default(1) int intervalDays,        // SM-2 兼容字段
    @Default(2.5) double ease,            // SM-2 兼容字段
    @Default(0) int reps,                 // 累计成功复习次数（lapse 不重置）
    @Default(0) int lapses,
    @Default(false) bool isLeech,
    @Default(SrsItemType.word) SrsItemType type,
    DateTime? lastReviewedAt,             // 最近一次复习时间
    double? stability,                    // FSRS S（单位：天）
    double? difficulty,                   // FSRS D ∈ [1, 10]
    @Default(1) int fsrsState,            // 1=learning 2=review 3=relearning
    int? learningStep,                    // FSRS learning/relearning step index
  }) = _SrsWord;

  factory SrsWord.fresh(String wordId) => SrsWord(
        wordId: wordId,
        dueAt: DateTime.now(),
      );
}
```

**Mastery 不是离散阶段**：UI 应使用 retrievability / mastery 分数，而不是"通过第几关"。

---

## 3.12 LessonWordLink — 词汇/表达首次出现链接

[`LessonWordLink`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/lesson_word_link.dart) 记录一个 wordId/expressionId 首次出现在哪个 Lesson，便于 SRS 闪卡显示 "Learned in: <lesson>"：

```dart
enum LinkType { word, expression }

@freezed
abstract class LessonWordLink with _$LessonWordLink {
  const factory LessonWordLink({
    required String id,           // wordId or expressionId
    required String lessonId,
    required String lessonName,
    required LinkType type,
  }) = _LessonWordLink;
}
```

由 [`LessonLinkStore`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/lesson_link_store.dart) 在内存中查询。

---

## 3.13 MistakeEntry — 错题记录

[`MistakeEntry`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/mistake_entry.dart) 包含完整的原始 Interaction 快照，重做时无需再查 lesson/stage：

```dart
@freezed
abstract class MistakeEntry with _$MistakeEntry {
  const factory MistakeEntry({
    required String id,
    required String lessonId,
    required String stageId,
    required String interactionId,
    String? wordId,
    String? expressionId,
    String? grammarPointId,                  // → grammar review 跨路由
    Interaction? interactionSnapshot,        // JSON 序列化的 Interaction
    @Default('') String userAnswer,
    @Default('') String correctAnswer,
    required DateTime timestamp,
    @Default(0) int rewriteCount,            // 已正确重做次数
  }) = _MistakeEntry;
}
```

---

## 3.14 ListeningPhase — 听力三段式

[`ListeningPhase`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/listening_phase.dart)：

```dart
enum ListeningPhaseType {
  wordPairing,   // Phase 1: TL 音频 ↔ 英文释义
  dialogue,      // Phase 2: 对话 + 理解题
  summary,       // Phase 3: 总结音频，不出题
}

@freezed
abstract class ListeningPhase with _$ListeningPhase {
  const factory ListeningPhase({
    required String id,
    required String name,
    @Default(ListeningPhaseType.dialogue) ListeningPhaseType type,
    String? audioAsset,
    @Default('') String transcript,
    @Default(<Interaction>[]) List<Interaction> items,
  }) = _ListeningPhase;
}
```

---

## 3.15 ReadingPassage — 阅读篇章

[`ReadingPassage`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/course/reading_passage.dart)：

```dart
@freezed
abstract class ReadingPassage with _$ReadingPassage {
  const factory ReadingPassage({
    required String title,
    @Default(<String>[]) List<String> paragraphs,
    @Default(1) int difficulty,              // 1=A1, 2=A2, 3=B1, 4=B2
    @Default(<String>[]) List<String> linkedWordIds,
    @Default(<String>[]) List<String> linkedExpressionIds,
  }) = _ReadingPassage;
}
```

---

## 3.16 音频抽象（audio/）

[`lib/domain/audio/`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/audio/) 抽象音频解析，让课程内容与具体播放实现解耦：

| 文件 | 作用 |
|---|---|
| [`vocab_audio_resolver.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/audio/vocab_audio_resolver.dart) | 根据 wordId / term 解析播放音频（预录 asset 或 TTS fallback） |
| [`anki_audio_resolver.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/audio/anki_audio_resolver.dart) | Anki deck 导入音频的专用解析器，处理 `anki://<importId>/<file>` 协议 |

---

## 3.17 Repository 接口（repositories/）

[`lib/domain/repositories/`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/repositories/) 定义两个核心抽象：

### 3.17.1 ICourseRepository

[`i_course_repository.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/repositories/i_course_repository.dart) 课程内容读取 API：

```dart
abstract class ICourseRepository {
  // 三级加载（L0/L1/L2）—— 为 ~10k lessons 优化
  Future<List<Section>> sectionShells();             // L0: 仅 section 元数据
  Future<Section> section(String id);                // L1: section 树（units/lessons 元数据，content 为空）
  Future<Lesson> lessonById(String id);              // L2: 完整 LessonContent

  Future<String?> sectionIdForUnit(String unitId);
  Future<String?> sectionIdForLesson(String lessonId);

  Future<List<WordEntry>> vocabulary();
  Future<List<GrammarPoint>> grammarPoints();
  Future<GrammarPoint?> grammarPointById(String id);
  Future<List<Expression>> expressions();
  Future<Expression?> expressionById(String id);

  // Bulk write（Anki 导入）
  Future<void> bulkInsertCourseTree(Section section);
  Future<void> bulkInsertVocabulary(List<WordEntry> words);
  Future<int> deleteByTag(String tag);
  Future<void> deleteSection(String sectionId);

  Future<List<db.AnkiImport>> ankiImports();
}
```

### 3.17.2 IStudyLogRepository

[`i_study_log_repository.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/repositories/i_study_log_repository.dart) 学习活动日志：

```dart
abstract class IStudyLogRepository {
  Future<void> appendLog(StudyLog log);
  Future<List<StudyLog>> readLogs({
    DateTime? since,
    DateTime? until,
    StudyActivityType? type,
  });
  Future<Map<String, DailyStudyStats>> readAllDailyStats();
  Future<List<DailyStudyStats>> readLastNDays(int n);
  Future<void> clearAll();
}
```

---

## 3.18 学习/认证模型（study/, auth/）

| 文件 | 内容 |
|---|---|
| [`domain/study/study_log.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/study/study_log.dart) | 单次学习活动记录（含 `StudyActivityType` 枚举） |
| [`domain/study/daily_stats.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/study/daily_stats.dart) | 按日聚合的学习统计 |
| [`domain/auth/local_user.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/auth/local_user.dart) | 本地用户模型（替代云端登录） |
| [`domain/achievement.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/achievement.dart) | 成就定义 |
| [`domain/game/user_game_state.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/game/user_game_state.dart) | 用户游戏状态（XP / 宝石 / 连胜等） |