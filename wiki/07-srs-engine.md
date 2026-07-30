# 07. SRS / 间隔重复引擎

> 路径：`lib/core/`（算法）+ `lib/application/srs_queue_provider.dart`（共享基础设施）+ `lib/data/srs_state_dao.dart`（持久化）

Varnamala 使用 **FSRS**（生产默认，ADR 0028）+ **SM-2**（保留可用）作为间隔重复调度算法，并维护一套完整的复习数据流。

---

## 7.1 调度器抽象

[`lib/core/srs_scheduler.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/core/srs_scheduler.dart)：

```dart
abstract class SrsScheduler {
  /// Apply a quality grade and return the updated card state.
  /// [quality] uses SuperMemo-style 0..5 (or FSRS-mapped binary grades).
  /// [random] may drive interval fuzz when supported.
  SrsWord review(SrsWord word, int quality, {DateTime? now, Random? random});

  /// Deterministic preview of the next interval in whole days.
  /// Must not apply random fuzz.
  int previewIntervalDays(SrsWord word, int quality, {DateTime? now});

  /// Predicted probability of successful recall at [now] (0..1).
  double retrievability(SrsWord word, {DateTime? now});

  /// Continuous mastery signal in [0,1] for UI — **not** a discrete stage.
  double masteryScore(SrsWord word, {DateTime? now});
}
```

**关键设计原则**：**mastery 是连续信号**（retrievability / masteryScore），不是"通过第几关"。

---

## 7.2 SM-2 引擎（保留）

[`lib/core/sm2.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/core/sm2.dart) — SuperMemo 2 算法，二元评分调优版。

### 7.2.1 评分约定

| 评分 | 含义 | UI 按钮 |
|---|---|---|
| 0..2 | 失败（忘了） | "Again" |
| 3..5 | 成功（记住） | "Hard" / "Good" / "Easy" |

UI 实际使用 **二元评分**（4 按钮），通过 [`ReviewGrade`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/core/sm2.dart) 别名映射：

| UI 按钮 | SM-2 quality |
|---|---|
| 不认识 (Again) | 1 |
| Hard | 3 |
| Good | 4 |
| Easy (认识) | 5 |

### 7.2.2 Binary-specific 调优

相比经典 SM-2，二元评分场景做了以下调整：

```dart
class Sm2Engine implements SrsScheduler {
  static const double initialEase = 2.5;
  static const double minEase = 1.3;              // ease 地板
  static const double maxEase = 3.0;              // ease 天花板
  static const double knownEaseBonus = 0.02;     // 每次成功缓慢恢复 ease
  static const double lapseEasePenalty = 0.2;    // 固定 ease 惩罚（Anki 风格）
  static const double lapseIntervalFactor = 0.2; // 成熟卡 lapse 时保留旧 interval 比例
  static const int matureThresholdDays = 21;     // 成熟阈值
  static const int maxIntervalDays = 730;        // interval 上限
  static const int relearnDelayMinutes = 10;     // 失败后多久重做（同日 relearn）
  static const double overdueBonusCap = 2.0;     // 延迟复习奖励倍数
  static const int fuzzThresholdDays = 7;        // 早期 interval 不抖动
  static const double fuzzRatio = 0.15;          // 成熟 interval ±15% 抖动
}
```

**核心特性**：

- 失败使用固定 ease penalty 而非线性 SM-2
- 成熟卡 lapse 时保留 20% 旧 interval（Anki "new interval"）
- 成功 review 让 ease 缓慢恢复（避免 ease hell）
- 过期复习获得 overdue 奖励
- 成熟卡 interval 加 ±15% 抖动避免堆积

---

## 7.3 FSRS 引擎（生产默认）

