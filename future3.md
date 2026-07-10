# Varnamala Future Plan v3：从"框架可用"到"内容可规模化生产"

> 本文档继承 [`future2.md`](./future2.md)。future2 解决了"框架打磨"问题；future3 解决"如何持续、低成本、高质量地生产内容"以及"如何让这套框架真正对学习者有长期价值"的问题。
>
> 撰写日期：2026-07-10
> 适用对象：开发者 / Agent / 内容贡献者

---

## 1. 文档定位

| 文档 | 回答的问题 | 状态 |
|---|---|---|
| `dreamplan.md` | 早期"宏大愿景"（11,000 课、GUI 编辑器等） | 已被 future2 取代，仅作历史参考 |
| `future2.md` | 如何把现有框架去社交化、打磨到任意内容都能正确渲染复习统计 | 已完成（Phase 7–12） |
| `future3.md` | 下一步目标：内容替换、内容生产工具、学习体验深化、框架长期维护 | **本文档** |

**核心原则延续**：
- 本地优先、无云、无社交、无付费摩擦。
- 不引入 Hearts / League / Leaderboard / Gems 商店等"反学习"机制。
- 任何新功能必须回答一个问题：**它是否让"单人离线学习"变得更好？**

---

## 2. 当前真实状态（future2 之后）

### 2.1 已验证完成的资产

- 11 种 Interaction Renderer、6 种 Lesson Template 的渲染/进度/复习链路已跑通。
- SRS（SM-2）、错题本、语法复习、学习统计、暗色模式、TTS 语速等核心闭环稳定。
- `flutter test` 132/132 通过，`flutter analyze` 0 error。
- 社交/排行榜/联赛/红心/宝石商店/Patreon 等代码已清理。

### 2.2 当前最突出的矛盾

| 矛盾 | 现象 | 影响 |
|---|---|---|
| **内容与品牌严重不符** | `assets/courses/swahili/vocab.json` 仍是 Kannada 占位词（Naanu / Neenu / Howdu），但 `index.json` 标为 Swahili、`grammar_points.json` 已是真正 Swahili 语法、TTS 语言码已切到 `sw` | 用户学习的是"标为 Swahili 的 Kannada 词汇"，体验不可接受 |
| **Expression 管道空转** | schema v5 已支持 `Expressions` 表，`expressions.json` 存在但为空数组 | 花了工程成本，没有学习内容产出 |
| **内容生产方式原始** | 所有课程数据是手写 JSON + `course_validator.dart` 离线校验 | 生产 100 课尚可，生产 1,000+ 课效率极低、易出错 |
| **音频策略未闭环** | `WordEntry.audioAsset` / `Expression.audioAsset` 字段存在，但没有任何真实离线音频；TTS 已切 `sw` 但词汇是 `kn` | 听力题、发音示范无法真实验证 |
| **学习辅助功能缺失** | 无词典/搜索、无本地复习提醒、无内容更新机制 | 学完即走，难以形成长期学习习惯 |

### 2.3 一个基本判断

> future2 让 Varnamala 成为了一台"好车"；future3 的任务是给这台车加"油"（真实 Swahili 内容）和"加油站"（可持续生产内容的工具链）。没有油，车再好也到不了目的地。

因此，**future3 必然涉及内容生产**。这与 future2 的"不新增内容"临时禁令不矛盾——future2 的禁令是为了先完成框架；future3 的禁令是"不生产低质量/一次性内容"，目标是建立可复用的内容生产能力。

---

## 3. 总目标

**把 Varnamala 从"技术框架 demo"变成"真正可学的 Swahili 课程产品"，并建立让非程序员也能持续贡献内容的工具链。**

具体拆为四个子目标：

1. **内容替换**：用真实、系统的 Swahili 词表/表达/课文替换 Kannada 占位内容。
2. **内容生产工业化**：建立 CSV/TSV → JSON → 校验 → 构建的流水线，降低内容贡献门槛。
3. **音频闭环**：确定 TTS 预生成 / 真人录音 / 运行时 TTS 的混合策略，让听力题真实可用。
4. **学习体验深化**：词典、搜索、本地复习提醒、弱词专项训练等不依赖社交/付费的辅助功能。

