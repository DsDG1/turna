# 测试基线收据

> 本文件只保留最近批次的测试基线。更早的批次在 git 历史里（`git log -- test/BASELINE.md`）。
> 引用收据用「文件 + 条目日期 + 标题」三段锚，禁止行号。

## 最近批次

---

### 2026-10-22 记忆卡适配：真实端点打通（凭据不入库）

- **性质**：验证批次 + 两个真实缺陷修复；**测试数 +1**（`ai_card_adaptation_service_test` 9 → 10 条）。
- **怎么测的**：新增 `tool/live/ai_adaptation_live_smoke_test.dart`（不在 `test/` 下，默认测试集与 CI 都不会跑到）。凭据路径走环境变量 `TURNA_LIVE_CREDENTIALS`，仓库里不出现个人路径、更不出现凭据；结果摘要写到 `build/live_adaptation_smoke.log`（不入库），日志里把 key 替换成 `***`。测试内部先发一次最小探针请求看真实错误，再走 `AiCardAdaptationService` 全链路。
- **真实端点暴露的两个缺陷**：①**合规回复被误判成 `not_json`**——协议明确让模型不要给 `scope`（由应用附加），而 `CardAdaptationPlan.fromJson` 要求 `scope`，于是模型越守规矩越失败。现在解析时用调用方事实补 `scope`，随后仍由 `_withFactsScope` 覆盖。②**默认输出预算对推理模型不够**——`maxTokens: 1200` 在 MiniMax-M3.1-Flash 上把 thinking（实测约 9k 字符）和正文一起截断，返回空内容 + `finish_reason=length`，被正确地判成终态 `truncated`，但等于适配永远不可用。默认改为 4000。
- **顺带补齐**：`AiJsonSchemas.cardAdaptation` 与 `outputProtocol` 增加 `defaultExercise`（此前模型无从表达「这组做听写」，只能落到 flip）。
- **验证**：真实端点一次调用 → `outcome=accepted`，`revalidation_ok=true`，`blocks=front:2,back:2`，`bindings={prompt:0,answer:1,audio:2,image:3}`，`repaired=false`；`flutter analyze lib test` **No issues found**；`flutter test --exclude-tags golden` **2433 passed / 0 failed**。
- **未验**：仍未经 app 内路径（设置里配 key → 预览页生成）验证；一台设备都没有，真机链路、鸿蒙 HAP、Rust 抽样三项外部阻塞不变。凭据只在本机会话外的一次测试中使用，**未写入仓库任何文件**。

---

### 2026-10-22 记忆卡适配：撤销已生效方案的 UI 入口

- **性质**：功能批次；**测试数 +6**（新增 `adaptation_restore_sheet_test` 6 条）。
- **改动**：①新增 `views/anki_official/components/adaptation_restore_sheet.dart`：来源级「显示方式」面板，读 manifest 列出当前生效的 scope（`notetype:template[:cloze]` → 「笔记类型 X · 模板 Y」），支持逐组或全部恢复原卡。恢复只调 `deactivate` / `replaceManifest`，**不碰卡片内容、不碰排期**（plan §12.4）。②课程管理页的溢出菜单新增「显示方式」项，只在官方来源上出现；面板关闭后如有变更提示一次「已恢复原卡显示」。③面板本身不碰引擎：`loadManifest` / `restoreScope` / `restoreAll` 由调用方注入，因此可以在没有引擎的测试里验证「恢复失败不得显示成已恢复」「空清单显示空态」「坏 scope 键原样显示」。
- **验证**：`flutter analyze lib test` **No issues found**；`flutter test --exclude-tags golden` **2432 passed / 0 failed**；断言覆盖按标签列出 scope、逐组恢复后该行消失而其它行保留、失败保留该行、全部恢复后转空态、无方案空态、坏 scope 键原样显示。
- **未验**：面板背后的 `deactivate` 只切 manifest，**真实课时里的展示变化要靠重进课时重新派生**（目前没有主动刷新）；单卡覆盖（`writeCardOverride`）仍无 UI 入口；外部阻塞（设备 / Rust 抽样 / 鸿蒙 hvigor）不变。

---

### 2026-10-22 记忆卡适配：全量自检（接线补口 + 去重 + ADR 对账）

- **性质**：审计与修正批次；**测试数 +1**（`official_anki_architecture_guard_test` +1 条）。
- **发现并修掉**：①**卸载不清适配命名空间**——`AnkiDeckManager._uninstallV2Source` 只 retire 账本与卡片，`turna.adapt.*` 四个键族会永久残留。现在在 `beginRetire` 之后、引擎删除之前调用 `deleteSourceNamespace`；引擎缺席时记一条告警（配置区删不了），且这条清理**不得挡住 retire**。②两处死代码：`AnkiImportAdaptationDrafts.clearScope` 与 `OfficialAnkiRoleValues.allAudio` 无调用方，删除。③「不支持结构」的判定此前有两份几乎相同的正则（`card_document_builder` 与 `projection_payloads`），合并为 `cardCarriesUnsupportedStructure` 单一实现，payloads 侧改为委托——两份清单正是漂移的源头。④ADR 0057 与实现的对账：键名改成实际的 `r<revision>`；单卡覆盖改成实际的「按来源一张小表」；块类型改成实际实现的四种（text / richText / imageGroup / audioGroup），视频与容器组明确标为后续增量；协议示例的 `bindings` 改成扁平「角色 → 序号」、`exercisePolicy` 改成 `defaultExercise` + `optionalExercises`、去掉没有实现的 `guards` 与 `visualFacts`；并写明 `fallback` 目前只接受 `original`。
- **验证**：`flutter analyze lib test` **No issues found**；`flutter test --exclude-tags golden` **2426 passed / 0 failed**；新守卫断言「retire 先于清理、且引擎缺席有告警」；`docs_hygiene_test` 绿。
- **未验**：卸载接线只有静态守卫 + store 级测试，没有走 `AnkiDeckManager` 的集成测试（构造它需要 repo / importDao / appPrefs 与组合根，成本高于本轮价值）；`deactivate` 与 `clearCardOverride` 仍只有测试调用——**线上还没有「取消已生效方案」「单卡覆盖」的 UI 入口**，属 P6 未完成的用户路径。

---

### 2026-10-22 记忆卡适配：可解释性落地 + 架构叙述入 guide

- **性质**：功能 + 文档批次；**测试数 +1**（`smart_adaptation_panel_test` 6 → 7 条；该文件此前的一条断言扩展了具体原因文案）。
- **改动**：①`AppStrings.presentationReasonLabel`：把解析器的 14 个 `PresentationReason` 逐条译成中文解释（「必填字段被截断，无法证明内容完整」「媒体的正反面归属无法确认」等），界面不再只能显示一句笼统失败。②补齐枚举里确实缺的两个原因：`planMissing`（manifest 引用的修订缺失）与 `unsupportedStructure`（脚本/表格/内嵌媒体这类渲染不了的结构），并在课时派生里按实际情况计数。③`SmartAdaptationPanel` 被本地拒绝时列出前两条具体原因（新增 `_issueLabel` 覆盖 14 个 `AdaptationIssue`）。④课时派生按原因聚合一次写日志（只记枚举名与次数，不记字段内容），ADR 0057 §9 的「可解释」从契约变成可观测。⑤`docs/project-guide.md` §6.1 新增架构叙述：单一解析器、配置区四键族与激活协议、按面媒体与 `CardDocument` 布局、AI 输入预算与本地校验、新练习 opt-in、正式复习首期原卡。
- **验证**：`flutter analyze lib test` **No issues found**；`flutter test --exclude-tags golden` **2425 passed / 0 failed**；`docs_hygiene_test` 绿；新断言：每个 `PresentationReason` 都有非空中文标签且不含专名、被拒方案显示具体原因（`答案会出现在题面`）。
- **未验**：原因文案只覆盖「方案被拒」与日志聚合两处；课时页面里还没有面向用户的「为什么这张卡是原卡」入口。外部阻塞（设备 / Rust 抽样 / 鸿蒙 hvigor）不变。

---

### 2026-10-22 记忆卡适配：方案布局真正参与渲染（CardDocument）

- **性质**：功能批次；**测试数 +9**（新增 `card_document_builder_test` 6 条、`official_anki_projection_payloads_media_test` +2 条、`official_anki_v2_lesson_content_test` +1 条）。
- **改动**：①新增 `application/anki_import/adaptation/card_document_builder.dart`：把方案的 `front` / `back` 有序块合成「每面文本 + 该面音频 + 该面图片」——`text`/`richText` 取字段纯文本并按块序换行拼接，`audioGroup`/`imageGroup` 按 `selection`（all / first）取该字段的媒体 occurrence。②块点到不存在的字段、或点到脚本/表格/内嵌媒体这类渲染器表达不了的结构时，`CardDocument.unsupported = true`，调用方整张卡回原卡，**不渲染半份布局**。③`OfficialAnkiRoleValues` 增加 `document`；`values(row, mapping, plan: …)` 在方案生效时构建它。flip 载荷在文档在场时由文档接管文本与四类按面媒体，legacy 全量表清空。④课时派生把方案传进 `values`，`unsupported` 直接走 `canonicalLink`。
- **验证**：`flutter analyze lib test` **No issues found**；`flutter test --exclude-tags golden` **2424 passed / 0 failed**；断言覆盖按面块归属（文本/图片/音频各归其面）、`selection=first`、多文本块按序拼接、越界字段 unsupported、脚本块 unsupported、无块时不生成文档、方案接管时不再退 legacy 全量表、课时里 unsupported 布局回原卡。
- **边界（已写进 ADR 0057 §5）**：这一版**只决定内容落在哪一面**，不做同一面内「文本—媒体」交错排版；flip 渲染器先文本后媒体，真正的交错版面需要独立的卡片文档渲染器，属后续增量。外部阻塞（设备 / Rust 抽样 / 鸿蒙 hvigor）不变。

---

### 2026-10-22 记忆卡适配 P4/P6 补口：方案真的换题型、绑定真的生效

