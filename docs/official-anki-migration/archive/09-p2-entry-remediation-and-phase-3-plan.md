# P2 必要补齐 + Phase 3 课程投影实施计划

> 文档代号：P2E-P3  
> 状态：`P2/P3 HOST CONSTRUCTION GO / P2 → P3 STRICT ENTRY NO-GO / P3 CONSTRUCTION GO / P2 TECHNICAL ACCEPTANCE NO-GO / P2 PRODUCTION NO-GO`  
> 制定日期：2026-08-17  
> 当前分支：`spike/official-anki-core-android`  
> 审计基线 HEAD：`cc1484b30739bceeba07fe1a3be98b8b0e11018d`  
> 上游 Anki pin：`967aa0d578fc75181e292e95326f9b58698da25c`  
> 当前 contract：`1.1`  
> 首发平台：Android arm64  
> 前置文档：`08-phase-2-result-report.md`、`p2fix.md`  
> 明确排除：License/法律签字、官方 Scheduler、Legacy 删除、AnkiWeb Sync

## 1. 计划目的

本计划不是等待 Phase 2 全部生产门禁完成后才开始 Phase 3，也不是带着已知的 Reviewer
确定性错误直接向前施工。它定义一条受控的联合路线：

1. 先关闭会污染 P3 调试、原卡预览和设备判断的 P2 硬阻断。
2. 形成一个比“P2 Technical Go”更小但可验证的 `P2 → P3 Entry Gate`。
3. Entry Gate 通过后，在独立 feature flag 下实施 Phase 3 课程投影。
4. P2 尚未完成的安全、性能、第二设备和 release 门禁继续保留为 NO-GO，不能因 P3 开工而消失。
5. Phase 3 只读取官方 Collection，并生成可删除、可重建的 Turna 课程投影；不复制出第二套
   Anki 事实源。

当前决策：

```text
P2 DETERMINISTIC FIXES: REQUIRED
P2/P3 HOST CONSTRUCTION: GO
P2 → P3 STRICT ENTRY: NO-GO
P3 DESIGN: GO
P3 CODE CONSTRUCTION: GO
P2 TECHNICAL ACCEPTANCE: NO-GO
P2 PRODUCTION: NO-GO
```

Host/Dart/JS/Kotlin JVM 施工通过不等于 Device A 或 instrumented WebView 已验收。
严格 Entry 仍要求 Device A smoke 与 instrumented flip-path 实测；在此之前不得写无条件 `P2 → P3 ENTRY GO`。

## 2. 为什么只补齐一部分 P2

Phase 3 的课程投影主要依赖官方 Collection、分页查询、source catalog 和 CourseDatabase，
不依赖 P2 完整的恶意卡矩阵、第二设备、release 性能签字。因此可以把 P2 工作分成两组。

### 2.1 P3 开工前必须关闭

以下问题会直接破坏原卡预览、字段映射确认或产物真实性：

- 同一卡片 generation 更新后 `card-frame` 拒绝 `setCard`，导致翻面超时。
- Flutter/Kotlin 多个 `present()` 共用一个 pending result，completion 可能串线。
- 答案 UI 等待整组 AV/TTS 播放完才显示。
- WebView `renderError` 只有日志，没有可恢复 UI 状态。
- Session cleanup 没有保存 resolved native 路径，超时回收不完整。
- Android `.so` 和 APK 早于最新 Rust `display/bodyClass` 源码。
- 没有真实 WebView 的最小正面/答案/换卡自动化证明。
- 没有一台设备完成 import → reopen → render → flip 的 smoke。

### 2.2 允许与 P3 并行、但不能从 P2 报告删除

- 完整 hostile-card fixture 和外部请求计数。
- Service Worker/WebStorage/cookie 全矩阵。
- 100 次 Reviewer 创建/销毁和 RSS 预算。
- 100 卡快速切换性能采样。
- 飞行模式完整 MathJax/字体/音视频矩阵。
- 第二台 Android/WebView 设备。
- release APK、R8、release WebView debugging 验证。
- clean CI runner。
- 真实 Native 5k import cancel/recover。

上述延期项仍阻塞 `P2 TECHNICAL GO` 和 production renderer；只是不阻塞 P3 的内部施工。

## 3. 不可破坏的架构边界

### 3.1 数据所有权

```text
Official Anki Collection
  ├── Note 字段/GUID/tags
  ├── Notetype/字段定义/模板/CSS
  ├── Card/Deck/template ordinal
  ├── Scheduler/revlog/deck config
  └── collection.media
          │
          │ bounded projection query
          ▼
Official catalog（不可由 CourseDatabase 降级清空）
  ├── source/card 关联
  ├── 用户确认的字段 mapping
  ├── 用户锁定的课程位置
  └── projection job/checkpoint/error
          │
          │ deterministic rebuild
          ▼
CourseDatabase（派生缓存，可删除重建）
  ├── Section/Unit/Lesson
  ├── 精简的 Flutter practice payload
  └── official projection index
```

