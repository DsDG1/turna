# Anki 课程与复习大一统实施计划

> 文档状态：施工中（P0–P5 合同、ACK、一卡一 presentation、introduction/queue、StudySessionController 已落地）  
> 编写日期：2026-08-20  
> 适用范围：Anki 导入、课程投影、课程学习、正式复习、卡片渲染、调度、历史、统计、撤销、重新导入与旧数据迁移  
> 核心目标：以课程为产品主线，让同一张 Anki 卡在课程与复习中拥有唯一身份、唯一题型、唯一学习状态和唯一调度写入者。

---

## 0. 执行摘要

当前 Anki 功能不是简单存在两个不同页面，而是同一个 `.apkg/.colpkg` 在应用内形成了多套业务事实：

- 导入流程先生成 Legacy 课程树和 Turna SRS，再可能同步到 Official Anki collection；
- 课程页面读取 CourseDatabase 中的 Interaction 投影，正式复习可能读取 Official scheduler；
- 同一张源卡可能被投影成 Flip、MultipleChoice、ListenPick、TypeAnswer 等多个正式课程项；
- 正式复习队列只看 scheduler due，不可靠地检查卡片是否已在课程中学习；
- 课程和复习可能在不同时间、用不同分类器把同一张卡识别成不同题型；
- 普通词汇卡、HTML 卡和 Official practice surface 分别维护翻面、显示答案和提交状态；
- Official practice surface 的答案呈现依赖未挂载 renderer 产生 ACK，存在“显示答案不可点击”的状态死锁；
- 最近的统一工作主要完成了二元结果、部分 ledger 和部分页面外壳，尚未统一卡片身份、课程资格、presentation、导入所有权和正式会话。

本计划的目标架构不是把所有数据粗暴塞入同一张表，而是建立清晰的唯一事实边界：

```text
Canonical Anki Store
  └─ 唯一源卡身份、Note/Card/Template/媒体

Course Domain
  └─ 唯一课程位置、学习顺序、presentation、是否已学

Study Session
  └─ 课程学习、正式复习、自由练习、预览共用卡片状态机和 renderer

Source-owned Ledger
  ├─ Official Anki Scheduler：官方卡排期唯一事实
  └─ Turna FSRS：内置课程和 Legacy 迁移期卡排期唯一事实
```

最终产品合同：

```text
一张 canonical card
  = 一个稳定 CardKey
  = 一个 active CoursePlacement
  = 一个 active Presentation
  = 一个 IntroductionState
  = 一个 Ledger Owner

正式复习资格
  = scheduler due
  ∩ 当前课程包含
  ∩ 已在课程中 introduced
  ∩ 未暂停/未退休
```

---

## 1. 产品原则与不可动摇的决策

### 1.1 “以课程为准”的准确含义

课程是以下内容的唯一产品真相：

1. 用户当前选择了哪门 Anki 课程；
2. 卡片位于哪个 Section、Unit、Lesson；
3. 用户按什么顺序第一次接触卡片；
4. 卡片是否已经在课程内真正学习；
5. 同一张卡使用选择题、填空、听力、翻面或原模板中的哪一种 presentation；
6. 哪些卡允许进入正式复习；
7. 课程完成、解锁和课程奖励如何计算。

课程不负责自行重写 Official Anki 的调度算法。Official collection/scheduler 仍是官方卡到期时间、队列、撤销和 revlog 的唯一事实来源。否则所谓统一会退化成另一种双写。

### 1.2 一张卡只有一个正式课程形态

同一个 `cardId` 在一门课程中只能有一个 active presentation：

- 真正的选择题使用课程选择题；
- 真正的多选题使用课程多选题；
- Cloze 使用课程填空题；
- 明确的听力题使用课程听力题；
- 普通单词/释义卡使用 Anki 翻面卡；
- 复杂模板使用 Fidelity 翻面卡；
- 置信度不足时选择 Flip/Fidelity，不自动伪造客观题。

从同一张卡派生出的额外练习只能是 optional drill，不得成为第二张正式课程卡，不得拥有独立课程进度和正式调度状态。

### 1.3 Note 与 Card 不可混淆

- `noteId` 表示一条 Anki Note；
- `cardId` 表示由 Note + Template Ord 生成的具体卡；
- 一个 Note 的正向卡和反向卡可能拥有两个不同 `cardId`；
- 去重必须以 canonical `cardId` 为主，不得按 `noteId` 把合法反向卡删除；
- 更新迁移可以使用 `noteGuid + templateOrd` 辅助匹配，但运行时身份仍必须是 CardKey。

### 1.4 统一结果，不强制统一交互形态

领域层统一为：

```dart
enum RecallOutcome {
  forgotten,
  remembered,
}
```

但用户交互按题型不同：

| Presentation | 用户操作 | 标准结果 |
| --- | --- | --- |
| MultipleChoice | 选对 | remembered |
| MultipleChoice | 选错 | forgotten |
| MultiSelect | 完全正确 | remembered |
| MultiSelect | 部分/错误 | forgotten |
| FillBlank/TypeAnswer | 正确 | remembered |
| FillBlank/TypeAnswer | 错误 | forgotten |
| Flip/Fidelity | 显示答案后点“记得” | remembered |
| Flip/Fidelity | 显示答案后点“不记得” | forgotten |

不要求选择题答完后再多问一次“记得/不记得”。统一的是最终 outcome、写入和统计，而不是让所有卡都变成相同按钮。

### 1.5 一次作答只有一个写入者

硬约束：

- Official-owned 卡只写 Official ledger；
- Turna-owned 卡只写 Turna ledger；
- Official 写入失败不得回退 Turna；
- 课程模式、复习模式都必须在会话开始前解析唯一 ledger owner；
- 一次提交拥有唯一 idempotency key；
- UI 只有拿到 ledger receipt 后才能推进为成功；
- 撤销必须按 receipt 精确撤销。

### 1.6 模式必须显式

统一定义：

```dart
enum StudyMode {
  learn,
  review,
  practice,
  preview,
}
```

- `learn`：课程首次学习；完成卡片后标记 introduced，并初始化/写入排期；
- `review`：只处理 due 且 introduced 的卡，正式写入排期；
- `practice`：已经学过后的自由练习，不改变正式排期；
- `preview`：浏览器/管理页预览，不写进度、不写排期。

页面不得通过路由名称、ID 前缀或是否存在 Lesson 来猜模式。

---

## 2. 当前系统现状与根因

### 2.1 导入双写

当前导入流程大致为：

```text
AnkiImportPage
  1. AnkiImporter.parse
  2. AnkiDeckAssembler.assemble
     └─ CourseDatabase / NoteStore / Interaction 投影
  3. AnkiSrsMigrator.migrate
     └─ Turna SRS
  4. 可选 OfficialAnkiImportFacade.importOfficialOrNull
     └─ Official collection / Official scheduler
```

这意味着 Official 路由开启时，一个导入同时存在：

- Legacy course projection；
- Legacy NoteStore；
- Turna SRS 卡；
- Official source catalog；
- Official collection card；
- Official scheduler 状态；
- Legacy import 与 Official source 的 migration link。

这不是缓存，而是多套可以独立变化的业务事实。

### 2.2 课程投影一对多

当前 Official projection 对 vocab classification 可能返回多个 kind：

```text
vocab card
├─ flip
├─ multipleChoice
├─ listenPick
└─ typeAnswer
```

`OfficialAnkiCourseProjectionStore` 会把每个 projected item 都写入 Lesson JSON 和 projection index，因此同一 `cardId` 在课程中会表现为两张或更多卡。

这类重复不是 SQL 插入偶发重复，而是产品策略主动制造的一卡多题。

### 2.3 课程与复习分类不一致

课程投影可能使用：

