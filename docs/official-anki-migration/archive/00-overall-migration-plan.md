# Turna 迁移到官方 Anki Core 的完整方案

> 文档导航：[迁移文档索引](../README.md) · [第一阶段实施方案](./01-phase-0-implementation-plan.md)

> 文档状态：提案 / 待阶段 0 验证  
> 适用项目：Turna（原 VarnamalaPlus）  
> 编写日期：2026-08-16  
> 官方 Anki 本地参考仓库：`/home/whwen/documents/reso/Varnamalaplus/anki`  
> 参考提交：`967aa0d578fc75181e292e95326f9b58698da25c`  
> 参考版本描述：`25.09.2-370-g967aa0d57`  
> 目标首发平台：Android arm64  

## 1. 执行摘要

当前 Turna 的 Anki 功能同时维护了自研包解析、数据库读取、模板渲染、HTML 渲染、WebView 回退、媒体复制、课程投影和调度迁移。多个事实源之间缺乏严格边界，已经导致以下用户可见问题：

- 部分字段、媒体文件名和 Unicode 内容出现乱码。
- Reverse Card、`FrontSide`、Cloze ordinal 等官方模板语义无法稳定复现。
- 同一张卡可能在 Flutter HTML、WebView 和预渲染缓存之间切换。
- 卡片能够显示正面但无法按官方模板得到正确背面。
- Turna 自研 SRS 状态与 Anki 的队列、FSRS、revlog 和撤销语义不一致。
- 新旧 `.apkg`、zstd、Protobuf 和 Collection schema 的适配工作不断扩散。
- 已存在大量实验模块，但生产导入入口仍然主要依赖旧的 `AnkiImporter`。

本方案决定将官方 `ankitects/anki` 的 Rust 核心 `rslib` 作为唯一的 Anki 事实源：

1. `.apkg` 导入由官方 Core 完成。
2. Note、Card、Notetype、Deck、媒体和调度状态保存在官方 Collection 中。
3. 原始 Anki 卡片的正反面由官方模板引擎生成。
4. Anki 卡片复习由官方队列和 FSRS 管理。
5. Turna 只保存来源关联、课程位置、语言字段映射和可重建的练习投影。
6. 原始 Anki 卡固定使用隔离 WebView；Turna 派生练习固定使用 Flutter Widget。
7. Dart 不直接依赖上游 Protobuf、数据库 schema 或 service/method 数字编号。

推荐集成方式为：

```text
Flutter / Dart
    ↓ Turna 自有稳定 DTO
Rust FFI bridge（libturna_anki.so）
    ↓ 固定提交的内部 Rust API
官方 anki::Collection / rslib
    ↓
官方 collection.anki2 + media + media DB
```

不建议：

- 继续扩展 Turna 自研 Anki 解析器或模板引擎。
- 把整个 Anki Desktop 的 Python、Qt 和桌面前端移植进 Flutter。
- 将 AnkiDroid UI 直接嵌入 Turna。
- 将官方 Protobuf 直接生成 Dart API 并作为长期公共契约。
- 在官方渲染失败时静默回退到旧渲染器。
- 对同一张 Anki 卡同时写官方调度和 Turna SRS。

## 2. 目标与非目标

### 2.1 目标

迁移完成后必须满足：

- 使用官方实现导入当前官方 Anki 支持的包格式。
- 使用官方 Collection 保存 Anki 数据，不再复制原始 Note/Notetype/Card。
- Basic、Basic and Reversed、Cloze、`FrontSide` 和特殊字段按官方语义渲染。
- 图片、音频、TTS 标签、自定义字体、CSS、MathJax 和 typed answer 有明确处理路径。
- Again、Hard、Good、Easy 直接提交官方调度状态。
- 支持官方 Undo、Bury、Suspend、Deck counts 和完成状态。
- Turna 的 Section、Unit、Lesson 和语言练习仍能使用 Anki 内容。
- 新旧引擎可以在迁移期被明确识别，但不得双写同一张卡。
- 所有上游变化都封闭在 Rust bridge 中。
- Android 主线程不得执行 Collection I/O、导入、搜索或调度计算。
- 导入、投影和迁移具备恢复、取消、日志和回滚机制。

### 2.2 “完全适配官方 Anki”的定义

本项目中的“完全适配”定义为“官方核心语义兼容”，包括：

- 官方 Collection 数据模型。
- 官方包导入和更新规则。
- 官方模板渲染核心。
- 官方 Deck、Search、Card、Note、Media API。
- 官方 Scheduler、FSRS、revlog 和 Undo。
- 官方支持的 AV/TTS 标签和 typed answer 后端能力。

它不等同于完整复制 Anki Desktop 环境。

### 2.3 明确非目标

第一轮迁移不承诺：

- 运行 Anki Desktop Python add-on。
- 运行 add-on 注入的模板 hook 或 Python 自定义过滤器。
- 复制 Qt 菜单、Browser、编辑器和插件管理界面。
- 完全兼容任意访问互联网或本地文件的卡片 JavaScript。
- 与 AnkiWeb 或官方 Anki 账号做 Collection / Media 同步（P6 已取消，不考虑）。
- 首期完成 OHOS、iOS、macOS、Windows 和 Linux 的官方 Core 打包。
- 把 Turna 自有课程也迁入 Anki Collection。

## 3. 当前实现诊断

### 3.1 当前生产链路

当前导入入口在：

- `lib/views/anki/anki_import_screen.dart`
- `_AnkiImportPageState` 直接实例化 `AnkiImporter`。
- 文件选择后调用 `_importer.parse()`。
- 解析结果作为完整 `AnkiCollection` 传入 `AnkiImportService`。

当前持久化链路在：

- `lib/application/anki/anki_import_service.dart`
- `AnkiDeckAssembler`
- `AnkiSrsMigrator`
- `AnkiAudioResolver`
- `AnkiImportDao`
- `AnkiNoteDao`

当前渲染链路在：

- `lib/application/anki/anki_canonical_card_loader.dart`
- `lib/application/anki/anki_template_renderer.dart`
- `lib/application/anki/anki_card_html_renderer.dart`
- `lib/application/anki/anki_render_policy.dart`
- `lib/application/anki/anki_render_fallback_chain.dart`
- `lib/views/anki/anki_html_card_view.dart`
- `lib/views/anki/anki_flutter_html_view.dart`
- `lib/views/lesson/components/interactions/anki_html_card_renderer.dart`

当前调度链路在：

- `lib/application/anki/anki_srs_migrator.dart`
- `lib/application/anki/anki_queue_policy.dart`
- `lib/application/anki/anki_review_assembler.dart`
- `lib/application/anki/anki_review_commit_service.dart`
- Turna `SrsProvider` / `srs_states`

### 3.2 重复事实源

Turna 当前数据库保存了官方 Collection 已经拥有的信息：

- `anki_notetypes`
- `anki_notes`
- `anki_cards_meta`
- `anki_prerendered_html`
- 卡片 scheduling JSON
- 拷贝后的 import media 目录

这意味着一次导入后至少存在：

```text
.apkg 中的数据
Turna 内存 AnkiCollection
Turna Drift 中的 Anki 镜像表
Turna Lesson JSON/CardRef
Turna SRS 状态
Turna media copy
Turna prerender cache
```

