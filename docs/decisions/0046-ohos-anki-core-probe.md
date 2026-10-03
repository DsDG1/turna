# ADR 0046: Anki 引擎层在 OpenHarmony 上可行（探针收据）

- 状态：已接受（探针结论）
- 日期：2026-10-03
- 关联：[`0041-ohos-product-eol.md`](./0041-ohos-product-eol.md)（产品退役，**本 ADR 不撤销它**）

## 背景

ADR 0041 判定 OHOS 产品线退役。随之而来的是一批「如果哪天要复活，Anki
引擎怎么办」的悬空问题，其中最硬的一条是：rslib 能不能交叉编译到
OpenHarmony。

`34-official-anki-migration` 文档把 Android 侧验收记为 NO-GO，但**没有**给出
OHOS 侧的引擎可行性判断——因为那需要一次真机实验才能回答。ADR 0041 退役的是
「鸿蒙产品」，不是「鸿蒙平台的引擎知识」。本 ADR 只补后者。

## 结论

**引擎存储层在 OpenHarmony 上可行。** 真机（HUAWEI Mate 90 Pro Max，
aarch64，API 26，HarmonyOS 7.0.0.109）实测 7 个探针符号：

| 探针 | 真机结果 |
|---|---|
| `dlopen("libturna_anki_probe.so")` | **OK** |
| `turna_anki_abi_version()` | **1** |
| `sqlite_roundtrip` | **PASS** |
| `unicase_collation` | **PASS**（自定义排序规则 + VACUUM b-tree 重建） |
| `set_fs_path` | **0** |
| `tokio_runtime` | **PASS** |
| `tokio_fs` | **PASS** |
| `tokio_signal` | **挂死** |

产物 `libturna_anki_probe.so`，2,939,144 字节，`elf64-littleaarch64` /
`EM_AARCH64` / `SharedObject`，**`NEEDED` 仅 `libc.so`**——`bundled` 的 SQLite
确实静态编入，不需要外部 `libsqlite3.so`。

## `tokio_signal` 挂死为什么不是阻断

这是本次唯一的真实失败，定责明确：

- rslib 全仓 `tokio::signal` 只有**一处**调用：
  `anki/rslib/src/sync/http_server/mod.rs` 的 `tokio::signal::ctrl_c()`。
  那是「用 HTTP 提供牌组服务」用的，Turna 的 bridge 走 C ABI 直接调引擎，
  **根本不会进入该路径**。
- `bridge/src/*.rs` 对 tokio 的引用数为 **0**。`signal` feature 是在
  `Cargo.toml` 里启用的，但桥接层没有代码去用它。

所以挂死落在一条 Turna 不走的代码路径上。**这不等于该 feature 安全**——如果
将来要在鸿蒙上做 HTTP 同步服务，必须先解决它。

## 探针过程中被自己骗到的一次

`tokio_fs` 第一次真机跑返回 `-32`（`read_dir` 报错）。差点记成「tokio 文件
系统在 OHOS 上坏了」——而 rslib 到处依赖 `tokio::fs` 做媒体处理，这个结论
会直接否掉整条路线。

实际原因是探针读了 `"."`：ArkTS ability 进程的 cwd 不保证可枚举。改用调用方
传入的 `filesDir`（刚往里写过文件，必可读）后返回 **PASS**。

**教训**：探针报告失败时，先证明失败的是被测对象而不是探针本身。这条 `-32`
和真正的 `tokio_signal` 挂死在原始输出里长得一模一样。

## 同批追加：真 rslib 与真机引擎生命周期

上一节只用最小 crate 做了隔离验证，rslib 自身依赖树仍未证明。**同批补齐，
且零阻力**：

- 交叉编译 `Finished release profile in 2m 39s`：无 feature 被迫关闭、无 C
  依赖编不过、无补丁冲突
- `libturna_anki.so` **23,123,056 字节**，`NEEDED` = `libc.so` +
  `libtime_service_ndk.so`，7 个 bridge 符号全导出
- **`protoc` 无需为 OHOS 换版**：它是宿主工具而非目标工具，编 Android 的那个
  Windows 二进制直接编这个 target
- 新依赖 `libtime_service_ndk.so` 来自 `iana-time-zone` 的 `tz_ohos.rs`
  （取本地时区）。良性，但 `verify_bridge_symbols.sh` 因此断言**每个
  `NEEDED` 都能在 sysroot 解析**——让解析不了的依赖在构建期失败而非设备期

**真机**（Mate 90 Pro Max，hap 进程内 dlopen）：

```
dlopen("libturna_anki.so")   OK
turna_anki_abi_version()     1
turna_anki_engine_new        status 0, buffer len 8 (u64 handle)
turna_anki_engine_close      status 0
dlclose                      OK
```

`engine_new` 是真检验：它内部调 `touch_rslib()`，构建并关闭一个内存
`Collection`。status 0 因此意味着 **rslib 与 bundled SQLite 在设备上真的
初始化过**。`buffer len` 恰为 8 证明 C ABI 结构布局与 `bridge/src/abi.rs`
一致。进程存活无 fault。

契约以 Dart 侧 FFI 声明为准而非臆测：`TurnaAnkiResult` / `TurnaAnkiBuffer`
布局、以及 `_engineNew(nullptr, 0)`（**确实不需要 config payload**）都直接
读自 `official_anki_native_transport.dart`。

## 范围边界（必须一起读）

本 ADR **只**覆盖引擎存储层与引擎生命周期。以下全部**未验证**，不得由本结论
外推：

- rslib 完整交叉编译**已通过**（见上），但**磁盘 collection 打开**未验证
- 复习调度器在真实复习负载下的行为
- 导入链路（`turna_anki_call` 的 operation 分发与 JSON 契约）
- 卡片渲染：Android 侧 1,161 行 Kotlin / iOS 侧 846 行 Swift 的
  ArkTS 移植**完全未评估**
- `official_anki_sqlite.dart` 需新增 OHOS 分支（`ensureOfficialAnkiSqlite()`
  只覆盖 Linux/Android），且要随 hap 分发一个**独立**的 `libsqlite3.so`
  ——与 bridge 内的静态 sqlite 是两套，`bundled` 只免掉了前者的依赖

## 副作用

`test/application/anki_official/ohos_eol_architecture_guard_test.dart` 扫描
`lib` / `tool` / `.github` / `README.md` / `AGENTS.md` /
`docs/project-guide.md` / `docs/android-build-setup.md`，**不扫** `native/` 与
`docs/decisions/`。本批新增的 OHOS 构建工具链落在 `native/turna_anki_core/`
下，因此门禁保持绿。

这是**有意的例外，不是侥幸**：在一条声明 OHOS 已退役的分支上新增 OHOS 构建
工具链，只有在「它不复活产品线、只固化已验证的引擎知识」这个前提下才成立。
该前提由本 ADR 记录。**若将来真的推进鸿蒙产品线，必须先撤销 ADR 0041 并重写
门禁**，不能靠加白名单绕过。

## 产物

- `native/turna_anki_core/probe-ohos/`：探针 crate（6 个宿主测试）
- `native/turna_anki_core/build-ohos/build.sh`、`verify_symbols.sh`、
  `README.md`（四个真实构建坑的成因与对策）
