# A1 听力课节目格式设计（MiniMax 版）

面向 A1 阶段、以“广播节目”为包装的听力课。每节课是一段 2 分钟左右的短节目，
由 **开场 BGM + 节目片头 → 课前词 → 正片 → 题目 → 结束语** 组成。

> 音频合成平台：**MiniMax**（`https://api.minimax.io/v1/t2a_v2`）
> 目标课程类型：`listening` / `template: listening`
> 对应代码模型：`lib/domain/course/listening_phase.dart`

---

## 1. 节目结构（时间线）

```
0:00  ├─ 节目片头（3–5s）+ BGM
      │   "Welcome to today's show. Today we are going to..."
      │   每个节目的片头文案/风格不同
0:05  ├─ 固定课前词导语（~5s）
      │   "Before the video, here are some words that you should know..."
0:10  ├─ 4 个关键单词（每个 3–4s，共 ~15s）
      │   只读单词 + 简单英文释义（A1 水平）
0:25  ├─ 正片节目（~45–60s）
      │   三种节目档案之一
1:10  │   题目 1：选出听到的单词（5 选 3）
1:20  │   题目 2：细节理解题（1 题）
1:30  └─ 题目 3：主旨大意题（选择题）
1:40  └─ 节目结束语（3–5s，可复用）
      │   "Thanks for listening. See you next time."
```

总时长控制在 **1 分 30 秒 ~ 2 分钟**。

---

## 2. 三种节目档案

| 节目 | 中文名 | 内容形式 | 语气/风格 | 适合主题 |
|------|--------|----------|-----------|----------|
| Show 1 | 又是一个奇怪的人 | 听众打电话进直播间，向主播讲述自己的困扰/故事 | 轻松、对话感、略带戏剧化 | 日常麻烦、求助、购物、问路 |
| Show 2 | 探索日记 | 主播介绍一个事物、地点或活动 | 科普、平稳、信息型 | 动物、食物、节日、交通工具 |
| Show 3 | 妈妈的作文 | 一位妈妈朗读自己写的“今天发生了什么”日记 | 温暖、叙事、生活化 | 家庭、一天作息、市场、做饭 |

每个节目有独立的片头文案和片头 BGM，形成品牌感。

---

## 3. 片段与 JSON 映射

在课程 JSON 中，一节听力课拆成 3 个 `ListeningPhase`：

```json
{
  "id": "l-uX-listening-example",
  "name": "Listening: Example Show",
  "type": "listening",
  "template": "listening",
  "content": {
    "listeningPhases": [
      {
        "id": "lp-intro",
        "name": "Show intro",
        "type": "wordPairing",
        "audioAsset": "listening/uX_show_intro",
        "transcript": "Welcome to today's show. Today we are going to hear a story about a strange phone call.",
        "items": []
      },
      {
        "id": "lp-prewords",
        "name": "Words before the show",
        "type": "wordPairing",
        "audioAsset": "listening/uX_prewords",
        "transcript": "Before the video, here are some words that you should know. Market. Money. Banana. Help.",
        "items": [
          {
            "runtimeType": "listenAndPick",
            "id": "preword-1",
            "audioAsset": "listening/uX_prewords",
            "prompt": "Which words do you hear?",
            "options": ["market", "school", "money", "banana", "help"],
            "correctAnswer": "market"
          }
        ]
      },
      {
        "id": "lp-main",
        "name": "Main show",
        "type": "dialogue",
        "audioAsset": "listening/uX_main_show",
        "transcript": "...",
        "items": [
          {
            "runtimeType": "multipleChoice",
            "id": "main-detail-1",
            "prompt": "Where does the story happen?",
            "options": ["At school", "At the market", "At home"],
            "correctAnswer": "At the market"
          },
          {
            "runtimeType": "multipleChoice",
            "id": "main-gist-1",
            "prompt": "What is the show mainly about?",
            "options": [
              "A man loses his money",
              "A woman buys bananas",
              "A child goes to school"
            ],
            "correctAnswer": "A man loses his money"
          }
        ]
      }
    ]
  }
}
```

