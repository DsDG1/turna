# Phase 1 实施方案：稳定 Engine 与官方导入

> 阶段名称：第二阶段（Phase 1）  
> 文档状态：**Ready for implementation**；生产切流状态：**禁止**  
> 基线日期：2026-08-16  
> 前置决策：Phase 0 `Conditional Go`  
> 首发平台：Android arm64  
> 上游基线：`ankitects/anki@967aa0d578fc75181e292e95326f9b58698da25c`  
> 预计工期：15～20 个工程日；其中 C1 构建/真机专项预留 3～5 日

## 1. 本阶段要交付什么

Phase 1 不以“界面上能选择 `.apkg`”作为完成标准，而是交付一条可恢复、可诊断、
可在 Android 真机运行的官方导入链路：

```text
用户选择包
  → worker isolate 计算 hash
  → 打开当前 profile 的官方 Collection
  → 建立持久化 import attempt
  → 官方 rslib 导入
  → 分页取得本次来源关联的 Note/Card
  → 写入 Turna 来源目录
  → 关闭并重新打开后仍可识别该来源
```

本阶段完成后，官方 Collection 是新导入 Anki 数据的唯一事实源。Turna 只保存来源、
Card 关联、导入状态和恢复日志，不保存官方 Note 字段、模板、CSS、调度状态或预渲染
HTML 的第二份副本。

Phase 1 只允许在内部/测试 feature flag 下接入生产导入入口。正式用户默认切流、官方
原卡 WebView、课程字段映射和官方 Scheduler 分别属于后续阶段。

## 2. 开工基线与事实修正

### 2.1 已经具备

- 官方 Anki 源码以 submodule 固定到指定 commit。
- Rust bridge 已有 Collection open/close/check、import、search、render、queue、answer、
  undo 的 Host Spike。
- Android arm64 `.so` 已能交叉编译。
- 9 个冻结 fixture、5k/100k 生成器和 Host golden 已存在。
- Dart Spike 已能 probe、probe Collection 和 import，耗时操作通过 isolate 离开 UI。
- Host Rust 当前 19 个测试通过；定向 Flutter 测试 20 个通过。
- strip 后 native 增量约 16 MiB，100k Host import 约 3.6 秒。

这些结果证明“可以继续”，不代表生产能力已经完成。

### 2.2 当前没有具备

- 没有稳定的 `OfficialAnkiEngine`；当前代码仍位于 `spike/`。
- Dart 尚未正式暴露 render/query/queue/answer/undo。
- `turna_anki_spike.proto` 没有参与实际编解码；实际 wire format 是无统一 envelope 的
  JSON。
- runtime `ENGINE_INFO` 没有成为 backend commit、ABI 和 contract version 的事实源。
- 没有全局 profile Collection owner，也没有稳定 worker isolate。
- 没有 `anki_sources` / `anki_source_cards` / import attempt journal。
- 没有官方 backup/recovery 和崩溃续跑。
- 生产入口仍调用 `AnkiImporter` 和 `AnkiImportService`。
- 没有 Android 真机完整证据，也没有包含 `.so` 的新 APK。
- About 页尚未注册官方 Anki 许可证。

### 2.3 C1 最新阻塞结论

2026-08-16 最新 release 构建已经越过 `flutter-plugin-loader` 解析，进入
`assembleRelease` 后 Gradle daemon 被系统 OOM killer 终止。内核记录中 Java 进程
anon RSS 约 2.56 GiB；主机 14 GiB RAM、无 swap，`android/gradle.properties` 当前为
`org.gradle.jvmargs=-Xmx4G`。

因此 C1 当前应记录为“构建主机内存压力/OOM，且无 adb 真机”，不能继续把旧的
`25.0.2` 插件错误写成唯一根因。旧 APK 均早于 `.so`，不能作为打包证据。

## 3. 范围边界

### 3.1 本阶段包含

1. 修复 C ABI 内存和生命周期安全问题。
2. 冻结 Turna-owned contract v1，并建立兼容性测试。
3. 建立稳定 Engine、单 owner worker isolate 和 profile Collection 布局。
4. 实现导入、进度、取消、check、backup、分页索引与恢复所需的正式 API。
5. 建立独立的官方来源目录数据库和 Saga journal。
6. 在内部 feature flag 下接入生产文件选择入口。
7. 关闭 Phase 0 的 C1～C5 条件中本阶段可以工程化关闭的部分。
8. 建立 Host、Dart、Drift、APK 和真机门禁。

### 3.2 明确不包含

- 不实现正式 reviewer WebView、媒体 origin、MathJax 或 typed answer UI。
- 不把课程复习切到官方 Scheduler。
- 不做完整语言字段映射和课程树投影。
- 不迁移或删除现有 Legacy 数据。
- 不删除 `AnkiImporter`、`AnkiImportService` 或旧镜像表。
- 不实现 AnkiWeb Sync。
- 不承诺 OHOS/iOS/桌面平台。
- 不升级 pinned Anki commit、NDK、AGP 或 Flutter，除非有独立变更和全量门禁证据。

### 3.3 施工红线

- 官方导入失败时不得自动调用 Legacy importer。
- Dart 不得读取 `collection.anki2`、`collection.media.db2` 或上游 protobuf。
- Dart 不得出现上游 service/method index。
- 不得修改官方 Collection schema。
- 不得在 UI isolate 执行导入、check、hash 或大批量 JSON 解码。
- 不得将未知恢复状态标成 `active`。
- 不得在 C1、contract、Saga 恢复测试未通过前把 official import 设为默认。
- 不得以“Host 通过”替代“Android debug/release 真机通过”。

