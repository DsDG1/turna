# 30 — 官方 Anki 卡按语言课体验投影与渲染

> 文档代号：P-COURSE-LIKE-CARD  
> 日期：2026-08-20  
> 状态：**Host / Unit 已通过**；生产默认未翻（课化复习、课程入口、chrome）。产品收口见 [`31`](./31-anki-product-experience-plan.md)。  
> 前置：ADR [`0036`](../decisions/0036-official-anki-core-migration.md)、[`09`](./archive/09-p2-entry-remediation-and-phase-3-plan.md) P3-051、[`11`](./archive/11-p3-remediation-and-phase-4-scheduler-plan.md)、[`29`](./archive/29-p5e-wave1-production-decoupling-report.md)  
> 目标：在**不撤回官方 Anki 核心**的前提下，把导入卡重新变成「像语言课一样」的 Flutter 练习：自动识别题型、生词卡/选择/听音/填空、翻面或展开动画，评分仍写官方 Scheduler。

本文是逐步施工手册，不是愿景草稿。每一阶段都可以单独开 PR、单独测试、单独回滚。

---

## 0. 一句话

官方 `rslib` 继续负责 Collection / 模板 / FSRS。Turna 只把**够简单的卡**投影成现有语言课 `Interaction`，用现有 `InteractionRenderer` 画出来；画不了的卡继续走隔离 WebView。

---

## 1. 背景：丢了什么，什么必须留下

### 1.1 曾经的自研方案（体验层）

Legacy 路径在导入时做三件事：

1. `AnkiCardAdapter.inferMapping` 按 notetype 字段名猜类型（词汇 / 挖空 / 选择题 / 翻面）。
2. `AnkiCardAdapter._autoDecide` **按卡**升级：Cloze → 填空，题干 A/B/C → 选择，正面音频 → 听音，短答案 → 选择或打字，其余 → 翻面。
3. 课程里用 Flutter 渲染器画：`AnkiCardRenderer`（点按翻面 + 缩放脉冲）、`MultipleChoiceRenderer`、`FillBlankRenderer`、`ListenAndPickRenderer`、`ShowWordRenderer`（大号词 + TTS）。

语言课本身的模型见 [`docs/authoring/lesson-type-templates.md`](../authoring/lesson-type-templates.md)：intro 课先 `showWord` 见面，再 `multipleChoice` / `fillBlank` / `listenAndPick`。

### 1.2 现在的官方方案（真源层）

官方投影（P3）把卡变成课程项，但判定极保守：

| 现状 | 文件 | 结果 |
|---|---|---|
| 字段角色只认英文名 `Front/Back/target/native` | `official_anki_projection_mapper.dart` | 中文「正面/反面」、Cloze、题干选项经常 `needsConfirm` |
| 映射不完整 → 只出 `canonicalLink` | `official_anki_projection_payloads.dart` `kindsFor()` | 打开 WebView 预览 |
| 正式复习是网页换面 | `official_anki_review_page.dart` | 「Show Answer」后直接换 HTML，无动画、无语言课卡片壳 |
| 派生练习不写官方调度 | [`09`](./archive/09-p2-entry-remediation-and-phase-3-plan.md) P3-051 | 课程里练了，主复习队列不知道 |

`AnkiCardRenderer` 和语言课 renderer **都还在**，只是官方投影几乎喂不进去。

### 1.3 必须留下的铁律

1. 官方 Collection 是唯一 Anki 事实源。不恢复自研 `.apkg` 解析 / 模板引擎 / Scheduler。
2. `lib/application/anki_official/` **禁止** import `package:turna/application/anki/` 或 `package:turna/views/anki/`（P5-E Wave 1，`official_anki_forbidden_imports_test.dart`）。分类器必须放在共享目录，不能直接复用 `anki_card_adapter.dart`。
3. 复杂原卡（`<script>`、MathJax、自定义 CSS、拆不出的「像选择题」）走隔离 WebView。禁止用牌组 distractor 冒充选项。
4. 派生练习不得改写官方 Note/Card/模板。投影可重建、可失效。
5. 不对 Android 平台 WebView 做 3D `rotateY`。旧版 300px 3D 翻转已因卡顿删除。
6. 不把 `canonicalLink` 预览偷偷变成一次正式评分。

---

## 2. 目标架构

```text
官方 Collection（rslib）
        │  字段 + 渲染后的 question/answer 文本 + 媒体标记
        ▼
共享分类器  lib/application/anki_practice/card_classifier.dart
        │  每张卡 → Vocab | Expression | Cloze | Quiz | Listen | Fidelity
        ▼
官方投影    OfficialAnkiProjectionPayloads.kindsFor()
        │  一卡可多 kind（介绍 + 练习），写入 CourseDatabase
        ▼
┌───────────────────────┬──────────────────────────────┐
│ 语言课轨（Flutter）     │ 保真轨（官方 WebView）          │
│ ShowWord / MCQ /      │ canonicalLink + 展开揭示外壳    │
│ Listen / FillBlank /  │                               │
│ TypeTheWord / Flip    │                               │
└───────────┬───────────┴──────────────┬───────────────┘
            │                          │
            ▼                          ▼
     课程 LessonViewModel         正式复习 OfficialReviewSession
     （课时推进 + 可选评分桥）      answer(rating) → 官方 FSRS/revlog
```

语言课渲染器是**皮肤**。官方 Anki 是**账本**。分类器是二者之间的翻译。

---

## 3. 阶段总览

按依赖顺序施工，禁止把分类、渲染、调度、动画揉进同一个 PR。

