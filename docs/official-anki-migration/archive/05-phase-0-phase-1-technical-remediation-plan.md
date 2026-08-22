# Phase 0 + Phase 1 技术修补与收口计划

> 状态：已实施（技术结论见 `06-phase-0-phase-1-technical-remediation-result.md`）  
> 制定日期：2026-08-16  
> 范围：Phase 0 技术 Spike、Phase 1 稳定 Engine 与官方导入  
> 明确排除：License、AGPL 展示、源码要约、法律确认及其签字  
> 目标结论：`TECHNICAL GO` 或保留有证据的 `TECHNICAL CONDITIONAL GO`  
> 生产切流：修补完成前保持关闭

## 1. 目的

Phase 0 已证明官方 Anki `rslib` 在 Host 和 Android arm64 上具有技术可行性，Phase 1
也已经建立 contract、Engine、catalog、Saga 和 feature flag 的代码骨架。但当前两份
结果报告把“Host/Fake 测试通过”“代码存在”和“真实 Android 生产链路完成”混在了一起。

本计划不重做迁移架构，而是修补以下缺口：

1. 让 C ABI 的内存和请求生命周期真正安全。
2. 让 stable Engine 真实加载并调用 `.so`，而不是只接受测试注入函数。
3. 让长任务运行在真正的 worker isolate，并且导入期间仍可查询进度和取消。
4. 让 contract v1 无法被 raw Spike payload 绕过。
5. 让 backup、Saga、cursor 和 catalog 在崩溃及 100k 规模下可信。
6. 用真实 Native Engine 重跑官方 fixture，而不是用 Fake Engine 模拟 Note/Card 数。
7. 关闭 release APK、真机、干净 CI、性能和体积门禁。
8. 修正 Phase 0/1 文档中的重复、矛盾和高估结论。

修补完成后仍不代表 License 已经完成。技术结论与 License/法律结论必须分别记录；即使
最终得到 `TECHNICAL GO`，对外发布仍需经过计划外的 License 门禁。

## 2. 范围边界

### 2.1 本计划包含

- Phase 0：P0-000、P0-003、P0-004、P0-008、P0-010、P0-011、P0-013 的技术缺口。
- Phase 1：P1-000～P1-014、P1-016、P1-017 的未闭合或被高估部分。
- P1-015 中纯技术性的上游 patch replay、pin/metadata 一致性检查。
- C1 Android 构建和真机闭环。
- C2 native 体积测量与产品技术决策。
- C5 上游 patch 可重复应用。

### 2.2 明确排除

- P0-012/P1-015 中的 License、AGPL、About 展示、source offer 和法律确认。
- Phase 2 正式安全 WebView、媒体 origin、MathJax 和 reviewer UI。
- Phase 3 完整课程投影。
- Phase 4 正式 Scheduler UI、真实答题耗时和完整 review session。
- Legacy 数据迁移/删除。
- AnkiWeb Sync。
- OHOS/iOS/桌面适配。

现有 License 代码不需要删除或回退，只是不作为本计划的施工内容和技术完成判据。

### 2.3 数据与行为红线

- official feature flags 保持默认关闭。
- 不删除、reset 或 checkout 当前大量未提交改动。
- 不删除 Legacy importer、renderer、SRS 或数据库表。
- 不让 Dart 读取官方 Collection SQLite。
- 不修改官方 Collection schema。
- official 失败不得自动转 Legacy。
- 不用旧 APK、旧 `.so` 或 Fake Engine 结果替代新产物验收。
- 不把 Host 通过写成 Android 通过。

## 3. 当前真实状态

### 3.1 已确认通过

- Anki submodule 固定在 `967aa0d578fc75181e292e95326f9b58698da25c`。
- Host `cargo fmt --check`、`clippy -- -D warnings` 通过。
- 当前工作树 Rust 33 tests 通过。
- 当前工作树 `test/application/anki_official` 48 tests 通过。
- Host import/render/queue/Good/Undo/cancel/100k 闭环存在。
- Android arm64 `.so` 可以交叉编译。
- debug APK 曾包含 16,078,224 字节的 `libturna_anki.so`。
- contract、catalog、Saga、recovery、feature flag 已有代码骨架。

### 3.2 上述通过不能证明的事情

- 33 个 Rust test 不证明 Dart stable Engine 能调用真实 `.so`。
- 48 个 Flutter test 中的导入/Saga 测试使用 `FakeOfficialAnkiEngine`，不证明官方
  `rslib` 实际导入结果能穿过 Dart contract 写入 catalog。