## 4. 完成定义

只有下列项目全部满足，Phase 1 才能标记完成：

| 门禁 | 完成条件 |
|---|---|
| ABI 安全 | Rust 返回 buffer 的分配/释放布局一致；请求 slice 无伪造 `'static`；panic 不跨 FFI |
| Contract | v1 请求/响应 envelope 被真实使用；运行时返回真实 backend commit；未知主版本明确拒绝 |
| Engine | 一个 profile 只有一个 Collection owner；所有长操作串行运行在持久 worker isolate |
| Android | arm64 debug/release APK 均包含并加载 `libturna_anki.so`，真机闭环通过 |
| Import | 9 个 fixture、5k 和至少一次 100k 可导入、索引并重开 |
| Cancel | 取消后来源不为 `active`，Collection check 通过，可再次导入 |
| Crash recovery | 每一个 fault injection 点重启后可续跑、回滚或进入可解释的 `needs_reconciliation` |
| Source catalog | 来源与 Card 关联可分页查询；不镜像字段、模板、CSS 或 scheduling |
| Duplicate import | 同 hash 不产生第二个 active source；更新策略明确且有测试 |
| Feature flag | 默认关闭；依赖不满足时 fail closed；无 official→legacy 自动回退 |
| 许可与体积 | C2 有书面决策；About 可见 Anki AGPL；C4 有书面结果 |
| CI | Host Rust、contract、Dart、数据库 migration、Android arm64 构建进入 CI |
| 文档 | 结果报告含真实 commit、命令、APK hash/大小、设备型号、耗时和未决风险 |

Phase 1 完成不等于用户已经能高保真复习原卡；那是 Phase 2 的退出门槛。

### 4.1 Phase 0 条件接续表

| 条件 | 当前状态 | Phase 1 动作 | 关闭前限制 |
|---|---|---|---|
| C1 Android APK/真机 | 未关闭；release 构建 OOM、无 adb 证据 | P1-003、P1-004 | 不得打开 release import flag |
| C2 native 体积 | 已测量、未获产品接受 | P1-014 | 不得发布含 `.so` 的外部包 |
| C3 About 许可证 | Spike 有注册函数，生产入口未调用 | P1-015 | 不得发布含 `.so` 的外部包 |
| C4 法律确认 | 未签字 | P1-015 | 不得发布含 `.so` 的外部包 |
| C5 上游 patch | patch 已保存，尚无 CI replay 门禁 | P1-002、P1-015 | 不得升级 Anki pin |

### 4.2 初始任务状态

| 任务 | 初始状态 | Owner | 验收证据位置 |
|---|---|---|---|
| P1-000 基线冻结 | 待实施；本文只完成计划 | Native/App | Phase 1 结果报告 |
| P1-001 ABI 安全 | 待实施；已识别阻塞级风险 | Native | Rust tests + commit |
| P1-002 Native 门禁 | 待实施；当前有 7 个 warning | Native/CI | CI run |
| P1-003 Android 构建 | 已尝试、未验收；OOM | Build | APK hash + build log |
| P1-004 真机闭环 | 待设备 | Android | adb/logcat + device matrix |
| P1-005 contract v1 | 待实施；Spike contract 未真实使用 | Native/Dart | golden matrix |
| P1-006～P1-013 | 待实施 | Native/Dart/Data/App | 对应任务证据 |
| P1-014 体积决策 | 待产品签字 | Product | ADR/纪要 |
| P1-015 合规 | 部分脚手架、未关闭 | App/Legal/Native | UI + source offer + 签字 |
| P1-016 CI | 待实施 | CI | clean runner |
| P1-017 结果报告 | 待实施 | Tech lead | `04-phase-1-result-report.md` |

## 5. 目标结构

### 5.1 Native

```text
native/turna_anki_core/
├── anki/                          # pinned official submodule
├── bridge/src/
│   ├── abi.rs                     # 只处理 C transport 和 panic boundary
│   ├── contract.rs                # v1 envelope、版本和 DTO
│   ├── engine.rs                  # handle、owner、Collection lifecycle
│   ├── errors.rs                  # stable Turna error mapping
│   ├── import.rs                  # import/check/backup/progress/cancel
│   └── query.rs                   # page token + batch descriptor
├── contract/
│   ├── VERSION
│   ├── operations.md
│   ├── compatibility.md
│   └── fixtures/                  # request/response golden JSON
├── build-android/
└── patches/
```

`turna_anki_spike.proto` 在 P1-004 必须二选一：真正用于生成和编解码，或明确归档并由
versioned JSON contract 取代。Phase 1 默认选择后者，因为现有可运行实现和 Dart
生态已经使用 JSON。禁止同时维护“看起来像事实源的 proto”和另一套实际 JSON。

### 5.2 Dart

```text
lib/application/anki_official/
├── contract/
│   ├── official_anki_contract.dart
│   ├── official_anki_dto.dart
│   └── official_anki_errors.dart
├── engine/
│   ├── official_anki_engine.dart
│   ├── official_anki_engine_ffi.dart
│   ├── official_anki_worker.dart
│   └── official_anki_capabilities.dart
├── import/
│   ├── official_anki_import_orchestrator.dart
│   ├── official_anki_import_state.dart
│   ├── official_anki_recovery_service.dart
│   └── official_anki_source_hasher.dart
├── storage/
│   ├── official_anki_database.dart
│   ├── official_anki_source_dao.dart
│   └── official_anki_import_attempt_dao.dart
├── official_anki_paths.dart
├── official_anki_feature_flags.dart
└── spike/                         # Phase 1 收口后仅保留诊断或删除
```