任何层发生丢字段、编码变化、ID 转换或模板误判，最终展示都会偏离原卡。

### 3.3 乱码的主要成因

乱码不一定来源于单一 UTF-8 解码错误，当前链路存在多种可能：

- 对旧/新 Collection schema 使用自研读取路径。
- zstd 解压和 package metadata 分支不完整。
- Protobuf wire 自行解释造成字段类型或边界错误。
- SQLite text/blob 判断不一致。
- 媒体文件名经过 URI、文件系统和 JSON 多次编码。
- Note 字段在 HTML strip、JSON 和重建模板之间发生二次转换。
- Unicode normalization 在媒体索引与文件名之间不一致。

迁移后禁止 Dart 直接解释 Anki 的 SQLite、zstd 和 Protobuf 内容，所有包格式兼容问题归还官方 Core。

### 3.4 翻转卡失败的主要成因

Anki 的背面不是简单交换 Front/Back 字段。正确背面可能依赖：

- 当前 Card template ordinal。
- `qfmt` 与 `afmt`。
- `{{FrontSide}}`。
- 条件字段。
- Cloze ordinal。
- 特殊字段和过滤器。
- Note type 的模板顺序。

任何“取字段 0 为正面、字段 1 为背面”或“根据字段名猜方向”的策略都无法可靠支持 Reverse Card。

### 3.5 WebView 混乱的主要成因

WebView 不是根本问题。官方 Anki Reviewer 本身也使用 HTML/JavaScript 前端显示后端渲染结果。

当前问题是渲染选择不确定：

- 普通卡优先 Flutter HTML。
- 遇到 JS/MathJax/复杂 CSS 再切 WebView。
- 某些卡片先使用预渲染 HTML。
- 失败时进入 fallback chain。
- 正面和背面可能走不同的内容重建路径。

迁移后不再猜测：原始 Anki Card 总是 WebView，派生 Turna 练习总是 Flutter。

## 4. 官方 Anki Core 能力核对

### 4.1 Collection 生命周期

官方 `rslib/src/collection/mod.rs` 提供 `CollectionBuilder`：

- 指定 Collection path。
- 指定 media folder。
- 指定 media DB。
- 注入翻译资源。
- 注入共享 progress state。
- 打开、创建和关闭 Collection。

移动端应显式调用 `set_media_paths()`，不依赖 Desktop 的路径推导。

### 4.2 Package 导入

官方 `Collection::import_apkg()`：

- 读取 zip/package metadata。
- 支持官方当前 package 数据格式。
- 导入媒体。
- 处理 Note/Notetype/Deck 冲突。
- 可保留 scheduling 和 deck configs。
- 在官方事务中完成导入。
- 返回 Note import log。

Import log 可用于构建 Turna 的来源关联。

### 4.3 卡片渲染

官方 `render_existing_card()` 根据 Card ID 查询：

- Card。
- Note。
- Notetype。
- 当前模板或 Cloze 模板。
- Deck、Subdeck、Tags、Card、CardFlag 等特殊字段。

官方 `CardRenderingService` 还提供：

- `ExtractAvTags`
- `ExtractLatex`
- `EncodeIriPaths`
- `DecodeIriPaths`
- `StripHtml`
- `HtmlToTextLine`
- `CompareAnswer`
- `ExtractClozeForTyping`

### 4.4 Scheduler

官方 Scheduler 提供：

- `GetQueuedCards`
- `AnswerCard`
- `GetSchedulingStates`
- `DescribeNextStates`
- `CountsForDeckToday`
- `CongratsInfo`
- `BuryOrSuspendCards`
- `ScheduleCardsAsNew`
- `SetDueDate`
- FSRS 参数与记忆状态计算

`QueuedCard` 已包含当前 Card、队列分类、四档下一状态和 SchedulingContext。前端不应自行重新计算下一间隔。

### 4.5 Undo 和取消

Collection service 提供：

- `GetUndoStatus`
- `Undo`
- `Redo`
- `LatestProgress`
- `SetWantsAbort`

官方共享 progress state 会定期检查 abort 标记。Turna 应轮询进度并通过官方取消通道终止长操作。

### 4.6 Android 适配基础

官方代码已经存在 Android 特殊处理，例如：

- Android SQLite `temp_store=memory`。
- Android backup 时间戳分支。
- Android 媒体文件时间兼容。
- `ankidroid.proto` 和 AnkiDroid service。

这说明 `rslib` 本身适合构建为 Android 后端，但官方 Desktop 仓库没有直接给 Turna 提供现成 Flutter 插件。Turna 仍需维护自己的 NDK/FFI 打包层。

## 5. 方案选型

### 5.1 选项 A：继续维护当前自研实现

优点：

- 无新增 Rust 构建链。
- 当前 Flutter 代码可以逐步修补。
- 安装包体积短期不增加。

缺点：

- 必须长期追踪官方包格式和 schema。
- 必须重写模板、Cloze、typed answer 和调度语义。
- 乱码和渲染分歧无法从架构上消失。
- 自研实现的测试成本接近重做一个 Anki Core。

结论：否决。

### 5.2 选项 B：移植整个 Anki Desktop

优点：

- 理论上最接近 Desktop UI。

缺点：

- 包含 Rust、Python、Qt、TypeScript、桌面媒体服务器和插件环境。
- 与 Flutter UI 和移动端生命周期冲突。
- 体积、构建、线程、安全和平台适配成本过高。

结论：否决。

### 5.3 选项 C：直接依赖 AnkiDroid Backend/AAR

优点：

- 已验证官方 Core 的 Android 编译和打包。
- 可复用 Kotlin/JNI 经验。

缺点：

- API 主要服务 AnkiDroid 自身。
- Android-only。
- Turna 会同时依赖 Anki 上游和 AnkiDroid 包装层的版本变化。
- Dart 仍需 Kotlin/JNI 二次桥接。

结论：作为构建参考或阶段 0 对照，不作为首选长期公共接口。

### 5.4 选项 D：官方 rslib + Turna Rust FFI

优点：

- 官方核心语义。
- 桥接面可保持很小。
- Dart 契约由 Turna 控制。
- Android 首发后仍可评估其他 native 平台。
- 可以只打包 Turna 实际需要的能力。

缺点：

- 需要维护 Rust/NDK 构建。
- 上游 Rust API没有稳定 semver 保证。
- Web Reviewer 前端仍需 Turna 补齐。
- 需要严格处理 AGPL 合规。

结论：采用。

## 6. 目标目录结构

建议新增：

```text
native/
└── turna_anki_core/
    ├── README.md
    ├── Cargo.toml
    ├── Cargo.lock
    ├── rust-toolchain.toml
    ├── anki/                       # 固定 tag/commit 的 git submodule
    ├── bridge/
    │   ├── Cargo.toml
    │   └── src/
    │       ├── lib.rs
    │       ├── abi.rs
    │       ├── engine.rs
    │       ├── errors.rs
    │       ├── import.rs
    │       ├── render.rs
    │       ├── review.rs
    │       ├── query.rs
    │       └── progress.rs
    ├── contract/
    │   ├── turna_anki.proto
    │   ├── VERSION
    │   └── compatibility.md
    ├── build-android/
    │   ├── build.sh
    │   └── verify-symbols.sh
    └── licenses/
        ├── ANKI-LICENSE
        ├── THIRD-PARTY-NOTICES.md
        └── SOURCE-OFFER.md
```