- mapping suggestion；
- projection payload classifier；
- sibling answer pool；
- import-time template/field mapping。

Official review practice surface 又会根据当前 question/answer HTML 在运行时重新调用 classifier。两次输入、版本和上下文不同，因此同一张卡可能出现：

- 课程中是 MultipleChoice，复习中是 Flip；
- 课程中有三个干扰项，复习中选项不同；
- 课程中是词汇卡，复习中被判断为 Fidelity；
- 重新导入后课程 presentation 已更新，但复习仍按另一路径分类。

### 2.4 正式复习不检查课程学习资格

Legacy review 主要按以下条件收集：

```text
wordId 是 Anki
&& !suspended
&& !buried
&& dueAt <= now
```

Official review 直接从 Official scheduler 获取队列。两者都没有稳定地与“课程中是否已学”做交集。

因此新导入后，即使用户从未进入课程，scheduler 中的 New Card 仍可能出现在正式复习入口。

### 2.5 Official 课程作答与 Official 排期脱节

课程 LessonViewModel 会显式跳过 `official-anki-` ID，不写 Turna SRS；Official course grade bridge 又不是课程主路径的强制依赖。

结果是：

- 用户完成了课程题目；
- 课程进度可能增加；
- Official scheduler 未必收到首次学习结果；
- Official review 仍将其视为未处理的 New Card；
- 或相反，Official review 已复习，但课程仍显示未学。

### 2.6 UnifiedReviewPage 仍会压平结构化题型

当前 `ReviewItem` 的标准内容可附带 `Interaction`，但统一页只读取 front/back 文本并交给普通卡片正文，不调用课程 `InteractionRenderer`。

这使选择题、多选、填空和听力失去原课程交互，退化为翻面卡。

### 2.7 Official practice surface 的答案 ACK 死锁

当前 Formal Official Review 默认尝试显示 practice surface，但显示答案的可用条件要求 presenter 已收到 question-present ACK。真正产生 ACK 的 Official reviewer view 在 practice surface 模式下没有挂载，形成：

```text
practice surface 可见
→ official renderer 不可见/未挂载
→ question ACK 不产生
→ Show Answer disabled
→ 点击卡面也被相同 guard 拒绝
→ 永远不能进入 answer phase
```

### 2.8 现有“统一完成”定义过早

现有统一文档主要把以下内容标记为完成：

- 二元评分；
- Turna/Official ledger adapter；
- 部分 ReviewProgressHeader/Completion 外壳；
- 通用 SRS 排除 Anki；
- 部分真实 due 计算。

但以下核心仍未完成：

- Official formal review 没有真正使用同一个 UnifiedReviewPage/Controller；
- 课程与复习没有共享 Presentation；
- ReviewItem 无法原生承载结构化 Interaction 会话；
- 导入仍双写；
- 课程学习状态没有成为 review eligibility；
- 一卡多投影仍是明确行为；
- Legacy 与 Official 仍可同时存在。

---

## 3. 目标领域模型

### 3.1 CanonicalCardKey

```dart
enum AnkiBackendKind {
  official,
  localCanonical,
  legacyTurna,
}

class CanonicalCardKey {
  final AnkiBackendKind backend;
  final String profileId;
  final String sourceId;
  final int cardId;
}
```

约束：

- UI、session、renderer 不允许从 `rawId.startsWith()` 推断 backend；
- 所有旧字符串 ID 只在 migration/adapter 边界解析一次；
- `sourceId` 与用户展示的 courseId/importId 分离；
- `cardId` 必须是源卡 ID，不能使用 projection item ID 替代。

### 3.2 CanonicalCard

```dart
class CanonicalCard {
  final CanonicalCardKey key;
  final int noteId;
  final String noteGuid;
  final int templateOrd;
  final int deckId;
  final String sourceFingerprint;
  final CanonicalTemplateRef template;
  final List<CanonicalFieldValue> fields;
  final List<CanonicalMediaRef> media;
  final CanonicalSchedulingSnapshot? importedScheduling;
}
```

CanonicalCard 不直接保存课程题型；题型属于 CoursePresentation。

### 3.3 CourseCardPlacement

```dart
class CourseCardPlacement {
  final String placementId;
  final String courseId;
  final CanonicalCardKey cardKey;
  final String sectionId;
  final String unitId;
  final String lessonId;
  final int order;
  final bool active;
  final int projectionVersion;
}
```

约束：

```text
UNIQUE(course_id, source_id, card_id) WHERE active = 1
```

### 3.4 CardPresentation

```dart
enum CardPresentationKind {
  multipleChoice,
  multiSelect,
  fillBlank,
  listenAndPick,
  typeAnswer,
  flip,
  fidelity,
}

sealed class CardPresentation {
  CanonicalCardKey get cardKey;
  CardPresentationKind get kind;
  String get sourceFingerprint;
  int get classifierVersion;
  int get mappingVersion;
}

class StructuredCardPresentation extends CardPresentation {
  final Interaction interaction;
}

class FlipCardPresentation extends CardPresentation {
  final String frontText;
  final String backText;
  final String? pronunciation;
  final String? hint;
  final List<CanonicalMediaRef> media;
}

class FidelityCardPresentation extends CardPresentation {
  final CanonicalTemplateRef templateRef;
}
```

每个 active placement 只有一个 active presentation。

### 3.5 CardIntroductionState

```dart
enum CardIntroductionStatus {
  unintroduced,
  introduced,
  retired,
}

enum CardIntroducedBy {
  course,
  importedHistory,
  migration,
  manual,
}

class CardIntroductionState {
  final String courseId;
  final CanonicalCardKey cardKey;
  final CardIntroductionStatus status;
  final CardIntroducedBy? introducedBy;
  final DateTime? introducedAt;
  final String? firstLessonId;
  final DateTime? lastStudiedAt;
}
```

### 3.6 StudyItem

```dart
class StudyItem {
  final String sessionItemId;
  final String courseId;
  final String placementId;
  final CanonicalCardKey cardKey;
  final CardPresentation presentation;
  final StudyMode mode;
  final StudyLedgerOwner ledgerOwner;
  final StudyCapabilities capabilities;
}
```

StudyItem 不携带裸 `int quality`，也不使用 UI 字符串推断来源。

### 3.7 StudyEventReceipt

```dart
class StudyEventReceipt {
  final String eventId;
  final String idempotencyKey;
  final CanonicalCardKey cardKey;
  final StudyLedgerOwner ledgerOwner;
  final RecallOutcome outcome;
  final DateTime reviewedAt;
  final DateTime? nextDueAt;
  final Object? nativeUndoToken;
  final Object? previousSnapshot;
}
```

所有错题、统计、奖励、撤销投影都必须引用同一个 `eventId`。

---

## 4. 目标存储设计

实际表名可按 Drift 规范调整，但职责必须保留。

### 4.1 anki_course_sources

```text
course_id                PK
profile_id
source_id
backend_kind
display_name
source_hash
source_fingerprint
state                    staging/active/failed/archived
created_at
updated_at
```

唯一约束：

```text
UNIQUE(profile_id, source_id)
UNIQUE(profile_id, source_hash, course_id)  -- 同一课程重新导入识别
```

### 4.2 anki_course_card_placements

```text
placement_id             PK
course_id
profile_id
source_id
card_id
section_id
unit_id
lesson_id
display_order
active
projection_version
source_fingerprint
created_at
updated_at
```

关键唯一索引：

```text
UNIQUE(course_id, source_id, card_id) WHERE active = 1
```

### 4.3 anki_card_presentations

```text
course_id
source_id
card_id
presentation_kind
payload_json
status                    candidate/active/stale/rejected
mapping_version
classifier_version
source_fingerprint
user_confirmed
updated_at
```

关键唯一索引：

```text
UNIQUE(course_id, source_id, card_id) WHERE status = 'active'
```