不要把新逻辑继续堆进 `anki_import_screen.dart`。页面只能依赖一个 import facade，并根据
flag 选择明确的 official 或 legacy 实现。

## 6. Stable contract v1

### 6.1 C ABI 与业务 contract 分层

C ABI 保持最小：

```c
uint32_t turna_anki_abi_version(void);
TurnaAnkiResult turna_anki_engine_new(const uint8_t*, size_t);
TurnaAnkiResult turna_anki_engine_open(uint64_t, const uint8_t*, size_t);
TurnaAnkiResult turna_anki_call(uint64_t, uint32_t, const uint8_t*, size_t);
TurnaAnkiResult turna_anki_cancel(uint64_t);
TurnaAnkiResult turna_anki_engine_close(uint64_t);
void turna_anki_buffer_free(uint8_t*, size_t);
```

`TurnaAnkiResult.status` 只表达 transport/ABI 级失败，例如非法指针、无效 handle、panic
boundary。可预期业务错误必须进入统一响应 envelope，这样增加 error code 不需要改变
C ABI。

### 6.2 实际 wire envelope

请求：

```json
{
  "contractVersion": {"major": 1, "minor": 0},
  "requestId": "01J...",
  "operation": "IMPORT_PACKAGE",
  "payload": {}
}
```

响应：

```json
{
  "contractVersion": {"major": 1, "minor": 0},
  "requestId": "01J...",
  "ok": true,
  "payload": {},
  "error": null,
  "engine": {
    "abiVersion": 1,
    "backendCommit": "967aa0d...",
    "contractMajor": 1,
    "contractMinor": 0
  },
  "durationMillis": 12
}
```

错误：

```json
{
  "ok": false,
  "payload": null,
  "error": {
    "code": "PACKAGE_INVALID",
    "messageKey": "official_anki.package_invalid",
    "recoverable": false,
    "retryAfterMillis": null,
    "debugDetails": null
  }
}
```

用户可见文案由 Dart 本地化，Rust 不返回包含字段内容或完整私有路径的错误消息。

### 6.3 版本规则

- major 不同：拒绝调用，返回 `CONTRACT_VERSION_MISMATCH`。
- 相同 major、Dart minor 小于 native minor：忽略未知响应字段。
- 相同 major、Dart minor 大于 native minor：只有 capability 明确存在时才可调用新操作。
- operation 编号一旦发布只追加不重排；文档同时记录稳定字符串名。
- 字段删除、改类型、改变默认语义必须升 major。
- 每个 golden 同时由 Rust encode 和 Dart decode 验证。
- backend commit 由 Native 构建时注入并通过 `ENGINE_INFO` 返回；Dart 不再硬编码为诊断事实。

### 6.4 Phase 1 必需 operation

| Operation | 用途 | 约束 |
|---|---|---|
| `ENGINE_INFO` | ABI、contract、backend、capability | 不要求 Collection 已打开 |
| `OPEN_COLLECTION` | 打开 profile Collection | 路径必须经过 Native canonicalize/root 校验 |
| `CLOSE_COLLECTION` | 安全关闭 | 等待写事务，不强杀 |
| `CHECK_COLLECTION` | 快速/完整检查 | 有进度，可取消 |
| `CREATE_BACKUP` | 导入前 checkpoint | 返回可验证 backup ID |
| `IMPORT_PACKAGE` | 官方导入 | 返回完整 import log 摘要和 attempt token |
| `LATEST_PROGRESS` | 查询进度 | 结构化 stage/current/total，不只 message |
| `CANCEL_OPERATION` | 请求安全取消 | 幂等 |
| `LIST_DECK_TREE` | 完整递归 deck tree | 不只展开两层 |
| `SEARCH_CARDS_PAGE` | 分页 Card ID | 有稳定 page token/limit 上限 |
| `GET_NOTE_CARDS_BATCH` | 将 import log Note ID 转 Card | 单批有上限 |
| `GET_CARD_DESCRIPTORS_BATCH` | 写来源关联需要的最小 DTO | 不返回全部字段/HTML |

Render、AV/TTS 和 Scheduler operation 可以继续保留 Host Spike，但在 Phase 2/4 前不得被
生产 UI 当作正式完成能力。

### 6.5 分页与内存预算

当前 `SEARCH_CARDS` 会把所有 Card 和所有 Note 字段一次性组成 JSON；它不能进入生产。

- 默认 page size 200，最大 1000。
- response uncompressed JSON 建议上限 4 MiB，硬上限 8 MiB。
- page token 由 Native 生成，包含查询 fingerprint 和游标；Dart 不拼 SQL offset。
- token 在 Collection 修改后失效并返回 `PAGE_TOKEN_STALE`。
- descriptor 只含 `cardId/noteId/deckId/noteGuid/templateOrd`。
- 字段内容在后续课程投影按需批量读取，不进入 Phase 1 来源索引。
- 100k 测试必须记录 Native 峰值 RSS 和 Dart isolate 峰值，不只记录 wall time。

## 7. 必须先修的 Native 安全问题

### 7.1 返回 buffer 容量错误

当前 `ok_bytes(Vec<u8>)` 只返回 pointer 和 length，随后
`Vec::from_raw_parts(ptr, len, len)` 释放。原始 `Vec` 的 capacity 不保证等于 length，
因此可能以错误 allocator layout 释放，属于生产阻塞级未定义行为。

目标实现使用 `Box<[u8]>`：

