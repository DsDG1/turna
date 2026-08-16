# 第一阶段实施方案：官方 Anki Core Android 技术 Spike

> 阶段编号：Phase 0  
> 文档状态：Phase 0 已收口（Conditional Go，见结果报告 §19）  
> 前置文档：[总体迁移方案](./00-overall-migration-plan.md)  
> 文档索引：[README](./README.md)  
> 目标平台：Android arm64-v8a  
> 目标工程：Turna  
> 官方 Anki 本地参考：`/home/whwen/documents/reso/Varnamalaplus/anki`  
> 参考提交：`967aa0d578fc75181e292e95326f9b58698da25c`  
> 参考 Rust toolchain：`1.97.1`  

## 1. 阶段目标

本阶段不是正式迁移，而是一个受控的技术 Spike。其唯一目标是用最小代码证明下面这条链路在真实 Android release 构建中成立：

```text
Flutter 测试入口
    ↓ Dart FFI
libturna_anki.so
    ↓ Turna Rust bridge
官方 anki::Collection
    ↓
打开 Collection
    ↓
导入 .apkg
    ↓
渲染 Basic / Reverse / Cloze
    ↓
获取官方 Queue
    ↓
Good 回答一张卡
    ↓
Undo
    ↓
关闭并重新打开 Collection
```

完成本阶段后，团队必须能基于测量结果作出明确的 Go/No-Go 决策，而不是仅得到“理论上可以集成”的结论。

## 2. 本阶段必须回答的问题

### 2.1 构建问题

- 官方 `rslib` 能否在 Linux/CI 主机交叉编译为 `aarch64-linux-android`？
- 当前 OpenHarmony Flutter 分支使用的 Android NDK 是否与 Rust/cargo-ndk 兼容？
- 哪个 NDK revision、cargo-ndk 版本和 API level 能稳定构建？
- 上游依赖是否包含 Android 不可用的 native library？
- Release/R8/resource shrink 后 `.so` 是否仍被打包且符号可见？
- 构建是否可以完全从仓库内的锁定信息复现？

### 2.2 API 问题

- Bridge 能否直接持有 `anki::Collection`？
- `CollectionBuilder`、`import_apkg()`、`render_existing_card()` 和 Scheduler 方法能否从外部 bridge crate 调用？
- 哪些能力必须通过生成的 service trait 调用？
- 是否需要修改上游 Anki 源码？
- 是否能够不向 Dart 暴露官方 service/method 数字索引？

### 2.3 正确性问题

- Legacy 和当前 `.apkg` 是否都能导入？
- 中文、梵文、组合 Unicode 是否保持不变？
- Basic and Reversed 的正反面是否正确？
- Cloze c1/c2 是否按 Card ordinal 正确渲染？
- `FrontSide` 是否由官方引擎正确处理？
- AnswerCard 与 Undo 是否正确修改并恢复 Card/revlog？

### 2.4 产品可行性问题

- `.so` 和 APK/AAB 体积增量是多少？
- 首次加载和首次渲染耗时是多少？
- 5 千/10 万 Card 的导入、索引、队列性能如何？
- 峰值内存是否会导致中低端 Android 设备 OOM？
- AGPL 源码、构建脚本和 Notices 的分发方案是否可接受？

## 3. 范围

### 3.1 本阶段包含

- 固定官方 Anki 源码版本。
- 建立最小 Rust `cdylib`。
- 建立最小稳定 C ABI。
- Dart FFI 动态库加载和调用。
- 官方 Collection 创建、打开、关闭。
- `.apkg` 导入、进度和取消验证。
- DeckTree 或最小 Card 查询。
- 官方 Card 正反面渲染数据验证。
- Queue、Good、Undo 的闭环。
- Android debug/release 真机运行。
- 核心 fixture、基线数据和阶段报告。
- License/源码分发初步评审。

### 3.2 本阶段不包含

- 不替换生产 `AnkiImporter`。
- 不修改现有正式导入页面默认路径。
- 不创建正式 `anki_sources` Drift migration。
- 不删除任何 Legacy 解析、渲染或 SRS 代码。
- 不实现正式 Reviewer WebView shell。
- 不实现 Turna Section/Unit/Lesson 投影。
- 不迁移真实用户数据。
- 不实现 AnkiWeb Sync。
- 不正式适配 OHOS。
- 不支持 Desktop Python add-on。
- 不加入静默 Legacy fallback。

若某个任务需要修改上述范围，必须停止实施、更新总体方案并重新评审，而不是在 Spike 中顺手扩张。

## 4. 阶段产物

阶段完成时应存在以下文件或等价产物：

```text
native/
└── turna_anki_core/
    ├── README.md
    ├── Cargo.toml
    ├── Cargo.lock
    ├── rust-toolchain.toml
    ├── .cargo/
    │   └── config.toml
    ├── anki/                         # pinned submodule/source
    ├── bridge/
    │   ├── Cargo.toml
    │   ├── include/
    │   │   └── turna_anki.h
    │   ├── src/
    │   │   ├── lib.rs
    │   │   ├── abi.rs
    │   │   ├── engine.rs
    │   │   ├── error.rs
    │   │   ├── operation.rs
    │   │   └── spike.rs
    │   └── tests/
    │       ├── lifecycle_test.rs
    │       ├── import_render_test.rs
    │       └── scheduler_test.rs
    ├── contract/
    │   ├── turna_anki_spike.proto
    │   └── VERSION
    ├── build-android/
    │   ├── build.sh
    │   ├── verify_symbols.sh
    │   └── README.md
    └── licenses/
        ├── ANKI-LICENSE
        └── THIRD-PARTY-NOTICES-DRAFT.md

lib/
└── application/
    └── anki_official/
        └── spike/
            ├── official_anki_spike_engine.dart
            ├── official_anki_spike_ffi.dart
            ├── official_anki_spike_models.dart
            └── official_anki_spike_page.dart

test/
└── fixtures/
    └── anki_official/
        ├── README.md
        ├── manifest.json
        └── packages/

tool/
└── official_anki_spike/
    ├── run_android.sh
    ├── collect_metrics.sh
    └── verify_fixture_results.dart

docs/
└── official-anki-migration/
    └── 02-phase-0-result-report.md
```

允许根据现有项目习惯调整目录，但不得把 Spike FFI 代码混入当前大型 Legacy 文件。

