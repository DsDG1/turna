# 课程类型设计模板

本模板用于在 `assets/courses/<lang>/sections/*.json` 中设计单节课（Lesson）。
它围绕六种 `LessonType` 展开，并给出每种类型推荐的 `LessonTemplate`、内容结构、典型题型和最小可运行示例。

> 与代码模型的对应关系见 `lib/domain/course/lesson.dart`。
> 所有 JSON 编写完成后必须运行：
>
> ```bash
> python tool/course_cli.py validate
> python tool/course_cli.py lint
> ```

---

## 类型速查

| 类型 | 用途 | 推荐模板 | 核心内容字段 |
|------|------|----------|--------------|
| `normal` | 普通新课或常规练习 | `guide` / `intro` / `practice` / `legacy` | `pages`、`subLessons` 或 `stages` |
| `listening` | 听力专项训练 | `listening` | `listeningPhases` |
| `dialogue` | 角色对话与学习者回应 | `dialogue` | `dialogueScene` + `stages` |
| `reading` | 阅读理解训练 | `reading` | `readingPassage` + `stages` |
| `review` | 混合复习 | `review` | `subLessons` 或 `stages` |
| `challenge` | 掌握检测 / 关卡挑战 | `mastery` | `stages` |

---

## 1. `normal` — 普通课

### 用途

最常用的课程类型，用于：

- 引入新词汇 / 表达 / 语法点（`template: intro`）
- 对前面课程内容做难度更高的巩固练习（`template: practice`）
- 兼容旧版无模板课程的平铺题型（`template: legacy`）

### 推荐结构

新课优先使用 `intro` 模板，分成 4 个子课；练习课优先使用 `practice` 模板，同样以子课组织。

### 子课（subLesson）体量契约

每个子课在课程树上是一个**独立的可玩节点**（ADR 0064）：树上渲染为「课组头 +
每子课一个瓦片」，瓦片标题就是子课 name；点进一个子课瓦片，只玩这一节的独立
会话，会话结束回课程树。因此：

- 每个子课的题目总量（所有 stage 的 items 之和）目标 **12–15 题**——即传统
  一节课的体量；3–4 题的子课在播放上会显得过碎。
- 一节课包含 n 个子课（n ≥ 2，常见 2–5），n 由单元主题的材料量决定，不是
  固定值。
- 子课 id 必须全局唯一且不可变更：小课级完成进度以 `lessonId::subLessonId`
  持久化，改 id 会丢进度；子课 name 只是显示标题，可以修改。
- 子课 name 即瓦片标题，直接面向学习者：建议 ≤ 12 字、能独立表意，避免同质
  的单词名连排（一排单词瓦片会失去课的定位感）。

### 常用题型

- `showWord`：展示新词
- `multipleChoice`：选择释义 / 用法
- `fillBlank`：填空；带 `choices` 即**选择填空**——挖空处点候选词块填入，
  词块点一下读音（choices 一律写目标语词）
- `translateSentence`：翻译句子
- `reorderSentence`：句子排序；带 `prompt` 即**翻译拼句**——词库上方显示
  源句（如中文题面），词块点一下读音
- `readAloud`：跟读（[ADR 0061](../decisions/0061-read-aloud-word-matching.md)）。
  只有 `targetText` 必填（非空，Dart 与 Python validator 都查）——示范音不写
  `audioAsset`，app 用 TTS 直接读 `targetText`；识别与逐词比对由 app 完成，
  评分二元（≥60% 词读到为过）。平台不支持时自动降级为听示范卡，内容侧无需
  关心。示例：

  ```json
  {
    "runtimeType": "readAloud",
    "id": "ra-u1-merhaba",
    "targetText": "Merhaba!",
    "prompt": "进店的第一句，读出声来"
  }
  ```

### 示例

```json
{
  "id": "l-u1-intro-merhaba",
  "name": "Merhaba",
  "description": "学习基础问候语",
  "type": "normal",
  "template": "intro",
  "prerequisiteLessonIds": [],
  "content": {
    "subLessons": [
      {
        "id": "sl-1",
        "name": "Meet the words",
        "stages": [
          {
            "id": "st-show",
            "name": "Show",
            "items": [
              {
                "runtimeType": "showWord",
                "id": "sw-merhaba",
                "wordId": "w-merhaba"
              }
            ]
          }
        ]
      },
      {
        "id": "sl-2",
        "name": "Choose",
        "stages": [
          {
            "id": "st-mcq",
            "name": "MCQ",
            "items": [
              {
                "runtimeType": "multipleChoice",
                "id": "mc-merhaba",
                "prompt": "What does 'Merhaba' mean?",
                "options": ["Hello", "Goodbye", "Thanks"],
                "correctIndex": 0
              }
            ]
          }
        ]
      }
    ]
  }
}
```