```rust
let boxed = bytes.into_boxed_slice();
let len = boxed.len();
let ptr = Box::into_raw(boxed) as *mut u8;

// free
let slice = std::ptr::slice_from_raw_parts_mut(ptr, len);
drop(Box::from_raw(slice));
```

同时测试 empty、1 byte、非精确 capacity、大响应和至少 10 万次 alloc/free 循环。

### 7.2 请求 slice 伪造静态生命周期

当前 `request_bytes()` 返回 `&'static [u8]`。Phase 1 必须把 slice 生命周期限定在单次
FFI entry closure 内，任何引用不得写入 Engine 或跨调用保存。

### 7.3 其他 Native 硬化

- request pointer/length 组合和最大 payload 长度都要先校验。
- 所有导出函数都有 panic boundary；析构函数不得 panic。
- path 使用 canonicalize 后验证在允许 root 内；创建前验证最近存在父目录。
- 拒绝 collection/media/media-db 路径相同、父子逃逸、符号链接逃逸和 NUL。
- 清理当前 Rust unused import/dead code warning；CI 使用 `clippy -- -D warnings`。
- `0001-export-progress-state.patch` 每次构建前验证可干净 replay。

## 8. Engine 生命周期与线程模型

### 8.1 一个 profile、一个 owner

```text
Flutter UI
  → OfficialAnkiEngine facade
  → 单个持久 Dart worker isolate
  → 同一个 FFI handle
  → Rust 单 Collection owner
```

不能用每次调用一次 `Isolate.run()` 作为正式模型，因为多个调用可能落到不同 isolate，
无法自然保证顺序、取消和 close 语义。正式 worker 启动后持有 FFI binding 与 handle，
通过 request ID 串行执行写操作；只读并发也先关闭，直到有数据证明可以开放。

### 8.2 生命周期

```text
notStarted → starting → readyClosed → opening → open → busy → open
                                           ↘ failedRecoverable
open → closing → readyClosed → disposed
```

- `start()` 和 `openProfile()` 幂等。
- profile 切换必须先 drain/cancel、close，再打开新 profile。
- app pause 不关闭正在提交的官方事务。
- app detach 等待受控超时；超时只记录未完成 attempt，不删除文件。
- 任意状态异常都返回 typed error，不由 UI 猜状态。

### 8.3 文件布局

```text
<application-support>/anki/profiles/<profile-id>/
├── collection.anki2
├── collection.media/
├── collection.media.db2
├── backups/
├── engine.json
└── locks/
```

`profile-id` 必须是内部生成的不透明单段 ID。外部 display name 不进入路径。

`engine.json` 至少包含：

```json
{
  "formatVersion": 1,
  "profileId": "...",
  "collectionInstanceId": "...",
  "backendCommit": "...",
  "contractMajor": 1,
  "contractMinor": 0,
  "createdAtMillis": 0,
  "lastOpenedAtMillis": 0
}
```

写入采用 temp file + fsync + atomic rename。路径和用户内容不写日志。

## 9. 来源目录数据库

### 9.1 独立数据库

Phase 1 默认新增 `OfficialAnkiDatabase`，存放在 profile 官方目录之外的稳定 app data
路径。不要把新表直接加入当前 `CourseDatabase`，原因是该数据库 downgrade 分支会按
“可重建课程缓存”策略删除全部表，而 import Saga、来源关系和恢复状态不能在降级时
被静默擦除。

若实现者坚持复用 `CourseDatabase`，必须先提交 ADR，修改 downgrade/重建策略并证明
不会删除 official source journal；否则 P1-007 不得开工。

### 9.2 最小 schema v1

```sql
CREATE TABLE anki_sources (
  source_id TEXT PRIMARY KEY,
  profile_id TEXT NOT NULL,
  source_hash TEXT NOT NULL,
  source_size INTEGER NOT NULL,
  display_name TEXT NOT NULL,
  original_uri TEXT,
  state TEXT NOT NULL,
  backend_commit TEXT NOT NULL,
  contract_major INTEGER NOT NULL,
  contract_minor INTEGER NOT NULL,
  import_options_json TEXT NOT NULL,
  active_attempt_id TEXT,
  imported_at_millis INTEGER,
  last_error_code TEXT,
  last_error_safe_message TEXT,
  created_at_millis INTEGER NOT NULL,
  updated_at_millis INTEGER NOT NULL,
  UNIQUE(profile_id, source_hash)
);

CREATE TABLE anki_source_cards (
  source_id TEXT NOT NULL REFERENCES anki_sources(source_id) ON DELETE CASCADE,
  card_id INTEGER NOT NULL,
  note_id INTEGER NOT NULL,
  deck_id INTEGER NOT NULL,
  note_guid TEXT,
  template_ord INTEGER NOT NULL,
  PRIMARY KEY(source_id, card_id)
);

CREATE INDEX anki_source_cards_card_idx
  ON anki_source_cards(card_id);

CREATE TABLE anki_import_attempts (
  attempt_id TEXT PRIMARY KEY,
  source_id TEXT NOT NULL REFERENCES anki_sources(source_id),
  request_id TEXT NOT NULL UNIQUE,
  state TEXT NOT NULL,
  checkpoint_id TEXT,
  native_import_token TEXT,
  imported_note_ids_json TEXT,
  cursor_json TEXT,
  started_at_millis INTEGER NOT NULL,
  heartbeat_at_millis INTEGER NOT NULL,
  completed_at_millis INTEGER,
  last_error_code TEXT,
  recovery_count INTEGER NOT NULL DEFAULT 0
);
```

约束：

