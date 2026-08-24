# Turna

> 本地优先、离线的 Flutter 语言学习框架。当前目标语：**Turkish（土耳其语）**。
> 复习引擎基于 **FSRS**，可导入 **Anki** 牌组，AI 能力由统一引擎层 + AI Hub 承载。

[![Flutter CI](https://github.com/rshrc/Varnamala/actions/workflows/flutter_ci.yml/badge.svg)](.github/workflows/flutter_ci.yml)

> 详尽的设计与实现见 [`docs/project-guide.md`](./docs/project-guide.md)（单一真理源）。本 README 只给概览与快速上手。

---

## 这是什么

基于上游 [Turna](https://github.com/rshrc/Varnamala) 的 Section/Unit/Lesson/SRS/错题本骨架，聚焦 **Turkish**，持续深化：FSRS 复习引擎、Anki 牌组导入与原卡复习（默认 Flutter HTML）、统一 AI 引擎层。

- **纯本地**：SQLite（drift，schemaVersion 18），无云后端 / 推送 / 登录。
- **单人离线**：无好友、排行榜、联赛、心数、宝石购买。
- **主打 Android**：以 **Android** 为核心主力平台，兼顾 iOS 与 Web（有限支持）。OHOS 产品支持已退役（ADR 0041）。
- **教学法驱动**：功能取舍以二语习得研究为依据（见 project-guide §2 / §15）。

> 本仓库非上游官方版本；纯原版功能请访问 [rshrc/Turna](https://github.com/rshrc/Varnamala)。

---

## 快速开始

```bash
git clone git@gitee.com:dhwdwf3/Varnamalaplus.git
cd Varnamalaplus
flutter pub get
flutter run
```

> **生成代码已提交**（`.freezed.dart` / `.g.dart` / `.gr.dart` / `injection.config.dart`），新克隆**无需** `build_runner`。仅当修改 `@freezed` / `@JsonSerializable` / `@AutoRoute` / `@injectable` 注解时才需重新生成：
>
> ```bash
> flutter pub run build_runner build --delete-conflicting-outputs   # 或 make gen
> ```

### 当前内容状态

Turkish 课程，8 个 CEFR 分级 Section（A1->B2），全部填充真实内容（148 词 / 18 表达 / 8 语法 / 54 课时）。清单见 [`docs/content_inventory_current.md`](./docs/content_inventory_current.md)。

---

## 构建 / 平台 / 测试

```bash
flutter test                                        # 基线见 test/BASELINE.md
flutter analyze
make ci                                             # analyze + test + test-python + build-release-smoke
python tool/build_release.py --version 0.4.0-future4
```

- **核心平台**：**Android**（主战场；Anki 默认 Flutter HTML，WebView 仅 JS；Google/系统离线 TTS 与 FSRS SQLite）。
- **多端兼顾**：iOS 及有限 Web 支持；构建说明见 [`docs/android-build-setup.md`](./docs/android-build-setup.md)。
- **环境**：官方 Flutter SDK `>=3.2.3 <4.0.0` + JDK 17（Android）。Windows 上用 `python` 而非 `python3`。

构建、Makefile、发布流水线、平台门控详见 project-guide §10；课程数据格式见 §13；主题与调色板见 §9。

---

## 课程编辑器（tool/gui）

[`tool/gui/`](./tool/gui/) 是面向课程创作者 / 教师的 PySide6 桌面编辑器（**不进 App 本体**）：课程树、可视化蓝图、AI 课程工坊、教材导入、教师视图。完整说明见 [`tool/gui/README.md`](./tool/gui/README.md)。

```bash
python -m tool.gui.src.main
```

---

## 文档索引

| 文档 | 说明 |
|---|---|
| [`docs/project-guide.md`](./docs/project-guide.md) | **详尽版**：架构、FSRS、Anki、AI 引擎、教学法、平台全解（单一真理源） |
| [`CLAUDE.md`](./CLAUDE.md) | AI Agent 路由与 Key Files |
| [`docs/analysis/project-framework-analysis.md`](./docs/analysis/project-framework-analysis.md) | 产品 / 用户 / 商业化视角 |
| [`docs/content_inventory_current.md`](./docs/content_inventory_current.md) | Turkish 内容清单 |
| [`docs/official-anki-migration/31-anki-product-experience-plan.md`](./docs/official-anki-migration/31-anki-product-experience-plan.md) | Anki 产品体验收口：先打通导入，再课化/向导 |
| [`docs/ai_companion_implementation.md`](./docs/ai_companion_implementation.md) | AI companion 实现边界 |
| [`docs/advanced-settings-system-health.md`](./docs/advanced-settings-system-health.md) | 高级设置与系统健康 |
| [`docs/android-build-setup.md`](./docs/android-build-setup.md) | Android / 官方 Flutter 构建配置 |
| [`docs/authoring/`](./docs/authoring/) | Authoring 契约与教师指南 |
| [`docs/audio-recording-guidelines.md`](./docs/audio-recording-guidelines.md) | 人工录音提交规范 |
| [`docs/decisions/`](./docs/decisions/) | 架构决策记录（ADR 0030–0037） |
| [`test/BASELINE.md`](./test/BASELINE.md) | 测试基线 |

---

## 致谢

- 原始框架：[Turna](https://github.com/rshrc/Varnamala) - Section/Unit/Lesson 树 + Provider + Drift + Freezed + auto_route 骨架。
- 复习算法：[fsrs](https://pub.dev/packages/fsrs)（FSRS）、SM-2（后备）。
- 完整依赖清单与教学法依据见 project-guide §17。

## License

见 [LICENSE](./LICENSE)。