## 5. 实施原则

### 5.1 固定事实源

- Anki 数据事实源：官方临时 Collection。
- 上游代码事实源：固定 commit/tag。
- Bridge 契约事实源：`contract/VERSION` 和 schema。
- Fixture 预期事实源：固定官方 Anki 版本生成的 manifest/golden。
- 性能事实源：阶段报告中的原始测量文件。

### 5.2 不做双写

Spike 使用独立临时 Collection：

```text
<app-support>/anki-spike/<run-id>/collection.anki2
<app-support>/anki-spike/<run-id>/collection.media/
<app-support>/anki-spike/<run-id>/collection.media.db2
```

不得写入：

- 当前 Turna `anki_notes`。
- 当前 Turna `anki_notetypes`。
- 当前 Turna SRS。
- 当前用户课程。
- 真实用户正式 Anki Collection。

### 5.3 不依赖本机隐式环境

- 不把 `/home/.../anki` 写入正式 Cargo path。
- 不依赖最新 NDK 自动选择作为最终结果。
- 不依赖未记录版本的 `cargo-ndk`。
- 不依赖开发机已缓存的 Cargo crate。
- 不把构建产物手工复制后当成可复现集成。

## 6. 阶段任务依赖图

```text
P0-000 基线与环境盘点
    ├── P0-001 固定上游源码
    │       └── P0-002 Host Rust 最小编译
    │               └── P0-003 Android arm64 交叉编译
    │                       └── P0-004 Dart FFI 加载
    └── P0-005 Fixture 与官方预期

P0-004 + P0-005
    └── P0-006 Collection 生命周期
            └── P0-007 官方导入
                    ├── P0-008 查询与渲染
                    └── P0-009 Queue/Answer/Undo

P0-008 + P0-009
    ├── P0-010 进度、取消、错误与恢复
    ├── P0-011 性能、体积与安全测量
    └── P0-012 License 和源码分发评审

P0-010 + P0-011 + P0-012
    └── P0-013 阶段报告与 Go/No-Go
```

P0-002 未完成前不编写大量 Dart FFI；P0-007 未通过前不开发 Reviewer UI。

## 7. P0-000：建立基线与环境盘点

### 7.1 目标

记录构建前的真实环境，避免后续无法解释结果差异。

### 7.2 输入

- 当前 Turna commit 和 dirty status。
- 当前官方 Anki commit。
- Flutter/OHOS Flutter 版本。
- Dart 版本。
- Java 版本。
- Gradle/AGP/Kotlin 版本。
- Android SDK/NDK 版本。
- Rust/rustup/cargo 版本。
- cargo-ndk 是否安装及其版本。

### 7.3 实施步骤

1. 新建阶段执行分支，例如：

   ```text
   spike/official-anki-core-android
   ```

2. 保存基线命令输出到阶段报告，不提交包含用户名或敏感路径的完整环境转储。
3. 明确当前工程使用 OpenHarmony Flutter 分支，而不是假设官方 Flutter。
4. 记录 `android/app/build.gradle` 中：
   - `compileSdkVersion 36`
   - `ndkVersion flutter.ndkVersion`
   - Java/Kotlin target 11
   - release R8/resource shrink
5. 记录 Android 实际 `minSdkVersion` 数值；不能只记录 `flutter.minSdkVersion` 表达式。
6. 执行当前应用不带 Anki Native 的基线构建。
7. 保存基线 APK/AAB 大小和启动时间。

### 7.4 输出

在 `02-phase-0-result-report.md` 中建立：

```text
Turna commit:
Anki commit:
Flutter version:
Dart version:
JDK version:
Gradle/AGP/Kotlin:
Android SDK:
Android NDK:
Rust toolchain:
cargo-ndk version:
baseline APK size:
baseline install size:
baseline cold start:
```

### 7.5 验收

- [ ] 所有版本都有明确数值。
- [ ] 当前无 Native Core 的 release 基线可重复构建。
- [ ] 基线指标有原始命令或 CI artifact。
- [ ] 未覆盖用户当前未提交的工作。

### 7.6 预计工作量

0.5–1 工程日。

## 8. P0-001：固定官方 Anki 源码

### 8.1 目标

让开发机和 CI 使用同一份官方源码。

### 8.2 推荐实现

优先使用 git submodule：

```text
native/turna_anki_core/anki
```

Spike 可以使用当前参考 commit，但正式迁移前仍需评估稳定 release tag。

### 8.3 规则

- 不跟随 `main`。
- 不引用 `/home/whwen/.../anki` 作为提交后的 path dependency。
- 不在上游目录直接混入 Turna Dart/Android 文件。
- 如需 patch，存放在 `native/turna_anki_core/patches/` 并由脚本重放。
- 每个 patch 必须写明原因、上游 issue 和删除条件。

### 8.4 上游元数据

新增 `native/turna_anki_core/README.md`，至少记录：

```text
upstream repository
upstream commit/tag
git describe
Rust toolchain
Anki license
Turna patches
last compatibility run
```

### 8.5 验收

- [ ] fresh clone 可以取得相同 Anki commit。
- [ ] `git submodule status` 可用于 CI 校验。
- [ ] Cargo path 只使用仓库相对路径。
- [ ] 上游工作树保持可区分；Turna patch 有独立清单。

### 8.6 预计工作量

0.5–1 工程日。

## 9. P0-002：Host Rust 最小编译

### 9.1 目标

先在 host 上验证 bridge 对官方 crate 的依赖和 API 可见性，再处理 Android 交叉编译问题。

### 9.2 Bridge Cargo 结构

候选 `bridge/Cargo.toml`：

```toml
[package]
name = "turna_anki_bridge"
version = "0.0.1"
edition = "2021"
publish = false

[lib]
name = "turna_anki"
crate-type = ["cdylib", "rlib"]

[dependencies]
anki = { path = "../anki/rslib" }
anki_proto = { path = "../anki/rslib/proto" }
prost = "0.13"
```

实际版本必须尽可能继承或匹配固定 Anki workspace，避免同一消息存在两套不兼容的 `prost`。

### 9.3 最小代码

第一步只实现：

```rust
#[no_mangle]
pub extern "C" fn turna_anki_abi_version() -> u32 {
    1
}
```

然后逐步加入：

- `CollectionBuilder` 类型检查。
- 构建 `:memory:` Collection 的 Rust test。
- 正常 close。

