# 10. 依赖关系与第三方库

> 路径：[`pubspec.yaml`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/pubspec.yaml)、[`pubspec.lock`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/pubspec.lock)

---

## 10.1 Dart SDK 与 Flutter

```yaml
environment:
  sdk: ">=3.2.3 <4.0.0"
```

依赖 Dart 3.2.3+（`sealed class`、`switch` 表达式、`record` 类型）。Flutter SDK 随 Dart。

---

## 10.2 运行时依赖

### 10.2.1 核心框架

| 包 | 版本 | 用途 |
|---|---|---|
| `flutter` | SDK | Flutter 框架 |
| `cupertino_icons` | ^1.0.2 | iOS 风格图标 |

### 10.2.2 状态管理与 DI

| 包 | 版本 | 用途 |
|---|---|---|
| `provider` | ^6.1.2 | ChangeNotifier 注入 |
| `get_it` | ^9.2.1 | 服务定位器 |
| `injectable` | ^3.0.0 | DI 代码生成注解 |

### 10.2.3 路由

| 包 | 版本 | 用途 |
|---|---|---|
| `auto_route` | ^11.1.0 | 声明式路由 + Guards |

### 10.2.4 数据模型与序列化

| 包 | 版本 | 用途 |
|---|---|---|
| `freezed_annotation` | ^3.1.0 | `@freezed` 注解 |
| `json_annotation` | ^4.9.0 | `@JsonSerializable` 注解 |

### 10.2.5 持久化

| 包 | 版本 | 用途 |
|---|---|---|
| `drift` | ^2.22.1 | 类型安全的 SQLite ORM |
| `sqlite3_flutter_libs` | ^0.5.24 | 跨平台 sqlite3 native lib |
| `path_provider` | ^2.1.4 | 获取应用文档目录 |
| `path` | ^1.9.0 | 路径处理 |
| `streaming_shared_preferences` | ^2.0.0 | 响应式 SharedPreferences |
| `crypto` | ^3.0.7 | SHA-256（cache key 等） |

### 10.2.6 SRS 算法

| 包 | 版本 | 用途 |
|---|---|---|
| `fsrs` | ^2.0.1 | FSRS 调度器（生产默认） |

### 10.2.7 UI / 体验

| 包 | 版本 | 用途 |
|---|---|---|
| `google_fonts` | ^8.1.0 | Google Fonts（含 Lexend for Dyslexia） |
| `fl_chart` | ^0.69.0 | 图表（学习统计 / 记忆曲线） |
| `intl` | ^0.20.2 | 国际化 / 日期格式化 |
| `logger` | ^2.4.0 | 日志 |

### 10.2.8 音频 / TTS

| 包 | 版本 | 用途 |
|---|---|---|
| `flutter_tts` | ^4.0.2 | TTS（语言代码 `'tr'`） |
| `audioplayers` | ^6.0.0 | 预录 MP3 播放 |

### 10.2.9 通知

| 包 | 版本 | 用途 |
|---|---|---|
| `flutter_local_notifications` | ^19.5.0 | 本地每日提醒 |

### 10.2.10 文件 / 网络 / 系统

| 包 | 版本 | 用途 |
|---|---|---|
| `http` | ^1.2.0 | AI HTTP 调用 |
| `file_picker` | ^8.1.4 | 教材 / Anki 导入文件选择 |
| `share_plus` | ^10.0.0 | 分享学习进度 |
| `url_launcher` | ^6.3.2 | 外部链接 |
| `package_info_plus` | ^9.0.1 | 包信息 |

---

## 10.3 开发依赖

| 包 | 版本 | 用途 |
|---|---|---|
| `build_runner` | ^2.4.12 | 代码生成 runner |
| `freezed` | ^3.2.5 | freezed 代码生成器 |
| `json_serializable` | ^6.8.0 | JSON 序列化生成器 |
| `auto_route_generator` | ^10.5.0 | auto_route 生成器 |
| `injectable_generator` | ^3.0.2 | injectable 生成器 |
| `drift_dev` | ^2.22.1 | drift schema 生成器 |
| `flutter_gen` | ^5.15.0 | 资源引用生成器 |
| `flutter_gen_runner` | ^5.15.0 | flutter_gen runner |
| `flutter_launcher_icons` | ^0.14.1 | 多平台 launcher 图标 |
| `flutter_lints` | ^6.0.0 | Lint 规则 |
| `flutter_test` | SDK | 单元测试 |
| `import_sorter` | ^4.6.0 | 自动 import 排序 |
| `pubspec_dependency_sorter` | ^1.0.5 | pubspec 依赖排序 |
| `shared_preferences` | ^2.2.3 | 测试 fallback |
| `sqlite3` | ^2.4.0 | 测试 sqlite3 |

---

## 10.4 OHos（鸿蒙）适配（dependency_overrides）

为支持鸿蒙平台（OpenHarmony），`pubspec.yaml` 通过 `dependency_overrides` 从开源仓库拉取平台实现：

