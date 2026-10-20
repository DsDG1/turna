# Android 构建说明

> 本项目使用**官方 Flutter SDK**，主力产品平台为 **Android**。鸿蒙的**产品级**支持已退役，但存在**不进主交付**的伴生轻量版（[ADR 0047](./decisions/0047-ohos-companion-lite-build.md)）。三层口径（产品级 / 伴生版 / Official Anki）与 Hold 项见 [`status.md`](./status.md) §6。**本页只讲 Android**；伴生版的 fork SDK 与 `flutter build hap` 口径见 [AGENTS.md](../AGENTS.md) §9.1 与 ADR 0047，**两者不可混用**。
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
# 4. 发布 APK 仅 arm64（Official native，ADR 0044）
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

## 与 OHOS 伴生版的关系

`ohos/` 目录在仓库里存在，它是**伴生版**的产品 target（[ADR 0047](./decisions/0047-ohos-companion-lite-build.md)）。它是 Android 构建的一部分，但**不随正式版发布**，也不进主 CI。

**成立的三条：**

- 不引入 OHOS fork 补丁工具链（补丁脚本与补丁目录，ADR 0047 §2 第 6 条点名的那两个
  路径）保持删除，伴生版走预编译 SDK 路线。
- 伴生版**要求** HarmonyOS Flutter fork，但**不要求**对 pub cache / Flutter SDK 打外部补丁
  （自维护的两处 Flutter 侧移植都在仓库内、受版本控制、由门禁断言，见 ADR 0047 §7）。
- 残留 OHOS 安装的数据出口见 `lib/application/migration/turna_migration_export.dart`
  （`turna-migration-v1`）与 [ADR 0050](./decisions/0050-ohos-official-anki.md)。

`ohos/` 与 5 条钉 ref 的社区 fork override 随伴生版存在（清单见 ADR 0047 §6），
受 `ohos_eol_architecture_guard_test.dart` 的 override ratchet 约束。

**依赖排查提示：** 上表「`file_picker` / notifications 行为异常 → 确认 `pubspec.yaml`
**无** OHOS community Git `dependency_overrides`」这条在伴生树下**会误导**——
`shared_preferences` / `path_provider` / `url_launcher` / `package_info_plus` /
`share_plus` 五条 override 是伴生版的**预期状态**。Android 侧遇到插件行为异常时，
应改查 `flutter --version` 确认当前用的是官方 SDK 而非 fork。

**Official Anki 的鸿蒙口径：** 引擎层已在鸿蒙真机验证可行，全档接线已授权
（[ADR 0050](./decisions/0050-ohos-official-anki.md)）且**接线步 0–5b 已施工**
——真机首卡全链路（渲染 / 翻卡 / 评分落库 / 队列前进 / 强杀恢复）已走通；
余项为真机导入、课程学习解锁与步 6 独立 CI 首跑收据。
当前口径与 Hold 项见 [`status.md`](./status.md) §6。
本页的 arm64-only ABI 约束目前只约束 Android 产物（鸿蒙伴生版另有一份提交进
`ohos/entry/libs/arm64-v8a/` 的 `.so`，由 `ohos_eol_architecture_guard_test.dart` 断言）。

## Official Anki release ABI

Official native (`libturna_anki.so`) is packaged for **arm64-v8a** only:

```bash
flutter build apk --release --split-per-abi --target-platform android-arm64
```

Do not ship a fat multi-ABI APK that claims other ABIs without matching `libturna_anki.so` (ADR 0044 — fail closed, never Legacy fallback).

### Remaining dart-defines

Production Official capabilities are **not** toggled per-feature. `OfficialAnkiFeatureFlags.fromEnvironment()` is the Android Official bundle. Optional:

| Define | Default | Meaning |
|---|---|---|
| `TURNA_OFFICIAL_ANKI_CUTOVER` | `true` | Pause new Official import/review (`false` → Anki unavailable, not Legacy) |
| `TURNA_OFFICIAL_ANKI_DIAGNOSTICS` | `false` | Release diagnostics route guard |
| `TURNA_OFFICIAL_ANKI_REVIEWER_DIAGNOSTICS` | `false` | Reviewer diagnostics |
| `TURNA_OFFICIAL_ANKI_COURSE_GRADES_SCHEDULER` | `false` | Course answers write Official scheduler |

Do not pass `TURNA_OFFICIAL_ANKI_ENGINE` / `IMPORT` / `GRAY_COHORT` / `OFFICIAL_FIRST_IMPORT` — those dart-defines were collapsed (ADR 0043).