Dart 侧建议新增：

```text
lib/application/anki_official/
├── official_anki_engine.dart
├── official_anki_engine_ffi.dart
├── official_anki_contract.dart
├── official_anki_errors.dart
├── official_anki_import_orchestrator.dart
├── official_anki_course_projector.dart
├── official_anki_review_controller.dart
└── official_anki_migration_service.dart

lib/views/anki_official/
├── official_anki_card_view.dart
├── official_anki_review_page.dart
├── official_anki_import_page.dart
└── official_anki_compatibility_report.dart
```

命名可在实现时调整，但必须保持 `official` 与 `legacy` 边界清晰，禁止继续把新旧逻辑放进同一个大型文件。

## 7. Native bridge 设计

### 7.1 为什么不直接暴露官方 RPC 编号

官方 service/method index 是根据 Protobuf service 顺序生成的。上游新增 RPC 后编号可能变化，而且官方明确说明 Protobuf 当前不是公共 API。

因此以下接口禁止出现于 Dart：

```dart
runServiceMethod(int service, int method, Uint8List protobuf);
```

### 7.2 C ABI

建议保持 ABI 极小：

```c
typedef uint64_t TurnaAnkiHandle;

TurnaAnkiResult turna_anki_engine_new(
    const uint8_t* config,
    size_t config_len
);

TurnaAnkiResult turna_anki_engine_open(
    TurnaAnkiHandle handle,
    const uint8_t* request,
    size_t request_len
);

TurnaAnkiResult turna_anki_call(
    TurnaAnkiHandle handle,
    uint32_t operation,
    const uint8_t* request,
    size_t request_len
);

TurnaAnkiResult turna_anki_cancel(TurnaAnkiHandle handle);
TurnaAnkiResult turna_anki_engine_close(TurnaAnkiHandle handle);
void turna_anki_buffer_free(uint8_t* ptr, size_t len);
```

所有返回内存必须由同一动态库释放，禁止 Dart 直接释放 Rust allocator 分配的内存。

### 7.3 Turna operation

第一版至少包含：

```text
ENGINE_INFO
OPEN_COLLECTION
CLOSE_COLLECTION
CHECK_COLLECTION
CREATE_BACKUP
IMPORT_PACKAGE
LATEST_PROGRESS
CANCEL_OPERATION
LIST_DECK_TREE
SEARCH_CARDS
GET_CARD_DESCRIPTOR
GET_NOTE_DESCRIPTOR
GET_CARDS_OF_NOTE
RENDER_CARD
EXTRACT_AV_TAGS
COMPARE_TYPED_ANSWER
EXTRACT_CLOZE_FOR_TYPING
SET_CURRENT_DECK
GET_REVIEW_QUEUE
DESCRIBE_NEXT_STATES
ANSWER_CARD
GET_UNDO_STATUS
UNDO
REDO
BURY_CARDS
SUSPEND_CARDS
GET_DECK_COUNTS
GET_CONGRATS_INFO
```

operation number 属于 Turna contract，发布后不可重排，只能追加。

### 7.4 Contract 版本

每次请求包含：

```text
contract_version
request_id
operation
payload
```

每次响应包含：

```text
contract_version
request_id
ok
payload
error_code
error_message
error_details
backend_commit
duration_ms
```

Bridge 必须拒绝未知的主版本。次版本新增字段使用向后兼容规则。

### 7.5 Bridge 内部调用方式

首选：

- 直接持有 `anki::collection::Collection`。
- 调用公开的 Collection 方法。
- 对没有直接公开高层方法的能力，在 Rust 内调用生成的公开 service trait。
- 将上游 protobuf 立即转换为 Turna DTO。

不首选：

- 从 Dart 传 service/method index。
- Dart 直接读取 `collection.anki2`。
- Dart 持有上游 protobuf message。
- 为课程字段修改官方 Collection schema。

如果批量读取性能不足，按以下顺序优化：

1. 在 bridge 内循环调用服务，而不是 Dart 循环 FFI。
2. 增加 Turna bridge 的 batch operation。
3. 最后才考虑对固定的 Anki fork 增加一个极小的批量 descriptor API。

禁止为了批量读取而在 Dart 中执行官方数据库 SQL。

### 7.6 线程模型

每个 profile 一个 Engine：

```text
UI isolate
    ↓ request
Dart Anki worker isolate
    ↓ FFI
Rust engine worker / single collection owner
    ↓
SQLite exclusive collection
```

规则：

- Collection 只在一个受控原生线程或互斥区内访问。
- UI isolate 不执行同步 FFI 长任务。
- Import、backup、check、search 和 queue build 都可返回进度。
- Cancel 通过共享 progress state 设置 abort。
- Engine close 等待当前操作到达安全取消点。
- App 进入后台时不强杀正在提交的 answer/import transaction。

## 8. Collection 与媒体布局

### 8.1 推荐：每个 Turna profile 一个全局 Collection

```text
<app-files>/anki/profiles/<profile-id>/
├── collection.anki2
├── collection.media/
├── collection.media.db2
├── backups/
└── engine.json
```

`engine.json` 仅保存外部元数据：

```json
{
  "backendCommit": "...",
  "contractVersion": 1,
  "createdAt": 0,
  "lastOpenedAt": 0,
  "collectionSchema": 0
}
```

选择全局 Collection 的原因：

- Deck 层次保持官方语义。
- FSRS 和每日限制无需跨 Collection 合并。
- 同一 Note 的重复导入和更新遵循官方规则。
- 官方 Scheduler / FSRS / 每日限制只需一套生命周期。
- 只需维护一个 Collection 生命周期。

### 8.2 不推荐：每个 `.apkg` 一个 Collection

它虽然隔离性好，但会造成：

- 多 Collection 队列需要 Turna 自行合并。
- 每日限制、Filtered Deck 和 Scheduler context 被分裂。
- 与官方全局调度、每日限制、重复 Note 语义冲突。
- 重复 Note 无法按官方全局语义更新。
- 同时打开多个 SQLite Collection 的资源成本更高。

### 8.3 媒体 URL

WebView 内不直接使用 `file://`。

建议将官方渲染结果中的媒体相对路径解析到：

```text
https://anki.local/media/<encoded-path>
```

资源拦截器只能读取 `collection.media` 根目录下经过 canonicalize 验证的文件。

必须拒绝：

- `..` 路径穿越。
- 绝对路径。
- `file://`。
- `content://`，除非是受控导入临时源。
- 指向应用其他私有目录的符号链接。

## 9. Turna 数据模型

### 9.1 官方 Collection 是唯一事实源

以下信息只存在官方 Collection：

- Note 字段和 GUID。
- Notetype、模板和 CSS。
- Card、Deck 和 ordinal。
- Scheduler state。
- Revlog。
- Deck config。
- 官方媒体清单。