| 阶段 | 名称 | 用户能感知到什么 | 是否写官方 Scheduler |
|---|---|---|---|
| A | 共享分类器 | 无 UI | 否 |
| B | 投影接入 + 自动确认 | 导入后短文本卡变成翻面/选择，不再全是网页 | 否 |
| C | 生词卡按语言课画 | 词汇卡变成大号词 + 释义 + TTS | 否 |
| D | 课程练习链 | 一张词汇卡：先见面，再选义，有音频再听音 | 否 |
| E | 正式复习复用 renderer | 到期复习也是语言课卡面，不再是 Official Review 网页 | **是（已有）** |
| F | 翻面 / 展开动画 | 点卡面有过渡；复杂卡答案滑出 | 否 |
| G | 课程评分桥 | 课程里做完也会推进官方到期 | **是（新增）** |

**推荐第一刀：A + B。** 做完导入体感就会回来。C–G 可并行于后续 PR。

阶段 G 改变 P3-051「课程练习不写官方调度」的产品语义，必须单独评审、单独 flag、默认可关。

---

## 4. 阶段 A — 共享分类器（无 UI）

### 4.1 目的

把 Legacy `_autoDecide` / `AnkiRenderPolicy` / 字段名启发式抽成 **官方模块可 import、Legacy 也可逐步改用** 的纯函数。零 Flutter、零 DB、零 FFI。

### 4.2 新建文件

```text
lib/application/anki_practice/
  card_classifier.dart          # 纯函数入口
  card_classifier_models.dart   # 输入/输出类型
  card_text.dart                # stripHtml、shortAnswer、media 文件名
  embedded_options.dart         # 从题干拆 A./B./C.  （从 adapter 迁出逻辑）
test/application/anki_practice/
  card_classifier_test.dart
  embedded_options_test.dart
```

**不要**把文件放进 `lib/application/anki/`（官方禁导）或 `lib/application/anki_official/`（那是官方 Core，不应塞启发式）。

### 4.3 输入模型

分类器**不读官方 Collection 句柄**。投影层把已有分页行喂进来。

```dart
class AnkiPracticeCardInput {
  final int cardId;
  final int notetypeId;
  final String notetypeName;
  final bool isCloze;
  final int templateOrdinal;
  final List<String> fieldNames;
  final List<String> fields;          // 与 fieldNames 对齐的原始字段
  final String questionText;          // 已剥 HTML 的正面（有则优于 fields[front]）
  final String answerText;            // 已剥 HTML 的背面
  final String rawQuestionHtml;       // 用于侦测 <script>/<img>/<table>
  final String rawAnswerHtml;
  final String qfmt;
  final String afmt;
  final List<String> tags;
  final List<String> deckPath;
  final List<String> siblingAnswers;  // 同牌组其它卡的短答案，供干扰项
}
```

第一期 `questionText` / `answerText` 可以由 mapper 的 `shortText(fields[i])` 填。不必等官方 `RENDER_CARD` HTML。有 HTML 后再作为加分输入，不阻塞 A/B。

### 4.4 输出模型

```dart
enum AnkiPracticeShape {
  vocab,        // 短词 + 翻译
  expression,   // 短句 + 意思
  cloze,        // {{cN::}}
  quiz,         // 稳定选项 + 答案键
  listen,       // 正面音频 + 短答案
  typeAnswer,   // 短答案、干扰项不足
  flip,         // 短正反面，不客观判分
  fidelity,     // 必须走官方原卡
}

class AnkiPracticeClassification {
  final AnkiPracticeShape shape;
  final double confidence;            // 0..1
  final List<String> evidence;        // 稳定短码，写入 mapping evidence
  final String term;
  final String meaning;
  final String? example;
  final String? pronunciation;
  final String? audioFilename;
  final String? imageFilename;
  final List<String> options;         // quiz；含正确答案
  final int? correctIndex;
  final List<int>? correctIndices;    // multi-select
  final String? clozeSentence;        // 挖空后带 _____
  final String? clozeAnswer;
  final bool looksLikeQuizButUnparsed; // 铁律：走 fidelity
}
```

### 4.5 判定顺序（必须按此优先级，写成单一 `classify()`）

复制 Legacy 已验证的顺序，禁止「先看字段名再看内容」导致把测验卡当成词汇卡。

1. **保真强制**  
   `qfmt`/`afmt`/正反面 HTML 含 `<script` 或 `on[a-z]+=`，或含 `{{type:` → `fidelity`。  
   证据：`js_or_type_answer`。

2. **复杂 HTML**  
   正反面或模板含 `<img` / `<table` / `<svg` / `<audio` / `<video` / `<iframe` / `<canvas` → `fidelity`。  
   例外：仅 `[sound:…]` / `<img src>` 且其余为短纯文本 → 仍可 `vocab`/`listen`，媒体文件名抽到 `audioFilename`/`imageFilename`。  
   证据：`complex_html` 或 `plain_plus_media`。

3. **Cloze**  
   `isCloze == true` 或正文匹配 `\{\{c\d+::(.*?)(?:::(.*?))?\}\}` → `cloze`。  
   抽第一处挖空为 `clozeAnswer`，全文替换为 `_____` 得 `clozeSentence`。抽不出 → `fidelity`。  
   证据：`cloze_marker`。

4. **题干选项**  
   `looksLikeEmbeddedOptions(front)`：  
   - `extractEmbeddedOptions` 成功且答案键恰好 1 个 → `quiz`（单选）。  
   - 成功且答案键 ≥ 2 且有多选证据 → `quiz`（多选，填 `correctIndices`）。  
   - 看起来像但拆失败 / 答案键冲突 → **`fidelity`，禁止用 siblingAnswers 凑选项**。  
   证据：`embedded_options` 或 `embedded_options_unparsed`。

5. **听音**  
   正面能抽出 `[sound:…]` 或 `[anki:play:…]`，且背面 `isShortAnswer`（≤ 60 字，与 `AnkiCardAdapter.shortAnswerMaxLength` 一致）→ `listen`。  
   证据：`front_audio_short_answer`。