候选 presentation 可以有多个，但 active 只能有一个。

### 4.4 anki_card_introduction_states

```text
course_id
source_id
card_id
status
introduced_by
introduced_at
first_lesson_id
last_studied_at
version
```

主键：

```text
(course_id, source_id, card_id)
```

### 4.5 study_product_events

该表不是 Official revlog 的第二份调度真相，只是产品统一投影和幂等记录。

```text
event_id                  PK
idempotency_key           UNIQUE
course_id
source_id
card_id
ledger_owner
mode
outcome
native_event_ref
reviewed_at
next_due_at
session_id
undone_at
effects_state
```

### 4.6 anki_import_jobs

用于跨 CourseDatabase 与 Official collection 的 saga：

```text
job_id                    PK
course_id
source_path
source_hash
state
canonical_commit_ref
expected_card_count
canonical_card_count
placement_count
active_presentation_count
introduced_count
error_code
error_detail
retry_count
created_at
updated_at
```

状态：

```text
created
parsing
canonicalStaging
canonicalCommitted
mapping
placementStaging
placementCommitted
scheduleLinked
validating
complete
failedRecoverable
failedFatal
cancelled
```

---

## 5. 统一 Repository 与服务边界

### 5.1 CanonicalAnkiRepository

```dart
abstract interface class CanonicalAnkiRepository {
  Future<CanonicalSource> importPackage(ImportPackageRequest request);
  Future<CanonicalSource?> sourceById(String profileId, String sourceId);
  Future<List<CanonicalCardKey>> cardKeysForSource(String sourceId);
  Future<CanonicalCard> loadCard(CanonicalCardKey key);
  Future<List<CanonicalCard>> loadCards(List<CanonicalCardKey> keys);
  Future<void> archiveSource(String sourceId);
}
```

实现：

- `OfficialCanonicalAnkiRepository`；
- `LocalCanonicalAnkiRepository`；
- `LegacyCanonicalAdapter`，仅用于迁移期读旧数据。

### 5.2 CourseCardRepository

```dart
abstract interface class CourseCardRepository {
  Future<List<CourseCardPlacement>> placementsForLesson(String lessonId);
  Future<CourseCardPlacement?> placementForCard(
    String courseId,
    CanonicalCardKey key,
  );
  Future<void> publishProjection(CourseProjectionGeneration generation);
  Future<void> archivePlacement(String placementId);
}
```

### 5.3 CardPresentationRepository

```dart
abstract interface class CardPresentationRepository {
  Future<CardPresentation> activePresentation(
    String courseId,
    CanonicalCardKey key,
  );
  Future<void> activateCandidate(PresentationCandidate candidate);
  Future<void> markStaleByFingerprint(String sourceId, String fingerprint);
}
```

### 5.4 CardIntroductionRepository

```dart
abstract interface class CardIntroductionRepository {
  Future<CardIntroductionState> stateFor(
    String courseId,
    CanonicalCardKey key,
  );
  Future<Set<CanonicalCardKey>> introducedKeys(String courseId);
  Future<void> markIntroduced(
    String courseId,
    CanonicalCardKey key, {
    required CardIntroducedBy by,
    required String lessonId,
  });
}
```

### 5.5 StudyLedger

```dart
abstract interface class StudyLedger {
  Future<DueSnapshot> dueSnapshot(StudyScope scope);
  Future<SchedulePreview> preview(
    CardSchedulingKey key,
    RecallOutcome outcome,
  );
  Future<StudyEventReceipt> commit(
    CardSchedulingKey key,
    RecallOutcome outcome, {
    required String idempotencyKey,
  });
  Future<bool> undo(StudyEventReceipt receipt);
}
```

### 5.6 StudyLedgerResolver

resolver 只接受强类型 owner：

```dart
StudyLedger resolve(StudyLedgerOwner owner);
```

禁止：

```dart
if (id.startsWith('official-anki-')) ...
if (id.startsWith('anki-')) ...
```

### 5.7 ReviewQueueRepository

```dart
abstract interface class ReviewQueueRepository {
  Future<ReviewQueueSnapshot> build({
    required String courseId,
    String? sectionId,
    String? lessonId,
    int limit = 20,
  });
}
```

内部流程：

```text
1. 读取课程 active placements
2. 读取 introduced key set
3. 按 ledger owner 分组
4. 各 ledger 获取 authoritative due
5. 与 active placements、introduced 求交集
6. 排除 suspended/buried/retired
7. 合并为稳定顺序
8. 批量加载 presentation
9. 返回 StudyItem
```

不得从全局 SRS state 扫描后再通过 ID 前缀临时拼装内容。

---

## 6. Presentation 判定规则

### 6.1 判定优先级

```text
用户确认的 mapping/presentation
  > 明确结构化契约
  > 高置信度官方分类
  > Flip
  > Fidelity fallback
```

### 6.2 MultipleChoice

只有满足以下条件才能生成：

- 源卡明确包含选项；或
- notetype mapping 明确声明 option fields；
- 能确定唯一正确答案；
- options 去重后不少于产品最小值；
- 正确答案确实存在于 options；
- 没有 conflicting answer key；
- projection fingerprint 稳定。

不得仅因为牌组中有其他词义可作为干扰项，就把普通词汇卡强制变成正式 MCQ。

### 6.3 MultiSelect

必须满足：

- 明确的多答案键；
- 正确索引不少于 2；
- 所有答案能一一映射到 options；
- 不存在重复/冲突键。

### 6.4 FillBlank/Cloze

必须保留 cloze ordinal 语义。不同 cloze ord 对应不同 `cardId` 时分别建立 placement，不得把整条 Note 的所有 cloze 合成一张卡。

### 6.5 ListenAndPick

必须存在可解析的音频引用，并且题面/答案方向明确。没有音频时降级 Flip，不生成假音频题。

### 6.6 Flip

普通词汇和表达的默认形态：

- front/back；
- 发音；
- 图片/音频；
- 点击卡面或按钮显示答案；
- 显示答案后出现“记得/不记得”；
- 可返回正面，但返回正面不提交结果。

### 6.7 Fidelity

适用：

- 复杂 HTML/CSS；
- JS 模板；
- MathJax；
- `{{FrontSide}}`、复杂条件模板；
- 结构化分类置信度不足；
- 用户要求保留原模板。

WebView 只负责卡片正文，不拥有会话进度、调度按钮和完成页。

---

## 7. 统一 Study Session

### 7.1 状态机

```dart
enum StudyCardPhase {
  idle,
  loadingQuestion,
  showingQuestion,
  collectingAnswer,
  revealingAnswer,
  showingAnswer,
  showingFeedback,
  committingOutcome,
  readyForNext,
  recoverableError,
  fatalError,
  completed,
}
```

### 7.2 StudySessionController 职责

```dart
class StudySessionController extends ChangeNotifier {
  Future<void> start();
  Future<void> submitObjectiveAnswer(Object answer);
  Future<void> revealAnswer();
  Future<void> submitRecall(RecallOutcome outcome);
  Future<void> continueNext();
  Future<bool> undoLast();
  Future<void> retryCurrent();
}
```

控制器负责：

- 加载当前 presentation；
- generation/token 管理；
- 防重复点击；
- 客观题校验；
- reveal；
- present ACK；
- outcome 归一化；
- ledger preview；
- ledger commit；
- introduction state；
- product event；
- 错题/统计 effects；
- receipt-based undo；
- 队列推进；
- 完成状态；
- 错误恢复。

控制器不负责：

- 课程 Section/Unit 解锁策略；
- 页面导航；
- 直接访问 DAO；
- 根据 ID 前缀判断 source；
- 在 renderer 内写 scheduler。

### 7.3 提交流程

