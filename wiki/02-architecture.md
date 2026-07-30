# 02. 整体架构

## 2.1 分层架构总览

Varnamala 采用 **Clean Architecture**，自下而上分为四层：

```
┌─────────────────────────────────────────────────┐
│  views/                # UI 层（Flutter Widgets） │
├─────────────────────────────────────────────────┤
│  application/          # 状态管理（Providers）    │
├─────────────────────────────────────────────────┤
│  domain/               # 领域模型 + Repository 接口 │
├─────────────────────────────────────────────────┤
│  data/                 # 数据层（Drift + DAO）     │
├─────────────────────────────────────────────────┤
│  courses/              # 资源加载器 + 校验器       │
├─────────────────────────────────────────────────┤
│  core/                 # 纯函数 + 工具 + 算法      │
├─────────────────────────────────────────────────┤
│  service/              # 横切服务（TTS / 通知）    │
├─────────────────────────────────────────────────┤
│  di/                   # 依赖注入（GetIt）         │
├─────────────────────────────────────────────────┤
│  routing/              # 路由 + Guards             │
└─────────────────────────────────────────────────┘
```

依赖方向：**上层依赖下层，下层不感知上层**。Domain 层只定义接口，不知道 Drift / SQLite 的存在；Data 层实现 Domain 接口，向上提供数据。

## 2.2 模块职责矩阵

| 目录 | 职责 | 关键文件 |
|---|---|---|
| `lib/main.dart` | 入口；安装全局错误处理器；初始化 DI；first-frame 后异步加载课程 | [`main.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/main.dart) |
| `lib/views/app.dart` | 根 Widget；MultiProvider 注入；Theme/Accessibility 解析 | [`app.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/views/app.dart) |
| `lib/application/` | 全部 ChangeNotifier 状态管理；SRS / Mistake / Stats / Settings | 详见 [04-application-layer.md](./04-application-layer.md) |
| `lib/domain/` | Freezed 模型（Section/Unit/Lesson/Stage/Interaction 等）+ Repository 接口 | 详见 [03-domain-layer.md](./03-domain-layer.md) |
| `lib/data/` | Drift DB Schema、DAO、Repository 实现、Seeder | 详见 [05-data-layer.md](./05-data-layer.md) |
| `lib/courses/` | 从 JSON 加载课程、规范化、校验；按语种分发 | [`courses/course_loader.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/courses/course_loader.dart) |
| `lib/core/` | 纯函数、SM-2/FSRS 算法、调度器、Logger、扩展 | 详见 [09-core-and-utils.md](./09-core-and-utils.md) |
| `lib/service/` | `AppPrefs`（StreamingSharedPreferences）、`TtsAvailabilityChecker`、`LocalReminderService`、导出服务 | [`service/locator.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/service/locator.dart) |
| `lib/di/` | GetIt 单例注册 + Injectable 代码生成 | [`di/injection.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/di/injection.dart) |
| `lib/routing/` | Auto Route 配置 + `CourseReadyGuard` | [`routing/routing.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/routing/routing.dart) |
| `lib/views/` | 所有 UI 页面与组件（按 feature 分目录） | 详见 [06-views-layer.md](./06-views-layer.md) |
| `lib/gen/` | `flutter_gen` 生成的资源引用代码 | [`gen/assets.gen.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/gen/assets.gen.dart) |

## 2.3 关键设计模式

### 2.3.1 Provider + ChangeNotifier

所有应用状态都封装在 `ChangeNotifier` 子类中，通过 `provider` 包注入到 widget 树：

```dart
// 注入：lib/application/providers.dart
final providers = [
  ChangeNotifierProvider<CourseProvider>(create: (_) => getIt<CourseProvider>()),
  ChangeNotifierProvider<SrsProvider>(create: (_) => getIt<SrsProvider>()),
  ...
];

// 消费：UI 层
final course = context.watch<CourseProvider>().selectedSection;
final dueCount = context.select<SrsProvider, int>((p) => p.dueCount);
```

`@lazySingleton` 标注确保 GetIt 与 Provider 使用同一实例，避免状态分裂。

### 2.3.2 GetIt + Injectable 依赖注入

```dart
// lib/di/injection.dart
@InjectableInit(initializerName: 'init', preferRelativeImports: true, asExtension: true)
void configureDependencies() => getIt.init();
```

生成的 `injection.config.dart` 注册所有 `@injectable` / `@lazySingleton` 类。常见模块：

- `audio_module.dart`：TTS / 音频相关
- `renderer_module.dart`：Interaction 渲染器（每种题型一个 Renderer）

### 2.3.3 Auto Route

```dart
// lib/routing/routing.dart
@AutoRouterConfig(replaceInRouteName: 'Page,Route')
class AppRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: SplashRoute.page, initial: true),
    AutoRoute(page: HomeRoute.page, guards: [_courseReadyGuard]),
    AutoRoute(page: NewLessonRoute.page),
    ...
  ];
}
```

- `CourseReadyGuard`：当 DB 还未 seed 时重定向到 splash 页
- `replaceInRouteName: 'Page,Route'`：自动将 `NewLessonPage` 转换为路由名 `NewLessonRoute`

### 2.3.4 Freezed 不可变模型 + JSON 序列化

所有领域模型使用 `@freezed` 注解，编译期生成不可变数据类 + `fromJson`/`toJson`：

```dart
@freezed
abstract class Lesson with _$Lesson {
  const factory Lesson({
    required String id,
    required String name,
    required LessonContent content,
  }) = _Lesson;
  factory Lesson.fromJson(Map<String, dynamic> json) => _$LessonFromJson(json);
}
```

对于 sealed union（如 `Interaction`），使用 `@Freezed(fromJson: true, toJson: true)` 以允许 `runtimeType` 区分变体。

### 2.3.5 Repository 接口 + 实现

`domain/repositories/` 定义接口，`data/` 实现：

```dart
// Domain 接口
abstract class ICourseRepository {
  Future<List<Section>> sectionShells();
  Future<Lesson?> lessonById(String id);
}