```yaml
dependency_overrides:
  # OHos 平台实现
  shared_preferences:
    git:
      url: https://gitcode.com/openharmony-tpc/flutter_packages.git
      path: packages/shared_preferences/shared_preferences
      ref: br_shared_preferences-v2.5.3_ohos
  path_provider:
    git:
      url: https://gitcode.com/openharmony-tpc/flutter_packages.git
      path: packages/path_provider/path_provider
      ref: br_path_provider-v2.1.5_ohos
  url_launcher:
    git:
      url: https://gitcode.com/openharmony-tpc/flutter_packages.git
      path: packages/url_launcher/url_launcher
      ref: br_url_launcher-v6.3.2_ohos
  package_info_plus:
    git:
      url: https://gitcode.com/openharmony-sig/flutter_plus_plugins.git
      path: packages/package_info_plus/package_info_plus
  share_plus:
    git:
      url: https://gitcode.com/openharmony-sig/flutter_plus_plugins.git
      path: packages/share_plus/share_plus
  file_picker:
    git:
      url: https://gitcode.com/openharmony-sig/fluttertpc_file_picker.git
  flutter_local_notifications:
    git:
      url: https://gitcode.com/openharmony-sig/fluttertpc_flutter_local_notifications.git
      path: flutter_local_notifications
  # win32: 3.x+ uses UnmodifiableUint8ListView, which OHos Flutter SDK's
  # Dart 3.6.2 runtime is missing from dart:typed_data. Pin to 2.7.0.
  win32: 2.7.0
```

**OHos 目录**：[`ohos/`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/ohos/) — 鸿蒙平台标准结构（`AppScope/`、`entry/`、`hvigor/`、`oh-package.json5`）。

---

## 10.5 关键依赖图

```
                  ┌──────────────────┐
                  │  flutter (SDK)   │
                  └──────────────────┘
                          │
   ┌──────────────┬───────┼────────┬──────────────┐
   │              │       │        │              │
┌──▼──┐       ┌───▼─┐  ┌──▼──┐ ┌──▼────┐    ┌────▼─────┐
│ pro │       │ drft│  │ frz │ │ auto  │    │ flutter  │
│ vdr │       │     │  │     │ │ route │    │   _tts   │
└─────┘       └─────┘  └─────┘ └───────┘    └──────────┘
                                              │
                                  ┌───────────┴────────┐
                                  │                    │
                            ┌─────▼──────┐     ┌───────▼──────┐
                            │ flutter_   │     │ flutter_local│
                            │ local_     │     │ notifications│
                            │ notif.     │     └──────────────┘
                            └────────────┘

   ┌────────────────┐       ┌──────────────────┐
   │ streaming_     │       │ get_it +         │
   │ shared_prefs   │       │ injectable       │
   └────────────────┘       └──────────────────┘

   ┌────────────────┐       ┌──────────────────┐
   │ fsrs           │       │ google_fonts     │
   │ (SRS 算法)     │       │ fl_chart         │
   └────────────────┘       └──────────────────┘
```

---

## 10.6 第三方库分类速查

### 10.6.1 Flutter 官方

`flutter` (SDK), `cupertino_icons`

### 10.6.2 持久化

- `drift` / `sqlite3_flutter_libs` / `path_provider` / `path` — SQLite
- `streaming_shared_preferences` — KV
- `crypto` — SHA-256

### 10.6.3 状态管理

- `provider`
- `get_it` / `injectable` — DI

### 10.6.4 路由

- `auto_route`

### 10.6.5 模型

- `freezed_annotation` / `freezed`
- `json_annotation` / `json_serializable`

### 10.6.6 UI

- `google_fonts` / `fl_chart` / `intl` / `logger`

### 10.6.7 多媒体

- `flutter_tts` / `audioplayers`

### 10.6.8 系统集成

- `flutter_local_notifications`
- `http` / `file_picker` / `share_plus` / `url_launcher` / `package_info_plus`

### 10.6.9 算法

- `fsrs`

---

## 10.7 关键 ADR（架构决策记录）

| ADR | 主题 |
|---|---|
| 0001 | Swahili TTS 决策（已由 0020 取代） |
| 0007 | Repository 接口（Phase 21） |
| 0009–0018 | future4 框架完成轮 |
| 0012 | StudyLog 追加策略（recent + main 双 blob） |
| 0013 | SrsQueueProvider 基类抽取 |
| 0015 | GameProvider Facade |
| 0018 | future4 框架完成与内容移交 |
| 0020 | Swahili → Turkish 迁移 |
| 0021 | SrsScheduler 抽象 |
| 0028 | FSRS 引擎（生产默认） |
| 0029 | 同日 relearn 阶梯 |

完整 ADR 见 [`docs/decisions/`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/docs/decisions/)。

---

## 10.8 关键模块依赖关系（粗略）

```
lib/views/* → lib/application/* → lib/domain/* → lib/data/* (实现 domain/repositories)
                              ↓
                          lib/courses/*
                              ↓
                          lib/core/*
                              ↓
                          lib/service/* + lib/utils/*
                              ↓
                          lib/di/* (注册到 GetIt)
                              ↓
                          lib/routing/* (生成 routes)
```

依赖方向单向向下，UI 不直接接触 data/，data/ 不感知 UI。

---

## 10.9 平台特定配置

### 10.9.1 Android

[`android/`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/android/) — 标准 Flutter Android 项目结构。TTS 优先选 Google TTS。

### 10.9.2 iOS

[`ios/`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/ios/) — `Info.plist` 配置权限（如 `NSMicrophoneUsageDescription` 等可能需要的权限）。

### 10.9.3 Web

[`web/`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/web/) — `index.html`、`manifest.json`、PWA icons。

### 10.9.4 Windows / macOS / Linux

| 平台 | 入口 |
|---|---|
| Windows | [`windows/runner/main.cpp`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/windows/runner/main.cpp) + `flutter_window.cpp` |
| macOS | [`macos/Runner/AppDelegate.swift`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/macos/Runner/AppDelegate.swift) |
| Linux | [`linux/main.cc`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/linux/main.cc) + `my_application.cc` |

### 10.9.5 OHos

[`ohos/`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/ohos/) — 鸿蒙平台。`hvigor` + `AppScope` + `entry`。通过 `dependency_overrides` 适配插件。