- **性质**：功能批次；**测试数 +2**（`official_anki_v2_lesson_content_test` +2 条）。
- **改动**：①课时派生里 `values` 的取值时机修正——此前先用原始映射算出 values，再为解析器套上方案（只影响 kind），于是 `plan.bindings` 永远进不到正面/背面文本里。现在先查方案、再用「方案绑定 + 方案练习范围」构造映射重新取值，绑定才算真的生效。②新增 `_withPlanBindings`：把方案的 `prompt` / `answer` / `pronunciation` / `example` / `audio` / `image` / `options` 绑定覆盖到候选角色上（confidence 1 + `plan` 证据），没被方案绑定的角色继续沿用识别结果。
- **验证**：`flutter analyze lib test` **No issues found**；`flutter test --exclude-tags golden` **2415 passed / 0 failed**；两条新断言：方案 `defaultExercise: dictation` 时，带正面音频的卡真的产出 `Dictation`（`expected = merhaba`、`audioAssets = ['merhaba.mp3']`），而同组没有正面音频的卡回落 `AnkiCard`；方案把 `prompt` 绑到字段 1 时，翻卡正面变成释义（`你好`）、背面是词条（`hello`）。
- **未验**：布局块（`front` / `back` 的有序 block）仍只做校验与存储，**没有驱动渲染**——真正的 block 渲染（`CardDocument`）还没做，本轮让绑定生效不等于布局生效。设备、Rust 抽样、鸿蒙 HAP 三条外部阻塞不变。

---

### 2026-10-22 记忆卡适配 P8 收尾：升迁流程抽成可测单元 + 鸿蒙构建受阻

- **性质**：重构 + 验证批次；**测试数 +5**（新增 `adaptation_promotion_flow_test` 5 条）。
- **改动**：①把提交期升迁从 `anki_import_official_flow.dart` 的私有函数抽成 `application/anki_official/v2/adaptation_promotion_flow.dart` 的 `promoteAdaptationDrafts(live:, sourceId:, plans:)`：live 为空 → 空报告；`plans` 为空 → 零引擎调用；projection schema 读取异常 → 吞掉并记日志（此时导入已经提交成功）；schema 没有模板事实 → 该组按 `missingTemplate` 跳过，绝不猜序号。②flow 改为调用该函数，行为不变，但这条链路现在能脱离整个 commit 流程单独验证。
- **验证**：`flutter analyze lib test` **No issues found**；`flutter test --exclude-tags golden` **2413 passed / 0 failed**；5 条新断言覆盖无 live 引擎、无草稿时零调用、schema 抛错可吞、无模板事实跳过、有模板事实时升迁在 live 生效。
- **未验**：**鸿蒙 HAP 构建失败（环境问题）**。把 DevEco 的 `hvigor` / `ohpm` 加进 PATH 后 `flutter build hap --debug` 已能启动 hvigor（`flutter doctor` 显示两者就位），但停在 `hvigorconfig.ts / hvigorfile.ts` 解析错误、`0 task executed`——本机全局 hvigor 版本与仓库的 `modelVersion 5.1.0` + `flutter-hvigor-plugin` 依赖不匹配。这既不是本轮代码问题，也没有被绕过验证，故如实记为未验。

---

### 2026-10-22 记忆卡适配 P7 + P8 出包：正式复习维持原卡 + APK 构建

- **性质**：功能批次 + 交付批次；**测试数 +4**（`official_formal_review_fidelity_test` 4 → 8 条）。
- **改动（P7）**：①正式复习的 flip 面按 `renderCard` 的 AV 事实恢复媒体（`formalReviewFlipMedia`）：`soundOrVideo` 标签且文件名带音频扩展名才成为音频 occurrence，面归属直接用官方给的正/背标签，路径段剥成 basename；TTS 标签不伪装成文件，视频不在本阶段支持集，缺文件名的标签也不是媒体。此前纯文本卡在正式复习里会把 `[sound:]` 丢掉——「原卡优先」不等于「原卡音画可以消失」。②fidelity 分支不变（WebView 渲染原 HTML 与媒体）。③**首期正式复习恒原卡**变成可执行断言：即使 live 配置区已有生效方案，正式复习也不读配置区（`getConfigCalls == 0`）并继续返回 Fidelity/Flip，绝不产出结构化练习。
- **改动（P8）**：`flutter build apk --debug` 出包成功（`build/app/outputs/flutter-apk/app-debug.apk`，194.8 MB），`docs/status.md` §4 追加一条 Held：适配端到端未验（无设备、AI 未打真实端点、分层抽样未实现）。
- **验证**：`flutter analyze lib test` **No issues found**；`flutter test --exclude-tags golden` **2408 passed / 0 failed**；新断言覆盖按面音频（含 `../../` 路径剥名）、TTS/视频/缺文件名的排除、方案存在也不改变正式复习、正式复习永不返回 `StructuredCardPresentation`。
- **未验 / 未完**：正式复习**没有接入统一解析器**——首期的正确行为就是恒原卡，接上解析器需要先明确接受哪些「语义等价布局」，属独立产品决策（plan §14 P7 前置）。APK **未安装到任何设备**（`adb devices` 为空、`hdc list targets` 为空）；鸿蒙 HAP 未构建；AI 请求未打真实端点；分层抽样仍缺 Rust 工具链。

---

### 2026-10-22 记忆卡适配 P6c：导入预览的智能适配入口 + 草稿随提交落库

- **性质**：功能批次；**测试数 +10**（新增 `smart_adaptation_panel_test` 6 条、`official_anki_adaptation_promoter_test` 的 in-session 组 4 条）。
- **改动**：①新增 `AnkiImportAdaptationDrafts`（scopeKey → plan，`ChangeNotifier`）：方案只在**会话内**暂存，不写 staging collection——`promoteStagingCollection` 是否连带搬配置区属于后端语义，不能假设；没提交就退出则什么都不落地。②`AnkiImportController` 暴露 `adaptationDrafts`，提交时把草稿传给 `commitOfficialPreview`，成功后清空、失败保留（可重试）。③`commitOfficialPreview` 新增 `pendingAdaptations` 参数：collection 提交成功后 best-effort 调 `promotePlans`，live 模板序号由 live 引擎的 projection schemas 现查；任何失败只记日志，导入本身已经成功。④新增 `SmartAdaptationPanel`（纯展示与确认：生成、显示方案修订、应用、恢复原卡，以及未配置 / 不可用 / 被拒 / 截断四类状态）与 `SmartAdaptationHost`（事实构造、AI 调用、二次本地校验、暂存），预览页只留三行摆放。⑤按 ADR 0056，`isDegraded(aiGeneration)` 时整个入口隐藏而不是置灰。⑥剥离后预览页回到 473 行、controller 599 行，两条既有 size ratchet（预览 ≤500、controller ≤600）都满足——**没有放宽任何数值**。
- **验证**：`flutter analyze lib test` **No issues found**；`flutter test --exclude-tags golden` **2404 passed / 0 failed**；断言覆盖未配置时按钮禁用、accepted 显示修订且能应用、unavailable / rejected / truncated 三类文案、已暂存可恢复、会话内方案升迁成功 / 模板消失跳过 / 空集合零写入 / 键与 body scope 不一致跳过。
- **未验**：没有用真实 `.apkg` 走完「预览 → 智能适配 → 提交 → 课时」这条端到端路径；AI 请求未打真实端点；预览页与提交链没有 widget 级联调（只有面板单测 + 服务单测 + 升迁单测）。

---

### 2026-10-22 记忆卡适配 P6b：staging → live 重绑定

- **性质**：功能批次；**测试数 +10**（新增 `official_anki_adaptation_promoter_test` 10 条）。
- **改动**：①`parseAdaptationScopeKey`：`notetype:template[:c<cloze>]` 的逆向解析，坏键返回 null（被跳过的条目绝不猜）。②store 增加 `replaceManifest` / `replaceCardOverrides`——升迁只需要**一次** manifest 写；按单 scope 逐条切换会让一次崩溃暴露半升迁状态。③新增 `OfficialAnkiAdaptationPromoter`：把 manifest 引用的修订逐条搬到 live，用调用方提供的 live 模板序号核每个 scope，最后一次写 live manifest 完成切换；单卡覆盖随组迁移；live 上已有的旧 scope 走**合并**而不是覆盖，一次新导入不会抹掉老方案。跳过原因按 `AdaptationSkipReason`（malformedScope / missingBody / missingTemplate / scopeMismatch）逐条报出，任何跳过都不在 live 留半份状态。
- **验证**：`flutter analyze lib` **No issues found**；`flutter test --exclude-tags golden` **2394 passed / 0 failed**；断言覆盖有效 scope 升迁并生效、模板序号消失整组跳过、未知 note 类型 fail-closed、方案体缺失跳过、坏 scope 键跳过、方案自述 scope 与键不一致跳过、与既有 live scope 合并、单卡覆盖随迁、幂等重跑、无候选时零写入。
- **未验**：**UI 入口仍未接**；升迁目前只有服务与测试，还没挂进 commit 流；备份/恢复实测与模板资源 GC 未做；未出包。

---

### 2026-10-22 记忆卡适配 P6：配置区激活协议与执行

