# 34 — Cutover receipt（W8–W10 收口摘要）

> 日期：2026-08-25（一次性施工 host 收口后更新；2026-09-24 架构简化计划 P0–P4 施工后补充下方「架构简化批次」；2026-09-27 补记 iOS 启用与真机证据台账、订正 Held 表；2026-10-08 补记鸿蒙 Official Anki 接线批次步 0–4；2026-10-14 补记鸿蒙步 5b 判据结清；同夜补记步 5b 真机首卡收据；2026-10-15 补记步 6 独立 CI workflow 施工；2026-10-16 补记评分回执与按钮互斥修复）
> 状态：**验收 NO-GO；Official Anki 迁移中**（host/自动化门禁全绿、**Android 写侧与 iOS 导入链各有一次真机/模拟器证据**；生产 bundle 全链路与外部事实未验收。不得写「迁移完成」，不得写「Android 可正常使用」）
> 计划真源：[`34-official-anki-production-cutover-and-ohos-retirement-plan.md`](./34-official-anki-production-cutover-and-ohos-retirement-plan.md)
> 剩余波次：[`34-remaining-construction-plan.md`](./archive/34-remaining-construction-plan.md)（已归档，R0–R8 全部闭环）
> W9 HOLD 解除记录与证据台账：见本收据「W9 HOLD 解除记录与证据台账（2026-08-27）」一节（原独立文件 `34-w9-legacy-deletion-hold.md` 已于 2026-09-27 并入该节并删除）
> OHOS EOL ADR：[ADR 0041](../decisions/0041-ohos-product-eol.md)（草案曾写 0038；0038 已占用）

---

## 架构简化批次（2026-09-24，`Turna架构简化实施计划` P0–P4）

> 计划 P0 的门禁核对结论：现行收据口径**准确**——host 门禁全绿、无任何正式发版
> （存量用户数为零）、真机矩阵未跑，**维持 NO-GO 标注**。本批次在 host 侧完成：

- **P0 备份一致性**：busyGuard 生产接线（`StudyActivityGate` 学习/备份互斥，覆盖
  导入 parse/commit、正式复习、课时与三个练习页）；快照期各阶段间复查，学习活动
  中途出现即中止并清理 staging；媒体改为复制进 staging 后从副本校验/上传；并发
  变更/中断/恢复测试覆盖数据库、偏好与媒体（备份域 63 例全绿）。
- **P1 Legacy 读退役**：Legacy 浏览器/统计分支、Legacy 卸载链、scope 启动修复与
  `decodeLegacy`、迁移包 NoteStore 载荷、due 聚合 Legacy 词扫描全部删除；非
  Official 源 fail-closed 显示错误。W9-B..C 的 host 侧部分就此关闭。
- **P2 schema 清理（W9-E 兑现）**：course.db v27 DROP `anki_notetypes/anki_notes/
  anki_cards_meta`，`AnkiNoteDao`/`IAnkiNoteStore` 删除；catalog 链 v6/v8 死 DDL
  移除；**历史迁移链保留不折叠**（逐版本迁移测试齐全，折叠收益不明显；理由见
  计划文档 P2 记录）。
- **P3 语言切换失败语义**：内容先加载、失败拒绝切换；级联失败整体回退旧语言并
  向调用方抛错；偏好写入 await；连续切换串行化（9 例失败注入测试）。
- **P4**：浏览器牌组下拉改专用牌组查询（不再全量物化卡片）+ 浏览路径性能埋点；
  `LessonSrsUndoLog` / `CourseCatalogOrdering` 职责拆出（行为不变，小步可回归）。
- **验证**：`flutter analyze` 0 issue；全量 `flutter test` 1937:2（2 例为
  course_tree golden 已知本机失配，09-22 批已记录，非本批回归）。
- **仍 Held**：真机矩阵（干净/升级安装、导入、复习、语言切换、备份恢复、强杀、
  卸载）与 Android 样本包流程——无设备会话，不以 widget test 替代（plan 34 §4.4）。
  真机基线测量（冷启动/课程切换/大卡组浏览）随 P4 埋点就绪，待设备执行。


## iOS 官方 Anki 栈启用（2026-09-26，PR #7 `ec0170ae`）

> 本节为 2026-09-27 补记：iOS 启用与模拟器 E2E 当时只进了
> `test/BASELINE.md` 2026-09-26「iOS 官方 Anki 栈接通」条目与本目录
> `README.md`，本收据未同步，导致「唯一状态源」比实际落后一个批次。
> 本节补齐后，Held 表的「无设备会话」表述同步订正（见下）。

- **范围**：首发平台由 Android 单平台扩为 **Android arm64 + iOS**。iOS 走
  与 Android 同一条 Official 生产路径——`productModeFor('ios')` →
  `AnkiProductMode.officialAndroid`，`AnkiImportExecutionPlanner` 对两平台
  返回同一 `officialFirst`（`test/application/anki_official/
  anki_import_execution_plan_test.dart` 的 ios 用例即此约束的守卫）。
- **native 形态差异**：Android 打包 `libturna_anki.so`（dlopen 探针）；iOS
  静态链接 rslib（`turna_anki_core` 加 `staticlib` → `build-ios/build.sh` →
  `ios/Frameworks/TurnaAnki.xcframework`，产物**不入库**），探针改为查进程
  符号表（`DynamicLibrary.process()` 找 `turna_anki_abi_version`）。
- **复习器**：iOS 为 WKWebView（`ios/Runner/AnkiReviewer/`），与 Android
  MethodChannel/JS 协议对齐，`WKURLSchemeHandler` 服务
  `turna-anki://anki.local` 提供渲染资产与媒体 Range/206。