- `OfficialAnkiWorker` 当前是同 isolate 的 `Queue<Future<void>>`，不是持久 worker
  isolate；同步 FFI 仍可能阻塞 UI，也无法在同 isolate 的长调用中处理 cancel。
- `FfiOfficialAnkiEngine` 当前要求外部注入 `nativeCall`，仓库中没有 production
  `DynamicLibrary` factory、handle 管理或 DI 组装。
- 生产 `anki_import_screen.dart` 没有向 facade 传入 official orchestrator；flag 打开时
  只会 fail closed，并不能完成真实 official import。
- 当前 debug APK 与 jniLibs `.so` 均早于最新 ABI/contract/Saga 修补，不是最终证据。
- release APK 是旧包且不含 `.so`。
- 当前没有 ABI 修补后真机证据。

### 3.3 新发现的阻塞级问题

| ID | 问题 | 影响 |
|---|---|---|
| T-ABI-LIFE | `request_bytes<'a>()` 返回与输入无生命周期关系的任意 `'a` | 仍可被推断为过长生命周期，当前“非 static”修补不完整 |
| T-FFI | Stable Engine 没有真实 DynamicLibrary/handle 实现 | Phase 1 production Engine 实际不可用 |
| T-WORKER | Worker 只是同 isolate async queue | 导入可卡 UI，进度/取消无法在阻塞期间可靠执行 |
| T-CONTRACT | Native 对无 envelope 请求回退 raw Spike payload | contract v1 可绕过；正式与实验接口未真正隔离 |
| T-BACKUP | Collection 打开时直接 `fs::copy(collection.anki2)` | SQLite/WAL snapshot 可能不一致，不能作为恢复 checkpoint |
| T-FAKE | Dart fixture/Saga 测试全部使用 Fake Engine | 没有 Dart→FFI→rslib→catalog 的真实集成证据 |
| T-SAGA-N2 | `_indexCards` 累积 descriptors 后每批重写全部历史数据 | 导入索引趋近 O(N²)，100k 风险严重 |
| T-CURSOR | cursor 保存 batch 起点，恢复时仍从 0 开始 | “resume”实际是全量重跑，不是真正断点续传 |
| T-JOURNAL | 全部 imported Note IDs 存在单行 JSON | 100k journal 过大，更新/解码/崩溃恢复成本不可控 |
| T-TOKEN | `nativeImportToken` 只是 handle+elapsed 拼接值 | 不是官方持久 token，不能证明崩溃后的导入结果 |
| T-DB | catalog 建表无整体 transaction，且同步 sqlite 在调用 isolate 执行 | 半迁移和 UI 阻塞风险 |
| T-PAGE | 每一页重新 materialize/sort 全部 Card IDs | 多页遍历会重复 O(N)，100k 查询成本放大 |
| T-AV | 官方 `q_tags/a_tags` 被丢弃，重新手扫 `[sound:]` | TTS/复杂 AV 语义不等于官方实现 |
| T-CI | 无 official Anki CI job | pin、patch、metadata、Host/Android 构建不可持续验证 |
| T-DOC | Phase 0 重复章节、勾选矛盾；Phase 1 结果高估 | 不能据此做可靠阶段决策 |

## 4. 修补完成定义

除 License 外，以下全部通过才可写 `TECHNICAL GO`：

| 类别 | 硬门禁 |
|---|---|
| 工作树 | 修补代码形成可追溯的 scoped commits；不夹带无关改动 |
| ABI | 无 unconstrained lifetime；buffer 分配/释放一致；panic 不跨 FFI |
| Contract | stable call 强制 envelope；operation name/id 一致；runtime metadata 真实 |
| Stable Engine | production factory 能加载 `.so`、创建 handle、调用、释放、close |
| Worker | Native/JSON/catalog 长任务不在 UI isolate；运行中 progress/cancel 可响应 |
| Backup | 使用官方/SQLite 一致性方案；恢复后 Collection check/open 通过 |
| Saga | batch O(N)；cursor 真续跑；100k journal 分块；异常状态持久化 |
| Real integration | 9 fixtures 至少在 Host Dart FFI 和 Android 真机走真实 Engine |
| AV | 使用官方 typed AV/TTS tags，不再手工扫描 `[sound:]` |
| Android | 新 debug/release APK 均包含新 `.so`，两类 arm64 设备闭环通过 |
| Performance | with/without native 同模式对比；5k/100k、RSS、冷启动、取消均有数据 |
| C2 | native 体积方案得到产品技术确认 |
| CI | clean runner 运行 Host、Dart FFI、contract、pin/patch 和 arm64 APK inspection |
| 文档 | Phase 0/1 报告与真实证据一致，不重复、不把未测写通过 |