- **性质**：功能批次；**测试数 +15**（新增 `official_anki_adaptation_store_test` 12 条、`official_anki_v2_lesson_content_test` +3 条）。
- **改动**：①新增适配键族 `OfficialAnkiAdaptationConfigKeys`（`turna.adapt.plan.<planId>.r<revision>` / `manifest.<sourceId>` / `cards.<sourceId>` / `index.<sourceId>`），并在文件里钉住载荷模型 `AdaptationManifest`、`AdaptationCardOverride`、`AdaptationCardOverrideTable`、`AdaptationPlanIndex`；单卡覆盖刻意做成「每 source 一个键的小表」——逐卡建键会让按来源清理命名空间需要枚举配置区，而引擎没有可靠的枚举语义。②新增 `OfficialAnkiAdaptationStore`：方案体不可变（同键不同内容抛 `invalidState`，同字节重放幂等）、`activate` 先写体再回读再切 manifest、`deactivate` 只切引用不删体、`lookup` 实现「单卡覆盖 > 精确 cloze scope > 模板 scope > 无方案」四级优先，并把「明确回原卡」「manifest 指向的修订不存在」「根本没有方案」分成三个类型——第三种才是旧数据的正常路径。③`AdaptationSnapshot`：manifest 与覆盖表各读一次，修订体按需读并缓存，20 张卡的课时从 3×N 次配置读降到 2 + 不同方案数。④课时派生接上方案：命中方案时把该组的练习范围收窄为「默认练习 + 可选练习 + flip + canonicalLink」，仍是逐卡重判（方案说「这组做听写」，但没有正面音频的卡照旧回落）；方案明确回原卡或修订缺失时该卡直接走 `canonicalLink`，并在日志里与「无方案」区分开。⑤`CardAdaptationPlan` 补 `defaultExercise`（与布局分开：改练习改任务，改布局不改任务），校验器新增 `unknownDefaultExercise`。
- **验证**：`flutter analyze lib` **No issues found**；`flutter test --exclude-tags golden` **2384 passed / 0 failed**；新增断言覆盖激活写序、修订不可变、幂等重放、manifest 指向已删体、损坏体按缺失、单卡覆盖双向优先、精确 cloze scope 优先、停用后仍可复用体、无方案是正常路径、损坏 manifest 读成空、卸载清空整个 `turna.adapt.` 命名空间、scope key 区分模板序号与 cloze 目标、课时里单卡覆盖只影响该卡、修订缺失回原卡、坏方案不拖垮整课。
- **未验**：**UI 还没接**——导入预览里没有「智能适配 / 应用 / 恢复原卡」入口，`AiCardAdaptationService` 仍无生产调用方；staging→live 重绑定、备份/恢复实测、模板资源 GC 也还没做。未出包。

---

### 2026-10-22 记忆卡适配 P5：AI 候选生成 + 本地语义校验

- **性质**：功能批次；**测试数 +28**（新增 `adaptation_plan_validator_test` 12 条、`adaptation_input_builder_test` 5 条、`ai_card_adaptation_service_test` 10 条；`card_presentation_resolver_test` 批量汇总 2 条，其中一条替换了原有 formal-review 用例的结尾断言）。
- **改动**：①`lib/domain/anki/adaptation/card_adaptation_plan.dart`：声明式方案契约（scope / bindings / front / back / optionalExercises / fallback / fingerprints / provenance）+ 受控词表 `AdaptationVocabulary`（块类型、练习、绑定角色、回退、selection）。解析只保证信封完整，语义一律交给校验器；缺信封抛 `AdaptationPlanFormatException(code)`，不做「尽量猜」。②`AdaptationPlanValidator`：信封 → scope（source / notetype / 模板序号）→ 词表 → 字段引用 → 信息泄漏逐层拒绝；新增两条泄漏规则——答案绑定字段不得出现在 front、仅背面渲染的字段不得出现在 front；空 front、非 `original` 回退、未知练习/块/绑定角色一律拒。③`AdaptationInputBuilder`：只发结构事实（字段名、每模板正/背字段序号、typeIn/script/complexHtml 标记、最多 3 条截断样本、每字段音画直方图、受控词表与输出协议），**不发模板源码 / CSS**；样本 3 条、单字段 120 字、单样本 1200 字封顶；系统提示写明牌组内容是不可信数据。④`AiCardAdaptationService`：一组一次调用、最多一次修复尝试；scope 由应用覆盖（模型自报 source 无效）；截断按终局拒绝处理（重试同一请求不可能成功）；传输异常 → `unavailable`、非 JSON → `not_json`、语义不过 → `invalid_plan`，全部以返回值表达，不向导入流程抛异常；AI 关闭或鸿蒙降级时零调用。生产绑定 `viaEngine` 仍走 `AiEngine.requestJson`（取消、缓存、用量、合规门都在）。⑤`AdaptationBatchSummary`：结构化 / 回原卡 / 需修正 / 不可用四类计数与占比，空组按 0% 而不是 100%。⑥`AiJsonSchemas.cardAdaptation` 只钉信封，语义留给本地校验——JSON Schema 表达不了「答案不得出现在正面」。
- **验证**：`flutter analyze lib` **No issues found**；`flutter test --exclude-tags golden` **2369 passed / 0 failed**；新增断言覆盖答案上正面被拒、背面专属字段上正面被拒、越界字段、未知块/练习/绑定/回退、跨源/跨笔记类型/跨模板 scope、坏信封、JSON 往返、样本与字段截断、音画直方图、请求确定性、请求不含模板源码、一次修复即通过、二次无效即拒绝、截断终局、传输失败可继续、AI 关闭零调用、模型伪造 source 被覆盖。
- **未验**：未用真实端点跑过（无 key、本轮不做网络调用）；尚未接进任何 UI（P6 才接线），所以「用户点智能适配」这条端到端路径还不存在；取样仍是引擎侧的 `SortMode::NoOrder`，没有变分层。

---

### 2026-10-22 记忆卡适配 P4：看图回忆与听写两种展示 + 组件注册

- **性质**：功能批次；**测试数 +18**（新增 `dictation_renderer_test` 4 条、`image_recall_renderer_test` 6 条、`card_presentation_resolver_test` +6 条、`official_anki_projection_payloads_media_test` +2 条；`renderer_lookup_test` 只扩样本不加用例）。
- **改动**：①`Interaction` 联合类型新增 `ImageRecall`（看图回忆）与 `Dictation`（听写），走 freezed + json_serializable（OHOS fork SDK 重新生成）；六个穷举 switch（grammarPointId / AI 提示资格 / 正确答案标签 / 题面标签 / 类型标签 / 选项标签）同步补臂，两种展示都没有文字题面，因此 AI 提示资格为 false——否则提示框会把答案的语境递出去。②新增两个渲染器 `image_recall_renderer.dart` / `dictation_renderer.dart` 并 `@injectable`，同时进 `RendererModule` 的 Set、`lookupRenderer` 的 `_handlesTypeFor`、以及 `StudyCardSurface` 的默认渲染器集。③两个新 `OfficialAnkiProjectionKind`（`imageRecall` / `dictation`）与 `CardPresentationKind` 两值；解析器只在**用户预设显式启用且前提可证**时选它们（正面图已证 / 正面音已证 + 答案够短 + 无未证面媒体），否则回落翻卡或原卡。④新增两个练习预设 `lookAtImage` / `dictation`（各带 flip + canonicalLink 兜底），映射页 chip 与中文标签同步；`auto` 预设不变，旧映射行为不变。⑤抽 `BinaryGradeRow` 到 `interaction_renderer.dart`，翻卡与看图回忆共用同一套二档判定行（原 `_GradeButton` 删除，避免两处漂移）。⑥payload 两种新形态都不带提示字段：听写无 `prompt`、看图回忆的 `hint` 恒空。
- **验证**：`flutter analyze lib` **No issues found**；`flutter test --exclude-tags golden` **2341 passed / 0 failed**；新增门禁覆盖「答案不在题面」「错答显示正确文本」「土语大小写折叠」「看图回忆翻面前无答案文本」「记住/忘记二档提交」「注册表解析到新渲染器」「未证面媒体禁用新展示」。`test/application/anki/official_anki_architecture_guard_test.dart` 的「单一 kind 决策」守卫改指向新载体（resolver），同时新增「payload 层不得出现 `selectOfficialKind`」的反向断言。
- **未验**：未跑 golden；未出包；未在真机上看新展示的实际排版与朗读；P4 的「长答案解释折叠」尚未做（属后续增量）。

---

### 2026-10-22 记忆卡适配 P3（Dart 侧）：按模板方向 + 显式卡级变体

- **性质**：功能批次；**测试数 +9**（`official_anki_projection_payloads_media_test` 3 → 12 条）。
- **改动**：①`templateFaces` 增加 `direction`：导入时逐模板判定「正面渲染的是题干角色还是答案角色」（`officialAnkiTemplateDirection`），随映射决策落盘。此前 `direction` 只从旧 JSON 解码、生产代码从不写入，反向模板卡会把答案当题干展示——这是「正反向模板混淆」的实际后果。②`OfficialAnkiProjectionPayloads.values()` 按 `row.templateOrdinal` 取方向，反向时交换 prompt/response 角色再抽取（题干、答案、cloze 定位、选项对齐同步换）；媒体面归属仍由字段序号决定，不随方向重算，所以反向卡的题面音频会正确落到背面。③新增 `CardContentVariant`（none / cloze / choice / audioFirst）：basicPair 组里的卡级挖空/选择/听力升级不再是一次静默的 `effectiveArchetype` 覆写，而是显式变体；课时派生按变体计数写一条诊断日志，便于确认「这一课到底发生了什么」。
- **验证**：`flutter analyze lib test/application/anki_official/projection` **No issues found**；`test/application/anki_import` + `test/application/anki_official`（`--exclude-tags golden`）**515 passed / 0 failed**；新增断言 9 条：正向模板不反转、反向模板换面且音频不留在正面、无模板事实时按笔记类型方向、两角色都在正面不算反转、cloze 变体显式化、普通卡无变体。
- **未验 / 未完**：**P3 的引擎侧没做**——分层代表性抽样（仍是 `SortMode::NoOrder` 后 `take(sample_limit)`）与「条件/顺序的已知-未知」新派生事实需要改 `native/turna_anki_core/bridge/src/projection.rs` 并重编原生库；本机无 `cargo` / `rustup`，这一轮无法构建也无法验证，故未改 Rust，也不宣称抽样已改善。

---

### 2026-10-22 记忆卡适配 P2：按面媒体 + 官方媒体名可用化 + 面未证回原卡

