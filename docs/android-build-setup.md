# Android 构建说明

> 本项目使用**官方 Flutter SDK**，主力产品平台为 **Android**。OHOS / OpenHarmony 产品支持已退役（见 [ADR 0041](./decisions/0041-ohos-product-eol.md) 与 [doc 34](./official-anki-migration/34-official-anki-production-cutover-and-ohos-retirement-plan.md)）。
>
> 维护者快速入口：构建报错时先看 [常见错误速查](#常见错误速查)。

---

## TL;DR（首次或换机器）

```bash
# 1. 确保 JAVA_HOME 指向 JDK 17（User 级环境变量，见下文）
#    重启终端后: java -version 应显示 17
# 2. 装依赖
flutter pub get
# 3. 构建
flutter build apk --debug
# 4. 发布 APK 仅 arm64（Official native，doc 34 §14.2）
flutter build apk --release --split-per-abi --target-platform android-arm64
```

---

## 1. 环境要求

### JDK 17（必须）

AGP 8.x 要求 JDK 17+。机器若装了 Java 8，`gradlew` 会用 `JAVA_HOME` 指向的版本并报 JVM 过旧。

**设置**（Windows，User 级，覆盖系统级、无需管理员）：

```powershell
[Environment]::SetEnvironmentVariable('JAVA_HOME', 'C:\Program Files\Microsoft\jdk-17.0.8.101-hotspot', 'User')
```

然后**重启终端 / Android Studio**（当前会话不会自动刷新环境变量）。

- 可用 JDK：`jdk-17`（Microsoft，**推荐**）、`jdk-21`（也可）。
- **不要用过新的实验 JDK**：确认 Gradle 版本支持的上限。
- 验证：`java -version` 显示 `17.x`。

### Flutter SDK

使用**官方 stable**（或项目 CI 固定的版本）。`flutter --version` 应显示官方渠道，**不是** `*-ohos*` fork。

```bash
flutter channel stable
flutter upgrade
flutter doctor
```

---

## 2. 依赖与构建

```bash
flutter pub get
flutter build apk --debug    # 或 --release
flutter test
flutter analyze
```

生成代码已提交；仅在修改 `@freezed` / `@JsonSerializable` / `@AutoRoute` / `@injectable` 后需要：

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

---

## 常见错误速查

| 症状 | 原因 | 处理 |
|---|---|---|
| `Dependency requires at least JVM runtime version 11` | `JAVA_HOME` 指向过旧 JDK | 设为 JDK 17 并重启终端 |
| `sdk.dir` / Android SDK 找不到 | 本地 `android/local.properties` 未配置 | Android Studio 打开工程一次，或手写 `sdk.dir=` |
| `LICENSE` / NDK 相关 | SDK 组件未装全 | `sdkmanager` 安装 platform-tools / build-tools / NDK（按 `android/app/build.gradle` 要求） |
| `file_picker` / notifications 行为异常 | 旧 OHOS Git override 残留 | 确认 `pubspec.yaml` **无** OHOS community Git `dependency_overrides`；删 `pubspec.lock` 后重跑 `flutter pub get` |

---

## Firebase App Distribution

向测试员分发 arm64 发布 APK：GitHub Actions 工作流 `.github/workflows/firebase_app_distribution.yml`（`workflow_dispatch` 或 `v*` tag）。一次性 Firebase Console 与 GitHub Secrets 见 [`docs/firebase-app-distribution.md`](./firebase-app-distribution.md)。

---

## 与 OHOS 退役的关系

- 仓库不再包含 `ohos/` 产品 target 或 OHOS fork 补丁目录/脚本。
- 不再要求 HarmonyOS Flutter fork 或对 pub cache / Flutter SDK 打外部补丁。
- 残留 OHOS 安装的数据出口见 `lib/application/migration/turna_migration_export.dart`（`turna-migration-v1`）与 ADR 0041。

## Official Anki release ABI

Official native (`libturna_anki.so`) is packaged for **arm64-v8a** only:

```bash
flutter build apk --release --split-per-abi --target-platform android-arm64
```

Do not ship a fat multi-ABI APK that claims other ABIs without matching `libturna_anki.so` (doc 34 §14.2 — fail closed, never Legacy fallback).

### Remaining dart-defines

Production Official capabilities are **not** toggled per-feature. `OfficialAnkiFeatureFlags.fromEnvironment()` is the Android Official bundle. Optional:

| Define | Default | Meaning |
|---|---|---|
| `TURNA_OFFICIAL_ANKI_CUTOVER` | `true` | Pause new Official import/review (`false` → Anki unavailable, not Legacy) |
| `TURNA_OFFICIAL_ANKI_DIAGNOSTICS` | `false` | Release diagnostics route guard |
| `TURNA_OFFICIAL_ANKI_REVIEWER_DIAGNOSTICS` | `false` | Reviewer diagnostics |
| `TURNA_OFFICIAL_ANKI_COURSE_GRADES_SCHEDULER` | `false` | Course answers write Official scheduler |

Do not pass `TURNA_OFFICIAL_ANKI_ENGINE` / `IMPORT` / `GRAY_COHORT` / `OFFICIAL_FIRST_IMPORT` — those dart-defines were collapsed (doc 34 C4).
