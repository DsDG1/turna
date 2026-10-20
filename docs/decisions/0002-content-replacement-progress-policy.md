# ADR 0002 — Content Replacement Progress Policy

> **Status**: Accepted ｜ **Date**: 2026-07-10 ｜ **Related**: Phase 13、Phase 20
## 决策

当随包课程的 `version` 上升且 app 检测到已有用户进度时，启动时显示**一个非阻塞对话框**，只有两个选项：

1. **Reset progress** — 清空所有 completed lesson IDs、perfect lesson IDs、SRS 卡片、学习统计与错题本记录，用新课程从头开始。
2. **Keep progress** — 保留 completed lesson IDs 与其它记录。用户从中断处继续，但某些此前标记完成的课时可能已包含新词/新句。
## 理由

应用当时处于过渡态：课程标着「Swahili」、语法点是真实斯瓦希里语，但 `vocab.json` 里仍是卡纳达语占位词（`Naanu`、`Neenu`、`Howdu` 等）。后续 Phase 20 会把这些占位词整体替换成真实斯瓦希里语词汇。

底层词表一变，用户进度记录（完成的课时、SRS 间隔、错题本条目）可能不再有语义：
### 被否决的选项

- **Silently reset everyone**：数据一致性最简单，但对活跃用户不尊重。
- **Migrate progress word-by-word**：尝试用 `migration/vocab_map.json` 把旧 SRS 卡片映射到新词。
## 影响与边界

### Reset progress

- **优点**：干净起点；SRS 间隔与错题本和新内容语义一致；避免卡纳达语残留造成的困惑。
- **缺点**：用户失去连胜/课时完成历史；若已投入大量时间，可能感觉被惩罚。
### Keep progress

- **优点**：尊重用户的时间投入；不强制重启。
- **缺点**：SRS 卡片可能仍引用旧卡纳达语词条；错题本可能指向译义已变的词；某些标记「已完成」的课时回访时会显示新内容。
### 实施约束

- 对话框**每个内容版本只弹一次**。
- 默认选项是 **Keep progress**（非破坏性）。
- 选择结果被持久化，后续启动不再弹同一版本的对话框。
- 本策略适用于 Phase 20 的卡纳达语 → 斯瓦希里语替换，也适用于未来任何重大内容版本变更。
### 落地形态

- **检测**：`CourseRepository.contentVersion()` 读 `contentVersion` meta（`DatabaseSeeder` 写入的 `index+expressions` 复合版本），与 `LocalStateKeys.contentVersionAcknowledged` 比较。
- **触发点**：`HomePage._maybePromptContentUpdate`，在 `initSession` 的连胜检查之后 post-frame 运行。**仅当用户已有进度**（`GameProvider.completedLessonIds` 非空）时弹；全新安装静默确认，永不看到对话框。
- **对话框**：`ContentUpdateDialog`（`lib/views/content_update/`），`barrierDismissible: false`，返回 typed `ContentUpdateChoice`——「Keep progress」（默认）/「Reset progress」。
- **重置动作**（选「Reset progress」时清）：`GameProvider.resetLessonProgress()`、`MistakeProvider.clear()`、`StudyLogRepository.clearAll()`，以及新增的 `SrsProvider.clear()` / `GrammarReviewProvider.clear()`（Phase 17 之前 SRS 队列没有重置方法）。
- **持久化**：无论选哪个，都把 `contentVersionAcknowledged` 置为当前存储版本，同一版本不再弹。
- 跨 Phase 17 升级的既有安装会看到一次性 reseed（它们的 meta 是旧的单段 `"5"`，与新的 `"5+1"` 不同）——这正是有进度的用户会看到弹窗的原因。
- **重置动作**（选「Reset progress」时清）：`GameProvider.resetLessonProgress()`、`MistakeProvider.clear()`、`StudyLogRepository.clearAll()`，以及新增的 `SrsProvider.clear()` / `GrammarReviewProvider.clear()`（Phase 17 之前 SRS 队列没有重置方法）。
- **持久化**：无论选哪个，都把 `contentVersionAcknowledged` 置为当前存储版本，同一版本不再弹。
- 跨 Phase 17 升级的既有安装会看到一次性 reseed（它们的 meta 是旧的单段 `"5"`，与新的 `"5+1"` 不同）——这正是有进度的用户会看到弹窗的原因。
### 相关代码

- `lib/views/settings/settings_page.dart` — 手动重置入口

- `lib/application/game_provider.dart` — `resetLessonProgress()`
- `lib/application/course_provider.dart` — 内容版本检测