必须遵守：

- 官方 Collection 是唯一 Anki 内容事实源。
- 用户确认 mapping 和手动位置不是派生数据，必须放 Official catalog，不能随 CourseDatabase
  downgrade wipe 丢失。
- CourseDatabase 可以保存生成后的短文本、练习参数和媒体文件名，但不能保存完整 raw Note、
  qfmt/afmt、CSS、Scheduler 或 revlog 镜像。
- 删除 CourseDatabase 中的 official projection 后，必须能从官方 Collection + Official catalog
  完整重建。
- P3 不写官方 Scheduler，也不把 official Card 写入 Turna SRS 作为权威复习状态。
- P3 不调用 Legacy `.apkg` parser、Legacy template renderer、`AnkiDeckAssembler` 或旧
  `AnkiNoteDao` raw NoteStore 生成 official 课程。

### 3.2 运行时边界

```text
UI / mapping wizard
       │
       ▼
OfficialAnkiCourseProjectionService
       │ worker isolate only
       ▼
OfficialAnkiSession
       │ contract 1.2 paged calls
       ▼
Rust bridge → official rslib Collection
```

- FFI、字段读取、fingerprint 和大页 JSON 解码不得在 UI isolate。
- Dart 只做课程语义映射，不解析 Mustache、Cloze 模板或 qfmt/afmt。
- 映射候选只能依据字段名称、样本值、tags 和 deck path；不能从渲染 HTML 猜模板语义。
- 每次 native response 必须有大小上限；禁止一次把 5k/100k Note fields 全部返回 Dart。

## 4. P2 → P3 Entry Gate

只有本节全部通过，才能把本文状态改为 `P3 CONSTRUCTION GO`。

### P2E-000：冻结联合施工基线

记录：

- HEAD、branch、submodule SHA、dirty files。
- 当前 Host/Android `.so`、debug APK、Reviewer assets hash/mtime。
- 当前 Flutter/Kotlin/Rust 测试命令和结果。
- 当前设备型号、API、WebView version。

产物：

```text
docs/official-anki-migration/artifacts/p2e-p3/
  baseline.txt
  commands.txt
  artifact-manifest.txt
```

禁止 reset、checkout、删除用户工作树或把现有无关修改混入提交。

### P2E-001：修复 card frame generation 协议

当前错误是 `setCard` 自己也受旧 generation 相等检查约束。目标协议：

```text
setCard(new generation)
  - 必须来自 parent
  - nonce 必须匹配当前 frame session
  - generation 必须 > 已接受 generation
  - 原子替换 payload，并回复 cardAccepted

showQuestion/showAnswer
  - nonce 必须匹配
  - generation 必须 == 当前已接受 generation
  - cardId 必须 == 当前 cardId
```

规则：

- 同一卡正反面继续使用同一个 card frame。
- 新 cardId 必须销毁旧 frame，创建新 nonce。
- 旧 generation completion 必须丢弃。
- `cardAccepted` 超时后不得继续发送 show 消息。
- timeout 后允许重建一次 frame；第二次失败进入 recoverable error，不无限重试。

必须新增可执行 JS 测试，不接受只读取源码字符串：

- generation 1 question → generation 2 answer 成功。
- generation 2 后拒绝 generation 1 completion。
- cardId 改变时 frame/nonce 改变。
- 同 cardId 更新 comparison/theme 时不换 frame。
- cardAccepted timeout 不再发送 showAnswer。

### P2E-002：串行化 PlatformView present

Kotlin 不得再用单个可覆盖的 `waitingResult` 表示所有请求。实现选择：

1. 推荐：任何时刻只允许一个 active present；新 generation 到来时，旧 result 返回
   `{ok:false, code:"RENDER_SUPERSEDED"}`。
2. 每个轮询 callback 捕获自己的 request id/generation，不读取可变的全局 side/result。
3. Flutter 创建 PlatformView 时只发一次初始 present；`ready` 只表示 shell ready，不重复提交同一 payload。
4. Flutter 检查 native 返回的 `ok/code/generation/side`，而不是使用 `invokeMethod<void>` 丢弃结果。

验收：快速提交 question/answer/question，不存在悬空 Future，不存在旧 height 覆盖新页面。

### P2E-003：UI 显示与 AV/TTS 解耦

目标顺序：

```text
controller 更新 side/comparison
  → setState / present DOM
  → renderComplete
  → 启动该 side autoplay
```

- 页面启动不能等待 question audio 完成才退出 loading。
- 翻答案不能等待 answer audio/TTS 完成才显示 DOM。
- 切面时仍必须先 stop 旧 side。
- autoplay task 使用 generation；旧 task completion 不更新当前 UI。
- `replay()` 可以等待播放完成，但按钮必须有 busy/disabled 状态。
- missing media/voice 进入非致命提示，不把卡片隐藏。