- 不新增 raw fields、qfmt、afmt、CSS、scheduler/revlog 或 prerendered HTML 列。
- `original_uri` 可空，并按平台权限模型处理；日志不得输出。
- hash 唯一性以 profile 为边界。
- attempt journal 只保存恢复所需 ID，不保存用户字段内容。
- `imported_note_ids_json` 超过安全阈值时改用子表分页保存，禁止无限大单行 JSON。
- migration 必须测试 fresh create、v1 reopen、future-version fail closed 和 downgrade。

## 10. 导入 Saga

### 10.1 状态机

```text
selected
  → hashing
  → preparing
  → backing_up
  → importing_official
  → indexing_notes
  → indexing_cards
  → active
```

终止/恢复状态：

```text
cancel_requested → cancelled
failed_before_import
failed_after_import
needs_reconciliation
recovering
rolled_back
```

状态变化必须以 transaction + expected previous state 更新，禁止任意页面直接写字符串。

### 10.2 正常流程

1. 校验 URI/file、扩展名、大小和读取权限。
2. worker 流式计算 SHA-256 与字节数。
3. 查询 `(profile_id, source_hash)`：active 则展示“已导入”，未完成则进入恢复。
4. 写 `source(selected)` 和 `attempt(preparing)`。
5. Engine check；失败停止，不启动官方 import。
6. 创建官方 checkpoint，持久化 `checkpoint_id`。
7. 调 `IMPORT_PACKAGE`，立即持久化 native import token 和 import log Note IDs。
8. 分批 `GET_NOTE_CARDS_BATCH`，再分批取最小 Card descriptor。
9. 每批在一个 Drift transaction 内 upsert `anki_source_cards` 和 cursor。
10. 核对 expected/actual 唯一 Note/Card 数量。
11. 再次快速 check，标记 source/attempt 为 `active/completed`。
12. 生成可显示的安全摘要：deck 数、note 数、card 数、警告和缺失媒体数。

### 10.3 恢复原则：优先续跑，不盲目 Undo

总体方案曾写“投影失败优先调用官方 Undo”。Phase 1 将其收紧为：

- 官方导入尚未开始：安全标记 `failed_before_import` 或直接重试。
- 官方导入明确完成、只有 Turna 索引失败：保留官方数据，从持久化 Note IDs/cursor
  续跑索引；不要为了派生数据失败回滚官方事实源。
- 官方导入调用返回取消：check Collection，标记 `cancelled`；遗留无引用媒体允许后续
  官方清理，不自行删文件。
- 进程在 Native import 中死亡且结果不明：标记 `needs_reconciliation`，先 check，再用
  import token/log 能力判断；不能证明时不得重复盲导。
- 只有“本 attempt 是 Collection 最后一个独占写操作、官方 Undo token 仍匹配、用户
  明确选择回滚”时才执行 Undo。
- backup 是灾难恢复手段。恢复全局 backup 会回退整个 profile，必须确认导入期间没有
  review/sync/其他写操作，并向用户展示影响。

这一收紧避免为了修复 Turna 的索引失败而丢失已经成功写入的官方内容。P1-009 实现前
应同步修订总体方案 §10.3 或新增 ADR。

### 10.4 故障注入点

至少在下列位置模拟 throw/process restart：

1. hash 完成前。
2. source 已写、checkpoint 未写。
3. checkpoint 已写、import 未调用。
4. import 调用中取消。
5. import 返回后、Note IDs 落盘前。
6. Note IDs 落盘后、第一批 Card 前。
7. 中间批次 cursor 提交后。
8. 全部 Card 写完、source 标 active 前。
9. active 后 app 立即重启。

每个点必须声明期望状态、自动动作、用户可见动作和数据不变量。

## 11. 重复、更新与删除语义

### 11.1 同一包重复选择

- 同 profile、同 SHA-256、source=`active`：不再次导入，打开来源摘要。
- 同 hash、未完成 attempt：进入 recovery，不新建第二条 source。
- 同名不同 hash：视为更新候选，必须让用户确认官方 import options。

### 11.2 更新包

- 覆盖/合并决策交给官方 import options，不用 Turna 比较 Note mod 决定。
- 新 attempt 完成后重建该 source 的关联集合。
- 关联切换在一个 catalog transaction 内完成。
- 同一 Card 可关联多个 source。
- Phase 1 不自动删除“不再出现在更新包里”的官方 Card。

### 11.3 删除来源

Phase 1 的“删除来源”只删除 Turna source/card association，不删除官方 Note/Card/媒体。
“同时删除官方内容”属于后续独立设计，必须处理多来源引用与 revlog，不在本阶段顺手做。

## 12. Feature flag 与生产入口

### 12.1 Flags

```dart
class OfficialAnkiFeatureFlags {
  final bool engine;
  final bool import;
  final bool diagnostics;
}
```

规则：

- release 默认全部 false；内部构建可以通过受控 build config 打开。
- `import` 依赖 `engine`、catalog schema、runtime capability、C1 平台检查同时通过。
- debug 设置页只能改变 debug/internal override，不能改变商店包默认值。
- flag 状态与 build channel 写入诊断报告。
- flag 关闭不会删除官方 Collection 或 source catalog。

### 12.2 页面接法

```text
Anki import screen
  → AnkiImportFacade
      ├── OfficialAnkiImportFacade（flag on）
      └── LegacyAnkiImportFacade   （flag off）
```

二者是用户在进入流程前确定的路径。Official 运行中失败时只提供重试、诊断、恢复或取消，
不得悄悄转入 Legacy。Phase 1 不要求重写整个向导；先抽出 facade，保持 UI 行为可测。