---

## 4. 明确不做（继承并扩展 future2）

| 不做项 | 原因 |
|---|---|
| 任何社交 / 排行榜 / 联赛 / 好友 / 私信 | 与单人离线学习无关 |
| 任何付费道具 / 订阅 / 广告 / Patreon 入口 | 本地优先、无摩擦 |
| Hearts / Lives / Streak Repair / XP 乘数 | 反学习摩擦 |
| 云端 CMS / 后端 / 增量同步 / Firebase | 本地优先；内容通过应用更新/侧载分发 |
| Speaking 题型（录音匹配） | 准确率瓶颈；TTS + 听力已足够 |
| 外部 GUI 编辑器（重型） | 先做轻量 CLI/网页生成器，再评估是否需要 GUI |
| 多语言课程（除 Swahili 外） | 先把单一目标语做深，再考虑复用 |
| AI 自动生成完整课程（无人工校验） | 生成内容必须经过校验和审核流程 |

---

## 5. 明确要做

### 5.1 内容替换（最高优先级，但放在最后做"大爆炸"）

- 用真实 Swahili A1/A2 词表替换 `vocab.json` 中的 Kannada 占位词。
- 保持 `id` 稳定或建立迁移映射；避免破坏已有进度统计。
- 补充 `expressions.json`：常用短语、问候、数字、时间表达等。
- 重写 `s-foundations` / `s-daily` / `s-world` 的课程 lesson，使其与真实 Swahili 词汇和语法一致。
- 删除或归档 `s-test.json` 中的 smoke lesson（或保留为框架测试，不面向用户）。
- **关键原则**：先建工具链、先用小批量试点验证流程，最后再做全量替换。避免"一次性改几千行 JSON 后跑不通"。

### 5.2 内容生产工业化

- `tool/course_cli.py`：命令行工具，支持：
  - `validate`：调用 Dart `course_validator` 的等价逻辑，离线校验整个课程。
  - `import-csv`：从 CSV/TSV 导入 vocab / expressions / grammar points。
  - `export-csv`：把现有 JSON 导出为 CSV，方便译者/内容作者编辑。
  - `lint`：检查 dangling wordId、空 translation、缺失 audioAsset 标记等。
- `tool/audio_manifest.py`：扫描课程中所有 `audioAsset` 引用，生成待录制/待 TTS 生成的清单。
- `tool/content_diff.py`：比较两个版本课程，输出新增/删除/修改的词条，便于版本说明。

### 5.3 音频策略落地

- **运行时 TTS**：作为 fallback 保留，但优先使用预生成音频。
- **批量 TTS 预生成**：使用 Piper / Coqui TTS / 其他本地 Swahili 语音模型，批量生成 `.mp3`，放入 `assets/sounds/swahili/`。
- **真人录音接口**：定义志愿者录音提交格式（ID 匹配、采样率、命名规范），为后续社区贡献留口子。
- **听力题真实化**：所有 `listenAndPick` / `listenOnly` / `TypeTheWord` 的音频引用必须指向真实音频或生成清单中的条目。

### 5.4 学习体验深化

- **词典 / 搜索**：新增 `DictionaryPage`，支持按 term / translation / tag 搜索 vocab / expression / grammar point。
- **弱词专项复习**：在 SRS 基础上，针对错误率高的词生成"弱词练习"小测验。
- **本地复习提醒**：使用 `flutter_local_notifications`，在用户设定的时间发送温和的每日复习提醒（可关闭）。
- **学习路径可视化**：在课程树显示已掌握 / 待复习 / 薄弱单元。
- **内容更新提示**：当应用内置课程 version 变化时，提示用户重置进度或保留进度继续学习。

### 5.5 框架长期维护

- **可访问性审计**：语义标签、颜色对比度、屏幕阅读器支持。
- **大课程性能**：课程树大数据量下的渲染优化、图片/音频懒加载。
- **发布流水线**：`flutter build apk/appbundle/web` 的脚本化，自动打包课程资源。
- **文档更新**：`CLAUDE.md` 增加内容贡献指南；`docs/decisions/` 增加音频策略、内容版本策略等 ADR。