### P2E-004：可恢复 render error

增加统一 UI 状态：

```text
rendering
visible
recoverableError(code, side, generation)
fatalError(code)
```

至少处理：

- `RENDER_TIMEOUT`。
- `RENDER_SUPERSEDED`。
- `MATHJAX_ASSET_MISSING`。
- `MATHJAX_TYPESET_FAILED`。
- shell/frame asset missing。
- WebView main-frame error。

recoverable UI 提供“重试当前面”和“返回”；不能只 `debugPrint`。

### P2E-005：Session cleanup 最小闭环

- Session 保存 worker 实际解析后的 native library absolute path。
- graceful dispose 和 timeout cleanup 共用同一个 close ownership token。
- cleanup isolate 增加第二层有界等待；超时后记录 orphan cleanup，不阻塞 UI Future。
- worker 已关闭 handle 时 cleanup 不重复 free。
- 增加可注入 cleanup executor/transport，以测试非零 handle、timeout 和 double dispose。
- 默认 `libraryPath == null` 的 Android 生产路径必须有测试。

本 Entry Gate 不要求完成 100 次真机生命周期，但要求 Fake 和 Host 非零 handle 路径可重复验证。

### P2E-006：重建本轮 native 和 debug APK

从当前 Rust 源码重新构建 Android arm64 `.so`，然后重新构建 APK。证据必须证明：

- `.so` mtime/hash 晚于 `display.rs`、`typed.rs`、`ops.rs`。
- contract 是预期版本，backend pin 正确。
- `RENDER_CARD` 实际响应包含 `templateOrdinal/bodyClass`。
- APK 内 stripped `.so` 来源 hash 可追溯。
- APK 内含 Reviewer assets 和 MathJax。
- Reverse fixture 第二模板实际得到 `card2`。

旧 APK `39b404...` 只能保留为 P2FIX 中间产物，不能作为本计划验收包。

### P2E-007：最小 Android instrumented 测试

新增真实 `android/app/src/androidTest/`，Entry Gate 最少覆盖：

1. shell ready。
2. question generation 1 renderComplete。
3. 同 card answer generation 2 renderComplete。
4. answer DOM 确实不同于 question DOM。
5. `card2` body class。
6. 下一 card 使用新 frame。
7. 相对 Unicode 图片请求 `/media/` 并加载成功。
8. 外部 HTTPS image 被 handler 拒绝。
9. dispose 两次不 crash。

完整 hostile-card、安全计数、性能矩阵仍留在 P2FIX-031～033。

### P2E-008：设备 A smoke

在当前主设备完成一次：

```text
official import
→ app/session reopen
→ source/card list
→ question visible
→ answer visible
→ return question
→ next card
→ relative media
→ one AV or TTS
→ one Typed Answer
→ one MathJax card
→ leave reviewer
```

记录 APK hash、`.so` hash、设备/API/WebView、flags、fixture hash、日志和失败项。

### P2E-009：Entry Gate 决策

允许的结论（已拆分，禁止再用无条件 ENTRY GO 覆盖未跑设备）：

```text
P2/P3 HOST CONSTRUCTION GO | NO-GO
P2 → P3 STRICT ENTRY GO | NO-GO
```

当前实测：HOST CONSTRUCTION GO；STRICT ENTRY NO-GO（无 Device A / instrumented WebView）。
即使 STRICT ENTRY 日后 Go，`08` 仍保持 `P2 TECHNICAL ACCEPTANCE NO-GO`，直到 P2FIX 全门禁关闭。

## 5. Phase 3 目标能力

Phase 3 完成后，用户可以：

1. 从已导入的 official source 生成 Turna 课程入口。
2. 查看 Deck/Subdeck 映射出的 Section/Unit/Lesson。
3. 查看每个 Notetype 的字段角色候选和证据。
4. 在含糊时确认 target/native/audio/example/unit/lesson 字段。
5. 生成 Flutter 原生的派生词汇/练习投影。
6. 从课程项打开对应官方原卡预览。
7. 删除并重建投影，而官方 Collection 和用户 mapping 不变。
8. 重复导入后只重建变化卡片，并保留用户确认和锁定位置。

Phase 3 不提供：

- 官方 Again/Hard/Good/Easy。
- 官方 queue/due/counts/congrats。
- Anki revlog 写入。
- Legacy source 自动转换。
- raw NoteStore 镜像。
- 自动启用 production renderer。

## 6. Phase 3 contract 1.2

### P3-010：新增只读 projection operations

在 contract `1.2` 增加 additive operations，旧 1.1 Dart 应继续忽略未知 capability：

```text
GET_PROJECTION_SCHEMAS      suggested id 24
BEGIN_PROJECTION_READ       suggested id 25
GET_PROJECTION_ROWS_BATCH   suggested id 26
```