### 9.2 Turna 只保存投影与关联

建议表：

```sql
CREATE TABLE anki_sources (
  source_id TEXT PRIMARY KEY,
  source_hash TEXT NOT NULL,
  display_name TEXT NOT NULL,
  original_path TEXT,
  imported_at INTEGER NOT NULL,
  backend_commit TEXT NOT NULL,
  contract_version INTEGER NOT NULL,
  import_options_json TEXT NOT NULL,
  state TEXT NOT NULL,
  last_error_code TEXT,
  last_error_message TEXT
);

CREATE UNIQUE INDEX anki_sources_hash_idx
  ON anki_sources(source_hash);

CREATE TABLE anki_source_cards (
  source_id TEXT NOT NULL REFERENCES anki_sources(source_id),
  card_id INTEGER NOT NULL,
  note_id INTEGER NOT NULL,
  deck_id INTEGER NOT NULL,
  note_guid TEXT,
  template_ord INTEGER NOT NULL,
  PRIMARY KEY(source_id, card_id)
);

CREATE INDEX anki_source_cards_card_idx
  ON anki_source_cards(card_id);

CREATE TABLE anki_course_cards (
  card_id INTEGER PRIMARY KEY,
  word_id TEXT NOT NULL UNIQUE,
  section_id TEXT,
  unit_id TEXT,
  lesson_id TEXT,
  sort_order INTEGER NOT NULL,
  projection_version INTEGER NOT NULL
);

CREATE TABLE anki_language_mappings (
  notetype_id INTEGER PRIMARY KEY,
  target_field TEXT,
  native_field TEXT,
  audio_field TEXT,
  example_field TEXT,
  unit_field TEXT,
  lesson_field TEXT,
  option_fields_json TEXT NOT NULL,
  answer_field TEXT,
  user_confirmed INTEGER NOT NULL,
  mapping_version INTEGER NOT NULL
);

CREATE TABLE anki_projection_cache (
  card_id INTEGER NOT NULL,
  projection_kind TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  source_fingerprint TEXT NOT NULL,
  projection_version INTEGER NOT NULL,
  PRIMARY KEY(card_id, projection_kind)
);
```

Drift 实现时字段类型和外键命名可遵循项目约定，但数据所有权不得改变。

### 9.3 来源与 Card 是多对多关系

同一张 Card 可能由多个 `.apkg` 导入来源命中，因此：

- 删除来源时先删除 `anki_source_cards` 关联。
- Card 仍被其他来源引用时不得删除官方 Note/Card。
- Card 无来源后也不自动删除。
- 只有用户明确选择“同时删除原始 Anki 内容”时才删除孤儿数据。

## 10. 官方导入流程

### 10.1 导入状态机

```text
selected
  ↓
hashing
  ↓
backing_up
  ↓
importing_official
  ↓
indexing_cards
  ↓
projecting_course
  ↓
active
```

失败状态：

```text
cancelled
failed_before_import
failed_after_import
needs_reconciliation
rolled_back
```

### 10.2 导入步骤

1. 校验文件可读、扩展名和最小长度。
2. 计算 source hash，但不在 UI isolate 读取大文件。
3. 检查同 hash 来源是否已存在。
4. 创建 `anki_sources(state=selected)`。
5. 创建导入前 Collection backup/checkpoint。
6. 调用官方 `ImportAnkiPackage`。
7. 保存官方 Import log 的 Note IDs。
8. 对每个 Note 调用 `CardsOfNote`，在 Rust 内批量组装 descriptor。
9. 写入 `anki_source_cards`。
10. 获取 DeckTree、Note fields 和必要的 Card descriptor。
11. 生成 Turna 课程树和语言字段候选。
12. 写入课程投影。
13. 标记来源 `active`。

### 10.3 跨数据库一致性

官方 SQLite 和 Turna Drift 无法共享一个 ACID 事务，因此使用 Saga：

- 每个阶段先更新 `anki_sources.state`。
- 官方导入成功后若投影失败，优先调用官方 Undo。
- 如果 App 已重启或 Undo stack 不再可用，恢复导入前 backup。
- 恢复前验证 backup 的 backend/schema 兼容信息。
- 若不能安全自动恢复，标记 `needs_reconciliation`，禁止重复盲目导入。

### 10.4 更新导入

再次导入同一来源时：

- 使用官方 update options。
- 不自行比较 Note mod 时间决定覆盖。
- 保存新的 Import log。
- 重建该来源的 `anki_source_cards`。
- 对受影响 Card 失效课程投影缓存。
- 用户手动调整的语言字段 mapping 按 notetype ID/fingerprint 保留。
- Deck 移动后重新计算默认课程位置，但不覆盖用户锁定的位置。

## 11. 渲染架构

### 11.1 渲染分类

| 内容 | 数据来源 | 渲染方式 | 是否写官方调度 |
|---|---|---|---|
| 原始 Anki Card | 官方 render | 隔离 WebView | 是 |
| Turna 词汇投影 | 官方字段快照/查询 | Flutter | 否 |
| Turna 选择题 | 显式字段映射 | Flutter | 否 |
| Turna 拼写练习 | 显式字段映射 | Flutter | 否 |
| Turna 自有课程 | Turna DB | Flutter | Turna SRS |

### 11.2 原卡渲染请求

建议 Dart DTO：

```dart
class OfficialAnkiRenderRequest {
  final int cardId;
  final bool browser;
  final bool includeAvTags;
  final ColorSchemeMode colorScheme;
}

class OfficialAnkiRenderedCard {
  final int cardId;
  final String questionHtml;
  final String answerHtml;
  final String css;
  final bool latexSvg;
  final bool isEmpty;
  final List<OfficialAnkiAvTag> questionAvTags;
  final List<OfficialAnkiAvTag> answerAvTags;
  final OfficialAnkiTypedAnswer? typedAnswer;
}
```

Bridge 使用 `partial_render=false` 获取官方完整核心渲染。

### 11.3 正反面生命周期

同一张卡应使用同一个 WebView 实例：

```text
load reviewer shell
    ↓
setQuestion(questionHtml, css)
    ↓ 用户点击显示答案
setAnswer(answerHtml, css)
    ↓ 用户评分
dispose/reuse for next card
```

不得：

- 把问题 HTML 与答案 HTML放到两套不同 Widget 树。
- 通过交换字段实现翻面。
- 将答案附加到问题下方并同时保留两个独立文档上下文。
- 因检测到 `<script>` 才临时改用 WebView。

### 11.4 AV/TTS

官方 Core 负责解析：

- `[sound:...]`
- TTS 标签
- voice、lang、speed 和参数

Turna 负责播放：

- 媒体音频交给 `AudioController`。
- TTS 交给 `SmartSpeech` 或当前平台语音层。
- 切卡和翻面时按官方 question/answer AV tag 分组。
- Stop/Replay 按钮由 Flutter chrome 提供。

非 Windows 平台不能假定官方 Desktop TTS backend 可直接工作。

### 11.5 Typed Answer

流程：

