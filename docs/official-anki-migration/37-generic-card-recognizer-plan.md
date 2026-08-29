# 37 — 通用卡片识别器重设计（导入识别推倒重来）

> 状态：**提案（待批准施工）**。本文是施工计划，未开工。
> 范围：替换 Anki 导入/投影链路里的两层识别器（notetype 字段角色映射 + 逐卡形态分类），收敛类型体系，重构预览 UI 的识别信息展示。**不改变**渲染、调度、备份、导入 saga、官方 collection 数据所有权。
> 前置阅读：[30](./30-course-like-card-experience-plan.md)（现行识别器的来源，其「自动题型识别」部分由本文取代）、[34](./34-official-anki-production-cutover-and-ohos-retirement-plan.md)（契约与发布面口径）、[36](./36-projection-tree-ordering-and-limits.md)（投影写入语义）。
> 铁律：**识别器只认结构、不认内容题材**。任何主题词/学科词（"考研""政治"之类）出现在识别代码或词典里即为设计失败。

## 0. 一句话

把「每张卡跑 8 条内容启发式规则 + 字段名 if-else 关键词梯」的识别器，替换为「读集合声明的结构事实（notetype kind / reqs / 模板 filter / 字段词典 / 位置先验）→ notetype 级一次判定 → 卡级只做校验与抽取」的证据驱动识别器；全链路类型体系从四套收敛为一套；识别开销从随卡数线性（2 万卡秒级）降到随 notetype 数（毫秒级）。

## 1. 背景与根因（施工前）

### 1.1 现状识别器是两个互不通信的组件

- **识别器 B（notetype 级字段角色映射）**：`OfficialAnkiProjectionMapper.suggest()`（`lib/application/anki_official/projection/official_anki_projection_mapper.dart:180`）。`_candidatesFor()`（:300–447）是一条内联上百个中英文关键词的 if-else 梯；识别不到按位置兜底 `positional:front/back`（:218–250）。在预览阶段运行，结果落 `anki_projection_mappings`。
- **识别器 A（卡片级形态分类）**：`AnkiPracticeCardClassifier.classify()`（`lib/application/anki_practice/card_classifier.dart:29–282`），8 条有序规则 + 魔法阈值。在投影阶段对**每张卡**运行（`official_anki_projection_payloads.dart:98`）。

### 1.2 六个结构性缺陷（均已代码核实）

1. **本末倒置**：apkg 集合里声明的结构事实（cloze 类型、模板 `{{type:}}`、reqs 字段依赖、字段名与顺序）是权威信号，现状却以内容启发式（文本长度、句式）为主信号，领域一变即失灵——这是"不通用"的根源。
2. **模板钩子是死代码**：分类器模型留了 `qfmt/afmt/isCloze/notetypeName` 字段（`card_classifier_models.dart:5–15`），但官方投影路径构造输入时**从不传**（`payloads.dart:85–97`）；Rust 契约侧 `projection.rs:117–128` 的 `forbidden_keys` 政策性禁传模板。
3. **逐卡分类导致兄弟卡漂移**：同一 note 的多张卡各自跑规则可能得到不同形态。
4. **四套类型体系串转换**：`AnkiPracticeShape`(8) → `OfficialAnkiProjectionKind`(9) → `CardPresentationKind`(7) → UI 的 `ImportRecognitionAttention`，转换散在 `CardPresentationPolicy` 与 payloads。
5. **职责混杂**：classifier 同时做分类、字段抽取、MCQ 选项解析与答案对齐。
6. **词表不可演进**：关键词内联在代码；`classifierVersion` 字段存在但恒为 1。复习侧 `_classify()`（`official_anki_practice_review_surface.dart:109–119`）甚至不跑识别器、硬编码 flip——投影分类与复习展示已经脱节。

### 1.3 可行性调研结论（2026-08-29，内外两路核查）

**内部六前提**：

