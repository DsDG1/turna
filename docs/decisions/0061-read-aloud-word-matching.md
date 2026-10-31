# ADR 0061 — 跟读识别（readAloud）：采用词面匹配，音素级发音评分维持不做

> 日期：2026-10-30 ｜ 状态：已接受（实现随同批提交）
>
> 关联：[ADR 0028](./0028-fsrs-continuous-memory-model.md)（课时练习二元评分）、
> [ADR 0047](./0047-ohos-companion-lite-build.md)（伴生版范围与降级机制）、
> [ADR 0056](./0056-ohos-remove-ai-compliance.md)（`OhosDegradation` 的先例用法）、
> `docs/project-guide.md` §15（原「不做口语录音匹配」条目，本决策将其收窄）。

## 背景

「读一下、识别读得怎么样」——学习者看着句子朗读，应用判断读得如何。这是白板
「主动开口」课型（看图说话、跟着语音回应，标注「课型还没有，要新建」）的核心
能力缺口。

project-guide §15 原条目把「口语录音匹配」整体列为不做，理由是「自动语音评分在
非主流语种（含土耳其语）上可靠性和效度不足」。2026-10 逐家核实后，这条理由
**对音素级那一档成立，对词面匹配那一档不成立**——原结论比证据宽了一档：

| 档 | 回答的问题 | 2026-10 可买性 |
|---|---|---|
| 词面匹配 | 哪些词读出来了、哪些没读出 | ✅ Whisper 级模型处理土耳其语相当可靠，平台 ASR（Google / Apple）直接可用 |
| 音素级评分 | 每个音发得准不准（ELSA 型） | ❌ [Azure 发音评估不支持 tr-TR](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/language-support)；sherpa-onnx 的发音评分组件只有中文音节级 zipformer CTC 模型，土耳其语连官方 ASR 预训练模型都没有（社区转码器模型做不了音素对齐）；鸿蒙 Core Speech Kit 识别面向中文 |

## 决策

**采用词面匹配档，Android / iOS only；音素级发音评分维持不做（§15 条目收窄，
理由原文保留给该档）。**

1. **题型**：`Interaction.readAloud`（`runtimeType: "readAloud"`，必填
   `targetText`）。示范音不占 `audioAsset`——直接走现有 TTS 路径朗读
   `targetText`，普通课最能扛设备 TTS 的音质瑕疵（媒体纪律不变）。
2. **识别**：`ReadAloudBackend` 缝（`lib/service/read_aloud_backend.dart`）包
   `speech_to_text` 7.5（平台 SpeechRecognizer / SFSpeechRecognizer），locale
   取课程目标语。纯新增依赖，不进 `dependency_overrides`。
3. **打分**：纯函数 `lib/core/read_aloud_scoring.dart`——`foldTurkish`
   折叠（复用 `turkish_text.dart`）→ 去标点分词 → 保序 DP 对齐 → 匹配比例。
   词匹配容忍两类近失：前后缀扩展（`merhaba` ↔ `merhabalar`，土耳其语黏着）
   与长词单编辑距离（`ışık` ↔ `isik`）；填充词（「yani」）不破坏对齐也不扣分。
4. **二元评分**：比例 ≥ 0.6（`kReadAloudPassRatio`）→ pass，走 ADR 0028 的
   现有 pass/fail 管线（FSRS、错题本、统计）。逐词反馈只是展示，不新增评分
   档。识别失败（没说话 / 没听清）不算作答，可重点麦克风；权限被拒或无识别
   服务降级为听示范卡（`listenOnly` 的 always-correct 先例），不阻塞进度。
5. **隐私与开关**：平台识别服务可能云端处理音频，不承诺本地——设置页文案与
   iOS 权限描述同口径写明。主开关 `readAloudExercisesEnabled` **默认关**
   （opt-in，同 `ttsFeatureEnabled` 先例；`resetLearningDefaults` 不碰它），
   降级卡上提供课内一键开。`ensureReady` 触发系统权限弹窗，只在用户点麦克风
   时调用，启动时不探测。
6. **平台档位**：`OhosDegradation.readAloud`——伴生版上跟读题降级为听示范卡
   （`speech_to_text` 无 OHOS 实现，Core Speech Kit 不支持土耳其语）。Web 同样
   降级。工厂 `createReadAloudBackend()` 在这些平台返回
   `UnavailableReadAloudBackend`，永不触碰插件的 platform channel。
7. **口径纪律**：用户文案写「没听到这个词」，不写「发音错误」——词面匹配测的
   是可懂度（intelligibility），不是口音；TTS 侧继续叫「智能朗读」，本功能中文
   一律叫「跟读」，避免与既有 read-aloud（TTS）术语混淆。

## 待验证（真机）

- iOS `SFSpeechRecognizer` 的 tr-TR 识别质量（安卓 Google 识别已知良好）；
- 0.6 阈值与两类容差在真实录音分布下的体感，上线后按课内答题记录调参；
- Android 无 Google 识别服务的设备：`initialize()` 返回 false，走降级路径
  （已由测试覆盖，真机待验）。

## 不做的事（本决策边界）

- 音素级发音评分 / 发音位反馈——无土耳其语供应商，自训 CTC 声学模型远超范围；
- 每题重试——框架无 per-item retry，错即记错走 GOT IT，与其他题型一致；
- 云端 ASR / 多模态 LLM 定性反馈——等词面档在安卓上验证学习者真的用再议；
- AI 练习生成白名单不加 readAloud（生成物无需音频，但先保守）。
