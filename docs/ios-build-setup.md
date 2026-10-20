# iOS 构建说明

> iOS 已接通官方 Anki Core（静态链接 rslib + WKWebView 复习器），与 Android 走同一条 Official 生产路径。本文只覆盖**构建链**；产品口径（iOS 为何算 Official、验收状态）见 [project-guide §6 与 §10](./project-guide.md)。
>
> 维护者快速入口：构建报错时先看 [已知问题](#已知问题)。原生静态库那一段的完整细节在 [`native/turna_anki_core/README.md`](../native/turna_anki_core/README.md) 的「iOS static-library commands」小节，本文不复制。

---

## TL;DR（首次或换机器）

```bash
# 1. 环境：官方 Flutter SDK（本项目 CI 钉 3.44.5）+ Xcode
flutter --version          # 官方 stable 渠道，不是任何 *-ohos* fork
xcodebuild -version

# 2. 依赖
flutter pub get

# 3. 先重建原生静态库 —— ios/Frameworks/TurnaAnki.xcframework 不入库！
cd native/turna_anki_core
git submodule update --init anki
git -C anki submodule update --init --depth 1 ftl/core-repo ftl/qt-repo
export PROTOC="$PWD/tools/protoc/bin/protoc"   # 或跑 build-android/fetch_protoc.sh
export PROTOC_BINARY="$PROTOC"
./build-ios/build.sh                            # 产出 ios/Frameworks/TurnaAnki.xcframework
cd ../..

# 4. 构建（模拟器）
flutter build ios --simulator --no-codesign
```

---

## 1. 环境要求

### Flutter SDK

官方 stable。CI（`.github/workflows/flutter_ci.yml`、`official_anki.yml`、`firebase_app_distribution.yml`）把 `flutter-version` 钉在 **3.44.5**，本地建议对齐同一版本。`flutter doctor` 应无红色项。

> 注意：**CI 里没有 macOS runner**（所有 job 都是 `ubuntu-latest` / `windows-latest`），所以 iOS 构建完全没有流水线门禁，全靠本地执行。改坏 iOS 链接不会让 CI 变红。

### Xcode

`ios/Runner.xcodeproj` 需要 `xcodebuild`、`lipo`、`xcrun -f nm`（`build-ios/build.sh` 与 `verify_symbols.sh` 都要用）。仓库**未固定 Xcode 版本**（没有任何 workflow 或文档钉它）——用能跑通模拟器 26.x 的稳定版即可；Xcode 版本与 iOS SDK 的具体下限属**未核实**项。

Rust 侧另需 `1.97.1` 工具链（`rust-toolchain.toml`）与 `protoc` 31.1，见下一节。

### 部署目标

Runner target 的三个配置（Debug / Release / Profile）都是 `IPHONEOS_DEPLOYMENT_TARGET = 15.0`，`SUPPORTS_MACCATALYST = NO`。`build-ios/build.sh` 默认也用 15.0（可用环境变量 `IPHONEOS_DEPLOYMENT_TARGET` 覆盖，**改了要两边一起改**，否则 `___chkstk_darwin` 链接失败）。

---

## 2. 原生 rslib 静态库链

iOS 侧没有 `dlopen` 可用的 dylib，Anki 核心是以 **staticlib 打进 app 二进制**的：

| 环节 | 位置 | 产物 |
|---|---|---|
| crate 声明 | `native/turna_anki_core/Cargo.toml` | `crate-type = ["cdylib", "rlib", "staticlib"]` |
| 构建 + 打包 | `native/turna_anki_core/build-ios/build.sh` | device arm64 + simulator arm64/x86_64 fat → `ios/Frameworks/TurnaAnki.xcframework` |
| 符号校验 | `native/turna_anki_core/build-ios/verify_symbols.sh` | 7 个 `_turna_anki_*` 导出处 + arm64 slice + ≥ 2 MiB |
| Xcode 接线 | `ios/Runner.xcodeproj/project.pbxproj` | xcframework 引用 + `-Wl,-u,_turna_anki_*` + `STRIP_STYLE=non-global` |
| Dart 侧打开 | `lib/application/anki_official/engine/official_anki_native_transport.dart` | iOS 分支走 `DynamicLibrary.process()` |

**xcframework 不入库**：`.gitignore` 有 `ios/Frameworks/TurnaAnki.xcframework/`，干净 clone 连 `ios/Frameworks/` 目录都没有，而 pbxproj 无条件引用该路径。命令、工具链表与 pbxproj 设置逐条说明见 [`native/turna_anki_core/README.md`](../native/turna_anki_core/README.md)。

---

## 3. 构建与验证

```bash
# 模拟器（无签名的最快回路）
flutter build ios --simulator --no-codesign

# 逐个校验静态库符号（build.sh 已自动跑过一次，可单独复跑）
./native/turna_anki_core/build-ios/verify_symbols.sh \
    native/turna_anki_core/target/aarch64-apple-ios/release/libturna_anki.a

# 在模拟器里跑
flutter devices && flutter run -d <simulator-id>
```

**真机构建**（需在 `ios/Runner.xcconfig` / Xcode 里配好签名团队与 bundle id `me.dsdogs.turna`）：

```bash
flutter build ios --release --no-codesign     # 出未签名包，先验证链接
flutter build ipa                            # 出可分发包，需要有效签名
```

> 真机 / release 链路的签名与产物**未在本仓库验证过**（无设备会话），见下节。

---

## 4. 与官方 Anki 引擎的关系

- iOS 已是 Official 产品路径，不是「暂不承诺」：`AnkiImportExecutionPlanner.productModeFor(platform: 'ios')` 返回 `AnkiProductMode.officialAndroid`（Android 沿用同一枚举值），即**导入、正式复习、课程投影都走官方 Core**，与 Android 同源同代码。实现见 `lib/application/anki_official/import/anki_import_execution_plan.dart`。
- 复习器是 **WKWebView**（不是 `webview_flutter`）：`ios/Runner/AnkiReviewer/` 下三个文件（`OfficialAnkiReviewerView` / `OfficialAnkiSchemeHandler` / `OfficialAnkiReviewerFactory`），在 `AppDelegate` 里用 `registrar(forPlugin: "OfficialAnkiReviewer")` 注册，Dart 侧 `lib/views/anki_official/official_anki_reviewer_view.dart` 在 iOS 上返回 `UiKitView`。
- 资源经自定义 scheme 提供：`OfficialAnkiSchemeHandler` 注册 `turna-anki://anki.local` 源（`config.setURLSchemeHandler`），服务端渲染资产与媒体按 Range/206 返回。这是代码注册，**不需要在 `Info.plist` 里登记 URL scheme**。
- 整个 iOS 官方栈由提交 `ec0170ae`（PR #7）引入；口径与状态以 [`status.md`](./status.md) 为准（**验收 NO-GO、迁移中，不得写「迁移完成」**）。

---

## 已知问题

| 症状 | 原因 | 处理 |
|---|---|---|
| 干净 clone 后 iOS 链接失败 / 找不到 `TurnaAnki.xcframework` | 产物 gitignored，仓库里没有 `ios/Frameworks/` | 先跑 `native/turna_anki_core/build-ios/build.sh` 生成 xcframework（需要 Xcode + `protoc` 31.1 + Anki FTL 子模块） |
| `___chkstk_darwin` / 链接期 undefined symbol | `IPHONEOS_DEPLOYMENT_TARGET` 与 Runner target（15.0）不一致 | 统一用 15.0；或用环境变量同步覆盖 `build.sh` 与 pbxproj |
| 运行时 `library_missing` / Official 能力全关 | staticlib 里的符号被链接器裁掉 | 确认 pbxproj 三个配置的 `-Wl,-u,_turna_anki_*` 都在，且 `STRIP_STYLE = non-global`（全局 strip 会删掉 C 符号） |
| 修改了 bridge 导出符号后 iOS 静默失联 | pbxproj 的 `-Wl,-u` 列表与 `verify_symbols.sh` 里的 7 个名字是**硬编码**的 | 两处同步更新，并重跑 `verify_symbols.sh` |
| iOS 改坏了 CI 不报 | 没有任何 macOS runner | 本地必跑 `flutter build ios --simulator --no-codesign` |

## 验证状态（不要越读）

- **已验证（仅模拟器）**：`flutter build ios --simulator --no-codesign` 链接通过、7 个 `turna_anki_*` 符号进 `Runner.debug.dylib`；iPhone 17 模拟器（iOS 26.5）上用真实 `.apkg` 走完导入 + 复习器 Q→A 渲染 E2E。收据见 `test/BASELINE.md`「iOS 官方 Anki 栈接通」条目。
- **未验证**：真机（clean install / 升级安装 / 强杀恢复）、release 构建与签名、TestFlight / App Store 分发。真机矩阵仍 Held，见 [`status.md`](./status.md) §4。
- **未核实**：Xcode 版本下限、iOS 26.x SDK 与本工程的具体兼容性边界。