- **验证**：`flutter build ios --simulator --no-codesign` 链接通过、7 个
  `turna_anki_*` 符号确认进 `Runner.debug.dylib`；**iPhone 17 模拟器
  （iOS 26.5）E2E：真 .apkg 导入完成、复习器 Q→A 渲染通过**。该次 E2E
  实测暴露并修掉 2 个真运行时 bug（`jsString` 缺 `.fragmentsAllowed` 致崩、
  scheme 响应缺 `Content-Type` 触发 FrameLoadInterrupted）——即「模拟器
  跑通」本身是这两次修复的产物，不是既有代码的既有能力。
- **全量计数**：`flutter test` 1938 passed / 2 failed（2 例为 HEAD 既有的
  `course_tree` golden 本机失配，非本批回归）。

---

## 鸿蒙生产调用链修复（2026-10-13）

2026-10-08 的 `catalog=ok` 是 `probeOfficialAnkiSqlite()` 的内存 SQLite
探针，`runtimeOk=true` 是 ABI / engine-info 探针；二者不证明真实 catalog
初始化、磁盘 collection、导入或正式复习用户流已经可用。本次核对发现
`initializeReadOnlyLocator()` 仍跳过鸿蒙，正式复习仍经旧 WebView 文本降级，
且共享回执可在答案未呈现时允许评分。此前「只剩复习器」的推论不成立。

本次修复：真实 catalog 冷启动初始化与课程读取绑定；鸿蒙 RDB 事务显式
begin / commit / rollback、连接隔离和事务错误传播；正式复习统一使用官方
渲染 / 输入答案 / AV 管线，等待卡片身份与代次匹配的渲染回执；关闭脚本时
该管线明确失败，不创建 WebView 或发成功回执；课程卡片
失败时不得完成，切换卡片重置答案确认；共享内容保留 CSS。现有 ArkUI
探针同步修正内层 CSP、CSP 请求见证与媒体 Range/206 判据。

验证记录见 `test/BASELINE.md` 2026-10-13「鸿蒙 Anki 生产调用链修复」。
**仍未验收**：真机导入、课程学习解锁（正式复习 / 评分 / 重启恢复已于 2026-10-14
夜取得收据，见下下节）。「步 5b 仍 Held」与「鸿蒙正式复习必须明确失败」两条
约束已被 2026-10-14 夜的首卡收据取代。伴生版仍不进主交付。

## 鸿蒙步 5b 判据结清：ArkUI `Web` 可满足复习器（2026-10-14）

2026-10-13 批次当时**无连接设备**，因此「鸿蒙复习器能不能做」这个前置问题仍然悬着。
2026-10-14 接上真机（Mate 90 Pro Max / API 26）后，ADR 0050 §3 的**前提 3**
——ArkUI `Web` 能否满足复习器的 CSP + 自定义 scheme + 媒体 Range/206——拿到收据，
**三条子句全部成立**。收据原文与逐条判定见 [ADR 0050](../decisions/0050-ohos-official-anki.md) §3.2。

要点（均可核验，不接受转述）：

- **CSP 不是只看页面自述**：页面报 `cspConnect:"blocked"`，同时**服务端见证**
  `mustNotFetched=false`——那个本该被策略拦下的请求从未到达服务端。
- **自定义 scheme**：`https://anki.local` 经 `onInterceptRequest` 提供，
  shell / css / js / iframe 全部 200，iframe 内联脚本跑通。
- **媒体 Range/206**：内核发 `Range:bytes=0-`，服务端回 206（`Accept-Ranges: bytes`
  + `Content-Range`），`ranged=true`。
- 跑之前先修了**探针自身**的一个缺陷：`probeJs()` 的 `PENDING = 4` 只数四个自动
  检查，判定在加载后约 1.5 秒就上报并终止 ability，人来不及点 `PLAY + SEEK`，
  4b 在实践中不可达（前几轮 `seekPhase` 恒为 `"pending"` 即因此）。改为 `PENDING = 5`。

**一条超出判据的新发现：脚本触发的 `play()` 被拒**（`NotAllowedError`，有手势也一样）。
它**不推翻前提 3**——判据问的是 Range/206 而非能否出声，且真复习器从不让 Web 自己
放音（`card-frame.js` 全文无 `play()` / `autoplay`，只剥离 `<video>` 不剥 `<audio>`），
真正的 AV / TTS 回放由 Dart 侧 `OfficialAnkiAvCoordinator` → `OfficialAnkiAvPlayer`
驱动平台播放器。留下的真实边界：**依赖脚本自动出声的卡片模板在鸿蒙上不会自动播**，
须写入正式页的文档与降级说明。

**当晚后续**：2026-10-14 晚些时候 `OfficialAnkiReviewerStage` 接上 ArkUI 复习页
（先推媒体再呈现，评分走 `wordId` 与翻卡计时，见 ADR 0050 §3.6），**当夜即上机**——
首屏复现 `render_failed`，修复八处接线缺陷后取得首卡全链路收据，5b 就此完成，
见下节。步 6 独立 CI 后于 2026-10-15 落库、首跑收据待取（见下方
「鸿蒙步 6 独立 CI workflow 施工」节）。伴生版仍不进主交付。

## 鸿蒙步 5b 真机首卡收据（2026-10-14 夜）

接上真机（Mate 90 Pro Max / API 26 / HarmonyOS 7.0.0.109）把当天的接线代码第一次
带上设备，首屏即复现 `official_anki.render_failed`，逐轮「构建 → 装机 → 复现 → 定位」
修复**八处**只在真机暴露的缺陷：AV 适配器的 audioplayers 构造崩溃、会话创建与
拦截取值的两处时序竞态、@Entry 页面模块状态隔离（页面与导入方各持一份）、shell
加载编排（显式 `loadUrl` 三种时序全数输给内核驱动）、小资产预热竞态、
`setResponseData` 传 `Uint8Array` 得空响应体、ack 轮询协议接错、以及 ArkTS
`replace` 首处替换语义差导致的轮询解析永败。修复后拿到**首卡全链路收据**：