---

## 6. 阶段规划

> 与 future2 不同，future3 的每一步都会**实际修改或生产内容**。因此每步必须有明确的"内容质量标准"和"工程验收标准"。
>
> **关键顺序**：先建工具 → 再用小批量真实内容试点验证 → 再扩展学习功能 → 最后做全量内容替换。全量替换放在最后，是因为一旦替换，所有 lesson、音频、测试都会联动变化，必须在工具和流程都跑通后再执行。

### Phase 13：内容审计与迁移映射（1 周）

**目标**：搞清楚"现有 Kannada 占位词对应哪些真实 Swahili 词"，确保替换不会丢失 lesson 结构。

1. **导出当前内容清单**
   - 运行脚本输出所有 `wordId` / `term` / `translation` / `tags` / 被哪些 lesson 引用。
   - 输出所有 `expressionId` 引用（当前为 0）。
   - 输出所有 `grammarPointId` 引用。

2. **建立 Swahili A1 词表草案**
   - 参考开源 Swahili 词表（如 SIL、Wiktionary A0/A1 lists）。
   - 按主题分组：greetings、pronouns、numbers、colors、family、food、travel、verbs 等。
   - 每个词包含：term、translation、pronunciation（可选）、tags、audioAsset 占位。

3. **设计迁移映射**
   - 对每一个被 lesson 引用的 Kannada `wordId`，决定：
     - 替换为哪个 Swahili `wordId`；
     - 或删除该引用并调整 lesson；
     - 或保留旧 id 但改 term（不推荐，易造成混淆）。
   - 输出 `migration/vocab_map.json`。

4. **决策：是否重置用户进度？**
   - 选项 A：替换内容但保留 `completedLessonIds`（用户已完成标记不变）。
   - 选项 B：内容大改时提示用户"课程已更新，是否重置进度？"。
   - 写入 ADR：`docs/decisions/0002-content-replacement-progress-policy.md`。

**验收**：
- `migration/vocab_map.json` 覆盖所有被引用的 Kannada wordId。
- 脚本 `tool/export_content_inventory.py` 可运行并输出清单。

---

### Phase 14：内容生产 CLI（2 周） ✅ 已完成

**目标**：在动大规模内容之前，先把"怎么生产内容"的工具链做出来。

**完成摘要**：
- 实现 `tool/course_cli.py`（Python 3 标准库），子命令：`validate`、`import-csv`、`export-csv`、`lint`、`audio-manifest`、`diff`。
- 实现 `test/course_cli_test.py` 共 7 个单元测试，覆盖正常路径与异常路径。
- 新增 `.github/workflows/course_validation.yml`，PR / push 到 `master` 时自动校验课程内容。
- `python tool/course_cli.py validate` 对当前课程 0 error；`flutter test` 132/132 通过。

1. **`tool/course_cli.py` 骨架**
   - 子命令：`validate`、`import-csv`、`export-csv`、`lint`、`audio-manifest`、`diff`。
   - 使用 Python 标准库 + 可选依赖（如 `tabulate`、`requests`）。

2. **`validate` 命令**
   - 加载 `index.json` → 合并所有 section → 加载 vocab / expressions / grammar → 运行与 Dart `course_validator.dart` 等价的检查。
   - 输出所有错误，exit code 非零时 CI 失败。

3. **`import-csv` / `export-csv` 命令**
   - 支持 vocab / expressions / grammar_points 三张表。
   - CSV 列与 JSON 字段映射清晰。
   - 导入时自动补全默认值、检查重复 term/translation。

4. **`lint` 命令**
   - 检查空 translation、空 term、tag 拼写、audioAsset 缺失、dangling 引用。
   - 输出 warning 和 error 两类问题。

5. **CI 集成**
   - GitHub Actions workflow：PR 时自动 `course_cli.py validate`。
   - 课程数据变更必须过校验才能合并。