### 设计检查清单

- [ ] 是否明确了这节课要教授的 `linkedGrammarPointIds`
- [ ] 新词是否先在 `vocab.json` 中定义，`showWord` 的 `context`/`example` 是否采用 `目标语句 — 中文说明` 格式
- [ ] 两个首次新词之间是否至少间隔 2 道题（索引差 ≥ 3）
- [ ] 子课数量是否在 2–5 个之间（每个子课 12–15 题）
- [ ] 孤立单词选义单选是否已控制到位（`intro` 每子课 ≤ 2 道，`practice` 为 0 道）
- [ ] 是否已杜绝 `「词」= _____` 等号式伪填空，且可作答题以真实句子为主（`intro` ≥ 55%，`practice` ≥ 80%）
- [ ] 逐个代入 `fillBlank` 候选词与选择题选项后是否仅有唯一解（无「多个同类词都能填」且 `fillBlank` 未挂载 `assets/` 路径图片）

---

## `dialogue` — 情景对话

用于点单、询问、回应等真实社交任务。课程包含角色、按顺序推进的轮次，以及需要学习者亲自完成的回应；不是只给普通选择题套一个情景题干。

- `type: dialogue`、`template: dialogue`。
- `content.dialogueScene` 包含 `id`、`title`、`characters`、`turns`。
- 角色包含全局场景内唯一的 `id`、显示名 `name` 和可选 `imageAsset`。
- 角色台词轮写 `text`；学习者回应轮写 `interactionId`，二者必须二选一。
- 学习者题目仍写在平铺 `content.stages` 中，轮次顺序必须与题目顺序一致，每个题目恰好被一个轮次引用。
- 学习者轮次不重复写答案；提交后由题目自己的正确答案恢复对话文本。当前答案与未来轮次不会提前显示。
- 回应优先使用 `fillBlank`、`reorderSentence`、`translateSentence`、`readAloud` 等直接语言运用题型。展示卡和导入记忆卡不能作为对话回应。
- 对话逐句使用系统 TTS，不填写整段预生成对话音频。

最小可运行骨架见 `templates/lesson-dialogue.json`，决策见 [ADR 0070](../decisions/0070-scenario-dialogue-lessons.md)。

---

## 2. `listening` — 听力课

### 用途

集中训练听力理解，分为三个固定阶段：单词配对、对话理解、总结听力。

### 推荐模板

`listening`

### 内容结构

`content.listeningPhases[]` 包含三种 `ListeningPhaseType`：

- `wordPairing`：听到目标语音频，选择英文释义
- `dialogue`：播放对话音频，回答理解题
- `summary`：只播放总结音频，无题目，用于收尾

### 常用题型

- `listenAndPick`：听音选择
- `typeTheWord`：听写
- `listenOnly`：只听不答（summary 阶段）

### 示例

```json
{
  "id": "l-u2-listening-greetings",
  "name": "Listening: Greetings",
  "description": "练习听辨问候语",
  "type": "listening",
  "template": "listening",
  "prerequisiteLessonIds": ["l-u1-intro-merhaba"],
  "content": {
    "listeningPhases": [
      {
        "id": "lp-word",
        "name": "Word pairing",
        "type": "wordPairing",
        "items": [
          {
            "runtimeType": "listenAndPick",
            "id": "lp-word-1",
            "audioAsset": "sounds/turkish/merhaba.mp3",
            "prompt": "What do you hear?",
            "options": ["Merhaba", "Teşekkürler", "Hoşça kal"],
            "correctIndex": 0
          }
        ]
      },
      {
        "id": "lp-dialogue",
        "name": "Dialogue",
        "type": "dialogue",
        "audioAsset": "sounds/turkish/dialogue_greetings.mp3",
        "transcript": "A: Merhaba! B: Merhaba, nasılsın?",
        "items": [
          {
            "runtimeType": "multipleChoice",
            "id": "lp-diag-1",
            "prompt": "What is the dialogue about?",
            "options": ["Greetings", "Food", "Family"],
            "correctIndex": 0
          }
        ]
      },
      {
        "id": "lp-summary",
        "name": "Summary",
        "type": "summary",
        "audioAsset": "sounds/turkish/summary_greetings.mp3",
        "transcript": "Today we learned common greetings."
      }
    ]
  }
}
```

