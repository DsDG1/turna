# ADR 0031 — Turna Rebrand (Non-Visual)

> 状态：**已接受**｜日期：2026-08-03｜范围：仅非视觉改名 —— 产品文案、Dart 包与符号、原生平台标识、桌面 / Web / OHOS 名称、课程编辑器名、文档、兼容迁移。
>
> 方案原文：`~/Desktop/Turna改名计划.md`（用户自撰，仓库外）
>
> 不在范围：logo、应用图标、启动图、吉祥物美术、`assets/images/mala/*` 文件、主题色值、孔雀视觉 token。

## 理由

产品名继承自上游 `Varnamala`：Dart 包、原生配置、桌面启动器、Web manifest、OHOS bundle、课程编辑器、文档各层都还带着 `Varnamala` / `varnamala` / `vernamala` 标识。产品尚未发布，这是**公开发布前对齐身份、不必处理应用商店升级兼容的最后窗口**。改名由外部计划 `~/Desktop/Turna改名计划.md` 驱动；本 ADR 记录改名矩阵、迁移策略与审计规则，使后来者能区分「有意保留」与「漏改」。

## 决策

### 命名矩阵

| Object                        | Current                          | Target                  |
|-------------------------------|----------------------------------|-------------------------|
| User-visible product name     | Varnamala / Varnamala Plus       | **Turna**               |
| Dart package name             | `varnamala`                      | `turna`                 |
| Root Flutter widget           | `VarnamalaApp`                   | `TurnaApp`              |
| Brand theme class             | `VarnamalaTheme`                 | `TurnaTheme`            |
| Android namespace             | `com.varnamala.app`              | `me.dsdogs.turna`       |
| Android `applicationId`       | `com.varnamala.app`              | `me.dsdogs.turna`       |
| iOS / macOS Bundle ID         | `com.example.varnamala`          | `me.dsdogs.turna`       |
| Linux Application ID          | `com.example.varnamala`          | `me.dsdogs.turna`       |
| OHOS Bundle Name              | `me.dsdogs.vernamala`            | `me.dsdogs.turna.hmos`* |
| Windows / Linux binary name   | `varnamala`                      | `turna`                 |
| Course editor display name    | Varnamala Course Editor          | Turna Course Editor     |

\* 鸿蒙一行已由 [ADR 0051](./0051-ohos-bundle-name-unique-vs-android.md) 覆盖为 `me.dsdogs.turna.hmos`：AGC 要求鸿蒙包名不得与安卓 `applicationId` 相同。本文关于 Peacock token 保留原样的结论已由 [ADR 0033](./0033-turna-wetland-crane-palette.md) 修订：`peacock*` 别名按该 ADR 删除。

### 范围内

- User-visible product copy everywhere a user sees the brand.
- Dart package name, import paths, brand class names.
- Android, iOS, macOS, Windows, Linux, Web, OHOS application names and publishing identities.
- Course editor display name (`tool/gui`).
- Compatibility migration for local settings (QSettings) and config dirs.
- Current README, dev docs, user guides, non-historical docs.
- Test files, generated code, build configs — current product name.

### 范围外

- `assets/images/app_logo*.png`.
- `assets/images/mala/` mascot artwork.
- Android launcher icon, iOS/macOS `AppIcon`, Web icon, Windows ICO, OHOS icon.
- iOS `LaunchImage` and other launch imagery.
- Image file paths and image-only fields in `assets.gen.dart`.
- Theme colour values; the Peacock palette overall.
- Course JSON schema, SQLite table names, content IDs.
- Upstream repo name, historical commits, old release facts.

图标不动，重命名后的 APK/bundle 在开发期仍显示旧视觉资产；发布前由后续视觉资产任务收口。

### 实施原则

1. Baseline before mechanical search-replace.
2. User-visible copy and technical identity land in separate stages so build errors stay localised.
3. Generated files are owned by the generator — never hand-edit them.
4. Upstream / old releases stay named *Varnamala*; we don't rewrite history.
5. Old local configs are read-compatible, with a one-shot migration to the new namespace; old config is not auto-deleted.
6. Each stage lands as its own commit so reverts stay narrow.

### 执行阶段

| # | Stage | Anchor commit message | Key files |
|---|-------|------------------------|-----------|
| 1 | Baseline | (no commit, snapshot only) | `git status --short`; `flutter pub get`/`analyze`/`test`; old-name census |
| 2 | User-visible copy | `feat: update user-facing product copy to Turna` | `lib/l10n/app_strings.dart`, `lib/views/app.dart`, `lib/views/settings/about_varnamala_page.dart`, `lib/views/settings/widgets/settings_about_section.dart`, splash / welcome / share |
| 3 | Dart package & symbols | `refactor: rename Flutter package and Dart symbols to Turna` | `pubspec.yaml`; `package:varnamala/→package:turna/` everywhere; `VarnamalaApp`→`TurnaApp`; `VarnamalaTheme`→`TurnaTheme`; `about_varnamala_page.dart`→`about_turna_page.dart`; rerun `build_runner` |
| 4 | Native identities | `chore: rename native application identities to Turna` | `android/app/build.gradle`, `AndroidManifest.xml`, Kotlin package path; iOS `Info.plist`/`project.pbxproj`; macOS `AppInfo.xcconfig`/`pbxproj`; Windows `CMakeLists.txt`/`main.cpp`/`Runner.rc`; Linux `CMakeLists.txt`/`my_application.cc`; Web `index.html`/`manifest.json`; OHOS `oh-package.json5` + AppScope resources |
| 5 | Editor + local-data compat | `refactor: rename course editor and migrate local settings` | `tool/gui/*`; `QSettings("Turna","CourseEditor")` with read-from-old on first run; `.varnamala`/`.varnamala-gui` → `.turna`/`.turna-gui` (with read-compat); `.varnamala-backup` preserved |
| 6 | Docs | `docs: document Turna rebrand and preserve upstream attribution` | `README.md`, `CLAUDE.md`（已删）, project analysis, course authoring guide, GUI user docs, release/build notes |
| — | Final verification | (no commit, audit only) | `flutter pub get` + `dart format .` + `flutter analyze` + `flutter test`; platform build per §11.2; old-name audit per §11.4 |

