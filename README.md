# Turna

[![GitHub Release](https://img.shields.io/github/v/release/DsDG1/turna?label=Release)](https://github.com/DsDG1/turna/releases/latest)
[![Android](https://img.shields.io/badge/Android-arm64--v8a-3DDC84?logo=android&logoColor=white)](https://github.com/DsDG1/turna/releases/latest)
[![Flutter](https://img.shields.io/badge/Flutter-3.44.5-02569B?logo=flutter&logoColor=white)](https://flutter.dev/)
[![License](https://img.shields.io/github/license/DsDG1/turna)](./LICENSE)

**本地优先的土耳其语学习应用。** 无需注册，打开即可学习，核心功能支持离线使用。

课程、复习记录和错题本默认保存在自己的设备上。AI 助教与远程备份是可选能力，只有主动启用时才使用相应的外部服务。换手机时可导出备份，再导入新设备。

[官网](https://turnalangua.xyz/) · [下载 Android 版](#下载-android-版) · [功能介绍](#能做什么) · [开发指南](#快速开始)

## 下载 Android 版

当前版本 **v0.9.1**，由 GitHub Actions 云端构建，并使用发布密钥签名。

**[下载 Turna v0.9.1 APK](https://github.com/DsDG1/turna/releases/download/v0.9.1/turna-v0.9.1-release.apk)** · [SHA-256 校验文件](https://github.com/DsDG1/turna/releases/download/v0.9.1/turna-v0.9.1-release.apk.sha256) · [查看全部版本](https://github.com/DsDG1/turna/releases)

- **系统要求**：Android 7.0 及以上。
- **设备架构**：仅支持 arm64-v8a；发布包不适用于 x86 / x86_64 模拟器。
- **安装方式**：下载 APK 后，按 Android 提示允许当前浏览器或文件管理器安装应用。

> 从旧的调试签名包切换时，两个签名不能互相覆盖升级。请先在应用内导出备份，再卸载旧版并安装正式签名包；卸载会清除本机应用数据。

## 能做什么

- **按课程学习**：主线课程按 A1 到 B2 规划为 8 章。第 1 章已有首个完整单元候选内容；真实听力音频、语言审校和移动真机验收仍在推进，第 2 章起尚未施工。
- **按记忆曲线复习**：通过 [FSRS](https://pub.dev/packages/fsrs) 间隔重复算法安排复习，在接近遗忘时进行主动回想，比旧的 SM-2 更贴近真实遗忘规律。
- **重做错题**：做错的题会留在错题本中，可以重做，也可以回到对应的语法点。
- **离线查词典**：支持土耳其语和中文查询。
- **导入 Anki 牌组**：直接导入 `.apkg` 文件，使用 Anki 官方排期和评分内核，复习节奏与 Anki Desktop、AnkiDroid 完全一致。牌组可显示为课程目录，也支持原卡片复习界面。
- **可选 AI 助教**：自行填写 API key 后，可使用语法讲解、生成复习课和从 PDF 教材生成课程；不填写不影响其他功能。
- **语音朗读**：单词、句子和听力材料支持自动朗读，可使用土耳其语语音包。
- **查看学习记录**：连续学习天数、成就和学习曲线默认保存在本机。

**不包含**：账号体系、排行榜、好友、内购和广告。

## 平台支持

| 平台 | 当前情况 |
| --- | --- |
| **Android** | 主要目标平台，功能最全；正式 Release 仅提供 arm64-v8a APK。 |
| **iOS** | 支持，记忆卡内核已接通；物理真机与分发链路仍待验收。 |
| **HarmonyOS** | 存在受限的伴生轻量版，能学课程、能复习，但不随正式版发布。 |
| **Web / 桌面** | 部分功能可用，记忆卡导入和正式复习不可用。 |

详细的平台边界和未验收项目以 [`docs/status.md`](./docs/status.md) 为准。

## 快速开始

### 开发环境

| 用途 | 需要 |
| --- | --- |
| 运行 App | Flutter **3.44.5**，官方 stable 版 |
| 编译 Android | JDK **17** |
| 运行工具脚本、桌面编辑器 | Python **3.11+** 和 PySide6 |

### 克隆并运行

```bash
git clone https://github.com/DsDG1/turna.git
cd turna
flutter pub get
flutter run
```

代码生成产物（`.freezed.dart`、`.g.dart` 等）已提交到仓库，克隆后可以直接运行。只有修改 `@freezed`、`@AutoRoute`、`@injectable` 等注解后，才需要重新生成：

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

> GitHub 仓库名为 `turna`，Gitee 远端仍叫 `dhwdwf3/Varnamalaplus.git`。从 Gitee 克隆时目录名会是 `Varnamalaplus`，内容相同。

### 检查与构建

```bash
flutter analyze
flutter test --exclude-tags golden
flutter build apk --release --split-per-abi --target-platform android-arm64
```

本地 release 签名与完整环境配置见 [Android 构建说明](./docs/android-build-setup.md)。未配置发布密钥时，Gradle 会回退到调试签名，不应把这种 APK 当作正式版本分发。

发布脚本会检查命令中的版本核心段是否与 `pubspec.yaml` 一致：

```bash
python tool/build_release.py --version 0.9.1 --skip-web
```

GitHub Actions 可以完成云端签名构建，并把 APK 和校验文件发布到 GitHub Releases，配置见 [Android 发布与 Firebase 分发](./docs/firebase-app-distribution.md)。

`make help` 可查看全部命令；`make ci` 会运行完整本地检查。测试基线见 [`test/BASELINE.md`](./test/BASELINE.md)。

## 课程内容

课程内容以 JSON 保存在 `assets/courses/`，首次启动时读入本地数据库。当前自动生成的内容清单见 [`docs/content_inventory_current.md`](./docs/content_inventory_current.md)。

主线课程 **NouveauTurkish** 规划为 8 章：

- 第 1 章包含首单元候选内容：1 个单元、24 课、27 个可玩节点、17 个词和 4 个固定表达。
- 第 2–8 章目前只有主题与等级规划，尚无课时。
- 12 条真实听力音频、人工语言审校、移动真机与学习效果验收尚未完成。

课程地图见 [`docs/authoring/nouveau-turkish-course-map.md`](./docs/authoring/nouveau-turkish-course-map.md)。添加课程时可参考 [`docs/authoring/`](./docs/authoring/) 的格式说明，或使用 [`tool/gui/`](./tool/gui/) 中独立的课程作者桌面编辑器。

0.9 起不再随包分发第二门语言。原法语课程已移到 `test/fixtures/french_course/`，仅作为测试 fixture；多语言机制仍然保留，导入的 `.turnapack` 课程包可与土耳其语课程共存。

## 文档与贡献

| 想了解的内容 | 入口 |
| --- | --- |
| 架构、领域模型与模块设计 | [`docs/project-guide.md`](./docs/project-guide.md) |
| 当前平台能力、课程内容与 Held 项 | [`docs/status.md`](./docs/status.md) |
| 文档索引 | [`docs/README.md`](./docs/README.md) |
| 代码分层、命名与提交前约束 | [`AGENTS.md`](./AGENTS.md) |
| Android 构建与签名 | [`docs/android-build-setup.md`](./docs/android-build-setup.md) |
| iOS 构建 | [`docs/ios-build-setup.md`](./docs/ios-build-setup.md) |
| 云端 Release 与 Firebase 分发 | [`docs/firebase-app-distribution.md`](./docs/firebase-app-distribution.md) |
| 历史设计决策 | [`docs/decisions/`](./docs/decisions/) |

## 致谢

项目骨架来自开源项目 [Varnamala](https://github.com/rshrc/Varnamala)，内置课程的复习算法基于 [FSRS](https://pub.dev/packages/fsrs)。本仓库是独立的个人分支，与上游无关；原版项目请访问上游仓库。

## License

见 [LICENSE](./LICENSE)。