### 设计检查清单

- [ ] 音频资源是否已放入 `assets/sounds/` 并在 `pubspec.yaml` 注册
- [ ] 是否有 `wordPairing` → `dialogue` → `summary` 的完整三阶段
- [ ] 多词音频的 `listenAndPick` / `typeTheWord` 是否在题干指明词序或说话人（不让音频中的多个选项同时满足题干）
- [ ] 对话阶段题目是否基于音频内容而非常识
- [ ] 是否为每个听力阶段提供了 `transcript`

---

## 3. `reading` — 阅读课

### 用途

提供一篇目标语阅读材料，并围绕材料设计理解题。适合培养长文本阅读能力。

### 推荐模板

`reading`

### 内容结构

- `content.readingPassage`：结构化阅读文章（标题、段落、来源等）
- `content.stages`：阅读理解题目，通常只放一个大 Stage

### 常用题型

- `readingMcq`：阅读选择题
- `readingTrueFalse`：判断正误
- `readingShortAnswer`：简答

### 示例

```json
{
  "id": "l-u3-reading-market",
  "name": "Reading: At the Market",
  "description": "阅读一篇关于市场的短文",
  "type": "reading",
  "template": "reading",
  "prerequisiteLessonIds": ["l-u2-listening-greetings"],
  "content": {
    "readingPassage": {
      "id": "rp-market",
      "title": "Pazarda",
      "paragraphs": [
        "Bugün Pazartesi. Anna pazara gidiyor.",
        "Meyve ve sebze alıyor. İki avokado yüz lira."
      ],
      "source": "Adapted from A1 reader"
    },
    "stages": [
      {
        "id": "st-reading-questions",
        "name": "Comprehension",
        "items": [
          {
            "runtimeType": "readingMcq",
            "id": "rq-1",
            "prompt": "Where does Anna go?",
            "options": ["To school", "To the market", "To the hospital"],
            "correctIndex": 1
          },
          {
            "runtimeType": "readingTrueFalse",
            "id": "rq-2",
            "statement": "Anna buys fruit and vegetables.",
            "answer": true
          }
        ]
      }
    ]
  }
}
```

### 设计检查清单

- [ ] 文章长度是否适合当前语言水平
- [ ] 题目答案是否都能在文中找到依据
- [ ] 是否覆盖了主旨、细节、推理三种理解层次
- [ ] 是否为 `readingPassage` 提供了稳定的 `id`

---

## 4. `review` — 复习课

### 用途

不引入新知识，而是混合复习前面多个课时学过的词汇、表达和语法点，帮助巩固记忆。

### 推荐模板

`review`

### 内容结构

- 可以用 `subLessons` 按主题组织复习块（推荐 3 个子课）
- 也可以用 `stages` 平铺所有复习题
- 平铺题池可声明 `reviewPolicy`，每次打开随机抽题；不写该字段则保持原有静态复习行为

随机题池示例：

```json
{
  "minItems": 15,
  "maxItems": 16,
  "typeWeights": {
    "fillBlank": 1.2,
    "reorderSentence": 1.0
  }
}
```

规则：

- `1 <= minItems <= maxItems <= 题池实际题数`；`typeWeights` 只能使用已知可作答题型，权重必须大于 0。
- 随机题池只支持平铺 `stages`，不与 `subLessons` / `listeningPhases` 混用。
- 每次装载随机确定题数，再无放回抽取并混排；同一场内不因撤销或结算重抽。
- 当前课程的课内错题会提高对应题型权重，最高为基础权重的 4 倍；不使用 FSRS 或记忆卡到期状态。
- 题池不要放 `showWord`、`listenOnly` 或导入记忆卡题型。

完整决策见 [ADR 0071](../decisions/0071-review-question-pool.md)。

### 常用题型

- `multipleChoice`
- `fillBlank`
- `translateSentence`
- `reorderSentence`
- `listenAndPick`（复习已学过的听力词）

### 示例