**验收**：
- 任一贡献者可通过 `python tool/course_cli.py import-csv --type vocab words.csv` 更新词表。
- GitHub Actions 校验失败时 PR 不能合并。

---

### Phase 15：音频策略与管道（2–3 周） ✅ 已完成

**目标**：确定音频生成方案并建立可批量执行的管道。

**完成摘要**：
- 写入 ADR：`docs/decisions/0003-audio-generation-strategy.md`，明确本地批量预生成 + 运行时 Piper TTS fallback 的混合策略。
- 创建音频资源目录：`assets/sounds/swahili/{words,expressions,listening}/`。
- 更新 `pubspec.yaml` 让 Flutter 打包新音频目录。
- 实现 `tool/generate_audio.py`：支持 `all` / `list` / `speak` 子命令，优先 `sherpa-onnx` Python API，备选 `piper` CLI。
- 更新 `tool/course_cli.py audio-manifest`：识别新的目录约定并输出分类覆盖率。
- 新增 `docs/audio-recording-guidelines.md` 真人录音提交指南。
- 新增 `test/generate_audio_test.py` 8 个单元测试。
- 未在当前环境实际生成音频（无 TTS 后端），脚本在无后端时输出待生成清单并退出；Phase 16 安装后端后批量生成试点音频。

1. **确定音频生成方案**
   - 评估 Piper Swahili 模型质量、Coqui TTS、Mozilla TTS 等。
   - 写入 ADR：`docs/decisions/0003-audio-generation-strategy.md`。
   - 选择方案：本地批量生成 + 运行时 fallback TTS。

2. **建立音频资源目录**
   - `assets/sounds/swahili/words/`：按 `wordId` 命名，如 `w-habari.mp3`。
   - `assets/sounds/swahili/expressions/`：按 `expressionId` 命名。
   - `assets/sounds/swahili/listening/`：按 lesson 或 listening phase 命名。

3. **批量生成脚本**
   - `tool/generate_audio.py`：读取 vocab + expressions + listening 清单，批量调用 TTS 引擎生成 mp3。
   - 输出缺失清单，便于人工补录。

4. **真人录音接口**
   - 定义提交格式：文件命名、采样率 44.1kHz、单声道/立体声、ID 与课程条目对应规则。
   - `tool/audio_manifest.py` 输出"需要录音的条目清单"。

**验收**：
- `tool/generate_audio.py` 可为一个 CSV 词表批量生成音频。
- 生成后的音频可被 `AudioController.speakWord` 正确播放。
- 无 audioAsset 的 word 仍能 fallback 到 TTS。

---

### Phase 16：试点内容种子（1 周）

**目标**：用一小批真实 Swahili 内容验证 CLI、音频管道和模板渲染，不碰全量课程。

1. **选择试点内容**
   - **词汇**：10–15 个最基础的 Swahili 词（如 `habari`、`nzuri`、`jambo`、`asante`、`mimi`、`wewe`、`sisi`、`moja`、`mbili`、`tatu`）。
   - **表达**：5–10 条常用短语（如 `Habari gani?`、`Nina furaha`、`Jina langu ni ...`）。
   - **语法点**：1 个简单语法点（如问候语）。

2. **通过 CLI 导入试点内容**
   - 用 `tool/course_cli.py import-csv` 导入 vocab 和 expressions。
   - 运行 `validate` 和 `lint`，确保工具链能发现/修复问题。

3. **生成试点音频**
   - 用 `tool/generate_audio.py` 为试点词/表达生成音频。
   - 更新 `audioAsset` 字段。

4. **写一个试点 lesson**
   - 在 `s-test.json`（或新建 `s-pilot.json`）中写一个仅含试点内容的 mini lesson。
   - 覆盖 intro / practice / listening / review / mastery 链路。
   - 使用真实 Swahili 词，验证所有 template 和 renderer 在真实内容下工作正常。

5. **运行端到端测试**
   - `flutter test` 全量。
   - 手工走一遍试点 lesson：ShowWord → MCQ → FillBlank → ListenAndPick → Mastery。