### 本地数据迁移

QSettings（`tool/gui`）升级后首次运行的读取顺序：

1. Look up `QSettings("Turna","CourseEditor")`.
2. If empty, read `QSettings("Varnamala","CourseEditor")`.
3. Copy the value into the new `Turna` settings and proceed with the new key from there.
4. Never delete the old `Varnamala` key — leave it for any user who rolls back the binary.

本地目录：`.varnamala` → `.turna`（用户配置目录）；`.varnamala-gui` → `.turna-gui`（编辑器配置目录）；两者迁移方式一致 —— 读旧目录，回退，写穿到新目录，不删除旧目录。`.varnamala-backup` 是课程内部备份格式，**保留**：改名会使既有课程备份与测试夹具失效。

不迁移的协议：course JSON schema 与字段名、SQLite 表名与库结构、既有 course / vocab / lesson ID、Anki 导入格式与学习进度数据结构。

### 关于页的上游署名规则

关于页改写为 *Turna*，但不得谎称出身。措辞模板：

> Turna 是一款本地优先的土耳其语学习应用，基于开源项目 Varnamala 开发。

保留 `github.com/rshrc/Varnamala` 链接、上游作者与社区署名、全部 license 文本。

## 影响与边界

### 有意保留的 `Varnamala` 引用（不是回归）

复核者应把下列命中视为**有意保留**：

- 上游仓库名、链接与社区署名（`README`、`About`、`LICENSE`）。
- `CHANGELOG` / ADR 里的历史条目。
- `tool/gui` 一次性迁移代码（读旧写新，QSettings + 本地目录）：`tool/gui/src/application/settings.py`（`LEGACY_ORG_NAME`、`app_data_dir(legacy_name=…)`、`course_clones_dir(legacy_name=…)`、`migrate_legacy_varnamala_qsettings`）、`tool/gui/src/app.py`（调用点）、`tool/gui/src/backend/credential_store.py`（`_KEYRING_SERVICE_LEGACY = "varnamala.git"` 与旧读取路径）、`tool/gui/src/backend/ai_config_file.py`（`CONFIG_KIND_LEGACY = "varnamala.ai_config"`，双 kind 接受）。
- 课程内部备份逻辑与夹具里的 `.varnamala-backup` 路径（`tool/gui/src/backend/course_adapter.py`、`assets/courses/turkish/.gitignore`、BASELINE 历史文件）。
- 烘入仓库根绝对路径的 Flutter / Hvigor 生成缓存（`ios/Flutter/Generated.xcconfig`、`macos/Flutter/ephemeral/Flutter-Generated.xcconfig`、`windows/flutter/ephemeral/generated_config.cmake`、`ohos/.hvigor/**`）：按目录路径重建，不属于真源。
- 上游物理仓库名 `Varnamalaplus`（`README.md` 的 `git clone` 命令、旧分析文档的 `file:///` slug）：上游目录未改名，URL 与 slug 保持。
- 测试基线历史文件（`test/BASELINE.md`、`tool/gui/tests/BASELINE.md`）：描述改名前的测试结果，只更新「当前现状」一行。

除以上之外，当前产品文案、当前 `package:` 导入、当前平台显示名与当前发布标识必须全部为 `Turna` / `turna` / `me.dsdogs.turna`。

### 验收口径

改名「完成」当且仅当：

- [ ] All user-visible product copy is `Turna`.
- [ ] Dart package is `turna`; no `package:varnamala/` imports remain in committed code.
- [ ] Root widget and brand theme class use `Turna` naming.
- [ ] Android, Apple, Linux, Windows, Web, OHOS identities are unified.
- [ ] Android `applicationId` and Apple `Bundle ID` confirmed as the long-term release values (`me.dsdogs.turna`).
- [ ] Course editor displays as `Turna Course Editor`.
- [ ] Old GUI settings and local directories have read-compat or one-shot migration in place.
- [ ] Upstream Varnamala attribution, links, and historical records preserved.
- [ ] No images, icons, mascot files were modified.
- [ ] Static checks, unit tests, and available platform builds pass.
- [ ] Every remaining `Varnamala` hit has a documented "intentional" reason under 「有意保留的 `Varnamala` 引用」.

### 后续（不在本 ADR 范围）

单独的视觉资产批次负责：Turna logo、新吉祥物与姿势组、各平台应用图标、启动图与商店物料、重新评估 Peacock 调色板是否保留。视觉任务必须先于任何公开发布。
