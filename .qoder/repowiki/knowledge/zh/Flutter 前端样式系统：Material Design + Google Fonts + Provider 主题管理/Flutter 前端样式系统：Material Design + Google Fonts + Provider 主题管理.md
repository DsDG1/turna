---
kind: frontend_style
name: Flutter 前端样式系统：Material Design + Google Fonts + Provider 主题管理
category: frontend_style
scope:
    - '**'
source_files:
    - pubspec.yaml
    - lib/main.dart
---

该 Flutter 项目采用标准的 Material Design 风格，通过以下方式进行前端样式管理：

**样式系统与框架：**
- 基于 Flutter 的 Material Design 组件库（uses-material-design: true）
- 使用 google_fonts 包进行字体管理
- 通过 Provider 状态管理模式管理 UI 主题和样式
- 使用 cupertino_icons 提供 iOS 风格的图标资源

**主题配置：**
- 在 pubspec.yaml 中配置了 Web 平台的主题色（theme_color: "#1F727E"）
- 应用背景色设置为白色（background_color: "#FFFFFF"）
- 使用 flutter_launcher_icons 统一管理各平台的启动图标

**资源管理：**
- 静态资源通过 assets 目录组织，包括图片、音频和课程数据
- 使用 flutter_gen 工具自动生成资源访问代码
- 支持多平台图标生成（Android、iOS、Web、Windows、macOS）

**依赖注入与架构：**
- 使用 get_it + injectable 进行依赖注入
- 遵循 Clean Architecture 分层模式
- 通过 Provider 管理 UI 状态变化

**开发工具：**
- 使用 flutter_lints 进行代码规范检查
- 集成 import_sorter 自动排序导入语句
- 使用 build_runner 进行代码生成

该项目主要依赖 Flutter 内置的 Material Design 组件，没有发现自定义的主题文件或复杂的样式系统，属于较为简洁的样式实现方式。