---
kind: dependency_management
name: 多语言依赖管理体系（Flutter/Dart、iOS CocoaPods、Android Gradle、Python）
category: dependency_management
scope:
    - '**'
source_files:
    - pubspec.yaml
    - pubspec.lock
    - ios/Podfile
    - ios/Podfile.lock
    - android/app/build.gradle
    - tool/gui/pyproject.toml
    - tool/gui/.venv/pyvenv.cfg
---

本项目采用多工具链并行的依赖管理策略，针对不同平台和子项目分别使用各自生态的标准包管理器：

**1. Flutter/Dart 主应用依赖**
- 声明文件：`pubspec.yaml`，通过 `dependencies` 和 `dev_dependencies` 两段式管理运行时与开发期依赖
- 锁定机制：`pubspec.lock` 记录精确版本与 SHA256 校验值，所有依赖来源均为 `https://pub.dev` 官方源，未配置私有仓库或镜像
- SDK 约束：`environment.sdk: ">=3.2.3 <4.0.0"` 限定 Dart SDK 范围
- 关键依赖包括：`drift`（数据库）、`get_it`+`injectable`（依赖注入）、`provider`（状态管理）、`audioplayers`（音频）、`flutter_tts`（语音合成）等
- 构建时代码生成：`build_runner` + `freezed`/`json_serializable`/`auto_route_generator`/`drift_dev` 等 dev 依赖配合注解实现编译时代码生成
- 资源生成：`flutter_gen` 自动生成 assets 访问代码

**2. iOS 原生依赖（CocoaPods）**
- 声明文件：`ios/Podfile`，通过 `flutter_install_all_ios_pods` 自动安装 Flutter 插件所需的 Pods
- 锁定文件：`ios/Podfile.lock` 记录完整依赖树（包含 abseil、sqlite3 等底层库），版本精确到具体 release
- 优化配置：`ENV['COCOAPODS_DISABLE_STATS'] = 'true'` 禁用统计以提升构建速度
- 模块化：启用 `use_frameworks!` 和 `use_modular_headers!` 提升编译性能

**3. Android 原生依赖（Gradle）**
- 构建配置：`android/app/build.gradle` 中通过 `dependencies` 块声明 Android 层依赖（如 `desugar_jdk_libs`）
- NDK/SDK 版本：由 Flutter 插件统一管理（`flutter.ndkVersion`、`flutter.minSdkVersion`）
- 混淆与压缩：R8 开启 `minifyEnabled true` 和 `shrinkResources true`，ProGuard 规则在 `proguard-rules.pro` 中维护
- 签名配置：支持可选的 `key.properties` 文件进行 release 签名，不存在时回退到 debug 签名

**4. Python GUI 工具依赖**
- 声明文件：`tool/gui/pyproject.toml`，使用 PEP 621 标准格式定义依赖（PySide6、PyPDF2、python-docx、keyring）
- 虚拟环境：`tool/gui/.venv/` 隔离 Python 3.12 运行环境，`include-system-site-packages = false` 确保隔离性
- 构建系统：基于 `setuptools>=61`，packages 指向 `src` 目录

**5. 平台特定依赖管理约定**
- 各平台 Runner 工程（macOS/Linux/Windows）均遵循 Flutter 官方模板结构，依赖由 Flutter 插件自动处理
- Android 使用 Gradle Wrapper（`gradlew`）保证构建工具一致性
- 未使用 vendoring 策略，所有第三方库均通过网络下载
- 未发现私有仓库配置（无 `.npmrc`、`~/.gradle/gradle.properties` 中的私有源设置）

**6. 依赖更新与维护**
- Flutter 依赖通过 `flutter pub upgrade` 管理，锁文件需提交至版本控制
- iOS 依赖通过 `pod install` 更新，`Podfile.lock` 需提交
- Python 依赖可通过 `pip freeze > requirements.txt` 导出锁定版本（当前使用 pyproject.toml 而非 requirements.txt）