若只有设备、CI 资源或 C2 外部确认尚缺，可以写 `TECHNICAL CONDITIONAL GO`，但必须有
owner、期限和明确禁止项。代码正确性、真实 FFI、backup/Saga 安全不能作为可延期条件。

## 5. 总施工顺序

```text
R-000 冻结证据与变更边界
  → R-001 修正 ABI 最后一处生命周期问题
  → R-002 严格 contract + production FFI binding
  → R-003 真正 worker isolate + control channel
  → R-004 一致性 backup/check/restore
  → R-005 Saga/catalog 规模与恢复修补
  → R-006 真实 Host Dart FFI 集成
  → R-007 production composition + internal flag/UI
  → R-008 官方 AV/TTS 修补
  → R-009 可重复 Android debug/release 构建
  → R-010 真机 E2E
  → R-011 性能/体积/C2
  → R-012 CI
  → R-013 文档收口与最终技术决策
```

R-001～R-008 都应在生成最终 `.so` 前完成。不能先用旧 `.so` 做真机验收，再声称后续
Native 修补不影响设备结果。

## 6. R-000：冻结证据与变更边界

### 目标

在脏工作树中建立可审计基线，不覆盖用户和其他阶段的改动。

### 实施

1. 记录当前 HEAD、branch、submodule commit、submodule diff、相关文件 status。
2. 生成 Phase 0/1 相关文件清单，不使用 `git add .`。
3. 将现有 Phase 1 未提交代码视为待审代码，而不是已完成 artifact。
4. 为每个 R 任务指定独立 scoped commit；若暂不提交，至少记录 patch/diff hash。
5. 记录旧 APK/`.so` 的时间、大小、SHA-256，并统一标为 `stale/non-evidence`。

### 验收

- 无 reset/checkout/clean。
- 无无关文件进入修补 commit。
- 后续每个 artifact 都能关联到代码 commit 和 submodule commit。

### 预计

0.5 日。

## 7. R-001：C ABI 安全彻底收口

### 当前问题

`Box<[u8]>` 已修复返回 buffer 的 capacity/layout 问题，但：

```rust
fn request_bytes<'a>(ptr: *const u8, len: usize) -> Result<&'a [u8], i32>
```

其中 `'a` 不受任何输入借用约束，调用者理论上仍可选择任意生命周期。现有测试只证明
某次调用可以赋给 `&[u8]`，不能证明引用无法逃逸。

### 实施

1. 删除返回 borrowed slice 的安全 helper。
2. 采用以下两种方式之一：
   - 在每个 FFI entry 内校验后立即 `from_raw_parts`，引用不离开 closure；或
   - `with_request_bytes(ptr, len, |bytes| ...)`，closure 不能返回该借用。
3. `engine_new` 的 config pointer/length 同样走统一校验，不能永久忽略非法非零输入。
4. 保持 `Box<[u8]>` 分配/释放；文档写清 null/zero 和调用者契约。
5. 所有 exported function 经过 panic boundary；free 对合法 library pointer 不 unwind。
6. 加入 malformed envelope、8 MiB 边界、重复 free 的契约说明。重复 free 本身是调用者
   UB，不要伪装成可安全支持。

### 测试

- empty、1 byte、capacity > len、8 MiB、8 MiB+1。
- 10 万次 alloc/free。
- null+nonzero、invalid UTF-8、invalid JSON、panic mapping。
- 编译期测试确保 request slice 不能存入 Engine/static。
- 可用时增加 Host ASan/Valgrind job；不可用时写明原因，不假报。

### 验收

- 不再出现无输入约束的 lifetime parameter。
- `cargo fmt/clippy/test` 全绿。
- 新 native artifact 必须在此任务之后生成。

### 预计

0.5～1 日。

## 8. R-002：严格 contract 与真实 FFI binding

### 8.1 Contract 修补

当前 `dispatch_call()` 对没有 `contractVersion` 的请求回退 `engine::dispatch()`。这使 stable
symbol 同时接受正式 envelope 和 raw Spike JSON。

实施：

1. production `turna_anki_call` 强制 contract v1 envelope。
2. 如需保留 Host Spike raw API，只允许：
   - Rust 内部直接调用 `engine::dispatch()`；或
   - debug-only 的独立 symbol/feature，release 不导出。