> 说明：
> - `lp-intro` 对应“片头 + 课前词导语”，可以合并成一条音频。
> - `lp-prewords` 对应 4 个关键单词；题目可以是“选出听到的单词”。
> - `lp-main` 对应正片 + 2 道题目（细节 + 主旨）。
> - `type` 字段复用现有枚举：`wordPairing` / `dialogue` / `summary`。

---

## 4. 音频生产流程（MiniMax）

### 4.1 文案准备

每节课需要以下文案：

1. **片头文案**（固定，可复用）
2. **课前词文案**（固定 + 4 个单词释义）
3. **正片脚本**（约 80–100 个英文/土耳其语单词）
4. **结束语文案**（固定，可复用）

### 4.2 MiniMax 生成

1. 选择适合节目角色的 MiniMax 音色。
2. 为每个节目建立固定音色：
   - Show 1：主播 + 听众（可一人分饰，用不同 voice_id）
   - Show 2：主播单人
   - Show 3：妈妈角色
3. 按片段生成音频：
   - `u{unit}_show_intro.mp3`
   - `u{unit}_prewords.mp3`
   - `u{unit}_main_show.mp3`
   - `outro.mp3`（全局复用）

#### 4.2.1 已配置的 MiniMax Voice ID

| 角色 | Voice ID | 推荐使用场景 |
|------|----------|--------------|
| 精英男声 | `male-qn-jingying` | Show 1「又是一个奇怪的人」主播 / 男听众；Show 2「探索日记」主播 |
| 温柔女声 | `female-tianmei` | Show 1 女听众 / 求助者；Show 2「探索日记」主播；也可用于部分 Show 3 |
| 少女声 | `female-shaonv` | Show 3「妈妈的作文」妈妈角色（温暖、叙事感） |

建议的节目音色分配（可调整）：

- **Show 1（又是一个奇怪的人）**
  - 主播：精英男声 `male-qn-jingying`
  - 打电话的听众：温柔女声 `female-tianmei` 或 少女声 `female-shaonv`
- **Show 2（探索日记）**
  - 主播：温柔女声 `female-tianmei`（柔和、科普感）
- **Show 3（妈妈的作文）**
  - 妈妈：少女声 `female-shaonv`

> 通用参数：
> - `model`: `speech-2.8-hd`
> - `output_format`: `mp3`
> - `speed`: 建议 `0.9`，A1 听力稍慢更清晰
> - 认证：环境变量 `MINIMAX_API_KEY`（必需），部分账号还需 `MINIMAX_GROUP_ID`

### 4.3 BGM 与混音（批量脚本）

MiniMax TTS **不生成 BGM**，需要后期混音。混音策略：

- **BGM 只贯穿正片（main）**，不贯穿固定的片头和结束语。
- 片头（debutA/B/C.mp3）和结束语（finA/B/C.mp3）是 3 套固定素材，按节目类型选用。
- 使用批量脚本 `tool/mix_listening_a1.py` 合成最终文件。

目录约定（A1 专用）：

```
assets/sounds/turkish/listening/
  ├── raw_a1/                 # MiniMax 生成的中间文件
  │     ├── S1U1L01A.mp3
  │     ├── S1U1L02B.mp3
  │     └── ...
  ├── debut/
  │     ├── debutA.mp3        # Show 1：又是一个奇怪的人
  │     ├── debutB.mp3        # Show 2：探索日记
  │     └── debutC.mp3        # Show 3：妈妈的作文
  ├── fin/
  │     ├── finA.mp3
  │     ├── finB.mp3
  │     └── finC.mp3
  ├── bgm/
  │     ├── bgmA.mp3          # Show 1 正片 BGM
  │     ├── bgmB.mp3          # Show 2 正片 BGM
  │     └── bgmC.mp3          # Show 3 正片 BGM
  └── mixed_a1/               # 最终输出
        ├── S1U1L01A_mixed.mp3
        ├── S1U1L02B_mixed.mp3
        └── ...
```

节目类型映射表：`tool/mappings/a1_show_mapping.csv`

```csv
S1U1L01,A
S1U1L02,B
S1U1L03,C
```

批量合成命令：

```bash
# 1. 安装依赖
pip install pydub

# 2. 批量合成
python tool/mix_listening_a1.py all \
  --main-dir assets/sounds/turkish/listening/raw_a1 \
  --debut-dir assets/sounds/turkish/listening/debut \
  --fin-dir assets/sounds/turkish/listening/fin \
  --bgm-dir assets/sounds/turkish/listening/bgm \
  --mapping tool/mappings/a1_show_mapping.csv \
  --output-dir assets/sounds/turkish/listening/mixed_a1
```

