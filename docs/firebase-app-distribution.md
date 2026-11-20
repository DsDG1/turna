# Android 发布与 Firebase App Distribution（GitHub Actions）

工作流：[`.github/workflows/firebase_app_distribution.yml`](../.github/workflows/firebase_app_distribution.yml)（名称：**Android Release & Firebase Distribution**）。

工作流只编一次 arm64 发布 APK（经 `tool/build_release.py` 构建并校验内嵌 `libturna_anki.so`），同时覆盖 **GitHub Release**、**Workflow Artifact** 与可选的 **Firebase App Distribution**（Firebase 上传失败或未配置 secrets 时不阻断 GitHub Release）。

Android 应用配置已入库：`android/app/google-services.json`、`lib/firebase_options.dart`，入口 `Firebase.initializeApp`（仅 Android）。**不要**提交服务账号 JSON 或 keystore。App Distribution **上传**仍走 Admin API（`FIREBASE_APP_ID` + `FIREBASE_SERVICE_ACCOUNT`）。

## 触发方式

| 触发 | 产物与去向 |
|---|---|
| 推送 `v*` tag（如 `v0.9.1`） | 构建 `turna-v<version>-release.apk`（含 `.sha256`），**自动创建/更新对应 GitHub Release**；若已配 Firebase secrets，同步上传 App Distribution |
| `workflow_dispatch` 手动触发 | 默认上传 14 天保留的 Workflow Artifact，并按配置上传 Firebase；勾选 `publish_github_release` 时也会创建/更新 GitHub Release（`version` 默认取 `pubspec.yaml` 主版本号） |

构建走现有 `python3 tool/build_release.py`（与 `make build-release` 同源）：`pub get`、`build_runner`、arm64 `--split-per-abi` APK，并校验 APK 内嵌 `lib/arm64-v8a/libturna_anki.so`。Native `.so` 在脚本前按 `official_anki.yml` 同一套 NDK/Rust/`build.sh` 产出。Web、AAB 与课程 lint 在此工作流里跳过（课程校验仍由 `course_validation.yml` 负责；Play 用 AAB 请本地 `make build-release`）。注意：`tool/build_release.py` 会校验 `version` 核心段（`X.Y.Z`）与 `pubspec.yaml` 一致，发版 tag 需先对齐 `pubspec.yaml`。

## 一次性：Firebase Console（仅使用 App Distribution 时需要）

1. 项目已存在：[`turna-d0d5e`](https://console.firebase.google.com/project/turna-d0d5e/overview)，Android 包名 **`me.dsdogs.turna`**。
2. **App Distribution → Testers and groups** → 新建组，默认工作流使用组名 **`testers`**（大小写需一致）。把测试员邮箱加进该组。
3. 创建用于上传的 Google Cloud **服务账号**（维护者按需配置）：
   - Google Cloud Console（同一 GCP 项目）→ IAM → 服务账号 → 创建（例如 `turna-app-distribution`）。
   - 授予角色 **Firebase App Distribution Admin**（`roles/firebaseappdistro.admin`）。若控制台没有该预设角色，用 Firebase 文档中的等价权限（至少能调用 App Distribution 上传 API）。
   - 创建 JSON 密钥，把**整份 JSON**粘进 GitHub Secret `FIREBASE_SERVICE_ACCOUNT`。密钥文件不要提交。

## 一次性：GitHub Secrets

仓库 **Settings → Secrets and variables → Actions** 按需添加：

| Secret | 必填 | 内容 |
|---|---|---|
| `FIREBASE_APP_ID` | 仅 Firebase | `1:644663272231:android:4b600e3bcdef21a051bf02`（`google-services.json` 的 `mobilesdk_app_id`） |
| `FIREBASE_SERVICE_ACCOUNT` | 仅 Firebase | 服务账号 JSON **全文**（勿提交文件） |
| `ANDROID_KEYSTORE_BASE64` | 否 | 发布 keystore 的 base64（`base64 -w0 upload-keystore.jks`） |
| `ANDROID_KEYSTORE_PASSWORD` | 与 keystore 同组 | `storePassword` |
| `ANDROID_KEY_ALIAS` | 与 keystore 同组 | `keyAlias` |
| `ANDROID_KEY_PASSWORD` | 与 keystore 同组 | `keyPassword` |

### 签名现状

`android/app/build.gradle` 在缺少 `android/key.properties` 时，**release 回退到 debug 签名**。本地 / 现有 CI smoke 也是这条路径。

- **不配 keystore secrets**：工作流仍能产出可安装 APK 并挂到 GitHub Release，测试员能直接安装，但签名是 debug，以后换成正式 keystore 时无法作为同一签名应用覆盖升级。
- **要装得像正式包**：把四个 `ANDROID_*` secrets 配齐。工作流会在 runner 上写出 `android/key.properties`（keystore 放在 `$RUNNER_TEMP`，不进 git）。

## 手动运行

1. GitHub → Actions → **Android Release & Firebase Distribution** → **Run workflow**。
2. 可选参数：
   - `version`（发布 GitHub Release 时默认取 `pubspec.yaml` 主版本号如 `0.9.1`，否则默认为 `<pubspec>-dist.<run_number>`）
   - `publish_github_release`（勾选后会同步创建/更新 GitHub Release 并挂载 APK）
   - `cleanup_old_releases`（默认关闭；与 `publish_github_release` 同时勾选时，发布成功后清理更早的已发布 Release）
   - `upload_firebase`（默认开启；未配置 secrets 时自动跳过）
   - `groups`（默认 `testers`）、`release_notes`（默认自动生成或取最近一次 commit subject）
3. 成功后：同一 run 下会保留 APK + `.sha256` artifact（14 天）；若由 `v*` tag 触发或勾选了 `publish_github_release`，仓库 **Releases** 页面会直接挂载 `turna-v<version>-release.apk` 与校验文件。

### 发布后清理旧 Release

`cleanup_old_releases` 只在手动触发时生效，且必须先勾选 `publish_github_release`。清理步骤在本次 Release 和 APK 资产发布成功后运行，按 Release 的创建时间判断新旧：

- 删除所有**创建时间早于本次 Release**的已发布 Release，包括旧 prerelease；其 APK 等资产随 Release 一起删除，原下载链接会失效。
- 保留本次 Release、创建时间更晚的 Release 和所有草稿，避免重跑旧工作流时误删新版。
- **不删除任何 Git tag 或提交**，旧版本源代码仍可经 tag 取回。

普通 `v*` 标签推送的默认行为不变，不会自动清理旧 Release。

## 限制

- 产物仅 **arm64-v8a**（与 `build_release.py` / ADR 0044 一致）。
- 应用侧已接 `firebase_core` + `lib/firebase_options.dart`（仅 Android）。未加 Analytics / App Distribution 客户端 SDK；Firebase 测试员仍通过 **App Tester** 安装分发 APK，GitHub Release 用户可直接下载 APK 安装。
- Firebase 上传配置了 `continue-on-error: true`：若服务账号或测试组未就绪，该步骤会标黄跳过，不影响 GitHub Release 生成。