```text
用户完成交互
  1. 锁定当前 StudyItem
  2. 生成/确认 RecallOutcome
  3. 确认答案已真实呈现（PresentationReceipt）
  4. 若 mode=learn 且未 introduced，准备 introduction mutation
  5. 调用唯一 ledger.commit(idempotencyKey)
  6. 获得 StudyEventReceipt
  7. 写 product event
  8. 提交 introduction state
  9. 执行错题/统计/奖励 effect
  10. 标记 readyForNext
```

失败规则：

- ledger 未返回 receipt：不得推进；
- ledger 已成功但产品投影失败：记录 pending effect，不重复 ledger commit；
- introduction 写失败：记录 recovery job，不能用第二 ledger 补写；
- 用户重试使用相同 idempotency key；
- App 重启后根据 product event/ledger mutation receipt 对账恢复。

### 7.4 客观题流程

```text
showingQuestion
→ 用户选择/输入
→ submitObjectiveAnswer
→ 显示课程式正确/错误反馈
→ 产生 answer PresentationReceipt
→ correct/incorrect 映射 RecallOutcome
→ ledger commit
→ Continue
```

客观题不再显示额外二元按钮。

### 7.5 Flip/Fidelity 流程

```text
showingQuestion
→ 点击卡面或“显示答案”
→ revealAnswer
→ 背面真实绘制完成
→ 产生 answer PresentationReceipt
→ 显示“记得/不记得”
→ ledger commit
→ 下一张
```

---

## 8. Renderer-neutral Present ACK

### 8.1 问题

现有 ACK 与 Official WebView presenter 绑定，导致课程式 practice surface 可见时无法产生 ACK。

### 8.2 新合同

```dart
enum PresentationSide { question, answer }

enum PresentationRendererKind {
  flutterStructured,
  flutterFlip,
  officialTemplate,
  fallbackText,
}

class PresentationReceipt {
  final CanonicalCardKey cardKey;
  final int generation;
  final PresentationSide side;
  final PresentationRendererKind renderer;
  final DateTime presentedAt;
}
```

### 8.3 ACK 来源

- Flutter structured renderer：当前题面/反馈完成 frame 后 ACK；
- Flutter flip renderer：正面/背面完成 frame 后 ACK；
- Official WebView：页面 render complete 后 ACK；
- 非 WebView fallback：文本布局完成 frame 后 ACK。

### 8.4 安全规则

- receipt 的 cardKey、generation、side 必须匹配当前 session；
- 旧 generation ACK 一律忽略；
- answer commit 前必须存在当前 generation 的 answer receipt；
- renderer 切换必须增加 generation；
- 不允许通过隐藏/Offstage WebView 伪造 ACK；
- WebView render error 必须进入 recoverable/fatal 状态，不切换 ledger。

---

## 9. 课程学习流程

### 9.1 Lesson 加载

课程 Lesson 不再保存整张 canonical 卡的大份 HTML 副本。建议保存：

```text
Lesson
└─ Stage
   └─ CardPlacementRef(placementId)
```

运行时：

```text
placementId
→ CourseCardPlacement
→ active CardPresentation
→ CanonicalCard（需要 Fidelity/媒体时）
→ StudyItem(mode=learn/practice)
```

### 9.2 首次学习

- `unintroduced` placement 进入 `learn`；
- 完成一次有效提交后标记 introduced；
- 同一提交通过唯一 ledger 初始化排期；
- 用户中途退出时，已提交卡保留 introduced，未提交卡保持 unintroduced；
- Lesson 完成负责课程奖励/解锁，不决定每张卡是否 introduced。

### 9.3 重学课程

已 introduced 卡重新打开 Lesson：

- 默认 `practice`；
- UI 明确显示“练习，不改变正式排期”；
- 允许设置显式“计入排期”，但若实现必须仍使用唯一 ledger；
- 首版建议不开放该选项，降低双写和误排期风险。

### 9.4 课程完成副作用

课程完成仍由课程宿主负责：

- Lesson progress；
- Section/Unit 解锁；
- XP/Gems；
- 课程完成统计。

卡片提交的公共副作用由 StudySessionEffects 负责：

- 错题；
- 产品 review event；
- 卡片最近学习时间；
- 可撤销 effect。

不得把课程解锁副作用放进正式复习 controller。

---

## 10. 正式复习流程

### 10.1 入口统一

以下入口最终都进入相同 route：

- Play Hub 的 Anki 复习；
- Anki 聚合页的全部复习；
- 指定课程的“复习 N 张”；
- Section/Deck 的复习按钮；
- 统计页的“继续复习”。

```dart
StudySessionRoute(
  courseId: courseId,
  mode: StudyMode.review,
  scope: StudyScope(...),
)
```

入口只能改变 scope，不能选择另一套 page/controller。

### 10.2 Review Queue

```text
active placements
∩ introduced states
∩ authoritative ledger due
− suspended
− buried
− retired
```

### 10.3 多 Ledger 课程

迁移期一门聚合课程可能临时包含不同 owner。QueueRepository 必须先按 owner 分组，再分别查询 due；每个 StudyItem 自带 owner。

长期目标是一门 Anki course 对应一个 owner；混合 owner 只作为迁移兼容，不作为新功能。

### 10.4 到期数

所有入口消费同一个 `ReviewQueueSnapshot`：

```dart
class ReviewQueueSnapshot {
  final int introducedDue;
  final int unintroducedNew;
  final bool loading;
  final DateTime? refreshedAt;
  final Object? error;
}
```

必须区分：

- 0；
- loading；
- unavailable；
- error；
- stale。

不得用 0 表示未知。

---

## 11. 新导入大一统流程

### 11.1 Orchestrator

新增统一入口，例如：

```dart
class UnifiedAnkiImportOrchestrator {
  Future<UnifiedAnkiImportResult> importPackage(
    UnifiedAnkiImportRequest request,
  );
}
```

UI 不再先调用 Legacy assembler 再 best-effort Official sync。

### 11.2 阶段

#### 阶段 A：解析与 source identity

- 计算 source hash；
- 检测相同 source；
- 识别 reimport/update/appendAsNew；
- 建立 staging job；
- 不发布课程可见树。

#### 阶段 B：Canonical import

- 根据平台能力选择 canonical backend；
- 导入 Note/Card/Template/媒体/调度快照；
- 返回稳定 sourceId 和 CardKey 列表；
- 对账源 card count；
- 写 `canonicalCommitted`。

#### 阶段 C：Mapping/Presentation

- 获取 notetype schemas；
- 合并已有用户 mapping；
- 运行一次 classifier；
- 每张卡生成 candidate；
- 选出且只选出一个 active presentation；
- 需要确认时停在 `needsMapping`，不发布半成品课程。

#### 阶段 D：Course placement

- 根据 Deck/Tag/Field 生成 Section/Unit/Lesson；
- 每个 CardKey 建一个 placement；
- 一卡一 placement 对账；
- 超大牌组使用 CardRef 分页，不复制 HTML；
- 原子发布新的 projection generation。

#### 阶段 E：Introduction 初始化

- 保留调度且有 reps/revlog：introducedByImport；
- 无历史：unintroduced；
- reimport：保留原 introduction state；
- 新增卡：unintroduced；
- 删除卡：retired。

#### 阶段 F：验证与发布

必须满足：

```text
canonical_card_count
= active_placement_count
= active_presentation_count
```

合法多模板按 cardId 计数，不按 note count 对账。

验证通过后：

- source active；
- course projection generation active；
- CourseProvider reload；
- job complete；
- 旧 generation 异步清理。

### 11.3 平台后端

上层不感知平台差异：

| 平台能力 | Canonical backend | Ledger |
| --- | --- | --- |
| Android Official 可用 | Official collection | Official ledger |
| Official 不可用但本地解析可用 | Local canonical store | Turna ledger |
| 旧数据未迁移 | Legacy adapter | Turna legacy ledger |
| 完全不支持 | fail closed/只读说明 | 不产生假成功 |