- **性质**：功能批次；**测试数 +14**（新增 `card_media_extractor_test` 8 条、`official_anki_projection_payloads_media_test` 3 条；`card_presentation_resolver_test` +2 条、`anki_card_renderer_test` +1 条）。
- **改动**：①映射决策（配置区）新增 `templateFaces`——每个模板的正/背字段序号，导入预览从 `schema.templateFacts` 落盘；旧决策缺该键按「面未证」处理，不需要迁移。②新增 `application/anki_import/adaptation/card_media_extractor.dart`：按字段文档序提取 `[sound:]` / `[anki:play:]` / `<img src|srcset>` / `[image:]`，保留 occurrence 顺序与有意重复（同一音频出现两次不合并）；**只在模板实际渲染的字段里取**，面未证时只扫角色绑定字段——隐藏字段的媒体不会被抬上卡面。③`OfficialAnkiRoleValues` 携带 `mediaOccurrences`（含面归属）；flip payload 拆成正/背各两个按面列表，面未证的留在 legacy `audioAssets` / `imageAssets`。④`Interaction.ankiCard` 增四个按面字段（`freezed` + `json_serializable`，用 OHOS fork SDK 重新生成）。⑤`AnkiCardRenderer` 正面只渲染已证正面媒体，背面渲染已证背面 + legacy：**背面答案音画不再在翻面前出现**（此前正反面共用同一份媒体，答案侧媒体提前可见）。⑥解析器新增 `unknownMediaSide` 规则：flip 卡只要有一条媒体面未证，即回原卡而不是猜面。⑦官方媒体名真正可用：`AnkiMediaStrip` 现在接受裸官方媒体名（`hello.mp3`），经新增的 `AudioController.resolveOfficialMediaPath`（复用 `officialAnkiMediaCandidateFile`）解析到 `collection.media`，播放同样落到 `playOfficialMediaFile`。**此前官方卡媒体名没有 `anki://` 前缀，被 strip 的 scheme 过滤整段丢掉**——这是「资源导入了但界面永远看不见媒体」的直接原因。⑧复习侧按面传媒体：`reviewContentFor`、`StudyCardSurface`、`itemFromReviewCard`。
- **验证**：`flutter analyze lib` **No issues found**；`test/application/anki_import` + `test/application/anki_official`（`--exclude-tags golden`）**506 passed / 0 failed**；`test/views/anki_card_renderer_test` + `anki_media_strip_test` **11 passed**（其中「媒体条仍旧挂载」一条改写为「已证正面媒体照常挂载」并新增「面未证的媒体等翻面」一条）。
- **未验**：未跑全量 `--exclude-tags golden`；未出包；未用真实 `.apkg` 走完「导入 → 课时 → 复习」看实际渲染。媒体可用化只到 resolver 层，真机解码格式差异未验。

---

### 2026-10-22 记忆卡适配 P0/P1：单一展示决策 + 类型化结果 + 超限不丢卡

- **性质**：架构收敛批次；**测试数 +9**（新增 `test/application/anki_import/adaptation/card_presentation_resolver_test.dart` 9 条）。
- **改动**：①新增 ADR 0057「记忆卡适配方案与统一展示解析」：钉住四条现状决策路径（预览 policy / 视图 `_resolvePrimaryKind` / 课时 `_derive` / 正式复习 `renderCard`）、单一解析器、适配方案作用域（source + notetype + 模板身份，Cloze 目标作运行参数）、回退优先级、按面有序内容块、配置区键族与「不可变 revision + manifest 单键切换」激活协议、AI 只产声明式配置、正式复习首期维持原卡；`docs/README.md` ADR 索引同步。②新增 `lib/domain/anki/adaptation/presentation_decision.dart`：`sealed CardPresentationDecision`（结构化 / 原卡 / 需修正 / 不可用）+ 11 个 `PresentationReason` 原因码 + `resolverVersion`。③`OfficialAnkiPresentationPolicy.resolve()` 成为唯一卡级判定并返回 `(kind, reasons)`，`selectOfficialKind` 降为它的投影（判定逻辑逐条搬运，输出不变）；新增静态 `expectedKindForArchetype`，v2 视图重建改调它——视图里的 kind 从「主 kind」降为「预计 kind」提示，视图与卡级规则不再各长一张表。④新增 `application/anki_import/adaptation/card_presentation_resolver.dart`：卡级解析器把「过期视图 kind」只记成 `storedKindDrift` / `unknownStoredKind`，未知 kind 不再被当成 flip。⑤v2 课时正文改为逐卡重判展示；payload 超限不再 `continue` 丢卡，改退 `canonicalLink` 原卡引用，原卡引用也放不下才记单卡不可用并按告警计数（之前超限卡静默消失）。⑥删掉 `OfficialAnkiProjectionPayloads.kindsFor`（生产无调用方，且是第四条决策路径）。⑦共享复习内容补上媒体传递：`StandardCourseCardContent` 增正/背面音画四列表，`reviewContentFor`、`StudyCardSurface` 传 `FlipCardPresentation.media`，`itemFromReviewCard` 从 `AnkiCard` 媒体填充，`FlutterCourseCardBody` 用 `AnkiMediaStrip` 渲染且背面媒体只在翻面后构建（此前 `media` 全程被丢弃；面归属未证明的媒体一律落在答案面）。
- **验证**：`flutter analyze lib` **No issues found**；`presentation_policy_test` **4 passed**（判定输出未变）；`official_anki_v2_lesson_content_test` **7 passed**（其中「未知 kind 降 flip」一条改写为「未知 kind 被忽略、由卡级事实重判」）；新增 `card_presentation_resolver_test` **9 passed**。
- **未验**：未跑 `flutter test --exclude-tags golden` 全量；未出包；未用真实 `.apkg` 复现多媒体问题（面归属、多媒体 occurrence、媒体引用协议属 P2）。

---

### 2026-10-21 app 内文案去 Anki 化：统一写「记忆卡」

- **性质**：文案批次（无行为改动）；**测试数 +6**（新增 `test/architecture/app_wording_terminology_guard_test.dart` 6 条）。
- **改动**：①app 内面向用户的文案不再出现 anki / Anki，统一写「记忆卡」——`lib/l10n/app_strings.dart` 74 处字符串（**只改字面量**，getter 名与标识符不动）、`assets/changelog.md` 14 处（应用内更新日志）、`lib/application/settings/release_manifest.dart` 17 处（更新日志后援）、`lib/application/system_health_monitor.dart` 与 `lib/views/settings/system_health_page.dart`（诊断模块名「记忆卡渲染」**两处必须同步**：页面按模块名匹配建议分支，只改一边会让建议弹窗静默失效）、`lib/application/ai/ai_card_context_resolver.dart`（来源显示名）、`lib/application/settings/commands/reset_learning_settings_command.dart`、`lib/domain/audio/anki_media_platform_stub.dart`（平台不支持时的报错文案）、`assets/anki_reviewer/`（复习器页 `<title>` 与 iframe 无障碍标签）。②`assets/anki_reviewer/manifest.json` 的 sha256 / bytes 随资产同步更新，`assetVersion` p2e-2 → p2e-3。③`AGENTS.md` §7.2 新增术语口径（app 内写「记忆卡」；三类例外：第三方 AGPL 许可文本 / 内部契约（协议键、原生库名、本地源、表名、id 前缀、level 标记）/ 文档层），§8 强制手段表登记新门禁。④新增 `test/architecture/app_wording_terminology_guard_test.dart`（6 条）：字符串表严格扫描 + 全 `lib/` 中文文案扫描 + 应用内更新日志与复习器资产扫描，另加两条**反向锚点**（AGPL 文本必须仍点名 Anki、协议键必须仍在字符串表），防止「去品牌」被做成「去许可」。⑤两处测试断言跟随文案更新（`play_hub_screen_test` 11 处、`storage_diagnostics_page_test` 1 处）。文档层（`docs/`、ADR、根 `CHANGELOG.md`）按约定不改。
- **验证**：`flutter test --tags golden` **12 passed**（`play_hub` golden 不渲染该文案，无需重生）；`flutter test --exclude-tags golden` **2291 passed / 0 failed**（较上一批 2285 +6，即新增门禁本身）；新门禁 `app_wording_terminology_guard_test` **6 passed**；`flutter analyze --no-pub` **No issues found**。
- **未验**：未出包、未在真机/模拟器上肉眼过一遍新措辞（「记忆卡组」这类连写是否符合预期观感，未经用户确认）。

---

### 2026-10-21 AI 课程助手移出课时 + 统一 section JSON + 后台生成 + 我的练习库

