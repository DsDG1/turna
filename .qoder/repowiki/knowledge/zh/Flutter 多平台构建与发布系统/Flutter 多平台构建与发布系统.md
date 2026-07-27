---
kind: build_system
name: Flutter 多平台构建与发布系统
category: build_system
scope:
    - '**'
source_files:
    - Makefile
    - pubspec.yaml
    - build.yaml
    - tool/build_release.py
    - tool/gui/build_gui.py
    - android/build.gradle
    - android/app/build.gradle
    - .github/workflows/flutter_ci.yml
    - .github/workflows/course_validation.yml
    - tool/course_cli.py
---

## 构建系统与工具链概述

Varnamala 项目采用 Flutter 作为核心跨平台框架，通过 Makefile 统一编排构建流程，结合 Python 脚本实现多平台产物打包、内容校验和测试自动化。构建系统覆盖 Android、iOS、Web、Linux、macOS、Windows 六大平台，并配套独立的 GUI 工具链。

## 核心构建文件与职责

**顶层构建入口**：`Makefile` 提供统一的命令接口，包括 `gen`（代码生成）、`analyze`（静态分析）、`test`（Dart/Python/GUI 测试）、`build-release`（发布构建）等目标。

**Flutter 依赖管理**：`pubspec.yaml` 声明应用依赖，版本锁定在 Dart SDK >=3.2.3 <4.0.0，使用 `flutter_gen` 处理资源，`flutter_launcher_icons` 生成各平台图标。

**代码生成配置**：`build.yaml` 配置 freezed、json_serializable、auto_route_generator、drift_dev、flutter_gen 等代码生成器的行为选项。

## 多平台原生构建配置

**Android 构建**：`android/build.gradle` 和 `android/app/build.gradle` 配置 AGP 8.x、Kotlin 2.2.20、编译目标 SDK 36，支持 R8 混淆和资源压缩，可选 keystore 签名。

**iOS/macOS 构建**：通过 Xcode 项目和 CocoaPods 管理依赖，Podfile 定义 iOS 特定配置。

**桌面平台**：Linux/macOS/Windows 使用 CMake + 原生宿主，Flutter 引擎嵌入到各平台窗口系统中。

## 发布构建流程

**主构建脚本**：`tool/build_release.py` 是核心发布工具，按顺序执行：
1. `flutter pub get` 获取依赖
2. `build_runner build` 生成代码
3. 可选的内容验证（course_cli validate/lint）
4. 构建 APK/AAB/Web 产物
5. 导出内容清单文档

**GUI 工具构建**：`tool/gui/build_gui.py` 使用 PyInstaller 将 Python GUI 工具打包为独立可执行文件。

## CI/CD 流水线

**Flutter CI** (`.github/workflows/flutter_ci.yml`)：
- 触发条件：lib/test/tool/pubspec.yaml 等代码变更
- 步骤：安装依赖 → 代码生成 → 静态分析 → 运行测试 → 发布冒烟构建
- 跳过 Web 构建和内容验证以加速 CI

**课程验证 CI** (`.github/workflows/course_validation.yml`)：
- 触发条件：assets/courses/** 或 tool/course_cli.py 变更
- 步骤：Python 3.12 环境 → JSON 验证 → 内容 Lint → CLI 测试

## 测试分层策略

**Dart 测试**：`flutter test` 运行单元测试和 Golden 截图测试
**Python 工具测试**：`python3 -m unittest discover -s test -p "*_test.py"`
**GUI 测试分层**：
- L0 Gate：体验门禁测试（约 27 项检查）
- L1 Fast：纯后端无 UI 测试
- L2 Full：完整 GUI 测试套件（BASELINE 基准）

## 构建约定与约束

**版本管理**：版本号通过 `--version` 参数传入，产物命名格式 `varnamala-v{version}-release.{apk|aab}`
**输出目录**：默认 `build/releases/<version>/`，可通过 `--output-dir` 自定义
**增量构建**：build_runner 使用 `--delete-conflicting-outputs` 确保生成文件一致性
**离线优先**：所有课程数据存储在 assets/courses/ 中，应用完全离线运行
**签名策略**：Android release 构建支持可选 keystore，缺失时回退到 debug 签名

## 关键设计决策

- **单一入口点**：Makefile 统一所有构建操作，避免分散的 shell 脚本
- **Python 工具链**：复杂逻辑用 Python 实现，便于维护和测试
- **分层测试**：GUI 测试按复杂度分层，CI 默认只运行快速测试
- **内容即代码**：课程数据通过 Python CLI 严格验证，保证数据结构一致性
- **跨平台一致**：Flutter 核心代码 + 原生宿主适配的架构模式