6. **词汇**  
   正面、背面均为非空短文本，不像句子（无。！？。且词数少），字段名或内容像 term/translation → `vocab`。  
   `term = 正面`，`meaning = 背面`。  
   证据：`short_pair_vocab`。

7. **表达**  
   正面像句子（含标点或长度明显长于单词）且背面短 → `expression`。  
   证据：`sentence_plus_meaning`。

8. **打字 / 选择 / 翻面**  
   短答案：  
   - `siblingAnswers` 去重后可用干扰项 ≥ 2 → 仍标 `vocab`（练习链在 D 阶段生成 MCQ，分类本身不必变成 quiz）。  
   - 干扰项不足 → `typeAnswer`。  
   长答案或空正面 → `flip`；再不行 → `fidelity`。

`confidence` 建议：规则 1–4 命中 ≥ 0.90；规则 6 在字段名也像 Front/Back 时 ≥ 0.90；仅靠内容猜测 0.70–0.85。

### 4.6 字段名词表（mapper 必须扩到中文）

从 `AnkiCardAdapter.inferMapping` 迁入，官方 mapper 与分类器共用同一词表：

| 角色 | 英文 | 中文 |
|---|---|---|
| target / term | front, word, term, target, expression, question, q | 正面, 单词, 词, 问题, 前面, 题目, 题干 |
| native / meaning | back, meaning, translation, native, answer, a | 反面, 释义, 翻译, 答案, 后面 |
| audio | audio, sound | 音频, 发音, 声音 |
| image | image, picture | 图片, 插图 |
| cloze | cloze | 填空, 挖空 |
| options | option, choice | 选项 |

### 4.7 步骤

1. 新建目录与空 `classify()`，先只实现规则 1 和 6，配 10 个表驱动测试。
2. 把 `looksLikeEmbeddedOptions` / `extractEmbeddedOptions` **原样搬出** `anki_card_adapter.dart`，adapter 改为转发，保持 Legacy 测试绿。
3. 搬 `stripHtml` / `isShortAnswer` / sound 文件名抽取。`AnkiCardAdapter.stripHtmlPublic` 改为调用共享函数。
4. 补全规则 2–8。测试用例至少覆盖：
   - Basic Front/Back `hello` / `你好` → `vocab`
   - `正面` / `反面` 中文字段名 → `vocab`
   - `{{c1::猫}}` → `cloze`
   - `下列正确的是：\nA. 甲\nB. 乙` + 答案 `A` → `quiz`
   - 题干有 A./B. 但拆不出 → `fidelity`（铁律）
   - `[sound:a.mp3]` + 短背面 → `listen`
   - 含 `<script>` → `fidelity`
   - 长段落背面 → `flip` 或 `fidelity`
5. 跑：
   ```bash
   flutter test --no-pub test/application/anki_practice
   flutter test --no-pub test/anki/anki_card_adapter_test.dart
   flutter test --no-pub test/application/anki_official/official_anki_forbidden_imports_test.dart
   ```
6. **本阶段不改投影、不改 UI。**

### 4.8 完成定义

- 分类器对上表用例 100% 稳定（同输入同输出）。
- `anki_official` 仍零 import Legacy。
- Legacy adapter 测试不减少、不失败。

---

## 5. 阶段 B — 投影接入与自动确认

### 5.1 目的

让导入后的课程项真正变成 `AnkiCard` / `MultipleChoice` / `FillBlank` / `ListenAndPick`，而不是清一色 `canonicalLink`。

### 5.2 改哪些文件

| 文件 | 改动 |
|---|---|
| `official_anki_projection_mapper.dart` | 词表并入中文；`autoCandidate` 门槛：target+native 均 ≥ 0.85 **或** 分类器 `confidence ≥ 0.90` 且 shape ≠ fidelity |
| `official_anki_projection_payloads.dart` | `kindsFor()` 改用分类器；扩展 kind |
| `official_anki_projection_projector.dart` | enum 增加 kind；payload 带分类字段 |
| `official_anki_projection_paging.dart` | `officialAnkiProjectionAlgorithmVersion` **1 → 2**（强制旧投影重建） |
| `official_anki_projection_service.dart` | 扫描行时调用分类器；`autoConfirmAutoCandidates` 对 vocab/cloze/quiz 高置信自动确认 |
| `test/application/anki_official/official_anki_projection_test.dart` | 金样更新 |
| `test/application/anki_official/official_anki_projection_p3fix_test.dart` | 回归 |

### 5.3 扩展 `OfficialAnkiProjectionKind`

现有：

```dart
enum OfficialAnkiProjectionKind {
  flip, multipleChoice, listenPick, typeAnswer, canonicalLink,
}
```

阶段 B 先加，阶段 C/D 才用满：

```dart
enum OfficialAnkiProjectionKind {
  showWord,         // 生词介绍（C 启用；B 可先仍用 flip）
  flip,
  multipleChoice,
  multiSelect,
  listenPick,
  typeAnswer,
  fillBlank,        // cloze / expression
  translate,        // 可选，D 再开
  canonicalLink,
}
```

B 的最小可用集合：`flip` / `multipleChoice` / `listenPick` / `fillBlank` / `canonicalLink`。`showWord` 若 B 就写入，C 的 renderer 必须同时能吃内联字段，否则课程里会画出空生词卡。

**建议 B 暂不写 `showWord`。** 词汇卡 B 先投影为 `flip`（立刻有 `AnkiCardRenderer`）。C 再把 vocab 改成 `showWord`。

### 5.4 新的 `kindsFor()` 伪代码