- **性质**：功能改造批次；**测试数 +16**（删除 `ai_lesson_helper_undo_test` 2 条、`ai_lesson_undo_store_test` 2 条、`srs_tutor_provider_test` 7 条、`ai_prompt_catalog_test` 2 条已退役 prompt、`ai_tutor_chat_session_test` 1 条弃用断言；新增 `ai_practice_pipeline_test` 12 条、`ai_practice_quality_test` 11 条、`ai_practice_repository_test` 6 条、`schema_33_ai_course_library_test` 1 条）。
- **改动**：①课时 AppBar 删掉「AI 课程助手」入口与 `AiLessonHelper*` / `AiLessonUndoStore` / 撤销横幅，连带删掉「降低/提高难度、加 3 题、改听力、优化提示词」5 个单课 chip；单题 AI 提示与深度讲解保留。②新增 `lib/application/ai/practice/`：`AiPracticePrompts`（移植 GUI 的模板/资源/ID/CEFR/干扰项/大纲/分课提示词语义）、`AiPracticePipeline`（大纲校验、shell、splice、逐课/整节校验，文本题型白名单）、`AiPracticeGenerator`（大纲→逐课→校验，失败带错误重问一次）、`AiPracticeJobQueue`（app 级 `@lazySingleton`，`queued/running/ready/failed`，关闭面板不取消）、`AiPracticeSourceContextBuilder`（错题/弱词/难懂点证据块）。③`course.db` **v33** 新增 `ai_courses` + `ai_course_versions` 两张表（合集 / 每次生成一版）配 `AiPracticeRepository`；v32 的 `ai_practice_sets` 平表在迁移里 1:1 拆成「1 合集 + 1 版本」后删除（平表把任务生命周期和收藏内容挤在同一行，重新生成会覆盖旧内容、失败一次连能用的版本一起藏起来）。生成物不写 `sections/units/lessons`（seeder 内容版本变化会清空课程表，且会污染学习页课程树）。内容核验由 `AiPracticeQualityChecker` 两级把关：阻断级（越界正确答案、重复选项、空阶段、生词零覆盖、占位文本、阅读无段落等）先修两次再判失败，提示级只写进核验报告。④AI Hub 新增「我的练习」区与生成 sheet（按错题/弱词/难懂点、自定义课程：主题/等级/单元/课数/课型/编排意图/词表接地）；新增库页（多选删除、存放=置顶保留、7 天过期）、开练页（从 section JSON 走 `LessonViewModel.loadLessonInstance`，不记课程完成度/成就）、详情页（目录树 / 核验报告 / 生成历史）；练习页「智能练习」角标显示生成中/待练习。⑤删除 `TutorLaunchSheet`、`SrsTutorProvider`、`AiWishProvider`、`AiWishChatPage` 与 `AiWishChatRoute`；教材导入 tombstone 保留。⑥新增 ADR 0054，同步 `docs/project-guide.md` §7 与 `docs/README.md` ADR 索引。
- **验证**：`flutter analyze --no-pub` **No issues found**；练习库四份测试 **30 passed**（`ai_practice_pipeline_test` 12 / `ai_practice_quality_test` 11 / `ai_practice_repository_test` 6 / `schema_33_ai_course_library_test` 1）；`test/application/ai` + `test/data` + `test/views/ai` + `test/views/settings` + `test/routing` + `provider_identity_test` + `course_scope_codec_migration_test` **466 passed**；`test/architecture/` **27 passed**（含 `layering_guard_test`、`docs_hygiene_test`）。真实端点冒烟（MiniMax `api.minimax.cn/v1` / `MiniMax-M3.1-Flash`，仅 2 次调用）：大纲返回合法 JSON（1 unit / 1 lesson / 2 words），逐课返回合法 lesson JSON（6 道 `multipleChoice`，无音频题型）。`flutter build apk --debug --no-pub`（OHOS fork SDK）**built app-debug.apk**。**收尾全量复跑**：`flutter test --exclude-tags golden` **2285 passed / 0 failed**（3m0s）；`flutter test --tags golden` **12 passed**（修掉两条长期红着的门禁后，见下一条）；`python -m unittest discover -s test -p "*_test.py"` **Ran 60 tests / OK**；`tool/gui run_gui_tests.py full -j 4` **ran=204 passed=204 failed=0**；`check_ai_boundaries` / `gen_module_tree --check` / `check_docs_index` 三条门禁全绿。
- **未验**：APK 未安装到真机/模拟器；未在界面上点过「生成 → 切页 → 回到我的练习 → 开练 → 调整/删除/存放」完整流程。

---

### 2026-10-21 门禁修复：OHOS vendored 白名单 + 课程树 golden 基线

- **性质**：测试/门禁批次；无产品代码改动。
- **改动**：①ADR 0055 §1 引入的 vendored `flutter_secure_storage` 覆盖没进 `ohos_eol_architecture_guard_test` 的白名单，全量一直有一条红。白名单拆成两张表：「允许出现的 vendored 覆盖」与「TargetPlatform 移植子集（带通配 arm 下限）」，另加 `_secureStoragePatchSite` 钉住唯一的补丁行——重 vendor 丢掉该行会编译通过、全部测试通过，只在真机重启后表现为 API key 消失。ADR 0047 §7.3 补上这一行的筛选依据，§7.5 的 override 计数订正为 5 个 git + 3 个 vendored。②`course_tree_expanded_light` 自 2026-09-22 起就是红的（此前 BASELINE 一直记作「既有失败」，没查因）：课程树新增 `_ensureNextUpExpanded` 后单元进页即自动展开，测试再点一下标题反而把它**收起**，抓到的正是收起态。测试改为断言展开态、不再盲点；`course_tree_expanded_dark.png` 原本就是收起态，一并按展开态重生（light 字节未变，说明它本来就是对的）。
- **验证**：`ohos_eol_architecture_guard_test` **14 passed**，并做变异验证（把补丁行改成 `false` 即成红）；`flutter test --tags golden` **12 passed**；`flutter test --exclude-tags golden` **2285 passed / 0 failed**。
- **未验**：无（两处都只碰测试与文档）。


---

### 2026-10-20 文案中立化 + 系统提示词面板开放全部 AI 功能（含一键恢复默认）

- **性质**：文案 + 能力扩大批次；**测试数 +7**（`ai_prompt_catalog_test` +5、`srs_tutor_provider_test` +1、`ai_prompt_sheet_test` +1）。
- **文案中立化**：用户可见文案里的「土耳其语」清零，只剩三处真实指代（`ttsNativeLanguageLabel` 的语言名映射、关于页的转向史实、Anki 示例牌组）。具体：复习进度来源 `课程 · 土耳其语` → `课程`；词典搜索提示、每日挑战副标题、导出课程副标题、内容更新提示去掉语言名；TTS 三处改成按当前语言取名——`settingsTtsGoogleInstalledMissingVoice` / `splashGoogleTtsMissingBody` / `splashGoogleTtsNotReadyBody` 由 getter 改为带参方法。
- **提示词面板开放**：`AiPromptFeature` 由 5 个扩到 9 个，新增 `tutorPlan`（定制复习）、`courseGeneration`（课程生成 / 愿望建课）、`lessonTransform`（AI 改课）、`courseExplainer`（课程说明）；后三者原本内联在各 provider 里的 system 文案搬进 `AiPromptCatalog`，JSON schema 契约仍留在用户消息里（面板 `usage` 与页脚都写明这一点）。
- **一键默认**：面板新增「全部恢复默认」（存在自定义时才出现，二次确认），调用既有的 `AiPromptOverridesStore.clearAll()`。
- **顺带统一**：5 处 `AiPromptOverridesStore.resolve().textFor(...)` 收敛为 `AiPromptOverridesStore.overrideFor(...)`。
- **验证**：`flutter analyze`（`lib/application/ai`、`lib/views/ai`、`lib/l10n`、`lib/views/splash`、`lib/views/settings` 等）No issues found；`test/application/ai` + `srs_tutor_provider_test` + `test/views/ai` + `test/views/splash` + `test/views/settings` + `test/architecture` **306 passed / 0 failed**。新增断言覆盖「每个功能都有非空默认文本且追加生效」「定制复习的 system 消息真的带上用户追加」「一键恢复清空全部且不残留空提示词」。
- **未验**：真机看 9 个芯片的面板排版；未构建安装包。

---

### 2026-10-20 AI 讲解在 Anki 语境下不再冒充「土耳其语」

- **性质**：行为修正批次；**测试数 +2**（`ai_prompt_catalog_test`）。
- **症状**：从复习页打开 Anki 卡片的「卡片讲解」时，系统提示词固定写 `You are a language-learning companion for Turkish.` —— 导入日语 / 英语牌组后，AI 仍按课程语言讲解；AI Hub 的介绍文案也有「问任何土耳其语相关问题」「解释一段土耳其语句子」这类硬编码。
- **改动**：①`unified_review_page` 的讲解语言改按来源判定（课程卡片 → 当前课程语言显示名；`LegacyAnkiSource` / `OfficialAnkiSource` → `null`）；②`AiPromptCatalog.cardExplain` 接收可空语言，未知时改为「从卡片文本自行判断，不要默认课程语言」；③`AiCardExplainProvider` 删掉 `'the target language'` 兜底，null 原样透传；④AI 介绍 / 示例文案去土耳其语硬编码（自由问答作用与适用场景、追问示例、课程生成示例、自定义提示词占位符）。
- **验证**：`flutter analyze`（`lib/application/ai`、`lib/views/review`、`lib/l10n`）No issues found；`test/application/ai` + 复习页守卫 **210 passed / 0 failed**；`test/views/review` + `test/architecture` **57 passed / 0 failed**。
- **未验**：真机点「Anki 卡片 → 卡片讲解」未跑；未构建安装包。

---

### 2026-10-20 AI 定制复习 / 学习诊断全挂：JSON 模型留空时把 `model: ""` 发上线

- **性质**：缺陷修复批次；**测试数 +10**（`ai_engine_config_test` +5、`ai_engine_test` +1、新增 `ai_error_mapper_test` 4 条）。
- **症状**：`custom` 预设下 AI 对话可用，而「定制复习（弱词 / 错题）」「学习诊断」「生成课程」等一切走 JSON 的调用全部失败，界面显示 `AI planning failed: ... HTTP 400 ... unknown model`。
- **根因**：`AiEngineConfig.selectModel` 移植 `config.py:select_model` 时，把「留空回落到 `self.model`」写成了「回落到 `preset.defaultModel`」。deepseek / mimo 预设的默认模型非空，缺陷被掩盖；`custom` 预设的默认模型是空串，于是 JSON 请求带着 `model: ""` 上线。`isComplete` 又只校验会话模型，配置页因此照常显示「已配置」，界面看不出异常。
- **改动**：①`selectModel` 收敛成单一回退链——JSON 侧留空继承会话模型（新增 `effectiveChatModel` / `effectiveJsonModel`，未知 kind 同样回落到会话模型），`isComplete` 改用 `effectiveChatModel`；②`fromJson` 把空串模型归一成 `null`（旧设置页把空输入框原样存成 `''`，迁移到 `custom` 后既拿不到 retired 默认值、也不像「没填」）；③配置页 JSON 模型字段补提示「留空则与聊天模型相同」，并补该字段的预设快选芯片；④`AiErrorMapper` 新增 `modelUnavailable`（`unknown model` / `model_not_found` 一族，`canRetry: false`、`canConfigure: true`）；⑤`SrsTutorProvider` 规划失败改走 `AiErrorMapper`，供应商原始 body 只进 `logger.w`，不再直出到界面。
- **验证**：`flutter analyze`（改动面 `lib/application/ai`、`lib/views/ai`、`lib/l10n` 等）No issues found；5 个测试文件 **47 passed / 0 failed**（`ai_engine_config_test` 19、`ai_engine_test` 5、`ai_error_mapper_test` 4、`ai_http_client_test`、`srs_tutor_provider_test`）；对真实端点（MiniMax `api.minimax.cn/v1`）实测复现：`model: ""` → `400 invalid params, unknown model '' (2013)`，同名模型正确值 → `200`，`response_format: json_object` 亦被接受。
- **未验**：全量 `flutter test --exclude-tags golden` 未跑；app 内端到端（配置页改模型 → 点「定制复习」）未在真机或模拟器点过。