[`lib/core/fsrs_engine.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/core/fsrs_engine.dart) — 基于 `fsrs` 包的 FSRS 调度器（ADR 0028）。

### 7.3.1 关键差异（vs SM-2）

| 维度 | SM-2 | FSRS |
|---|---|---|
| 模型 | 离散阶段（review / relearn） | 连续记忆模型 |
| 关键参数 | ease factor | `stability`（天数）+ `difficulty`（[1,10]） |
| 计算方式 | 启发式公式 | 21 个权重 + 期望保留率 |
| 评分 | 0..5 | pass=Good / fail=Again（二元） |
| 个性化 | 单一 ease | 用户个性化权重（FSRS Optimizer） |

### 7.3.2 构造函数

```dart
class FsrsEngine implements SrsScheduler {
  FsrsEngine({
    this.desiredRetention = 0.9,            // 目标 recall 概率
    this.maximumIntervalDays = 730,         // interval 上限
    this.enableFuzzing = true,              // 间隔抖动（确定性预览时禁用）
    this.maxSameDayFails = 4,               // 同日失败次数上限
    List<double>? parameters,               // 21 长度权重（null = 默认）
  }) : ...;

  static const double masteryStabilityRefDays = 30.0;
}
```

### 7.3.3 Binary-only 评分

`FsrsEngine.review()` 内部把 `quality` 映射为 `fsrs.Rating`：

| UI | quality | Rating |
|---|---|---|
| 不认识 (Again) | 1 | Again |
| Hard | 3 | Hard |
| Good | 4 | Good |
| Easy (认识) | 5 | Easy |

### 7.3.4 同日 relearn 阶梯

[`lib/core/fsrs_relearn.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/core/fsrs_relearn.dart)（ADR 0029）：

```dart
Duration? relearnDelayForFailStreak(int failStreak, {bool mature = false}) {
  if (failStreak <= 0) return const Duration(minutes: 10);
  if (failStreak == 1) {
    return Duration(minutes: mature ? 30 : 10);  // 成熟卡首次失败延长到 30min
  }
  if (failStreak == 2) return const Duration(minutes: 30);
  if (failStreak == 3) return const Duration(hours: 2);
  return null; // ≥4 次失败 → 推到明天
}

const double matureStabilityDays = 21.0;
bool isMatureStability(double? stability, int intervalDays);
```

### 7.3.5 FSRS 优化器

[`lib/core/fsrs_optimizer.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/core/fsrs_optimizer.dart) — 根据用户的 `review_events` 历史拟合个性化 21 维权重：

- 输入：用户的 review history（cardId, queue, reviewedAt, quality, ...）
- 输出：`List<double>` 长度 21 的最优权重
- 用户在 Settings → Learning → FSRS Optimization 可触发

---

## 7.4 SRS 共享基础设施

[`lib/application/srs_queue_provider.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/srs_queue_provider.dart) — `SrsQueueProvider` 是 SrsProvider + GrammarReviewProvider 的共享基类。

### 7.4.1 类签名

```dart
abstract class SrsQueueProvider extends ChangeNotifier {
  SrsQueueProvider(this.appPrefs, this.linkStore, this.srsDao) {
    engine = _buildFsrsEngine();
  }

  final AppPrefs appPrefs;
  final LessonLinkStore linkStore;
  final SrsStateDao srsDao;

  /// 生产默认：FSRS（ADR 0028）。测试可注入 Sm2Engine。
  late SrsScheduler engine;

  /// Legacy SM-2 engine kept for callers that need the concrete type.
  @protected
  final Sm2Engine sm2Engine = const Sm2Engine();

  @visibleForTesting
  void setSchedulerForTesting(SrsScheduler scheduler);

  // 子类必须实现
  String get statePrefsKey;   // legacy blob key（仅 v7 迁移使用）
  String get queueId;         // 'srs' | 'grammar'
  String get logTag;
}
```

### 7.4.2 内存缓存 + 写穿透

```dart
Map<String, SrsWord>? _cachedState;  // id-keyed

Map<String, SrsWord> get state {
  if (_cachedState != null) return _cachedState!;
  // 同步读取 from in-memory cache（hydrated by ensureLoaded）
}

Future<void> persist(Map<String, SrsWord> next) async {
  _cachedState = next;
  await srsDao.upsertBatch(queueId, next.values);  // 穿透到 SQLite
  notifyListeners();
}
```

**为什么需要内存缓存**：UI 中 `dueCount`、`getDueWords()`、`context.select` 都需要同步读取；不能每次 await DB。

### 7.4.3 ensureLoaded 启动流程

```dart
Future<void> ensureLoaded() async {
  if (_cachedState != null) return;  // idempotent

  // 1. 从 SQLite 加载（schema v7 之后的路径）
  _cachedState = await srsDao.loadQueue(queueId);

  // 2. 如果有 legacy prefs blob，运行一次性迁移
  await _migrateLegacyPrefsIfNeeded();

  notifyListeners();
}
```

### 7.4.4 注册新词

```dart
void registerItem(String id, {SrsItemType type = SrsItemType.word}) {
  final state = this.state;
  if (state.containsKey(id)) return;  // 幂等
  state[id] = SrsWord.fresh(id).copyWith(type: type);
  // 不持久化 —— 等下次 reviewItem 才落库（lazy write）
  notifyListeners();
}
```