```text
classify(input) → shape

if mapping.status ∈ {needsMapping, skipped} AND shape.confidence < 0.90:
    return [canonicalLink]

switch shape:
  fidelity → [canonicalLink]
  cloze    → [fillBlank]           // payload: sentence/answer/hint
  quiz     → [multipleChoice] 或 [multiSelect]
  listen   → [listenPick]          // 干扰项 < 2 则 typeAnswer，再不行 flip
  vocab    → [flip]                // B；C 改为 showWord + 练习
  expression → [fillBlank] 或 [flip]
  typeAnswer → [typeAnswer] 若 typeAnswerEnabled 且有音频，否则 [flip]
  flip     → [flip]
```

B **一卡一种 kind**（除 overflow 回落 canonicalLink）。多 kind 练习链放到 D，避免课表突然膨胀 3 倍。

### 5.5 `interactionJson` 对照

| kind | Interaction | 字段来源 |
|---|---|---|
| flip | `Interaction.ankiCard` | front=term, back=meaning, audio/image |
| multipleChoice | `Interaction.multipleChoice` | prompt, options, correctIndex |
| listenPick | `Interaction.listenAndPick` | audioFilename, prompt=meaning, options |
| fillBlank | `Interaction.fillBlank` | clozeSentence / expression front, answer |
| typeAnswer | `Interaction.typeTheWord` | prompt=term, expected=meaning；无音频时 `audioAsset: ''`（确认现有 renderer 能 TTS 回退） |
| canonicalLink | `Interaction.showWord` + `official-canonical-link:` context | **保持不变** |

媒体 filename 继续只存 Collection 内已校验名字，不复制 URI。路径解析沿用现有 official media resolver。

`TypeTheWord.audioAsset` 当前是 `required`。若分类为 typeAnswer 但无音频：B 改投影为 `flip` 或 `fillBlank`，不要生成空字符串骗 renderer。

### 5.6 自动确认策略

替换「必须 Front+Back 都 ≥ 0.90」的单一门槛：

| 条件 | mapping status | 是否打断导入向导 |
|---|---|---|
| 分类器 confidence ≥ 0.90 且 shape ≠ fidelity | `autoCandidate`，`userConfirmed=true` | 否 |
| 字段名命中词表且分类器 ≥ 0.80 | `autoCandidate` | 否 |
| 0.60–0.80 | `needsConfirm`，导入后可改 | 向导可跳过，先按分类器投影并在 UI 标「自动识别」 |
| < 0.60 或 fidelity | `needsMapping` 但 **仍生成 canonicalLink**，导入不失败 | 否（保真卡不是错误） |

「跳过映射」不得再导致整副牌只有网页入口。跳过 = 该 notetype 全部走分类器或 canonicalLink。

### 5.7 重建

`algorithmVersion` 升到 2 后，已有 official source 在下次打开/导入时走现有 job 重建。确认：

- `officialAnkiProjectionCanonical` fingerprint 含 algorithmVersion（已含）。
- 重建期间课程树仍显示旧投影，切到新 generation 是原子的（现有 store 语义，不要改成边写边读）。

### 5.8 步骤

1. 把分类器接入 `OfficialAnkiProjectionPayloads`，`kindsFor` 加 `AnkiPracticeCardInput` 参数；旧签名保留转发以免一次性改爆测试。
2. Projector 组装 input：`fields` + mapper `shortText` + notetype 名 + tags。
3. 扩展 mapper 中文词表；更新 `mapping goldens use names and samples only`：`Front/Back` 仍 autoCandidate；新增 `正面/反面` 金样。
4. 加测试：Basic 20 张 → 20 个 `flip`，0 个 `canonicalLink`（无脚本）。
5. 加测试：映射 status=`needsMapping` 但分类器 vocab 0.92 → 仍 flip，不阻断。
6. 加测试：unparsed A/B/C → canonicalLink，且无 multipleChoice。
7. bump algorithmVersion。
8. 跑：
   ```bash
   flutter test --no-pub test/application/anki_official/official_anki_projection_test.dart
   flutter test --no-pub test/application/anki_official/official_anki_projection_p3fix_test.dart
   flutter test --no-pub test/application/anki_official/official_anki_projection_p3r_test.dart
   flutter test --no-pub test/application/anki_official/official_anki_forbidden_imports_test.dart
   ```

### 5.9 完成定义

- 标准 Basic 牌组导入后，课程项打开的是 `AnkiCardRenderer`，不是 WebView。
- 含脚本的卡仍是 canonicalLink。
- 映射向导对 Basic 不再是必经步骤。

---

## 6. 阶段 C — 生词卡按语言课渲染

### 6.1 目的

词汇卡看起来像语言课 `ShowWord`：大号词、释义、喇叭、可选例句；而不是通用 Anki 翻面图标。

### 6.2 为什么不能直接复用现在的 `ShowWord`

`ShowWordRenderer` 用 `wordId` 查 `vocabById`（语言课词典）。官方卡的 id 是 `official-anki-<profileKey>-c<cardId>`，不在那本词典里。  
`canonicalLink` 已经占用 `ShowWord.context` 前缀 `official-canonical-link:`。两条路径必须分清。

### 6.3 方案（选定）

给 `Interaction.showWord` 增加**可选内联字段**，有内联就不查词典：

```dart
const factory Interaction.showWord({
  @Default('') String id,
  required String wordId,
  String? context,
  String? grammarPointId,
  String? expressionId,
  String? term,            // NEW
  String? translation,     // NEW
  String? pronunciation,   // NEW
  String? audioAsset,      // NEW
  String? imageAsset,      // NEW
}) = ShowWord;
```

判定：

```text
if parseCanonicalLink(context) != null → OfficialAnkiCanonicalLinkView（不变）
else if term != null && term.isNotEmpty → 用内联字段画 _ShowWordCard
else → vocabById[wordId]（语言课原路径）
```

JSON 缺字段时 freezed 默认 null，旧课程 JSON 继续能解析。改完必须 `build_runner`。

### 6.4 改哪些文件

