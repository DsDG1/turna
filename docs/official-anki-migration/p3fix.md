# Phase 3 官方 Anki 课程投影修补计划

> 文档代号：P3FIX
> 状态：Host 施工已落地；`P3 FIX CONSTRUCTION GO / P3 TECHNICAL NO-GO / P3 TECHNICAL ACCEPTANCE NO-GO / P3 PRODUCTION NO-GO`
> 制定日期：2026-08-17
> 当前分支：`spike/official-anki-core-android`
> 审计基线 HEAD：`cc1484b30739bceeba07fe1a3be98b8b0e11018d` + 当前 dirty worktree
> 上游 Anki pin：`967aa0d578fc75181e292e95326f9b58698da25c`
> 目标 contract：`1.2`
> 首发平台：Android arm64
> 输入文档：`09-p2-entry-remediation-and-phase-3-plan.md`、`08-phase-2-result-report.md`、`p2fix.md`
> 明确排除：License/法律签字、AnkiWeb Sync、Legacy 删除、Phase 4 正式 Scheduler 切流
> 生产切流：全部 P3FIX 硬门禁通过前，projection/course-entry flags 保持默认关闭

## 1. 目的

Phase 3 已经落下 contract 1.2、Official catalog v3、CourseDatabase v16、字段候选、稳定 ID、
课程投影服务和部分测试，但当前实现仍是 Host/Data foundation，不是用户可用的完整课程链路。

本计划不推翻 Phase 3 的数据所有权和只读投影方向，而是修复以下问题：

1. `09`、README 和 entry decision 对 P2 → P3 Entry Gate 的结论互相冲突。
2. Android `.so` 和 APK 早于 `projection.rs`、最新 `ops.rs`，不包含 contract 1.2 的三个投影操作。
3. `projectSource()` 接收并复制完整 Card ID List，没有从 catalog 按 source 有序分页。
4. `missingCardIds` 被忽略，可能把缺卡结果静默发布为完整课程。
5. projection fingerprint 受输入顺序影响，且没有绑定 schema fingerprint。
6. `anki_projection_jobs` 只有表，没有 job、heartbeat、cursor、恢复或 ownership 实现。
7. `cancel()` 会永久污染当前 service 实例，取消后不能安全重试。
8. 当前 mapping page 只能展示候选，不能编辑 role、查看样本、恢复建议或生成课程。
9. `listenPick`/image payload 经过短文本清理后可能丢失媒体文件名；选择题也没有可验证选项池。
10. 投影 JSON 尚未证明可被现有 Lesson/Interaction 解析，CourseProvider 和正式路由没有接入。
11. Android instrumentation 源码直接读取 sandbox iframe `contentDocument`，尚未在设备执行且存在失败风险。
12. 5k 性能、RSS、cancel/recovery、release、第二设备和 clean CI 尚无证据。

目标是把当前“代码存在、Host 单测通过”的施工状态推进到：

```text
P3 DATA/CONTRACT: VERIFIED
P3 SOURCE PROJECTION: RECOVERABLE
P3 COURSE ENTRY: END-TO-END VERIFIED
P3 TECHNICAL: CONDITIONAL GO 或 GO
```

本计划完成不自动把 P2 Renderer、Phase 4 Scheduler 或整个官方 Anki 迁移改为 Production Go。

## 2. 当前审计结论

### 2.1 现态决策

```text
P0/P1: TECHNICAL CONDITIONAL GO
P2 TECHNICAL ACCEPTANCE: NO-GO
P2 PRODUCTION: NO-GO
P3 HOST CONSTRUCTION: GO
P3 ANDROID CONTRACT 1.2: NO-GO
P3 END-TO-END COURSE FLOW: NO-GO
P3 PRODUCTION: NO-GO
```

严格按 `09` 的文字，Device A smoke 和 instrumented WebView 是 P2 → P3 Entry Gate 必过项，
因此在它们实际通过前，不得继续写无条件 `P2 → P3 ENTRY GO`。允许 P3 Host/Dart 内部施工不等于
Entry Gate 已验收。

### 2.2 已确认通过

2026-08-17 对当前工作树重新运行：

```text
flutter test --no-pub test/application/anki_official \
  test/data/schema_migration_test.dart
# 128 passed

cargo test --lib -- --test-threads=1
# 60 passed

cargo test --lib
# 60 passed

./gradlew :app:testDebugUnitTest
# 12 tests, 0 failures; BUILD SUCCESSFUL

node test/application/anki_official/js/card_frame_protocol_test.mjs
# all five protocol cases passed

flutter analyze --no-pub \
  lib/application/anki_official \
  lib/views/anki_official \
  test/application/anki_official \
  test/data/schema_migration_test.dart
# 0 errors；2 个测试 lint
```

通过项只证明 Host、Dart unit、Kotlin JVM 和 JS harness；不替代 Android WebView、设备性能或
release 验收。