1. 渲染结果识别 typed answer 占位信息。
2. Flutter 或 WebView 显示输入框。
3. Cloze 卡调用官方 `ExtractClozeForTyping`。
4. 用户答案调用官方 `CompareAnswer`。
5. 比较结果作为答案面内容的一部分展示。
6. typed answer 本身不决定官方评分，用户仍选择四档评分。

### 11.6 MathJax 与前端资源

- MathJax 必须随应用离线打包。
- reviewer shell 的 CSS/JS 必须固定版本并记录与 backend commit 的对应关系。
- 不直接复制整个 Qt mediaserver。
- 可参考官方 Reviewer 资源，但需清点其许可证和构建产物来源。
- 资源升级需要 WebView golden 和真实卡组回归。

### 11.7 JavaScript 安全

原始卡片兼容性和安全存在天然冲突。默认策略：

- JavaScript 可在卡片页面执行。
- 禁止文件系统访问。
- 禁止跨 origin 任意网络请求。
- 禁止打开新窗口。
- 禁止下载。
- 禁止通用 native bridge。
- 禁止导航离开 `anki.local`。
- CSP 由 reviewer shell 尽可能收紧。

若未来提供“兼容模式”，必须：

- 按来源显式开启。
- 展示风险说明。
- 记录启用状态。
- 仍不得授予文件系统和任意原生调用。

## 12. 课程框架适配

### 12.1 默认层级映射

```text
Anki root deck       → Turna Section
Anki child deck      → Turna Unit
Tag/explicit field   → Turna Lesson
Anki Card            → Stage/CardRef
```

深度超过 Turna 课程约束时，使用稳定的折叠/分页规则，但不得修改官方 Deck 名称。

### 12.2 字段角色

每个 Notetype 可配置：

- `targetText`
- `nativeText`
- `audio`
- `example`
- `unit`
- `lesson`
- `optionFields`
- `answerField`

字段角色推断只能产生候选和置信度，只有用户确认后才能用于结构化练习。

### 12.3 原卡与派生练习分离

原卡：

- 使用 Card ID。
- 使用官方模板。
- 使用官方 Scheduler。

派生练习：

- 读取明确字段角色。
- 使用 Flutter UI。
- 不修改 Card HTML。
- 不写官方 Scheduler。
- 不从 HTML 文本猜测正确答案。
- 不自动制造无法解释来源的干扰项。

若一个 Lesson 同时包含派生练习和原卡，必须在交互层明确区分“练习”与“正式 Anki 复习”。

## 13. 官方调度接入

### 13.1 队列流程

```text
SetCurrentDeck(deckId)
    ↓
GetQueuedCards(fetchLimit)
    ↓
取 QueuedCard.card / states / context
    ↓
RenderExistingCard(cardId)
    ↓
显示问题 → 显示答案
    ↓
用户选择 Again/Hard/Good/Easy
    ↓
用官方 states 构造 CardAnswer
    ↓
AnswerCard
```

前端构造 `CardAnswer` 时必须携带：

- card ID。
- current state。
- 对应 rating 的 new state。
- rating。
- answered-at milliseconds。
- elapsed milliseconds。
- 官方要求的 SchedulingContext/custom data。

### 13.2 下一间隔标签

按钮上的下一间隔通过 `DescribeNextStates` 获取，不在 Dart 中格式化或重算 FSRS 间隔。

### 13.3 Undo

- Answer 成功后查询官方 Undo status。
- 用户撤销时调用官方 `Undo`。
- Turna 页面状态根据返回的 changes 刷新。
- 不使用删除本地 review history 行来模拟官方撤销。

### 13.4 两套 SRS 的边界

| 内容 | 状态所有者 |
|---|---|
| 官方 Anki Card | 官方 Collection Scheduler |
| Turna 原生词汇 | Turna SRS |
| Turna 原生语法 | Turna SRS |
| 从 Anki 派生的无评分练习 | 不写任何正式 SRS，或独立练习统计 |

首页可以聚合两个引擎的 due count，但聚合不代表统一存储。

## 14. Legacy 数据迁移

### 14.1 未正式发布或用户数据可舍弃

首选 clean break：

1. 保留用户语言字段 mapping 和课程偏好。
2. 要求重新选择原 `.apkg`。
3. 使用官方 Core 重新导入。
4. 默认采用包内 scheduling 或明确重置。
5. 不迁移 Turna 自研 scheduling JSON。
6. 迁移成功后删除 legacy 镜像。

### 14.2 已有正式用户数据

增加：

```text
engine_kind = legacy | official
migration_state
migrated_source_id
```

迁移期规则：

- 新导入只允许 official。
- Legacy 数据只读。
- Legacy review 不再写入，或在过渡版本中明确提示升级后才能继续。
- 同一来源不得同时启用两个 review engine。
- 不进行双写验证。

### 14.3 Card 映射

映射优先级：

1. `note GUID + template ordinal`。
2. 原 Card ID（仅作为同源快速路径）。
3. `notetype fingerprint + normalized fields + ordinal`。
4. 无可靠匹配时要求重新建立课程位置。

禁止只用 `wordId=anki-<importId>-c<cardId>` 作为跨引擎永久身份，因为 import ID 和 Card ID 都可能在合并时变化。

### 14.4 调度迁移

不建议把 Turna SRS 状态写成官方 revlog，原因：

- 状态模型和历史字段不等价。
- 缺少完整官方 review history 时无法安全重建。
- 人工构造 revlog 可能影响 FSRS 优化。

允许用户选择：

- 使用 `.apkg` 原有 scheduling。
- 将导入卡片作为新卡。
- 若未来实现受控转换，必须先有独立设计和 fixture 验证，不属于本方案首期。

## 15. 代码处置清单

### 15.1 官方导入上线后删除

- `anki_importer.dart`
- `anki_package_decoder.dart`
- `anki_zstd_codec.dart`
- `anki_protobuf_wire.dart`
- `anki_snapshot.dart`
- `anki_import_worker.dart` 中的自研 package decode 部分
- Android/OHOS 自研 Anki package decoder channel
- 直接读取 Anki SQLite schema 的 Dart 代码

删除条件：官方导入 fixture、进度、取消、错误恢复和性能门槛全部通过。

### 15.2 官方渲染上线后删除

- `anki_template_renderer.dart`
- `anki_card_html_renderer.dart`
- `anki_flutter_html_document.dart`
- `anki_flutter_html_view.dart`
- `anki_face_paint_engine.dart`
- `anki_render_policy.dart`
- `anki_render_fallback_chain.dart`
- `anki_prerendered_html` 相关 DAO、缓存和 DOM capture

删除条件：Reverse、Cloze、typed answer、MathJax、媒体和 JS fixture 全部通过。

### 15.3 官方 Scheduler 上线后删除

- `anki_srs_migrator.dart`
- `anki_queue_policy.dart`
- Anki 分支的 `anki_review_commit_service.dart`
- Anki Card 对 Turna `SrsProvider` 的写入
- scheduling JSON 镜像
- 用 Turna review history 模拟官方 Undo 的逻辑

删除条件：queue、四档评分、interval label、revlog、undo、bury、suspend 和 due count 全部通过。

### 15.4 保留并重构

