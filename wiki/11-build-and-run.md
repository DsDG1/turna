# 11. 构建与运行

> 本节覆盖本地开发、代码生成、测试、发布构建流水线。

---

## 11.1 环境要求

- **Flutter SDK**：随 Dart `>=3.2.3 <4.0.0` 兼容的版本
- **Dart SDK**：`>=3.2.3 <4.0.0`
- **平台特定**：
  - Android：Android Studio + SDK 21+
  - iOS：Xcode 14+
  - Windows：Visual Studio 2022 + Win32
  - macOS：Xcode
  - Linux：CMake + GTK
  - Web：现代浏览器
  - OHos：DevEco Studio（鸿蒙）

---

## 11.2 安装与首次运行

```bash
# 1. 克隆
git clone git@gitee.com:dhwdwf3/Varnamalaplus.git
cd Varnamalaplus

# 2. 安装依赖
flutter pub get

# 3. 运行（Android 示例）
flutter run -d android

# 或：
flutter run -d chrome       # Web
flutter run -d ios          # iOS
flutter run -d windows      # Windows
flutter run -d macos        # macOS
flutter run -d linux        # Linux
```

> ⚠️ **生成代码已提交到版本库**（`.freezed.dart` / `.g.dart` / `.gr.dart` / `.gen.dart` / `injection.config.dart`），新克隆**无需先跑 `build_runner`**。

只有修改了带 `@freezed`、`@JsonSerializable`、`@AutoRoute`、`@injectable` 注解的类时，才需要重新生成：

```bash
flutter pub run build_runner build --delete-conflicting-outputs
# 或
make gen
```

---

## 11.3 Makefile 目标

[`Makefile`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/Makefile)：

```bash
make help                # 显示所有 target 帮助
make gen                 # 运行 build_runner
make analyze             # 静态分析
make test                # Dart 测试
make test-python         # Python 工具测试
make build-release       # 构建发布包（需 VERSION 参数）
make build-release-smoke # CI smoke 构建（跳过 web + content 校验）
make ci                  # analyze + test + test-python + build-release-smoke
make clean               # flutter clean && flutter pub get
```

### 11.3.1 发布构建

```bash
make build-release VERSION=0.4.0-future4
# 或
python3 tool/build_release.py --version 0.4.0-future4
```

输出：
- Android APK
- Android AAB
- Web（zip）
- 内容清单

### 11.3.2 CI smoke 构建

```bash
make build-release-smoke
# 或
python3 tool/build_release.py --version ci-smoke --skip-web --skip-content-validation
```

---

## 11.4 完整命令清单

| 类别 | 命令 |
|---|---|
| 依赖 | `flutter pub get` |
| 生成代码 | `flutter pub run build_runner build --delete-conflicting-outputs` |
| 运行 | `flutter run [-d <device>]` |
| 静态分析 | `flutter analyze` |
| 测试（Dart） | `flutter test` |
| 测试（Python） | `python3 -m unittest discover -s test -p "*_test.py"` |
| 测试（GUI） | `cd tool/gui && python -m pytest tests/` |
| 清理 | `flutter clean && flutter pub get` |
| Release 构建 | `python3 tool/build_release.py --version <VERSION>` |

---

## 11.5 代码生成产物

| 注解 | 生成器 | 输出 | 何时需要重新生成 |
|---|---|---|---|
| `@freezed` | `freezed` | `*.freezed.dart` | 修改领域模型 |
| `@JsonSerializable` | `json_serializable` | `*.g.dart` | 修改序列化字段 |
| `@AutoRouteConfig` | `auto_route_generator` | `routing.gr.dart` | 修改路由 |
| `@injectable` | `injectable_generator` | `injection.config.dart` | 新增 @injectable 类 |
| `@DriftDatabase` | `drift_dev` | `course_database.g.dart` | 修改数据库 schema |
| `flutter_gen` | `flutter_gen_runner` | `gen/assets.gen.dart` | 新增/重命名资源 |

---

## 11.6 测试结构

### 11.6.1 Dart 测试

[`test/`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/test/)：