`LIST_DECK_TREE` 已存在，但必须正式加入 Dart Engine/Session API 和 DTO，不通过旧的临时
`SEARCH_CARDS` 获取 deck 信息。

#### GET_PROJECTION_SCHEMAS

请求：

```json
{
  "notetypeIds": [123],
  "includeSamples": true,
  "sampleLimit": 3
}
```

响应中的每个 schema：

```json
{
  "notetypeId": 123,
  "name": "Basic",
  "kind": "normal",
  "fieldNames": ["Front", "Back", "Audio"],
  "templateNames": ["Card 1"],
  "schemaFingerprint": "sha256...",
  "samples": [
    {"noteId": 10, "fields": ["hello", "你好", "[sound:a.mp3]"]}
  ]
}
```

限制：

- sampleLimit 默认 3、最大 10。
- 单字段最大 8 KiB；截断必须返回 `truncated=true`。
- 不返回 qfmt、afmt、CSS、revlog 或 scheduling。
- 样本只用于 mapping wizard，不持久化为 raw Note mirror。

#### BEGIN_PROJECTION_READ

Rust bridge 看不到独立的 Official catalog，因此不能接收 `sourceId` 后假装知道来源边界。投影服务
先从 catalog 按 source 计算有序 card-set fingerprint，再开始一次只读 snapshot：

```json
{
  "cardSetFingerprint": "sha256(sorted source card ids)",
  "mappingVersion": 1
}
```

响应：

```json
{
  "snapshotToken": "opaque-token",
  "collectionGeneration": 42,
  "backendCommit": "..."
}
```

token 绑定当前 Collection generation、card-set fingerprint 和 mapping version。import、restore、
reopen 或其他会改变 Collection 的操作后，旧 token 必须返回 `PROJECTION_SNAPSHOT_STALE`。

#### GET_PROJECTION_ROWS_BATCH

请求：

```json
{
  "cardIds": [1, 2, 3],
  "snapshotToken": "opaque-token"
}
```

响应行：

```json
{
  "cardId": 1,
  "noteId": 10,
  "noteGuid": "...",
  "notetypeId": 123,
  "deckId": 456,
  "deckPath": ["Language", "Unit 1"],
  "templateOrdinal": 0,
  "tags": ["lesson::greetings"],
  "fields": ["hello", "你好", "[sound:a.mp3]"],
  "sourceFingerprint": "sha256..."
}
```

限制：

- `cardIds` 每批默认 200、最大 500；catalog DAO 按 `source_id, card_id` 分页提供，禁止先把
  5k/100k ID 全量加载进内存。
- source card allowlist 由 projection service 从 catalog `anki_source_cards` 取得；native 只接受
  明确 cardIds，不提供“不带过滤搜索全部 Card”的 P3 API。
- response 最大 8 MiB；超限缩小页或返回稳定错误。
- 每批校验 snapshot token；Collection/import 变化后返回 `PROJECTION_SNAPSHOT_STALE`。
- 响应必须列出 `missingCardIds`，不能因一张 Card 消失而静默改变计数。

#### 最终 projection fingerprint

由 projection service 对 card-set fingerprint、每行 sourceFingerprint、相关 notetype schema、
mapping version、Collection generation 和 backend commit 做确定性组合，用于判断 no-op rebuild；
不能仅使用 `.apkg` 文件 hash。

### P3-011：Native 测试

- 九套现有 fixture projection schema/row golden。
- Unicode、Reverse、Cloze、media field、empty field。
- 200/500 batch boundary、8 MiB response boundary。
- stale snapshot、未知 card、missingCardIds。
- response 不含 qfmt/afmt/css/revlog/scheduling。
- 5k fixture 分页期间内存不线性保留全部 field payload。

## 7. Official catalog v3

### P3-020：持久化 mapping、位置和 job

`OfficialAnkiDatabase` 从 schema v2 升 v3，建议新增：