### 9.4 必须验证的 API

- `CollectionBuilder::new()`。
- `set_media_paths()`。
- `set_shared_progress_state()`。
- `build()`。
- `Collection::close()`。
- `Collection::import_apkg()`。
- `Collection::render_existing_card()`。
- Scheduler service trait 或公开方法。

若外部 bridge crate 无法调用某些能力，按以下顺序处理：

1. 使用官方生成的公开 service trait。
2. 在 bridge 中组合多个公开调用。
3. 记录最小上游 patch 需求。
4. 不得转而让 Dart 使用 SQL 或数字 RPC index。

### 9.5 测试

```text
cargo test -p turna_anki_bridge
cargo build -p turna_anki_bridge
```

具体命令以最终 workspace 结构为准，并写入 `native/turna_anki_core/README.md`。

### 9.6 验收

- [ ] Host 编译成功。
- [ ] `:memory:` Collection 创建/关闭成功。
- [ ] `cargo test` 不依赖 Android。
- [ ] 明确记录所有不可直接调用的上游 API。
- [ ] 没有为了 Spike 修改官方数据库 schema。

### 9.7 预计工作量

1–3 工程日。如果 workspace/protobuf 代码生成与外部 crate 冲突，升级为阶段风险并记录实际耗时。

## 10. P0-003：Android arm64 交叉编译

### 10.1 目标

生成：

```text
android/app/src/main/jniLibs/arm64-v8a/libturna_anki.so
```

### 10.2 推荐工具链

- Rust target：`aarch64-linux-android`
- Android ABI：`arm64-v8a`
- 工具：固定版本的 `cargo-ndk`
- NDK：使用与当前 Flutter Android 构建一致的明确 revision

官方 cargo-ndk 支持将产物直接输出为 Android `jniLibs` 目录结构。候选命令：

```bash
rustup target add aarch64-linux-android
cargo ndk \
  -t arm64-v8a \
  -o ../../../android/app/src/main/jniLibs \
  build \
  --manifest-path bridge/Cargo.toml \
  --release
```

执行时需要根据实际工作目录修正相对路径，并把验证后的唯一命令固化到 `build-android/build.sh`。不得让文档中的候选路径永久替代脚本。

### 10.3 API level

构建脚本必须显式使用与 App `minSdkVersion` 兼容的 Android platform level。若 cargo-ndk 自动选择，阶段报告仍需记录最终值。

### 10.4 产物检查

`verify_symbols.sh` 至少检查：

```text
ELF architecture = AArch64
SONAME/filename = libturna_anki.so
turna_anki_abi_version 可见
turna_anki_engine_new 可见
turna_anki_call 可见
turna_anki_buffer_free 可见
无意外依赖 host glibc
```

可以使用 `file`、`readelf`、`llvm-readelf` 或 NDK 对应工具，脚本需在 CI 使用相同工具。

### 10.5 常见失败分类

| 类别 | 处理 |
|---|---|
| NDK 未找到 | 固定 `ANDROID_NDK_HOME` 或 CI SDK 配置 |
| C/C++ dependency | 检查 cargo-ndk 导出的 compiler/linker 环境 |
| OpenSSL | 优先避免 native-tls，使用上游 rustls feature 或不启用网络功能 |
| `/tmp`/temp file | 确认官方 Android cfg 生效 |
| Protobuf build tool | 区分 host build dependency 与 Android target dependency |
| linker 丢符号 | 对 C ABI 使用 `#[no_mangle] extern "C"` 和可见性检查 |
| builtins 缺失 | 仅在证据支持时评估 cargo-ndk `--link-builtins`，不可默认掩盖问题 |

### 10.6 验收

- [ ] 一条脚本命令生成 arm64 `.so`。
- [ ] fresh CI environment 可复现。
- [ ] 产物符号检查通过。
- [ ] NDK、API level、cargo-ndk 版本进入报告。
- [ ] `.so` 不依赖设备不存在的共享库。

### 10.7 预计工作量

2–5 工程日。这是本阶段第一个高风险门禁。

## 11. P0-004：Flutter/Dart FFI 加载

### 11.1 目标

在 Android debug 和 release 中通过 Dart 调用 `turna_anki_abi_version()`。

### 11.2 依赖处理

当前 `ffi` 是传递依赖。正式使用前应将 `ffi` 作为 `pubspec.yaml` 的直接依赖，版本遵循当前解析结果和项目升级策略。

Spike 不强制引入 `flutter_rust_bridge`。由于目标 ABI 很小，优先手写/ffigen 生成稳定 C bindings，减少第二个大型代码生成框架的影响。

### 11.3 动态库加载

Android 使用：

```dart
DynamicLibrary.open('libturna_anki.so');
```

平台判断必须明确：

- Android：尝试加载。
- 其他平台：返回 `unsupportedPlatform`。
- 测试：使用 fake engine，不要求 VM 加载 Android `.so`。

### 11.4 Smoke Page

Spike 页面只显示诊断信息：

```text
library loaded
ABI version
backend commit
contract version
collection state
last operation
last error
```

页面只能通过开发入口或 debug flag 打开，不进入普通用户导航。

### 11.5 Release 验证

- 构建 split-per-ABI arm64 release。
- 解包 APK，验证 `lib/arm64-v8a/libturna_anki.so`。
- 真机启动并调用 ABI。
- 在启用 R8/resource shrink 的情况下重复验证。

Flutter 官方 Android FFI 文档确认 Android 使用独立 `.so` 并通过 `DynamicLibrary.open()` 加载；阶段实现应以实际使用的 Flutter/OHOS fork 行为为最终证据。

### 11.6 验收

- [ ] Debug 真机加载成功。
- [ ] Release 真机加载成功。
- [ ] 不支持平台返回结构化错误，不崩溃。
- [ ] 动态库缺失时页面显示明确诊断。
- [ ] Dart isolate 重启或页面销毁不会错误卸载仍被使用的库。

### 11.7 预计工作量

1–2 工程日。

## 12. P0-005：Fixture 与官方预期

### 12.1 目标

建立可重复的正确性基准，避免只用随机用户牌组人工观察。

### 12.2 最小 fixture 集

建议独立 package：

