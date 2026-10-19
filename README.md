# Turna

一个学土耳其语的手机应用。打开就能用，不用注册，断网也能用。

课程内容、复习记录、错题本全都存在你自己的设备上，不上传到任何服务器。换手机时导出一份备份文件，再导入新手机就行。

官网：<https://turnalangua.xyz/>

## 能做什么

- **按课程学** —— 8 节课程，从 A1 到 B2。每节都有单词、语法、听力和阅读练习，内容是完整写好的，不是占位。
- **按记忆曲线复习** —— 用间隔重复算法安排复习时间，在快要忘记的时候让你回想一遍。算法用的是 [FSRS](https://pub.dev/packages/fsrs)，比老的 SM-2 更贴近真实遗忘规律。
- **错题本** —— 做错的题会留下来，随时能重做，也能跳回对应的语法点。
- **查词典** —— 输入土耳其语或中文都能查，支持离线。
- **导入 Anki 牌组** —— `.apkg` 文件可以直接导入。导入的牌组用 Anki 官方的排期和评分内核，所以复习节奏和 Anki Desktop、AnkiDroid 完全一致。牌组会同时显示成课程目录，可以按单元推进，也可以用原卡片界面。
- **AI 助教**（可选） —— 自己填一个 API key 之后，可以让 AI 讲解语法、帮你出一套复习课、从 PDF 教材生成课程。不填也能正常用。
- **朗读** —— 单词、句子、听力材料都能自动朗读，支持土耳其语语音包。
- **学习记录** —— 连续学习天数、成就、学习曲线都在本机保存。

**不做的事**：没有账号、没有排行榜、没有好友、不能内购、不弹广告。数据不离开你的设备。

## 运行需要什么

| 用途 | 需要 |
| --- | --- |
| 跑 App | Flutter **3.44.5**（官方 stable 版） |
| 编译 Android | 再装 **JDK 17** |
| 跑工具脚本、桌面编辑器 | 再装 **Python 3.11+** 和 PySide6 |

> 仓库里另有一个给课程作者用的桌面编辑器，在 [`tool/gui/`](./tool/gui/)，是独立的 Python 工程，不影响 App 本体。

## 快速开始

```bash
git clone https://github.com/DsDG1/turna.git
cd turna
flutter pub get
flutter run
```

> 仓库名没跟上产品改名：GitHub 远端是 `turna`，gitee 远端还叫 `dhwdwf3/Varnamalaplus.git`。从 gitee 克隆时目录名是 `Varnamalaplus`，内容一样。

代码生成产物（`.freezed.dart`、`.g.dart` 等）已经提交进仓库，克隆下来直接就能跑。只有改了 `@freezed`、`@AutoRoute`、`@injectable` 这类注解才需要重新生成：

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

## 构建与测试

```bash
flutter analyze
flutter test                                  # 测试基线见 test/BASELINE.md
flutter build apk --release --split-per-abi --target-platform android-arm64
```

发布用的版本号必须和 `pubspec.yaml` 里的 `version` 一致，脚本会自己检查：

```bash
python tool/build_release.py --version 0.9.0
```

`make help` 可以看全部命令；`make ci` 是本地跑全套检查（格式、静态分析、测试、工具测试、桌面编辑器检查、构建冒烟）。

## 支持哪些平台

| 平台 | 情况 |
| --- | --- |
| **Android** | 主要目标平台，功能最全。发布包只发 arm64。 |
| **iOS** | 支持，Anki 内核也接通了。 |
| **HarmonyOS** | 有个测试用的轻量版本，能学课程、能复习，但不随正式版发布。 |
| **Web / 桌面** | 能用一部分，Anki 导入和复习不可用。 |

各平台的详细环境配置：

- [Android 构建说明](./docs/android-build-setup.md)
- [iOS 构建说明](./docs/ios-build-setup.md)
- [内测分发（Firebase App Distribution）](./docs/firebase-app-distribution.md)

## 课程内容

课程内容是 JSON 文件，放在 `assets/courses/` 里，由程序读进本地数据库。当前清单见 [`docs/content_inventory_current.md`](./docs/content_inventory_current.md)（自动生成，不要手改）。

- **土耳其语**：正式课程，A1 到 B2 共 8 节。

0.9 起不再随包分发第二门语言：原先作为「多语言并存」验收样例的法语课程已移入
`test/fixtures/french_course/`，只作为测试 fixture 存在。多语言机制本身保留，
导入的 `.turnapack` 课程包仍可与土耳其语共存。

要加新课程，参考 [`docs/authoring/`](./docs/authoring/) 里的格式说明，或者用上面的桌面编辑器。

## 文档

| 想知道 | 看哪里 |
| --- | --- |
| 完整的技术说明（每个模块怎么实现的） | [`docs/project-guide.md`](./docs/project-guide.md) |
| 所有文档的索引 | [`docs/README.md`](./docs/README.md) |
| 写代码要遵守的规矩 | [`AGENTS.md`](./AGENTS.md) |
| 每次改动的测试记录 | [`test/BASELINE.md`](./test/BASELINE.md) |
| Anki 内核迁移的进度和证据 | [`docs/official-anki-migration/`](./docs/official-anki-migration/README.md) |
| 为什么这么设计（历史决策） | [`docs/decisions/`](./docs/decisions/) |

## 致谢

骨架来自开源项目 [Varnamala](https://github.com/rshrc/Varnamala)，内置课程的复习算法基于 [fsrs](https://pub.dev/packages/fsrs)。本仓库是独立的个人分支，与上游无关；想用原版请去上游仓库。

## License

见 [LICENSE](./LICENSE)。