---

## 12. 重新导入与更新策略

### 12.1 相同文件

`sourceHash` 完全相同：

- 默认 no-op；
- 可执行媒体完整性修复；
- 不生成新 courseId；
- 不复制 placement；
- 不重置 introduction/schedule/history。

### 12.2 同一来源的新版本

匹配顺序：

```text
稳定 cardId
→ noteGuid + templateOrd
→ 用户确认
```

更新分类：

- unchanged：不改；
- contentChanged：刷新 presentation fingerprint；
- moved：更新 placement；
- added：新建 unintroduced；
- removed：retired；
- ambiguous：进入 review required，不自动复制。

### 12.3 Force Replace

不应先创建第二套完整课程再尝试删除旧课程。目标流程：

- staging 新 generation；
- 验证通过；
- 原子切换 active generation；
- 旧 generation 标记 archived；
- 延迟清理；
- 用户进度通过 CardKey mapping 继承。

### 12.4 Append as New

只有用户明确选择时创建新的 courseId/source identity。UI 必须说明它会生成独立课程和独立学习进度。

---

## 13. 旧数据迁移计划

### 13.1 迁移前冻结

- 禁止继续给 Legacy Anki 页面增加新功能；
- 禁止增加新前缀判断；
- 禁止新增四评分产品入口；
- 新 Anki 改动必须落在 canonical/presentation/session abstraction；
- 建立旧数据 census 和只读诊断页。

### 13.2 Census

每个 import 收集：

```text
legacy import record
legacy note count
legacy card meta count
legacy SRS count
legacy review history count
legacy section/unit/lesson/item count
official source link
official source card count
official collection availability
official revlog count
official projection item count
duplicate cardId projection count
orphan placement count
```

### 13.3 Owner 决策

```text
有明确 official migration row 且 collection/source 可用
→ Official owner

无 official source 或平台无法运行 official
→ Legacy Turna owner

同时存在但映射不一致
→ blockedForRepair，不自动双写
```

### 13.4 ID 映射

建立持久 mapping：

```text
legacy_import_id
legacy_word_id
legacy_card_id
profile_id
official_source_id
canonical_card_id
match_method
confidence
```

匹配必须验证：

- cardId；
- noteGuid；
- templateOrd；
- source fingerprint；
- deck/source scope。

### 13.5 Introduction 回填

优先级：

```text
Official revlog/reps > 0
→ introducedBy importedHistory

Turna Anki history/reps > 0
→ introducedBy migration

所在 Lesson 已完成
→ introducedBy migration

否则
→ unintroduced
```

### 13.6 重复课程项收敛

同 CardKey 有多个 projection kind 时：

1. 保留用户确认的 kind；
2. 否则按新 Presentation Policy 重新决定；
3. 普通词汇优先 Flip；
4. 复杂模板优先 Fidelity；
5. 其他自动生成项转 optional drill 或归档；
6. 合并旧完成/错题引用到 canonical event view；
7. 不合并不同 cardId。

### 13.7 调度冲突

Official owner：

- Official schedule/revlog 胜出；
- 停止 Turna Anki SRS 新写入；
- Turna 旧历史只保留为 analytics legacy source；
- 不重放 Turna 历史到 Official scheduler。

Legacy owner：

- Turna FSRS 保持；
- 不创建伪 Official source；
- UI 明确来源能力；
- 后续可通过独立迁移流程转 Official。

### 13.8 回滚

- 迁移前创建 manifest 和备份；
- 只添加新表/新 generation，不立即删除旧表；
- active route 可以切回旧只读课程树；
- 不回滚 Official collection 的真实复习写入；
- 新 projection 可以删除重建；
- 完成至少一个版本稳定观察后再清理 Legacy 数据。

---

## 14. 详细施工阶段

每个阶段应独立合并、独立验证、可回滚。禁止一次大 PR 同时改导入、数据库、renderer、scheduler 和迁移。

### P0：产品合同、基线与架构守卫

目标：冻结新合同，防止施工期间继续扩大双系统。

任务：

- 将本文件作为大一统主计划；
- 更新旧 Anki 文档，标记冲突部分 superseded；
- 记录完整 analyze/test 基线；
- 增加现状复现测试；
- 增加依赖守卫；
- 为新领域模型建立空实现/接口，不切生产。

架构守卫：

- `views/**` 不得直接 import scheduler DAO；
- renderer 不得写 SRS/Official scheduler；
- 新 UI 不得传裸 quality；
- 新代码不得通过字符串前缀解析 source；
- Official source 不得调用 Legacy manager；
- 新 projection 不得返回多个 active kind。

完成标准：

- CI 可以明确识别新增回归；
- 现有“一卡多投影”“未学可复习”“ACK 死锁”都有失败测试；
- 业务行为尚未切换。

### P1：修复翻面与 Official ACK 死锁

目标：先恢复当前用户最基本的可操作性。

任务：

- 将 ACK 抽象为 renderer-neutral receipt；
- practice surface 正面显示完成后产生 question receipt；
- Flip/structured 背面或反馈显示后产生 answer receipt；
- 卡面点击和“显示答案”走同一 controller 方法；
- 接通 `OfficialTemplateWebViewBody.onReveal`；
- 删除必须依赖未挂载 Official renderer 的 guard；
- 保留 card/generation/side 安全校验；
- 增加 Android 真机回归。

测试：

- 普通词汇卡点击卡面翻面；
- 点击“显示答案”翻面；
- 背面出现前评分不可用；
- 背面 receipt 后评分可用；
- 连续快速点击只 reveal 一次；
- 切卡后的旧 ACK 不启用新卡按钮；
- Fidelity render error 不产生成功 ACK。

### P2：一卡一 Placement、一卡一 Presentation

目标：停止继续制造课程重复卡。

任务：

- 新增 placement/presentation 表与唯一索引；
- 修改 Official `kindsFor()` 为单选 active kind；
- 修改 Legacy adapter：普通词汇不再根据牌组干扰项自动升级正式 MCQ；
- 额外生成题移入 optional drill；
- publish 前执行 cardinality reconciliation；
- CourseProvider 优先读取新 generation；
- 旧 projection 暂时只读兼容。

完成标准：

```text
每个 active CardKey
  exactly one active placement
  exactly one active presentation
```

### P3：统一 CardPresentation 与 renderer

目标：课程和复习展示同一个 presentation。

任务：

- 引入 `CardPresentation` union；
- 新建 `StudyCardSurface`；
- Structured 直接复用课程 `InteractionRenderer`；
- 提取 `AnkiFlipCardSurface`；
- Fidelity WebView 只作为 body；
- ReviewItem/StudyItem 原生持有 presentation；
- 删除统一复习页把 Interaction 压平为 front/back 的路径；
- 删除 Official review runtime 二次分类；
- 课程/复习/预览都从 presentation repository 加载。

测试：

- 同一卡在 learn/review/preview 的 kind 一致；
- MCQ options/correctIndex 一致；
- Flip front/back/media 一致；
- Fidelity template fingerprint 一致；
- mapping 更新原子切换，不出现半新半旧。

### P4：课程 Introduction State

目标：正式复习严格受课程学习资格控制。

任务：

- 新增 introduction repository；
- 课程有效提交后 markIntroduced；
- Lesson 中途退出保留已提交卡状态；
- ReviewQueueRepository 求 due ∩ introduced；
- 导入历史初始化；
- 课程重学明确进入 practice；
- 页面展示“未学新卡”和“已学待复习”两个不同数量。

测试：

- 新导入 20 张，未学习时正式 due=0；
- 学习 3 张退出，最多只有这 3 张可进入正式复习；
- 导入有历史的 8 张直接 introduced；
- practice 不改变 due；
- review 不改变课程 placement；
- retired 卡不进入任何正式队列。

