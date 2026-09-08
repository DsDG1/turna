# Firebase App Distribution（GitHub Actions）

工作流：[`.github/workflows/firebase_app_distribution.yml`](../.github/workflows/firebase_app_distribution.yml)。

合并本流程后，维护者配置 GitHub Secrets，即可用 **Actions → Firebase App Distribution → Run workflow**（或推送 `v*` 标签）打出 arm64 发布 APK，并上传到 App Distribution。测试员会收到 App Tester 通知 / 安装链接。

Android 应用配置 `android/app/google-services.json` 已入库（Firebase 项目 `turna-d0d5e`，包名 `me.dsdogs.turna`）。**不要**提交服务账号 JSON 或 keystore。App Distribution **上传**走 Firebase Admin API（`FIREBASE_APP_ID` + `FIREBASE_SERVICE_ACCOUNT`）；APK 不必内嵌完整 Firebase SDK。

## 触发方式

| 触发 | 说明 |
|---|---|
| `workflow_dispatch` | 必有。Actions 页手动跑，不必等 tag。可填 version、tester 组、release notes。 |
| 推送 `v*` tag | 例如 `v0.8.0`。version 取去掉前缀 `v` 后的 tag 名。 |

构建走现有 `python3 tool/build_release.py`（与 `make build-release` 同源）：`pub get`、`build_runner`、arm64 `--split-per-abi` APK，并校验 APK 内嵌 `lib/arm64-v8a/libturna_anki.so`。Native `.so` 在脚本前按 `official_anki.yml` 同一套 NDK/Rust/`build.sh` 产出。Web、AAB 与课程 lint 在此工作流里跳过（课程校验仍由 `course_validation.yml` 负责；Play 用 AAB 请本地 `make build-release`）。

## 一次性：Firebase Console

1. 项目已存在：[`turna-d0d5e`](https://console.firebase.google.com/project/turna-d0d5e/overview)，Android 包名 **`me.dsdogs.turna`**。
2. **App Distribution → Testers and groups** → 新建组，默认工作流使用组名 **`testers`**（大小写需一致）。把测试员邮箱加进该组。
3. 创建用于上传的 Google Cloud **服务账号**（维护者仍需完成）：
   - Google Cloud Console（同一 GCP 项目）→ IAM → 服务账号 → 创建（例如 `turna-app-distribution`）。
   - 授予角色 **Firebase App Distribution Admin**（`roles/firebaseappdistro.admin`）。若控制台没有该预设角色，用 Firebase 文档中的等价权限（至少能调用 App Distribution 上传 API）。
   - 创建 JSON 密钥，把**整份 JSON**粘进 GitHub Secret `FIREBASE_SERVICE_ACCOUNT`。密钥文件不要提交。

## 一次性：GitHub Secrets

仓库 **Settings → Secrets and variables → Actions** 添加：

| Secret | 必填 | 内容 |
|---|---|---|
| `FIREBASE_APP_ID` | 是 | `1:644663272231:android:4b600e3bcdef21a051bf02`（`google-services.json` 的 `mobilesdk_app_id`） |
| `FIREBASE_SERVICE_ACCOUNT` | 是 | 服务账号 JSON **全文**（仍由维护者创建，勿提交文件） |
| `ANDROID_KEYSTORE_BASE64` | 否 | 发布 keystore 的 base64（`base64 -w0 upload-keystore.jks`） |
| `ANDROID_KEYSTORE_PASSWORD` | 与 keystore 同组 | `storePassword` |
| `ANDROID_KEY_ALIAS` | 与 keystore 同组 | `keyAlias` |
| `ANDROID_KEY_PASSWORD` | 与 keystore 同组 | `keyPassword` |

### 签名现状

`android/app/build.gradle` 在缺少 `android/key.properties` 时，**release 回退到 debug 签名**。本地 / 现有 CI smoke 也是这条路径。

- **不配 keystore secrets**：工作流仍能产出可安装 APK，测试员能装，但签名是 debug，以后换成正式 keystore 时无法作为同一签名应用升级。
- **要装得像正式包**：把四个 `ANDROID_*` secrets 配齐。工作流会在 runner 上写出 `android/key.properties`（keystore 放在 `$RUNNER_TEMP`，不进 git）。

## 手动运行

1. GitHub → Actions → **Firebase App Distribution** → **Run workflow**。
2. 可选：`version`（默认 `pubspec` 版本 + `-dist.<run_number>`）、`groups`（默认 `testers`）、`release_notes`（默认最近一次 commit subject）。
3. 成功后：Firebase Console → App Distribution 能看到该 APK；测试员走 App Tester 或邮件链接安装。同一 run 还会挂一份 APK artifact（保留 14 天）。

## 限制

- 产物仅 **arm64-v8a**（与 `build_release.py` / doc 34 §14.2 一致）。
- 本工作流只负责**分发**；未额外加入 Flutter Firebase SDK。
- 首次上传前必须已配置 `FIREBASE_SERVICE_ACCOUNT`、tester 组 `testers`（或 dispatch 时改 `groups`），否则 upload step 会失败。