### 2.3 当前产物事实

审计时记录：

```text
Android arm64 .so:
  sha256 554e5601c539e9c6cb873fec0f0806141e6adf36295c3e75dcd439021109ce32
  mtime  2026-08-17 13:59:50 +0800

debug APK:
  sha256 77cc6f8c545c80e60e199b81de5227ebc710bbe468f59c50503ed9bb8a1df306
  mtime  2026-08-17 14:08:05 +0800

projection.rs:
  mtime  2026-08-17 15:26:41 +0800

ops.rs:
  mtime  2026-08-17 15:39:03 +0800
```

Host `.so` strings 包含：

```text
GET_PROJECTION_SCHEMAS
BEGIN_PROJECTION_READ
GET_PROJECTION_ROWS_BATCH
```

当前 Android `.so` 和 APK 内 `.so` 不包含以上三个 operation。因此旧 APK 只能作为 P2E 中间
产物，不能作为 P3FIX 验收包。

### 2.4 已有实现应保留

- Official Collection 仍是 Note/Card/Deck/media 的唯一事实源。
- contract 1.2 使用 additive operation 24/25/26。
- Native projection response 不返回 qfmt、afmt、CSS、revlog、queue 或 due。
- Official catalog 保存 mapping、placement 和 projection state。
- CourseDatabase 只保存派生课程树和 projection index。
- word ID 使用 profile identity + card ID；tree ID 使用 source identity。
- source 级 publish 已放在 CourseDatabase transaction 中。
- production projection/course-entry flags 默认 false。
- official path 不调用 Legacy importer/renderer/projector。

## 3. 修补范围和红线

### 3.1 包含

- 统一 P2 Entry、P3 construction、P3 acceptance 的事实状态。
- 重建当前 contract 1.2 Android native 和 APK。
- 修通真实 Android instrumentation 与 Device A smoke。
- 增加 source-scoped、cardId 升序、常量内存的 catalog 分页。
- 修复 missing/stale/schema/fingerprint 一致性。
- 实现 projection job、heartbeat、cursor、cancel、retry 和 crash recovery。
- 完善原子发布、故障注入和安全删除边界。
- 实现可编辑 mapping wizard 和用户确认持久化。
- 生成可被现有课程框架解析的 Interaction payload。
- 接入 CourseRepository、CourseProvider、Lesson 和 Official Reviewer router。
- 完成 5k 性能、RSS、重启恢复、release、第二设备和 clean CI 证据。
- 写 P3FIX 结果报告和 artifact manifest。

### 3.2 排除

- 修改官方 Anki Scheduler、FSRS 或 revlog。
- 把课程练习分数回写到官方调度状态。
- 删除 Legacy Anki 数据或入口。
- AnkiWeb Sync。
- OHOS/iOS/桌面正式投影发布。
- 把 raw Note、qfmt/afmt/CSS 复制进 CourseDatabase。
- License、AGPL 展示、源码要约和法律签字。

### 3.3 红线

- 不 reset、checkout、清理或覆盖当前用户 dirty worktree。
- 不因为 Device 不可用而把 Android 测试写成通过。
- 不因为 Fake/Host 通过而写 P3 Technical Go。
- 不把 `List<int> cardIds` 的测试方便接口保留为生产 source 投影入口。
- 不忽略 `missingCardIds`、snapshot stale 或 payload 超限。
- 不允许 placement override 指向并删除非 official 课程树。
- 不让 mapping 自动建议在没有用户确认时成为不可逆事实。
- 不让 official projection fallback 到 Legacy parser/renderer。
- 不在 P3 写 Official Scheduler。

## 4. 目标架构

```text
Official catalog: anki_source_cards (source_id, card_id)
        │ card_id ASC，page <= 500
        ▼
Pass A: source scan
  - total count
  - ordered card-set fingerprint
        │
        ▼
BEGIN_PROJECTION_READ
        │ snapshot token
        ▼
Pass B: native row batches
  - validate missing/stale/truncated
  - map fields to confirmed roles
  - generate bounded derived items
        │
        ▼
Official catalog projection job/staging
  - job owner / heartbeat / cursor
  - derived payload only；不存 raw Note/template
        │ validated generation
        ▼
CourseRepository source-level transaction
  - replace official tree/index
  - rollback keeps previous active tree
        │
        ▼
CourseProvider → Lesson parser → Interaction
        ├── derived practice：Turna 课程统计
        └── canonicalLink：Official Reviewer router
```

发布完成后才把 `anki_source_projection_state` 指向新 active generation。读取侧永远只看到上一个
完整 generation 或新完整 generation，不能看到半棵树。

## 5. 严重度和施工顺序