### P5：统一 StudySessionController

目标：课程和正式复习共享卡片生命周期、提交、ACK、receipt 和撤销。

任务：

- 建立统一 controller；
- 客观题 outcome resolver；
- Flip 二元 outcome；
- ledger owner 在 session item 构建时确定；
- 统一 preview/commit/undo；
- 统一 product event；
- 统一错误恢复和 idempotency；
- 课程宿主只保留 Lesson completion；
- 复习宿主只保留 queue/completion；
- 逐步退役 `LessonViewModel` 中 Anki 正式调度职责。

完成标准：

- 相同 StudyItem 在 learn/review 走同一 card state machine；
- renderer 不调用 scheduler；
- 一次提交只有一个 ledger receipt；
- 撤销只恢复一个 event；
- 页面退出/恢复不会重复提交。

### P6：入口大一统

目标：不同入口只改变 StudyScope，不再选择不同产品页面。

任务：

- 新建统一 `StudySessionRoute`；
- Play Hub 接入；
- Anki hub 接入；
- 课程“复习 N 张”接入；
- Deck/Section 接入；
- 统计页接入；
- 删除生产路由中的 Legacy/Official page 分叉；
- gate 只负责 capability 和 backend readiness。

完成标准：

- 所有正式复习入口落到同一个 controller；
- route snapshot 中不存在按 engine 选不同 page；
- Official 不可用时 fail closed，不回落不同语义页面。

### P7：新导入停止双写

目标：从源头停止新用户继续产生两套系统。

任务：

- 上线 UnifiedAnkiImportOrchestrator；
- Android Official 可用时只导入 Official canonical；
- CourseDatabase 只发布 CardPlacement/Presentation；
- 不再为 Official source 创建 Turna Anki SRS；
- Local backend 走相同上层合同；
- 引入 import saga/recovery；
- 重新导入走 generation swap；
- 导入结果页显示 canonical/placement/introduced 对账。

### P8：旧数据迁移

目标：把已有用户收敛到新的 CardKey/Placement/Introduction/Ledger Owner。

任务：

- census；
- backup manifest；
- owner decision；
- ID mapping；
- introduction 回填；
- duplicate projection 收敛；
- Official/Turna schedule 冲突处理；
- dry run；
- 小范围灰度；
- rollback drill；
- 全量迁移。

### P9：历史、统计和 effects 统一

目标：用户看到的复习数据覆盖全部来源且不重复。

任务：

- product event projection；
- Official revlog reader；
- Turna history reader；
- analytics normalization；
- eventId 驱动的错题/奖励；
- undo effect compensation；
- 统计按 course/source 过滤；
- unknown/unavailable 明确展示。

### P10：退役 Legacy 产品路径

目标：删除无调用旧实现，结束长期双轨。

任务：

- 删除旧 Anki formal review route；
- 删除 synthetic Lesson review；
- 删除 Official runtime 二次 classifier；
- 删除一卡多正式投影逻辑；
- 删除 Legacy/Official 双写 import；
- 删除生产 UI 前缀推断；
- 删除过期 flags；
- 删除旧四评分 UI；
- 更新全部 ADR/docs/changelog；
- 旧表在稳定观察期结束后再物理清理。

---

## 15. 建议 PR 切片

1. `anki-unification-contract-and-regression-tests`
2. `renderer-neutral-present-ack`
3. `fix-official-practice-reveal-deadlock`
4. `canonical-card-key-and-placement-schema`
5. `one-card-one-active-presentation`
6. `stop-vocab-multi-projection`
7. `shared-card-presentation-model`
8. `shared-anki-flip-card-surface`
9. `structured-review-uses-course-renderers`
10. `remove-review-runtime-reclassification`
11. `card-introduction-state`
12. `review-queue-due-intersect-introduced`
13. `study-session-controller-core`
14. `objective-outcome-resolver`
15. `study-event-idempotency-and-receipts`
16. `course-learn-mode-adapter`
17. `review-mode-adapter`
18. `unified-study-session-route`
19. `unified-anki-import-orchestrator`
20. `official-import-single-write-cutover`
21. `local-canonical-backend-adapter`
22. `legacy-census-and-dry-run`
23. `legacy-card-key-migration`
24. `legacy-introduction-backfill`
25. `duplicate-projection-collapse`
26. `review-analytics-unification`
27. `legacy-route-retirement`
28. `legacy-storage-cleanup-after-observation`

每个 PR 应包含：

- 明确行为变更；
- 新增/修改测试；
- 数据兼容说明；
- flag/回滚说明；
- `rg` 架构守卫结果；
- 性能影响；
- 真机需求；
- 文档更新。

---

## 16. 文件级施工地图

| 区域 | 当前文件/目录 | 目标动作 |
| --- | --- | --- |
| 导入 UI | `lib/views/anki/anki_import_screen.dart` | 改为只调用 Unified Import Orchestrator |
| Legacy parser | `lib/application/anki/anki_importer.dart` | 降为 Local canonical backend 的解析实现 |
| Legacy assembler | `lib/application/anki/anki_deck_assembler.dart` | 停止直接生成多套业务事实，迁为 placement builder |
| Legacy adapter | `lib/application/anki/anki_card_adapter.dart` | 输出 PresentationCandidate，停止普通词自动升级正式 MCQ |
| Official import | `lib/application/anki_official/import/**` | 作为 Official canonical backend，不再附带第二套 Legacy 产品写入 |
| Official projection | `lib/application/anki_official/projection/**` | 一卡一个 active placement/presentation；候选与 active 分离 |
| Course provider | `lib/application/course_provider.dart` | 读取统一 course source/placement generation，不同时暴露重复树 |
| Lesson VM | `lib/application/lesson_viewmodel.dart` | 逐步移出 Anki 调度与翻面状态，保留课程宿主职责 |
| Lesson page | `lib/views/lesson/new_lesson_screen.dart` | 接入 StudyCardSurface/StudySession learn adapter |
| Interaction renderers | `lib/views/lesson/components/interactions/**` | 纯渲染/收集答案，不写调度 |
| Anki flip | `anki_card_renderer.dart` | 提取共享 AnkiFlipCardSurface |
| HTML flip | `anki_html_card_renderer.dart` | 改为共享 session + renderer-neutral ACK |
| Unified review | `lib/views/review/unified_review_page.dart` | 升级为 StudySessionPage，支持 Structured/Flip/Fidelity |
| Review controller | `lib/application/review/review_session_controller.dart` | 演进/替换为 StudySessionController |
| Legacy review assembler | `lib/application/anki/anki_review_assembler.dart` | 由 ReviewQueueRepository 替代 |
| Legacy review page | `lib/views/anki/anki_review_session_page.dart` | 迁移后退役 |
| Official review page | `lib/views/anki_official/official_anki_review_page.dart` | 迁为统一 session host，最终删除独立状态机 |
| Official practice surface | `official_anki_practice_review_surface.dart` | 删除运行时二次分类，消费 active Presentation |
| Official reviewer stage | `official_anki_reviewer_stage.dart` | 只实现 Fidelity body 和 ACK，不拥有正式复习产品 |
| Official render state | `official_anki_render_state.dart` | ACK 泛化为 renderer-neutral contract |
| Ledger | `lib/domain/review/**` | 扩展为 StudyLedger/Receipt/Owner 强类型合同 |
| SRS | `lib/application/srs_provider.dart` | 只维护 Turna-owned 项，Official 卡彻底禁止注册 |
| 数据库 | `lib/data/course_database.dart` | 新增 source/placement/presentation/introduction/event/import-job schema |
| 路由 | `lib/routing/**` | 所有正式入口改为 StudySessionRoute |
| 统计 | review/history/stats providers | 读取统一 analytics projection |
| 文案 | `lib/l10n/app_strings.dart` | 区分学习、复习、练习、预览；去除误导性重复概念 |