```text
01-basic-unicode.apkg
02-basic-reversed.apkg
03-optional-reversed.apkg
04-cloze-multi-ord.apkg
05-frontside-css.apkg
06-media-paths.apkg
07-typed-answer.apkg
08-scheduling.apkg
09-legacy-package.apkg
10-large-generated-5k.apkg
11-large-generated-100k.apkg
```

字段至少包含：

- 简体中文。
- 土耳其语特殊字符。
- 梵文/天城文。
- 组合重音字符。
- Emoji。
- HTML entities。
- 文件名中的空格、中文、`#`、`%` 和括号。

### 12.3 Fixture manifest

`manifest.json` 示例：

```json
{
  "fixtureVersion": 1,
  "generatedWithAnkiCommit": "...",
  "packages": [
    {
      "file": "02-basic-reversed.apkg",
      "sha256": "...",
      "expectedNotes": 1,
      "expectedCards": 2,
      "assertions": [
        "template-0-question-contains:...",
        "template-0-answer-contains:...",
        "template-1-question-contains:...",
        "template-1-answer-contains:..."
      ]
    }
  ]
}
```

### 12.4 预期来源

- 使用固定官方 Anki Desktop/backend 生成或验证。
- 保存生成脚本、输入字段和 package SHA-256。
- HTML 中不稳定的 ID/时间戳先做明确 normalization，再比较。
- 不通过修改期望值来迁就 Turna 输出；差异必须解释。

### 12.5 许可与隐私

- Fixture 使用项目自建内容或明确可再分发内容。
- 不提交用户私人牌组。
- 不提交受版权保护的课程数据。
- 大牌组通过脚本生成。

### 12.6 验收

- [ ] 每个 package 有 SHA-256。
- [ ] 每个 package 有明确 Card/Note 数和断言。
- [ ] 能从脚本重新生成大牌组。
- [ ] 官方预期版本被记录。
- [ ] Fixture 可合法进入仓库/CI。

### 12.7 预计工作量

2–3 工程日，可与 P0-001 至 P0-004 并行准备，但本计划默认不使用子代理并行执行。

## 13. P0-006：Collection 生命周期

### 13.1 目标

通过 FFI 创建、打开、关闭和重新打开真实文件 Collection。

### 13.2 Engine 状态机

```text
uninitialized
  ↓ engine_new
created
  ↓ open_collection
open
  ↓ close_collection
closed
  ↓ engine_free
released
```

非法调用：

- `created` 时执行 render。
- `open` 时再次 open 不同路径。
- `released` 后调用任何 operation。
- operation 运行时并发 close。

全部返回结构化错误，不得 panic。

### 13.3 路径 DTO

```text
collection_path
media_folder
media_db
check_integrity
```

所有路径：

- 必须由 Dart 使用 `path_provider` 取得应用私有目录。
- 必须转换为绝对路径后传入。
- Bridge 验证 collection/media 不指向相同文件。
- Bridge 创建缺失的父目录。
- 错误中避免返回完整敏感目录。

### 13.4 Handle registry

禁止把 Rust 对象裸指针直接暴露为可随意使用的地址。建议：

- 原生内部 `HashMap<u64, Engine>`。
- 随机或单调不复用 handle ID。
- 全局 registry mutex 只保护 handle 查找。
- Collection 长操作使用 engine 自身互斥，不长期持有 registry lock。

### 13.5 验收

- [x] 第一次 open 创建文件和媒体目录。
- [x] close 后数据库可再次打开。
- [x] 双 open 返回 `COLLECTION_ALREADY_OPEN/LOCKED`。
- [x] 无效 handle 返回 `INVALID_HANDLE`。
- [x] 并发操作被串行化或明确拒绝。
- [x] 100 次 open/close 无 FD 持续增长。

Host Rust 已覆盖上述项。Engine mutex 串行化同 handle 操作；同路径第二
handle 返回 `COLLECTION_LOCKED`。真机 FFI open 仍随 P0-004 待验证。

### 13.6 预计工作量

1–2 工程日。

## 14. P0-007：官方 Package 导入

### 14.1 目标

使用官方 `Collection::import_apkg()` 将 fixture 导入临时 Collection。

### 14.2 请求

```protobuf
message SpikeImportPackageRequest {
  string package_path = 1;
  bool merge_notetypes = 2;
  UpdateCondition update_notes = 3;
  UpdateCondition update_notetypes = 4;
  bool with_scheduling = 5;
  bool with_deck_configs = 6;
}
```

### 14.3 响应

```protobuf
message SpikeImportPackageResponse {
  repeated int64 new_note_ids = 1;
  repeated int64 updated_note_ids = 2;
  repeated int64 duplicate_note_ids = 3;
  repeated int64 conflicting_note_ids = 4;
  repeated int64 missing_notetype_note_ids = 5;
  uint64 elapsed_millis = 6;
  repeated string warnings = 7;
}
```

Spike contract 可以只包含必要字段，但编号一旦进入真机测试产物不得任意重排。

### 14.4 执行线程

- 导入在 Dart worker isolate 发起。
- FFI 调用不得阻塞 UI isolate。
- 原生 Engine 在导入期间拒绝 render/queue 等并发操作。
- progress 查询和 cancel 是允许的并发控制操作。

### 14.5 测试场景

1. 全新 Collection 导入。
2. 同 package 重复导入。
3. 修改 Note 后更新导入。
4. `with_scheduling=true`。
5. `with_scheduling=false`。
6. 导入到一半取消。
7. 无效 ZIP。
8. 不存在文件。
9. 只读路径。
10. 低磁盘空间模拟或可控错误注入。

### 14.6 验收

- [x] 所有小 fixture 导入成功。
- [x] Note/Card 数与 manifest 一致。
- [x] Unicode 字段 round-trip 一致。
- [x] Import log 分类可获得。
- [x] 无效 package 返回结构化错误。
- [x] 取消后 Collection 完整性检查通过。
- [x] Dart 从未读取 package 内部 SQLite/Protobuf。

### 14.7 预计工作量

2–4 工程日。

## 15. P0-008：查询与官方渲染

### 15.1 目标

从导入后的官方 Collection 找到 Card ID，并获得官方正反面渲染结果。

### 15.2 最小查询

Spike 只需实现：

- DeckTree。
- SearchCards/whole collection。
- Card descriptor：card ID、note ID、deck ID、template ordinal。
- CardsOfNote。

批量查询在 Rust bridge 内完成，禁止 Dart 对 10 万 Card 逐个 FFI 调用。