- 导入向导 UI → `OfficialAnkiImportPage`。
- `AnkiImportService` → 只做 Saga orchestration。
- `AnkiDeckAssembler` → `OfficialAnkiCourseProjector`。
- `AnkiCardAdapter` → 显式语言字段投影。
- `AnkiReviewAssembler` → 官方 queue adapter。
- `AnkiAudioResolver` → 官方 media URL 和 AV tag adapter。
- CourseProvider、课程树和 Lesson UI。
- Turna AudioController、SmartSpeech。
- Turna 原生练习组件。

## 16. 分阶段实施计划

### 阶段 0：技术 Spike

目标：证明官方 Core 能在当前 Android 工程中稳定运行。

任务：

- [ ] 选择固定 Anki commit/tag。
- [ ] 建立最小 Rust `cdylib`。
- [ ] 配置 Android NDK arm64 target。
- [ ] 打开临时 Collection。
- [ ] 导入 legacy 和 latest fixture。
- [ ] 渲染 Basic、Reverse、Cloze 的正反面。
- [ ] 读取 DeckTree 和 SearchCards。
- [ ] 获取 queue、answer 一张卡、Undo。
- [ ] 验证进度和取消。
- [ ] 测量动态库、APK、冷启动、峰值内存和导入时间。
- [ ] 验证 release/R8 后 FFI symbols 存在。
- [ ] 完成 AGPL 初步评审。

退出门槛：

- 无数据损坏。
- Android release APK 能加载动态库。
- 关键 fixture 行为与 Anki Desktop/官方后端一致。
- 性能和体积得到明确数据，而不是主观判断。

### 阶段 1：稳定 Engine 与导入

任务：

- [ ] 定义 contract v1。
- [ ] 实现 Engine lifecycle。
- [ ] 实现 error mapping。
- [ ] 实现 import options。
- [ ] 实现 progress/cancel。
- [ ] 建立全局 Collection 路径。
- [ ] 实现 backup/check/recovery。
- [ ] 新建 `anki_sources` 和 `anki_source_cards`。
- [ ] 生产导入入口加 feature flag。
- [ ] Legacy 导入仍可只读回退，但失败时不得自动调用。

退出门槛：

- 新来源可以完整导入并重新打开。
- 崩溃恢复测试通过。
- 取消不会留下 `active` 的半成品来源。

### 阶段 2：官方原卡渲染

任务：

- [ ] 实现 `RENDER_CARD`。
- [ ] 实现 secure reviewer shell。
- [ ] 实现 media origin。
- [ ] 实现 question/answer 同 WebView 切换。
- [ ] 接入 AV/TTS tags。
- [ ] 接入 typed answer。
- [ ] 离线 MathJax。
- [ ] 实现 JS/navigation/network policy。
- [ ] 新 Reviewer 加 feature flag。
- [ ] 移除 official source 到 Legacy renderer 的运行时 fallback；Legacy 源码留到 Phase 5 再删除。
- [ ] P2 reviewer 只做预览：不写 Again/Hard/Good/Easy，不写入 Turna SRS 或官方 Scheduler。

退出门槛：

- 核心 fixture 截图和交互一致。
- 乱码、Reverse、Cloze 和 media 文件名测试全部通过。
- 恶意卡片无法访问应用文件和原生接口。

### 阶段 3：课程投影

任务：

- [ ] Deck/Subdeck 映射 Section/Unit。
- [ ] 定义 Lesson grouping。
- [ ] 实现字段角色候选。
- [ ] 实现用户确认 mapping。
- [ ] 明确原卡与派生练习。
- [ ] 重建 course projection cache。
- [ ] 移除 raw Note/Notetype/Card mirror。

退出门槛：

- 删除投影后可从官方 Collection 重建。
- 用户 mapping 在重复导入后仍可保留。
- 大牌组投影不会将全部 HTML 写入 Lesson JSON。

### 阶段 4：官方 Scheduler

任务：

- [ ] SetCurrentDeck。
- [ ] GetQueuedCards。
- [ ] DescribeNextStates。
- [ ] AnswerCard。
- [ ] Undo/Redo。
- [ ] Bury/Suspend。
- [ ] Counts/Congrats。
- [ ] 复习页适配官方 queue context。
- [ ] 删除 Anki→Turna SRS 双写。

退出门槛：

- 与官方后端对同一 fixture 的状态变化一致。
- App 重启后队列和 due 状态一致。
- Undo 能恢复 Card 和 revlog 语义。

### 阶段 5：Legacy 迁移和清理

任务：

- [ ] 实现来源 reimport migration。
- [ ] 使用 GUID+ordinal 映射 Card。
- [ ] 迁移课程位置和字段 mapping。
- [ ] 提供 scheduling 选择。
- [ ] Legacy 数据只读观察一个版本周期。
- [ ] 删除旧表和无生产引用实验模块。
- [ ] 更新用户帮助、隐私和许可证页面。

退出门槛：

- 已迁移用户不再依赖 legacy reader。
- 数据删除前存在可验证 backup。
- 官方 feature flag 可成为默认且 legacy 不再自动启动。

### 阶段 6：已取消

2026-08-20 产品书面：不考虑与 AnkiWeb / 官方 Anki 同步。不另开设计、不写 sync 包、不接账号凭证。生产路由须保持 `ankiweb_not_linked_from_production_routes`。

## 17. 测试与验收矩阵

### 17.1 Package 与编码

- [ ] 旧版 `.anki2` package。
- [ ] 当前 `.anki21b`/zstd package。
- [ ] UTF-8 中文。
- [ ] 梵文和组合字符。
- [ ] Emoji。
- [ ] RTL 文本。
- [ ] 超长字段。
- [ ] 空字段和条件模板。
- [ ] 媒体文件名包含空格、中文、`#`、`%`、括号。

### 17.2 模板

- [ ] Basic。
- [ ] Basic and Reversed。
- [ ] Optional Reversed。
- [ ] 多模板 Notetype。
- [ ] `FrontSide`。
- [ ] 条件字段。
- [ ] Cloze c1/c2/c10。
- [ ] typed answer。
- [ ] Cloze typed answer。
- [ ] 特殊字段 Tags/Deck/Subdeck/Card/CardFlag。
- [ ] 自定义 CSS。
- [ ] 自定义字体。
- [ ] MathJax。
- [ ] 卡片 JavaScript。
- [ ] 未支持的 Python custom filter 给出明确诊断。

### 17.3 媒体与安全

- [ ] 图片。
- [ ] 音频。
- [ ] 视频或明确不支持提示。
- [ ] TTS tag。
- [ ] 相对媒体路径。
- [ ] 路径穿越。
- [ ] `file://`。
- [ ] 外部 HTTP/HTTPS。
- [ ] iframe。
- [ ] window.open。
- [ ] download。
- [ ] JS bridge 探测。
- [ ] symlink 逃逸。

### 17.4 导入语义

- [ ] 新 Note。
- [ ] 更新 Note。
- [ ] duplicate。
- [ ] conflicting。
- [ ] missing notetype。
- [ ] notetype merge。
- [ ] deck config preserve/ignore。
- [ ] scheduling preserve/reset。
- [ ] 重复导入同 source hash。
- [ ] 同 Note 来自多个来源。
- [ ] 删除单个来源。
- [ ] 取消导入。
- [ ] 导入时强杀进程。
- [ ] 投影阶段失败。
- [ ] backup restore。