### 12.3 允许切流的顺序

1. debug 诊断页。
2. internal build 的隐藏 official import 入口。
3. 测试渠道显式选择 official。
4. Phase 2/3/4 完成后才讨论新导入默认 official。

## 13. Android 构建与真机专项（C1）

### 13.1 目标

生成本轮、可追溯的 arm64 debug/release APK，确认 `.so` 来自当前 commit，并在真机跑完：

```text
ENGINE_INFO → open → check → import fixture → page cards → close → reopen
```

### 13.2 OOM 排查顺序

1. 记录构建前可用内存、swap、Java/Gradle 进程和 Flutter/JDK 版本。
2. 停止陈旧 Gradle daemon，确保没有并行 Flutter/Gradle build。
3. 使用 `--no-daemon`、`--max-workers=1` 的等价 Gradle配置验证峰值。
4. 保持 `-Xmx4G` 为基线，不以盲目加大 heap 作为第一动作。
5. 如本机仍 OOM，使用有足够 RAM/swap 的干净 CI/构建机；记录资源配置。
6. 分别构建 debug 和 split-per-ABI release，不复用旧 APK 作为证据。
7. 检查 APK zip entry、ABI、动态依赖、导出符号和 strip 状态。

候选命令需在执行报告中按实际环境修正：

```bash
./native/turna_anki_core/build-android/build.sh
flutter build apk --debug --target-platform android-arm64
flutter build apk --release --split-per-abi --target-platform android-arm64
unzip -l <apk> | rg 'lib/arm64-v8a/libturna_anki.so'
```

不要把手工复制且时间戳早于构建的 `.so` 当作可重复打包流程。正式脚本要从固定 Cargo
artifact 复制 strip 后产物，并验证 SHA-256。

### 13.3 真机矩阵

最低要求：

- 一台 Android 8/API 26 左右 arm64 低内存设备或等价模拟器。
- 一台当前 Android arm64 真机。
- debug 和 release 各至少一次冷启动。
- 安装、升级安装、强杀重启、后台恢复。
- import/取消/重开各一次；release 下确认符号未被错误裁剪。

记录设备型号、Android/API、ABI、可用内存、APK SHA-256、`.so` 大小、logcat 摘要。

## 14. 许可、体积与发布条件

### 14.1 C2 体积

产品必须在下列方案中书面选择并记录：

- 接受 arm64 包 strip 后约 16 MiB native 增量。
- 使用按 ABI 分发的 AAB/split APK 控制单设备下载。
- 另立按需交付方案；不得在 Phase 1 临时发明网络下载可执行库。

未有决策时可以开发，不得发布含 `.so` 的外部包。

### 14.2 C3/C4 许可

- 两个生产 `showLicensePage()` 入口都必须在调用前执行
  `registerOfficialAnkiLicenses()`，并有 widget/unit test。
- 对外包诊断页显示准确的 Anki commit。
- source offer、对应源码、patch 和构建说明与 release artifact 对齐。
- 法律负责人给出书面 GO 或 GO WITH CONDITIONS；工程师不能代替法律签字。

### 14.3 C5 patch

CI 校验 `0001-export-progress-state.patch` 可针对 pinned submodule replay。上游升级必须独立 PR，
重新生成许可材料、native hash 并重跑所有 fixture/contract/Android 门禁。

## 15. 可观测性

每次请求记录：

- request ID、operation、duration、result/error code。
- contract major/minor、backend commit、app build channel。
- source ID/attempt ID 的不可逆或内部 ID。
- progress stage、current/total、cancel latency。
- Collection state 和 recovery decision。

默认禁止记录：

- Note 字段、HTML、typed answer、媒体内容。
- 完整文件 URI、application support 绝对路径。
- 用户账号、AnkiWeb credential。

诊断导出要能回答：“哪一个 native、哪一个 contract、哪次 attempt、停在哪个阶段、
能否安全重试”。

## 16. 工作包与依赖

```text
P1-000 基线冻结
  ├── P1-001 ABI 安全修复 ── P1-002 Native 质量门禁
  ├── P1-003 C1 Android 构建 ── P1-004 真机闭环
  └── P1-005 contract v1
          └── P1-006 稳定 Engine/worker
                  ├── P1-007 正式 Native import/query API
                  ├── P1-008 路径与 profile 布局
                  └── P1-009 catalog schema
                           └── P1-010 import Saga
                                   ├── P1-011 恢复/故障注入
                                   ├── P1-012 feature flag/入口
                                   └── P1-013 性能与 100k

P1-014 C2 体积决策 ─┐
P1-015 C3/C4/C5 ───┼── P1-016 CI/发布门禁 ── P1-017 结果报告
P1-004 真机闭环 ───┘
```

P1-001 与 P1-003 可以并行思考，但包含 `.so` 的真机运行必须使用 P1-001 修复后的产物。
P1-012 可以先抽 facade，不能在 P1-004、P1-005、P1-010、P1-011 完成前打开 release flag。

## 17. 逐任务施工单

### P1-000：冻结基线与证据目录（0.5 日）

交付：

- 记录 Turna HEAD、submodule commit、patch hash、Rust/NDK/Flutter/JDK/Gradle 版本。
- 新建 Phase 1 evidence 目录规则，但不提交 APK 二进制。
- 把 C1 根因从旧插件错误更新为本轮 OOM 事实。
- 记录相关脏树文件，禁止把无关用户改动纳入 commit。

验收：基线命令可复跑，结果报告能区分旧产物和本轮产物。

### P1-001：修复 C ABI 内存安全（0.5～1 日）

