# Phase 3 官方 Anki 课程投影修补结果

> 文档代号：P3FIX 结果  
> 日期：2026-08-17  
> 分支：`spike/official-anki-core-android`  
> HEAD：`cc1484b30739bceeba07fe1a3be98b8b0e11018d` + dirty worktree  
> 上游 pin：`967aa0d578fc75181e292e95326f9b58698da25c`  
> contract：`1.2`

## 决策

```text
P3 TECHNICAL NO-GO
P3 FIX CONSTRUCTION GO
P3 TECHNICAL ACCEPTANCE NO-GO
P3 PRODUCTION NO-GO
```

拆分状态（与 `09`、README、`artifacts/p2e-p3/entry-decision.txt` 一致）：

```text
P2/P3 HOST CONSTRUCTION: GO
P2 → P3 STRICT ENTRY: NO-GO
P2 TECHNICAL ACCEPTANCE: NO-GO
P2 PRODUCTION: NO-GO
```

不得把 HOST 施工通过写成无条件 `P2 → P3 ENTRY GO`。Device A 与 instrumented WebView 未跑。

## 已完成的 Host 施工

- Official catalog 按 `source_id` + 严格升序 `card_id` 分页（默认 200，最大 500）。生产入口不再接收完整 Card ID List。
- `missingCardIds`、duplicate、stale snapshot、required-role 截断 fail closed；`publish = false`，上一棵 active 树保留。
- Fingerprint 绑定 contract major/minor、backend commit、profile/source、有序 card-set、Collection generation、sorted schema、mapping version + confirmed hash、sorted card+sourceFingerprint、algorithm version。输入/行顺序变化不改变 fingerprint。
- `anki_projection_jobs` 实现 owner token、heartbeat、cancel、retry、单 writer。`cancel()` 只取消当前 job；新 job 可启动。取消不改 `anki_sources.state=active`，不删上一棵树。
- 首发恢复策略是 **全量原子重建（rebuild-from-0）**，不是增量，也不是未使用 cursor 表冒充 checkpoint resume。
- 发布是 CourseDatabase 单事务替换 tree + lesson content + projection index；active generation 只在事务成功后更新。中途 fault injection 保留旧 generation。
- placement 不能指向/删除非 official 树。删除 source A 不影响 source B、Official Collection、mapping、locked placement。
- Mapping 可确认/编辑/恢复/跳过；保存映射不触发生成课程。schema 变化进入 `needs_review`。
- audio/image 提取单个受验证媒体文件名；optionPool 解析、去重、有界。kinds 仅在 required roles 有值时发出。
- 生成 JSON 经生产 `Lesson` / `Interaction.fromJson` 往返。
- CourseProvider `load`/`reload` 会查 catalog active 状态 + CourseDatabase index（不读 staging），只展示 `allowsCourseEntry && sourceProjectionState == active` 的 official section。
- `projectSource` 在 mapping 未经用户确认（或 skip）前不发布课程树。schema fingerprint 变化进入 `needsReview` 并保留旧树。
- `ShowWordRenderer` 对 `official-canonical-link:` 走 Official Reviewer；按钮调用 shipped `OfficialAnkiCanonicalLinkView.openOfficialReviewer`，用默认 profile paths `Navigator.push` `OfficialAnkiReviewerPage`；缺能力 fail closed，不回退 Legacy。无测试专用 opener hook。
- Official Scheduler writes = 0；official-path Legacy calls = 0。
- `TURNA_OFFICIAL_ANKI_PROJECTION` / `TURNA_OFFICIAL_ANKI_COURSE_ENTRY` 默认 false。

## Android 产物

| 产物 | sha256 | 备注 |
|---|---|---|
| jniLibs `libturna_anki.so` | `1f0391bd31b925e13db0d27e4f6b7ee040a3372eb5804f697484157aa7d73c0c` | cargo-ndk 未 strip；mtime 晚于 contract/ops/projection/display/typed |
| debug APK | `7cd34748f60d0326c351631b79800f7d498b458ec9e928507a764adb519a55f5` | 不是旧包 `77cc6f…` |
| APK 内 `.so` | `8f97eb185a5d7a10d5df4fd7bb9cada5c84deb5fb52175dc0b331010904d2c65` | Gradle strip 后与 jniLibs 不同；strings 含 1.2 三操作和 pin |

APK 含 Reviewer + MathJax `tex-svg-full.js`。aarch64 `ENGINE_INFO` 可执行探针因无设备未跑；Host FFI 套件读到 `contractMajor=1`、`contractMinor=2`、capabilities 含 `GET_PROJECTION_SCHEMAS` / `BEGIN_PROJECTION_READ` / `GET_PROJECTION_ROWS_BATCH`。

## 测试

- `flutter test --no-pub test/application/anki_official test/data/schema_migration_test.dart` ×2：每次 **141 passed**
- 新增 shipped-path 测试覆盖分页、fail closed、fingerprint、job cancel、mid-publish、placement、Interaction 往返、CourseProvider flag 矩阵、mapping wizard
- `cargo test --lib` 默认并行：第 1 次 59/1（已知 `second_handle_same_path_is_locked` 竞态）；随后多次 60 passed
- `./gradlew :app:testDebugUnitTest`：BUILD SUCCESSFUL
- JS host protocol：见 scratch `js-protocol.log`
- 作用域 `flutter analyze --no-pub`：无 error。全仓 analyzer 非 Anki 债务不记为 P3 通过

instrumented 源码已改为 test-only `testSnapshot` / `testSnapshotResult`，不再读 iframe `contentDocument`，不设 `allow-same-origin`。因 `adb` 为空，10 个设备用例未执行。

## 未跑硬门禁

- Device A smoke / instrumented WebView
- 5k Device A 时间、RSS、UI stall
- release APK
- Device B
- clean CI

因此不能写 `P3 TECHNICAL GO`。

## 回滚

```text
TURNA_OFFICIAL_ANKI_PROJECTION=false
TURNA_OFFICIAL_ANKI_COURSE_ENTRY=false
```
