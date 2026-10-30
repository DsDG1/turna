# 状态（唯一真源）

> 本文件只回答一件事：**现在是什么样**。
>
> 不回答「为什么这么定」——那是 [`decisions/`](./decisions/) 的事；不回答「代码怎么分层」——那是 [`project-guide.md`](./project-guide.md) 的事；不回答「改代码该守什么」——那是 [`../AGENTS.md`](../AGENTS.md) 的事。
>
> **历史不在这里。** 每次施工的经过、真机收据原文、排查过程，一律在 git 历史（`git log -- docs/status.md`）与对应 ADR 里。本文件只保留**当前仍然成立的结论**。
>
> 改动本文件前先确认：写下的状态有可核验证据，且它没有过期。

---

## 1. 迁移总体口径

**验收 NO-GO；Official Anki 迁移中。**

| 禁语 | 为什么 |
|---|---|
| 不得写「迁移完成」 | 设备矩阵未闭环，见 §4 |
| 不得写「Android 可正常使用」 | 缺一次 arm64 真机上的**生产 bundle** 完整用户流冒烟，判据见 [ADR 0044](./decisions/0044-anki-v2-revival.md) |
| 不得写「鸿蒙支持 Official Anki」 | 「支持」是产品级断言；真机导入与课程学习解锁仍无收据，见 §6 |
| 不得写「鸿蒙复习器做不出来」 | 真机首卡收据已证明 ArkUI `Web` 满足 CSP / 自定义 scheme / Range 206，见 [ADR 0050](./decisions/0050-ohos-official-anki.md) |

**代码侧收口已完成**：host 侧 R0–R8 一次性收口全绿；架构简化 P0–P4 落地（Legacy 读退役 / `course.db` v27 删表 / 备份互斥）；iOS 官方 Anki 栈接通。首发平台是 **Android arm64 + iOS**，走同一条 Official 生产路径。

---

## 2. 平台档位

档位由代码判定，不是文档口径：[`AnkiImportExecutionPlanner.productModeFor`](../lib/application/anki_official/import/anki_import_execution_plan.dart) 返回 `AnkiProductMode`。

| 平台 | 档位 | 前提 |
|---|---|---|
| Android | 官方档（枚举名 `officialAndroid`） | cutover flag 开启 |
| iOS | 官方档（同上，同一条生产路径） | cutover flag 开启 |
| 鸿蒙 | 官方档 | cutover flag 开启；接线步 0–5b 已施工（§6） |
| 其余（linux / windows / web / macos） | `ankiUnavailable` | 新导入与正式复习不可用；**不得创建 Legacy Anki 写者** |
| 全部平台 | `ankiUnavailable` | cutover flag 关闭时 |

`officialAndroid` 这个枚举名是 iOS 加入支持集之前留下的，改名要动全部调用点，无行为收益——保留原名，别当错号修。

---

## 3. 已验证能力（证据台账）

| 平台 / 形态 | 覆盖 | **未覆盖** |
|---|---|---|
| Android **真机** PLG110，**debug 构建** | 写侧链路：导入 → 账本 → 视图 → 删除收敛。硬性能：10 万卡 commit 3.5s、视图重建 2.8s、强杀零数据损伤 | ①生产 bundle 未验；②同夜 F6 阻断「进一个课时」，已修但**修后无真机复跑** |
| iOS **模拟器** iPhone 17 / iOS 26.5 | 真 .apkg 导入完成 + 复习器 Q→A 渲染 | ①非真机；②未覆盖升级安装 / 备份恢复 / 强杀恢复；③Android 生产 bundle 仍未验 |
| 鸿蒙 **真机** Mate 90 Pro Max / API 26 | 引擎、内存 SQLite、平台路由、降级拆除探针收据；首卡全链路（渲染 / 翻卡 / 评分落库 / 队列前进 / 强杀恢复） | 真机导入、课程学习解锁（§6） |
| 鸿蒙 **真机** CMM-AL10 / HarmonyOS 7.0.0.109 / API 26 | 二档评分按钮、评分落库（记住 → `ease=3`）、源徽章、工具栏启用谓词、完成交棒、连续过卡推进 | 遗留打磨项；步 6 CI 首跑收据 |

「跑通过」不能推出「可正常使用」。每次写状态时，上面两列都要照实填。

---

## 4. 仍未验收（Held）