| ID | 问题 | 严重度 | 阻塞 |
|---|---|---:|---|
| P3F-ARTIFACT | Android native/APK 早于 P3 源码 | P0 | Android contract 1.2、设备验收 |
| P3F-ENTRY-TRUTH | Entry GO 与未跑设备事实冲突 | P0 | 可信决策、后续报告 |
| P3F-SOURCE-PAGE | 生产入口全量接收 Card IDs | P0 | 5k/100k、source 边界 |
| P3F-MISSING | 忽略 missingCardIds | P0 | 完整性、可重建性 |
| P3F-FINGERPRINT | 顺序/schema 未绑定 fingerprint | P0 | no-op/reimport 正确性 |
| P3F-JOB | jobs 表未使用 | P0 | cancel、crash recovery、进度 |
| P3F-COURSE-WIRE | CourseProvider/Interaction 未接入 | P0 | 用户端完整链路 |
| P3F-PAYLOAD | audio/image/options 不可用或无界 | P1 | 练习正确性、容量 |
| P3F-WIZARD | mapping UI 只读 | P1 | 用户确认和冲突处理 |
| P3F-PUBLISH | 中途失败/安全删除证据不足 | P1 | 旧课程保护 |
| P3F-ANDROID-TEST | iframe 测试未运行且探针不可靠 | P1 | Reviewer 设备证据 |
| P3F-PERF | 无 5k/RSS/release/第二设备 | P1 | Technical Go |
| P3F-HYGIENE | dirty diff、文档漂移、全仓 analyzer 失败 | P2 | 合入和 CI |

P0 全部关闭前，不接 production CourseProvider。P1 全部关闭前，不写 P3 Technical Go。

## 6. 工作分解

### P3FIX-000：冻结修补基线并修正文档事实

任务：

- 记录 HEAD、branch、submodule SHA 和完整 `git status --short`。
- 记录 Host/Android `.so`、APK、contract fixtures 和 P3 源文件 hash/mtime。
- 将 P2 Entry 的结论拆成 `HOST CONSTRUCTION` 和 `STRICT ENTRY` 两个状态。
- `09`、README、entry decision 使用同一状态，不保留互相冲突的 GO/NO-GO。
- 记录当前 repo 全量 analyzer 的非 Anki error，明确 owner；不得把它写成 P3 error 已通过。
- 为本轮创建独立 evidence 目录，不覆盖 P2E/P2FIX 旧工件。

产物：

```text
docs/official-anki-migration/artifacts/p3fix/
  baseline.txt
  commands.txt
  artifact-manifest.txt
  ticket-status.txt
  device-a.txt
  device-b.txt
  performance.txt
  exit-decision.txt
```

验收：

- baseline 包含 dirty files；不以 clean tree 冒充基线。
- 所有 hash 可由命令重算。
- 文档状态和实际设备事实一致。

### P3FIX-001：重建 contract 1.2 Android native 和 APK

任务：

- 从当前 Rust 源码重建 Android arm64 `.so`。
- 重建 debug APK；后续验收阶段再构建 release APK。
- 从 APK 解包并核对实际 packaged `.so`，不能只核对 jniLibs 源文件。
- 运行 Android 或 arm64 可执行探针读取 `ENGINE_INFO`。
- 核对 backend pin、ABI、contract major/minor 和 capabilities。

硬检查：

```text
contractMajor == 1
contractMinor >= 2
backendCommit == 967aa0d578fc75181e292e95326f9b58698da25c
capabilities contains GET_PROJECTION_SCHEMAS
capabilities contains BEGIN_PROJECTION_READ
capabilities contains GET_PROJECTION_ROWS_BATCH
```

验收：

- Android `.so` mtime 晚于 `contract.rs`、`ops.rs`、`projection.rs`、`display.rs`、`typed.rs`。
- APK 内 `.so` hash 与本轮 artifact manifest 一致。
- APK 包含 Reviewer 和 MathJax assets。
- 旧 APK `77cc6f...` 不再作为 P3FIX 验收包。

### P3FIX-002：修复 Android instrumented 测试协议

当前 iframe 使用 `sandbox="allow-scripts"`，父 document 不应依赖直接读取 iframe
`contentDocument`。测试改成受控 test-only postMessage 探针：

```text
test request:  {type: "testSnapshot", generation, nonce}
test response: {type: "testSnapshotResult", generation, side,
                bodyClass, qaTextHash, mediaUrls}
```

规则：

- 探针只在 androidTest harness/test asset 中启用，不进入 production Reviewer API。
- production 卡片仍无法调用 Kotlin/Dart/Rust。
- 快照只返回摘要/hash/URL，不返回完整敏感 DOM。
- 测试不得添加 `allow-same-origin` 来绕过真实隔离模型。

instrumented 最少覆盖：

1. shell/frame ready。
2. generation 1 question 完成。
3. 同 card generation 2 answer 完成且摘要变化。
4. generation 2 后 generation 1 completion 无效。
5. `card2` body class。
6. 新 card 使用新 frame/nonce。
7. Unicode media 真正触发 `/media/` handler 并返回 200。
8. 外部 HTTPS 请求由实际 handler 拒绝，而非只调用纯函数。
9. dispose 两次不 crash。
10. MathJax 离线完成或返回稳定 recoverable error。