| 文件 | 改动 |
|---|---|
| `lib/domain/course/interaction.dart` | 加字段 |
| `interaction.freezed.dart` / `.g.dart` | 生成 |
| `show_word_renderer.dart` | 内联优先 |
| `official_anki_projection_payloads.dart` | vocab → `showWord` payload |
| `official_anki_projection_projector.dart` | kind `showWord` |
| `test/views/lesson/renderers/show_word_renderer_test.dart`（或新建） | 内联生词卡、canonicalLink 不回归 |
| `test/domain/interaction_unknown_type_fallback_test.dart` | 确认仍吞未知类型 |

### 6.5 `_ShowWordCard` 行为

已有实现即可：大号 term、点击朗读 term、translation 在下方、contextSentence 作为例句条。C 把 `example` 填进 `context`（注意：`context` 已被 canonicalLink 占用）。

**冲突：** `ShowWord.context` 现在既是例句，又是 canonical token。C 不要把例句写进 `context`。新增 `example` 字段（或 `contextSentence`）专门放例句。canonicalLink 继续只用 `context`。

最终字段建议：

- `context`：仅 canonical token 或语言课原有「语境」——语言课现有 JSON 用它当例句。为避免破坏语言课，**不要改变语言课语义**。
- 官方内联用新字段 `exampleTarget` / 复用 `context` 仅当 `parseCanonicalLink == null`。

更稳：官方 payload 把例句放进新字段 `example`。Renderer：

```text
final example = i.example ??
    (parseCanonicalLink(i.context) == null ? i.context : null);
```

语言课旧数据：无 `example`，`context` 不是 canonical 前缀 → 仍当例句。官方生词卡：填 `term/translation/example`，`context` 留空。canonicalLink：只填 `context` token。

### 6.6 步骤

1. 扩展 `ShowWord` + codegen。
2. Renderer 三路分支 + widget 测试（内联 / 词典 / canonicalLink）。
3. Payload：shape=vocab 时 kind=`showWord`，不再只出 `flip`。B 导入的旧 `flip` 项仍合法，重建后变成 showWord。
4. 确认 `autoAdvance == true` 仍适用：生词介绍点卡继续，不评分。这与 Anki 翻面「先藏答案」不同，符合语言课 intro。
5. 若用户在**课程介绍**里仍想先藏释义：不要改 ShowWord；把「先藏后翻」留给正式复习（阶段 E 用 `AnkiCard`/`flip`）。课程 intro = 见面；复习 = 回忆。

### 6.7 完成定义

- 打开官方词汇课第一节，卡面视觉与土耳其语 intro `showWord` 同类：大号词、释义、喇叭。
- canonicalLink 项仍打开 WebView，不会误画成生词卡。
- 语言课词典 `showWord` golden / widget 测试不挂。

---

## 7. 阶段 D — 课程练习链（一卡多题）

### 7.1 目的

模仿 intro 课：同一词汇先见面，再练习。

语言课结构（`lesson-intro.json`）：

```text
subLesson "Meet the words"
  stage Show → showWord
subLesson "Practice"
  stage → multipleChoice / fillBlank
```

官方投影目前按 deck 每 20 卡一个 Lesson，每种 kind 平铺。D 在**同一 Lesson 内**为 vocab 卡追加练习项，不拆新 Section。

### 7.2 生成规则（一卡最多 3 项，防止课表爆炸）

对 `shape == vocab`：

| 序号 | kind | 条件 |
|---|---|---|
| 1 | `showWord` | 总是 |
| 2 | `multipleChoice` | `siblingAnswers` 可用干扰项 ≥ 2（B 起分类器要带 sibling 池） |
| 3 | `listenPick` | 有 `audioFilename` 且干扰项 ≥ 2 |

对 `shape == listen` 且不像词汇对：只出 `listenPick`，不出 showWord。

对 `cloze` / `quiz` / `expression`：仍一卡一项。

对 `fidelity`：只有 `canonicalLink`。

### 7.3 干扰项池

Projector 在同一 notetype 或同一 deckPath 桶内收集短 `meaning`/`term`。去重、去掉自身、截断 80 字、最多取 3 个。种子继续用现有 `officialAnkiShuffleSeed`，保证重建不漂。

**禁止**用别的 notetype 的答案当干扰项（避免「苹果」出现在语法测验里）。

铁律：`looksLikeQuizButUnparsed` 的卡不得进入干扰项生成。

### 7.4 Lesson 内排序

同一 `cardId` 的多项必须连在一起，顺序：`showWord` → `multipleChoice` → `listenPick`。  
`officialAnkiItemId(wordId, kind, ordinal)` 已按 kind 区分 id，课程完成态不会撞。

若 20 卡 × 3 kind 超过 `content_json` 512 KiB 或 CourseValidator 上限，沿用现有 `officialAnkiSplitLessons`。优先按卡边界切，不要把同一 card 的 showWord 和 MCQ 切到两个 Lesson。

### 7.5 `enabledKinds` 与用户控制

mapping 已有 `enabledKinds`。向导增加开关：

- 生成生词介绍
- 生成选义
- 生成听音

默认：vocab 全开。用户关掉选义则只留 showWord（或 flip）。

### 7.6 步骤

1. Projector 增加 sibling 池构建（O(n)，按桶）。
2. `kindsFor` 对 vocab 返回 1–3 个 kind。
3. 稳定排序测试：重建两次 item id 序列相同。
4. 容量测试：200 张词汇卡 × 3 kind 能切 Lesson，无 overflow 丢卡。
5. Widget/VM：连续三项提交后 `LessonViewModel` 前进 3 步，showWord autoAdvance 不卡死（对照 P3R-012 canonicalLink 完成语义）。

### 7.7 完成定义

- 词汇牌组一节课：先出大号词，再出四选一。
- 无音频则无听音项。
- 测验牌组不会先出 showWord 再出选择（quiz 直接 MCQ）。

---

## 8. 阶段 E — 正式复习复用语言课 renderer