### 15.3 渲染请求

```protobuf
message SpikeRenderCardRequest {
  int64 card_id = 1;
  bool browser = 2;
}
```

Bridge 固定调用：

```text
render_existing_card(card_id, browser=false, partial_render=false)
```

### 15.4 渲染响应

```protobuf
message SpikeRenderedCard {
  int64 card_id = 1;
  string question_html = 2;
  string answer_html = 3;
  string css = 4;
  bool latex_svg = 5;
  bool is_empty = 6;
  repeated AvTag question_av_tags = 7;
  repeated AvTag answer_av_tags = 8;
}
```

本阶段可以先在诊断页面使用可选择文本显示 raw HTML 和摘要，不要求完成正式 WebView Reviewer。

### 15.5 比较规则

- 保留原始 HTML 用于 artifact。
- 另生成 normalized HTML 用于断言。
- Normalization 规则必须版本化。
- 不 strip HTML 后比较正文来替代模板正确性。
- Reverse Card 必须分别比较两个 Card/template ordinal。
- Cloze 必须分别比较 c1/c2 Card。

### 15.6 未知过滤器

使用 `partial_render=false` 时不运行 Desktop Python add-on hook。若 fixture 包含未知自定义过滤器：

- 记录兼容性告警。
- 不调用 Legacy renderer。
- 不宣称支持该 add-on。
- 报告中记录官方 core 的实际输出。

### 15.7 验收

- [x] Basic 正反面一致。
- [x] Reverse 两张 Card 的方向一致。
- [x] `FrontSide` 正确。
- [x] Cloze c1/c2 正确。
- [x] 中文、梵文、组合字符逐字一致。
- [x] CSS 返回且未被 Dart 重写。
- [x] AV tags 可分 question/answer 提取。
- [x] 10 万 Card 的 ID/descriptor 获取不存在 10 万次 Dart FFI。

### 15.8 预计工作量

2–4 工程日。

## 16. P0-009：Queue、Answer 与 Undo

### 16.1 目标

证明官方 Scheduler 可以成为 Turna Anki 卡片的唯一调度引擎。

### 16.2 最小流程

```text
SetCurrentDeck
  ↓
GetQueuedCards(fetch_limit=10)
  ↓
选择第一张 QueuedCard
  ↓
DescribeNextStates
  ↓
选择 GOOD 对应 new_state
  ↓
构造 CardAnswer
  ↓
AnswerCard
  ↓
GetUndoStatus
  ↓
Undo
```

### 16.3 Queue DTO

必须保留：

- Card ID。
- Queue kind。
- Current state。
- Again/Hard/Good/Easy state。
- SchedulingContext。
- 官方 custom data。
- new/learning/review counts。

不得只返回四个计算后的天数，因为 AnswerCard 需要官方状态和上下文。

### 16.4 Answer DTO

```text
card_id
rating
current_state_token/full state
new_state_token/full state
scheduling_context
answered_at_millis
milliseconds_taken
```

Spike 内部可以让 Bridge 根据 queue token 取回完整状态，减少 Dart 持有上游 protobuf；但必须防止 stale token：

- token 绑定 engine session。
- token 绑定 card ID。
- answer 后 token 失效。
- close/reopen 后 token 失效。

### 16.5 验证数据

回答前后记录：

- Card queue/type/due/interval 等必要 descriptor。
- revlog count。
- deck counts。
- undo status。

Undo 后必须恢复到回答前的官方可观察状态。

### 16.6 验收

- [x] Queue 可以取得 Card。
- [x] 四档下一状态存在。
- [x] 官方 next-state label 可取得。
- [x] Good 后 Card 状态改变。
- [x] revlog 增加。
- [x] Undo 后 Card 和 revlog 恢复。
- [x] 重启 Collection 后状态持久。
- [x] stale answer 被拒绝，不错误评分下一张卡。

### 16.7 预计工作量

2–4 工程日。

## 17. P0-010：进度、取消、错误和恢复

### 17.1 目标

验证长操作不冻结 UI，并且失败后不会留下无法解释的 Collection。

### 17.2 Progress DTO

```text
operation_id
operation_kind
stage
current
total
message_key
can_cancel
updated_at_millis
```

UI 文案由 Dart 本地化，Native 尽量返回 message key/结构化计数，不返回不可翻译的长字符串作为唯一信息。

### 17.3 Cancel

- Bridge 保存共享 `ProgressState`。
- `cancel(operation_id)` 只设置 abort 请求。
- UI 显示“正在取消”，直到官方操作返回 Interrupted。
- 不通过杀线程取消 SQLite transaction。
- 不通过关闭动态库取消。

### 17.4 Error envelope

```protobuf
message SpikeError {
  string code = 1;
  string message = 2;
  string debug_details = 3;
  bool recoverable = 4;
}
```

至少映射：

```text
INVALID_HANDLE
INVALID_STATE
CONTRACT_VERSION_MISMATCH
COLLECTION_LOCKED
COLLECTION_OPEN_FAILED
COLLECTION_CORRUPT
PACKAGE_NOT_FOUND
PACKAGE_INVALID
IMPORT_CANCELLED
CARD_NOT_FOUND
RENDER_FAILED
QUEUE_EMPTY
SCHEDULING_CONTEXT_STALE
ANSWER_FAILED
UNDO_UNAVAILABLE
IO_ERROR
BACKEND_PANIC
INTERNAL_ERROR
```

### 17.5 Panic boundary

- 所有 `extern "C"` 入口使用 panic boundary。
- panic 不得 unwind 跨 FFI。
- panic 后返回结构化错误。
- Engine 是否还能继续使用必须明确；未知时标记 poisoned 并要求 close/reopen。
- 不记录完整用户字段。

### 17.6 恢复测试

- 导入取消后 close/reopen。
- 导入期间 App 进程被杀后重新打开。
- Card render error 后继续渲染另一张卡。
- Answer 超时/重复提交。
- 无 Undo 时调用 Undo。
- 无效 buffer/空请求。

### 17.7 验收

- [x] UI isolate 流畅性有实际证据。
- [x] 取消可观察且不会立即假报成功。
- [x] Collection 在取消后通过检查。
- [x] FFI panic 不导致进程未定义行为。
- [x] 所有错误有稳定 code。
- [x] 错误日志不泄露完整卡片内容。

