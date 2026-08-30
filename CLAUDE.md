# Turna - Language Learning App

> 本地优先、离线 Flutter 语言学习框架，目标语 Turkish。复习引擎 FSRS，可导入 Anki 牌组，AI 能力由统一引擎层 + AI Hub 承载。
>
> **详尽架构 / 实现 / 教学法见 [`docs/project-guide.md`](./docs/project-guide.md)**（单一真理源）。本文件只给 Agent 路由所需的导航与命令，不重复 project-guide 的内容。

---

## 快速导航

- **当前状态**：8 个 CEFR 分级 Section（A1->B2）全部填充真实内容（148 词 / 18 表达 / 8 语法 / 54 课时）。schemaVersion 21，课程内容版本 12。
- **目标语**：Turkish，TTS 语言码 `tr`。
- **复习引擎**：FSRS（`lib/core/fsrs_engine.dart`），SM-2 后备；Anki 卡排期走官方 Core scheduler（ADR 0036/0037，`lib/application/anki_official/`）。Android 生产 bundle 见 `OfficialAnkiFeatureFlags.productionAndroid`；收口施工以 [doc 34](./docs/official-anki-migration/34-official-anki-production-cutover-and-ohos-retirement-plan.md) 为准（迁移中；W9 HOLD 已于 2026-08-27 由负责人决策解除，观察期证据按负责人豁免，W9-B..E 分波删除可开工，豁免决策记录见 [doc 34 收据](./docs/official-anki-migration/34-cutover-receipt.md)「Held」表）。
- **调色板**：Turna「湿地鹤」（ADR 0033/0035，主色 `#1F727E`，无 `peacock*` 别名）。真源 `lib/views/theme.dart` ↔ `tool/gui/src/theme_tokens.py`。
- **构建**：官方 Flutter + Android（JDK 17）；见 [`docs/android-build-setup.md`](./docs/android-build-setup.md)。OHOS 产品 EOL 见 [ADR 0041](./docs/decisions/0041-ohos-product-eol.md)。
- **AI 引擎层**：`lib/application/ai/engine/`（全应用唯一 LLM 出入口，配置含 API key 经 `StreamingSharedPreferences` 持久化、写入绕过日志）。
- **决策记录**：`docs/decisions/`（ADR 0030–0042）。

功能实现状态见 project-guide §4；已明确不做的功能见 §15。

---

## 架构（导航级）

Clean Architecture + Provider + ChangeNotifier + GetIt/Injectable + Auto Route。

```
lib/
├── application/   # Providers + 应用服务
│   ├── ai/         # AI 能力（engine/ 统一引擎层 + companion/ + textbook/）
│   ├── anki_import/    # Anki 导入向导 controller / flow / 完成协调 + recognition/ 证据驱动识别器（doc 37，notetype 级判定）
│   ├── anki_official/ # 官方 Anki Core（rslib FFI）引擎 / 导入 / 渲染 / 投影 / 迁移（ADR 0036）
│   ├── srs_provider.dart          # 单词 SRS 队列（FSRS，SrsQueueProvider 子类）
│   ├── grammar_review_provider.dart  # 语法 SRS 队列
│   ├── srs_queue_provider.dart    # SRS 队列共享基类
│   ├── mistake_provider.dart      # FIFO 错题本
│   ├── study_stats_provider.dart  # 学习统计聚合
│   ├── memory_curve_provider.dart # 记忆曲线
│   ├── audio_controller.dart      # TTS / 音效统一接管
│   ├── smart_speech.dart          # 智能朗读（语言检测 + 自动朗读）
│   ├── accessibility_provider.dart # 6 项可访问性偏好
│   └── game_provider.dart         # 薄 facade -> score/streak/progress/gems
├── core/          # fsrs_engine / sm2 / language_detector / html_stripper / streak / logger
├── courses/       # 字母 + 语种 loader/validator（目标 Turkish）
├── data/          # drift CourseDatabase（schemaVersion 21）+ Seeder + DAO + Repository
├── di/            # GetIt + Injectable（renderer_module / audio_module）
├── domain/        # 领域模型 + Repository 接口（course / audio / repositories）
├── routing/       # Auto Route + CourseReadyGuard
├── service/       # AppPrefs / locator / TTS / 本地提醒
└── views/         # courses / dictionary / home / lesson / play / profile / review /
                   # ai / anki / anki_official / settings / theme.dart
```

