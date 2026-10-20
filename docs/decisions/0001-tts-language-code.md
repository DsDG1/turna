# ADR 0001 — TTS 语言码（斯瓦希里语）

> 状态：Accepted（2026-07-09）｜**已被 [ADR 0020](./0020-swahili-to-turkish-pivot.md) 取代**——项目从斯瓦希里语转向土耳其语，TTS 语言码现在是 `'tr'`。本 ADR 作为历史记录保留。
## 决策

用 **`'sw'`** 作为 `TargetLanguage.swahili` 的 TTS 语言码；`lib/application/language_provider.dart` 的 `ttsLanguageCode` 返回 `'sw'`。
## 理由

随包词表（`assets/courses/swahili/vocab.json`）当时仍是卡纳达语占位词，而课程 index（`index.json`）已声明课程语言为 `"sw"`——两个码不能混用。

TTS 语言码原本被设成 `'kn'`，好让设备 TTS 引擎能念出那些卡纳达语占位词；原 `future2.md`（已删）Phase 10 要求一个明确决定：用 `'sw'` 还是保留 `'kn'`。
### 被否决的选项

- **保留 `'kn'`**——能让卡纳达语占位词照旧发音，但会把实现细节泄进运行时行为，并与「斯瓦希里语优先」的定位冲突。
## 影响与边界

- app 与其声明的目标语言一致（`index.json` / `vocab.json` / `expressions.json` 全为 `"sw"`）。
- 在卡纳达语占位词被真实斯瓦希里语内容替换前，设备 TTS 会用斯瓦希里语音念卡纳达语词；念不出的词很可能退化为逐字母拼读。
- `AudioController.speakWord` 的离线音频兜底路径不变：真实音频资产进入 `WordEntry.audioAsset` / `Expression.audioAsset` 后会自动优先于 TTS。
- 本决策不生成任何新音频或课程内容。