// Data 实现
@LazySingleton(as: ICourseRepository)
class CourseRepository implements ICourseRepository {
  final db.CourseDatabase database;
  // ...
}
```

### 2.3.6 DB 作为派生缓存（Source-of-Truth = JSON）

课程 JSON 是唯一真理源，Drift DB 只是为了：
1. **快速加载**（避免每次启动反序列化全部 JSON）
2. **结构化查询**（按 id 查找、按前置依赖排序）
3. **Anki 导入合并**（用户导入的 deck 与内置课程并存）

`DatabaseSeeder` 在首次启动或 `index.json` version 变化时从 bundle JSON reseed。

## 2.4 应用初始化流程

```
┌──────────────────────────────────────────────────────────────┐
│ main()                                                        │
│  ├─ _installGlobalErrorHandlers()  // FlutterError.onError     │
│  ├─ WidgetsFlutterBinding.ensureInitialized()                 │
│  ├─ configureDependencies()         // GetIt.init()            │
│  ├─ await setupLocator()           // AppPrefs 异步初始化      │
│  └─ runApp(VarnamalaApp)           // 第一帧立即渲染           │
│       └─ MaterialApp.router                                      │
│           └─ SplashRoute (initial)                              │
└──────────────────────────────────────────────────────────────┘
            │
            ▼  （PostFrameCallback，第一帧后异步执行）
┌──────────────────────────────────────────────────────────────┐
│ loadVocabulary() / loadGrammarPoints() / loadExpressions()   │
│   → 填充同步查找表（CourseLookup）                            │
│ getIt<SrsProvider>().ensureLoaded()                          │
│   → SQLite → 内存缓存；运行 v7 schema 迁移                   │
│ getIt<GrammarReviewProvider>().ensureLoaded()                 │
│ getIt<CourseProvider>().load()                                │
│   → sectionShells() + preload first section                  │
│ TtsAvailabilityChecker.configureSystemEngine()                │
│   → Android 优先选 Google TTS                                 │
│ LocalReminderService.applyFromSettings()                      │
└──────────────────────────────────────────────────────────────┘
            │
            ▼  （CourseReadyGuard 检测到 shells 已加载，放行 HomePage）
┌──────────────────────────────────────────────────────────────┐
│ HomePage（底部导航：Learn / Play / Profile / Settings / AI）   │
└──────────────────────────────────────────────────────────────┘
```

**关键设计**：课程加载是**异步后台**进行的，避免阻塞 `runApp`。`CourseTree` 自己渲染 loading indicator 直到 shells 到达。`CourseProvider.load()` 幂等，可被多次调用。

## 2.5 数据流模式

### 2.5.1 用户完成一道题

```
InteractionRenderer (UI)
  ↓ 用户选择答案