**验收**：
- 试点词表/表达全部为真实 Swahili，无 Kannada。
- 试点 lesson 能在模拟器/真机上正常完成。
- 音频播放、TTS fallback、判分、复习均正常。
- 试点内容被明确标记为 `pilot`，不面向最终用户（或只在测试渠道出现）。

---

### Phase 17：学习体验深化（2–3 周）

**目标**：让学习者能查、能复习、能坚持。

1. **词典 / 搜索页**
   - 新 route `/dictionary`。
   - 支持按 Swahili term、English translation、tag 搜索 vocab / expression / grammar point。
   - 显示 term、translation、pronunciation、example expression、音频播放按钮。

2. **弱词专项复习**
   - 在 `MistakeProvider` 基础上，统计每个 wordId 的错误率。
   - Play hub 新增 "Weak Words" 卡片，生成 10 题小测。
   - 小测只包含最近 30 天内错 ≥2 次的词。

3. **本地复习提醒**
   - 使用 `flutter_local_notifications`。
   - Settings 页增加 "Daily reminder" 开关与时间选择。
   - 提醒文案温和，例如 "Time for a quick Swahili review"。
   - 无 streak repair、无惩罚，只是提醒。

4. **课程树状态增强**
   - 单元卡片显示：已完成 / 有弱词 / 有到期复习。
   - lesson icon 根据状态变色。

5. **内容更新提示**
   - App 启动时检测内置课程 version 变化。
   - 若 version 升高，弹出说明："课程已更新。是否重置进度？"（保留/重置二选一）。

**验收**：
- 词典页可搜索并播放任意 vocab / expression 音频。
- 本地提醒在设定时间弹出（需真机/模拟器测试）。
- 弱词小测正确聚合错题。

---

### Phase 18：可访问性与性能（1–2 周）

**目标**：让应用对更多设备和用户友好。

1. **可访问性**
   - 所有 icon button 加 `tooltip`。
   - MCQ 选项支持屏幕阅读器朗读。
   - 颜色对比度检查（暗色/亮色主题）。
   - 输入框加语义标签。

2. **性能**
   - 课程树大数据量下的 ListView 优化（若 lesson 数 > 100）。
   - 图片/音频资源懒加载。
   - 减少不必要的 Provider rebuild。

3. **测试补充**
   - 为新增页面写 widget test：DictionaryPage、WeakWordsPage、Settings 提醒开关。
   - 为内容生产 CLI 写 Python 单元测试。

**验收**：
- `flutter test` 新增用例全过。
- 在低端 Android 设备上课程树滚动流畅。

---

### Phase 19：发布流水线与版本策略（1 周）

**目标**：把 future3 的工程成果固定下来，建立可持续发布节奏。

1. **版本号与 tag 策略**
   - 明确语义化版本规则：内容大改升 minor，工程改动升 patch。
   - 准备 `v0.3.0-future3` 发布。

2. **构建脚本**
   - `tool/build_release.py`：自动执行 `flutter pub get`、`build_runner`、`flutter build apk/appbundle/web`、资源校验。
   - 生成带版本号的构建产物。

3. **内容清单报告**
   - 输出 `docs/content_inventory_v0.3.0.md`：
     - 词汇数、表达数、语法点数、lesson 数、音频覆盖率。
     - 已知问题与下一步内容缺口。

4. **应用商店/分发准备**
   - 准备截图（可先用试点内容）。
   - 准备应用描述。

**验收**：
- 一条命令可打出 release APK/AAB。
- 内容清单报告可阅读。

---

### Phase 20：真实 Swahili 词表与表达全量替换（2–3 周）

**目标**：用真实、系统的 Swahili 内容替换全部 Kannada 占位，这是 future3 的"大爆炸"阶段。

> **前置条件**：Phase 13–19 全部完成，CLI、音频管道、模板验证、学习功能、发布流程都已跑通。

1. **导入新词表**
   - 使用 `tool/import-csv` 把 Swahili A1 词表导入为 `vocab.json`。
   - 词表规模建议：A1 核心 300–500 词；总量可控制在 500–800（首期）。

