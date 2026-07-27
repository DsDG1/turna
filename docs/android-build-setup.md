# Android 构建说明（OHOS Flutter 分支）

> 本项目基于 **OpenHarmony Flutter 分支**（`3.35.8-ohos`，SDK 在 `C:\Users\DsDogs\Desktop\developper\flutter_flutter`），不是官方 Flutter。Android 构建需要 **JDK 17** 和 **一组源码补丁**才能跑通。本文说明如何配置与排错。
>
> 维护者快速入口：构建报错时先看 [常见错误速查](#常见错误速查)。

---

## TL;DR（首次或换机器）

```bash
# 1. 确保 JAVA_HOME 指向 JDK 17（User 级环境变量，见下文）
#    重启终端后: java -version 应显示 17
# 2. 装依赖
flutter pub get
# 3. 应用 OHOS fork 构建补丁（幂等，可重复跑）
bash tool/apply_patches.sh
# 4. 构建
flutter build apk --debug
```

---

## 1. 环境要求

### JDK 17（必须）

AGP 8.11.1 要求 JDK 17+。机器若装了 Java 8（如 Zulu 8），`gradlew` 会用 `JAVA_HOME` 指向的版本，报：

```
Dependency requires at least JVM runtime version 11. This build uses a Java 8 JVM.
```

**设置**（Windows，User 级，覆盖系统级、无需管理员）：

```powershell
[Environment]::SetEnvironmentVariable('JAVA_HOME', 'C:\Program Files\Microsoft\jdk-17.0.8.101-hotspot', 'User')
```

然后**重启终端 / Android Studio**（当前会话不会自动刷新环境变量）。

- 可用 JDK：`jdk-17`（Microsoft，**推荐**）、`jdk-21`（也可）。
- **不要用 jdk-26**：Gradle 8.14 只支持到 JDK 24，会报错。
- 验证：`java -version` 显示 `17.x`。

### Flutter SDK

使用 OHOS 分支克隆：`C:\Users\DsDogs\Desktop\developper\flutter_flutter`（`flutter --version` 显示 `3.35.8-ohos-1.0.4-beta`）。

---

## 2. 源码补丁（`tool/apply_patches.sh`）

OHOS fork 的工具链和部分 fork 插件与当前 AGP/Kotlin/Android SDK 不兼容，需要 4 处源码修改。这些修改在 **Flutter SDK** 和 **pub cache** 里（仓库外、易失），所以做成补丁文件 + 重放脚本，版本化在仓库 `tool/patches/` 下。

### 什么时候跑

- `flutter pub get`（若某个 git 依赖的 ref 变了、重新拉取）
- `flutter pub cache clean`
- 重新克隆 / 更新 OHOS Flutter fork 之后
- 构建报“找不到符号 / compilerOptions / 空安全”类错误时

平时不用跑（脚本幂等，已应用会自动 skip）。

### 怎么跑

```bash
bash tool/apply_patches.sh
```

可选环境变量覆盖路径：

```bash
PUB_CACHE=/path/to/pub/cache FLUTTER_SDK=/path/to/flutter_flutter bash tool/apply_patches.sh
```

### 工作原理

- **幂等**：每个补丁有一个唯一标记字符串，`grep` 到 = 已应用 → skip；否则用 `patch -p1 --forward` 应用。
- **用经典 `patch`，不用 `git apply`**：`git apply` 会被 git-format diff 里的 `index` 哈希行干扰，静默 “Skipped” 不改文件。`patch` 可靠。
- **glob 查找 checkout 目录**：按 `fluttertpc_flutter_local_notifications-*` 这类模式找，不硬编码 hash，ref 变了也能定位。

### 4 个补丁

| 补丁文件 | 作用目标 | 修复内容 |
|---|---|---|
| `flutter_tools-kgp-2.0.21.patch` | Flutter SDK `packages/flutter_tools/gradle/build.gradle.kts` | KGP `1.8.0`→`2.0.21`。flutter_tools 在组合构建的隔离 classloader 里绑定 KGP 1.8.0，插件子项目实际加载的就是它（根项目 `ext.kotlin_version=2.2.20` **够不到**它们）。现代插件用的扩展级 `kotlin { compilerOptions {} }` 要 KGP 2.0+。 |
| `jni-task-compilerOptions.patch` | pub cache `hosted/.../jni-1.0.1/android/build.gradle` | 扩展级 `kotlin { compilerOptions {} }` → 任务级 `tasks.withType(KotlinCompile).configureEach { compilerOptions{} }`（KGP ≥1.8 通用）。 |
| `flutter_local_notifications-fix.patch` | pub cache git `fluttertpc_flutter_local_notifications-*/.../FlutterLocalNotificationsPlugin.java` | `bigLargeIcon(null)`→`bigLargeIcon((Bitmap) null)`（AndroidX 新增 `bigLargeIcon(Icon)` 重载，`null` 歧义）。 |
| `package_info_plus-nullsafe.patch` | pub cache git `flutter_plus_plugins-*/.../PackageInfoPlugin.kt` | 3 处 Kotlin 空安全（`?.loadLabel ?: ""`、`versionName ?: ""`、`signatures.first()` smart-cast）。Kotlin 2.0 把 Android `@RecentlyNullable` 当真可空（1.x 宽松），fork 代码按 1.x 写的会报错。 |

> 补充：`flutter_local_notifications` 的 `ScheduledNotificationRepeatFrequency.java` 枚举**不需要补丁**--它在 fork 的 HEAD 里就有，只是某次工作区脏了才缺失。fresh checkout 会有。若发现它缺失：`git -C <fln_checkout> checkout -- .`。

---

## 3. 常见错误速查

| 报错 | 原因 | 处理 |
|---|---|---|
| `requires at least JVM runtime version 11 ... Java 8 JVM` | `JAVA_HOME` 指向 Java 8 | 设 User 级 `JAVA_HOME` 为 JDK 17，重启终端（见 [JDK 17](#jdk-17必须)） |
| `Could not find method compilerOptions() ... KotlinAndroidProjectExtension`（在 `:jni` 或 `:shared_preferences_android` 等） | KGP 还是 1.8.0（flutter_tools 没升） | 跑 `bash tool/apply_patches.sh`（应用 flutter_tools KGP 补丁） |
| `Only safe (?.) or non-null asserted (!!.) calls ... on a nullable receiver`（在 `:package_info_plus` 等 OHOS fork 插件） | Kotlin 2.0 严格空安全，fork 代码没适配 | 跑 `bash tool/apply_patches.sh`（应用对应空安全补丁） |
| `bigLargeIcon(Bitmap) ... bigLargeIcon(Icon) ... 匹配`（在 `:flutter_local_notifications`） | AndroidX 重载歧义 | 跑 `bash tool/apply_patches.sh`（应用 FLN 补丁） |
| `找不到符号 ... ScheduledNotificationRepeatFrequency` | FLN 工作区脏（枚举文件缺失，HEAD 里其实有） | `git -C <fln_checkout> checkout -- .`，再跑补丁脚本 |
| 其他插件 Kotlin 编译报空安全错 | 同 package_info_plus 模式 | 见 [新增补丁](#4-新增补丁当出现新的插件编译失败) |

---

## 4. 新增补丁（当出现新的插件编译失败）

OHOS fork 生态滞后，未来可能还有插件在 Kotlin 2.0 / 新 Android SDK 下编译失败。按这套流程加补丁：

1. **定位**：报错信息里的插件名 + 文件。判断属于哪类：
   - 扩展级 `compilerOptions`（`kotlin { compilerOptions {} }`）→ 说明 KGP 还是 1.8.0，先确认 flutter_tools KGP 补丁已应用；若已应用仍报，说明该插件用了别的 2.0+ DSL，按需 patch。
   - Kotlin 空安全（`nullable receiver`、`String?` 传给 `String`）→ 用 `?.` / `?: ""` / smart-cast 修。
   - fork 残缺源码（缺文件、API 歧义）→ 针对性修。
2. **改源码**：直接改 pub cache 里那个文件，让 `flutter build` 通过。
3. **生成补丁**（在该插件 checkout 目录里）：
   ```bash
   # git 依赖（checkout 是 git 仓库）：
   git -C <插件checkout目录> diff --relative -- <改的文件> > tool/patches/<插件名>-<简述>.patch
   # hosted 依赖（非 git）：手工写 unified diff，路径用 a/<rel> b/<rel>
   ```
4. **注册到脚本**：在 `tool/apply_patches.sh` 末尾加一段 `apply_if_needed`，指定 `目标目录`、`patch文件`、`标记文件`、`标记字符串`（标记 = 应用后文件里一定存在的唯一字符串）。
5. **验证**：撤销该改动，跑 `bash tool/apply_patches.sh`，确认报 `[applied]`；再跑一次确认报 `[skip: already applied]`；最后 `flutter build apk --debug` 通过。
6. **提交**：`git add tool/apply_patches.sh tool/patches/`。

---

## 5. 关键文件

| 文件 | 作用 |
|---|---|
| `tool/apply_patches.sh` | 补丁重放脚本（幂等） |
| `tool/patches/*.patch` | 4 个源码补丁 |
| `android/build.gradle` | 项目自身配置（`ext.kotlin_version = '2.2.20'`，subprojects 强制 compileSdk/targetSdk 36）。**未改动**。 |
| Flutter SDK `packages/flutter_tools/gradle/build.gradle.kts` | flutter_tools 绑定的 KGP（由补丁改为 2.0.21）。仓库外。 |

---

## 6. 备注

- **环境层（JDK 17 的 `JAVA_HOME`）不在仓库里**，换机器需手动设一次。
- **补丁层（`tool/`）在仓库里**，提交后换机器/新同事 `git pull` + 跑一次脚本即可。
- OHOS fork 更新后，`flutter_tools-kgp-2.0.21.patch` 可能需要重新生成（若上游改了那一行）。脚本会报 `[WARN]` 提示。
- 决策背景见 `docs/decisions/`（OHOS 迁移相关 ADR）。