### 17.8 预计工作量

2–3 工程日。

## 18. P0-011：性能、体积与安全测量

### 18.1 目标

给第二阶段提供量化预算。

### 18.2 构建体积

记录：

```text
baseline APK size
with-core APK size
baseline AAB/download estimate
libturna_anki.so unstripped size
libturna_anki.so stripped size
installed native size
ABI split result
```

必须区分下载体积、APK 文件体积和安装后体积。

### 18.3 运行指标

测试至少覆盖：

| 场景 | 指标 |
|---|---|
| `DynamicLibrary.open` | wall time |
| engine new/open | wall time、RSS |
| 空 Collection open | wall time |
| 5k import | wall time、peak RSS、cancel latency |
| 100k import | wall time、peak RSS、磁盘增长 |
| first render | wall time |
| warm render ×100 | p50/p95/p99 |
| queue build | wall time、RSS |
| answer | wall time |
| undo | wall time |
| close/reopen | wall time |

### 18.4 设备矩阵

至少：

- 一台主力 Android arm64 设备。
- 一台较低内存设备或受控低内存模拟环境。
- 一个 release 构建真机运行。

模拟器结果不能替代真机 native load 和性能结论。

### 18.5 安全检查

本阶段尚未实现正式 WebView，但必须检查 Native 边界：

- package path 只由受控文件选择结果提供。
- media/collection 路径 canonicalize。
- FFI buffer length 上限。
- 非法 protobuf/contract payload fuzz/smoke。
- 超大输入不会整数溢出。
- handle 猜测和重复 free 不导致 UAF。
- Rust buffer 只能由 `turna_anki_buffer_free` 释放。

### 18.6 初始 Go 门槛

以下是方向性门槛，具体数值在 P0-000 后由设备基线确认：

- Release APK 可正常加载，arm64 split 正确。
- 5k Card 无 OOM、无 UI 卡死。
- 100k Card 能完成导入和查询。
- 连续 100 张渲染无明显内存持续增长。
- Cancel latency 有明确测量，目标为用户可感知的秒级以内。
- Answer/Undo 为交互级延迟，不阻塞动画。
- Native 体积增量得到产品确认。

### 18.7 验收

- [x] 所有指标有原始记录。
- [x] 基线与接入后使用同一构建模式比较。
- [x] 指标区分 debug/release。
- [x] 无只报告平均值而隐藏 p95/p99。
- [x] 100k 测试成功或有明确 No-Go 证据。

### 18.8 预计工作量

2–4 工程日。

## 19. P0-012：License 与源码分发评审

### 19.1 目标

在投入生产迁移前确认 AGPL 不构成未处理的发布阻碍。

### 19.2 检查清单

- 官方 Anki AGPL-3.0-or-later LICENSE。
- `rslib` 及其直接/传递依赖许可证。
- Turna 对官方代码的 patch。
- 是否分发官方 Web/Reviewer assets。
- Cargo.lock 对应源码可获得性。
- 用户获取 Turna 对应版本完整源码的方式。
- 可重建 Native bridge 的脚本和工具链说明。
- App 内 License/Notices 展示。
- Turna 当前 GPLv3 声明与组合分发义务。

### 19.3 阶段产物

`licenses/THIRD-PARTY-NOTICES-DRAFT.md` 和阶段报告中的合规结论：

```text
GO
GO WITH CONDITIONS
NO-GO PENDING LEGAL REVIEW
```

### 19.4 验收

- [x] Anki LICENSE 已保留。
- [x] 使用和修改范围可枚举。
- [x] 源码/构建说明方案明确。
- [x] 未把“Turna 已是 GPL”当成自动完成 AGPL 合规。
- [x] 正式发布前需要的法律确认被记录为阻塞项或已完成。

### 19.5 预计工作量

工程清点 1–2 天；法律确认时间不计入工程工期。

## 20. P0-013：阶段报告与 Go/No-Go

### 20.1 报告结构

新增：

```text
docs/official-anki-migration/02-phase-0-result-report.md
```

必须包含：

1. 执行摘要。
2. 实际上游 commit。
3. 实际构建环境。
4. 唯一可复现构建命令。
5. Bridge/API 调用结论。
6. Fixture 通过矩阵。
7. 导入、渲染、Scheduler 证据。
8. APK/`.so` 体积。
9. 性能与内存。
10. Crash/取消/恢复结果。
11. License 评审状态。
12. 需要的上游 patch。
13. 未解决风险。
14. Go/Conditional Go/No-Go 决策。
15. 第二阶段准确工作量调整。

### 20.2 Go 条件

必须全部满足：

- Android arm64 debug/release 均能加载 `.so`。
- 构建脚本在干净环境可复现。
- Collection create/open/close/reopen 通过。
- Legacy/current package fixtures 可导入。
- Unicode fixture 零字段损坏。
- Basic/Reverse/Cloze/FrontSide 核心断言通过。
- Queue/Good/Undo 闭环通过。
- 取消后 Collection 可继续使用。
- 100k Card 结果可接受，或有已批准的规模限制方案。
- Native 体积得到产品确认。
- 无必须让 Dart 读取官方 SQLite/schema 的障碍。
- 无必须暴露数字 RPC index 的障碍。
- AGPL 评审至少为 `GO WITH CONDITIONS` 且条件可执行。

### 20.3 Conditional Go

允许条件：

- 需要一个很小且可维护的上游 Rust visibility/batch patch。
- 体积需要 arm64-only 或下载拆分策略。
- 100k 性能需要 Bridge batch API 优化。
- 少量不影响官方核心语义的卡片前端工作留到正式 Renderer 阶段。

每个条件必须有 owner、截止阶段和验收方式。

### 20.4 No-Go 条件

任一成立即暂停生产迁移：

- Release 构建无法稳定加载官方 Core。
- 必须大规模 fork 官方 Anki 才能完成基本导入/调度。
- 核心模板与官方输出无法一致且原因不可控制。
- 取消/崩溃会稳定损坏 Collection。
- 100k 规模无法运行且产品不能接受限制。
- Native 体积超出产品预算且无可行拆分。
- AGPL/源码分发方案无法接受。

No-Go 不代表继续无边界扩展 Legacy；应单独重新评估 AnkiDroid Backend/AAR 或缩小产品兼容目标。

### 20.5 预计工作量

1–2 工程日。