### 8.1 目的

到期复习不再是标题为 `Official Review` 的裸 WebView。已分类的简单卡用与课程相同的 Flutter 卡面；只有 fidelity 卡才嵌官方 ReviewerView。

评分按钮仍是 Again / Hard / Good / Easy，写入 `OfficialReviewSession.answer(rating)`。

### 8.2 不要做的事

- 不要让正式复习走 `LessonViewModel`（课时、mastery、课程进度会缠在一起）。
- 不要在正式复习里 autoAdvance 掉 showWord（复习必须先藏答案）。
- 不要把课程 intro 的 showWord 拿来当复习卡：复习用 `AnkiCard`（翻面）或「先藏 translation 的生词壳」。

### 8.3 复习卡面选择

| 分类 | 复习 UI |
|---|---|
| vocab / flip / expression（短） | `AnkiCardRenderer` 或「生词壳 + 藏释义」 |
| quiz | `MultipleChoiceRenderer`，提交后不出课程 Continue，出四档评分；对错仅作提示 |
| listen | `ListenAndPickRenderer`，同上 |
| cloze / typeAnswer | `FillBlankRenderer` / `TypeTheWordRenderer`，同上 |
| fidelity | 现有 `OfficialAnkiReviewerStage` + 阶段 F 的展开外壳 |

产品语义保持 ADR 与 anki-integration-design §7：客观题对错**提示**，最终间隔仍由四档评分决定。点对了不等于 Good。

### 8.4 实现位置

新建：

```text
lib/views/anki_official/official_anki_practice_review_surface.dart
```

由 `OfficialAnkiReviewPage._reviewerColumn` 在 `showingQuestion/showingAnswer` 时选择：

```text
if (classification.shape == fidelity || classification == null)
    OfficialAnkiReviewerStage(...)
else
    OfficialAnkiPracticeReviewSurface(
      interaction: projectedOrEphemeral,
      showingAnswer: session.phase == showingAnswer,
      onReveal: presenter.showAnswer,
      onRate: session.answer,
    )
```

**投影缓存 vs 即时分类：** 正式复习队列来自官方 Scheduler，不一定经过课程投影。E 必须能对 `cardId` 即时分类：

1. Engine 取字段（已有 projection row / `RENDER_CARD` 文本剥除）。
2. 跑同一 `classify()`。
3. 现场组装 `Interaction`（不要依赖 CourseDatabase 里的 lesson JSON）。

这样未开 `TURNA_OFFICIAL_ANKI_COURSE_ENTRY` 时，主复习队列也能是语言课卡面。

### 8.5 步骤

1. 从官方 cardId 取字段的只读 API（优先复用 projection paging 已扫的字段；没有则 engine 查 note）。
2. `PracticeReviewSurface`：内部 `lookupRenderer()` + 自定义 `OnInteractionSubmit`：客观题只 setState 出对错色，然后显示四档按钮；翻面题用 renderer 自带四档（`AnkiCardRenderer` 已有）。
3. `AnkiCardRenderer` 的 `onSubmit(correct, reviewQuality:)` 已映射 Again/Hard/Good/Easy。桥接到 `session.answer('1'|'2'|'3'|'4')`（对照现有 `_RatingRow` 的 rating 字符串）。
4. 客观题：用户选完选项 → 显示对错 → **仍要**按四档；可把「完全正确」默认高亮 Good 但不自动提交。
5. Widget 测试：vocab 卡无 `official_anki_reviewer` platform view。
6. 回归：`official_anki_formal_review_ack_test.dart`、`official_anki_scheduler_p4_test.dart` — fidelity 卡 ACK 语义不变。
7. 替换 AppBar 标题 `Official Review` 为与应用其它复习页一致的文案（`AppStrings`）。

### 8.6 完成定义

- 到期队列里的 Basic 词汇卡：Flutter 翻面 + 四档，无 WebView。
- JS 卡：仍 WebView + ACK 门禁。
- Undo/Redo/Bury/Suspend 仍走 session，不经 LessonViewModel。

---

## 9. 阶段 F — 翻面与展开动画

### 9.1 目的

简单卡恢复点按翻面过渡；复杂卡用展开揭示，而不是 3D 转 WebView。

### 9.2 简单卡（Flutter）

`AnkiCardRenderer` 已有 320ms 缩放脉冲（1.0 → 0.94 → 1.0），中点换面。课程路径 B 完成后自动具备。

可选增强（独立 PR，可关）：

- `MediaQuery.disableAnimationsOf` 为 true 时跳过动画（`settings_page.dart` 已有 reduceMotion 先例）。
- 轻量 `rotateY` **仅**用于无图片、无 WebView 的纯文本 `AnkiCard`。默认关，设置项「卡片旋转」。禁止对 `LessonPracticeCard` 里嵌平台 view 的表面做旋转。

### 9.3 复杂卡（WebView）

`OfficialAnkiReviewerStage` 现在 `showingAnswer` 变化即 `present(side)` 换 HTML，无过渡。

改为展开式外壳（恢复 Changelog 中 `AnkiRevealScaffold` 的产品意图，**不要**从 git 盲拷旧 300px 实现）：

1. 问题面 WebView 保持在上。
2. 点「显示答案」或点卡面 → `session.showAnswer()` + `presenter.showAnswer()`。
3. 答案面在下方 `AnimatedSize` / `SizeTransition` 展开。若单 WebView 不能同时持有两面：答案用第二高度或同 view 换 HTML 后，用 `AnimatedOpacity` 交叉淡入。优先交叉淡入，实现简单、不双开 WebView。
4. 四档评分出现在展开完成之后（与 `AnkiCardRenderer._showGradeButtons` 一样等 animation completed）。
5. 点问题面可收回答案、**不提交**评分。

### 9.4 步骤