---

### 2026-10-20 文档体裁分离与全量瘦身（删施工日志 / 建状态唯一源 / 加文档门禁）

- **性质**：纯文档批次，零运行时行为改动；**测试数 +11**（新增 `test/architecture/docs_hygiene_test.dart` 11 条断言）。
- **改动**：①**删除** 14 个一次性文档——`docs/official-anki-migration/` 整目录（4 份计划 + 收据 + archive）、`docs/ankiUpdate/`（2）、`docs/reviews/`（1）、ADR 0030 / 0036 / 0041 / 0046、`test/archive/BASELINE-pre-2026-09-20.md`、`native/turna_anki_core/contract/archive/README.md`、`tool/gui/docs/archive/`（4）、`tool/gui/docs/ai_configuration_and_features_report.md`；施工日志与真机收据原文一律转入 git 历史。②**新建 `docs/status.md`** 作为状态唯一源（迁移口径 / 平台档位 / 证据台账 / Held 项 / 鸿蒙三层口径），`AGENTS.md` §0 的状态口径由旧收据改指它。③`AGENTS.md` 27.6 → 19.9 KB：删 §7.1 状态快照（3481 字符单行）与真机收据、§9.1/§9.2 排错流水改为指向 `docs/ohos-build-setup.md`，**规范正文日期戳归零**。④`docs/project-guide.md` 68.6 → 24.2 KB（删「现状速览 / 目录 / 实现清单 / 下一轮计划」，保留教学法 / 架构 / 格式契约 / 「不做的事」）。⑤ADR 撞号修复：0021 与 0043 各有两篇历史复用 → 改为 0052 / 0053（接在 0051 之后），标题编号同步；ADR 目录 241.9 → 160 KB，**编号决策项零非预期丢失**（首轮压缩误删决策表格，已按 HEAD 原文逐篇重建）。⑥**清理失效文档指针 243 行 / 83 个文件**：`doc 34` / `plan 34`（77 行）、`step3.md` / `step4.md` / `step6.md`（28）、`doc 41`（24）、`official-anki-migration` / `cutover-receipt` / `ankiUpdate`（67）、`ADR 0041`（31）、`ADR 0046`（11）、`v2-first-device-findings.md`（5），全部改指现存 ADR 0043 / 0044 / 0050 或 `docs/status.md`。⑦`tool/gui` 文档树 321.9 → 184.3 KB（`tests/BASELINE.md` 142.3 → 24.4 KB；`ai_refactor_contract.md` §1–§18 编号与 §14 逐字保留）。⑧**取消跟踪**两个 HiLog 设备抓取（`ohos_launch_fixed.log` 17.8 MB + `ohos_launch_repro.log` 27.9 MB，零引用），并补 `.gitignore` 规则覆盖 `ohos_launch_*.log` 与 `build_ohos_*.log`（文件保留在磁盘）。⑨**门禁加到 10 条断言**：新增「ADR 编号提及必须真实存在」与「正文里反引号包着的 `.md` 文件名必须真实存在」；后者按**路径**判定（相对所在文件或相对仓库根），不按裸文件名兜底——兜底会让「同名但在别处」的死指针蒙混过关。连带修掉 3 处只能靠同名兜底的指针：ADR 0020 / 0031 指向 2026-09-29 已删的根 `CLAUDE.md`（标注「已删」），ADR 0053 的 `course-layout.md` / `course-pack-format.md` 改为 `docs/authoring/` 全路径。⑩**GUI 侧门禁加第二条不变式**：`tool/gui/tool/check_docs_index.py` 除「索引无孤儿」外，同时校验**文档指针存活**——GUI 树里反引号包着的 `.md` 名与 Markdown 链接都必须解析到真实文件（基准：提及所在文件 / GUI 工程根 / 仓库根）。连带修掉 3 处只靠同名兜底的指针：`tool/gui/docs/ai_refactor_contract.md` 的 `docs/archive/experienceai.md` 补「已移至」现路径，`CHANGELOG.md` 的 `CLAUDE.md` 与 `dreamplan.md` / `future2.md` / `future3.md` / `future4.md` 标注「已删」。⑪**复查发现压缩把正文截断了**：首轮压缩把 13 篇 ADR 由英文改写成中文时在句中断句，造成内容丢失。逐条与 HEAD 原文比对后修复——ADR 0001（状态 / 决策 / 理由三处截断 + 丢「被否决的选项」整段）、0002（落地形态缺「重置动作 / 持久化 / 一次性 reseed」3 条 + 头部 `Related` 截断）、0007（决策 5「不迁移 Freezed」+ 理由第 4 条 + 丢 `MatchProvider` 封装 / `AppRouter` 路由守卫两条决策 + 后果整节）、0010（决策 4/5 + 理由一段 + 后果一条）、0011（决策 3 截断 + 决策 4 + 「影响与边界」整节为空）、0015（表缺 2 行 + 4 条 bullet + 丢「迁移路径」整节）、0020（头部丢 `Supersedes` + 决策 3/4 + 后果一条）、0021（决策 3/4/5 + 理由截断 + 后果缺 4 条）、0026（决策 3/4 + 理由截断 + 后果缺 2 条）、0031（丢「不在范围」清单）、0032（丢「不动 `CLAUDE.md`」）、0033（丢「与契约同步」）、0034（决策 3–6 + 理由一段）、0037（丢「取代」行 + 三次修订的日期）、0038（决策第二段 + 「影响与边界」整节为空）、0039（`SecureCredentialStore` 那条 bullet 截断在 `secure_credential_s` + 页面行为丢 2 条 + 背景少一句）、0042（决策 4/5/6 + 头部丢关联）、0043（丢过程档指针 + 评审日期）、0044（丢过程档指针）、0045（决策 4/5 + 头部 `关联` 截断）、0047（丢「被否决的候选」3 条 + autofill 符号处置表 + SDK 档位证据表 + 方案正文指针）、0050（丢 §2.5 资产来源表 + 2 处代码段被折断）、0053（决策 3/4/5 + 理由与后果各截断）。为防复发，固化 3 个机械判据：①**全文反引号奇偶**（奇数 = 句中断在代码段里）——该判据已落成门禁：`docs_hygiene_test.dart` 第 11 条断言与 `check_docs_index.py` 的第三项检查，两侧均做过变异测试（注入未闭合反引号 → exit 1 并报出文件名 → 还原后字节级一致）；②**段落技术标识符覆盖**（HEAD 每段的技术 token 必须能在现文找到，跨语言成立）；③**编号决策项 / 表格行计数**（现文不得少于 HEAD）。接收侧同批补回 2 处死指针：ADR 0020 与 0031 指向 2026-09-29 已删的根 `CLAUDE.md`（标注「已删」）。
- **体量（口径：仓库自有 .md，排除 `.agents/` `.cursor/` `third_party/` 与 `native/turna_anki_core/anki/` 子模块内容）**：`docs/` 子树 66 篇 / 806.7 KB → 52 篇 / 339.7 KB；全口径 105 篇 / 1,741.5 KB → 84 篇 / 666.2 KB（**−1,075.2 KB，剩 38%**；含⑪回补的截断内容）。
- **验证**：`flutter analyze lib test` No issues found ✓；`flutter test test/architecture/docs_hygiene_test.dart` **11/11 通过** ✓；`ohos_eol_architecture_guard_test.dart` 等 6 个被触及的测试文件 **39 passed / 0 failed** ✓；`python tool/gui/tool/check_docs_index.py` **0 orphans** ✓；全仓 markdown 相对链接扫描 **0 断链** ✓；失效文档指针扫描 **0 残留**（余下命中均为标注「（已删）」的纯文本历史引用，非链接）✓；文档门禁**变异测试**通过——插入一个不存在的 `.md` 指针后门禁 exit 1 并精确报出所在文件与行号，改回后文件字节级一致；GUI 门禁 `check_docs_index.py` **7 documents, 0 orphans, 0 unresolved pointers, 0 unbalanced code spans** ✓（同样做过变异测试：注入假指针 → exit 1 + 精确行号 → 还原后复绿）；全树 85 篇项目 markdown（含 `tool/gui/` 与 `native/turna_anki_core/`）正文指针终检 **0 未解析** ✓；⑪复查后重跑三个机械判据：全仓 84 篇 markdown **反引号奇偶 0 处失衡** ✓；截断检测（段落末行无终结符 + 表格单元格数配对）**0 真命中**（余 6 处为手工硬换行、4 处为转义竖线误报）✓；内容保全验收（编号决策项 / 表格行 / 段落技术标识符覆盖）**ADR 决策项零缺失** ✓
- **未验**：全量 `flutter test --exclude-tags golden` 未跑（本批不改运行时行为，仅新增一个测试文件，已单独跑通）；`make ci` 未跑；鸿蒙 fork SDK 未构建。
- **不在本批范围**：`ohos/build-profile.json5`（release 签名材料 → debug）与 `ohos/hvigor/hvigor-config.json5`（新增 `execution` 块）的工作区改动**未纳入本批**，二者 mtime 与同期的 `ohos_launch_*.log` 抓取一致，判断为并行的真机调试会话所致，已保持原样留在工作区未暂存，由负责人判定是否保留。