## 21. Spike Contract v1 草案

### 21.1 设计目标

- Dart 不认识上游 protobuf 类型。
- Dart 不认识上游 service/method index。
- 所有整数 ID 使用 64 位。
- 所有 operation 有 request ID。
- 错误和成功共享统一 envelope。
- Contract 可以在 Host Rust 测试和 Dart fake 中复用。

### 21.2 Operation

```protobuf
enum SpikeOperation {
  SPIKE_OPERATION_UNSPECIFIED = 0;
  ENGINE_INFO = 1;
  OPEN_COLLECTION = 2;
  CLOSE_COLLECTION = 3;
  CHECK_COLLECTION = 4;
  IMPORT_PACKAGE = 5;
  LATEST_PROGRESS = 6;
  CANCEL_OPERATION = 7;
  LIST_DECK_TREE = 8;
  SEARCH_CARDS = 9;
  RENDER_CARD = 10;
  SET_CURRENT_DECK = 11;
  GET_REVIEW_QUEUE = 12;
  DESCRIBE_NEXT_STATES = 13;
  ANSWER_CARD = 14;
  GET_UNDO_STATUS = 15;
  UNDO = 16;
}
```

### 21.3 Envelope

```protobuf
message SpikeRequest {
  uint32 contract_version = 1;
  uint64 request_id = 2;
  SpikeOperation operation = 3;
  bytes payload = 4;
}

message SpikeResponse {
  uint32 contract_version = 1;
  uint64 request_id = 2;
  bool ok = 3;
  bytes payload = 4;
  SpikeError error = 5;
  string backend_commit = 6;
  uint64 duration_millis = 7;
}
```

### 21.4 C result

不要直接返回可变 Rust struct 给 Dart。使用稳定 POD：

```c
typedef struct TurnaAnkiBuffer {
  uint8_t* ptr;
  uintptr_t len;
} TurnaAnkiBuffer;

typedef struct TurnaAnkiResult {
  int32_t status;
  TurnaAnkiBuffer buffer;
} TurnaAnkiResult;
```

规则：

- `status=0` 表示 buffer 中是正常 response envelope。
- 非零仍尽可能返回错误 envelope。
- `ptr=NULL,len=0` 合法表示无 payload。
- Dart 完成复制后调用 `turna_anki_buffer_free(ptr,len)`。
- double free、错误 len 和释放外部指针在 debug/test 中尽早检测。

## 22. 测试计划

### 22.1 Rust unit tests

- Handle 分配与失效。
- Engine 状态机。
- Contract encode/decode。
- Error mapping。
- Panic boundary。
- Buffer allocate/free。
- Invalid operation。
- Invalid payload。

### 22.2 Rust integration tests

- Temporary Collection lifecycle。
- Import 每个小 fixture。
- Render assertions。
- Queue/Answer/Undo。
- Cancel/import integrity。
- Close/reopen persistence。

### 22.3 Dart unit tests

- Fake engine。
- FFI response decode。
- 64 位 Card ID 不丢精度。
- Native error 映射。
- Unsupported platform。
- Progress stream lifecycle。
- 页面销毁后的 callback 安全。

### 22.4 Android 真机 tests

- `.so` load。
- Engine info。
- Collection path。
- Package import。
- Render result。
- Queue/answer/undo。
- App background/foreground。
- Process restart/reopen。
- Release/R8。

### 22.5 测试数据清理

- 每次 run 使用唯一 spike 目录。
- 测试结束优先保留失败 artifact。
- 成功 run 可以由显式 cleanup 删除。
- 不使用广泛目录或 unresolved glob 删除。
- 不触碰生产 profile。

## 23. CI 建议

### 23.1 Host job

```text
checkout + submodule
verify Anki commit
install pinned Rust
cargo fmt --check
cargo test bridge
cargo clippy bridge
build host library
license scan
```

### 23.2 Android arm64 job

```text
checkout + submodule
install pinned Android SDK/NDK
install pinned Rust target
install pinned cargo-ndk
build libturna_anki.so
verify ELF/symbols/dependencies
flutter pub get
apply project-required OHOS Flutter patches
flutter build apk --release --split-per-abi --target-platform android-arm64
inspect APK native entry
publish APK/.so/size report
```

### 23.3 Fixture job

Host 可执行的 import/render/scheduler 测试优先在 Rust integration job 运行；Android 真机部分进入设备测试或人工受控门禁。

### 23.4 Cache

- Cargo registry/git cache 可以优化速度。
- Cache key 包含 Cargo.lock、Anki commit、Rust version 和 target。
- 首次可复现验证必须至少跑一次无 cache job。
- 不缓存未校验的手工 `.so` 作为正式输入。

## 24. PR 拆分

建议严格按以下 PR 合并：

| PR | 内容 | 前置 |
|---|---|---|
| 1 | ADR、目录、固定上游、License copy | P0-000 |
| 2 | Host bridge、ABI version、Collection compile test | PR 1 |
| 3 | Android cargo-ndk 构建和 symbol verification | PR 2 |
| 4 | Dart FFI load、debug spike page | PR 3 |
| 5 | Fixture manifest 和官方预期 | PR 1，可与 2–4 独立准备 |
| 6 | Collection open/close/check | PR 4 |
| 7 | Import、progress、cancel | PR 5、6 |
| 8 | Search/render | PR 7 |
| 9 | Queue/answer/undo | PR 7 |
| 10 | 性能、安全、License 报告与 Go/No-Go | PR 8、9 |

每个 PR：

- 不修改生产 Anki 默认入口。
- 不删除 Legacy。
- 有独立测试。
- 更新阶段报告的已验证事实。
- 标注上游 API 依赖。
- 标注回滚方式。

## 25. 风险登记表

