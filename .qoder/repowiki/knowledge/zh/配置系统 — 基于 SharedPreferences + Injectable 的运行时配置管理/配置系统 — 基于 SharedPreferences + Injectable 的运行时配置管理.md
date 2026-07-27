---
kind: configuration_system
name: 配置系统 — 基于 SharedPreferences + Injectable 的运行时配置管理
category: configuration_system
scope:
    - '**'
source_files:
    - lib/service/locator.dart
    - lib/application/settings_provider.dart
    - lib/di/injection.dart
    - lib/di/injection.config.dart
    - lib/main.dart
    - lib/application/ai/ai_api_config.dart
---

## 1. 使用的系统与框架
- **持久化存储**：`streaming_shared_preferences`（配合 `shared_preferences`）作为用户设置与本地状态的唯一持久化后端，提供响应式流式读取。
- **依赖注入**：`get_it` + `injectable`（代码生成 `injection.config.dart`）负责服务注册、生命周期管理与跨层依赖装配。
- **平台/环境区分**：通过 Flutter 的 `kIsWeb`、`defaultTargetPlatform`、`TargetPlatform.*` 进行平台分支；未使用 `.env` / `dotenv`，无外部环境变量加载机制。
- **构建期配置**：`pubspec.yaml` 声明依赖与 assets；`build.yaml` 仅用于 `flutter_gen` 等代码生成工具，不承载运行时配置。

## 2. 核心文件与包
- `lib/service/locator.dart`：定义 `AppPrefs` 封装、`PrefsConstants`、`LocalStateKeys` 常量集，以及 `setupLocator()` 初始化 DI 容器、打开并播种课程数据库。
- `lib/application/settings_provider.dart`：`SettingsProvider` 暴露可观察的用户设置（音效、触觉反馈、TTS 语速、每日提醒时间等），内部通过 `AppPrefs` 读写。
- `lib/di/injection.dart` 与 `lib/di/injection.config.dart`：`@InjectableInit` 触发 injectable 代码生成，集中注册所有 Provider/Service 为 `lazySingleton`。
- `lib/main.dart`：应用入口，先安装全局错误处理器 → 调用 `configureDependencies()` → `setupLocator()` → `runApp` → 在首帧后异步预加载词汇/语法/表达数据与课程。
- `lib/application/ai/ai_api_config.dart`：AI API 配置（baseUrl、apiKey、model、reasoning 开关），明确标注“仅内存、不持久化”，由 `AiCourseProvider` 持有并在会话内变更。

## 3. 架构与设计约定
- **分层清晰**：`service/locator.dart` 提供底层 `AppPrefs` 抽象；`application/*_provider.dart` 包装业务级设置并提供 `ChangeNotifier` 给 UI 订阅；`di/injection.*` 统一装配。
- **键值命名规范**：所有持久化 key 集中在 `LocalStateKeys`（如 `settings.soundEffects`、`progress.completedLessonIds`、`srs.state` 等），避免散落的魔法字符串。
- **默认值策略**：`AppPrefs` 构造时即赋予默认值（如 `currentLanguage = "turkish"`、`soundEffects = true`），保证冷启动可用。
- **不可变配置对象**：`AiApiConfig` 使用 `const` 构造函数 + `copyWith` 实现不可变更新，且 `isComplete` 校验必填字段。
- **平台适配**：TTS、数据库等能力通过 `kIsWeb` / `defaultTargetPlatform` 判断是否启用或跳过，web 端显式抛出 `UnsupportedError`。
- **日志安全**：`AppPrefs.printBefore` 在 debug 模式下仅记录 key，完整 value 仅在 `veryVerbose` 开关下输出，防止敏感信息泄露。

## 4. 约定与约束
- **所有用户设置必须通过 `SettingsProvider` 修改**，并由其调用 `AppPrefs` 写入，确保 UI 自动刷新。
- **新增持久化字段需同时更新**：`LocalStateKeys` 常量、`SettingsProvider` getter/setter、以及对应的 `_load()` 读取逻辑。
- **AI 配置不得持久化**：`AiApiConfig` 明确注释“never persisted”，仅存在于 Provider 内存中，退出即丢弃。
- **DI 容器必须在首帧前完成初始化**：`main.dart` 在 `runApp` 之前调用 `configureDependencies()` 和 `setupLocator()`，保证 `MultiProvider` 创建 ThemeProvider 时依赖已就绪。
- **Web 平台限制**：`CourseDatabase`（NativeDatabase/sqlite3）不支持 web，启动时会抛异常；相关功能需在 web 端另行处理。
- **无环境变量/配置文件机制**：项目未使用 `.env`、`Environment.from*`、`package:config` 等方案，所有配置均通过 Dart 代码中的默认值与 `SharedPreferences` 管理。