- 卡 781 问题面经 `https://anki.local/assets/reviewer.html` 完整渲染（官方 shell）；
- 翻卡后 `ack type=renderComplete side=answer`（约 60ms，代次匹配）；
- 评分 `good` 经 `wordId → answerOfficialCard → answerAndConfirm` 落库，
  队列 **781→782→783→784 三次真实前进**；
- 多轮强杀冷启动后复习会话自动恢复到当前卡。

逐条缺陷收据与修复细节以 [ADR 0050](../decisions/0050-ohos-official-anki.md) §3.7 与
`test/BASELINE.md` 2026-10-14「步 5b 真机首卡收据」条为准。**遗留打磨项**
（ability 中途关闭后重开在后台、换卡评分门时序空窗、reveal 状态未随换卡复位）与
**用户流余项**（真机导入、课程学习解锁）不推翻本收据；步 6 独立 CI 后于
2026-10-15 落库、首跑收据待取（见下方「鸿蒙步 6 独立 CI workflow 施工」节）；
伴生版不进主交付。

## 鸿蒙步 6 独立 CI workflow 施工（2026-10-15）

ADR 0047 承诺、ADR 0050 §6 列为唯一余步的**独立 CI workflow** 落库：
`.github/workflows/ohos_ci.yml` + `tool/ohos_ci_prepare.py`。鸿蒙构建仍
不进主 CI（`flutter_ci.yml` 不动）。

链条事实（全部现场查证，非推断）：

- **fork SDK 可按钉克隆**：gitcode `CPF-Flutter/flutter_flutter` 公开
  tag `3.44.9+ohos-0.0.1-canary1` 与本机检出（`git describe` 同名、工作树
  干净）commit 逐一相符；ADR 0047 §7.2 的 autofill shim 是仓库内幂等脚本，
  CI 在 `flutter precache --ohos` 之后 `--apply` 即可复现。
- **引擎工件有官方镜像**：fork README 指定
  `FLUTTER_STORAGE_BASE_URL=https://flutter-ohos.obs.cn-south-1.myhuaweicloud.com`。
- **签名走「键缺席 = 未签名 hap」**：fork 的 `checkOhosSignedInfo` 只拦
  **空列表**，接受键缺席；无 signingConfig 时 hvigor 产出
  `entry-default-unsigned.hap`（DevEco 后置签名流的同款产物）。CI 证明
  目标因此定为「ohos 树可编译打包」，不追签名材料——伴生机构本地的
  DevEco 调试证书进不了 CI。
- **机器本地态由构建自愈**：`ohos/package.json` / `local.properties` /
  ohpm locks 均由 fork 构建过程按当前机器重写，prepare 工具只负责剥
  签名块与剪旧 lock / 依赖树（附括号配平自校验，配错即响亮失败）。

**验证**：`test/ohos_ci_prepare_test.py` 7 例 + 全量 python 套件
60 tests OK；真实 `build-profile.json5` 的内存变换冒烟符合预期且幂等；
官方 SDK `flutter analyze` No issues。见 `test/BASELINE.md` 2026-10-15
「步 6 独立 CI workflow 施工」条。

**首跑收据仍 Held**：DevEco command-line tools 无稳定公开 URL（下载中心
发登录态链接），须先配仓库变量 `DEVECO_CMDLINE_TOOLS_URL`（Linux zip，
与伴生机同代）+ 可选 sha256，或在 workflow_dispatch 时用 inputs 覆盖；
首跑绿之前步 6 不改判为完成。

## 鸿蒙评分回执与按钮互斥修复（2026-10-16）

用户在真机复习中报「四档评分按钮点不动」。归因（见 [ADR 0050](../decisions/0050-ohos-official-anki.md)
2026-10-16 补记）：`rate` 为 fire-and-forget，Dart 侧一切拒绝被 grades 桥折叠成
`false` 后对 ArkUI 页面不可见——与死按钮不可区分。三条路径被证实：§3.7 已记录的
换卡评分门时序空窗与 reveal 未复位（后者使该卡每次点击均 `answer_not_ready`），
以及本日新证实的**末卡队列完结**（评分成功后无 present 换行、Flutter 完成屏被
ability 盖住，按钮从此死在屏上）。

修复双侧落库：Dart `rate` 回复稳定回执码，`answer_not_ready` 自愈翻回问题面并
re-present，`onNativeRated` 改 `Future<bool>`（队列完结→`ok_complete`）；ArkUI
点按即禁用、present 重新武装、重试码恢复 + 状态行、硬失败保持禁用并报码、
`ok_complete` 换入完成行（`Review complete` + `Close`→`terminateSelf`，回到
Flutter 完成屏）。同批给步 6 的 `ohos_ci.yml` 补了 guard 测试单文件 `openharmony`
needle 豁免（该工作区文件此前使 `.github` 禁记扫描先红）。验证与收据口径见
`test/BASELINE.md` 2026-10-16「鸿蒙复习器四档评分按钮『点不动』修复」条
（analyze No issues；全量 2149 passed / 0 failed；**真机复验收据待取**——互斥 /
回执 / 自愈 / 完成行四点均需真机过卡验证；ability 重开在后台的打磨项本批未触碰）。

## 鸿蒙 Official Anki 接线批次步 0–4（2026-10-08，ADR 0050 §6）