```sql
CREATE TABLE anki_projection_mappings (
  profile_id TEXT NOT NULL,
  notetype_id INTEGER NOT NULL,
  schema_fingerprint TEXT NOT NULL,
  mapping_json TEXT NOT NULL,
  status TEXT NOT NULL,
  user_confirmed INTEGER NOT NULL,
  mapping_version INTEGER NOT NULL,
  updated_at_millis INTEGER NOT NULL,
  PRIMARY KEY(profile_id, notetype_id)
);

CREATE TABLE anki_projection_jobs (
  job_id TEXT PRIMARY KEY,
  source_id TEXT NOT NULL REFERENCES anki_sources(source_id),
  state TEXT NOT NULL,
  projection_version INTEGER NOT NULL,
  source_fingerprint TEXT NOT NULL,
  cursor_card_id INTEGER,
  processed_cards INTEGER NOT NULL DEFAULT 0,
  total_cards INTEGER NOT NULL DEFAULT 0,
  started_at_millis INTEGER NOT NULL,
  heartbeat_at_millis INTEGER NOT NULL,
  completed_at_millis INTEGER,
  last_error_code TEXT
);

CREATE TABLE anki_course_placement_overrides (
  source_id TEXT NOT NULL REFERENCES anki_sources(source_id),
  card_id INTEGER NOT NULL,
  section_key TEXT,
  unit_key TEXT,
  lesson_key TEXT,
  locked INTEGER NOT NULL,
  updated_at_millis INTEGER NOT NULL,
  PRIMARY KEY(source_id, card_id)
);

CREATE TABLE anki_source_projection_state (
  source_id TEXT PRIMARY KEY REFERENCES anki_sources(source_id),
  state TEXT NOT NULL,
  active_projection_version INTEGER,
  source_fingerprint TEXT,
  projected_card_count INTEGER NOT NULL DEFAULT 0,
  last_projected_at_millis INTEGER,
  active_job_id TEXT
);
```

状态：

```text
not_projected
needs_mapping
ready
projecting
active
stale
failed
cancelled
```

不得把原有 `anki_sources.state=active` 改回 importing 来表达 projection；导入生命周期和投影
生命周期必须分开。

### P3-021：mapping 保留规则

- 相同 `(profileId, notetypeId, schemaFingerprint)`：直接复用用户 mapping。
- Notetype ID 相同但 fingerprint 变化：保留旧 mapping 供对照，状态改 `needs_review`。
- 仅新增字段且已映射字段仍存在：可以生成候选迁移，但未经确认不覆盖 user-confirmed JSON。
- Notetype 被删除：mapping 保留为 orphan，不立即删除。
- 相同 card 被多个 source 引用：字段 mapping 共用，课程 placement 仍按 source 独立。

## 8. CourseDatabase v16 投影缓存

### P3-030：只增加派生索引，不增加 raw mirror

CourseDatabase 从 v15 升 v16，建议新增：

```sql
CREATE TABLE official_anki_projection_index (
  source_id TEXT NOT NULL,
  card_id INTEGER NOT NULL,
  word_id TEXT NOT NULL,
  section_id TEXT NOT NULL,
  unit_id TEXT NOT NULL,
  lesson_id TEXT NOT NULL,
  projection_kind TEXT NOT NULL,
  source_fingerprint TEXT NOT NULL,
  projection_version INTEGER NOT NULL,
  PRIMARY KEY(source_id, card_id, projection_kind)
);

CREATE UNIQUE INDEX official_anki_projection_word_source_idx
ON official_anki_projection_index(source_id, word_id, projection_kind);
```

不为 official source 写入旧表：

```text
anki_notetypes
anki_notes
anki_cards_meta
anki_prerendered_html
anki_imports
```

这些旧表继续服务 Legacy source，直到 Phase 5 单独迁移和删除。

稳定 ID：

```text
section: official-anki-<sourceId>-s<topDeckId>
unit:    official-anki-<sourceId>-u<deckPathHash>
lesson:  official-anki-<sourceId>-l<groupHash>-p<part>
word:    official-anki-<profileKey>-c<cardId>
item:    <wordId>-p<projectionKind>-<ordinal>
```

`profileKey` 是 profileId 的稳定短 hash，避免把任意 profile 文本放进 ID。`wordId` 不含
sourceId，使同一官方 Card 被多个来源关联时仍有稳定身份；P3 不为它创建权威 Turna SRS
状态。同一 Card 可以有多个 projection kind，因此 projection index 主键必须包含 kind。

### P3-031：原子发布

投影不能边生成边让 CourseProvider 看到半棵树。流程：

1. catalog 创建 job=`projecting`。
2. worker 分页读取并生成轻量 projection rows。
3. 在内存或临时表按 source 构造新 generation；不得保存完整 HTML。
4. 在单个 CourseDatabase transaction 内：
   - 删除该 source 的旧 generated sections/vocabulary/index。
   - 插入新 Section/Unit/Lesson/content/index。
   - 写 active generation marker。
5. transaction 成功后把 catalog projection state 改为 `active`。
6. CourseProvider 只在 publish 成功后 reload 一次。

删除/替换某个 source 时，共享 `word_id` 对应的 vocabulary/derived row 只有在 projection index
中已无其他 source 引用后才能删除，不能让 source A 的卸载破坏 source B。

若第 4 步失败，CourseDatabase transaction 回滚，旧 generation 继续可见；catalog job 标记
`failed`。两库之间使用 Saga，不尝试跨 SQLite ACID。

## 9. 字段角色候选与用户确认

### P3-040：角色模型

支持角色：

```text
targetText
nativeText
pronunciation
audio
image
exampleTarget
exampleNative
unitLabel
lessonLabel
optionPool
ignored
```