3. request 必须同时校验：
   - major 支持；
   - request ID 非空且长度受限；
   - C argument operation ID 与 envelope operation name 映射一致；
   - payload 是 object 且大小受限。
4. unknown operation、name/id mismatch、缺 version 不得回退到数字 operation。
5. response request ID 必须与请求一致；`ok/payload/error` 组合必须互斥。
6. `BACKEND_COMMIT` 必须在 build/CI 与实际 submodule HEAD 比较，禁止常量漂移。

### 8.2 Production FFI binding

新增实际可用的 binding/factory：

```text
DynamicLibrary.open
  → lookup abi_version/engine_new/open/call/cancel/close/buffer_free
  → engine_new 得 handle
  → encode envelope
  → native call
  → copy response bytes
  → native buffer_free
  → decode typed response
```

要求：

- Android 打开 `libturna_anki.so`。
- Host integration 可注入本机 `target/debug/libturna_anki.so` 路径。
- handle、library 和 symbol 生命周期由一个 transport owner 管理。
- 所有 input allocation 在 finally 中释放，所有 Native output 只用
  `turna_anki_buffer_free`。
- engine_new/open 失败不遗留假 `_paths` 状态。
- close/dispose 幂等；partial open 失败可安全回收 handle。
- transport status 与 envelope business error 分开映射。

### 验收

- 不注入 fake callback，也能完成 Host `ENGINE_INFO → open → close`。
- contract golden 走真实 C ABI，而不是直接调用 Dart decoder。
- backend commit、ABI、contract major 均来自运行时 Native。

### 预计

2～3 日。

## 9. R-003：真正 worker isolate 与取消通道

### 当前问题

`OfficialAnkiWorker` 只保证 Future 顺序，不会把同步 FFI、JSON 解码、hash 和 sqlite3 移出
UI isolate。长 import 阻塞时，同 isolate 也不能调度 `latestProgress()`/`cancel()`。

### 目标架构

```text
UI isolate
  ├── request port ─────→ persistent Anki worker isolate
  │                         ├── FFI handle/Collection owner
  │                         ├── contract encode/decode
  │                         ├── source hashing
  │                         └── catalog sqlite
  └── control transport ─→ Native cancel/progress(handle)
```

### 实施

1. worker isolate 启动后创建 DynamicLibrary binding、Engine handle 和 catalog connection。
2. UI 只发送可序列化 DTO，不发送 Database/Pointer/Collection 对象。
3. request ID 映射 Completer，所有普通写操作串行。
4. cancel/progress 不能排在正在执行的 import Future 后面：
   - worker 初始化时把 opaque handle/control token 返回 controller；
   - UI/controller 可通过线程安全的 Native cancel/progress symbol 操作同一 registry handle；
   - close 必须先阻止新 control call，再等待 import 到安全点。
5. hash、large JSON 和 catalog batch 都放在 worker isolate。
6. app pause 不强杀事务；dispose 有 drain→cancel→close→engine_free 状态机。
7. isolate unexpected exit 时保留 attempt journal，启动后走 recovery。

### 测试

- ticker/frame heartbeat 在 5k import 期间继续推进。
- import 中 cancel，不等待 import Future 自然结束后才调用 cancel。
- progress 至少出现 busy/cancelling/terminal。
- concurrent open/import/close、double dispose、worker crash、profile switch。
- UI isolate 不出现同步 `sqlite3`/FFI 长调用。

### 验收

- 不是仅靠 `Queue<Future>` 的同 isolate 测试。
- 在真实 Native import 期间 cancel 可达，Collection check 随后通过。

### 预计

2～3 日。

## 10. R-004：一致性 backup、check 与 restore

### 当前问题

当前 `CREATE_BACKUP` 在 Collection 打开时直接 `fs::copy(collection.anki2)`。如果 SQLite
存在 WAL 或未 checkpoint 数据，副本可能不一致；同时它不处理媒体变化。

### 实施决策顺序

1. 优先调用 pinned rslib 公开的官方 backup/check 能力。
2. 若公开 API 不足，允许一个最小可维护 bridge/visibility patch。
3. 再不行时，必须在独占 owner 下：
   - quiesce 写操作；
   - 执行 SQLite online backup 或安全 close/checkpoint；
   - 复制到临时文件；
   - fsync；
   - 原子 rename；
   - reopen 并 check。
4. 不允许继续复制打开中的主 SQLite 文件作为“成功 backup”。