> 状态与证据明细以 [ADR 0050](../decisions/0050-ohos-official-anki.md) 为真源
> （§2.1 平台身份收据、§4.1 catalog、§4.2 dlopen、§4.3 静态侧、§6 步表）；本节只记
> 状态变化，**不改变本收据的验收 NO-GO 口径**——该口径约束的是 Android / iOS 生产
> 验收，鸿蒙伴生版不进主交付。

- **步 0（平台身份探针）**：真机 Mate 90 Pro Max（HarmonyOS 7.0.0.109 / API 26）
  确认 `operatingSystem=ohos`、`isHarmonyOsTarget=true`、`Platform.is*` 全 false。
- **步 1（引擎进 hap）**：`libturna_anki.so` 提交进 `ohos/entry/libs/arm64-v8a/`，
  真机 `dlopen=ok abi=1`——证明 API 26 设备可加载；最低 API 18 兼容仍待验证。
- **步 2（共享 catalog）**：`ensureOfficialAnkiSqlite` 分派重写为 `isHarmonyOsTarget`
  短路 + `overrideForAll`，独立 `libsqlite3.so`（SQLite 3.49.2）随 hap 分发；真机
  `catalog=ok sqlite=3.49.2`。新增门禁
  `test/application/anki_official/official_anki_sqlite_dispatch_test.dart`。
- **步 3（平台路由）**：能力矩阵 / `productModeFor` / composition probe 全部放行鸿蒙；
  真机 `runtimeOk=true reason=ready abi=1`。
- **步 4（降级拆除）**：`OhosDegradation.officialAnki` 移除，`degradations` 只剩
  `remoteBackup`；Official Anki 导入入口在鸿蒙上开放。
- **仍 Held**（写作当时）：步 6 独立 CI workflow——后已于 2026-10-15 落库、
  首跑收据待取，见上方「鸿蒙步 6 独立 CI workflow 施工」节。（步 5b ArkTS 保真复习器**已于 2026-10-14 夜
  完成并取得真机首卡收据**，见上方「鸿蒙步 5b 真机首卡收据」节；此前的
  `renderer_ohos_pending` 响亮失败已被取代。）鸿蒙复习器工作量**无估算**
  （ADR 0047 的「5–8 人日」按嵌入式 PlatformView 估，不可引用）。
- **门禁方向反转**：新增断言要求鸿蒙**不得**落进 unsupported 桶（与 ADR 0050 §5
  移除的旧断言方向相反）；`flutter analyze` 0 issue、`flutter test --exclude-tags golden`
  保持 0 failed（逐批收据见 `test/BASELINE.md` 2026-10-07/08 各条）。

---

## 真机 / 模拟器证据台账（截至 2026-09-27）

> 订正记录：本收据早期版本与 Held 表长期写「host 门禁全绿但**无设备会话**」。
> 该表述**已过期**——设备会话发生过两次。逐条如实登记，并标明各自覆盖与
> 未覆盖的范围，避免用「跑通过」推出「可正常使用」。

| 日期 | 平台 / 形态 | 覆盖 | **未覆盖** | 锚点 |
|---|---|---|---|---|
| 2026-09-02 | Android **真机** PLG110，**debug 构建 + v2 flag define** | 写侧链路：导入→账本→视图→删除收敛。硬性能：10 万卡 commit 3.5s、视图重建 2.8s、强杀零数据损伤 | ①**生产 bundle** 未验；②同夜发现 **F6 阻断最基本用户流**（课程树只有一个课 →「无法加载课程」），F6 已修但**修后无真机复跑记录** | `docs/ankiUpdate/v2-first-device-findings.md`（2026-09-02「真机首夜发现分析」） |
| 2026-09-26 | iOS **模拟器** iPhone 17 / iOS 26.5 | 真 .apkg 导入完成 + 复习器 Q→A 渲染 | ①非真机（模拟器）；②未覆盖升级安装 / 备份恢复 / 强杀恢复；③**Android 生产 bundle 仍未验** | `test/BASELINE.md` 2026-09-26「iOS 官方 Anki 栈接通」条目 |

### 关于「Android 可正常使用」的准确口径

**不得写「Android 可正常使用」。** 当前证据只支持下面这句：

> Android **写侧**（导入→账本→视图→删除收敛）曾于 2026-09-02 在真机
> PLG110 上以 debug 构建证明成立；同夜暴露的 F6（进课时「无法加载课程」）
> 已在代码层修复（`lib/application/lesson_viewmodel.dart` 接入
> `OfficialAnkiV2LessonContent.lessonFor()`，有
> `test/application/anki_official/v2/official_anki_v2_lesson_content_test.dart`
> 覆盖），但 **F6 修复后未在任何 Android 设备上复跑**，Android **生产
> bundle** 的完整用户流同样未验。

要合法改写为「可用」，缺的是**一次 arm64 Android 设备上、生产 bundle 的
完整用户流冒烟**：装包 → 导入真 .apkg → 打开课程 → 进入至少一个课时并完成
→ 正式复习答一张。ADR 0044「风险与纪律」已把这条立为唯一完成判据：host
测试、logcat、诊断导出、bugreport **均不构成完成，也不是推进条件**。

---

## 两项固有限制：仍无显式决策（2026-09-27 核对）

> 出处：`docs/ankiUpdate/v2-first-device-findings.md`（2026-09-02）「二、
> 三项固有限制」——原文定性为「修 bug 消不掉，需要显式决策」。
> 2026-09-27 全库核对（`docs/**/*.md` 搜 `限制①/限制②/来源所有权/概率收敛`）
> 结果：**该发现文档自身是唯一命中**，无任何 ADR 或收据章节记录决策结果。
> 即下表两项**至今开放**，不得默认按「已接受现状」处理。