每个候选必须包含：

```json
{
  "role": "targetText",
  "fieldIndex": 0,
  "fieldName": "Front",
  "confidence": 0.92,
  "evidence": ["name:front", "sample:plain_text", "non_empty:3/3"]
}
```

候选算法只提供建议，不偷偷成为用户事实：

- `confidence >= 0.90` 且 target/native 不冲突：允许标为 `auto_candidate`。
- `0.60–0.90`：必须在 mapping wizard 确认。
- `< 0.60`、字段冲突、多个同分候选：`needs_mapping`。
- audio 必须从字段值中的官方 AV/media 引用识别，不能把任意 URL 当本地媒体。
- HTML 清理只用于生成短文本投影；raw field 不落 CourseDatabase。

### P3-041：mapping wizard

UI 至少显示：

- Notetype 名称、字段列表。
- 3 个以内只读样本。
- 每个角色的候选、confidence、evidence。
- 原卡预览按钮；renderer flag 不可用时明确显示“预览不可用”，不能 fallback Legacy。
- 保存、恢复自动建议、跳过此 Notetype。
- 受影响 card 数量和将生成的练习类型。

保存 mapping 后立即写 Official catalog；只有用户点击“生成课程”才发布 CourseDatabase 投影。

## 10. 课程树和练习映射

### P3-050：Deck → Section/Unit/Lesson

默认规则：

- 顶层 Deck → Section。
- 顶层以下完整 deck path → Unit；显示名使用 `Parent › Child`，避免丢失深层结构。
- 已确认 `unitLabel/lessonLabel` 字段或 `unit::/lesson::` tag 优先于固定分组。
- 没有明确 lesson 时按稳定 cardId 顺序每 20 张一 Lesson。
- 超过现有 CourseValidator 上限时沿用分片策略，但 ID 必须由稳定 key 生成，重复重建不漂移。
- missing/cyclic deck hierarchy 进入 `Recovered` Section，并写 projection issue，不能丢卡。

### P3-051：投影种类

第一阶段只实现小而可验证的集合：

| 条件 | projection kind | Flutter Interaction | 是否写官方调度 |
|---|---|---|---:|
| target + native | `flip` | 正反面短文本 | 否 |
| target + native + optionPool | `multipleChoice` | 选择题 | 否 |
| target + audio | `listenPick` | 听音选择 | 否 |
| target + native | `typeAnswer`（显式启用） | 拼写 | 否 |
| mapping 不完整 | `canonicalLink` | 打开官方原卡预览 | 否 |

规则：

- `canonicalLink` 是保底投影，不复制 raw HTML。
- derived practice payload 每 Card 默认不超过 32 KiB。
- 单个 Lesson `content_json` 建议不超过 512 KiB；超限继续分片。
- media 只保存受验证的 Collection media filename，不复制 file/content URI。
- 课程练习得分在 P3 只属于课程交互统计，不写 Anki Scheduler/revlog。

### P3-052：课程读取接入

- 扩展 `ICourseRepository`，增加按 source 删除/替换 projection 的事务 API。
- CourseProvider section shells 应把 official projection 和既有课程一起加载。
- official/legacy section ID 前缀必须不同。
- 课程项打开 canonical card 时调用 Official Reviewer router；flag/capability 缺失时 fail closed。
- 不修改现有 Legacy `AnkiReviewAssembler` 让它同时承担 official source。

## 11. Projector 状态机与恢复

### P3-060：OfficialAnkiCourseProjectionService

建议目录：

```text
lib/application/anki_official/projection/
  official_anki_projection_contract.dart
  official_anki_projection_models.dart
  official_anki_projection_mapper.dart
  official_anki_projection_projector.dart
  official_anki_projection_service.dart
  official_anki_projection_recovery.dart
  official_anki_projection_ids.dart

lib/views/anki_official/
  official_anki_mapping_page.dart
  official_anki_projection_page.dart
  official_anki_projection_error_view.dart
```

状态机：

```text
not_projected
  → scanning_schema
  → needs_mapping ── user confirm ──┐
  → ready                           │
                                    ▼
                               projecting
                                ↙       ↘
                            active     failed
                               │
             source fingerprint changes
                               ▼
                              stale
                               │
                             rebuild
```

- cancel 只停止 projection job，不撤销已成功的官方 import。
- projection 失败不得把 `anki_sources.state=active` 改成 failed。
- app 重启发现 projecting 且 heartbeat 过期时，回滚未发布 generation 并从 checkpoint 重试。
- snapshot stale 时重新计算 source fingerprint；不能从旧 cursor 盲目继续。

### P3-061：重复导入和增量重建