### 恢复语义

- Turna 索引失败优先续跑，不自动恢复全 Collection backup。
- import 中进程死亡且结果未知 → `needs_reconciliation`，不盲目重复导入。
- 全局 backup restore 只允许在无 review/sync/其他写操作后显式执行。
- 媒体 orphan 与数据库恢复分开记录；不自行猜测删除官方媒体。
- 删除伪造的 durable `nativeImportToken` 概念，或重命名为仅当次进程有效的
  `operationToken`。没有官方可查询语义时不得用于崩溃判断。

### 测试

- import 前 backup，修改 Collection，restore，重开/check。
- WAL/非空媒体目录场景。
- backup 中断、磁盘不足、目标已存在、损坏 backup。
- restore 后 backend/schema 不兼容 fail closed。

### 验收

- backup artifact 独立 open/check 通过。
- 代码中不再对 open Collection 主文件直接 `fs::copy`。

### 预计

1.5～3 日，取决于官方 API 可见性。

## 11. R-005：Saga、catalog 与 100k 修补

### 11.1 消除 O(N²) batch

当前 `_indexCards()` 将 descriptor 累积到全局列表，然后每一批把历史全部重新 upsert。

修补：

- 每批只写 `currentBatchDescriptors`。
- 总 card/note 数用计数器/集合的有界形式维护。
- card batch + `nextOffset` cursor 在同一个 catalog transaction 提交。
- cursor 保存“下一批起点”，不是当前 batch 起点。
- recovery 从 cursor 开始；已有 batch 不重复读取/写入。

### 11.2 Journal 分块

- 新增 `anki_import_attempt_notes(attempt_id, ordinal, note_id)` 或 chunk 表。
- 不把 100k Note IDs 放进单行 JSON。
- import log 落盘与 attempt 状态切换在一个 transaction。
- DAO 提供 page/chunk iterator，不一次 decode 全部 ID。

### 11.3 Catalog migration

- schema create/migration 放在 transaction。
- 半创建数据库下次启动能恢复或 fail closed。
- future version 只读/拒绝策略明确。
- `needs_reconciliation` 是等待用户/诊断的终态，不应被每次启动无限重复 recovery。
- source/attempt ID 使用 UUID/ULID 或足够随机的 128-bit ID，不依赖毫秒+hash 前缀。
- source hash 唯一冲突与 source ID hash 前缀碰撞分别处理。

### 11.4 Saga 错误持久化

- orchestrator 顶层捕获已分类异常并持久化适当 state/error code。
- source/attempt 各阶段转换保持一致，不能 source 永远 selected 而 attempt 已 active 前崩溃。
- import response count 区分“本次关联数量”和“整个 Collection 总量”。
- duplicate/update/conflict 的真实 Note IDs 以官方 log 为准，并用真实重复导入 fixture 验证。
- update source 时在一个 transaction 中替换关联，不能留下旧 Card。

### 11.5 分页查询

当前每页重新搜索、排序整个 ID 集合。修补方案二选一并测量：

- Native query cursor/cache：首次生成有界 ID snapshot，后续页只切片，Collection generation
  改变后 token stale；或
- 使用官方可用的分页/limit 查询能力。

禁止每页重新 O(N) 后仍把它写成“100k 分页完成”。

### 测试

- 真实 9 fixture；真实同包第二次导入。
- 5k/100k 实际 journal、index、close/reopen。
- 第 1、中间、最后 batch 崩溃，恢复只处理剩余 batch。
- SQL 写入次数/Native batch 次数为 O(N/batch)，不是平方级。
- catalog create 中断、future version、foreign key、同 hash、ID collision。

### 验收

- 100k Dart/Native/catalog 全链路完成，有峰值 RSS 和调用次数。
- recovery cursor 有测试证明不会从 0 重跑。

### 预计

3～5 日。

## 12. R-006：真实 Host Dart FFI 集成门禁

### 目的

填补 Rust test 与 Fake Dart test 之间的空白。

### 实施

1. Host 构建真实 `libturna_anki.so`。
2. Dart test 通过 production binding 加载该库。
3. 使用临时 profile 和 file catalog，执行：

```text
ENGINE_INFO
  → open
  → check
  → backup
  → import real fixture
  → Note→Cards batch
  → descriptors
  → catalog active
  → close
  → reopen
  → verify source/card association
```

4. 分别跑 Unicode、Reverse、Cloze、legacy、media、duplicate/update、cancel。
5. Fake Engine tests 继续保留用于 fault injection，但报告明确标记为 unit test。

