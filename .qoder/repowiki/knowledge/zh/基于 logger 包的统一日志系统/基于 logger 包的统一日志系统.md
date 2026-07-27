---
kind: logging_system
name: 基于 logger 包的统一日志系统
category: logging_system
scope:
    - '**'
source_files:
    - lib/core/logger.dart
    - lib/main.dart
---

本项目使用 `package:logger`（第三方 Dart 日志库）作为统一的日志框架，通过 `lib/core/logger.dart` 暴露全局单例 `logger`，供全应用各层（application、data、service、views 等）直接引用。

**核心实现与初始化**
- 日志实例在 `lib/core/logger.dart` 中创建，配置了 `PrettyPrinter`（methodCount=0、errorMethodCount=8、lineLength=80、noBoxingByDefault=true），输出格式简洁可读。
- 通过自定义 `_ReleaseAwareFilter` 实现按构建模式过滤：debug/test 下所有级别均输出；release 模式下仅输出 warning 及以上级别，避免生产环境日志泛滥。
- 应用入口 `lib/main.dart` 在 `main()` 启动时安装全局错误处理器（`FlutterError.onError` 和 `PlatformDispatcher.instance.onError`），将未捕获的框架错误与平台错误统一记录到该 logger，确保异常可观测。

**日志级别与使用约定**
- 信息类：`logger.i(...)` 用于关键流程跟踪（如 AI 配置加载、课程 Provider 首次加载提示）。
- 警告类：`logger.w(...)` 广泛用于网络错误、解析失败、降级回退等非致命异常场景。
- 错误类：`logger.e(..., error: e, stackTrace: st)` 用于需要附带异常对象与堆栈的关键错误，便于问题定位。
- 未发现 debug/v 级别的显式使用，说明开发者主要依赖 i/w/e 三级。

**架构与约束**
- 这是一个离线应用，注释明确声明“logs go to the console (and the platform log) only, never to a remote backend”，即日志仅输出到控制台/平台日志，不上传至远程后端。
- 所有模块通过 `import 'package:varnamala/core/logger.dart'` 引入同一个全局 logger 实例，保证日志输出源一致。
- 未见独立的日志配置开关或动态调整机制，日志行为由构建模式（kReleaseMode）决定。

**关键文件**
- `lib/core/logger.dart`：日志器定义与过滤器
- `lib/main.dart`：全局错误处理器注册，确保异常被 logger 捕获
- 各 application 层 Provider/Service 文件中对 logger 的调用点（AI、Anki、Course、StudyLog 等模块）