### 7.4.5 复习（核心方法）

```dart
Future<SrsWord?> reviewItem(String id, int quality) async {
  final current = state[id];
  if (current == null) return null;

  // 1. 调用 scheduler
  final updated = engine.review(current, quality, now: DateTime.now());

  // 2. 写入状态
  state[id] = updated;
  await persist(state);

  // 3. 记录 review event（用于记忆曲线 / FSRS Optimizer）
  final failCount = quality < 3 ? sameDayFailCount(id) : 0;
  await reviewHistoryDao.insertEvent(ReviewEventRecord(
    cardId: id,
    queue: queueId,
    reviewedAt: DateTime.now().millisecondsSinceEpoch,
    quality: quality,
    prevIntervalDays: current.intervalDays,
    nextIntervalDays: updated.intervalDays,
    prevEase: current.ease,
    nextEase: updated.ease,
    reps: updated.reps,
    lapses: updated.lapses,
    type: updated.type.name,
  ));

  return updated;
}
```

---

## 7.5 SrsProvider

[`lib/application/srs_provider.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/srs_provider.dart) — 单词 + 表达 SRS 队列。

```dart
@lazySingleton
class SrsProvider extends SrsQueueProvider {
  @override String get statePrefsKey => LocalStateKeys.srsState;
  @override String get queueId => 'srs';
  @override String get logTag => 'SrsProvider';

  // 公开 API
  void registerWord(String wordId);
  void registerAll(Iterable<String> wordIds);
  void registerExpression(String expressionId);
  void registerAllExpressions(Iterable<String> expressionIds);

  Future<void> bulkImportStates(Map<String, SrsWord> states);  // Anki
  Future<void> removeByPrefix(String prefix);                  // Anki 卸载

  Future<void> recordLessonLinks({
    required Iterable<String> wordIds,
    required String lessonId,
    required String lessonName,
    LinkType type = LinkType.word,
  });

  Future<SrsWord?> reviewWord(String wordId, int quality);
  Future<SrsWord?> reviewWithQuality(String wordId, ReviewGrade grade);

  // 查询
  int get dueCount;
  List<SrsWord> getDueWords({int limit = 20});
  List<SrsWord> getRecentExpressions();  // 带缓存
}
```

---

## 7.6 GrammarReviewProvider

[`lib/application/grammar_review_provider.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/grammar_review_provider.dart) — 语法点 SRS 队列，与 SrsProvider 并行。

```dart
@lazySingleton
class GrammarReviewProvider extends SrsQueueProvider {
  @override String get statePrefsKey => LocalStateKeys.grammarReviewState;
  @override String get queueId => 'grammar';

  void registerGrammarPoint(String id);
  void registerAll(Iterable<String> ids);

  /// Force [id] into the due queue immediately (mistake → grammar cross-route).
  Future<void> markDueNow(String id);

  Future<void> recordLessonLinks({...});
  Future<SrsWord?> reviewGrammarPoint(String id, int quality);
}
```

两个 Provider 共享 `srs_states` 表（用 `queue` 列区分），但缓存与状态机完全独立。

---

## 7.7 错题本

[`lib/application/mistake_provider.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/mistake_provider.dart) — **不存 SQLite**，用 SharedPreferences JSON blob。

```dart
@lazySingleton
class MistakeProvider extends ChangeNotifier {
  static const int maxEntries = 30;
  static const String _prefsKey = LocalStateKeys.mistakeLog;

  List<MistakeEntry>? _cached;
  List<MistakeEntry>? _cachedView;

  List<MistakeEntry> get entries;       // unmodifiable view
  int get count;
  List<MistakeEntry> recentMistakes({int max = 20});  // AI tutor context

  Future<void> record(MistakeEntry entry);          // FIFO 添加
  Future<void> recordRewrite(String entryId);      // rewriteCount++; ≥2 时清除
  Future<void> clear();
  Future<void> removeById(String entryId);
}
```

**写入策略**：JSON 字符串读写；`_cachedView` 提供 immutable view。

---

## 7.8 弱词复习 Quiz 组装

[`lib/application/weak_word_quiz_assembler.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/weak_word_quiz_assembler.dart)：

```dart
class WeakWordQuizAssembler {
  /// 拼装规则：
  /// - 来自 MistakeProvider 的最近 30 天错题
  /// - 同一 wordId 错误次数 ≥ 2
  /// - 拼装为 10 道题 quiz
  Future<List<Interaction>> assembleQuiz({int questionCount = 10});
}
```