```json
{
  "id": "l-u1-review-basics",
  "name": "Review: Basics",
  "description": "复习第 1 单元的基础问候语",
  "type": "review",
  "template": "review",
  "prerequisiteLessonIds": ["l-u1-intro-merhaba", "l-u1-intro-tesekkurler"],
  "content": {
    "subLessons": [
      {
        "id": "sl-review-words",
        "name": "Words",
        "stages": [
          {
            "id": "st-review-mcq",
            "name": "Recall",
            "items": [
              {
                "runtimeType": "fillBlank",
                "id": "rv-1",
                "sentence": "— Bir çay _____!\n— Buyurun!",
                "answer": "lütfen",
                "choices": ["lütfen", "Merhaba"]
              },
              {
                "runtimeType": "reorderSentence",
                "id": "rv-2",
                "prompt": "请给我一杯茶",
                "scrambled": ["çay", "lütfen", "Bir"],
                "correct": ["Bir", "çay", "lütfen"]
              }
            ]
          }
        ]
      }
    ]
  }
}
```

### 设计检查清单

- [ ] 是否只包含已学过的内容，且题池内无重复题目
- [ ] 是否跨多个前置课时进行综合复习
- [ ] 是否设置了正确的前置依赖 `prerequisiteLessonIds`
- [ ] 句子级题目占比是否达到 ≥ 80%，且不出孤立单词选义单选与 `= _____` 伪填空
- [ ] 题目数量是否足够覆盖每个前置课时的核心点
- [ ] 每道填空/选择题代入所有候选词后是否仅有唯一正确答案，无多个同类词可同时成立

---

## 5. `challenge` — 挑战课

### 用途

作为单元末尾或关卡末尾的掌握检测（mastery check）。通常只有一次机会或较高通过门槛，通过后解锁后续内容。

### 推荐模板

`mastery`

### 内容结构

- 使用平铺 `stages`
- 通常只有一个 Stage，里面放一组难度混合的题目
- App 层通过 `Lesson.isMastery` 识别并启用特殊通过逻辑

### 常用题型

- `multipleChoice`
- `fillBlank`
- `translateSentence`
- `typeTheWord`
- `reorderSentence`

### 示例

```json
{
  "id": "l-u1-challenge-greetings",
  "name": "Challenge: Greetings",
  "description": "Unit 1 掌握检测",
  "type": "challenge",
  "template": "mastery",
  "prerequisiteLessonIds": [
    "l-u1-intro-merhaba",
    "l-u1-intro-tesekkurler",
    "l-u1-review-basics"
  ],
  "content": {
    "stages": [
      {
        "id": "st-mastery",
        "name": "Mastery check",
        "items": [
          {
            "runtimeType": "translateSentence",
            "id": "ch-1",
            "source": "Hello, how are you?",
            "expected": "Merhaba, nasılsın?"
          },
          {
            "runtimeType": "fillBlank",
            "id": "ch-2",
            "sentence": "_____, çok teşekkürler.",
            "answer": "Merhaba"
          }
        ]
      }
    ]
  }
}
```

### 设计检查清单

- [ ] 是否位于单元末尾并依赖本单元所有核心课
- [ ] 题目是否覆盖了本单元的核心词汇和语法
- [ ] 是否避免引入未学过的表达
- [ ] 句子级题目占比是否达到 ≥ 80%，且不出孤立单词选义单选与 `= _____` 伪填空
- [ ] 是否设置了合理的通过门槛（由 App 层控制）
- [ ] 逐一自读通读每道题并代入所有候选词，确认唯一解且不要求产出「只听不说」的店员侧表达

---

## 6. `guide` — 分页导览课

用于语言认识、文化背景和规则观察。`type` 仍为 `normal`，`template` 为 `guide`，正文只写 `content.pages`，不得混入 `stages`、`subLessons` 或 `listeningPhases`。页面不是逐题 Interaction：没有正确率、错题、SRS 或答题奖励，到达最后一页后仅记录课程完成。

每页包含稳定 `id`、`title`，可选 `kicker`、`intro` 与 `blocks`。末页可设置 `nextLabel`、`nextLessonId`、可选 `nextSubLessonId`，完成页据此进入下一课；`nextSubLessonId` 不得单独出现。

### 内容块

| `runtimeType` | 用途 | 核心字段 |
|---|---|---|
| `text` | 标题与长段介绍 | `title?`、`body` |
| `terms` | 点读词卡或字母卡 | `items[]`，每项 `text`、`translation`、`note`、`speechText?`、`wordId?`；`compact: true` 使用紧凑网格 |
| `classification` | 通用拖拽／点选分类 | `categories[]` 与 `cards[]`；卡片用 `categoryId` 指向应探索的分类，并可写 `hint`、`highlight` |
| `suffixBuilder` | 词根与词尾组合探索 | `examples[]`；每个例子的 `steps[]` 写 `suffix`、完整 `result`、`meaning` |
| `wordOrder` | 语序与句子成分探索 | `tokens[]`，每项 `text`、`role`、`meaning`，可选 `optional`；有可选词块时必须写 `optionalToggleLabel` |