| # | 限制 | 现状（代码实读） | 待决策 |
|---|---|---|---|
| ① | 引擎生命周期耦合 | 视图收敛、决策写入、物理删除、GC 全部排队等引擎打开（引擎懒开，仅 due sync / 复习 / 导入时开）。9-02 实证：10 万卡物理删除在账本 retiring 后**等了数小时**，直到用户下一次导入碰巧开引擎才执行 | 二选一：启动时见 v2 active 源即主动开引擎（收敛变保证）／ 接受概率收敛并写入设计文档（含用户可见后果） |
| ② | 共享 collection 上的来源所有权 | 数据面已齐：`OfficialAnkiImportLog` 含 `newNoteIds`/`duplicateNoteIds`/`conflictingNoteIds`。**策略面缺失**——`conflictingNoteIds` 全库**无人消费**，`OfficialAnkiV2ImportService.commit` 只读 `newNoteIds` 与 `duplicateNoteIds` 两个计数 | 定一条重导 / 同 GUID 策略（拒绝 + 明确 UI，或所有权转移规则），写进 ADR |

**限制③（双代并存）已消解**：v1 已整体退役——`lib/**/*.dart` 内
`v2ImportChain` 0 处、`IAnkiNoteStore` / `AnkiNoteDao` / `legacyMirror`
0 处（2026-09-27 全库计数核验）。**F6（课时正文装载）已修**，
回归由 `official_anki_v2_lesson_content_test.dart` 承担。

---

## Done（本收口有仓库证据）

### 2026-08-25 一次性施工（ANKI-CUTOVER-ONE-SHIP host 门禁）

| 项 | 证据 |
|---|---|
| R0 schema 9 回归 + 基线止血 | backup/restore 测试改读 `kSchemaVersion`/`kOfficialAnkiCatalogSchemaVersion`；`git diff --check` 0；native pin 验证 + so 重建（cutover-once/） |
| R1 CourseScope / 课程目录 / 精确卸载 | `CourseScope` codec v1 + `CourseCatalog`（authority+manifest）+ builtin 双隔离 + `anki:src` 歧义修复 + 顶栏课程名 + 导入三动作分流 + 完整 sourceId 卸载 |
| R2 保真实时复习 + Review All | fidelity-first 渲染、`OfficialFormalReviewLiveQueue`（Scheduler current 驱动、Again 重插、快照 generation）、`FormalReviewSourceCoordinator` 顺序消费 Legacy + Official 混合 owner并聚合失败、Redo/Bury/Suspend |
| R3 六集合 Due repository | `OfficialFormalDueRepository`（known/unknown/unavailable、stale generation、rollback、retired reader）；`OfficialAnkiHomeDue` 薄 facade、officialDue 派生 |
| R4 write fence + 权威 owner 事务 | `LegacyWriteFence` 全 mutator 围栏（intent/token/rollback phase）；`anki_owner_transitions` + `commitOwnership` 同库原子；生产 migration center/coordinator；commit 后 catalog mirror/smoke 失败只向前恢复，已提交 owner 拒绝 rollback |
| R5 Browser/Stats 产品入口 | Official 牌组 Browse/Stats 按钮可达，完整 sourceId 路由，无 Legacy 回退 |
| R6 导入 commit-last | authority staging 起始、`publishFromProjection` 后 visibility active；Legacy UI mutation 抽入 application executor，identity 与 CourseDB 同事务；同 ID 重导媒体 staging/原子换目录，并通过 incoming/committed hash 在启动时恢复强杀窗口；向导不抢 scope |
| R7 Android turna-migration-v1 导入器 | `TurnaMigrationImporter`（fail-closed 校验/事务/Legacy 行只入 pending）+ 设置页独立入口；export→import 往返测试 |
| R8 路由守卫 + 门禁 | `DiagnosticsReleaseGuard`（release+深链）；analyze 0 issue、全量 1852/0、golden 4/4、native 68/68、arm64 APK 56.1MB；APK 内验证 contract 1.6 新操作（sha256 见 cutover-once/apk-sha256.txt） |