---

## 17. 测试计划

### 17.1 领域单元测试

- CardKey equality/hash/serialization；
- Legacy ID 到 CardKey 解析只存在于 adapter；
- Note 多 Template 产生多个合法 CardKey；
- 同 CardKey 只允许一个 active placement；
- 同 CardKey 只允许一个 active presentation；
- Presentation policy 的优先级；
- 普通词汇默认 Flip；
- 明确 MCQ 保持 MCQ；
- ambiguous quiz 降级 Flip/Fidelity；
- objective correctness 到 RecallOutcome；
- ledger owner resolver；
- idempotency key 重试；
- receipt undo；
- introduction 状态转换；
- due ∩ introduced 集合运算。

### 17.2 Repository 测试

- Official/local backend 返回相同上层 DTO；
- 批量卡加载无 N+1；
- projection generation 原子切换；
- reimport preserve state；
- removed card retired；
- source hash no-op；
- appendAsNew 独立 course；
- import saga crash recovery；
- product event pending effects 恢复；
- stale presentation 不进入生产读取。

### 17.3 Controller 测试

- structured question 流程；
- flip reveal 流程；
- fidelity ACK 流程；
- double tap；
- stale ACK；
- ledger failure 不推进；
- side effect failure 不重复 ledger；
- undo 单 event；
- learn 标记 introduced；
- practice 不写 ledger；
- preview 不写任何状态；
- session restore 不重复提交。

### 17.4 Widget 测试

- MCQ 在课程和复习中使用相同 renderer；
- options/feedback 相同；
- 单词卡在课程和复习中使用相同 Flip surface；
- 卡面点击显示答案；
- 按钮显示答案；
- 返回正面不提交；
- answer ACK 前评分禁用；
- answer ACK 后评分启用；
- loading/error/retry；
- WebView 不吞掉外层唯一 reveal action；
- 无障碍 label；
- 大字体/窄屏/横屏；
- 深色模式。

### 17.5 Golden 测试

每种 presentation 至少覆盖：

- learn/light；
- review/light；
- learn/dark；
- review/dark；
- narrow/large text；
- question；
- answer/feedback。

课程和复习的卡片正文 golden 应一致；允许的差异只在宿主进度/课程标题等外围信息。

### 17.6 集成测试

| 场景 | 预期 |
| --- | --- |
| 导入无历史 20 张 | 课程 20 张，正式复习 0 张 |
| 学习前 3 张后退出 | 3 张 introduced，其余未学 |
| 第 1 张到期 | review 只出现第 1 张 |
| 课程 MCQ 答错 | 一次 forgotten ledger write |
| 课程 Flip 点记得 | 一次 remembered ledger write |
| Official 写入失败 | UI 不推进，不写 Turna fallback |
| 重学完成 Lesson | practice，不改变 due |
| 同文件重导 | 卡数不增加，状态保留 |
| 更新包新增 2 张 | 旧卡保留，新卡 unintroduced |
| 删除 1 张 | retired，不丢历史 |
| Note 正反模板 | 两个 cardId 均保留 |
| 旧一卡多 projection | 收敛为一个 active presentation |
| 撤销 | 只撤最近一个 receipt 及其 effects |
| App 在 ledger 成功后崩溃 | 重启按 idempotency 恢复，不重复写 |

### 17.7 真机测试

Official renderer/PlatformView 行为不能只依赖 widget test。

至少覆盖：

- Android 低版本/目标版本；
- 真机 WebView；
- 音频卡；
- 图片卡；
- MathJax；
- typed answer；
- JS 模板；
- 快速翻面；
- 前后台切换；
- 旋转屏幕；
- session 中断恢复；
- 20/100 张连续复习；
- release build。

---

## 18. 性能目标

### 18.1 导入

- 5k/100k 卡不物化大份 HTML 到每个 Lesson JSON；
- canonical card 读取分页；
- presentation 分类批量执行；
- placement publish 使用批量事务；
- UI progress 可更新；
- cancel 可恢复；
- 不在 CourseDatabase 写事务期间执行大规模媒体文件 I/O。

### 18.2 课程打开

- L1 只加载 Section/Unit/Lesson shell；
- L2 按 Lesson 批量加载 placement refs；
- presentation 按当前/预取窗口加载；
- canonical fidelity 内容按需加载；
- 不扫描全部 SRS state；
- 不为一张卡发起多次 DAO 查询。

### 18.3 复习打开

建议目标：

- 普通 20 张队列冷启动 < 500ms（不含 Official engine 首次 profile open）；
- queue build 使用批量 due + introduced key set；
- presentation 批量加载；
- 当前卡之外预取下一张；
- WebView/Fidelity 懒加载，但不得阻塞队列整体。

### 18.4 内存

- 100k 卡课程不在内存保存完整 Interaction 列表；
- session 默认最多持有当前批次和有限预取；
- 媒体使用引用和缓存；
- WebView controller 生命周期与可见 Fidelity 卡绑定。

---

## 19. 可观测性

不得记录卡片正文、答案、用户媒体或敏感导入内容。

建议匿名聚合指标：

- import stage success/failure/duration；
- canonical/placement/presentation count mismatch；
- duplicate active placement prevented；
- duplicate active presentation prevented；
- review due excluded because unintroduced count；
- question/answer ACK latency；
- stale ACK count；
- reveal failure count；
- ledger commit success/failure/retry；
- idempotency duplicate prevented；
- receipt/effect pending count；
- undo success/failure；
- runtime presentation differs from stored count，目标恒为 0；
- one interaction multiple ledger writes，目标恒为 0。

诊断日志必须包含稳定技术引用：

```text
courseId
sourceId hash/匿名 ID
cardId
sessionId
generation
ledgerOwner
presentationKind
eventId
errorCode
```

不包含 front/back 内容。

---

## 20. Feature Flag 策略

允许的短期 flags：

```text
canonicalCoursePlacementRead
singleActivePresentation
courseIntroductionEligibility
unifiedStudySession
unifiedImportOrchestrator
legacyMigrationRead
```

规则：

- 每个 flag 有 owner、开启条件、删除日期；
- 同一卡同一时刻只能有一个生产 writer；
- flag 可以切换 reader/page，但不能同时启用双 scheduler write；
- Official 不可用时 fail closed；
- 旧路径回滚仍必须经过唯一 ledger adapter；
- 迁移结束后删除永久双产品 flag。

---

## 21. 发布与回滚

### 21.1 发布顺序

1. 只读 schema/repository；
2. 双读对比，不切 UI；
3. 新 presentation 对小范围新导入生效；
4. introduction eligibility 生效；
5. 统一 session 按来源灰度；
6. 新导入停止双写；
7. 旧数据 dry run；
8. 旧数据灰度迁移；
9. 全量切读；
10. 停止旧写；
11. 观察一个或多个稳定版本；
12. 删除旧代码/数据。

### 21.2 回滚边界

可以回滚：

- UI route；
- presentation reader；
- projection generation；
- analytics projection；
- import publish 前的 staging job。

不能通过回滚修改：

- 已提交 Official revlog；
- 已经真实产生的 scheduler mutation；
- 用户在新版本完成的合法学习记录。

### 21.3 数据安全

- 物理删除旧数据前必须有 backup manifest；
- rollback drill 必须在真实 fixture 和测试设备通过；
- source uninstall 与 course archive 分离；
- 归档优先于删除；
- 删除 Official source 必须通过 Official repository，不使用 Legacy DAO。

---

## 22. 风险清单

### 高风险