```
test/
├── core/
│   ├── enum_by_name_test.dart
│   ├── fsrs_engine_test.dart
│   ├── fsrs_relearn_test.dart
│   ├── result_test.dart
│   ├── sm2_test.dart
│   ├── text_styles_test.dart
│   └── verbose_test.dart
├── data/
│   └── srs_state_dao_test.dart
├── domain/
│   └── achievement_test.dart
├── service/
│   └── locator_test.dart
└── BASELINE.md
```

跑全部 Dart 测试：

```bash
flutter test
```

**当前基线**：624 passed / 3 failed（见 [`test/BASELINE.md`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/test/BASELINE.md)）。

### 11.6.2 Python 工具测试

```
test/
├── course_cli_test.py
├── generate_audio_test.py
└── tool/
    ├── build_release_test.py
    └── gui_round_trip_test.py
```

```bash
python3 -m unittest discover -s test -p "*_test.py"
# 或仅 CLI：
python3 -m unittest discover -s test -p "*_cli_test.py"
```

### 11.6.3 GUI 编辑器测试

```
tool/gui/tests/
├── test_ai_*.py
├── test_app.py
├── test_diff_view.py
├── test_focus_ring.py
├── test_git_skill.py
├── test_goal_e3b1.py / e3b2.py / e3b3.py
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
├── test_ui_guard.py
└── usability_smoke.py
```

```bash
cd tool/gui
python -m pytest tests/
# 或（offscreen CI 友好）
QT_QPA_PLATFORM=offscreen python -m pytest tests/
```

---

## 11.7 发布流水线（`tool/build_release.py`）

[`tool/build_release.py`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/tool/build_release.py) — 一键生成版本化 APK / AAB / Web 产物 + 内容清单。

```bash
python3 tool/build_release.py --version 0.4.0-future4
```

**可选参数**：

```bash
python3 tool/build_release.py --help
```

通常支持的 flags：
- `--version <VERSION>`：必填，版本号（如 `0.4.0-future4`、`ci-smoke`）
- `--skip-web`：跳过 Web 构建
- `--skip-content-validation`：跳过课程内容校验
- `--output-dir <DIR>`：自定义输出目录

**输出物**：

```
dist/<VERSION>/
├── varnamala-<VERSION>-android.apk
├── varnamala-<VERSION>-android.aab
├── varnamala-<VERSION>-web.zip
└── content_inventory.md
```

---

## 11.8 内容创作工作流（CLI）

### 11.8.1 课程 CLI

[`tool/course_cli.py`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/tool/course_cli.py)：

```bash
# 校验课程
python3 tool/course_cli.py --course-dir assets/courses/turkish validate

# Lint
python3 tool/course_cli.py lint

# CSV 导入/导出
python3 tool/course_cli.py csv-export --output vocab.csv
python3 tool/course_cli.py csv-import --input vocab.csv

# 音频清单
python3 tool/course_cli.py audio-manifest --output manifest.csv

# Diff（对比两个 section）
python3 tool/course_cli.py diff section1.json section2.json
```

### 11.8.2 内容清单导出

```bash
python3 tool/export_content_inventory.py
# 输出 docs/content_inventory_current.md
```

### 11.8.3 课程拆分

```bash
python3 tool/split_course.py --input index.json --output-dir out/
```

---

## 11.9 听力音频生成

[`tool/generate_audio.py`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/tool/generate_audio.py) — 调用 MiniMax T2A v2 REST API 批量合成：

```bash
export MINIMAX_API_KEY="sk-..."
export MINIMAX_GROUP_ID="..."

python3 tool/generate_audio.py all                        # 全部
python3 tool/generate_audio.py all --voice-id male-qn-jingying --speed 0.9
python3 tool/generate_audio.py speak "Merhaba, nasılsın?" out.mp3
python3 tool/generate_audio.py all --force                 # 强制重生成
```

[`tool/mix_listening_a1.py`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/tool/mix_listening_a1.py) — 用 pydub 混音（需 ffmpeg）：