### 2026-08-24 及更早（原 Done 表）
|---|---|
| W0 原子导入计划 / Legacy 新写 fail-closed | `AnkiImportExecutionPlanner` + 向导 `_plan` 贯穿 pick/commit；Official-first 不得写 Legacy NoteStore；flag-off / `legacyMirror` fail-closed 零写入 |
| C3 Official-first 编排抽出 | `OfficialAnkiOfficialFirstService` 承载 saga / migration / preview / publish；向导只做 step UI 与 mapping。向导仍约 3400 行（C3 remainder：Legacy preview 未拆） |
| C5 死路径 | `officialFirstImportEligible` / `official_first_import_policy.dart` / `OfficialAnkiUserMigrationSaga` 已删；迁移预览无 stub cutover 按钮；用户可见 HarmonyOS 文案改为「仅旧版导入源」 |
| C4 配置面坍缩 | `OfficialAnkiFeatureFlags.fromEnvironment` 不再读 10 个能力 dart-define，生产 bundle 恒为 Official Android；**opt-in dart-define 仅剩 2 个**（`TURNA_OFFICIAL_ANKI_REVIEWER_DIAGNOSTICS`、`TURNA_OFFICIAL_ANKI_COURSE_GRADES_SCHEDULER`，见 `official_anki_feature_flags.dart` 类注释与 `fromEnvironment`）；`TURNA_OFFICIAL_ANKI_DIAGNOSTICS` 是 release 诊断路由守卫而非本类字段；`TURNA_OFFICIAL_ANKI_CUTOVER` 是 `LegacyAnkiMigrationFlags.cutoverEnabled` 暂停闸。（早期版本记录的 `migrationPilot` / `legacyMirror` 两个 opt-in flag **不存在**于当前类，已随 Legacy 退出一并消失。）Gray cohort 已退出 planner。`officialCapable` 改名为 `schedulerRuntimeAvailable`，不再冒充 owner。 |
| W8 可恢复单来源 Saga（§12.4） | `OfficialLegacySourceMigrationSaga` + `OfficialLegacyMigrationDriver`（census `cleanLegacy` 入队；需用户确认调度策略，启动不自动切 owner） |
| W8 调度策略用户可见三选一（禁止静默 reset） | `LegacyAnkiSchedulingPolicy` + `userVisibleLabel/Description`；无 lossless map 时要求 `policyConfirmedByUser` |
| W8 journal resume / rollback 单测 | `test/application/anki_official/official_legacy_source_migration_saga_test.dart`；输出 `/tmp/grok-goal-69bb594208d5/implementer/migration-legacy-retirement.txt` |
| W9-A（停住 Legacy 新写产品选择） | W0 fail-closed + architecture guards；W9-A 门槛与证据见本收据「W9 HOLD 解除记录与证据台账（2026-08-27）」一节 |
| W9 §13.3 CI 门禁补强 | `anki_unification_architecture_guard_test.dart`（doc 35 L3 后更名 `official_anki_architecture_guard_test.dart`）：planner/`legacyOnly`、Official 禁 `ensureWord/updateReview`、unsupported platform 指针；doc 35 施工后追加 L0–L2 反复活断言 |
| W9 物理删除 HOLD 书面落盘 | 原文件 `34-w9-legacy-deletion-hold.md`（2026-08-24 落盘）—— 已于 2026-09-27 并入本收据「W9 HOLD 解除记录与证据台账」一节并删除（负责人决策 D1） |
| W10 文档入口收口 | 本目录 `README.md` 以 doc 34 为唯一活跃施工入口；31/32/33 标注由 34 接管 |
| W3 census / reconciler + journal | 分类器 + `JoinedOfficialAnkiSourceEvidenceReader`（Drift ∪ catalog，按 hash/id）；`OfficialAnkiStartupCensus` 启动只读 collect + journal `scanned`（幂等）。**不**自动改 owner |
| W5 基础骨架（非产品验收） | 共享 host 已能调用 `showAnswer` 并提交 Official scheduler；但 formal review 仍有 HTML 降级、固定队列 stale、Review All 单来源和六集合 due 缺口，返工见 remaining R2/R3 |
| W6 course = practice/introduction | `AnkiStudySessionHost.itemForCourse` + `official_course_practice_introduction_test.dart` |
| OHOS product target / patches removed | ~~`ohos/` absent~~ **（2026-10-07 订正为失真）**：`ohos/` 自 [ADR 0047](../decisions/0047-ohos-companion-lite-build.md)（提交 `8ab24246`）起作为**伴生版**存在；`tool/apply_patches.sh` / `tool/patches/` absent 仍然成立 |
| OHOS EOL ADR | [ADR 0041](../decisions/0041-ohos-product-eol.md)（§决策 2 已被 [ADR 0050](../decisions/0050-ohos-official-anki.md) 作废） |

## W9 HOLD 解除记录与证据台账（2026-08-27）

> 本节由原独立文件 `34-w9-legacy-deletion-hold.md`（2026-08-24 落盘）**并入**（2026-09-27，负责人决策 D1）。
> 该文件此前被 7 处文档记为「随解除删除」，实际一直留在库中且状态头自相矛盾；本次按决策正式并入本收据并删除原文件，**内容按原文保留，不做弱化**。

### W9-A — 停住 Legacy 新写的产品选择（已由 W0 基本满足）

| 项 | 状态 | 证据 |
|---|---|---|
| 生产新导入不再选择 Legacy writer | **满足** | `AnkiImportExecutionPlanner`（`lib/application/anki_official/import/anki_import_execution_plan.dart`）：`officialAndroid` 下无 `allowLegacyOnly` 时只返回 `officialFirst` / `failClosed` / `unsupported`，从不静默 `legacyOnly`（见 `test/application/anki_official/anki_import_execution_plan_test.dart`） |
| 非 Android / cutover 关闭 → Anki 不可用 | **满足** | 同上；`AnkiProductMode.ankiUnavailable` 不写 Legacy NoteStore |
| Official-first 能力关闭时 fail-closed | **满足** | 测试用构造器/`copyWith(officialFirstImport: false)`；生产 `fromEnvironment` 不再读独立 dart-define。不再出现「Legacy NoteStore + Official identity」混合半态 |
| 架构门禁：planner 不在生产路径返回 `legacyOnly` | **本会话补齐** | 架构守卫测试 + 既有 execution plan 测试 |
| Official 树不调用 `SrsProvider.ensureWord/updateReview` | **本会话补齐** | 扫描 `lib/application/anki_official/**` |

W9-A 含义是：**停住 Legacy 新写入口的产品选择**，不是物理删文件。物理移除该入口属于 W9-C（HOLD 已于 2026-08-27 解除，可开工）。

### W9-B..E 门槛记录（解除时点的原始状态）

| 波次 | 内容 | 进入条件（解除时点状态） |
|---|---|---|
| W9-B | 删除 Turna FSRS 对 Anki 的 writer、Legacy formal review assembler | 正式 release 观察 + Legacy 新写=0（**未发生，2026-08-27 负责人决策豁免**） |
| W9-C | 删除 Dart production `.apkg` parser、Legacy import 分支、活动 NoteStore | 同上；migration-only exporter 可暂留 |
| W9-D | 删除 Legacy browser/stats 分支与死 DI | 同上 |
| W9-E | Schema tombstone → major schema drop | **先 stop-write 至少一个版本**，再 drop；需备份恢复能读上一版本（**此为 §13.2 硬规则，不随 HOLD 解除而豁免** —— 该条款实际被绕过，见下方「W9-E 破例记录」） |