### 17.5 Scheduler

- [ ] New queue。
- [ ] Learning queue。
- [ ] Review queue。
- [ ] Again。
- [ ] Hard。
- [ ] Good。
- [ ] Easy。
- [ ] next interval labels。
- [ ] daily limits。
- [ ] filtered deck。
- [ ] bury。
- [ ] suspend。
- [ ] undo/redo。
- [ ] congrats state。
- [ ] App 重启。
- [ ] 时区和跨日。

### 17.6 性能

至少测试：

- 5 千 Card。
- 10 万 Card。
- 5 千媒体文件。
- 单个大媒体。
- 冷打开 Collection。
- warm open。
- 首张 Card render。
- 连续 100 张 Card render。
- queue build。
- source projection rebuild。

记录：

- import wall time。
- projection wall time。
- peak RSS。
- native library size。
- APK/AAB size delta。
- first-frame 和 reviewer ready time。
- cancel latency。

### 17.7 测试层级

- Rust contract unit tests。
- Rust integration tests against temporary Collection。
- Dart fake-engine tests。
- Dart FFI contract tests。
- Drift migration tests。
- Android instrumented WebView tests。
- Android golden screenshot tests。
- 真机 smoke tests。
- 与固定官方 Anki commit 的差分测试。

## 18. 可观测性与诊断

每个 native 请求记录：

- request ID。
- operation。
- backend commit。
- contract version。
- duration。
- result/error code。
- card/note/deck/source ID（可选且避免记录字段内容）。
- progress stage。

禁止默认记录：

- 完整 Note 字段。
- 用户 typed answer。
- 音频内容。
- Collection path 的敏感前缀。
- AnkiWeb / 官方 Anki 账号凭证（本迁移不实现登录）。

兼容性报告应能导出：

- backend commit。
- collection schema/version。
- package import log 摘要。
- 不支持过滤器列表。
- 缺失媒体数量。
- WebView policy violations。
- 最近 native error code。

## 19. 错误模型

Turna error code 示例：

```text
ENGINE_NOT_INITIALIZED
COLLECTION_ALREADY_OPEN
COLLECTION_LOCKED
COLLECTION_CORRUPT
COLLECTION_SCHEMA_UNSUPPORTED
PACKAGE_NOT_FOUND
PACKAGE_INVALID
PACKAGE_UNSUPPORTED
IMPORT_CONFLICT
IMPORT_CANCELLED
MEDIA_IO_ERROR
CARD_NOT_FOUND
NOTE_NOT_FOUND
RENDER_FAILED
UNSUPPORTED_TEMPLATE_FILTER
QUEUE_EMPTY
SCHEDULING_CONTEXT_STALE
ANSWER_REJECTED
UNDO_UNAVAILABLE
CONTRACT_VERSION_MISMATCH
BACKEND_PANIC
INTERNAL_ERROR
```

Rust panic 不得跨过 FFI 边界。Bridge 顶层使用受控 panic boundary，将 panic 转成 `BACKEND_PANIC`，同时保证 buffer 和 handle 状态可诊断。

## 20. Feature flag 与发布策略

建议 flags：

```text
officialAnkiEngine
officialAnkiImport
officialAnkiRenderer
officialAnkiScheduler
officialAnkiLegacyMigration
```

规则：

- Flags 用于阶段化启用，不用于长期维持两套自动回退逻辑。
- 官方导入失败时展示错误和恢复选项，不自动调用 legacy importer。
- 官方渲染失败时展示兼容性诊断，不自动显示自研猜测结果。
- 同一来源只允许一个 engine owner。
- Release 前记录 flags 与数据库 migration version 的兼容矩阵。

发布顺序建议：

1. 内部开发版：阶段 0/1。
2. 测试渠道：官方导入与渲染可选。
3. Beta：新导入默认 official，legacy 只读。
4. Stable 1：official 默认，提供 legacy migration。
5. Stable 2：停止 legacy review。
6. Stable 3：达到迁移阈值后删除 legacy code/data。

## 21. 备份与回滚

### 21.1 Collection 备份

在以下操作前创建备份或官方支持的 checkpoint：

- 首次打开旧 Collection 并可能升级 schema。
- Import package。
- Legacy migration。
- Backend 大版本升级。

### 21.2 回滚条件

自动回滚：

- Import transaction 返回失败。
- Import 成功但索引/投影失败且 Undo 仍安全可用。
- 升级后完整性检查失败。

人工确认回滚：

- 已发生后续复习操作。
- Backup schema 与当前 backend 不确定兼容。
- 来源关联与官方 Collection 状态无法自动重建。

### 21.3 禁止行为

- 不用文件复制覆盖一个仍打开的 Collection。
- 不删除唯一 backup。
- 不在错误恢复中自动调用 legacy importer。
- 不在用户不知情时重置 scheduling。
- 不因投影失败而直接删除整个官方 Collection。

## 22. 上游版本管理

当前本地 checkout 是 `main` 上的开发提交，不适合作为长期生产依赖。

生产策略：

- 阶段 0 可使用当前 commit 验证。
- 正式集成选择稳定 release tag 或审核后的明确 commit。
- 通过 git submodule 或锁定 source archive 固定。
- `Cargo.lock` 提交到 Turna 仓库。
- CI 验证 submodule commit 与 `engine.json`/contract metadata 一致。
- 上游升级通过单独 PR，不使用浮动 branch。

每次升级必须运行：

- Rust contract tests。
- 全部 package fixtures。
- Reviewer golden。
- Scheduler differential tests。
- Collection schema upgrade/rollback tests。
- APK 体积和性能基线。
- License/notice diff。

## 23. AGPL 与第三方许可

官方 Anki 使用 GNU AGPL v3 or later，部分内容使用其他兼容许可证。直接链接、修改和分发官方 Core 前必须完成专门合规审查。

最低检查项：

- [x] 保存官方 Anki LICENSE。
- [x] 清点所用 reviewer Web assets 的许可证。
- [x] 清点 Rust transitive dependencies。
- [x] 记录修改过的官方源文件。
- [x] 提供对应版本完整源代码获取方式。
- [x] 提供可重建 bridge 的脚本和说明。
- [x] 在 App About/License 页面展示声明。
- [x] 检查 Turna 当前 GPLv3 声明与组合分发义务。
- [x] 审查 AnkiWeb/network 功能引入后的 AGPL 条款影响。→ **不做 AnkiWeb Sync**；§13 不因同步触发。本地嵌入 rslib 仍按现有 AGPL 处理。
- [ ] 在正式发布前获得法律确认。

本文不构成法律意见。

## 24. Android、OHOS 与其他平台

### 24.1 Android

Android 是首发目标：

- 当前工程已有 NDK 入口条件。
- release 使用 R8/resource shrink。
- arm64 split 可限制首期 native size。
- 官方 Core 已包含 Android 特殊路径。

需要补充：

- `.so` 打包目录。
- FFI symbol keep/verification。
- NDK 和 Rust target 固定。
- crash symbol/archive。
- WebView 最低版本和设备矩阵。