```bash
pip install pydub

python3 tool/mix_listening_a1.py all \
  --main-dir  assets/sounds/turkish/listening/raw_a1 \
  --debut-dir assets/sounds/turkish/listening/debut \
  --fin-dir   assets/sounds/turkish/listening/fin \
  --bgm-dir   assets/sounds/turkish/listening/bgm \
  --mapping   tool/mappings/a1_show_mapping.csv \
  --output-dir assets/sounds/turkish/listening/mixed_a1
```

混音结构：`debut + [主内容 + BGM(降 18dB)] + fin`，结尾 BGM 淡出 800ms。每节课映射到 A/B/C variant（不同 debut/fin/bgm 组合），CSV mapping 指定；未映射默认 A。

---

## 11.10 GUI 编辑器运行与打包

```bash
# 运行
pip install PySide6
python tool/gui/src/main.py

# 打包
pip install pyinstaller
python tool/gui/build_gui.py              # onefile → dist/varnamala-gui.exe
python tool/gui/build_gui.py --onedir     # onedir
```

详见 [`tool/gui/README.md`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/tool/gui/README.md) 与 [08-ai-engine.md](./08-ai-engine.md)。

---

## 11.11 应用启动时序

详细分析见 [02-architecture.md#24-应用初始化流程](./02-architecture.md#24-应用初始化流程)。简版：

```
main()
  ↓
_installGlobalErrorHandlers()
  ↓
WidgetsFlutterBinding.ensureInitialized()
  ↓
configureDependencies()         // GetIt 注册 @injectable 类
  ↓
setupLocator()                   // AppPrefs / CourseDatabase / TTS / Seeder
  ↓
runApp(VarnamalaApp)             // 第一帧立即渲染 SplashRoute
  ↓
PostFrameCallback（异步后台）
  ├─ loadVocabulary() / loadGrammarPoints() / loadExpressions()
  ├─ SrsProvider.ensureLoaded() (SQLite hydrate)
  ├─ GrammarReviewProvider.ensureLoaded()
  ├─ CourseProvider.load()
  ├─ TtsAvailabilityChecker.configureSystemEngine()（非 Web）
  └─ LocalReminderService.applyFromSettings()（非 Web）
```

---

## 11.12 CI（GitHub Actions）

[`.github/workflows/flutter_ci.yml`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/.github/workflows/flutter_ci.yml) — GitHub Actions CI 流水线：

- `flutter analyze`
- `flutter test`
- `python3 -m unittest discover -s test -p "*_test.py"`
- `tool/course_cli.py validate`
- GUI 套件（offscreen）
- Build release smoke

---

## 11.13 调试与诊断

### 11.13.1 日志等级

```dart
import 'package:varnamala/core/logger.dart';

logger.i('info');
logger.w('warn');
logger.e('error', error: e, stackTrace: st);
```

### 11.13.2 Verbose 开关

[`lib/core/verbose.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/core/verbose.dart)：

```dart
bool veryVerbose = false;  // 设置为 true 后 prefs 写入会打印 value（不仅 key）
```

### 11.13.3 全局错误处理

`main.dart` 中 `_installGlobalErrorHandlers()`：

- `FlutterError.onError` → 记录 + `presentError()`
- `PlatformDispatcher.instance.onError` → 记录 + 返回 `true`（抑制默认崩溃打印）

---

## 11.14 常见问题排查

### 11.14.1 课程加载卡住

- 检查 `assets/courses/turkish/index.json` 的 `version` 是否与 `course_meta` 表一致
- 触发 reseed：bump version 或清空 app data

### 11.14.2 SRS 状态丢失

- 检查 `srs_states` 表是否被误删
- prefs → SQLite 迁移在 v7：`srs.migratedToSqlite.$queueId` flag

### 11.14.3 TTS 无声音

- Android：检查 Google TTS 是否安装
- 触发 `TtsAvailabilityChecker.configureSystemEngine()`

### 11.14.4 编译失败（注解类）

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

### 11.14.5 OHos 构建

通过 `dependency_overrides` 已适配；若失败，检查 `ohos/` 目录与 `hvigor` 配置。