### P3FIX-003：完成 Device A 的 P2 Entry 前置验收

使用 P3FIX-001 的同一个 APK：

```text
official import
→ app/session reopen
→ source/card list
→ question
→ answer
→ question
→ next card
→ Unicode relative media
→ AV/TTS
→ Typed Answer
→ MathJax
→ leave/re-enter reviewer
```

记录：

- APK/.so/fixture hash。
- device、API、ABI、WebView version。
- 所有相关 dart-defines。
- 日志、截图或 machine-readable instrumentation result。
- 每个失败项和是否可重试。

P3FIX-002/003 未通过时，严格 P2 Entry 继续 NO-GO，但不回滚已经完成的 Host P3 代码。

### P3FIX-010：实现 source-scoped catalog cursor

生产 API 不再要求调用方构造完整 `List<int>`。新增 DAO 能力：

```dart
Future<OfficialAnkiSourceCardPage> pageSourceCardIds({
  required String sourceId,
  int? afterCardId,
  int limit = 200,
});
```

约束：

- SQL 必须包含 `WHERE source_id = ? AND card_id > ? ORDER BY card_id LIMIT ?`。
- limit 默认 200，最大 500。
- Card ID 严格递增；重复或逆序返回稳定错误。
- Pass A 分页扫描得到 total count 和 ordered card-set fingerprint。
- Pass B 使用同一 source 再分页，并按 batch 调 native rows API。
- 生产路径不得出现 `List.from(allCardIds)`。
- 可以保留显式 ID helper 供 unit test，但必须命名为 test/diagnostic API，不能被 composition root 使用。

验收：

- 0、1、199、200、201、500、501、5k Card 边界。
- 两个 source 有重叠 Card ID 时互不越界。
- 输入/数据库顺序变化不改变 fingerprint。
- 记录分页时的峰值 ID buffer，必须不超过 500。

### P3FIX-011：修复 missing、snapshot 和 fingerprint 一致性

`missingCardIds` 非空时默认 fail closed：

```text
PROJECTION_SOURCE_CHANGED
recoverable = true
publish = false
old active projection remains visible
```

允许一次完整 source rescan + 新 snapshot 重试；第二次仍缺卡则结束 job，不无限循环。

最终 fingerprint 必须按稳定顺序组合：

```text
contract major/minor
backend commit
profile/source identity
ordered card-set fingerprint
Collection generation
sorted(notetypeId + schemaFingerprint)
mapping version + confirmed mapping JSON hash
sorted(cardId + sourceFingerprint)
projection algorithm version
```

规则：

- schema 变化且 confirmed mapping 不再有效时进入 `needs_mapping`/`needs_review`，不得静默 no-op。
- truncated 字段必须进入 issue；若影响 required role，阻止对应 derived kind，不生成错误练习。
- snapshot stale 不能从旧 cursor 继续。
- rows 数、missing 数和 catalog source count 必须对账。
- duplicate row/cardId 是错误，不使用后写覆盖。

### P3FIX-012：补齐 Native/contract 1.2 边界测试

新增或扩展：

- 旧 1.1 client 对 1.2 backend 的 additive compatibility。
- operation 24/25/26 request/response golden。
- Unicode、Reverse、Cloze、media、empty field 九 fixture。
- sample limit 0/1/3/10/11。
- field 8 KiB UTF-8 边界和多字节截断。
- batch 0/1/200/500/501。
- response 8 MiB 边界。
- missing、duplicate request ID、unknown Card。
- import/reopen/restore 后 stale token。
- response forbidden-key recursive scan。
- 默认并行 `cargo test --lib` 连续运行至少三次。

fixture 缺失时测试不得直接 `return` 后记成通过；必须显式 skip 并在结果报告列出，或把 fixture
作为测试前置硬失败。

### P3FIX-020：实现 ProjectionJobRepository 和状态机

在现有 `anki_projection_jobs` 上实现 repository，不允许 service 直接散落 raw SQL 更新状态。

状态：

```text
created
→ scanning_source
→ scanning_schema
→ needs_mapping
→ projecting
→ publishing
→ active

created/scanning/projecting/publishing
  ├── cancel_requested → cancelled
  ├── recoverable error → retry_wait
  └── fatal error → failed
```

每次状态转换写：

- job ID 和 owner token。
- source ID、projection version、algorithm version。
- cursor card ID、processed/total。
- source/card-set/schema/mapping fingerprint。
- started、heartbeat、completed timestamp。
- retry count、last stable error code。

并发规则：

- 同一 source 只允许一个 active writer job。
- 新 job 不能覆盖另一 owner 的 heartbeat/cursor。
- app 重启发现 stale heartbeat 时先标记 abandoned，再决定重试。
- `cancel()` 只取消当前 job；新建 job 后 cancel token 必须重置。
- cancel 不改变 `anki_sources.state=active`，也不删除上一个 active projection。

