# Turna

一个本地优先的 Flutter 语言学习应用，当前专注土耳其语。数据全部落在本机的 SQLite 里，没有账号，没有云端后端，也没有好友、排行榜这类社交设计。复习引擎基于 FSRS，支持导入 Anki 牌组直接复习，AI 功能由一层统一的引擎提供。

完整的设计与实现记录在 [`docs/project-guide.md`](./docs/project-guide.md)，官网见 [turnalangua.xyz](https://turnalangua.xyz/)。这份 README 只保留上手必需的内容。

## Anki

Turna 内嵌了官方 Anki 内核（Rust 编写，经 FFI 调用）：导入的牌组直接写进标准 Anki Collection，排期与评分完全交给官方 Scheduler，FSRS 参数也由官方实现维护，因此复习行为与 Anki Desktop / AnkiDroid 一致。牌组同时会被投影成 Turna 的课程树，可以按 Section / Unit / Lesson 的节奏推进，也可以切换到原卡视图——模板默认在 Flutter 端渲染，MathJax、音频和输入题型都有覆盖。导入的 Anki 卡与内置课程相互隔离，不会写进错题本或 Turna 自己的 SRS；整个流程照旧完全离线。

## 快速开始

```bash
git clone git@gitee.com:dhwdwf3/Varnamalaplus.git
cd Varnamalaplus
flutter pub get
flutter run
```

生成代码（`.freezed.dart`、`.g.dart` 等）已经提交进仓库，克隆下来就能直接运行，不需要 build_runner。只有改动 `@freezed` / `@AutoRoute` 这类注解时才需要重新生成：

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

## 构建与测试

```bash
flutter analyze
flutter test   # 测试基线记录在 test/BASELINE.md
```

Android 是主要目标平台（需要 JDK 17），iOS 和 Web 只做有限支持。课程内容已覆盖 A1 到 B2 共 8 个分级 Section，全部为真实内容，清单见 [`docs/content_inventory_current.md`](./docs/content_inventory_current.md)。

仓库里另有一个面向课程创作者的 PySide6 桌面编辑器，位于 [`tool/gui/`](./tool/gui/)，与 App 本体无关，其目录下有单独的说明。

## 致谢

项目的骨架来自开源项目 [Varnamala](https://github.com/rshrc/Varnamala)，内置课程的复习算法基于 [fsrs](https://pub.dev/packages/fsrs)。本仓库是独立的个人分支，与上游无关；需要原版功能请访问上游仓库。

## License

见 [LICENSE](./LICENSE)。