- **Android 生产 bundle 完整用户流冒烟**：装包 → 导入真 .apkg → 打开课程 → 进入至少一个课时并完成 → 正式复习答一张。host 测试、logcat、诊断导出、bugreport **均不构成完成**。
- **iOS 真机（非模拟器）验证**：模拟器不替代真机验收。
- **release 真机矩阵**：干净安装 / 升级安装 / 迁移包 / 备份恢复 / 强杀恢复。
- **外部事实**：存量用户跑批与 owner 切换、Legacy 零新写观察期。
- **一个正式 release 观察**：按负责人豁免处理（非证据齐备）。
- **记忆卡适配（ADR 0057）端到端未验**：本机 `flutter build apk --debug` 出包成功，但没有连接任何 Android / 鸿蒙设备，未走「导入 → 预览智能适配 → 提交 → 课时 / 正式复习」真机链路。**AI 链路已在真实端点打通**（`tool/live/ai_adaptation_live_smoke_test.dart`，一次真实调用产出 `accepted` 方案且本地复核通过），但未走 app 内「设置里配 key → 预览页点生成」的真实路径；分层抽样仍未实现（缺 Rust 工具链）。鸿蒙 HAP 构建在 hvigor 配置解析阶段失败（本机全局 hvigor 与仓库 `modelVersion 5.1.0` + `flutter-hvigor-plugin` 不匹配），属环境问题。
  - 代码侧「单一解析器」收敛已完成（host 侧验证，见 `OfficialCardPresentationResolver.resolveCard`）：课时派生、导入预览（模式推断 + 逐卡计数）、正式复习（`formalReview` 约束 + 渲染内容指纹）都走同一解析器；方案→映射的折叠、不支持结构回原卡、Cloze 挖空作用域（模板序号 0 + `clozeTarget`）都在解析器与暂存键两侧对齐；预览生成方案时做样本级「全 unsupported 拒绝」。课时派生带失败原因返回（映射损坏 / 全组 needsMapping / 全卡派生失败可区分于普通 miss）。
  - 仍开放的实现缺口：视图行仍存「预计 kind」提示（ADR 0057 §1 的第四条判定路径已收敛到策略表并补齐日志，但结构性移除该列需连带 4 个测试文件重写，未做）；适配命名空间清理的返回值检查与维护任务挂点等引擎生命周期（开放决策①）落地后一起收。

---

## 5. 开放决策（不得默认按「已接受现状」处理）

| # | 限制 | 现状 | 待决策 |
|---|---|---|---|
| ① | 引擎生命周期耦合 | 视图收敛、决策写入、物理删除、GC 全部排队等引擎打开（引擎懒开，仅 due sync / 复习 / 导入时开）。10 万卡物理删除在账本 retiring 后等了数小时，直到用户下一次导入碰巧开引擎才执行 | 二选一：启动时见 v2 active 源即主动开引擎（收敛变保证）／ 接受概率收敛并写入设计文档（含用户可见后果） |
| ② | 共享 collection 上的来源所有权 | 数据面已齐：`OfficialAnkiImportLog` 含 `newNoteIds` / `duplicateNoteIds` / `conflictingNoteIds`。**策略面缺失**——`conflictingNoteIds` 全库无人消费，`commit` 只读 new / duplicate 两个计数 | 定一条重导 / 同 GUID 策略（拒绝 + 明确 UI，或所有权转移规则），写进 ADR |

限制③（双代并存）已消解：v1 已整体退役。

---

## 6. 鸿蒙三层口径

三层不要混用。「鸿蒙」这个词在不同层指的不是一回事。

| 层 | 事实 | 真源 |
|---|---|---|
| **产品级** | 已 EOL。伴生版不进主交付、不进主 CI | [ADR 0050](./decisions/0050-ohos-official-anki.md)（原 ADR 0041（已删）的 EOL 口径已被 ADR 0047 修订、0050 再修订） |
| **伴生版** | 存在但受限：课程 / SRS / 复习 / 词典 / 设置 / 备份 + 自维护 ArkTS 通道；**不含 AI 生成**（华为审核合规移除，[ADR 0056](./decisions/0056-ohos-remove-ai-compliance.md)） | [ADR 0047](./decisions/0047-ohos-companion-lite-build.md) |
| **Official Anki** | 已授权；接线步 0–5b 已施工 | [ADR 0050](./decisions/0050-ohos-official-anki.md) |

### 已成立