---

### 2026-10-20 鸿蒙签名配置修复 + release 包产出 + 全量门禁首跑（`make ci` 等价复刻）

- **性质**：修复 + 发布准备批次，测试数未变（无新增 / 删除用例）。
- **改动**：①根因是密钥库与证书**不同代**（`storeFile` 指 debug 密钥库、`certpath` 指 release 分发证书，报 `ERROR: 11111002`），`ohos/build-profile.json5` 的 `certpath` / `profile` 改指同代 debug 材料，密钥库、别名与加密密码原样不动；②`ohos/build-profile.json5.release` 由明文口令改为 DevEco 同构加密 blob（PBKDF2 + AES-128-GCM），`.gitignore` 注释订正为「存加密 blob、机器本地、不可入库」，并顺手删掉 `ohos/` 下 16 个 `.tmp_*` 排查残留；③`build-profile.json5` 补注释规则（同代要求、11111002 与误导性 keyAlias 提示、别名小写化、只有 debug p7b 带 `device-ids`）；④`Makefile` 的 `build-release-smoke` 加 `--allow-version-mismatch`（`build-release` 保持严格断言）。
- **验证**：`format-check` 953 files / 0 changed ✓；`analyze` No issues found ✓；`test`（含 golden）**2246 passed / 1 failed**（唯一失败为既有项 `golden/goldens/course_tree_expanded_light.png`）；`test-python` **Ran 60 tests / OK** ✓；`lint-gui` ✓；`guard-gui` ✓；`test-gui` **ran=204 passed=204 failed=0** ✓；`build-release-smoke` APK 阶段通过、AAB 阶段失败（Android 侧既有项，非本批引入）。
- **未验**：真机安装与 AppGallery 上传；本批 release 包未在真机或商店侧验证。

---

### 2026-10-20 发布 0.9.1：应用内 changelog 同步 + 签名材料防入库 + 全量工作区核验

- **性质**：发布准备批次，版本 `0.9.0+5` → `0.9.1+6`。
- **改动**：①版本号同步三处（`pubspec.yaml`、`ohos/AppScope/app.json5` 的 `versionCode: 6` / `versionName: "0.9.1"`、`ohos/local.properties`），`app.json5` 注释订正为「No test asserts this sync today」（既有守卫只断言文件存在）；②应用内 changelog 三处同步（`assets/changelog.md`、`release_manifest.dart` 的 `fallbackReleases` / `journeySteps`、`changelog_page.dart` 阶段数改由 `journeySteps` 派生）；③签名材料防入库：`.gitignore` 加 `ohos/build-profile.json5.release` / `.unsigned` / `tool/_tmp_*` 三条规则；④golden 归属判定与测试加固：回干净 HEAD 对照后确认 `settings_reminder_light/dark` 失效属本批并已重生，`changelog_page_test.dart` 加 2 条守卫、3 处脆弱断言改为 `scrollUntilVisible`。
- **验证**：`flutter analyze` No issues found；全量 `flutter test --exclude-tags golden` **2235 passed / 0 failed**（较上批 +2）；`python -m unittest discover -s test -p "*_test.py"` **Ran 60 tests / OK**；`test/golden/` **11 passed / 1 failed**（唯一失败即既有项 `course_tree_expanded_light`）；`dart format lib test` 全库合规。
- **未验**：真机；鸿蒙 fork SDK 未构建；`make ci` 的 `test-gui` / `build-release-smoke` 未跑。

---

### 2026-10-20 设置页开关 ON 态白色 thumb 被吞，一行颜色改回 + 像素级回归测试

- **性质**：视觉缺陷修复批次，1 行代码改动 + 1 个新测试文件。
- **改动**：①`settings_section.dart` 的 `settingsAdaptiveSwitch` 在 `WidgetState.selected` 态把 `thumbColor` 由 `TurnaTheme.brandTeal`（与 `activeTrackColor` 同色，thumb 与 track 融成一体）改 `TurnaTheme.textOnPrimary`（白），OFF 态仍走平台默认，两态区分度保留；该写法自 `980224e6` 引入即如此，非本次回归；②一处改动覆盖设置页全部 5 个开关入口，裸 `Switch` 两处本就正确未动；③新增 `test/views/settings/settings_switch_thumb_test.dart` 3 条像素级断言（渲进 `RepaintBoundary` → `toImage` → 统计白色 / teal 像素），已验证回退修复即精确失败。
- **验证**：`flutter analyze` No issues found；全量 `flutter test --exclude-tags golden` **2233 passed / 0 failed**；`flutter test test/views/settings/` **50 passed / 0 failed**；新测试 3 passed；`dart format --set-exit-if-changed` 干净。
- **未验**：真机观感；`test/golden/` 未跑（本批无 golden 图变更）。

---

### 2026-10-20 AI 面收敛与「智能练习」入队：去蓝紫 / 去 emoji / 服务商精简与接口责任标注 / 系统提示词可见可追加 / 练习页「AI 助手」横幅移除

- **性质**：产品面收敛批次，AI 从「并行专区」收回为「练习的一个来源」。
- **改动**：①配色与文案：AI 面 11 处 `amethystLeague` 移出（Hero 渐变改 `brandTealDark→brandTealLight`，图标与强调改 `brandTeal`；`amethystLeague` 常量保留，词典 / 练习信息面板 / 成就目录仍在用），全库用户可见 emoji 清零，并修两处假文案（AI 必然出网，隐私表述改为「配置只存本机，请求直达服务商」）；②服务商收敛（破坏性）：`AiProvider` 由 `deepseek / kimi / qwen / mimo / custom` 收敛为 `deepseek / mimo / custom`，`AiEngineConfig` 加 `schemaVersion: 2`，用 `kRetiredPresets`（`kimi` / `qwen` → `custom` + 原 Base URL + 原模型）与 `kRetiredModelAliases` 迁移，避免静默坏配置；③新增 `ai_prompt_catalog.dart`（5 功能默认 prompt 单一来源）、`ai_prompt_overrides.dart`（单键、追加式、4000 字上限）与 `ai_prompt_sheet.dart`（只追加不替换，默认文本含安全边界），配置页另加常驻 `_EndpointScopeNotice` 标注接口与责任；④练习页横幅移除，复习队列 2×2 增第四格「智能练习」（引擎未配置挂橙色「未配置」徽标），AI Hub 与功能手册标题同步改名。
- **验证**：`flutter analyze lib test` No issues found；全量 `flutter test --exclude-tags golden` **2225 passed / 0 failed**；`test/golden/play_hub_golden_test.dart` 2 passed（`play_hub_light/dark` 已重生）。
- **未验**：真机；鸿蒙侧 `flutter_secure_storage` 无该平台实现，AI 密钥只能 `sessionOnly`（重启需重填），未接平台侧 fork 覆盖。

---

### 2026-10-20 永久删除「开发者实验室」（Fun Lab）及其底层子系统

- **性质**：产品面清理批次，功能整体删除（不是隐藏）。
- **改动**：①删除设置分类 `SettingsDestination.developer`、设置首页 debug 入口块、`DeveloperSettingsPage`（含 `@RoutePage`）、`SettingsFunSection`、`FunProvider`、`FunLabSnapshotService`，`make gen`（fork SDK）重生成路由与 DI 并确认无残留；②连带清理成就页横幅与 `funPreview` 分支、`LocalStateKeys` 两个 Fun 键（备份清单同步移除）、`ISrsStateStore.countPostponable` / `postponeActiveBy` 及 DAO 实现、66 条文案与文档指路；③`CourseDatabase.kSchemaVersion` 30→31，v31 为纯 `DROP TABLE IF EXISTS`（4 张 Fun 表），onCreate 与 v15 / v20 / v25 迁移同步；④删 `fun_lab_snapshot_service_test.dart`（7 条）与 `achievement_badge_card_test.dart`（1 条），schema 迁移用例改 v30→v31 删表用例。
- **验证**：fork SDK `build_runner` exit 0；`flutter analyze` No issues found；全量 `flutter test --exclude-tags golden` **2192 passed / 0 failed**（本批净减 8 条）。
- **未验**：golden 未跑；真机未跑。

---

### 2026-10-19 暗色背景去绿 + 四个主 tab 顶栏统一

- **性质**：视觉一致性批次，两件互相独立但同一诉求的改动。
- **改动**：①夜间背景由墨绿改为中性黑阶（scaffold `#000000`、AppBar `#0F0F0F`、card `#141414`、elevated `#1E1E1E`、分割线 `#2A2A2A`、input / chip `#121212`），退役色值 `#0F2119` / `#152B21` / `#12261C` / `#1B3529` / `#2C453A` 在 `lib` / `android` / `ohos` / `tool/gui` 全仓零残留，并同步 Android `colors.xml`、鸿蒙 `AnkiReviewerChrome.ets` 的 `nightPalette()` 与 `tool/gui` 的 `_DARK_PALETTE`；②抽 `TurnaTheme.tabAppBarHeight = 60.0` 单一 token，三页 `preferredSize` 与设置页 `toolbarHeight` 统一读它，设置页标题由 `headlineSmall` 降为 `titleLarge` / w700 并删掉自绘底色覆盖；③新增 `test/views/tab_app_bar_contract_test.dart` 4 条，重生 6 张暗色 golden。
- **验证**：`flutter analyze` No issues found；全量 `flutter test --exclude-tags golden` **2197 passed / 0 failed**；`test/views/` 382 passed；`test/architecture/` 13 passed；`test/golden/` **11 passed / 1 failed**（唯一失败即既有项 `course_tree_expanded_light`）。
- **未验**：真机 / 模拟器上的顶栏观感与 golden 未覆盖的页面；`tool/gui` 的 Qt 测试在本机跑不了（venv 在 Linux 内建）。

---

### 2026-10-19 课程树单元名、官方视图读失败、课内 Anki 不写错题本、鸿蒙预热 API 删除与二档文案