- source card set 相同且 projection fingerprint 相同：no-op。
- mapping version 变化：重建相关 Notetype 的 cards。
- card sourceFingerprint 变化：只重建变化 Card，并重新打包受影响 Lesson。
- deck path/placement 变化：移动受影响 Card；用户 locked placement 优先。
- card 从 source 消失：删除该 source 的 projection index；官方 Card 本体不由 P3 删除。
- 同一 Card 仍被其他 source 引用：其他 source 投影不受影响。

首版如果增量发布复杂度过高，允许“分页读取 + source 级原子全量重建”，但必须满足 5k 性能门禁，
并把真正增量作为 P3.1；不能声称已经增量完成。

## 12. Feature flags 和入口

新增：

```text
TURNA_OFFICIAL_ANKI_PROJECTION=false
TURNA_OFFICIAL_ANKI_COURSE_ENTRY=false
```

规则：

```text
allowsProjection =
  engine && import && catalogReady && runtimeCapable && projection

allowsCourseEntry =
  allowsProjection && courseEntry && sourceProjectionState == active
```

- projection 不隐式打开 renderer。
- mapping wizard 的原卡预览需要额外满足 `allowsOfficialRenderer`。
- production 默认全部 false。
- official source 失败时不得 fallback Legacy importer/renderer/projector。
- 内部设置页明确显示 contract、capability、projection state 和 fingerprint。

## 13. 测试计划

### 13.1 Rust/contract

- contract 1.1 client 对 1.2 backend 的兼容测试。
- 1.2 新 operations golden request/response。
- projection schema/row page、大小上限、stale token。
- 九 fixture + 5k fixture。
- 不返回禁止字段。
- 默认并行 `cargo test --lib` 必须稳定；修复 handle count 测试的全局竞态。

### 13.2 Dart unit

- DTO unknown fields/minor compatibility。
- mapping candidate confidence/evidence golden。
- Unicode/HTML/AV/media filename 转换。
- stable ID 与 duplicate source/card。
- 20-card lesson 分组和 CourseValidator cap。
- no-op/full rebuild/stale/cancel/recovery。
- mapping fingerprint 变化保留用户选择。
- projection payload 不包含 qfmt/afmt/css/raw fields/scheduling。

### 13.3 数据库

- Official catalog v2 → v3 保留 source/cards/attempts。
- CourseDatabase v15 → v16。
- CourseDatabase downgrade wipe 后 mapping 仍在 catalog。
- source 级 publish transaction 失败保留旧 generation。
- 删除 projection 后可重建相同稳定 ID。
- 同 card 多 source 不产生 word identity 冲突。

### 13.4 Flutter integration/widget

- mapping wizard 自动候选、冲突、保存、恢复。
- projection progress/cancel/retry。
- CourseProvider reload 后显示新 Section。
- 打开 Lesson 只加载 L2 body，不全量加载 5k cards。
- canonicalLink 在 renderer flag off 时显示受控错误。
- derived practice 不调用 Official Scheduler operations。
- official path 不调用 Legacy Anki parser/renderer。

### 13.5 Android/device

- P2 Entry instrumented 套件全绿。
- 设备 A：5k source 投影期间 UI heartbeat。
- 生成课程后浏览 Section/Unit/Lesson。
- 打开一个 derived practice 和一个 canonicalLink。
- 删除 CourseDatabase projection，再从 Collection 重建。
- 重启后 mapping 和 locked placement 保留。

## 14. 性能和容量门禁

初始门禁，设备结果必须单独记录：

| 指标 | 门禁 |
|---|---:|
| Native projection batch | ≤ 500 rows，response ≤ 8 MiB |
| mapping samples | 每 Notetype ≤ 10，默认 3 |
| 单字段投影输入 | ≤ 8 KiB，超限显式 truncated |
| 单 Card derived payload | 建议 ≤ 32 KiB |
| 单 Lesson content JSON | 建议 ≤ 512 KiB |
| 5k Card source 投影 | 设备 A ≤ 60 s，单独记录机型 |
| 投影期间 UI heartbeat | 不出现 ≥ 500 ms 的 UI isolate stall |
| 5k 投影峰值 RSS 增量 | ≤ 120 MB，且完成后回落 |
| 删除后重建 card count | 与 `anki_source_cards` 精确一致 |
| official scheduler writes | 0 |
| Legacy official-path calls | 0 |

超过建议 payload/lesson 大小时允许进一步分片，不允许静默截掉整张 Card。

## 15. 施工批次

### 批次 A：P2 Entry Gate，2～4 工程日

- P2E-000～009。
- 输出新 native、debug APK、instrumented 结果和设备 A smoke。
- 结论只允许 Entry Go/No-Go，不升级为 P2 Technical Go。

### 批次 B：P3 contract 与数据底座，3～5 工程日

- P3-010/011：contract 1.2 projection query。
- P3-020/021：Official catalog v3。
- P3-030/031：CourseDatabase v16 和原子发布。

### 批次 C：mapping 与 projector，4～7 工程日