### 验收

- 至少一个测试确实跨越 Dart allocator、C ABI、Rust rslib 和 catalog。
- 测试失败时能区分 load/symbol/transport/contract/business/catalog 错误。

### 预计

1.5～2.5 日。

## 13. R-007：Production composition 与内部入口

### 当前问题

生产导入页面调用 `AnkiImportFacade.resolve()` 时没有提供 official orchestrator，所以即使
flag 全开也只会抛 `capabilityMissing`。

### 实施

1. 建立 application-level `OfficialAnkiCompositionRoot`：
   - application support/profile 路径；
   - worker isolate；
   - production FFI transport；
   - file catalog；
   - orchestrator/recovery service。
2. app 启动时只初始化轻量 capability；非终态 attempt 在 worker 中恢复/诊断。
3. facade 由 DI 获得 official/legacy 两个实现，页面不手工构造 Engine/DAO。
4. feature flag 来源使用受控 build channel/config；release 默认 false，不能只靠可变静态
   `OfficialAnkiFeatureFlags.current`。
5. runtime gate 检查 platform、library、ABI、contract、capability、catalog schema。
6. 内部 official UI 至少显示 hash/import/index/check 的进度、取消、reconcile 和安全摘要。
7. official 成功后不能伪装成 Legacy preview；Phase 2/3 未完成时明确展示“已导入官方
   Collection，复习入口尚未开放”。

### 测试

- flag off：现有 Legacy 行为不变。
- flag on + capability 完整：走真实 injected composition。
- flag on + 任一 gate 缺失：进入明确诊断，不构造 Legacy fallback。
- official 失败：Legacy mock 调用次数为 0。
- restart 后能找到 file catalog 和非终态 attempt。

### 验收

- internal build 可实际运行 official import，不再只是 fail closed scaffold。
- release 默认路径仍为 Legacy。

### 预计

2～3 日。

## 14. R-008：官方 AV/TTS 语义修补

### 当前问题

Native 已调用 `extract_av_tags()`，但丢弃其 `q_tags/a_tags`，转而手工查找 `[sound:]`。
这只能覆盖简单媒体，不能代表官方 TTS/复杂 AV 语义。

### 实施

1. 将官方 `q_tags/a_tags` 映射为 Turna typed DTO。
2. 保留官方处理后的 `question/answer text without AV`。
3. 删除 `sound_tags()` 手写扫描。
4. DTO 至少区分 sound/video 与 TTS，并保留官方必要字段。
5. 添加 sound、Unicode filename、question/answer 分离和 TTS fixture/golden。
6. Phase 0 只验证 Native DTO；播放/UI 留到 Phase 2。

### 验收

- 测试直接断言官方 tag DTO，而不是只断言 HTML 仍含 `[sound:]`。
- Phase 0 报告中的 AV 描述与实际能力一致。

### 预计

1～2 日。

## 15. R-009：可重复 Android 构建与 OOM 修补

### 当前事实

- 旧 debug APK 含旧 `.so`。
- 旧 release APK 不含 `.so`。
- 最新 release 尝试进入 assemble 后发生 Gradle daemon OOM kill。
- 主机约 14 GiB RAM、无 swap，Gradle `-Xmx4G`。

### 实施顺序

1. R-001～R-008 合并/冻结后重编 `.so`，生成 build metadata。
2. build script 自动：
   - 验证 Anki pin、patch、BACKEND_COMMIT；
   - build release arm64；
   - strip 到 staging；
   - verify ELF/NEEDED/symbol；
   - 复制确定产物到 jniLibs；
   - 输出 SHA-256/bytes。
3. 构建前记录 free memory/swap/daemon；停止陈旧 daemon，避免并行 build。
4. 先使用 `--no-daemon`、单 worker 的等价配置，不盲目提高 heap。
5. 本机仍 OOM 时转到有明确 RAM/swap 的干净 runner，不把环境失败写成代码 No-Go。
6. 分别生成新 debug 和 split arm64 release。
7. 解包 APK 验证 `.so`、ABI、size、build ID、backend commit/contract metadata。
8. 连续两次 clean runner 构建，防止使用 stale jniLib/Gradle cache。

### 基线对比

增加受控的 `includeOfficialAnki=false/true` 构建选项或等价 CI matrix；不能通过手工移动
用户文件产生 baseline。两组必须使用同 commit、同 build mode、同 ABI、同签名策略。

### 验收

