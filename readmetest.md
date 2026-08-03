# Turna

> 本地优先、离线的 Flutter 语言学习框架。当前目标语：**Turkish**。

基于上游 [Turna](https://github.com/rshrc/Varnamala) 的骨架，纯本地运行 —— SQLite（drift），无云后端/推送/登录，无社交功能。

## 快速开始

```bash
git clone <仓库地址> && cd VarnamalaPlus
flutter pub get && flutter run
```

生成代码已提交，**无需先跑 `build_runner`**。修改注解类后才需：

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

## 课程引擎

- **层级模型**：`Section → Unit → Lesson → SubLesson / ListeningPhase / ReadingPassage → Stage → Interaction`
- **13 种 Interaction 题型** + **6 种 Lesson Template**（intro / practice / listening / reading / review / mastery）
- JSON 课程数据按需加载 + drift SQLite 缓存，按内容版本自动 reseed
- 当前 8 个 CEFR 分级 Section（A1→B2），Section 1 含真实内容，Sections 2–8 为占位

## 核心功能

| 模块 | 能力 |
|---|---|
| **SRS 复习** | SM-2 算法，单词 + 语法点队列，闪卡显示学习来源 |
| **错题本** | 30 条 FIFO，含原始 interaction 快照，支持重做清除 |
| **语法复习** | Explain → Practice → Rate 三段流 |
| **每日挑战** | 从课程树随机抽取真实题项合成挑战课 |
| **弱词复习** | 近 30 天 ≥2 错次构建 10 题迷你 quiz |
| **Match Madness** | 单词配对小游戏 |
| **词典/搜索** | 搜单词、表达、语法点，`VocabAudioResolver` 播放音频 |
| **学习统计** | 90 天学习日志 + 7 日 XP 趋势 + 时长/准确率/弱词分析 |
| **AI 提示助手** | 课程内嵌 AI 聊天面板，按题目上下文提供提示（OpenAI-compatible） |
| **主题** | 暗色/亮色/跟随系统，`TurnaTheme` 语义化颜色 |
| **本地提醒** | `flutter_local_notifications` 每日提醒 |
| **进度管理** | 导出/导入 JSON，课程更新检测与重置提示 |

## 明确不做

League / 好友 / 排行榜 / Hearts / 商店 / Speaking 录音 / 云 CMS / Firebase

## 架构

```
Clean Architecture + Provider + ChangeNotifier + GetIt/Injectable + Auto Route
```

- `application/` — Providers（SRS / Grammar / Mistake / StudyStats / Score / Streak / Progress 等）
- `domain/` — 领域模型 + Repository 接口
- `data/` — drift 数据库 + Seeder + Repository 实现
- `views/` — courses / dictionary / home / lesson / play / profile / review / ai

## 构建与测试

```bash
flutter pub get && flutter run            # 运行
make gen                                  # 生成代码
make test                                 # Dart 测试 (385 passed)
make test-python                          # Python 工具测试
make analyze                              # 静态分析
make ci                                   # analyze + test + test-python + build smoke
make build-release VERSION=0.4.0-future4  # 发布构建
```

要求：Flutter SDK `>=3.2.3 <4.0.0`

## 文档

| 文档 | 说明 |
|---|---|
| [`CLAUDE.md`](./CLAUDE.md) | AI Agent 架构总览 |
| [`docs/decisions/`](./docs/decisions/) | ADR 0001–0020 |
| [`docs/content_inventory_current.md`](./docs/content_inventory_current.md) | Turkish 内容清单 |
| [`docs/authoring/course-layout.md`](./docs/authoring/course-layout.md) | Authoring 契约 |
| [`test/BASELINE.md`](./test/BASELINE.md) | 测试基线 |

## License

见 [LICENSE](./LICENSE)