- P3-040/041：候选算法和 mapping wizard。
- P3-050～052：课程树、练习类型、CourseProvider 接入。
- P3-060/061：projector、恢复、reimport。

### 批次 D：验收，2～4 工程日

- 全量 Rust/Dart/DB/Flutter tests。
- 5k 性能和设备 A rebuild。
- 结果报告、artifact manifest、remaining P2 debt。

预计：**11～20 工程日**。不含 P2 完整 hostile/security/lifecycle、第二设备和 release 收口。

## 16. 依赖关系

```text
P2E-000
  ├── P2E-001 ── P2E-002 ── P2E-007 ── P2E-008 ── P2E-009
  ├── P2E-003 ── P2E-004 ────────┘
  ├── P2E-005
  └── P2E-006 ────────────────────┘
                                      │ Entry Go
                                      ▼
P3-010 ── P3-011
   │
   ├── P3-020 ── P3-021
   └── P3-030 ── P3-031
                    │
            P3-040 ── P3-041
                    │
            P3-050 ── P3-051 ── P3-052
                    │
            P3-060 ── P3-061
                    │
                 P3 验收
```

允许在 P2 Entry 施工期间只做 P3 DTO/schema 设计和 fixture 准备；不得提前把 P3 生产入口接入
CourseProvider。

## 17. 每张施工票的完成格式

每个任务必须记录：

```text
ID:
commit / dirty diff hash:
changed files:
contract/schema version:
command:
result:
artifact hash:
device/webview（如适用）:
known gaps:
rollback:
```

“源码存在”“字符串断言”“Fake 通过”不能替代 Android/WebView/设备证据。

## 18. 联合退出门禁

### 18.1 P2 → P3 Entry Gate

- [ ] 同 card question → answer → question generation 全部完成。
- [ ] present 无悬空 Future、无旧 completion 覆盖。
- [ ] UI 先显示，AV/TTS 后异步播放。
- [ ] renderError 有重试/返回 UI。
- [ ] Session resolved native path 和有界 cleanup 通过。
- [ ] Android `.so`/APK 来自最新 Rust 源码。
- [ ] `templateOrdinal/bodyClass` 在 APK 真机链路出现。
- [ ] 最小 androidTest 全绿。
- [ ] 设备 A smoke 完成。

### 18.2 P3 技术门禁

- [ ] contract 1.2 projection operations 有 Rust/Dart golden。
- [ ] Official catalog v3 migration 保留 mapping。
- [ ] CourseDatabase v16 只保存派生 projection。
- [ ] mapping wizard 对冲突要求确认。
- [ ] Deck/Subdeck 稳定映射 Section/Unit/Lesson。
- [ ] 删除 projection 后可从 Collection 重建。
- [ ] reimport 保留 mapping 和 locked placement。
- [ ] 5k source 不把全部 raw HTML 写进 Lesson JSON。
- [ ] projection cancel/restart 不暴露半棵课程树。
- [ ] official scheduler write count 为 0。
- [ ] official path Legacy 调用计数为 0。
- [ ] production projection/course flags 默认 false。

允许的 Phase 3 结论：

```text
P3 TECHNICAL GO
P3 TECHNICAL CONDITIONAL GO
P3 NO-GO
```

P3 Go 不自动改变 P2 的 Technical/Production 决策。

## 19. 回滚

1. 关闭 `TURNA_OFFICIAL_ANKI_PROJECTION` 和 `TURNA_OFFICIAL_ANKI_COURSE_ENTRY`。
2. 保留 Official Collection、source catalog、mapping 和 placement overrides。
3. 删除 CourseDatabase 中该 source 的 generated tree/index。
4. 不删除 official Card/Note/media，不恢复 Legacy mirror。
5. contract capability 缺失时新 Dart fail closed；旧 1.1 client 忽略 1.2 additive operations。
6. P2 renderer 独立由 `TURNA_OFFICIAL_ANKI_RENDERER` 控制。

## 20. 建议提交切分

```text
docs(anki): define the P2 entry gate for Phase 3
fix(android): accept newer setCard generations in the card frame
fix(android): serialize reviewer present acknowledgements
fix(anki): render card sides before starting autoplay
fix(anki): surface recoverable reviewer render failures
fix(anki): bound native session orphan cleanup
build(anki): package the current official bridge for Android
test(android): exercise the minimum official reviewer flip path
feat(anki): add paged projection queries to contract 1.2
feat(anki): persist official projection mappings and jobs
feat(course): add the official Anki projection index
feat(anki): infer and confirm language field mappings
feat(anki): project official cards into stable course trees
feat(anki): recover and rebuild official course projections
test(anki): gate 5k course projection without raw mirrors
docs(anki): report Phase 3 technical results
```

每个提交只暂存明确文件，禁止 `git add .`，禁止混入当前 `pubspec.lock` 的无关依赖/镜像变化。