### 24.2 OHOS

FFI 设计有利于未来移植，但不等于自动支持 OHOS。必须单独验证：

- Rust target/toolchain。
- SQLite、OpenSSL/网络、zstd 等依赖。
- `cfg(target_os)` 分支。
- 临时目录和文件锁。
- WebView 资源拦截。
- 动态库打包与符号加载。

如果 OHOS 是必须支持的平台，在 OHOS 官方 Core Spike 通过前，不得删除其仍在使用的 legacy 导入能力。但应冻结 legacy 功能，不再继续扩展。

### 24.3 iOS/桌面

先维持 contract/FFI 的平台中立性，是否打包官方 Core由后续独立决策决定。禁止为了假想跨平台提前扩大首期范围。

## 25. 工期与角色建议

Android-only、由一名熟悉 Flutter 和 Rust/NDK 的资深工程师执行，核心迁移应按约 12–18 周量级规划，不包括 AnkiWeb Sync 和完整 OHOS 适配。

建议拆分：

- 阶段 0：1–2 周。
- 阶段 1：2–3 周。
- 阶段 2：3–4 周。
- 阶段 3：2–3 周。
- 阶段 4：2–3 周。
- 阶段 5：2–4 周，取决于现有正式用户数据。

需要的能力：

- Rust/FFI/NDK。
- Flutter isolate 和 platform packaging。
- SQLite/事务/恢复。
- WebView 安全。
- Anki template/scheduler 语义。
- AGPL/第三方许可协调。

工期必须在阶段 0 测得构建、体积和 API 障碍后重新评估。

## 26. 决策记录

### 已确定

- 官方 `rslib` 是唯一 Anki Core。
- Turna 不重写 package parser、template renderer 和 scheduler。
- 单 profile 单全局 Collection。
- Dart 使用 Turna 自有 contract。
- 原卡固定 WebView，派生练习固定 Flutter。
- Anki scheduling 只由官方 Scheduler 管理。
- Legacy 不作为官方失败的自动 fallback。
- 不与 AnkiWeb / 官方 Anki 同步（P6 已取消）。

### 阶段 0 后确认

- 最终固定的 Anki release/commit。→ **钉死** `967aa0d578fc75181e292e95326f9b58698da25c`。
- 直接 Rust FFI 或包装 AAR 的最终构建形式。→ **直接** Turna `cdylib` + C ABI，不用 AAR。
- Turna contract 使用 Protobuf、MessagePack 还是其他二进制编码。→ Phase 0 用 **JSON + 自有 operation 号**；编号进真机产物后不得重排。
- 动态库和 APK 体积预算。→ strip 后 **16 077 904** 字节；产品尚未签字（条件 C2）。
- 100k Card 性能门槛。→ host 导入 **3642 ms**；真机门槛待 C1 后补。
- Reviewer shell 复用哪些官方 Web assets。→ Phase 0 **不捆绑**；留第三阶段。
- 是否为 batch descriptor 维护极小 Anki patch。→ **只要** `ProgressState` 一行 re-export。

### 产品需要确认

- 是否已有必须保留的正式 Legacy 用户数据。
- Legacy scheduling 迁移产品文案。
- JavaScript 兼容模式是否存在。
- Android 首发后 OHOS 的优先级。
- 是否计划 AnkiWeb Sync。→ **否**（2026-08-20 书面取消 P6）。
- 来源删除时是否提供“同时删除孤儿原卡”。

## 27. Definition of Done

迁移只有在以下条件全部满足时才算完成：

- [ ] 新 `.apkg` 不经过任何 Turna 自研 package decoder。
- [ ] 原始 Anki Card 不经过任何 Turna 自研模板渲染。
- [ ] Reverse、Cloze、`FrontSide` 和 typed answer fixtures 通过。
- [ ] 原卡渲染不存在 Flutter/WebView 启发式选择。
- [ ] Anki Card 不写 Turna SRS。
- [ ] Again/Hard/Good/Easy、Undo 和 due count 来自官方 Core。
- [ ] Turna 不再保存 raw Note/Notetype/template/scheduling mirror。
- [ ] 课程投影可从官方 Collection 重建。
- [ ] 导入中断、崩溃和投影失败均可恢复或明确诊断。
- [ ] 恶意卡片无法读取应用文件或调用任意原生接口。
- [ ] 100k Card 和大媒体 fixture 达到确认后的性能预算。
- [ ] 上游 commit、contract version 和 Collection metadata 可诊断。
- [ ] Android release 构建和真机测试通过。
- [ ] Legacy 用户迁移或明确归档完成。
- [ ] AGPL、第三方 notices、源码和构建说明完成审核。
- [ ] 旧解析、渲染、fallback 和 Anki SRS 代码已删除，而非永久隐藏在 flag 后。

## 28. 推荐的下一步

不要立即重写现有页面或删除旧代码。下一项工作应只完成阶段 0：

1. 在 `native/turna_anki_core` 建立最小 Rust workspace。
2. 使用固定 Anki commit 构建 Android arm64 `libturna_anki.so`。
3. 只实现 open/import/render/queue/answer/undo 七个端到端动作。
4. 使用真实 legacy/latest/Reverse/Cloze/Unicode fixtures 验证。
5. 输出 APK 体积、导入时间、内存和兼容性报告。
6. 阶段 0 通过后，再批准生产链路迁移和 legacy 删除计划。

这个顺序能以最小改动验证最大风险，并避免在 Native Core 尚未证明可用前继续扩大现有 Anki 代码的复杂度。

## 29. 参考

本地官方 Anki 参考：

- `/home/whwen/documents/reso/Varnamalaplus/anki/AGENTS.md`
- `/home/whwen/documents/reso/Varnamalaplus/anki/docs/architecture.md`
- `/home/whwen/documents/reso/Varnamalaplus/anki/docs/language_bridge.md`
- `/home/whwen/documents/reso/Varnamalaplus/anki/rslib/src/collection/mod.rs`
- `/home/whwen/documents/reso/Varnamalaplus/anki/rslib/src/import_export/package/apkg/import/mod.rs`
- `/home/whwen/documents/reso/Varnamalaplus/anki/rslib/src/notetype/render.rs`
- `/home/whwen/documents/reso/Varnamalaplus/anki/rslib/src/scheduler/`
- `/home/whwen/documents/reso/Varnamalaplus/anki/proto/anki/card_rendering.proto`
- `/home/whwen/documents/reso/Varnamalaplus/anki/proto/anki/import_export.proto`
- `/home/whwen/documents/reso/Varnamalaplus/anki/proto/anki/scheduler.proto`
- `/home/whwen/documents/reso/Varnamalaplus/anki/proto/anki/collection.proto`
- `/home/whwen/documents/reso/Varnamalaplus/anki/pylib/anki/template.py`
- `/home/whwen/documents/reso/Varnamalaplus/anki/qt/aqt/reviewer.py`

外部项目：

- Anki：<https://github.com/ankitects/anki>
- AnkiDroid Backend：<https://github.com/ankidroid/Anki-Android-Backend>
- AnkiDroid：<https://github.com/ankidroid/Anki-Android>