2. **补充 expressions**
   - 常用问候：`Habari / Nzuri / Jambo / Asante / Samahani`
   - 自我介绍：`Mimi ni ... / Jina langu ni ... / Ninafurahi kukutana nawe`
   - 数字 1–20、时间、方向等固定表达。
   - 总量建议 50–100 条。

3. **更新 grammar_points.json**
   - 确保每个 grammar point 的 practiceItems 引用的选项/答案来自真实 Swahili 词表。
   - 修正当前 grammar point 中可能出现的 Kannada 残留（如 `Howdu / Illa`）。

4. **迁移 lesson 中的 wordId**
   - 根据 Phase 13 的映射，批量替换 lesson JSON 中的 `wordId`。
   - 运行 `validateSection` 全量校验，确保无 dangling wordId。

5. **生成全量音频**
   - 用 `tool/generate_audio.py` 为全部 vocab / expressions / listening 条目生成音频。
   - 输出缺失清单，人工补录或保留 TTS fallback。

6. **版本号升级**
   - `vocab.json` version → 2。
   - `expressions.json` version → 2（如需要）。
   - `index.json` version → 4。
   - 触发 seeder 重新加载。

**验收**：
- `vocab.json` 中无任何 Kannada term。
- `expressions.json` 有 ≥50 条真实 Swahili 表达。
- `flutter test` 全量通过。
- `course_cli.py validate` 0 error。
- 手工抽查 5 个 lesson：ShowWord 显示真实 Swahili 词，MCQ 选项合理，音频可播放。

---

### Phase 21：课程 lesson 重写与最终验证（2 周）

**目标**：让真实 Swahili 内容与 6 种 Lesson Template 配合，形成有教学逻辑的课程，并做最终发布。

1. **重写 s-foundations**
   - Greetings 单元：intro + practice + listening + review + mastery 完整链路。
   - Pronouns 单元：intro + practice + reading + mastery。
   - 每个 lesson 的 stage/item 必须覆盖教学目标。

2. **重写 s-daily / s-world**
   - Daily Life：colors、numbers、animals、food。
   - World Around：emotions、nature、travel。
   - 每个 section 至少 2 units，每个 unit 至少 3–4 lessons。

3. **删除或隔离测试内容**
   - `s-test.json` 中的 smoke lesson / pilot lesson 可以：
     - 保留为 `s-framework-test`（不显示在课程树），仅用于 CI 回归；
     - 或完全删除，把测试数据移到 `test/fixtures/`。

4. **模板使用规范**
   - intro：新词汇初次出现，以 ShowWord + MCQ 为主。
   - practice：同词汇多角度练习（FillBlank + ListenAndPick + TypeTheWord）。
   - listening：真实音频 + 听后选择/听写。
   - reading：ReadingPassage + 3 种阅读题。
   - review：混合前面学过的词汇和语法。
   - mastery：单 stage，6–10 题，80% 通过。

5. **最终发布**
   - 发布 `v0.3.0-future3`。
   - 打 tag：`future3-phase-21-done`。
   - 更新 `docs/content_inventory_v0.3.0.md` 为最终状态。

**验收**：
- 每个 section 有 ≥2 units，每个 unit 有 ≥3 lessons。
- 11 种 Interaction 在真实内容中都被用到至少一次。
- 跑一次完整 lesson（从 intro 到 mastery）教学逻辑通顺。
- tag 存在，文档反映最新状态。

---

## 7. 时间表（粗估）

| Phase | 内容 | 估计工时 | 累计 |
|---|---|---|---|
| 13 | 内容审计与迁移映射 | 1 周 | 1 周 |
| 14 | 内容生产 CLI | 2 周 | 3 周 |
| 15 | 音频策略与管道 | 2–3 周 | 5–6 周 |
| 16 | 试点内容种子（10–15 词 + 5–10 表达） | 1 周 | 6–7 周 |
| 17 | 学习体验深化 | 2–3 周 | 8–10 周 |
| 18 | 可访问性与性能 | 1–2 周 | 9–12 周 |
| 19 | 发布流水线与版本策略 | 1 周 | 10–13 周 |
| 20 | 真实 Swahili 词表与表达全量替换 | 2–3 周 | 12–16 周 |
| 21 | 课程 lesson 重写与最终验证 | 2 周 | 14–18 周 |

