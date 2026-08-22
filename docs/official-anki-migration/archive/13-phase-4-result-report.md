# Phase 4 官方 Anki Scheduler 结果报告

> 文档代号：P4-SCHEDULER 结果
> 日期：2026-08-17
> 分支：`spike/official-anki-core-android`
> HEAD：`81ba44b3bf11fc91846f787346245a17fd96a897` + dirty worktree
> 上游 pin：`967aa0d578fc75181e292e95326f9b58698da25c`
> contract source：`1.3`
> 计划：`12-phase-4-official-scheduler-implementation-plan.md`

## 决策

```text
P4 TECHNICAL ACCEPTANCE NO-GO
P4 PRODUCTION NO-GO
```

拆分状态：

```text
P4 HOST / CONTRACT CONSTRUCTION: GO
P4 PRODUCTION IMPLEMENTATION ENTRY: NO-GO
P4 TECHNICAL ACCEPTANCE: NO-GO
P4 PRODUCTION: NO-GO
```

`TURNA_OFFICIAL_ANKI_SCHEDULER` / `OfficialAnkiFeatureFlags.scheduler` 仍默认 `false`。本报告不授权打开生产评分。

## 已完成的 Host 施工

- Contract 1.3 发布 11–16、27–30；`ENGINE_INFO.capabilities` 只列出已实现操作。
- Request/response 为 camelCase。Dart 只接收 opaque `answerToken`、官方 interval labels 和 display DTO，不接收 `SchedulingStates` / FSRS / revlog 行。
- `GET_REVIEW_QUEUE` 生产路径 `fetchLimit=1`；native 空请求默认也是 1。
- `SET_CURRENT_DECK` 校验 deck 存在，成功后提升 `queueEpoch` 并清空旧 token。
- Answer token 在调用官方 `answer_card` 前不再删除。状态为 pending → in-flight → committed | failed-unwritten | unknown。
- 确认未写返回 `ANSWER_FAILED` 并允许同一 token 显式重试；提交后 response 丢失返回 `ANSWER_COMMIT_UNKNOWN`，再次使用同一 token 不增加 revlog。
- `millisecondsTaken` 回显请求值，拒绝负数和 >24h。Native answered-at 使用 `TimestampMillis::now()`；仅测试注入 flag 才接受 `answeredAtMillis`。
- Undo/Redo/Bury/Suspend/Counts/Congrats 走 pinned rslib。Bury 稳定 mode：`suspend` / `burySched` / `buryUser` / `restoreCards` / `unburyDeckAll` / `unburyDeckSchedOnly` / `unburyDeckUserOnly`。
- Formal Review（`/official-anki/review`）与 Preview/`canonicalLink` 分离。评分按钮只在 Show Answer 之后出现。
- `OfficialReviewSession`：answer-visible monotonic elapsed、single-flight、stale 重载不重放、unknown 进入 reconciliation 且不自动重答。
- 所有权计数：formal 路径 Turna SRS / Legacy / projection = 0；preview/derived official scheduler writes = 0。

## 测试证据

| 命令 | 次数 | 结果 |
|---|---:|---|
| `cargo test --lib` | 2 | 64 passed / 64 passed |
| `flutter test --no-pub test/application/anki_official` | 2 | 159 passed / 159 passed |
| Host FFI set-deck → queue → answer good → stale | 2 | 1 passed / 1 passed |
| `flutter analyze` official lib/views/tests | 1 | No issues found |
| `./gradlew :app:testDebugUnitTest` | 1 | BUILD SUCCESSFUL |
| Native bridge vs direct rslib differential | 1 | passed（Again/Hard/Good/Easy + answer→undo→redo） |

Shipped native tests prove：camelCase queue/answer；`millisecondsTaken` 非固定 0；同一 token 第二次使用不增加该卡 revlog；undo/redo/bury/counts/congrats 走官方 Collection；空 undo/redo 返回稳定 unavailable。

Shipped Dart tests prove：flag 默认 false 且 fail-closed；生产 session `fetchLimit=1`；延迟答题 elapsed > 0；in-flight 双击只写一次；stale/unknown 不二次写；Preview 无评分控件。

## Device A debug smoke（2026-08-17，PLG110）

内部 debug APK（scheduler dart-define 全开 + 新编 arm64 1.3 `.so` `1493d32c…`）已安装。

- 导入 `08-scheduling.apkg`：`status=active`，1 张卡，`mode=worker`。
- 正式复习打开；Show Answer 后出现官方间隔标签 Again/Hard/Good/Easy。
- Good、Again 都能提交并刷新 queue；杀进程后同一 cardId 仍可打开，正面 `sched-front` 渲染成功。
- 首次打开嵌入 Preview 出现 `RENDER_TIMEOUT`；重启后 `renderMs=6`。
- **不是** 100 卡 / release / Device B。详见 `artifacts/p4/device-a-debug-smoke.txt`。

## 未通过 / 未跑的硬门禁

- Device A 100-card debug/release smoke、RSS/UI stall：**未跑**。只有 1 卡 debug smoke。
- Device B：**不可用**（`adb devices` 只有一台）。
- 跨日 / 时区 / DST：未在设备上跑。Host 覆盖 elapsed 0 / 正常 / 上限 / 负数/溢出。
- Daily limit 与 filtered deck 完整差分：未做成独立设备矩阵。Bury 在 filtered deck 上 fail-closed。
- Packaged Android `jniLibs` `.so` 仍为 contract 1.2 hash `1f0391bd31b925e13db0d27e4f6b7ee040a3372eb5804f697484157aa7d73c0c`。本次只重建了 Host `target/debug/libturna_anki.so`。
- Clean CI / 可复算 release APK：**未跑**。

因此 Technical Acceptance 与 Production 必须保持 NO-GO。不得把 Host 64/159 写成设备验收通过。

## 入口决策

见 `artifacts/p3r-p4/p4-entry-decision.txt` 与 `artifacts/p4/final-decision.txt`。