| 前提 | 判定 | 关键事实 |
|---|---|---|
| 模板事实可得 | 成立 | `col.get_notetype` 返回的 Notetype 已含 qfmt/afmt/CSS/**reqs**（rslib `notetype/mod.rs:84–93`、`notetypes.proto:48–115`）；bridge 只是政策性不序列化。`reqs` 是官方预计算好的"每张卡依赖哪些字段"结构化结果 |
| 契约可 bump | 成立 | 纯增量 = minor bump 1.8→1.9；历史 minor +8 次、major 0 次；fail-fast 只卡 major |
| 多平台可重建 | 有条件成立 | Android arm64 有冻结构建脚本（唯一打包平台）；Windows/macOS 原生库未接线（本次不涉及） |
| 映射表可扩展 | 成立 | `schemaFingerprint/userConfirmed/mappingVersion` 列已存在；新字段放 `mapping_json` 零 SQL 迁移 |
| notetype 级判定更快 | 成立 | 现状每卡约 10 趟正则扫全字段；notetype 只有个位数~十位数 |
| 原型可持久化 | 有条件成立 | per-card `projection_kind` 已落 `official_anki_projection_index`；复习页零读取（本计划范围外，见 §9 风险 R2） |

**外部先例**：业界无一家做内容启发式分类。Anki 官方 CSV 导入 = 每列映射 + 用户确认；Mochi/RemNote = 全自动有损模板转换（社区有抱怨）；NextLang = 手动挑 front/back。GitHub 无同题开源项目。官方手册确认 cloze 判定以 notetype type 为准（社区存在 cloze 型当 basic 用的反例，需内容校验兜底）；`{{type:}}` 每卡至多一个。

**最弱假设**：字段词典覆盖率无量化数据（AnkiWeb 反爬，无法统计共享牌组）。对策：结构信号为主、词典为辅；P3 并行 diff 实测命中率。

## 2. 目标与非目标

### 2.1 目标

1. **通用性**：领域差异只进数据（词典、fixture 语料），永不进控制流。
2. **结构优先**：notetype kind、reqs、模板 filter、字段名、位置先验为权威信号；内容启发式只做次级证据。
3. **单一类型体系**：一套 `CardArchetype` 枚举贯穿识别、投影 policy、UI。
4. **notetype 级判定**：同一 notetype 的所有卡共享结论，兄弟卡漂移从机制上消失。
5. **可解释**：每个结论携带 evidence 列表，UI 可直接展示"为什么"。
6. **可演进**：`recognizerVersion` / `lexiconVersion` 真递增并落库；词典是版本化数据。
7. **性能**：识别开销与卡数解耦；2 万卡牌组的 Dart 侧识别成本降到毫秒级。
8. **识别永不阻塞导入**：低置信走兜底原型 + 用户确认，不走 blocking。

### 2.2 非目标

- 不做主题/学科猜测；不引入 LLM（v1；将来若做只作为低置信场景的辅助信号填入同一证据框架）。
- 不动复习侧渲染路线（RENDER_CARD 原生 HTML vs 投影交互的取舍）——单独立项。
- 不做 Windows/macOS 原生库接线。
- 不改导入 saga、备份、调度、官方 collection 数据所有权。
- 不重排导入向导整体信息架构（仅重构识别相关的预览/映射部分）。

## 3. 架构设计

### 3.1 管线分层

```
apkg ──rslib──> 官方 collection
                 │ get_projection_schemas（契约 1.9：+templateFacts，samples 上限 30）
                 ▼
   ┌────────────────────────────┐
   │ L0 事实提取 facts/           │ schema+samples+模板事实 → 纯数据 Facts
   └──────────────┬─────────────┘
                  ▼
   ┌────────────────────────────┐
   │ L1 角色绑定 bind             │ 词典+位置先验+reqs+值形状 → 字段→角色最优分配
   └──────────────┬─────────────┘
                  ▼
   ┌────────────────────────────┐
   │ L2 原型判定 archetype        │ 声明式规则表打分（结构信号优先）→ 带证据的结论
   └──────────────┬─────────────┘
                  ▼
   ┌────────────────────────────┐
   │ L3 卡级校验/抽取（投影期）    │ 按既定 (roles, archetype) 逐卡抽取；
   │                            │ 违反原型的卡降级 richHtml + archetype_violation
   └──────────────┬─────────────┘
                  ▼
   │ L4 policy 薄层：原型 × 用户偏好(enabledKinds/presets) → OfficialAnkiProjectionKind
```

### 3.2 模块布局

```
lib/application/anki_import/recognition/
  config.dart                // 全部阈值/权重/置信度分带，唯一调参点
  facts/
    notetype_facts.dart      // 契约 schema → 结构事实（kind/reqs/模板 filter/字段表）
    card_facts.dart          // 单卡事实（文本度量、媒体引用、cloze 标记、选项结构）
    text_metrics.dart        // 纯函数：长度/句子性/正则化（收编 card_text.dart）
    options_structure.dart   // 内嵌选项解析（收编 embedded_options.dart）
  lexicon/
    field_roles.dart         // 角色同义词表（数据，en/zh 首批），lexiconVersion
  recognize/
    archetypes.dart          // CardArchetype 枚举 + 声明式规则注册表
    recognizer.dart          // 入口：recognizeNotetype(schema, samples) → RecognitionResult
    binding.dart             // 角色分配求解（贪心+冲突回退；n 小，无需匈牙利）
    result.dart              // RecognitionResult / FieldBinding / Evidence
  policy/
    presentation_policy.dart // 薄层：原型×偏好→投影 kind（替代 CardPresentationPolicy 的分类转换职责）
```

### 3.3 核心数据结构

```dart
/// 全链路唯一原型枚举（识别/投影 policy/UI 共用）。
enum CardArchetype {
  richHtml,   // 模板含脚本/复杂结构 → 保真渲染（原 fidelity/canonicalLink）
  cloze,      // 集合声明 cloze（或样本强证据）
  choice,     // 有选项结构（字段池或内嵌选项）
  audioFirst, // 正面音频驱动
  typeIn,     // 模板含 {{type:}}
  basicPair,  // 正反两面文本对（最通用兜底，原 flip）
}

enum FieldRole {
  prompt,     // 正面（替代 targetText —— "target/native" 嵌入了语言学习假设）
  response,   // 背面；方向(direction)降级为 mapping 选项，不是角色名
  options, audio, image, pronunciation, example, hint, extra, ignored,
}

class RecognitionResult {
  final CardArchetype archetype;
  final double confidence;
  final List<Evidence> evidence;            // {signal, weight, detail}
  final Map<FieldRole, FieldBinding> roles; // role → {fieldIndex, confidence, evidence}
  final String templateFactsHash;           // 识别缓存失效键（区别于用户映射指纹）
  final int recognizerVersion;
  final int lexiconVersion;
}
```

持久化：`OfficialAnkiMappingSuggestion.toJson()` 增加上述字段（`archetype`/`recognizerVersion`/`lexiconVersion`/`templateFactsHash`），旧 JSON 反序列化给默认值——**零 SQL 迁移**，`anki_projection_mappings` 表不动。

### 3.4 L0 契约扩展（1.8 → 1.9）

`get_projection_schemas` 的每个 notetype 增加派生对象 `templateFacts`（不回传原始模板文本）：

```
templateFacts: {
  hash,                                  // sha256(模板内容+reqs)，识别缓存失效用
  templates: [{
    ord, name,
    frontFields: [...], backFields: [...],   // 经 ParsedTemplate::from_text 提取的每面字段引用
    filters: { typeIn: bool, tts: [...], hint: [...] },
  }],
  reqs: [{ cardOrd, kind: NONE|ANY|ALL, fieldOrds: [...] }],  // 直接序列化 nt.config.reqs
}
```

实现要点（Rust 侧全是"序列化已在手的数据"）：

- reqs 直接取 `Notetype.config.reqs`；每面字段引用用 `ParsedTemplate::from_text`（rslib `templates.rs:19–25`）。
- **键名天然不命中 `forbidden_keys` 禁词表**（qfmt/afmt/css/revlog/...），无需放宽政策；实现中若 tempted 加含禁词子串的键名，改名而不是改禁词表。
- samples 上限 10 → **30**（默认仍 3），预览识别请求显式传 30；DB 顺序前 N 保持不变（随机化不做，减少变量）。
- `schemaFingerprint` 公式**不变**（仍 name+fieldNames+templateNames）——避免存量已确认映射集体失效；模板变化用独立的 `templateFactsHash` 触发**识别结果**重算，不触发用户映射 needsReview。
- 契约版本四处同步：`contract/VERSION`、`bridge/src/contract.rs:16`、`lib/.../official_anki_contract.dart`、`contract/operations.md`。Dart 旧 minor 忽略未知字段，天然向后兼容。
- 不新增 operation（复用现有 op 的响应字段），不消耗 OP 编号。

### 3.5 L1 角色绑定：信号与权重（v1，全部集中于 config.dart）

| 信号 | 层 | 指向角色 | 权重 |
|---|---|---|---|
| 字段名规范化后精确命中词典 | 词典 | 对应角色 | 0.55 |
| 字段名包含命中（复合名如 `VocabKanji`） | 词典 | 对应角色 | 0.35 |
| reqs：字段出现于正面模板 | 结构 | prompt | 0.30 |
| reqs：字段仅出现于背面模板 | 结构 | response | 0.30 |
| 位置先验 field[0] / field[1] | 结构 | prompt / response | 0.25 / 0.25 |
| 样本值含 `[sound:` | 内容 | audio | 0.50 |
| 样本值含 `<img` | 内容 | image | 0.50 |
| 样本值纯短文本 | 内容 | prompt/response 增益 | +0.10 |

规范化：小写、去 `_ - 空格` 分隔符再匹配；词典只收**结构性**同义词（front/正面/question/题干、back/背面/answer/答案、audio/发音/音频、image/图片/遮图、option/选项、pronunciation/音标/拼音、example/例句……en/zh 首批），永不收主题词。

求解：每字段对各角色得分，全局贪心（最高分先占位，冲突者取次优），权重和封顶 1.0。字段数典型 2–10（社区上限约 220），贪心与最优解差异可忽略，不引入匈牙利算法。

### 3.6 L2 原型判定：声明式规则表（v1）

| # | 规则 | 信号层 | 目标原型 | 权重 | 备注 |
|---|---|---|---|---|---|
| A1 | notetype kind == cloze | 结构 | cloze | 1.00 | 官方权威语义 |
| A2 | 模板含 script/事件属性/javascript: 或 table/svg/audio/iframe 等复杂标签 | 结构 | richHtml | 1.00 | 现行"铁律"语义保留 |
| A3 | 模板含 `{{type:` | 结构 | typeIn | 0.95 | |
| A4 | options 角色已绑定且 response 可定位 | 绑定 | choice | 0.90 | |
| A5 | 样本 `{{cN::}}` 标记率 ≥ 60% | 内容 | cloze | 0.85 | 兼容"cloze 型当 basic 用"反例 |
| A6 | 样本内嵌选项结构率 ≥ 60% | 内容 | choice | 0.80 | 解析失败铁律→richHtml 保留 |
| A7 | 正面音频 + 短答案样本率 ≥ 60% | 内容 | audioFirst | 0.80 | |
| A8 | 短-短对（非句子）样本率 ≥ 60% | 内容 | basicPair | 0.75 | |
| A9 | 默认 | — | basicPair | 0.50 | |

聚合方式：各规则产生带权证据，**最高权重命中者胜**（非顺序短路）；并列时结构信号 > 绑定信号 > 内容信号。与现状 8 条 if-else 的本质区别：加规则不改其他规则的语义。

置信度分带（作用于整体结论）：

| 带 | 阈值 | 行为 |
|---|---|---|
| auto | ≥ 0.85 | 自动采用 |
| review | 0.60–0.85 | 可导入，预览页标"建议确认" |
| fallback | < 0.60 | 落 basicPair + 标记确认 |

现状五态 `OfficialAnkiMappingStatus` 收敛为三态 `auto / review / manual`；UI 的第四套 `ImportRecognitionAttention` 分级删除。

### 3.7 L3 卡级校验与抽取（投影期）

- 投影开始时按 notetype 取得 `RecognitionResult`（存量已确认映射优先，见 §5），构造 `RecognitionPlan`（原型 + 角色绑定 + 启用集），逐卡**只做抽取**：按绑定取 prompt/response/options/audio/...，cloze 拆 ordinal，内嵌选项解析。
- 卡级违反原型（如声明 cloze 但该卡无标记、choice 但选项对齐失败）→ 该卡降级 `richHtml`（canonicalLink），记 evidence `archetype_violation`——铁律语义从"分类阶段短路"移到"校验阶段降级"。
- sibling 干扰项池逻辑（projector:190–203）不动，仍属投影组课职责。

### 3.8 L4 policy 薄层：原型 → 投影 kind

| 原型 | 默认 kind | 受 enabledKinds 约束 | 特殊条件（维持现行语义） |
|---|---|---|---|
| richHtml | canonicalLink | — | |
| cloze | fillBlank | — | |
| choice | multipleChoice / multiSelect | multipleChoice/multiSelect | correctIndices ≥ 2 → multiSelect |
| audioFirst | listenPick | listenPick | 无音频或未启用 → flip |
| typeIn | typeAnswer | typeAnswer | 维持现行"需有音频"约束（`card_presentation_policy.dart:81–88`），放宽与否留待产品决策 |
| basicPair | flip | flip / showWord | |

## 4. UI 改造（预览"四件套"）

预览页（`official_anki_import_preview.dart`）每个 notetype 一张卡，只暴露四类信息：

1. **样卡预览**：按绑定渲染 1–2 张真实样本的正面 → 背面；
2. **原型 chip + 置信度带**：`填空 · auto`；
3. **证据展开**：evidence 列表直接人类可读化（复用现有 evidence 字符串习惯）；
4. **覆盖操作**：换原型 / 调角色绑定 / 跳过，保存路径不变（`confirmMapping`/`skipNotetype`）。

配套收敛：`ImportRecognitionAttention` 分级（`anki_import_view_helpers.dart:11–47`）删除；`official_anki_mapping_page.dart` 折叠进预览步骤（保留深链入口一个版本）；`OfficialExercisePreset` 属用户偏好层（policy 输入），保留。

## 5. 数据与持久化

- 读写时序不变：预览 = 每 schema 现算 `recognizerNotetype` → 与存量合并（`_mergeAndPersistMappings`，service:922–1009）→ 用户确认落库；投影 = 已确认行直接复用，未确认行用现算结果 + review 态提示。
- 存量行为：`user_confirmed=1` 的行**完全不动**（继续按既有 mapping_json 生效）；未确认行换用新识别器结果属预期改进，不需要迁移。
- `templateFactsHash` 变化 → 只重算识别建议，不把已确认映射置 needsReview（与 schemaFingerprint 变化的语义 deliberately 不同）。

## 6. 分阶段施工计划

> 每阶段独立可合并、可回滚；P1–P3 零用户可见行为变化。工作量按单人专注口径估算。

### P1 Rust 契约 + templateFacts（1–2 天）

- [ ] `projection.rs`：`get_projection_schemas` 响应加 `templateFacts`（reqs 序列化 + `ParsedTemplate` 提取 frontFields/backFields/filters + hash）
- [ ] samples 上限 10→30（请求参数化，默认 3 不变）
- [ ] 契约 1.8→1.9 四处同步（VERSION / contract.rs / Dart 常量 / operations.md）
- [ ] fixture 新增 3 个 notetype 场景：`{{type:}}`、选项池字段（A|B|C 分隔）、中文复合字段名；跑 `turna_anki_gen_fixtures` 更新 golden（注意 regen 会换 card id）
- [ ] Dart DTO：`OfficialAnkiProjectionSchema` 加 `templateFacts` 解析，缺字段默认空

验收：`cd native/turna_anki_core && cargo test` 全绿（含 forbidden_keys 反向断言更新）；contract golden 更新；`flutter test test/application/anki_official` 现有 9 个 apkg fixture 全绿（契约向后兼容证明）。

### P2 Dart 识别器模块 + 金标准语料（1.5–2 周）

- [ ] `recognition/` 目录按 §3.2 落地，纯 Dart、零 UI 依赖
- [ ] `config.dart` 集中全部权重/阈值/分带
- [ ] 词典 v1（en/zh 结构词），`lexiconVersion=1`
- [ ] 金标准语料：`test/fixtures/anki_recognition/corpus/*.json`，格式 `{schema(含 templateFacts+samples), expected: {archetype, roles, band}}`；首批 ≥ 16 案例覆盖矩阵：

| # | 场景 | 期望原型 | 考验信号 |
|---|---|---|---|
| 1 | Front/Back 基础 | basicPair/auto | 词典+位置 |
| 2 | 正面/背面 中文 | basicPair/auto | zh 词典 |
| 3 | kind=cloze 声明 | cloze/auto | A1 |
| 4 | standard 型但样本含 `{{c1::}}` | cloze/review | A5 反例 |
| 5 | 模板含 `{{type:}}` | typeIn/auto | A3 |
| 6 | 选项池字段 `A|B|C|D` + 答案字段 | choice/auto | A4 |
| 7 | 正面内嵌 A. B. C. 选项 | choice/auto | A6 |
| 8 | 内嵌选项但答案对不上 | richHtml | 铁律降级 |
| 9 | 正面音频 + 单词背面 | audioFirst/auto | A7 |
| 10 | Expression/Reading/Meaning/Audio 四字段 | basicPair + 绑定 | 复合绑定 |
| 11 | 模板含 `<script>` / table | richHtml/auto | A2 |
| 12 | 单字段 notetype | basicPair/review | 兜底 |
| 13 | 三字段全陌生命名 | basicPair/review | 位置先验 |
| 14 | mask/occlusion 图片字段 | basicPair + image 绑定 | 值形状 |
| 15 | 空背面样本 | review | 边界 |
| 16 | 模板 `{{tts:}}` filter | basicPair + audio 绑定 | filters |

- [ ] 单测：词典匹配/规范化、绑定求解（含冲突）、文本度量、规则表各条、分带
- [ ] 快照测试：语料全量 → RecognitionResult 快照（含 evidence）

验收：`flutter analyze` 0 新增 issue；新增单测+快照全绿。

### P3 并行 diff harness（2–3 天）

- [ ] feature flag `TURNA_RECOGNIZER_V2`（dart-define；**必须真实控制投影走新/旧识别器**——吸取 legacyMirror/diagnostics 死 flag 教训，P5 删除）
- [ ] diff 工具：同一 fixture 集合双跑新旧识别器，输出逐 notetype/逐卡 diff 报告（原型不一致、kind 不一致、绑定不一致）
- [ ] 跑 9 个 apkg fixture + 不少于 5 个手工真实牌组（含中文字段名、语言学习、题库类各至少 1）
- [ ] 度量三项：结构场景（A1–A4 命中）新旧一致率；词典命中率（无人工干预完成绑定比例）；低置信率（<0.6）

**Go/No-Go 门禁**（进入 P4 的硬条件）：
1. 结构可判定场景：新识别器与旧一致或"旧误判、新正确"，**零"新劣化"**（逐条人工复核 diff 报告）；
2. 词典命中率 ≥ 80%；
3. 低置信率 ≤ 20%；
4. 9 个 apkg fixture 投影产物 diff 全部可解释。

### P4 policy 切换 + 预览 UI（约 1 周）

- [ ] payloads 改为消费 `RecognitionPlan` 逐卡抽取（`AnkiPracticeCardInput`/classify 调用点替换）
- [ ] `CardPresentationPolicy` 重写为 §3.8 薄表；`OfficialAnkiMappingStatus` 收敛三态
- [ ] 预览页四件套改造；删 `ImportRecognitionAttention`
- [ ] flag 默认 false 合入，真机 dogfood 后一行切换默认 true

验收：`flutter test test/application/anki_official -j1` 全绿（与基线 flake 口径对齐 doc 36）；golden 无意外 diff；flag 开/关双跑 fixture 一致性符合 P3 预期。

### P5 删除旧识别器 + 版本收口（2–3 天）

- [ ] 删 `card_classifier.dart`、`card_classifier_models.dart`、`embedded_options.dart`、`official_anki_projection_mapper.dart`（`card_text.dart` 并入 `text_metrics.dart`）；guard test 断言 0 引用（沿用 doc 35 惯例）
- [ ] 测试迁移：`card_classifier_test.dart` 11 例映射进语料快照；`embedded_options_test.dart` → `options_structure_test.dart`
- [ ] `recognizerVersion=1` 落 mapping_json；未确认映射下次预览自动重建议
- [ ] 删 flag；更新 README 索引、`CHANGELOG.md`、MEMORY

验收：全量 `flutter test` 0 新增失败；analyze 0 新增。

## 7. 测试策略（四层）

1. **单测**：信号提取、词典、绑定求解、规则表、分带——全部纯函数。
2. **语料快照**：`corpus/*.json` → RecognitionResult 快照，词典/规则任何改动必须显式更新快照（reviewable）。
3. **回归**：现有 9 个 apkg fixture 的投影测试贯穿 P1/P3/P4 不变绿不合并。
4. **并行 diff**：P3 harness 保留到 P5 删除前，供后续词典迭代复用。

## 8. 风险与对策

| # | 风险 | 等级 | 对策 |
|---|---|---|---|
| R1 | 词典覆盖率无统计支撑 | 中 | 结构信号为主（词典最差场景恰是 reqs/位置先验最强场景）；P3 实测命中率，门槛 80% |
| R2 | 复习链路整合牵涉产品决策 | 中 | 与本计划解耦：识别器先落投影侧；复习侧读 `official_anki_projection_index` 单独立项 |
| R3 | 契约升级需重建 Android 原生库 | 低 | 冻结工具链一条命令（build-android/build.sh）；产物 gitignored 本就每次构建 |
| R4 | 存量用户映射迁移 | 低 | user_confirmed 行不动；新字段零 SQL 迁移 |
| R5 | 行为变化引发用户感知 | 低 | P4 flag 灰度 + P3 diff 报告逐条复核 |
| R6 | samples 前 30 条不具代表性（DB 顺序） | 低 | v1 接受；若 diff 显示偏差，P4 前加随机抽样参数（契约已有 minor 余量） |

## 9. 与既有文档的关系

- doc 30 的「自动题型识别」章节：**由本文取代**；其渲染/动画/语言课体验部分不受影响。
- doc 34：契约 minor bump 与 Android 重建遵循其工具链口径。
- doc 36：投影写入语义（排序/限额/指纹）不动；`officialAnkiProjectionAlgorithmVersion` 不因本计划递增（树结构不变，只有 kind 赋值可能变化，走 `recognizerVersion` 失效）。

## 10. 施工实录：与计划的差异

（施工时填写；按目录惯例记录实际 commit、命令、指标与偏离。）