分类的 `categoryId` 只用于即时解释，不计对错，不阻止翻页。`terms.wordId` 只追踪课程资源引用，不注册复习调度。所有页面与块 ID 在课内唯一；分类至少两个区域，互动列表不得为空。

```json
{
  "id": "nt-u0-l1-turkce-guide",
  "name": "认识土耳其语",
  "type": "normal",
  "template": "guide",
  "prerequisiteLessonIds": [],
  "content": {
    "pages": [
      {
        "id": "guide-tr-1-world",
        "kicker": "第一印象",
        "title": "你已经在接触土耳其语",
        "intro": "先不背词，也不做题。",
        "blocks": [
          {
            "runtimeType": "text",
            "id": "guide-tr-1-where",
            "title": "它在什么地方",
            "body": "土耳其语（Türkçe）属于突厥语族。"
          },
          {
            "runtimeType": "terms",
            "id": "guide-tr-1-terms",
            "title": "点一点，先听个大概",
            "items": [
              {
                "text": "Türkçe",
                "translation": "土耳其语",
                "note": "语言的名字",
                "wordId": "nt-w-turkce"
              }
            ]
          }
        ]
      }
    ]
  }
}
```

---

## 通用规则

### ID 规范

- Lesson ID 全局唯一，建议格式：`l-{unitSlug}-{n}` 或稳定的 UUID
- 一旦发布不要修改 ID，否则会丢失用户学习记录

### 内容字段选择

| 模板 | 使用字段 | 不要混用 |
|------|----------|----------|
| `guide` | `pages` | 任何答题阶段或子课 |
| `intro` / `practice` | `subLessons` | 与 `stages` 同时作为主线 |
| `review` | `subLessons`，或平铺 `stages` + 可选 `reviewPolicy` | 随机题池不与子课混用 |
| `listening` | `listeningPhases` | — |
| `dialogue` | `dialogueScene` + 平铺 `stages` | 不与子课 / 听力阶段混用 |
| `reading` | `readingPassage` + `stages` | — |
| `mastery` / `legacy` | `stages` | — |

### 语法点关联

如需让错题可以跳转到语法复习，在内容或题型上添加：

```json
{
  "runtimeType": "multipleChoice",
  "id": "mc-verb",
  "prompt": "Choose the correct verb form.",
  "options": ["gelir", "gider"],
  "correctIndex": 0,
  "grammarPointId": "gp-present-tense"
}
```

对应的 `grammarPointId` 必须已在 `grammar_points.json` 中定义。

课时级注册走 `content.linkedGrammarPointIds`（打开课时时写入语法 SRS）。词汇 `pos` 与 `showWord` 的内联覆盖字段（`term` / `translation` / `pronunciation` / `audioAsset` / `imageAsset` / `example`）可空；非空时覆盖词表默认显示。

### 替代答案与阅读词形

- `translateSentence`、`readingShortAnswer` 可用 `acceptedAnswers: []` 声明其他正确答案；`expected` / `expectedAnswer` 仍是答错后展示的规范答案。
- `reorderSentence` 的 `acceptedAnswers` 每项写完整句子字符串，例如 `"world hello"`；它必须与 `correct` 使用相同词块，只允许不同的排列。
- 判分统一折叠土耳其语大小写、支持的变音符号、连续空白与常见标点，不调用运行时 LLM。
- `readingPassage.wordFormMap` 用「文中词形 → vocab id」处理黏着词形，例如 `"evimde": "nt-w-ev"`；`linkedWordIds` 控制普通词形的点词范围，`imageAsset` 与 `imageAlt` 提供插图及无障碍文本。

---

## 导入题型（不进教学阶梯）

`ankiCard` 与 `ankiHtmlCard` 只来自 Anki 导入，AI 生成不要产出它们。媒体引用可以使用 `anki://<importId>/<file>`，桌面 lint 不要求仓库里存在该文件。`ankiHtmlCard` 的完整 HTML 渲染在 App 里；编辑器只保留剥标签后的文本。

---

## 参考

- 课程加载与类型定义：`lib/domain/course/lesson.dart`
- 题型定义：`lib/domain/course/interaction.dart`
- 听力阶段定义：`lib/domain/course/listening_phase.dart`
- 验证工具：`tool/course_cli.py`
- 已有最小模板：`docs/authoring/templates/`