- debug/release 都是 R-001 后的新 artifact。
- release APK 确实含 `lib/arm64-v8a/libturna_anki.so`。
- APK hash、库 hash/bytes、构建机资源和 exact command 写入报告。

### 预计

2～4 日，取决于构建机资源。

## 16. R-010：Android 真机 E2E

### 设备矩阵

- 一台接近最低 API 的 arm64 低内存设备/模拟器。
- 一台当前 Android arm64 真机。
- debug、release 各一次冷安装和升级安装。

### 必跑闭环

```text
cold start
  → ENGINE_INFO
  → open/check
  → import Unicode/Reverse/Cloze/media/legacy fixture
  → write catalog
  → close/reopen
  → verify association
  → start 5k import
  → observe progress
  → cancel
  → check/reimport
  → force-stop/restart recovery
```

### 观察

- `UnsatisfiedLinkError`、symbol missing、native tombstone。
- UI jank/ANR、低内存 kill、后台恢复。
- Collection lock、数据库损坏、catalog state。
- cancel request 到 UI 变化和 Native terminal 的耗时。

### 验收

- 两类设备 debug/release 均完成最小闭环。
- release 下真实 backend commit、contract 和 ABI 与构建记录一致。
- 无 crash/ANR/Collection corruption。

### 预计

1～2 日，前提是设备可用。

## 17. R-011：性能、体积与 C2

### 必测指标

| 场景 | 指标 |
|---|---|
| no-native vs with-native APK | bytes、download/install delta |
| cold/warm start | p50/p95、review/import ready |
| 5k real import+catalog | wall、peak RSS、FFI calls、SQL batches |
| 100k real import+catalog | wall、peak RSS、journal bytes、recovery time |
| cancel | UI acknowledge、Native terminal、check duration |
| 100 renders | p50/p95/p99、稳态 RSS 增长 |
| close/reopen | wall、fd/native memory |

### 建议技术阈值

阈值可由产品在执行前调整，但不能测试后移动：

- cold start p50 回归不超过 `max(10%, 300 ms)`。
- cancel UI acknowledge ≤ 250 ms；Native 安全终止 p95 ≤ 2 s，随后 check 通过。
- 100 次 warm render 后稳态 RSS 相对 warmup 增长 ≤ 20 MiB。
- 100k 不出现 O(N²) SQL/FFI 调用；batch 次数接近 `ceil(N/batch)`。
- 低内存设备不发生 LMK/ANR。
- native/APK 增量给出精确值并完成 C2 产品技术确认。

如果阈值不适合设备实际情况，应在测试前写入批准的新阈值和理由。

### 验收

- Host 数据与 Android 数据分开。
- RSS 不再使用“包含 cargo 编译进程”的值代表 App 内存。
- C2 记录选择 arm64/AAB split/其他交付方式；本计划不处理 License。

### 预计

1.5～2.5 日 + 产品确认等待。

## 18. R-012：CI 门禁

### Jobs

1. `official-anki-host`
   - submodule/pin/patch/metadata check；
   - fmt/clippy/test；
   - contract golden；
   - real Host Dart FFI integration。
2. `official-anki-dart`
   - fake unit/fault matrix；
   - catalog migration；
   - analyzer。
3. `official-anki-android-arm64`
   - clean native build；
   - debug/release APK；
   - unzip/ELF/symbol/size inspection。
4. 可用时 `official-anki-device-smoke`
   - emulator/device `ENGINE_INFO/open/import/reopen`。

### 防 stale artifact

- `.so` build metadata 含 Turna commit、Anki commit、contract、NDK、Rust toolchain。
- APK inspection 对比 metadata，不能只检查文件名存在。
- cache key 包含 submodule commit、Cargo.lock、patch hash、NDK/Flutter version。
- cache miss 情况必须成功一次。

### 验收

- 干净 runner 通过。
- pin/patch/BACKEND_COMMIT 任一漂移会失败。
- CI 不依赖开发者 `/home/...` 绝对路径。

### 预计

1.5～3 日。

## 19. R-013：文档修正与最终技术决策

### Phase 0 文档

1. 删除结果报告重复的 §16～§20。
2. 修正“P0-000～P0-013 全完成”与 P0-000/P0-004 未完成的矛盾。
3. 把旧 plugin-loader 根因更新为实际构建历史：旧错误已越过，最新失败为 OOM。
4. 按真实结果更新实施方案任务 checkbox 和最终总清单。
5. AV 从“手工 sound 扫描通过”修正为官方 typed AV/TTS 证据。
6. 写入新 debug/release/真机/性能证据。