LessonViewModel (application) ←─ LocalViewModel pattern
  ↓ onAnswer()
SrsProvider.registerWord() + reviewWord() (SRS)
  ↓ 写入 srs_states 表
Drift SrsStateDao ←─ SQLite
  ↓ notifyListeners()
所有监听 dueCount 的 widget rebuild
```

### 2.5.2 课程加载

```
CourseProvider.load()  (触发)
  ↓
CourseRepository.sectionShells()  (ICourseRepository)
  ↓
Drift: SELECT * FROM sections ORDER BY sort_order
  ↓
[Section shells]  → 注入 _sections
  ↓ notifyListeners()
CourseTree rebuilds
```

## 2.6 平台适配

### 2.6.1 多平台入口

每个平台都有独立的 `main` 函数：

| 平台 | 入口 | 说明 |
|---|---|---|
| Android | `android/app/src/main/AndroidManifest.xml` | 通过 Flutter 标准 |
| iOS | `ios/Runner/AppDelegate.swift` | 通过 Flutter 标准 |
| Windows | `windows/runner/main.cpp` + `flutter_window.cpp` | Win32 窗口 |
| macOS | `macos/Runner/AppDelegate.swift` | |
| Linux | `linux/main.cc` + `my_application.cc` | GTK |
| Web | `web/index.html` + `web/manifest.json` | |
| OHos（鸿蒙） | `ohos/entry/src/main/module.json5` | 通过 dependency_overrides |

### 2.6.2 OHos（鸿蒙）适配

`pubspec.yaml` 通过 `dependency_overrides` 从 `openharmony-tpc` / `openharmony-sig` Git 仓库拉取 OHos 平台实现：

```yaml
dependency_overrides:
  shared_preferences:
    git:
      url: https://gitcode.com/openharmony-tpc/flutter_packages.git
      path: packages/shared_preferences/shared_preferences
  path_provider:
    git:
      url: https://gitcode.com/openharmony-tpc/flutter_packages.git
      path: packages/path_provider/path_provider
  # ... 等等
  win32: 2.7.0  # Pin: 3.x+ 使用 OHos 缺失的 UnmodifiableUint8ListView
```

OHos 文件选择器通过 `lib/utils/ohos_file_picker.dart` 提供原生 fallback。

## 2.7 测试架构

### 2.7.1 Dart 测试

```
test/
├── core/                  # 纯函数测试（FSRS / SM-2 / enum_by_name / verbose）
├── data/                  # DAO 测试（srs_state_dao）
├── domain/                # 领域模型测试
├── service/               # 服务测试
├── BASELINE.md            # 测试基线记录
```

### 2.7.2 Python 工具测试

```
test/
├── course_cli_test.py     # 课程 CLI 校验
├── generate_audio_test.py # TTS 工具测试
└── tool/
    ├── build_release_test.py
    └── gui_round_trip_test.py  # GUI ↔ CLI round-trip
```

### 2.7.3 GUI 测试

```
tool/gui/tests/
├── test_ai_bench.py
├── test_ai_cache.py
├── test_ai_fixer.py
├── test_ai_phased.py
├── test_ai_presets.py
├── test_ai_scope.py
├── test_ai_stream.py
├── test_ai_summary.py
├── test_ai_usage.py
├── test_app.py
├── test_diff_view.py
├── test_focus_ring.py
├── test_git_skill.py
├── test_intent_llm.py
├── test_job_tray.py
├── test_labels.py
├── test_policy.py
├── test_proactive.py
├── test_save_brief.py
├── test_save_host.py
├── test_settings.py
├── test_teacher.py
├── test_telemetry.py
├── test_theme.py
└── test_ui_guard.py
```

## 2.8 代码生成策略

| 注解 | 生成器 | 输出 |
|---|---|---|
| `@freezed` | freezed | `*.freezed.dart` |
| `@JsonSerializable` | json_serializable | `*.g.dart`（领域模型） |
| `@DriftDatabase` / `@DataClassName` | drift_dev | `course_database.g.dart` |
| `@AutoRouteConfig` | auto_route_generator | `routing.gr.dart` |
| `@injectable` | injectable_generator | `injection.config.dart` |
| `flutter_gen` | flutter_gen_runner | `gen/assets.gen.dart` |

**生成代码已提交**到版本库，因此新克隆**无需先跑 `build_runner`**。只有修改了注解类时才需要：

```bash
flutter pub run build_runner build --delete-conflicting-outputs
# 或
make gen
```