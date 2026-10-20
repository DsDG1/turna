# ADR 0014 — 词典与薄弱词复习

> 状态：Accepted ｜ 日期：2026-07-11 ｜ 关联：future4 Phase 22

## 决策

### 词典

- 路由：`DictionaryPage` / `DictionaryRoute`（受 `CourseReadyGuard` 守卫）。
- 搜索是对内存 map 的纯函数（`searchDictionary`）；播放走 `AudioController.speakWord` / `speak`。

### 薄弱词

| 规则 | 取值 |
|---|---|
| 窗口 | 最近 **30** 天 |
| 阈值 | 同一 `wordId` 错过 **≥ 2** 次 |
| 上限 | **10** 道测验题 |
| 仅语法的错误 | 不计入单词测验 |

装配器：`WeakWordQuizAssembler` → 合成的 `Lesson`（term → translation 的 MCQ），复用 `LessonViewModel`。

### 本地提醒

可选的每日本地通知，文案温和；偏好为 `SettingsProvider` 上的 `dailyReminderEnabled` 与时/分；`LocalReminderService` 经 `flutter_local_notifications` 排期。

## 理由

学习者需要对随包词表 / 表达 / 语法点的离线检索，以及针对反复答错单词的专项训练。

## 影响与边界

- 验证不需要新内容。
- Play hub 暴露 Dictionary 与 Weak Words 两张卡。