### Phase 1 文档

在修补前先将以下表述降级：

- “稳定 Engine/worker 已落地”→ 当前只是 interface + same-isolate queue scaffold。
- “9 fixture 经过 orchestrator”→ 当前是 Fake Engine unit test。
- “backup/checkpoint 完成”→ 当前 raw copy 不可验收。
- “恢复续跑完成”→ 当前从 0 重跑，cursor 未生效。
- “生产入口完成”→ 当前只有 fail-closed hook，没有 production composition。

修补后才能依据 R-002～R-012 的证据重新升级状态。

### 新结果报告

新增：

```text
06-phase-0-phase-1-technical-remediation-result.md
```

报告结论仅允许：

- `TECHNICAL GO`
- `TECHNICAL CONDITIONAL GO`
- `TECHNICAL NO-GO`

并在首页固定写：

```text
License/legal: NOT EVALUATED BY THIS PLAN
Production release: subject to separate License gate
```

### 验收

- 每个“通过”都有 commit、命令、artifact 或设备证据。
- Fake/Host/Android 分栏记录。
- 未测项不写通过。

### 预计

1 日。

## 20. 任务跟踪表

| 任务 | 初始状态 | 前置 | 完成证据 |
|---|---|---|---|
| R-000 证据边界 | 未开始 | 无 | baseline/status/diff manifest |
| R-001 ABI | 部分实现，仍有 lifetime 问题 | R-000 | Rust tests + code review |
| R-002 contract/FFI | contract 部分；真实 binding 缺失 | R-001 | real Host FFI test |
| R-003 isolate/cancel | 未实现；当前同 isolate queue | R-002 | heartbeat/cancel real test |
| R-004 backup/restore | 不可验收；当前 raw copy | R-002、R-003 | restore/open/check test |
| R-005 Saga/catalog | scaffold；存在 O(N²)/假 cursor | R-003、R-004 | real 100k/recovery |
| R-006 Host Dart FFI | 未实现 | R-002～R-005 | 9 fixture real integration |
| R-007 production composition | 仅 fail-closed hook | R-003～R-006 | internal official import |
| R-008 AV/TTS | 部分；丢弃官方 tags | R-001 | typed golden |
| R-009 Android build | 未关闭；release OOM | R-001～R-008 | new APK hashes |
| R-010 真机 | 未关闭 | R-009 | device logs/matrix |
| R-011 性能/C2 | 部分 Host 数据 | R-009、R-010 | metrics + product record |
| R-012 CI | 未实现 | R-001～R-009 | clean CI run |
| R-013 文档决策 | 未开始 | 全部 | result report |

## 21. 建议 commit 切分

```text
fix(anki): close C ABI request lifetime hole
fix(anki): enforce official contract envelope
feat(anki): add production native transport
feat(anki): move official engine and catalog to worker isolate
fix(anki): create consistent collection backups
fix(anki): make import journal and cursor resumable at 100k
test(anki): run Dart saga against real rslib
feat(anki): wire internal official import composition
fix(anki): return official AV and TTS tags
build(anki): make arm64 artifacts reproducible
ci(anki): gate official core and APK contents
docs(anki): close Phase 0 and Phase 1 technical remediation
```

每个 commit 只暂存明确文件。禁止 `git add .`，禁止把当前其他 300 余项工作树改动混入。

## 22. 预计工期

| 工作块 | 工程日 |
|---|---:|
| ABI + contract + real FFI | 3～4 |
| worker isolate + cancel | 2～3 |
| backup + Saga/catalog | 4.5～8 |
| real Host integration + composition | 3.5～5.5 |
| AV/TTS | 1～2 |
| Android build + device | 3～6 |
| 性能 + CI + 文档 | 4～6.5 |
| 合计 | **18～35 工程日** |

该估算比原结果报告更高，因为此前把 Fake Engine、同 isolate queue、raw SQLite copy 和
未接入 production binding 计成了已完成。License/法律等待时间不包含在内。

## 23. 开工后的前三张票

1. **R-001**：删除 unconstrained `request_bytes<'a>`，完成 ABI code review。
2. **R-002**：强制 envelope，并让 Dart production transport 实际加载 Host `.so`。
3. **R-003**：用真实 worker isolate 跑 fixture import，同时打通并发 cancel/control。

在这三项完成前，不应继续以 Phase 1 “已实施”状态推进默认导入或 Phase 2 生产接入。