### 解除 HOLD 所需书面证据（最少）

1. 正式 release 的 build id / Git commit / 商店或内发版本号；
2. 该版本周期内 Legacy 新导入 / NoteStore 写入计数 = 0 的日志或遥测摘要；
3. W8 存量来源已 `cleanOfficial`、已导出/只读隔离、或有明确用户处理状态；
4. rollback / restore / uninstall drill 收据；
5. 本节追加「G5 GO」签字与日期后，方可开 W9-B PR。

### G5 GO 解除记录（2026-08-27）

> **HOLD 已解除。** 解除方式：项目负责人显式指令（2026-08-27，经 agent 会话落盘）。本节即上文第 5 项要求的「G5 GO」签字与日期。

#### 证据台账（解除时点的仓库内事实）

| # | 所需书面证据 | 解除时状态 |
|---|---|---|
| 1 | 正式 release 的 build id / commit / 版本号 | **缺失** — 仓库无 0.7.2 release tag；CHANGELOG 0.7.2 仍标注「候选版本，正式发布以最终验收结果为准」 |
| 2 | Legacy 新导入 / NoteStore 写入计数 = 0 的观察摘要 | **未发生** — 观察期未开始，无遥测/日志摘要归档 |
| 3 | W8 存量来源 cleanOfficial / 隔离 / 有处置结论 | **未跑批** — saga/driver 已落地，未对真实用户库执行 |
| 4 | rollback / restore / uninstall drill 收据 | **缺失** — 无真机会话 |
| 5 | 本节「G5 GO」签字与日期 | **本节即是**（负责人指令，2026-08-27） |

**定性**：本次解除是**负责人风险豁免决策**，不是证据齐备的自然解除。第 1–4 项外部事实在解除时点均未发生；若后续出现 Legacy 写入回退、存量数据迁移失败或备份不兼容，责任口径以本记录为准。

#### 解除范围与仍然有效的约束

- 解除的仅是 **W9-B / W9-C / W9-D 的开工门槛**；
- 主计划 §13.2 删除规则**全部继续有效**：每波先以 `rg` + 依赖图证明生产引用为 0；每波独立 PR、独立回滚；schema 不与 writer 删除同一 PR；**W9-E 仍须先停写至少一个版本再 drop**，且 drop 前备份恢复必须能读上一版本数据并完成升级 —— **该条款已被实际执行方式绕过，见下方「W9-E 破例记录」**；
- 存量迁移义务不因解除消失：W8 单来源 saga、调度策略用户三选一、owner 切换 commit 前 rollback 边界照旧执行；
- 本解除**不**勾选主计划 §19 任何未满足项；「Official Anki 迁移中 / 验收 NO-GO / 不得写迁移完成」的口径不变。

### W9-E 破例记录（2026-09-24，负责人决策 D2）

**规则原文**：主计划 §13.2 与上表 W9-E 行均要求「**先 stop-write 至少一个版本，再 drop 表**」，且不随 HOLD 解除而豁免。

**实际执行**：2026-09-24 架构简化批次 P2 在 **course.db v27 的同一次迁移中直接 DROP** `anki_notetypes` / `anki_notes` / `anki_cards_meta`（见 `lib/data/course_database.dart` v27 迁移段与本收据「架构简化批次」P2 条目），**中间没有插入任何正式发版**。即：规则要求的前置条件未被满足，而 drop 已发生。

**豁免依据**：本收据「架构简化批次」开篇已核对——**存量用户数为零、从未有过任何正式发版**，因此「停写至少一个版本」这一前置条件在物理上没有可作用的对象。v27 的备份/恢复兼容性仍待真机矩阵验证（见「Held」表），该风险未被本条记录消除。

**责任口径**：本次 drop 绕过自身声明的硬规则，属**负责人决策豁免**（与 2026-08-27 的观察期豁免同族、但**独立记录**）。若后续出现 v26 数据无法被 v27 读取、备份不兼容或升级链断裂，责任口径以本记录为准。

> **签字**：<待负责人填写 —— 认可该破例 · 姓名 / 日期>

## Held（不得在本会话勾选完成）

> 2026-08-25 更新：原 Held 表中 Course scope、正式复习保真、Review All、六集合 due、W8 owner cutover、Browser/Stats 入口、Android 迁移包导入七项的 host 侧实现已由一次性施工关闭（见上表）；下表为**仍 Held** 的项。
>
> **2026-09-27 订正**：原「release 真机矩阵」行写「host 门禁全绿但**无设备会话**」——该表述**已过期**。设备会话发生过两次（2026-09-02 Android 真机 PLG110、2026-09-26 iPhone 17 模拟器），各自覆盖与未覆盖范围见上方「真机 / 模拟器证据台账」。两次会话**均不覆盖** release 矩阵，故该行仍 Held，但原因由「无会话」订正为「会话范围不足」。