### P3FIX-021：增加有界 derived staging 和恢复

如果要从 cursor 恢复，不能只把所有 projected items 留在 Dart List。Official catalog 升级时增加
临时派生 staging（建议 schema v4）：

```sql
CREATE TABLE anki_projection_job_items (
  job_id TEXT NOT NULL,
  card_id INTEGER NOT NULL,
  projection_kind TEXT NOT NULL,
  section_id TEXT NOT NULL,
  unit_id TEXT NOT NULL,
  lesson_id TEXT NOT NULL,
  source_fingerprint TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  PRIMARY KEY(job_id, card_id, projection_kind)
);
```

规则：

- staging 只存 bounded derived payload，不存 raw fields、qfmt/afmt/CSS/scheduling。
- 每批 staging + cursor 在同一 catalog transaction 中提交。
- 重启后重新建立 native snapshot，并重算/复核 cursor 前滚动 fingerprint；不一致则清空 staging 从 0 重建。
- completed/cancelled/failed job 按保留策略清理 staging。
- staging 不是用户课程事实源，CourseProvider 永远不能读取它。

如果评估后决定 P3 首版不支持 cursor resume，必须删除“从 checkpoint 恢复完成”的声明，明确实现
为“安全从 0 重建”；不能留下未使用 jobs/cursor 表冒充恢复能力。

### P3FIX-022：强化原子发布和安全删除

把数据库写入收敛为 CourseRepository source-level API：

```dart
Future<void> replaceOfficialProjection(...);
Future<void> deleteOfficialProjection(String sourceId);
Future<OfficialProjectionSummary> readOfficialProjectionSummary(...);
```

要求：

- tree、lesson content、projection index 在一个 CourseDatabase transaction 中替换。
- active projection state 只在 Course transaction 成功后更新。
- 增加 mid-transaction fault injection，而不是只在进入 `_publish()` 前返回 failed。
- 任意插入点失败后，旧 tree/index/content 精确保留。
- 删除前验证 section/unit/lesson ownership；ID 必须是当前 source 的 official namespace。
- placement override 保存 logical placement key，再派生 source-scoped ID；不得接受任意现有课程 ID。
- 删除 source A 不影响 source B，即使 Card/word identity 重叠。
- 删除 projection 不删除 Official Collection Card、mapping 或 locked placement。

### P3FIX-030：完善 mapping domain 和校验

confirmed mapping 至少包含：

```text
notetypeId
schemaFingerprint
mappingVersion
role → fieldIndex
direction
enabled projection kinds
userConfirmed
updatedAt
```

校验：

- target/native required role 不能指向同一字段，除非用户明确选择单字段模式。
- field index 必须在当前 schema 范围。
- audio/image role 必须经过官方 media 引用识别。
- optionPool 定义分隔规则或结构来源，不能把任意长文本直接当选项数组。
- schema fingerprint 改变时映射进入 needs review，不自动发布。
- 保存相同 mapping 不增加 version；真实改变才增加。
- skip Notetype 是显式持久化状态，reimport 后不反复弹出。

### P3FIX-031：实现完整 Mapping Wizard

页面至少包含：

- Notetype 名称、字段列表和受影响 Card 数量。
- 最多三个只读样本；显示 truncated 标记。
- 每个 role 的字段选择、confidence 和 evidence。
- target/native 冲突即时校验。
- 将生成的 flip/multipleChoice/listenPick/typeAnswer/canonicalLink 预览。
- “恢复自动建议”“保存映射”“跳过 Notetype”三个独立动作。
- 原卡预览按钮；renderer flag/capability 不满足时 fail closed。
- 所有 Notetype ready 后单独显示“生成课程”，保存 mapping 不能隐式发布。

widget/integration 测试覆盖：

- auto candidate。
- needs confirm。
- no valid target/native。
- schema changed。
- restore suggestion。
- skip/reopen。
- preview unavailable。
- 保存后 catalog JSON/version 正确。

### P3FIX-040：生成可用且有界的 Interaction payload

不得对所有 role 统一调用 `shortText()`。

按 role 处理：

- target/native/example：HTML → bounded plain text。
- audio：从官方 AV tag 或受验证 `[sound:filename]` 提取单段 media filename。
- image：从受验证 media reference 提取 filename，不保存 file/content/http URL。
- optionPool：解析、去空、去重并限制数量/长度。
- pronunciation：保留 bounded plain text。
- canonicalLink：只保存 sourceId/cardId，不保存 raw HTML。

练习规则：

- `flip`：target/native 都非空。
- `multipleChoice`：至少一个正确项和足够的确定性唯一干扰项；不足则不生成该 kind。
- `listenPick`：可用 audio + target + 足够选项；audio 为空不得生成。
- `typeAnswer`：用户显式启用且答案非空。
- `canonicalLink`：mapping 不完整时的保底入口。