1. Flutter 翻面：确认 B 后课程路径已有脉冲；补 `disableAnimations`。
2. 给 `OfficialAnkiReviewerStage` 加 `onSurfaceTap` → flip（正式复习页已有 Show Answer 按钮，F 让卡面也可点）。
3. 交叉淡入：`AnimatedSwitcher` 包一层，key=`cardId+side`。WebView 是 platform view，Switcher 可能闪；若闪则改为按钮下方滑出评分 + 原地换 HTML，不强行动画 WebView。
4. 真机看 20 张：无掉帧、无双 AppBar、无二次 flip 按钮（对照 P4 NOW-4）。
5. 无 golden 也可先行为测试：`showAnswer` 后 350ms 内出现 rating row。

### 9.5 完成定义

- 文本卡点面有过渡，评分在过渡后出现。
- 复杂卡不旋转、不卡顿。
- 减少动态效果开启时无动画、功能完整。

---

## 10. 阶段 G — 课程练习写回官方 Scheduler

### 10.1 目的

课程里做完词汇练习，官方到期队列同步推进。否则会出现「课上学过、复习里还是新卡」。

这与 P3-051「课程练习不写官方调度」相反，必须：

- 独立 flag，默认 **关**，文档与设置写清楚。
- 同一 `cardId` 在一课内多 kind（showWord + MCQ + listen）**只写一次**官方 answer。
- showWord 介绍 **不写** Scheduler。
- 客观题对错映射到四档要可解释，且允许用户覆盖。

### 10.2 Flag

```text
TURNA_OFFICIAL_ANKI_COURSE_GRADES_SCHEDULER=false  # 默认
```

`OfficialAnkiFeatureFlags` 增加 `courseGradesScheduler`。设置页：「课程练习计入 Anki 进度」。

### 10.3 映射

| 课程项 | 是否写 Scheduler | rating |
|---|---|---|
| showWord | 否 | — |
| canonicalLink 预览 | 否 | — |
| multipleChoice / listen / fillBlank / type 答对 | 是（每 cardId 一次） | Good（3） |
| 同上答错 | 是（一次） | Again（1） |
| flip（AnkiCard 四档） | 是 | 用户选的 1–4 |

同一 card 先 MCQ 再 listen：以**最后一次客观项**为准，或「有一次错则 Again」。选定：**任何一次客观错 → Again；全对 → Good。** 写在代码注释与设置说明里。

### 10.4 写入路径

不要让 `LessonViewModel._applySrsOutcome` 写自研 FSRS 同时又写官方（双账本）。官方卡：

- `wordId` 以 `official-anki-` 开头时，**跳过**自研 `SrsProvider.registerWord`。
- 新小组件 `OfficialAnkiCourseGradeBridge`：课结束或该 card 的最后一项提交后，调 `OfficialReviewSession` 的单卡 answer API。若 session 必须先 `openDeck`，则增加 engine 的 one-shot `answerCard(cardId, rating)`（若 contract 已有则用现成的，不要为桥接复制 queue 状态机）。

先读 `official_anki_review_session.dart` 与 contract 1.3：能否对不在当前 queue 的 cardId 评分。若不能，G 先做「仅当该卡已在 due 队列」或「打开 filtered deck 含这些 cardId」。**禁止** invent 一套 due 计算。

### 10.5 步骤

1. Spike：对单个 cardId 调官方 answer，是否必须经过 queue。结论写入本文件附录或后续 result report。
2. Flag + 设置项。
3. LessonViewModel：official wordId 不进自研 SRS。
4. Bridge + 「每 cardId 一次」去重表（lesson 生命周期）。
5. 测试：一课 showWord+MCQ 对 → 官方 revlog 一条 Good；MCQ 错 → 一条 Again；关 flag → revlog 0。
6. Undo：课程 Undo 若不能官方 undo，则设置说明写「关闭后下一张生效」或调用 `session.undo`。做不到就不要在课程里显示 Undo 官方进度。

### 10.6 完成定义

- Flag 关：与今天 P3 行为一致（本阶段可单独 merge 但默认关）。
- Flag 开：课程答完，主页官方 due 减少，revlog 与 Desktop 同 rating 语义。
- 自研 `srs_states` 不出现 `official-anki-` wordId。

---

## 11. 端到端数据流（做完 A–E 之后）

```text
导入 .apkg
  → 官方 Collection 提交（已有 Saga）
  → projection job algorithm v2
      classify 每张卡
      vocab → showWord（课程） / 复习时 AnkiCard
      quiz  → multipleChoice
      cloze → fillBlank
      js    → canonicalLink
  → CourseDatabase 课程树（官方 section id 前缀 official-anki-<source>-）
  → 用户点 Lesson
      lookupRenderer(Interaction)
      ShowWord 内联生词卡 / MCQ / …
  → 用户点主页到期
      OfficialReviewPage
      简单卡 PracticeReviewSurface
      复杂卡 ReviewerStage
      session.answer → 官方 FSRS
```

---

## 12. 测试矩阵

| 层 | 命令 | 阶段 |
|---|---|---|
| 分类器 | `flutter test --no-pub test/application/anki_practice` | A |
| 投影 | `flutter test --no-pub test/application/anki_official/official_anki_projection_test.dart` 以及 p3fix/p3r | B D |
| 禁导 | `flutter test --no-pub test/application/anki_official/official_anki_forbidden_imports_test.dart` | 每一阶段 |
| ShowWord | renderer widget 测试 | C |
| 课程流 | `flutter test --no-pub test/application/lesson_viewmodel_flow_test.dart` `test/integration/lesson_flow_test.dart` | D G |
| 正式复习 | `official_anki_formal_review_ack_test.dart` `official_anki_scheduler_p4_test.dart` `official_anki_reviewer_behavior_test.dart` | E F |
| Legacy 不回退 | `flutter test --no-pub test/anki test/application/anki` | A（搬函数后） |
| 官方全集 | `flutter test --no-pub test/application/anki_official` | 每个 PR 末 |