交付：

- `Box<[u8]>` 返回/释放。
- 删除伪造 `'static` 请求 slice。
- 指针/长度/最大 payload 和 panic boundary 测试。

验收：Rust unit/integration 全绿；重复 alloc/free 压测通过；无 sanitizer/Miri 可解释告警。

### P1-002：Native 质量门禁（0.5 日）

交付：

- 清除 7 个现有 warning。
- `cargo fmt --check`、`cargo test`、`cargo clippy -- -D warnings`。
- patch replay 和导出 symbol 检查。

验收：本地和 CI 同命令通过。

### P1-003：关闭可重复 Android 构建（1～3 日）

交付：

- 受控内存的 build script/CI job。
- arm64 debug/release APK。
- APK、`.so` SHA-256/size/symbol/dynamic dependency 报告。

验收：从固定 commit 在干净环境连续两次产物结构一致；不要求 APK 签名 bit-for-bit 相同。

### P1-004：关闭真机 FFI 门禁（1～2 日）

交付：

- 两类设备的 debug/release smoke log。
- 真机 import、cancel、close/reopen、强杀恢复证据。
- Native 崩溃和 tombstone 检查。

验收：无 `UnsatisfiedLinkError`、allocator crash、ANR 或 Collection 损坏。

### P1-005：冻结 contract v1（1～2 日）

交付：

- `VERSION`、operation registry、compatibility rules、golden JSON。
- Rust typed DTO 与 Dart typed DTO。
- runtime `ENGINE_INFO`，移除 Dart 硬编码 commit 的事实源角色。
- proto 归档或真实接入，只保留一个 wire truth。

验收：Rust→Dart golden、未知字段、错误 major、缺字段、超大 payload 全部测试通过。

### P1-006：稳定 Engine 与 worker isolate（2 日）

交付：

- `OfficialAnkiEngine` interface、FFI/fake 实现。
- 持久 worker isolate、串行队列、request ID、cancel 和 dispose。
- DI 生命周期与 profile 切换。

验收：并发发起 import/check/close 不会产生双 owner；UI isolate 无长同步调用。

### P1-007：正式 import/query API（2～3 日）

交付：

- 结构化 progress/cancel。
- 完整递归 deck tree。
- page search、Note→Cards batch、Card descriptor batch。
- import log 覆盖 new/updated/duplicate/conflict 的关联语义。

验收：9 fixture 的来源 Card 集合与 expected 一致；100k 不构造全量字段 JSON。

### P1-008：profile 路径与文件安全（1 日）

交付：

- `OfficialAnkiPaths` 和 Native root validation。
- engine.json atomic write。
- 路径穿越、symlink、相同路径、非法 profile ID 测试。

验收：只可访问当前 profile 官方根目录和受控临时导入文件。

### P1-009：catalog schema 与 DAO（1～2 日）

交付：

- 关于独立数据库的 ADR。
- Drift schema v1、DAO、migration test。
- source/attempt/Card association 不变量。

验收：fresh/reopen/future-version/downgrade 测试通过；没有官方字段镜像列。

### P1-010：import Saga（2～3 日）

交付：

- hasher、orchestrator、state transition API、checkpoint 调用。
- 批量 cursor 和完成核对。
- 重复 hash 与更新候选处理。

验收：正常、重复、取消、无效包、磁盘不足、Collection locked 全部得到确定状态。

### P1-011：恢复与 fault matrix（2 日）

交付：

- 启动时扫描非终态 attempt。
- resume/retry/reconcile/explicit rollback 决策器。
- §10.4 九个 fault injection 测试。

验收：没有未解释的 `active` 半成品；重复启动 recovery 幂等。

### P1-012：feature flag 与入口 facade（1～2 日）

交付：

- typed flags/capability guard。
- official/legacy facade 分离。
- 内部入口、进度、取消、错误与来源摘要。

验收：默认 flag off 保持现有行为；flag on 失败不调用 Legacy；关闭 flag 不丢数据。

### P1-013：规模与资源门禁（1 日）

交付：

- 5k、100k import+index+reopen 数据。
- peak RSS、payload peak、cancel latency、首次 open、APK delta。
- page size 调优结论。

验收：无全量 materialization；阈值超标有明确 No-Go 或已批准预算。

### P1-014：C2 产品体积决策（非代码）

交付：ADR/产品纪要，写清 distribution 方案与预算。

验收：负责人、日期、目标 APK/AAB delta 和决策齐全。

### P1-015：C3/C4/C5 合规关闭（0.5～1 日 + 外部签字）

交付：生产 License 页钩子、source offer、法律结果、patch replay CI。

验收：对外构建手工检查可见，release commit 与 source bundle 可追溯。

### P1-016：CI 与发布门禁（1～2 日）

交付：

- Host Rust/contract job。
- Android arm64 native build 和 APK inspection job。
- Dart/Drift/fault matrix job。
- submodule pin、patch、license、backend metadata 一致性检查。

验收：干净 runner 通过；缓存失效时仍可构建；失败不会使用陈旧 `.so`。

### P1-017：Phase 1 结果报告与决策（0.5 日）

交付：`04-phase-1-result-report.md`，结论只能是 Go、Conditional Go 或 No-Go。

验收：逐项引用 commit、测试、设备与 artifact 证据；未测项目不得写“通过”。

## 18. 测试矩阵

### 18.1 Rust

- ABI alloc/free、null/zero/oversize/invalid UTF-8/invalid JSON。
- panic mapping、invalid handle、double open、busy close、cancel 幂等。
- contract version/golden/unknown field。
- path canonicalization/symlink escape。
- import new/update/duplicate/conflict/legacy/latest/cancel。
- recursive deck、paged query、stale token、batch bounds。
- checkpoint/check/reopen。