**总计约 3.5–4.5 个月**（一人全职），内容生产集中在最后两阶段，前面先把工具和流程打扎实。

---

## 8. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 真实 Swahili 词表质量参差不齐 | 使用多个开源来源交叉验证；建立内容审核 checklist |
| 替换 Kannada 词汇后旧用户进度语义混乱 | Phase 13 明确迁移策略；重置或保留都有用户提示 |
| TTS 生成的 Swahili 音频质量差 | Phase 15 先用 Piper 评估；Phase 16 用试点内容验证；质量不达标则改用真人录音或混合策略 |
| 内容作者不习惯 CSV/JSON 工作流 | Phase 14 提供模板、示例、文档；CLI 输出清晰错误信息 |
| 课程数据变大后 APK 体积膨胀 | 按 section 拆分 asset bundle；支持按需下载/更新（仍本地存储） |
| 新增功能破坏现有测试 | 每 Phase 结束必须 `flutter test` 全量；新增测试覆盖新功能 |
| 全量替换一次性改动过大 | 用 Phase 16 试点先行；全量替换前必须 CLI/音频/模板全部验证通过 |

---

## 9. 决策记录（ADR）清单

future3 期间需要补充的 ADR：

1. `docs/decisions/0002-content-replacement-progress-policy.md` — 内容替换时用户进度如何处理。
2. `docs/decisions/0003-audio-generation-strategy.md` — 音频生成方案选择。
3. `docs/decisions/0004-content-contribution-workflow.md` — CSV/JSON 贡献流程与审核规范。
4. `docs/decisions/0005-local-notification-policy.md` — 本地提醒的频率、文案、关闭选项。

---

## 10. 与当前未提交改动的关系

当前工作区有若干未提交文件（`settings_provider.dart`、`audio_module.dart`、`about_varnamala_page.dart`、大改的 `settings_page.dart` 等），它们不在 future2.md 范围内，但与 future3 Phase 17（Settings 扩展、音频）部分相关。

**建议**：
- 这些改动应作为 future3 的"预研/前置补丁"，先单独 review 并提交。
- 提交后把 future3 Phase 17 的 Settings 扩展工作基于这些改动继续。
- 不要让未提交改动与未来3 的大范围内容替换混在一起，否则难以 review。

---

## 11. 成功标准（future3 完成时）

- [x] `tool/course_cli.py` 可用：validate / import-csv / export-csv / lint / audio-manifest / diff。
- [x] 音频生成管道可批量产出 Swahili 音频，并有 fallback TTS。
- [ ] 试点 lesson（10–15 真实 Swahili 词 + 5–10 表达）能端到端跑通所有 template。
- [ ] 词典页、弱词复习、本地提醒可用。
- [ ] `vocab.json` 全部为真实 Swahili 词，无 Kannada 占位。
- [ ] `expressions.json` 有 ≥50 条真实 Swahili 表达。
- [ ] 所有面向用户的 section/lesson 都有真实、通顺的教学内容。
- [ ] ≥80% 的 A1 词汇有离线音频。
- [ ] 听力 lesson 能正常播放并判分。
- [ ] `flutter test` 全量通过，`flutter analyze` 0 error。
- [ ] 应用有可用版本的 tag 和发布说明。

---

## 12. 更远的未来（不在 future3 范围）

- **真实 Swahili B1/B2 内容扩展**。
- **其他非洲语言课程**（复用同一框架）。
- **更丰富的内容形式**：故事、对话、文化注释。
- **可选的云同步**（端到端加密、用户自持密钥）—— 仅当本地多设备需求强烈时才考虑。
- **社区贡献的音频录制平台**（仍本地优先，通过应用更新分发）。

---

*本文档是 future2.md 的下一章。核心原则不变：单人、本地、纯净、无社交摩擦。变化的是：从"不做内容"转向"可持续地生产高质量内容"。*
