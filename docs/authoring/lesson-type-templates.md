# 课程类型设计模板

本模板用于在 `assets/courses/<lang>/sections/*.json` 中设计单节课（Lesson）。
它围绕五种 `LessonType` 展开，并给出每种类型推荐的 `LessonTemplate`、内容结构、典型题型和最小可运行示例。

> 与代码模型的对应关系见 `lib/domain/course/lesson.dart`。
> 所有 JSON 编写完成后必须运行：
>
> ```bash
> python3 tool/course_cli.py validate --course-dir assets/courses/swahili
> python3 tool/course_cli.py lint --course-dir assets/courses/swahili
> ```

---

## 类型速查

| 类型 | 用途 | 推荐模板 | 核心内容字段 |
|------|------|----------|--------------|
| `normal` | 普通新课或常规练习 | `intro` / `practice` / `legacy` | `subLessons` 或 `stages` |
| `listening` | 听力专项训练 | `listening` | `listeningPhases` |
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

### 常用题型

- `showWord`：展示新词
- `multipleChoice`：选择释义 / 用法
- `fillBlank`：填空
- `translateSentence`：翻译句子
- `reorderSentence`：句子排序

### 示例

```json
{
  "id": "l-u1-intro-jambo",
  "name": "Jambo",
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
                "id": "sw-jambo",
                "wordId": "w-jambo"
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
                "id": "mc-jambo",
                "prompt": "What does 'Jambo' mean?",
                "options": ["Hello", "Goodbye", "Thanks"],
                "correctAnswer": "Hello"
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
- [ ] 新词是否先在 `vocab.json` 中定义
- [ ] 子课数量是否在 3–5 个之间
- [ ] 是否有至少一种产出型练习（翻译 / 填空 / 排序）

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
  "prerequisiteLessonIds": ["l-u1-intro-jambo"],
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
            "audioAsset": "sounds/swahili/jambo.mp3",
            "prompt": "What do you hear?",
            "options": ["Jambo", "Asante", "Kwaheri"],
            "correctAnswer": "Jambo"
          }
        ]
      },
      {
        "id": "lp-dialogue",
        "name": "Dialogue",
        "type": "dialogue",
        "audioAsset": "sounds/swahili/dialogue_greetings.mp3",
        "transcript": "A: Jambo! B: Jambo, habari?",
        "items": [
          {
            "runtimeType": "multipleChoice",
            "id": "lp-diag-1",
            "prompt": "What is the dialogue about?",
            "options": ["Greetings", "Food", "Family"],
            "correctAnswer": "Greetings"
          }
        ]
      },
      {
        "id": "lp-summary",
        "name": "Summary",
        "type": "summary",
        "audioAsset": "sounds/swahili/summary_greetings.mp3",
        "transcript": "Today we learned common greetings."
      }
    ]
  }
}
```

### 设计检查清单

- [ ] 音频资源是否已放入 `assets/sounds/` 并在 `pubspec.yaml` 注册
- [ ] 是否有 `wordPairing` → `dialogue` → `summary` 的完整三阶段
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
      "title": "Sokoni",
      "paragraphs": [
        "Leo ni Jumatatu. Anna anaenda sokoni.",
        "Ananunua matunda na mboga. Mbili za parachichi ni shilingi mia moja."
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
            "correctAnswer": "To the market"
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
  "prerequisiteLessonIds": ["l-u1-intro-jambo", "l-u1-intro-asante"],
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
                "runtimeType": "multipleChoice",
                "id": "rv-1",
                "prompt": "How do you say 'Thank you'?",
                "options": ["Jambo", "Asante", "Kwaheri"],
                "correctAnswer": "Asante"
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

- [ ] 是否只包含已学过的内容
- [ ] 是否跨多个前置课时进行综合复习
- [ ] 是否设置了正确的前置依赖 `prerequisiteLessonIds`
- [ ] 题目数量是否足够覆盖每个前置课时的核心点

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
    "l-u1-intro-jambo",
    "l-u1-intro-asante",
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
            "expected": "Jambo, habari?"
          },
          {
            "runtimeType": "fillBlank",
            "id": "ch-2",
            "sentence": "_____, asante sana.",
            "answer": "Jambo"
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
- [ ] 是否设置了合理的通过门槛（由 App 层控制）

---

## 通用规则

### ID 规范

- Lesson ID 全局唯一，建议格式：`l-{unitSlug}-{n}` 或稳定的 UUID
- 一旦发布不要修改 ID，否则会丢失用户学习记录

### 内容字段选择

| 模板 | 使用字段 | 不要混用 |
|------|----------|----------|
| `intro` / `practice` / `review` | `subLessons` | 与 `stages` 同时作为主线 |
| `listening` | `listeningPhases` | — |
| `reading` | `readingPassage` + `stages` | — |
| `mastery` / `legacy` | `stages` | — |

### 语法点关联

如需让错题可以跳转到语法复习，在内容或题型上添加：

```json
{
  "runtimeType": "multipleChoice",
  "id": "mc-verb",
  "prompt": "Choose the correct verb form.",
  "options": ["..."],
  "correctAnswer": "...",
  "grammarPointId": "gp-present-tense"
}
```

对应的 `grammarPointId` 必须已在 `grammar_points.json` 中定义。

---

## 参考

- 课程加载与类型定义：`lib/domain/course/lesson.dart`
- 题型定义：`lib/domain/course/interaction.dart`
- 听力阶段定义：`lib/domain/course/listening_phase.dart`
- 验证工具：`tool/course_cli.py`
- 已有最小模板：`docs/authoring/templates/`