- `productModeFor('ohos')` → 官方档。能力矩阵已把鸿蒙路由到官方档，**不再是 `ankiUnavailable`**。
- ArkTS 编译器收据已取得：`flutter build hap --debug` 产出 signed hap，0 ERROR。
- 复习评分档为**二档**（忘记 / 记住），只发 `again` / `good`，与安卓 `BinaryRecallBar` 同语义；协议层四个 rating 词保留。
- 顶栏只剩 `X` + 进度 + 源徽章。
- 入口白屏已收口，真机通过：预热整体撤除，首卡由 `OfficialAnkiReviewerStage.attach` 在 Flutter 仍在前台时 present。

### 不要复刻旧实现

预热（`warmUp`）、顶栏四键（撤销 / 重做 / 搁置 / 暂停）、`requestCardAction` / `requestUndo` 协议方法、debug 启动自拉的全屏能力探针——**这些曾实现，后来移除**。要加回去之前，先看 git 历史里它们为什么被移除。

当前顶栏只有 `X` + 进度 + 源徽章。入口白屏的根因是预热本身：预热会把 ability 全屏拉起，而批次尚未就绪、Stage 尚未 mount，原生页只渲染出空壳。首卡现由 `OfficialAnkiReviewerStage.attach` 在 Flutter 仍在前台时 present。

### 仍 Held

- **步 6 独立 CI 首跑收据**：workflow 已落库（`ohos_ci.yml` + `tool/ohos_ci_prepare.py`，无签名 hap 冒烟），首跑需先配 `DEVECO_CMDLINE_TOOLS_URL` 仓库变量。
- **用户流余项**：真机导入、课程学习解锁。

### 平台纪律

- 平台判断一律走 `isHarmonyOsTarget`（`lib/core/ohos_target.dart`），**不得内联 `Platform.is*` 比较**——鸿蒙上 `Platform.is*` 全为 false。
- `lib/` 里不得出现 `Ohos*` 标识符（`OhosView` / `OhosViewController` / `initOhosView` 等）。它们只存在于 OHOS fork SDK，官方 SDK 下是 `undefined_class`，而 `dependency_overrides` 无平台条件。
- `sqlite3` 包没有鸿蒙平台枚举值，可用入口只有 `overrideForAll()`——不是加一行 override。

---

## 7. 课程内容更新

本地内容读取接缝已接线：`CourseContentSource`、`DatabaseSeeder` 和 `CourseProvider.refreshBuiltinContent` 支持整套选源、版本比较、损坏更新回落、事务重播种与缓存刷新；决策见 [ADR 0058](./decisions/0058-builtin-course-content-source.md)。`tool/publish_course.py` 已实现本地快照校验、升版、zip 与 feed 生成、SHA-256 和历史清单，并已实际生成首包；`check_builtin_version` 拒绝低于内置的版本、对同版包给 stderr 警告（接缝同版选内置 assets），发布契约见 [ADR 0059](./decisions/0059-course-release-feed.md)。`CourseOtaService` 已实现 feed/zip 下载、相对 URL 解析、传输策略、SHA-256/大小校验、JSON-only zip-slip 防护、整包课程校验、版本拒绝及可恢复的原子目录切换；服务层测试覆盖失败保留旧内容与中断恢复。学习设置页的 `SettingsCourseUpdateTile` 已接入手动 URL 更新、进度/错误反馈和 `CourseProvider.refreshBuiltinContent`；下载成功但应用被学习／备份门控拦截时可免重下重试。`SettingsCourseRestoreTile` 通过 `CourseOtaService.clearInstalledContent` 删除已下载目录（含 backup 与 tmp）并重播种回内置内容，随后写 `contentVersionAcknowledged`，避免降级重弹 ADR 0002 提示。内存 DB 全链路已验证 HTTP 安装 → 重播种 → 课程树显示新内容，以及清除后回落内置内容。**尚未完成云端热更新日常闭环**：远端托管发布与真机验收仍待实现；本地覆盖、恢复入口与进度提示也尚无真机验收证据。

---

## 8. 维护规则

1. 本文件**只增结论，不增流水**。一轮施工做完，把结论改写成一两行状态，不要追加一段施工经过。
2. 状态变了就**改写**对应条目，不要在旁边加一句「其实……」——那正是本文件要消灭的写法。
3. 撤销一个结论就**删掉它**，不要在旁边留一句"其实……"。要查历史去 git。
4. 每条状态要么指向 ADR，要么指向代码或测试；指向会被改写的源码时用符号名，不写行号。
5. 测试数、版本号、文件清单这类会漂的数字**不写这里**，现场查。