### 18.2 Dart

- fake engine 的完整 state machine。
- worker 顺序、cancel race、dispose race、profile switch。
- native error→domain error→localized presentation。
- large page decode 不在 UI isolate。
- official failure 不触发 legacy mock。
- runtime engine metadata 与 build expectation 不一致时 fail closed。

### 18.3 Database/Saga

- fresh schema、migration、reopen、foreign key、unique hash。
- 每个合法/非法状态转换。
- batch cursor transaction rollback。
- 九个 fault point 和连续两次 recovery。
- 多 source 指向同 card、删除一个 source 不影响另一个。
- 未来 schema/旧 app downgrade 明确拒绝或安全只读，不静默 wipe journal。

### 18.4 Android

- debug/release load、冷启动、升级安装。
- file picker URI 权限和大文件 hash。
- 进度刷新、取消延迟、后台/前台、强杀。
- 低存储和低内存。
- APK 中 ABI、symbol、license、commit metadata。

### 18.5 Fixture 期望

| Fixture | Phase 1 关注点 |
|---|---|
| Basic Unicode | 字段不被 Turna 解码/重写，来源计数正确 |
| Reverse | 一 Note 多 Card 关联完整 |
| Cloze | 多 ord Card 关联完整 |
| FrontSide | 导入不预渲染、不镜像 HTML |
| media/unicode filename | 官方媒体导入成功，Turna 不自行改名 |
| legacy package | 官方 importer 兼容性 |
| malformed | typed error、无 active source |
| 5k/100k | 分页、内存、取消、重开 |

## 19. 建议命令门禁

以下是候选基线；执行时应使用仓库脚本封装 pinned `PROTOC`/NDK，不在 CI 依赖个人
shell 环境：

```bash
./native/turna_anki_core/build-android/host-test.sh
cargo fmt --manifest-path native/turna_anki_core/bridge/Cargo.toml --check
cargo clippy --manifest-path native/turna_anki_core/bridge/Cargo.toml --all-targets -- -D warnings
flutter test test/application/anki_official
dart analyze lib/application/anki_official test/application/anki_official
./native/turna_anki_core/build-android/build.sh
flutter build apk --release --split-per-abi --target-platform android-arm64
```

如果 analyze 仅因 sandbox 无法写 telemetry 而返回非零，报告必须同时保留“No issues
found”和真实 exit 原因；CI 中应提供可写的工具目录，以退出码为准。

## 20. Commit 与评审策略

- 一张 P1 任务一个主 commit；不要把格式化全仓、生成文件和无关用户改动混入。
- Native ABI、contract、database migration、production entry 分开评审。
- Drift codegen 与 schema 源在同一个 commit。
- submodule pin/patch 变化单独 commit。
- 每个 commit message 带 `P1-xxx` 或在正文引用任务号。
- 对 `abi.rs`、contract、migration、Saga recovery 至少要求一名第二 reviewer。
- 生产入口 PR 在最后合并，即使 facade 可以更早准备。

## 21. 进度记录模板

每完成一项在结果报告记录：

```text
任务：P1-xxx
状态：not-started / in-progress / blocked / done
Commit：<sha>
命令：<exact command>
结果：<passed/failed + count>
Artifact：<path + sha256 + bytes>
设备：<model/API/ABI/RAM> 或 host
指标：<duration/RSS/cancel latency>
未决：<risk/owner/date>
```

任务只有在“实现 + 测试 + 证据”齐全时才能标 `done`。代码存在但没有真机/恢复证据的，
最多标 `implemented, not accepted`。

## 22. Phase 1 退出评审问题

评审会必须逐项回答：

1. 当前 APK 内的 `.so` 是否由 pinned commit 和已记录 patch 构建？
2. Dart 与 Native 是否在运行时确认同一 contract major？
3. allocator、panic 和 request lifetime 是否已证明安全？
4. 100k 是否仍有一次性全量 JSON/字段 materialization？
5. app 在 import 的每一个崩溃点重启后会进入什么状态？
6. 官方导入成功、Turna 索引失败时是否可以幂等续跑？
7. 是否存在任何 official failure→legacy silent fallback？
8. catalog downgrade 是否可能静默擦除 recovery journal？
9. debug/release 是否都在真机加载并重开 Collection？
10. 体积、AGPL About、source offer 和法律签字是否齐全？
11. Phase 2 是否能在不修改 Phase 1 数据所有权的情况下接入官方渲染？
12. 仍有哪些条件必须阻止 release flag 打开？

任何问题没有证据时，结论不得写无条件 Go。

## 23. 开工顺序

下一次施工从以下顺序开始：

1. P1-000 冻结新基线。
2. P1-001 修复 FFI allocator/lifetime，先消除潜在崩溃源。
3. P1-002 清 warning 并建立 Native 门禁。
4. P1-003 用受控内存关闭 APK 构建。
5. P1-004 在修复后的 `.so` 上完成真机闭环。
6. P1-005 冻结真实 contract，然后才扩正式 Dart API。
7. P1-006～P1-011 完成 Engine、catalog、Saga 与恢复。
8. P1-012 最后接入内部生产入口。
9. P1-013～P1-017 完成性能、合规、CI 和退出报告。

第一张代码票不是修改 `anki_import_screen.dart`，而是修复 `abi.rs` 的内存所有权。
第一张平台票仍是 C1，但必须在 allocator 修复后的产物上验收。