设备（Android arm64，沿用 Device A 口径）：

1. 导入标准 Basic 中英词汇 20 张：课程第一项是生词卡不是 WebView。
2. 点选义，对错色正常，课时能前进。
3. 主页到期：同一批卡 Flutter 翻面，Again 后队列变化。
4. 导入带 JS / 图片复杂牌组：仍 WebView，无白屏。
5. 减少动画：功能完整。

---

## 13. 功能开关与回滚

| Flag / 版本 | 作用 | 默认 |
|---|---|---|
| `officialAnkiProjectionAlgorithmVersion = 2` | 重建投影 | 升版本即生效 |
| `TURNA_OFFICIAL_ANKI_COURSE_ENTRY` | 课程树是否显示官方 section | 现有 opt-in |
| `TURNA_OFFICIAL_ANKI_COURSE_LIKE_REVIEW`（E 新增） | 正式复习走 Flutter 卡面 | 建议 true（Android） |
| `TURNA_OFFICIAL_ANKI_CARD_ROTATE`（F 可选） | 纯文本 3D 旋转 | false |
| `TURNA_OFFICIAL_ANKI_COURSE_GRADES_SCHEDULER` | 课程写官方调度 | false |

回滚：

- 只回滚 Dart，不碰 Collection。把 algorithmVersion 留在 2 但 `kindsFor` 回 canonicalLink 会再次重建——**不要降 version 号**，用 flag 让 kindsFor 走旧分支。
- 分类器 bug：shape 强制 fidelity 即可，用户仍能复习原卡。
- G 出双写：关 courseGradesScheduler。

---

## 14. 明确不改的文件（除非后续阶段点名）

- `native/turna_anki_core/` contract / rslib 钉钉（除非 G 发现缺少单卡 answer API）。
- Legacy `AnkiImporter` 生产路径（P5-E 后 Android 已切官方）。
- OHOS Legacy 回退。
- AnkiWeb / 同步（P6 已取消）。

---

## 15. PR 切分（建议）

| PR | 内容 | 依赖 |
|---|---|---|
| PR1 | 阶段 A 共享分类器 + Legacy 转发 | 无 |
| PR2 | 阶段 B 投影 kindsFor + mapper 中文 + algorithm v2 | PR1 |
| PR3 | 阶段 C ShowWord 内联字段 + vocab→showWord | PR2 |
| PR4 | 阶段 D 练习链 + sibling 池 | PR3 |
| PR5 | 阶段 E 正式复习 Flutter 表面 | PR1（可不依赖课程树） |
| PR6 | 阶段 F 动画与无障碍 | PR5 |
| PR7 | 阶段 G 课程评分桥（默认关） | PR4 + contract Spike |

每个 PR 必须包含禁导测试与对应单元测试。PR2 起附 Basic 牌组手动步骤（可先 Host/emulator）。

---

## 16. 关键代码锚点（施工时打开这些文件）

```text
# 分类与旧启发式
lib/application/anki/anki_card_adapter.dart          _autoDecide, inferMapping
lib/application/anki/anki_render_policy.dart
lib/application/anki/anki_notetype_ai.dart           仅建议，不进 canonical 成败

# 官方投影
lib/application/anki_official/projection/official_anki_projection_mapper.dart
lib/application/anki_official/projection/official_anki_projection_payloads.dart
lib/application/anki_official/projection/official_anki_projection_projector.dart
lib/application/anki_official/projection/official_anki_projection_service.dart
lib/application/anki_official/projection/official_anki_projection_paging.dart
lib/application/anki_official/projection/official_anki_course_entry.dart

# 语言课渲染
lib/domain/course/interaction.dart
lib/views/lesson/components/interactions/interaction_renderer.dart
lib/views/lesson/components/interactions/show_word_renderer.dart
lib/views/lesson/components/interactions/anki_card_renderer.dart
lib/views/lesson/components/interactions/multiple_choice_renderer.dart
lib/views/lesson/components/lesson_practice_card.dart
lib/views/lesson/new_lesson_screen.dart
lib/application/lesson_viewmodel.dart

# 正式复习
lib/views/anki_official/official_anki_review_page.dart
lib/views/anki_official/official_anki_reviewer_stage.dart
lib/application/anki_official/engine/official_anki_review_session.dart

# 约束
test/application/anki_official/official_anki_forbidden_imports_test.dart
docs/authoring/lesson-type-templates.md
```

---

## 17. 开放问题（实施时不可默许）

1. **课程 intro 是否藏释义？** 本文默认不藏（与语言课一致）；回忆发生在正式复习。若产品要课程里也翻面，vocab 课程项改回 `flip`，showWord 只用于非 Anki 语言课。
2. **G 的单卡 answer 是否必须在 due 队列里？** 开 PR7 前用 Spike 回答，否则不要接 bridge。
3. **干扰项语言方向：** MCQ 是选译文还是选目标词？语言课选义通常 prompt=目标词、options=译文。分类器 `term/meaning` 应对齐 mapping `direction`（已有 `targetToNative`）。
4. **AI 识别：** `AnkiNotetypeAI` 只作为 needsConfirm 的预填，不自动覆盖 ≥0.90 规则。是否在官方导入向导里露出，单独产品决定。
5. **OHOS：** 无官方 renderer。本方案的 Flutter 练习链在 OHOS 可走投影（纯 Flutter）；canonicalLink / 正式 WebView 仍 fail closed。不要为 OHOS 恢复 Legacy 解析。

---

## 18. 验收一句话

导入一副普通中英单词牌组后：课程里像语言课一样先认词再选择；到期复习是同一套 Flutter 卡面加四档评分；只有真正依赖 Anki 模板的卡才打开官方 WebView。Collection 与 FSRS 始终是官方的。