| 项 | 原因 |
|---|---|
| 一个正式 release 观察（G5） | 未发生；2026-08-27 负责人决策按豁免处理（非证据齐备，见 HOLD 解除记录） |
| W9-B..E Legacy 物理删除 / schema drop | host 侧已由 2026-09-24 架构简化批次完成（读退役 + v27 表删除，见上方批次记录）；**W9-E 的「先停写一个版本再 drop」硬规则未满足即执行，破例已记档**（见本收据「W9-E 破例记录」）；真机验证仍随设备矩阵 |
| §19「Legacy importer/scheduler/schema 按 W9 分波删除」 | 显式未勾选 |
| 全量设备/release 真机闭环证明 | 已有两次设备会话（2026-09-02 Android 真机 / 2026-09-26 iOS 模拟器），但均不覆盖 release 矩阵；本会话未伪造设备证据 |
| **Android 生产 bundle 完整用户流冒烟** | **2026-09-27 新增。** 9-02 PLG110 只验了 debug 构建的**写侧**，且同夜 F6 阻断「进一个课时」；F6 修后未复跑、生产 bundle 未验。缺：装包 → 导入真 .apkg → 开课程 → 进至少一个课时并完成 → 正式复习答一张 |
| **iOS 真机（非模拟器）验证** | **2026-09-27 新增。** 现有 iOS 证据为 iPhone 17 模拟器 E2E；模拟器不替代真机验收 |
| **限制① 引擎生命周期耦合 · 显式决策** | **2026-09-27 新增。** 收敛时机仍为概率性（9-02 实证 10 万卡删除等了数小时），既无「启动即开引擎」策略，也无「接受概率收敛」的设计文档 |
| **限制② 共享 collection 来源所有权 · 显式决策** | **2026-09-27 新增。** `conflictingNoteIds` 全库无人消费，v2 提交只读 new/duplicate 两计数；重导 / 同 GUID 策略缺失 |
| OHOS 用户完成数据出口 | 导出器/导入器均已落地（Android 导入入口可用）；外部事实未发生：无 sunset 真机、无书面豁免（R7-1 二选一未决） |
| release 真机矩阵（干净安装 / 升级安装 / 迁移包） | 两次已有会话均未覆盖（9-02 未验安装形态，9-26 为模拟器）；host 门禁全绿不能替代（ADR 0044：logcat / 诊断导出 / bugreport 均不构成完成） |
| 真机 reimport / Browser/Stats/Media / 强杀恢复验证 | 同上，待设备矩阵 |
| 存量用户跑批 / owner 切换 | W8 driver 可入队 `cleanLegacy`；未对真实用户库执行 |
| OHOS 树物理删除 | ~~已完成（`ohos/` absent）~~ **（2026-10-07 订正为失真）**：`ohos/` 已由 ADR 0047 恢复为伴生版，物理删除从未在当前树成立；历史 archive 保留 |
| 鸿蒙 Official Anki | **已授权；接线步 0–5b 已施工（步 0–4：2026-10-08，见上方「鸿蒙 Official Anki 接线批次」节；步 5b：2026-10-14 夜，见上方「鸿蒙步 5b 真机首卡收据」节；[ADR 0050](../decisions/0050-ohos-official-anki.md)）**：引擎 / 内存 SQLite / 平台路由 / 降级拆除有真机探针收据（`dlopen=ok`、`catalog=ok sqlite=3.49.2`、`runtimeOk=true reason=ready`、`degradations=remoteBackup`、`catalogLocatorReady=true`）；2026-10-13 补修真实 catalog、RDB 事务和正式复习接缝；2026-10-14 夜步 5b 真机首卡收据——渲染 / 翻卡 / 评分落库 / 队列前进 / 强杀恢复全链路走通，八处接线缺陷已修（ADR 0050 §3.7），`productModeFor('ohos')` → 官方档。**仍 Held**：步 6 首跑收据（workflow 已于 2026-10-15 落库，见上方「鸿蒙步 6 独立 CI workflow 施工」节；需配 `DEVECO_CMDLINE_TOOLS_URL` 仓库变量后首跑）；用户流余项（真机导入、课程学习解锁）与遗留打磨项（ability 重开在后台；换卡评分门时序空窗与 reveal 复位已于 2026-10-16 代码修复、真机复验收据待取，见上方「鸿蒙评分回执与按钮互斥修复」节）；伴生版不进主交付 |

## Android ABI packaging

Doc 34 §14.2 option 1: **arm64-v8a only** for Official native (`libturna_anki.so`).
Release command: `flutter build apk --release --split-per-abi --target-platform android-arm64`.
A fat multi-ABI APK without matching `.so` is forbidden (fail-closed, never Legacy fallback).

## Accurate status line

> 验收 NO-GO；Official Anki 迁移中。**代码收口已完成**：R0–R8 host 侧一次性收口全绿，2026-09-24 架构简化 P0–P4（Legacy 读退役 / course.db v27 / 备份互斥）落地，2026-09-26 iOS 官方 Anki 栈接通，首发平台为 **Android arm64 + iOS** 同一条 Official 生产路径；全量 `flutter test` 1938 passed / 2 failed（2 例为 HEAD 既有 `course_tree` golden 本机失配）。**设备证据已有两次但范围有限**：2026-09-02 Android 真机 PLG110（debug 构建，写侧成立，硬性能 10 万卡 commit 3.5s / 视图重建 2.8s / 强杀零损伤；同夜 F6 阻断「进一个课时」，已修但**修后无真机复跑**）；2026-09-26 iPhone 17 模拟器（真 .apkg 导入 + 复习器 Q→A，实测修 2 个真运行时 bug）。**尚未验收**：Android 生产 bundle 完整用户流、iOS 真机、release 真机矩阵（干净/升级安装/迁移包/备份恢复/强杀恢复），以及外部事实（OHOS sunset/豁免、存量用户处置、Legacy 零新写观察期）。**两项固有限制至今无显式决策**：①引擎生命周期耦合（收敛概率性）、②共享 collection 来源所有权（`conflictingNoteIds` 无人消费）。**不得写「迁移完成」，不得写「Android 可正常使用」**——后者缺一次 arm64 Android 设备、生产 bundle 的完整用户流冒烟，判据见 ADR 0044「风险与纪律」与本收据「真机 / 模拟器证据台账」。