输入是 MistakeEntry 列表（每个含 wordId + interactionSnapshot），输出是 `List<Interaction>`，可以直接喂给 `LessonViewModel.startLesson(quizLesson, practiceMode: true)`。

---

## 7.9 连胜（Streak）

[`lib/application/streak_provider.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/streak_provider.dart) + [`lib/core/streak_resolver.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/core/streak_resolver.dart)

### 7.9.1 纯函数 StreakResolver

```dart
class StreakResolution {
  final int newStreak;
  final bool broken;
}

StreakResolution resolveStreakOnPractice({
  required int oldStreak,
  required DateTime? oldDate,
  required DateTime today,
}) {
  // oldDate null → 启动/保持 streak ≥ 1
  // 同一日历日 → unchanged
  // 连续日（gap=1）→ increment
  // gap ≥ 2 → reset to 1, broken
}
```

### 7.9.2 StreakProvider 状态机

```dart
@lazySingleton
class StreakProvider extends ChangeNotifier {
  int get streak;
  DateTime? get lastStreakDate;
  bool get streakWasBroken;

  StreakCheckResult _lastStreakCheckResult = StreakCheckResult.none;
  StreakCheckResult get lastStreakCheckResult;

  /// 调用时机：app 启动 / 进入主页
  StreakCheckResult checkStreakOnAppOpen();

  /// 调用时机：用户完成一节课（产生 Practice Day）
  Future<StreakResolution> applyPracticeDay(DateTime today);
}
```

---

## 7.10 复习事件历史（ReviewHistoryDao）

[`lib/data/review_history_dao.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/data/review_history_dao.dart)：

```dart
@lazySingleton
class ReviewHistoryDao {
  Future<void> insertEvent(ReviewEventRecord event);
  Future<void> insertBatch(Iterable<ReviewEventRecord>);  // Anki revlog 迁移

  Future<List<ReviewEventRecord>> eventsForCard(String cardId);
  Future<List<ReviewEventRecord>> recentEvents({int limit = 500});
}
```

**用途**：
- [`MemoryCurveProvider`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/memory_curve_provider.dart) — 计算保留率、预测、成熟度
- `FsrsOptimizer` — 个性化权重优化
- Profile 页统计图表

**不清理历史**：遗忘曲线模型需要完整 history。

---

## 7.11 完整数据流

```
用户答错一道题
  ↓
LessonViewModel.onAnswer(correct=false)
  ↓
SrsProvider.reviewWord(wordId, quality=1)        // 同时把 wordId 注册到队列
  ├─ engine.review(current, 1)                   // FSRS / SM-2
  │   ├─ 计算新 stability / difficulty / interval
  │   ├─ 同日失败 → relearn 阶梯（10m → 30m → 2h → next day）
  │   └─ 返回更新后的 SrsWord
  ├─ state[id] = updated                          // 内存 cache
  ├─ srsDao.upsert(queueId, updated)             // 穿透到 SQLite
  └─ reviewHistoryDao.insertEvent(...)           // review_events 表

LessonViewModel.onAnswer(correct=false)
  ↓
MistakeProvider.record(MistakeEntry(
  wordId, lessonId, stageId, interactionId,
  grammarPointId,  // 可选
  interactionSnapshot,  // JSON 化的 Interaction
  userAnswer, correctAnswer, timestamp,
))

如果 grammarPointId != null:
  ↓
GrammarReviewProvider.markDueNow(grammarPointId)  // 跨路由到语法复习

LessonViewModel.notifyComplete()
  ↓
LessonCompletionCoordinator
  ├─ StreakProvider.applyPracticeDay(today)
  ├─ ScoreProvider.addScore(XPEvent.lessonComplete)
  ├─ StudyStatsProvider.recordActivity(...)
  └─ GameMilestoneProvider.checkMilestones()
```

---

## 7.12 评分 UI 集成

SRS Review UI（[`views/review/srs_review_screen.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/review/srs_review_screen.dart)）的 4 按钮：

| 按钮 | 评分 | 含义 |
|---|---|---|
| Again (不认识) | 1 | 忘了 → 10m / 30m / 2h 重做 |
| Hard | 3 | 想起来但吃力 |
| Good | 4 | 正常想起（默认） |
| Easy | 5 | 完全掌握 |

按钮 → [`ReviewGrade`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/core/sm2.dart).outcome → SrsProvider.reviewWithQuality(wordId, grade)。