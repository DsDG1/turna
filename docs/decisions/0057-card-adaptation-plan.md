# ADR 0057 — 记忆卡适配方案与统一展示解析

> 日期：2026-10-22 ｜ 状态：已接受
>
> 关联：[ADR 0042](./0042-staging-first-official-import.md)（staging-first 导入）、
> [ADR 0043](./0043-anki-v2-single-source-of-truth.md)（v2 单一事实源与配置区决策）、
> [ADR 0050](./0050-ohos-official-anki.md)（鸿蒙 Official Anki 档位）。

## 背景

导入后的「这张卡怎么展示」目前由四条互不相认的路径决定：

| 入口 | 决策点 | 依据 | 失败行为 |
|---|---|---|---|
| 导入预览 | `OfficialAnkiPresentationPolicy.selectOfficialKind` | 识别原型 + `enabledKinds` + 置信度 | `canonicalLink` |
| v2 视图重建 | `OfficialAnkiV2ViewRebuilder._resolvePrimaryKind` | 只看 `archetype` + `enabledKinds`，按 notetype 取一个 kind | `canonicalLink` |
| 课时加载 | `OfficialAnkiV2LessonContent._derive` | 读视图行 kind，再按 `archetypeViolated` 现场降级 | 异常选择题降 flip，其余回原卡；超限 `continue` |
| 正式复习 | `OfficialFormalReviewProductionLoader` + 引擎 `renderCard` | 原卡 HTML / 纯文本 | 原卡 |

三个具体后果：

1. **同一张卡在不同入口可能得到不同展示**。视图存的是 notetype 级主 kind，课时又叠一层卡级降级；预览用的却是 `selectOfficialKind` 的完整判定。视图行的 `presentation_kind` 一旦过期就无人复核。
2. **多媒体只能表达成可空单值**。`OfficialAnkiRoleValues.audio` / `image` 各一个；音频从三个角色字段拼串后取首个匹配，图片只从 image 角色字段取首个。正反面归属、混排顺序、同字段多次引用全都无法表达，于是 `AnkiCardRenderer` 的正反面共用同一份 `_buildMedia`——背面答案音频/图片在翻面前就可能进入渲染与无障碍树。
3. **没有承载「如何解释内容」的配置**。`OfficialAnkiMappingSuggestion` 以 notetype 为主键，只有方向、启用题型、确认状态和版本，无法表达按面布局、有序媒体、条件与回退。

## 决策

### 1. 单一解析器：`CardPresentationResolver`

一切「这张卡怎么展示」的判定收敛到一个解析器，预览、v2 视图摘要、课时加载共用；正式复习在 P7 以 `formalReview` 约束调用同一解析器。

- 输入：读取上下文（staging / live、source、snapshot）、卡级事实、适配方案、用户偏好、设备能力。
- 输出：类型化结果——结构化展示 / 原卡 / 需修正 / 不可用，附原因码与版本。
- 视图行只存**计划引用与预计 kind**，实际卡面必须在加载时重新验证。过期的 `presentationKind` 不是绕过内容检查的权威。
- `_resolvePrimaryKind`、课时内 `archetypeViolated` 临时降级、`_kindFor` 的「未知 kind 降 flip」随本决策收敛，不保留为第四条路径。

### 2. 适配方案是唯一配置载体

引入 `CardAdaptationPlan`：只保存「如何解释内容」的决策，不保存样本卡全文、逐卡卡面或媒体字节。原始内容唯一事实源仍是 Collection 与其媒体目录；catalog 不新增卡面、字段、模板长期副本。

### 3. 作用域：source + notetype + 模板身份

- 普通卡用真实模板编号；Cloze 的 card ordinal 可能指向具体挖空编号，**不能当普通模板索引**。
- **方向按模板判定，不按笔记类型判定。** 一个笔记类型可以同时有正向模板与反向模板；正面渲染的是答案角色字段的那个模板，就是反向卡。把方向记在笔记类型上会让反向卡的答案出现在题面。
- 适配身份显式区分模板身份与 cloze 目标：一份 Cloze 方案复用整组，当前卡的挖空目标作为运行参数传入。
- 同一 notetype 跨牌组共享时，人工修正默认不传播到其他来源；跨来源只复用可重新绑定的结构配置，并再次验证。

### 4. 优先级与回退

单卡人工覆盖 > 当前来源内模板人工方案 > 当前来源内模板已确认方案 > 本地自动方案 > 原卡。

「原卡」是一等结果，不是失败态。无法证明可安全转换的内容一律回原卡；不因识别置信度高就把复杂卡自动化。

### 5. 按面有序的内容块

`CardDocument` 含 front / back，每面为有序 `CardBlock`。块只引用「字段序号 + 选取方式」，不内联字段内容；同一音频可以有意出现两次，所以块身份不是文件名。当前实现的块类型只有四种：`text`、`richText`、`imageGroup`、`audioGroup`——只声明渲染器真的能表达的东西，未知类型在校验阶段就被拒。视频、Cloze 块与容器组是后续增量，届时作为新块类型加入词表，而不是先声明再慢慢实现。

渲染边界：当前**按块决定内容落在哪一面**，不做同一面内文本与媒体的交错排版——flip 渲染器先文本后媒体，真正的交错版面需要独立的卡片文档渲染器，属后续增量。块点名了渲染器表达不了的结构（脚本、内嵌媒体、表格等）时，整张卡回原卡，不渲染半份布局。

`MediaReference` 区分文件资源、展示 occurrence、TTS 请求、外部 URL；可用性至少区分可播放、源包未提供、用户未导入、设备不支持、引用受限、未知待检查。