| ID | 风险 | 概率 | 影响 | 最早验证任务 | 处理 |
|---|---|---:|---:|---|---|
| R1 | `rslib` Android 交叉编译失败 | 中 | 高 | P0-003 | 对照 AnkiDroid Backend；限制 features；记录最小 patch |
| R2 | 外部 bridge 无法调用必要 API | 中 | 高 | P0-002 | service trait；bridge batch；极小上游 patch |
| R3 | `.so`/APK 体积过大 | 高 | 中/高 | P0-003/P0-011 | arm64 split、strip、feature audit、产品确认 |
| R4 | 100k import OOM | 中 | 高 | P0-011 | 官方流式导入、减少 Dart materialization、限制并发 |
| R5 | Flutter/OHOS fork 与 FFI packaging 冲突 | 中 | 高 | P0-004 | release 真机门禁；必要时独立 FFI plugin |
| R6 | Protobuf/codegen 版本冲突 | 中 | 中 | P0-002 | 匹配上游 workspace version；不重复定义上游类型 |
| R7 | Scheduler context 被 Dart 丢失 | 中 | 高 | P0-009 | opaque session token 或完整 Turna DTO |
| R8 | Cancel 无法及时响应 | 中 | 中 | P0-010 | 测量官方 progress 检查点；UI 正确表示“正在取消” |
| R9 | License 方案不被接受 | 低/中 | 极高 | P0-012 | 提前评审，不到发布前才处理 |
| R10 | Spike 侵入生产路径 | 中 | 高 | 所有 PR | 独立页面、独立目录、feature gate、review checklist |

风险状态必须在阶段报告中更新为 open/mitigated/accepted/blocking。

## 26. 每日执行与状态记录

每个工作日更新：

```text
日期：
完成任务：
当前任务：
实际命令：
新增事实：
失败与错误日志位置：
指标变化：
上游 API/patch 变化：
阻塞项：
下一步：
```

构建失败不是 No-Go；只有完成最小排查并确认无法在可接受范围内解决，才进入 No-Go 评审。

## 27. 阶段验收清单

### 构建

- [ ] 固定 Anki commit。
- [ ] 固定 Rust toolchain。
- [ ] 固定 NDK revision。
- [ ] 固定 cargo-ndk 版本。
- [ ] Host tests 通过。
- [ ] Android arm64 `.so` 构建通过。
- [ ] Release APK 加载通过。
- [ ] ELF 和 symbols 检查通过。
- [ ] fresh CI build 通过。

### Collection/Import

- [ ] create/open/close/reopen。
- [ ] exclusive access 行为明确。
- [ ] legacy package import。
- [ ] current package import。
- [ ] duplicate/update 行为记录。
- [ ] progress 可观察。
- [ ] cancel 可恢复。
- [ ] integrity check 通过。

### Rendering

- [ ] Basic。
- [ ] Reverse。
- [ ] Optional Reverse。
- [ ] `FrontSide`。
- [ ] Cloze c1/c2。
- [ ] Unicode。
- [ ] CSS。
- [ ] AV tags。
- [ ] 与官方预期差异为零或有批准说明。

### Scheduler

- [ ] queue。
- [ ] 四档状态。
- [ ] next state labels。
- [ ] Good answer。
- [ ] revlog change。
- [ ] Undo。
- [ ] close/reopen persistence。
- [ ] stale token rejection。

### 非功能

- [ ] 5k 性能。
- [ ] 100k 性能。
- [ ] 峰值 RSS。
- [ ] APK/`.so` 体积。
- [ ] cancel latency。
- [ ] 连续 render 无持续泄漏。
- [ ] FFI malformed input。
- [ ] License 初审。

### 边界

- [ ] 生产导入默认路径未改变。
- [ ] Legacy 代码未删除。
- [ ] 真实用户数据未迁移。
- [ ] Turna SRS 未被写入。
- [ ] 无自动 fallback。
- [ ] 无 AnkiWeb/OHOS 范围扩张。

## 28. 阶段完成定义

第一阶段完成不是“代码已经写了”，而是同时满足：

1. 一个干净环境能构建相同的 arm64 `.so`。
2. Android release 真机能加载并调用它。
3. 固定 fixtures 能完成官方导入与渲染。
4. Reverse、Cloze、Unicode 结果通过自动断言。
5. Queue、Good、Undo 构成持久化闭环。
6. 导入取消后 Collection 仍然健康。
7. 5k/100k 性能和体积有真实数据。
8. 上游 patch、API 风险和 License 条件已经列清。
9. 阶段报告给出明确 Go/Conditional Go/No-Go。
10. 未对生产用户造成数据或行为变化。

在这些条件满足前，不得将第二阶段标记为进行中。

## 29. 执行后的下一步

若结论为 Go：

1. 冻结 Spike 中验证过的 Anki commit、NDK 和 contract v1。
2. 将 Spike Bridge 重构为正式 `OfficialAnkiEngine`，而不是直接复制实验代码。
3. 编写第二阶段文档：稳定 Engine、全局 Collection、官方导入 Saga、`anki_sources` schema。
4. 为生产 feature flags 和数据库 migration 建立独立 PR。
5. 继续保持 Legacy 只读可用，直到正式迁移阶段。

若结论为 Conditional Go：

- 每个条件转换成第二阶段的 P0 blocker。
- blocker 未关闭前不得替换生产入口。

若结论为 No-Go：

- 保存 Spike、日志和指标。
- 不继续扩大自研兼容声明。
- 单独比较 AnkiDroid Backend/AAR 或降低产品目标。
- 总体方案更新为新的决策，不保留两个相互矛盾的默认架构。

## 30. 参考资料

本地：

- `./00-overall-migration-plan.md`
- `../android-build-setup.md`
- `/home/whwen/documents/reso/Varnamalaplus/anki/AGENTS.md`
- `/home/whwen/documents/reso/Varnamalaplus/anki/docs/architecture.md`
- `/home/whwen/documents/reso/Varnamalaplus/anki/docs/language_bridge.md`
- `/home/whwen/documents/reso/Varnamalaplus/anki/rslib/src/collection/mod.rs`
- `/home/whwen/documents/reso/Varnamalaplus/anki/rslib/src/import_export/package/apkg/import/mod.rs`
- `/home/whwen/documents/reso/Varnamalaplus/anki/rslib/src/notetype/render.rs`
- `/home/whwen/documents/reso/Varnamalaplus/anki/rslib/src/scheduler/`
- `/home/whwen/documents/reso/Varnamalaplus/anki/proto/anki/scheduler.proto`

外部：

- Anki：<https://github.com/ankitects/anki>
- Anki 架构：<https://github.com/ankitects/anki/blob/main/docs/architecture.md>
- AnkiDroid Backend：<https://github.com/ankidroid/Anki-Android-Backend>
- cargo-ndk：<https://github.com/bbqsrc/cargo-ndk>
- Flutter Android FFI：<https://docs.flutter.dev/platform-integration/android/c-interop>