脚本行为：

- 读取 `raw_a1/` 下每个 `S1U1LxxY.mp3`。
- 根据 mapping 决定节目类型 A/B/C，进而选用：
  - `debutA/B/C.mp3` 片头
  - `finA/B/C.mp3` 结束语
  - `bgmA/B/C.mp3` 正片背景音乐
- 把对应节目的 BGM 循环/裁剪到与 main 等长，音量降低约 -18dB 后叠加到 main。
- 拼接：`debut + (main+BGM) + fin`。
- 输出 `mixed_a1/S1U1LxxY_mixed.mp3`。

单文件调试：

```bash
python tool/mix_listening_a1.py one \
  assets/sounds/turkish/listening/raw_a1/S1U1L01A.mp3 \
  --variant A \
  --output /tmp/test.mp3
```

### 4.4 批量生成 MiniMax 语音

使用 `tool/generate_audio.py` 批量读取课程 JSON 中的 `listeningPhases`，调用 MiniMax API 生成 MP3。

```bash
# 生成全部听力音频
MINIMAX_API_KEY=sk-xxx python tool/generate_audio.py all

# 指定音色（默认使用 female-tianmei）
MINIMAX_API_KEY=sk-xxx python tool/generate_audio.py all --voice-id male-qn-jingying

# 生成单个文本到指定路径
MINIMAX_API_KEY=sk-xxx python tool/generate_audio.py speak "Welcome to today's show" /tmp/welcome.mp3
```

脚本行为：

- 扫描 `assets/courses/turkish/` 下所有 `template: listening` 的课程。
- 收集每个 `ListeningPhase.audioAsset` 及其 `transcript`。
- 调用 MiniMax `POST /v1/t2a_v2`，参数：`model=speech-2.8-hd`、`output_format=mp3`、`speed=0.9`。
- 将返回的音频字节写入 `assets/sounds/turkish/listening/{audioAsset}.mp3`。

---

## 5. 题目设计规则

### 题目 1：选出听到的单词（5 选 3）

- 从 4 个课前词里选 3 个作为正确答案。
- 第 4 个正确答案可来自正片新出现的、本单元学过的词。
- 干扰项可以不是是本单元学过的词，避免完全陌生。
- 题型：`multipleChoice` 或 `listenAndPick`（如允许重听）。

示例：

```json
{
  "runtimeType": "multiSelect",
  "id": "hear-words-1",
  "prompt": "Which 3 words do you hear in the show?",
  "options": ["market", "money", "banana", "school", "help"],
  "correctIndices": [0, 1, 2],
  "minSelections": 3,
  "maxSelections": 3
}
```

> `multiSelect` 支持多选；`correctIndices` 是所有正确选项的零基索引。

### 题目 2：细节理解题

- 只考正片中明确提到的信息。
- A1 级别避免推理，答案直接在台词里。

### 题目 3：主旨大意题

- 用一句话概括节目内容。
- 干扰项为细节放大或完全无关。

---

## 6. 生产清单（每节课）

- [ ] 确定本单元 4 个关键单词（均为已学词）
- [ ] 选择节目档案（Show 1 / 2 / 3）
- [ ] 写片头文案（≤30 词）
- [ ] 写课前词文案 + 4 词英文释义
- [ ] 写正片脚本（80–100 词，A1 句型）
- [ ] 写 3 道题目 + 答案
- [ ] 在 MiniMax 生成语音
- [ ] 用 `tool/mix_listening_a1.py` 叠加片头 BGM
- [ ] 输出 MP3 到 `assets/sounds/turkish/listening/`
- [ ] 更新课程 JSON 的 `listeningPhases`
- [ ] 运行 `python tool/course_cli.py validate`

---

## 7. 后续事项

- **节目模板库**：为每种 Show 写 2-3 个固定片头文案和 BGM 候选，方便轮换。

已完成：`multiSelect` 题型、`tool/mix_listening_a1.py` 混音脚本、`tool/generate_audio.py`（MiniMax 版）批量生成。