容量硬门禁：

```text
single derived item UTF-8 JSON <= 32 KiB
single lesson content UTF-8 JSON <= 512 KiB
lesson over limit → deterministic split
```

超限必须写 projection issue；不允许截断整个 Card 后继续声称成功。

### P3FIX-041：适配现有课程 Interaction 模型

为每种 projection kind 编写明确 adapter，输出必须由现有生产解析器反序列化，而不是测试自定义
`contentJson.contains(...)`。

验收：

- 生成 Lesson JSON 后，通过真实 Lesson/Interaction parser round-trip。
- widget renderer 能显示 flip、multipleChoice、listenPick、typeAnswer。
- canonicalLink 使用单独 interaction/action，不伪装成 Legacy Anki item。
- item ID 使用稳定 `wordId + kind + ordinal`。
- 同一卡多个 kind 不发生主键或进度 key 冲突。
- 课程得分只写 Turna 课程统计，Official Scheduler write counter 始终为 0。

### P3FIX-042：接入 CourseRepository、CourseProvider 和路由

接入顺序：

```text
source active projection
→ CourseRepository 加载 official section shells
→ CourseProvider 合并既有课程
→ 打开 Unit/Lesson 时按需加载 body
→ derived Interaction 或 canonicalLink
→ canonicalLink 进入 Official Reviewer router
```

规则：

- 只有 `allowsCourseEntry && sourceProjectionState == active` 才显示 official section。
- projection flag 开、course-entry flag 关时允许后台生成，但不显示课程入口。
- course-entry flag 开、projection inactive 时 fail closed，不显示半成品。
- official/legacy/bundled section ID namespace 不冲突。
- Provider 不加载 5k raw body，只按现有 L1/L2 分层策略加载。
- canonicalLink renderer 不可用时显示受控错误，不 fallback Legacy。
- 删除 projection 后 Provider reload 能移除 section。

端到端 widget/integration：

```text
import source
→ mapping wizard
→ generate course
→ provider reload
→ section/unit/lesson visible
→ derived exercise visible
→ canonical card opens Official Reviewer
→ delete/rebuild keeps stable IDs
```

### P3FIX-050：reimport、mapping 和 placement 恢复

覆盖：

- 相同 source/card/schema/mapping：no-op。
- mapping version 变化：重建受影响内容。
- sourceFingerprint 变化：安全全量重建；增量优化可留 P3.1。
- deck path 变化：未锁定 placement 更新，locked placement 保持。
- Card 消失：本 source index 删除；其他 source 不受影响。
- Notetype schema 变化：进入 needs review，旧 active projection 保留至用户确认。
- app 在 projecting/publishing 阶段被杀：重启后不暴露 staging/半棵树。
- CourseDatabase 被重建：Official catalog mapping/placement 保留，可重建相同稳定 ID。

必须明确首版能力：若仍是 source-level full rebuild，结果报告写“全量原子重建”，不得写“增量完成”。

### P3FIX-060：性能、容量和无副作用计数

设备 A 门禁：

| 指标 | 门禁 |
|---|---:|
| Native batch | 1–500 rows |
| 单 response | <= 8 MiB |
| mapping sample | 默认 3，最大 10 |
| ID page buffer | <= 500 |
| 单 item payload | <= 32 KiB |
| 单 Lesson JSON | <= 512 KiB |
| 5k source projection | <= 60 s |
| UI isolate stall | 不出现 >= 500 ms stall |
| 峰值 RSS 增量 | <= 120 MB，完成后回落 |
| publish count | 与有效 source Cards 精确一致 |
| Official Scheduler writes | 0 |
| Legacy official-path calls | 0 |

另记录：

- schema scan、native rows、mapping、staging、publish 分段耗时。
- cancel latency。
- crash recovery/restart latency。
- delete/rebuild 时间。
- 100 次 no-op/rebuild 后 staging/job 残留数。

### P3FIX-061：联合测试、release、第二设备和结果报告

执行：

```text
Rust fmt/clippy/test
Dart scoped analyze
Flutter official + schema + CourseProvider/Interaction tests
Kotlin JVM tests
Android connected instrumentation
debug APK Device A
release APK Device A
debug/release Device B（不同 WebView/API）
clean CI runner
```

产物：

```text
docs/official-anki-migration/10-phase-3-fix-result-report.md
docs/official-anki-migration/artifacts/p3fix/artifact-manifest.txt
docs/official-anki-migration/artifacts/p3fix/exit-decision.txt
```

结果只允许：

```text
P3 TECHNICAL GO
P3 TECHNICAL CONDITIONAL GO
P3 TECHNICAL NO-GO
```

设备、release、性能或恢复硬门禁缺失时不能写 GO。

## 7. 依赖关系