完整分层、关键模式、领域模型、14 种 Interaction、6 种 Lesson Template 见 project-guide §3-§4。

---

## Key Files（Agent 路由）

| 文件 | 用途 |
|------|------|
| `lib/main.dart` | App 入口 |
| `lib/views/app.dart` | 根 widget + providers |
| `lib/routing/routing.dart` | Auto Route 配置 + guards |
| `lib/routing/course_ready_guard.dart` | DB seed 完成前重定向 splash |
| `lib/di/injection.dart` | GetIt DI 设置 |
| `lib/service/locator.dart` | AppPrefs / preferences / TTS |
| `lib/application/game_provider.dart` | 薄 facade -> score/streak/progress/milestone |
| `lib/application/srs_provider.dart` | 单词 SRS 队列（FSRS） |
| `lib/application/grammar_review_provider.dart` | 语法 SRS 队列 |
| `lib/application/srs_queue_provider.dart` | SRS 队列共享基类 |
| `lib/application/mistake_provider.dart` | FIFO 错题本 |
| `lib/application/study_stats_provider.dart` | 学习统计聚合 |
| `lib/application/memory_curve_provider.dart` | 记忆曲线 |
| `lib/application/audio_controller.dart` | TTS / 音效统一接管 |
| `lib/core/fsrs_engine.dart` | FSRS 调度器 |
| `lib/core/language_detector.dart` | 智能朗读语言检测 |
| `lib/domain/course/lesson.dart` | Lesson 模型 + LessonTemplate |
| `lib/domain/course/interaction.dart` | Interaction 模型（14 种 freezed sealed union） |
| `lib/di/renderer_module.dart` | 14 个 InteractionRenderer 的 GetIt 多绑定集合；分发见 `interaction_renderer.dart` 的 `lookupRenderer()` |
| `lib/domain/audio/vocab_audio_resolver.dart` | 音频 / 内容解耦接口 |
| `lib/data/course_repository.dart` | 课程仓库实现 |
| `lib/views/theme.dart` | TurnaTheme（亮/暗/高对比 + 语义颜色 helper） |
| `docs/project-guide.md` | 详尽设计与实现说明 |
| `docs/decisions/` | ADR 0030–0041 |

---

## 开发命令

```bash
flutter pub get                                              # 生成代码已提交，无需 build_runner
flutter run
flutter pub run build_runner build --delete-conflicting-outputs  # 改 @freezed/@JsonSerializable/@AutoRoute/@injectable 后
flutter test                                                 # 基线见 test/BASELINE.md
flutter analyze
python -m unittest discover -s test -p "*_test.py"           # Python 工具测试
python -m unittest discover -s tool/gui/tests -p "test_*.py" # GUI 测试
python tool/build_release.py --version 0.4.0-future4         # 发布
```

Windows 用 `python`（非 `python3`）。完整 Makefile / 平台 / 发布流水线见 project-guide §10；课程数据格式见 §13；测试基线见 `test/BASELINE.md`。

---

## Agents Available

### Flutter/Firebase Expert
Location: `.claude/agents/FLUTTER_FIREBASE_EXPERT.md`
- 架构指导、Firebase 实现、状态管理、性能优化

### Course Generator Agent
Location: `.claude/agents/COURSE_GENERATOR_AGENT.md`
- 生成新语言课程、创建题集、校验课程结构、语言学科专长

---

## Contributing

1. 遵循现有代码模式
2. 模型改动后跑 `build_runner`
3. 提交前跑 `flutter test` + `flutter analyze`
4. 测试数变化时更新 `test/BASELINE.md`
5. UI 一致性用 theming 指南（project-guide §9）
6. 架构决策加 ADR 到 `docs/decisions/`