- **性质**：把集中在 Official Anki 的几处行为一起收口。
- **改动**：①`kSchemaVersion` 29→30，`anki_course_tree_view` 增 `unit_key`（v29 升级用 `ADD COLUMN … DEFAULT ''`，旧行仍可读），展示用非空 `unitKey`、空则退回 `lessonKey`，已安装的三级牌组需下次冷启动重建才换成真实单元名；②视图缺表仍返回空并记 info，其它 SQL 错误记 warning 后抛出，`CourseProvider.officialTreeLoadError` 与 `bootFailed` 分开，课程树顶部固定文案「官方课程暂时读不出来，内置课程不受影响。」；③anki-owned 课内提交统一走 `_applyAnkiCourseSubmit`，提交失败不再写错题本或 Turna FSRS；④鸿蒙侧 `advanceAndPresentAfterNativeRating` / `presentSessionCardInPlace` 挪到 `official_review_advance.dart`，删除 `warmUp`、`OfficialAnkiOhosReviewerWarmUp` 与 idle deadline，底栏 `ratingLabel` 只映射 again→忘记 / good→记住，Release 下 `requireImporter(useFake: true)` 直接抛 `capabilityMissing`。
- **验证**：`flutter analyze`（改动文件）No issues found；全量 `flutter test --exclude-tags golden` **2193 passed / 0 failed**；删 9 条只覆盖 warmUp 的用例，新增 6 条（schema v30 / 单元名 / 缺表 / 坏列 / 坏视图保留内置课 / 提交失败不写错题本）。
- **未验**：真机。

---

### 2026-10-19 README 与详解版重写 + 文档树精简（删 3 篇 / 改 2 篇 / 新增 1 篇索引）；纯文档，零代码行为改动 / 零测试增减

- **性质**：文档治理批次，目标是让 README 不再是黑话并砍掉已闭环的冗余文档。
- **改动**：①`README.md` 全文改大白话（开头一句话说清产品是什么，「能做什么」按用户视角列 8 项，FSRS 一句话解释，新增「运行需要什么」表与「不做的事」）；②`docs/project-guide.md` 保留原 17 节编号与标题（锚点不动）但内容按「只写还在的代码」重写，§5.13 删除后各节号不动，新增开篇现状速览表与 §1 目标用户 / 已知取舍；③订正过期事实（`schemaVersion` 实读 29、drift 13 张表、LessonTemplate 为 6 种教学模板 + 1 种兜底、`make ci` 实际 8 个目标），并对齐 Android / iOS 构建文档与 `tool/gui` 跑法；④删 3 篇（先内联独有内容再删）并新增 `docs/README.md` 文档索引，保留 `ankiUpdate` 两篇、`docs/official-anki-migration/archive/` 与全部 37 篇 ADR，另修 6 处断链（含 `.agents/skills` 下 20 处缺 `quick-rules/` 前缀）。
- **验证**：`flutter analyze` No issues found；`flutter test --exclude-tags golden` **2189 passed / 0 failed**；`python -m unittest discover -s test -p "*_test.py"` **Ran 60 tests / OK**；`check_docs_index.py --quiet` 12 documents, 0 orphans；全部 214 篇受版本控制的 markdown 相对链接全量解析，断链 0。
- **未验**：`tool/gui` 的 `gen_module_tree.py --check` 与 `check_ai_boundaries.py` 在干净 HEAD 上同样 exit 1，属本批之外的既存失败，未处理。

---

### 2026-10-19 鸿蒙复习页白屏修复：移除预热 + 顶栏四键收回 + 启动探针关闭；真机通过

- **性质**：入口缺陷修复 + 产品面精简，提交 `9f41ed25`。
- **改动**：①根因是预热与「首卡只能由 widget 树 attach 时 present」互斥——独立 ability 盖住 Flutter 页面时 Flutter 不产帧，`setState` 只标脏不重建，Stage 永不 mount，点击翻面无回执，只能靠 60 s idle deadline 自愈；②页面不再预热，首卡由 `OfficialAnkiReviewerStage.attach` 在 Flutter 仍在前台时 present，advance / present 抽成顶层 helper 并加顺序守卫；③顶栏四键（撤销 / 重做 / 搁置 / 暂停）与 `requestCardAction` / `requestUndo` 协议全链路删除，payload 契约字段 `canRedo` / `canMutate` 保留（页面不消费），另新增 `chromeThemeFor({dark, highContrast})` 单一来源；④启动不再拉起 `AnkiReviewerProbeAbility` 与音频 / 语音探针（探针代码仍在 `ets/probe/`，需手动启动），守卫改为反向断言（四词按钮与 handler 不得回归、页面源码不得出现预热）。
- **验证**：analyze 0 issue；相关两目录 `flutter test` 429 / 430 passed；fork `flutter build hap --debug` rc=0；真机（CMM-AL10 / HarmonyOS 7.0.0.109 / API 26）截图链 `s1→s2→n1→p1→p2→q1→q2`，入口不白屏 / 首卡呈现 / 翻面 / 二档 / 评分后推进 / 顶栏精简全部通过。
- **未验**：首卡时延数值、连续过卡 ≥6、Review All 跨源、高对比度观感、`presentInPlace` 跳过分支的边角。

---

### 2026-10-18 鸿蒙复习推进修通：注入了「被盖住的 Flutter 页不产帧」这条真根因，并让 binding 原地装卡 present

- **性质**：真机缺陷修复 + 真机收据（CMM-AL10 / HarmonyOS 7.0.0.109 / API 26）。
- **改动**：①根因同上一条——复习器是独立 ability，盖住 Flutter 页面时 `setState` 只标脏不重建，binding 拿不到新卡，一次 present 都不发，12 s 后 watchdog 判 `rating_stalled`（评分回执本身是 ok 的，差的只是「谁把下一张装进来」）；②新增 `OfficialAnkiOhosReviewerBinding.presentInPlace(cardId)`，成功判据为 `card.cardId == cardId && !ui.isError`；③成功后补 `acceptPresentation(question)`，否则新卡永远没有 `questionReceipt`、`canReveal` 为 false，翻面在 Dart 侧静默 no-op；④评分分支与 redo / bury / suspend 三键路径都接上，并新增 7 条诊断日志（body rebuild / body boot / stage attach / present card / present suppressed / in-place present）。
- **验证**：`flutter analyze lib` No issues found；全量 `flutter test --exclude-tags golden` **2197 passed / 0 failed**（新增 3 条守卫）；`flutter build hap --debug`（fork SDK）成功并 `hdc install -r` 装机；真机一次会话连评 6 张（记住 ×4 / 忘记 ×1 / 搁置 ×1），进度 `1/8 → 2/9 → 3/11 → 6/16`，全程 **0 次** `rating_stalled` / `advance_failed`，`again` 首次取证 `ease=1 ivl=-60`。
- **未验**：Flutter 帧恢复时同一张卡会重渲染一次（需把渲染控制器提到会话级持有，属结构性改动，未做）。

---

### 2026-10-18 鸿蒙复习链路首次真机复验：三处修复 + 两处阻塞缺陷登记

- **性质**：真机验收（CMM-AL10 / HarmonyOS 7.0.0.109 / API 26），首次把 UI-15 / UI-16 的 ArkTS 改动放上设备。
- **改动**：①已验证通过二档按钮、`记住 → ease=3(good) ivl=6`、Review All 源徽章、三键 `enabled` 属性、完成交棒到 `UnifiedReviewCompletion`、早退不发完成屏；②登记两处阻塞缺陷（未修）——评分后推进抛 `advance_failed`，连锁 `card_mismatch`（`official_anki.scheduling_context_stale`）；③主题首批时序：抽 `_syncChrome()` 前置，`attach` / `rebind` 增 `chromeTheme` 形参，首卡不再用构造默认值；④预热 deadline 20 s → 60 s 并在 `attach` 起手 disarm，三键颜色按同一谓词走 `textPrimary` / `textSecondary`，`advanceFromNativeRating` 失败分支加结构化日志（`phase` / `locked` / `current` / `items`）。
- **验证**：`flutter analyze lib` No issues found；全量 `flutter test --exclude-tags golden` **2192 passed / 0 failed**（新增 2 例 chrome 守卫）；`flutter build hap --debug` 成功并 `hdc install -r` 装机。
- **未验**：`advance_failed` 根因（下一轮带日志复现）、`again` 落库值、高对比度色板观感、`sourceProgress` 多源场景、连续进出 ×20。

---

### 2026-10-18 鸿蒙 UI-16 完成屏交棒：单源会话答完即把完成屏还给 Flutter

- **性质**：对齐缺口收尾 + 修一个结算缺陷。
- **改动**：①`_onNativeAbilityClosed` 改为按 `answeredCount > 0` 结算，且 `verdict == completed && isComplete && answered > 0` 时不 pop，保留 Flutter 侧已渲染好的完成屏（Review All 未完成时显示换源 spinner，避免闪一张属于刚结束那个源的完成屏）；②`ohosReviewerPayload` 新增 `autoComplete`，ArkTS 侧 `ReviewerPresentPayload` / `ReviewerChromeState` 同步（`chromeState` 第 16 个参数），`fetchSettlement` 拿到统计后 600 ms 自动 `endReview(VERDICT_COMPLETED)`，完成行在 `autoComplete` 时只出「复习完成 / 正在打开结算…」；③`endReview` 加 `terminating` 幂等守卫，`resetChrome` 只复位 `autoCloseScheduled`（`terminating` 守的是 ability 不是 session）；④Review All 不自动关——下一源复用同一个 ability，结束的源武装的定时器会关掉下一源正在用的页面，故定时器回调再校验 `alive && complete` 作双保险。
- **验证**：`flutter analyze lib` No issues found；全量 `flutter test --exclude-tags golden` **2190 passed / 0 failed**；`flutter build hap --debug` 成功（签名 hap）；`ohos_card_action_chrome_guard_test.dart` 新增 1 例 5 断言。
- **未验**：真机（600 ms 交棒观感、完成屏 XP 非零、Review All 跨源不被误关）。