面归属的事实来源是**每个模板的正/背字段序号**，随映射决策一起落在配置区（`templateFaces`），因此解析器不需要为每张卡再问一次引擎。旧决策没有这份事实时，面归属视为未证：媒体只能留在答案面，flip 卡整张回原卡——不按文件名或字段顺序猜面。

### 6. 激活协议：不可变修订 + 单键 manifest 切换

配置区键族（`turna.` 前缀，值恒为 JSON object）：

| 键 | 内容 |
|---|---|
| `turna.adapt.plan.<planId>.r<revision>` | 不可变方案体（`r` 前缀避免 planId 里的点与键分隔符混淆） |
| `turna.adapt.manifest.<sourceId>` | scopeKey → `{planId, revision}` 的 active 清单 |
| `turna.adapt.cards.<sourceId>` | 单卡覆盖（按来源一张小表，不逐卡建键） |
| `turna.adapt.index.<sourceId>` | 该来源写过的 plan 键清单（GC / 卸载清理用） |

先写候选修订并验证，最后一次写 manifest 切换 active。读取端只认 manifest 引用的完整修订，不使用散落候选；manifest 引用的修订缺失时回原卡，不拼接半份方案。

`SET_CONFIG` 单键写具备事务语义，多键不等于天然跨键原子——本决策不宣称多次调用整体原子，靠「先 revision 后 manifest」的顺序保证可恢复。

### 7. AI 只生成声明式配置

AI 经 `AiEngine.requestJson` 生成受约束的声明式方案：无脚本、无网络请求、无文件路径、无动态代码。scope、指纹与审计信息由应用附加，AI 不能指定别的 source 或 cardId。校验分四层：JSON Schema → 字段/模板/来源一致性 → 语义（答案不泄露、媒体可见性可解释）→ 本地全组逐卡验证。任一层不过即不进入 active。

AI 失败不导致导入失败：可继续用本地结果或原卡。

### 8. 正式复习首期维持原卡

第一阶段 `formalReview` 模式的解析结果恒为原卡优先。改动题面方向或增加提示会改变回忆难度，属独立决策；启用时只替换 presentation 解析，不替换队列、锁、answer token、评分确认或结算。

### 9. 新增展示是 opt-in，不是默认

看图回忆、听写这类新练习会改变任务本身（不是排版），因此只在用户于映射页显式选中对应预设时启用，并且卡面必须能证明前提：看图回忆要求正面图已证，听写要求正面音频已证、答案足够短。前提不成立时退回到已有的翻卡/原卡路径，不承诺一个残缺的练习。默认预设不变——旧导入与未改动映射的展示结果保持原样。

## 协议草案

```json
{
  "schemaVersion": 1,
  "planId": "plan-7f3a",
  "revision": 2,
  "scope": {
    "sourceId": "src-1",
    "notetypeId": 1654676743,
    "templateOrdinal": 0
  },
  "fingerprints": {
    "schema": "…",
    "templateFacts": "…"
  },
  "origin": "aiCandidate",
  "bindings": {"prompt": 0, "answer": 1},
  "front": [
    {"kind": "text", "fieldIndex": 0},
    {"kind": "audioGroup", "fieldIndex": 2, "selection": "all"}
  ],
  "back": [
    {"kind": "text", "fieldIndex": 1},
    {"kind": "imageGroup", "fieldIndex": 3, "selection": "all"},
    {"kind": "richText", "fieldIndex": 4}
  ],
  "defaultExercise": "flip",
  "optionalExercises": ["dictation"],
  "fallback": "original",
  "provenance": {"recognizer": "rules-3", "model": "<configured>", "confirmed": false}
}
```

`bindings` 是「角色 → 字段序号」的扁平表，角色词表与识别层一致（prompt / answer / pronunciation / example / audio / image / options）。`fallback` 目前只接受 `original`：「人工修正」与「不可用」是解析器的结果态，不是方案里可选的回退方式。

`selection=all` 只表示选择该字段内全部已提取 occurrence，不绕过媒体解析；`richText` 只支持已实现的子集，含不支持结构即回原卡。字段值不通过字符串拼接进入任意 HTML。

## 备选与否决

- **只扩 `CardRecognizer`**：视图、课时、正式复习各自有决策路径，改识别器只改其中一条。
- **只把 `audio` / `image` 改成 `List`**：仍丢正反面、混排顺序、字段来源与答案关系，等于把三个缺陷中的一个换成另一个。
- **按 notetype 内逐卡重分类**：与「笔记类型作为共享结构、只验证不重分类」的既有纪律冲突；现有 `values` 对 basicPair 的局部升级应显式建模为受约束变体，而不是继续叠加隐式分支。
- **把模板原文塞进 AI 输入**：Rust 投影的 `forbidden_keys` 明确禁止输出 `qfmt` / `afmt` / `css`。AI 只能看派生结构事实，不能看模板源码。

## 影响与边界

- `application → data` 的跨层禁则不变：方案读写经引擎配置区，仓储接口在 `lib/domain/repositories/`，不照抄现有白名单的例外。
- 不因新增展示提升数据库 schema；只有确需改变派生视图结构时才迁移，版本号现场读取。
- 鸿蒙伴生版：本地识别、原卡与已实现展示照旧；不开放 AI 生成（ADR 0056）。导入带来的现成适配配置能否解释，按组件能力白名单决定。
- 未决：共享 collection 的重导所有权仍按 `docs/status.md` 的开放决策处理，本功能不以「适配成功」替代该策略。