```text
P3FIX-000
  ├── P3FIX-001 ── P3FIX-002 ── P3FIX-003
  │
  ├── P3FIX-010 ── P3FIX-011 ── P3FIX-012
  │                         │
  ├── P3FIX-020 ── P3FIX-021 ── P3FIX-022
  │                         │
  └── P3FIX-030 ── P3FIX-031
                    │
              P3FIX-040 ── P3FIX-041 ── P3FIX-042
                    │                       │
                    └──── P3FIX-050 ────────┘
                              │
                         P3FIX-060
                              │
                         P3FIX-061
```

允许 P3FIX-001～003 与 P3FIX-010～022 并行施工，但正式 CourseProvider 接入必须等待 source
一致性、job ownership 和原子发布测试通过。

## 8. 建议施工批次和工期

### 批次 A：事实与 Android 同代产物，2～4 工程日

- P3FIX-000～003。
- 输出一致的 Entry 状态、新 Android `.so`/APK、instrumented 和 Device A 证据。

### 批次 B：source 一致性和 job/recovery，4～7 工程日

- P3FIX-010～012。
- P3FIX-020～022。
- 输出可恢复、可取消、不会发布缺卡/半棵树的 projection service。

### 批次 C：mapping、payload 和课程接入，5～8 工程日

- P3FIX-030/031。
- P3FIX-040～042。
- 输出 import → mapping → generate → course → reviewer 的内部端到端链路。

### 批次 D：重建和联合验收，3～6 工程日

- P3FIX-050/060/061。
- 输出 5k、release、第二设备、clean CI 和结果报告。

预计：**14～25 工程日**。不含 License、Phase 4 Scheduler、Legacy 删除和 AnkiWeb Sync。

## 9. 每张施工票的完成格式

```text
ID:
owner:
baseline HEAD / dirty diff hash:
changed files:
contract/catalog/course schema version:
commands:
unit/host result:
android/device result:
artifact hashes:
performance（如适用）:
known gaps:
rollback:
decision:
```

规则：

- 源码存在不是完成。
- Fake 通过不是 Native 通过。
- Host 通过不是 Android 通过。
- androidTest 源码存在不是 instrumented 通过。
- debug APK 构建成功不是 release 或设备通过。
- 单次 happy path 不是 cancel/recovery/atomic publish 通过。

## 10. 测试矩阵

| 能力 | Unit/Fake | Host Native | Android JVM | Android instrumented | Device E2E |
|---|---:|---:|---:|---:|---:|
| contract 1.2 ops | 必须 | 必须 | n/a | 必须 | 必须 |
| source cursor/page | 必须 | n/a | n/a | n/a | 5k 必须 |
| missing/stale | 必须 | 必须 | n/a | 可选 | 必须 |
| job/cancel/recovery | 必须 | 可选 | n/a | 可选 | 必须 |
| atomic publish rollback | 必须 | n/a | n/a | n/a | 重启验证 |
| mapping wizard | 必须 | n/a | n/a | n/a | 必须 |
| Interaction round-trip | 必须 | n/a | n/a | n/a | 必须 |
| canonical Reviewer | 必须 | 必须 | 必须 | 必须 | 必须 |
| media/MathJax | 必须 | 必须 | 必须 | 必须 | 必须 |
| 5k/RSS/UI heartbeat | 可选 | 指标 | n/a | 可选 | 必须 |
| release/第二设备 | n/a | n/a | n/a | 必须 | 必须 |

## 11. 联合退出门禁

P3R-000 对账（2026-08-17）：勾选 = Host 施工已有命令/测试证据。未勾选 =
Device/CI 硬门禁或 P3R 发现的 Host 缺口。不得把 Host 勾选读成 Device GO。

### 11.1 Android/P2 Entry 前置

- [x] Android APK 内 native 来自当前 contract 1.2 源码。 *(Host 重建；设备探针未跑)*
- [x] APK `ENGINE_INFO` 含三个 projection capabilities。 *(strings/Host FFI；设备探针未跑)*
- [ ] instrumented question/answer/new-card/media/MathJax/dispose 全绿。
- [ ] Device A import → reopen → render → flip smoke 全绿。
- [x] `09`、README、entry decision 状态一致。 *(HOST CONSTRUCTION GO / STRICT ENTRY NO-GO)*

### 11.2 Source/contract

- [x] 生产 projection 从 catalog 按 source/cardId ASC 分页。
- [x] 单页不超过 500，生产路径不构造完整 Card ID List。
- [x] missing/duplicate/stale 全部 fail closed，旧 projection 保留。
- [x] fingerprint 绑定 schema、mapping、backend、algorithm 和稳定 Card 顺序。
- [x] contract 1.2 边界和九 fixture 有真实测试证据。

### 11.3 Job/发布