1. Official scheduler mutation 与 CourseDatabase introduction mutation 无法单事务提交；
2. Official ACK 安全合同泛化后可能产生“答案未显示却允许评分”；
3. 旧数据 CardKey 映射错误会合并错误卡片；
4. Note 多模板被误判为重复；
5. 新导入切断 Legacy 写入后平台能力不足；
6. projection generation 切换中出现空课程；
7. 大牌组 migration 性能和存储压力；
8. 旧历史与 Official revlog 重复统计。

缓解：

- idempotency + saga recovery；
- renderer-neutral 但严格 generation/side ACK；
- dry-run mapping report；
- Card ID 与 noteGuid/templateOrd 双验证；
- Local canonical backend；
- generation atomic publish；
- cursor paging/batching；
- analytics sourceRef 去重。

### 中风险

- 用户习惯变化：词汇卡不再自动变 MCQ；
- 课程重学默认不写排期；
- 未学新卡从“Anki 复习”消失；
- 旧统计数字发生口径变化；
- 某些低置信度卡从结构化退回 Fidelity。

需要明确文案与迁移说明。

---

## 23. 明确禁止的实现方式

以下做法看似快速，实际会继续制造分裂：

1. 只把正课路由跳转到当前 AnkiReviewPage；
2. 只复制 AnkiReviewPage 的 UI 到 Lesson 页面；
3. 同时向 Turna SRS 和 Official scheduler 写相同 outcome；
4. Official 失败时静默回退 Legacy；
5. 根据 `id.startsWith()` 在 Widget 中决定 scheduler；
6. 按 noteId 去重所有卡；
7. 继续让词汇卡生成多个正式 projection；
8. 在复习页重新运行 classifier；
9. 使用隐藏 WebView 伪造答案 ACK；
10. 把完整 HTML 复制进每个 Lesson JSON；
11. 用课程 Lesson 完成状态代替逐卡 introduced；
12. 用 scheduler new/learning/review 代替课程是否已学；
13. 用 0 代表 due unavailable；
14. ledger 成功后因统计失败再次提交 scheduler；
15. 长期保留两套生产页面并继续分别开发。

---

## 24. Definition of Done

### 卡片身份

- [ ] 所有新 Anki 卡使用强类型 CanonicalCardKey；
- [ ] UI/session 不通过 ID 前缀判断 source；
- [ ] 一个 active CardKey 只有一个 active CoursePlacement；
- [ ] 一个 active CardKey 只有一个 active Presentation；
- [ ] Note 多模板的不同 cardId 被正确保留；
- [ ] 一卡多正式 projection 已停止。

### 课程资格

- [ ] 有逐卡 introduction state；
- [ ] 未学且无导入历史的卡不进入正式复习；
- [ ] 导入历史卡正确标记 introduced；
- [ ] Lesson 中途退出不会误标未提交卡；
- [ ] 课程重学默认 practice，不写正式排期。

### 渲染

- [ ] 课程和复习读取同一个 active Presentation；
- [ ] 选择题、多选、填空、听力复用课程 renderer；
- [ ] 普通词汇在课程和复习中复用同一个 Flip surface；
- [ ] Fidelity WebView 只作为卡片正文；
- [ ] 复习页不再二次分类；
- [ ] 卡面点击和显示答案按钮行为一致；
- [ ] answer receipt 前不能提交评分。

### 会话与调度

- [ ] learn/review/practice/preview 模式显式；
- [ ] 所有正式复习入口使用同一个 StudySessionController；
- [ ] 每个 StudyItem 在 session 开始前确定唯一 ledger owner；
- [ ] 一次作答只产生一个 scheduler mutation；
- [ ] Official 失败不回退 Turna；
- [ ] UI 只有收到 receipt 后推进；
- [ ] 撤销精确恢复一个 event 及对应 effects；
- [ ] crash retry 不重复写入。

### 导入与迁移

- [ ] 新导入不再 Legacy + Official 双写；
- [ ] canonical/placement/presentation 数量严格对账；
- [ ] 相同文件重导不重复；
- [ ] 更新包保留学习状态；
- [ ] 删除卡 retired 而非丢历史；
- [ ] 旧数据 owner 已决策；
- [ ] 旧一卡多投影已收敛；
- [ ] backup/rollback drill 已通过；
- [ ] Legacy 生产写路径已停止。

### 产品入口与统计

- [ ] Play Hub、Anki Hub、课程和统计页只改变 StudyScope；
- [ ] 不再根据 backend 进入不同正式复习产品；
- [ ] 到期数来自同一 queue repository；
- [ ] 0/loading/unavailable/error/stale 可区分；
- [ ] Official revlog 与 Turna history 统一展示且不重复；
- [ ] 用户可按课程/来源解释统计。

### 清理

- [ ] Legacy synthetic Lesson review 已删除；
- [ ] Official 独立 formal review 状态机已退役；
- [ ] 运行时 classifier 重复路径已删除；
- [ ] 过期 feature flags 已删除；
- [ ] 旧文档已标记 superseded 或更新；
- [ ] `rg` 架构守卫通过；
- [ ] 完整自动化测试和真机测试通过。

---

## 25. 最终验收场景

以一个包含 100 张卡、其中 20 张有已有 Anki 历史的牌组为例：

### 导入后

```text
canonical cards             = 100
active course placements    = 100
active presentations        = 100
introduced                  = 20
unintroduced                = 80
正式复习可见范围              = 20 中真正 due 的卡
```

课程里不会因为词汇派生 MCQ 而出现 120 或 180 个正式项目。

### 用户学习 5 张新卡

```text
introduced                  = 25
unintroduced                = 75
```

每张卡的首次提交只写所属 ledger 一次。退出 Lesson 后，第 6 张未提交卡仍为 unintroduced。

### 进入 Anki 复习

QueueRepository 返回：

```text
Official/Turna authoritative due
∩ 25 张 introduced
∩ 当前 course placements
```

未学的 75 张不会混入。

### 遇到选择题

- 使用与课程完全相同的题面、选项和反馈；
- 选对映射 remembered；
- 选错映射 forgotten；
- 只写一个 ledger event；
- 不再切成普通 front/back 卡。

### 遇到普通单词

- 使用与课程相同的 AnkiFlipCardSurface；
- 点击卡面或按钮均可显示答案；
- 背面真实显示后出现“记得/不记得”；
- 提交后进入下一张；
- 可按 receipt 撤销。

### 重新导入相同文件

```text
canonical cards             = 100
active placements           = 100
introduced                  = 25
```

不会变成 200 张，不会重置课程，不会复制调度状态。

---

## 26. 施工启动建议

建议第一轮只启动四个 PR，不直接进入大规模迁移：

1. 用测试稳定复现 Official 显示答案死锁；
2. 引入 renderer-neutral Present ACK 并修复翻面；
3. 引入 CardKey/Placement/Presentation schema 和只读 repository；
4. 修改 projection policy，保证一卡一个 active presentation。

这四步完成后，再开始 introduction state 和统一 session。原因是：

- 翻面问题是当前用户阻断，应最先修复；
- 一卡多投影若不先停止，后续迁移数据会继续膨胀；
- CardKey/Placement 是课程资格、统一 renderer、统一队列的共同基础；
- 在身份和 presentation 尚未稳定前直接重写 session，会把现有错误模型继续带进新页面。

本计划完成的最终标志不是“旧页面看起来和新页面一样”，而是任何一张卡都能回答以下问题且答案唯一：

```text
它是谁？            CanonicalCardKey
它属于哪门课？       CourseCardPlacement
它应该怎么显示？      Active CardPresentation
它是否已经学过？      CardIntroductionState
它现在是否到期？      Source-owned Ledger
这次作答写到哪里？    StudyLedgerOwner
如何撤销这次作答？    StudyEventReceipt
```

只要其中任意一个问题仍可能得到两个答案，Anki 功能就还没有真正完成大一统。