- [ ] 同 source 单 writer ownership 成立。 *(different-owner 成立；same-owner `needs_mapping` 会再插一条 — P3R)*
- [x] cancel 后可以创建新 job。
- [x] stale heartbeat/crash 能安全恢复或从 0 重建。
- [x] staging 不含 raw Note/template/scheduling，且完成后清理。
- [x] mid-publish failure 精确保留旧 tree/index/content。
- [x] placement override 不能删除非 official 课程树。

### 11.4 Mapping/课程

- [x] mapping wizard 可编辑、保存、恢复、跳过并显示样本/影响数。 *(widget；无生产 source 页 — P3R)*
- [x] schema 变化要求 review，不静默发布。
- [x] audio/image/options 使用受验证、bounded payload。
- [x] 所有生成 JSON 通过真实 Interaction parser round-trip。
- [x] CourseProvider 只显示 active official projection。 *(catalog+index 拼接；P3R 改 manifest)*
- [x] canonicalLink 进入 Official Reviewer，缺能力时 fail closed。 *(打开成立；返回不提交 — P3R)*
- [x] 删除/rebuild 后稳定 ID、mapping 和 locked placement 保留。

### 11.5 性能和发布

- [ ] 5k Device A 时间、RSS、UI heartbeat 达标。
- [x] Scheduler write count = 0。 *(Host 计数器)*
- [x] Legacy official-path calls = 0。 *(Host 计数器)*
- [ ] debug/release Device A 通过。
- [ ] 第二设备/WebView 通过。
- [ ] clean CI runner 通过。
- [x] production flags 默认 false。
- [x] P3FIX 结果报告和 artifact manifest 完整。

## 12. 回滚

### 12.1 功能回滚

```text
TURNA_OFFICIAL_ANKI_PROJECTION=false
TURNA_OFFICIAL_ANKI_COURSE_ENTRY=false
```

关闭后：

- 不启动新 projection job。
- CourseProvider 不显示 official projection section。
- Official Collection、source catalog、mapping 和 placement 保留。
- 已生成 CourseDatabase projection 可保留待恢复，也可通过 source-scoped API 删除。
- Legacy 现有路径不受影响。

### 12.2 数据回滚

- CourseDatabase 是派生缓存，可删除指定 source projection 后重建。
- catalog mapping/placement 不是派生缓存，不随 CourseDatabase 清理。
- abandoned job/staging 可清理，但必须先验证 owner/state，不按宽泛 glob 或 source 前缀删除。
- schema downgrade 必须有 migration test；不能手工删除用户数据库证明“可回滚”。

### 12.3 代码回滚

- contract 1.2 operation 编号不得重排或复用。
- 回滚 UI/课程入口时保留 DTO/数据库向后兼容读取。
- 不回滚到全量 Legacy 解析 official source。
- 不删除 P2 Reviewer 修补代码或现有用户工作树。

## 13. 建议提交切分

1. `docs(anki): freeze p3fix baseline and normalize entry status`
2. `build(anki): rebuild contract 1.2 android native and apk`
3. `test(anki): run sandbox-safe reviewer instrumentation`
4. `feat(anki): page official source cards with a bounded cursor`
5. `fix(anki): fail closed on missing rows and bind projection fingerprint`
6. `test(anki): complete projection contract boundary fixtures`
7. `feat(anki): persist projection job ownership and recovery`
8. `feat(anki): stage bounded derived projection items`
9. `fix(anki): make source publish atomic and ownership-safe`
10. `feat(anki): implement editable official field mapping wizard`
11. `fix(anki): validate bounded media and practice payloads`
12. `feat(anki): adapt official projections to course interactions`
13. `feat(anki): expose active official sections through course provider`
14. `test(anki): verify reimport cancel crash and stable rebuild`
15. `test(anki): record p3fix device performance and release evidence`
16. `docs(anki): publish phase 3 fix result and decision`

每个提交只处理一个可回滚主题；不要把 `pubspec.lock` 镜像漂移、非 Anki analyzer 修复或其他用户
修改混入 P3FIX 提交。

## 14. 最终完成定义

P3FIX 只有在以下事实同时成立时才完成：

1. Android 运行的是与当前源码一致的 contract 1.2 native。
2. 投影严格限定 source、稳定分页、缺卡/过期时不发布。
3. job 可以取消、重试、恢复，且永远不暴露半棵课程树。
4. 用户能确认 mapping，并明确触发课程生成。
5. 生成 payload 能被现有课程框架真实解析和渲染。
6. official section 能由 CourseProvider 加载，canonicalLink 能进入 Official Reviewer。
7. reimport/delete/rebuild 保留 mapping、placement 和稳定 ID。
8. 5k、release、第二设备、clean CI 有可复算证据。
9. Official Scheduler 写入为 0，official path Legacy 调用为 0。
10. 所有 production flags 仍默认 false，结果报告给出真实 GO/NO-GO。

在此之前，正确状态始终是：

```text
P3 FIX CONSTRUCTION GO
P3 TECHNICAL ACCEPTANCE NO-GO
P3 PRODUCTION NO-GO
```
