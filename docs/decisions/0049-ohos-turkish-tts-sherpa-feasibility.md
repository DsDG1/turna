# ADR 0049 — 土耳其语 TTS：sherpa-onnx 构建可行性记录（运行与实施仍待验证）

- 状态：**已实施并真机验收**（2026-10-07；此前为部分接受）
- 日期：2026-10-04
- 核验订正：2026-10-05（订正对 ADR 0048 的引用；未重跑 sherpa 构建、模型加载或许可核验）
- **实施与验收：2026-10-07**（见下方「2026-10-07 实施与真机验收」）
- 关联：[ADR 0048](./0048-ohos-companion-audio-tts.md)（本 ADR 是它「候选后续」一段的展开）
- 编号说明：0048 之后的下一个可用编号。

## 背景

[ADR 0048](./0048-ohos-companion-audio-tts.md) 的 2026-10-04 历史记录没有匹配到 `tr`，据此开展了 sherpa-onnx 的构建可行性调查。**2026-10-05 订正**：engine / namespace 的 `listVoices` 不能仅按接口位置解释为已安装／可下载，当前插件还丢弃了 `VoiceInfo.status`；本次没有真机返回值，不能继续断言 CoreSpeechKit 路线下土耳其语无解。当前内置土耳其语词表也没有词条录音引用，「由课程自带录音承担」的前提不成立。当前证据见 ADR 0048 的「2026-10-05 核验结果」小节。

本 ADR 保留当时 HAR 安装、声明解析、原生库进包与包体 A/B 的历史记录；这些记录不证明模型能在设备上运行或出声，也不作为当前依赖版本与包体的现场核验。

**先校准目标函数**（这条决定了整份评估的取向）：Android 侧基线是 **Google TTS，机器合成**，不是人声录音。所以「要不要引入一个 2021 年的单说话人 VITS 声音」不是质量问题，而是**工程成本问题**。本 ADR 因此不评价音质，只算成本与风险。

## 历史构建观测（2026-10-04，本机，签名态，同条件 A/B）

| 项 | 观测 |
|---|---|
| `ohpm install sherpa_onnx@1.13.3` | **历史记录为成功**。当时 registry `latest` 为 1.13.3；示例 pin 的 **1.13.8 在当次 ohpm 请求中返回 404**，因此当次探针使用 1.13.3。实施前应重新核验可用版本，不将历史 registry 结果写成永久限制 |
| ArkTS 声明解析 | **成功**。`import { OfflineTts, OfflineTtsConfig, OfflineTtsModelConfig, OfflineTtsVitsModelConfig } from 'sherpa_onnx'` 在本工程 API 26 编译通过 |
| 原生库进包 | **成功**。hap 内 `libs/arm64-v8a/` 与 `libs/x86_64/` 各 4 个 |
| hap 体积（同条件 A/B） | 无依赖 **39,632 KB（38.70 MB）** → 加依赖 **79,087 KB（77.23 MB）**，**增量 39,455 KB ≈ 38.53 MB** |
| 无需交叉编译 / 自写 NAPI | **确认**。HAR 已含 ArkTS 绑定与四个 `.so`，本工程只写调用代码 |

### 两条与文档不符、只能靠实测发现的 API 事实

1. **`numThreads` / `debug` / `provider` 在 `OfflineTtsModelConfig` 上，不在 `OfflineTtsConfig` 上**。`OfflineTtsConfig` 只有 `model` / `ruleFsts` / `ruleFars` / `maxNumSentences` / `silenceScale`。按文档示例（C / C++ / Python / Rust 各语言示例都把 `num_threads` 写在 model 层）写是对的，但 ArkTS 侧的 `Index.ets` 导出类型名相近（`OfflineTtsConfig` 与 `OfflineTtsModelConfig`），照着 C 示例的层级直觉写会编译失败——本 spike 第一次编译就是 `Property 'numThreads' does not exist on type 'OfflineTtsVitsModelConfig'`。
2. **x86_64 那套也会被打进 hap**（14,660 + 4,208 + 763 + 1,264 KB）。本工程只发 arm64，但 HAR 的 `build-profile.json5` 声明了两个 ABI 且无人过滤，故 x86_64 的 20.4 MB 是**纯浪费**。若实施，应在打包配置里限定 ABI，可省下约 20.4 MB。

## 尚未验证的部分（**实施前必须补，且都需要真机**）

| 项 | 状态 |
|---|---|
| 真机加载 tr 模型并出声 | **未验证**。spike 只做到编译期链接，刻意没有实例化引擎（无模型在手，失败也无法区分是绑定坏了还是模型缺失） |
| 首个词的合成延迟 / RTF | **未验证**。HAR 内有 RTF 计算代码，官方只给了树莓派 4B 的参考值，**手机上的数字没有** |
| 非 rawfile 路径能否加载模型 | **未验证**。官方示例只演示了把模型放进 `rawfile`；而 `rawfile` 进 hap 就是「内置」路线。若要走「首次使用下载」，必须先证实可传沙盒绝对路径 |
| 该声音的许可条款 | **未核实**。sherpa-onnx 自身 Apache-2.0（已核实），但 `tr_TR-dfki` 声音来自 `rhasspy/piper-voices`，其 MODEL_CARD 在 huggingface.co 上，**本机网络不可达**。模型压缩包内自带 `LICENSE`，实施时必须打开读，不能默认可商用 |

## 历史成本估算（2026-10-04，实施前需重新清点）

以下数字仅保留当时的记录和估算；本次未重新取得模型、核对依赖或复算 A/B，不能作为当前安装包的大小或实施报价。

模型侧（`vits-piper-tr_TR-dfki-medium`，1 说话人 / 22050 Hz）：

- int8 模型 18.7 MB + `tokens.txt` 921 B
- **`espeak-ng-data` 17.16 MB（323 个文件）在运行时强制存在** —— Piper VITS 靠它做音素化，缺了就发不出声
- int8 整目录 35.0 MB，tar.gz 归档 21.1 MB
- fp32 模型 63.2 MB（不建议）

两条投递路线：

| 路线 | hap 体积 | 代价 |
|---|---|---|
| **内置**（模型 + espeak 一并进 hap，且限定 arm64） | 38.70 + 18.2 + 35 ≈ **92 MB** | 无下载、无失败模式、离线即用；包体涨到 2.4 倍 |
| **首次使用下载** | **77.23 MB** | 需新增下载器 + 校验 + 断点续传 + 镜像（GitHub 直连在本机常被重置）；且**依赖上面那条未验证的沙盒路径** |

## 决策

**本批不做实施。** 三条理由，按权重：

1. **无真机**，而剩下的每一项未知（延迟、RTF、沙盒路径、真机出声）都需要真机。现在实施等于交付一个无法验收的东西。
2. **能力与兜底仍需验证**：先按 ADR 0048 重新核验当前设备的语音状态、初始化与实际发音。若目标语言不可用，当前内置词表没有词条录音可兜底，应再决策是否引入 sherpa 或补齐内容音频；不能将 CoreSpeechKit 已能朗读 zh / en、或土耳其语已有录音保障写成已验收前提。
3. **许可未核实**。这是可以在有网络时十分钟关掉的问题，但不该在没关掉之前写代码。

因此把它记为**待续的 P2**，并把实施前的必做项列死（见下），避免下次接手时重新调研。

## 2026-10-07 实施与真机验收

真机：HUAWEI Mate 40 Pro（**CMM-AL10**）/ OpenHarmony 7.0.0.109 / **API 26**。运行时 `sherpa_onnx@1.13.3`（ohpm registry 当前 `latest`，Apache-2.0，共 58 个版本）。模型 `vits-piper-tr_TR-dfki-medium-int8`（int8 权重 17.82 MB + `espeak-ng-data` 355 文件 / 17.16 MB，22050 Hz 单说话人）。

### 前提订正：CoreSpeechKit 不是「土耳其语缺音色」，是全平台不出声

`listVoices` 的真实返回（本机）：

| 音色 | status |
|---|---|
| `zh_CN person=13` | `INSTALLED` |
| `zh_CN person=21` | `GA` |
| `en_US person=8` | `GA` |

三条都写进日志后才看清两件事：

1. **`PERSON_CANDIDATES = [0..7]` 全是无效 id**，设备真实 id 是 13 / 21 / 8。所以历史上 `en-US/0..7` 全部 `1002300003 person not support` **不是「英语不支持」，而是 id 全错**；而 `zh-CN person 0` 被「接受」后是个空引擎，每句 ~44 ms 静默完成。**这条错误结论在仓库里存在了三轮。**
2. 即使用设备自称 `INSTALLED` 的 `zh_CN person=13` 朗读，中文**仍然没有声音**。`speak` 返回 true、`onStart` 触发、`onComplete` 在 ~44 ms 后触发两次、`onError` **一次都不出现**。因此 CoreSpeechKit 在这台设备上对**任何语言**都不出声，已退出候选 —— sherpa 不是土耳其语补丁，是伴生版唯一朗读路径。

### 本 ADR 三条「未验证」项的结论

| 项 | 结论 |
|---|---|
| 真机加载 tr 模型并出声 | **通过**。模型加载 1256 ms（含首次暂存 358 文件），单句合成 185 ms；**用户确认听到启动时段的「merhaba」以及课程内、语音来源两处朗读** |
| 首词延迟 / RTF | 部分。首句（含暂存）~2.8 s；稳态单句 185 ms。RTF 未单独测 |
| 非 rawfile 路径能否加载模型 | **通过**，且这是唯一可行路线，见下 |
| 该声音的许可条款 | **CC BY-NC-SA 4.0**（数据集 `marytts/dfki-ot-data`）。仓库外壳的 `mit` 压不住数据集许可。项目决定接受 NC，全开源免费，不作商业发布 |

### 「内置 rawfile」路线必须平铺，这是本批最硬的一条平台约束

`resourceManager` **只有** `getRawFd` / `getRawFileContentSync`，**没有 `getRawFilePath`，也没有 rawfile 目录枚举**。而 sherpa 要的是**文件路径**，`espeak-ng-data` 更是**目录**。所以 rawfile 里的模型无法直接喂给 sherpa，只能先落成真实文件。

平铺期间实测到两条会静默失败或直接报错的约束：

- **嵌套 rawfile 路径读不到。** 同目录 118 个条目全部读得出，第一个嵌套路径 `…/espeak-ng-data/lang/aav/vi` 即 `13900002 No such file or directory`——而文件确实在 hap 内（355/355 已核对）。故 hap 内改为 `espeak-flat/f0001…f0355`，目标路径写在随模型走的 `stage-manifest.tsv` 里，暂存时再还原目录结构。
- **清单里的目标路径必须带 `espeak-ng-data/` 前缀。** 漏掉时 355 个文件全落在模型根目录、该目录从未被创建，表现为 `Rule far does not exist`。

### 静默失败清单（本批全部形态一致：失败不报错）

| 症状 | 根因 | 怎么发现的 |
|---|---|---|
| `Please check your config!` | piper 的 espeak-ng-data 挂在 **`vits.dataDir`**，被挂到了 `OfflineTtsConfig.ruleFars`（后者是 FST 文本规范化规则集，另一种东西） | **`model.debug = true`** 后引擎自己说出 `'…/phontab' does not exist. Please check --vits-data-dir` |
| 进程反复重启、无任何日志 | 355 次同步读+写在 MethodChannel 处理器里占满平台线程，被系统杀掉 | 按 pid 连续抓日志看 pid 变化 |
| 「模型完整」但加载即崩 | 完整性校验只数文件数，发现不了被截断的 17.8 MB 权重 | 改为清单携带期望字节数、逐个 `statSync` 比对 |
| `copy failed at af_dict: 9001005` | 清单存的是平铺文件名，读取路径漏了 `espeak-flat/` 一段 | 核对 hap 内实际条目名 |
| 白屏、`ohos was not recognized as a target platform` | **不是代码问题**：用 PATH 上的 stock `dart` 跑 `build_runner`，把 `.dart_tool/package_config.json` 的 `flutter` 指向官方 SDK | 见下「工具链陷阱」 |

### 工具链陷阱：codegen 必须用 OHOS fork SDK

改 `@module` 签名后需要 `build_runner`。用 PATH 上的 `dart` 执行会把包配置指向 stock Flutter，编出的框架不认识 `TargetPlatform.ohos`，**启动即 `⛔ Uncaught platform error` 白屏**——失败的样子与 codegen 毫无关系。正确做法：`<fork>/bin/flutter.bat pub get` 恢复指向后再构建。本条建议写入 AGENTS.md 的踩坑记录。

### 对本文历史结论的订正

- **ABI 限制假设不成立。** `externalNativeOptions.abiFilters` 只约束本工程**自编译**的 native 代码，**不过滤 HAR 自带的预编译 `.so`**；x86_64 那 20.4 MB 仍在包内，且构建不报错。ADR 0047 曾记过的「172.94 MB」实为 **debug** 包体积，release 基线 38.70 MB 才是 A/B 可比的那个。
- 「沙盒路径未验证」已由本次实施消解：拷贝进 `filesDir` 后 sherpa 正常加载。
- `sherpa_onnx` 的配置类**必须构造、不能用对象字面量**（ArkTS 要求对象字面量满足全部已声明字段，`OfflineTtsModelConfig` 因此要补齐 7 个用不到的模型族）；`generate` 收 `TtsInput` 而非 `(text, sid, config)`；`numThreads` / `debug` / `provider` 在 `OfflineTtsModelConfig` 上。

### 形态（与「若实施，形态应当是」一节对照）

- 保留 `SpeechBackend` 接缝，新增 `SherpaSpeechBackend` 作为伴生版**主**实现（`createSpeechBackend()` 在 OHOS 分支直接选它；拿不到 speaker 时抛错而非退回已知不出声的 CoreSpeechKit）
- 合成出的 WAV 交给**已注册的** speech `AudioBackend` 播放，不另建播放器（否则两个播放器会互相打断）
- `availableLanguages()` 如实报 `['tr']`，不假装有英语音色
- 通道名双端一致、`AudioController` 不直连插件等既有门禁形状沿用
- `model.debug` 交付态为 `false`，但它是定位「配置错误」最有价值的一个开关，理由留在源码注释里

## 形态：实施时采纳的接缝形状

- 保留 `SpeechBackend` 接缝，新增实现的选择与回退根据实际语音状态、初始化和发音结果决定。CoreSpeechKit 的列表查询失败、状态未知与目标语言不可用需区分，不能仅凭历史列表启用或排除 sherpa。
- 复用 ADR 0048 已建的接缝与门禁形状：通道名双端一致断言、`AudioController` 不得直连插件、伴生版文案不得出现商店语义。
- **未采纳**：限定 arm64 ABI 省 20.4 MB。实测 `abiFilters` 不作用于 HAR 预编译 `.so`（见上），且项目决定不处理包体。
- **未采纳**：`generateAsync` 配 `sourceOption.workers`。当前合成走同步 `generate`，单句 185 ms 未观察到 UI 卡顿；此条留待实测有卡顿时再启用。
- 语音速控：sherpa 的 `speed` 与 UI 倍率同形（1.0 为正常），故换算取恒等而非第二套标尺，仍集中在后端内。

## 实施前的必做项（2026-10-07 已全部结清）

1. ~~核对该声音模型的 `LICENSE`~~ → **CC BY-NC-SA 4.0**，项目决定接受（全开源免费，不作商业发布）。
2. ~~把 ABI 限制写成门禁~~ → **未采纳**：`abiFilters` 对 HAR 预编译 `.so` 无效，项目决定不处理包体。
3. ~~取得真机，实测沙盒路径加载 / 首词延迟 / RTF / 真机出声~~ → **全部通过**，见上。
4. 据 3 的结果在「内置 / 下载」之间定案 → **内置**（平铺 rawfile + 首次暂存），理由已写在上。
5. 补 ADR 0048 的「候选后续」一段，指向本文并标记已实施 → 见下。

## 顺带订正的一处事实

2026-10-04 的原文记录：[ADR 0048](./0048-ohos-companion-audio-tts.md) 旧版与 `test/BASELINE.md` 2026-10-04「伴生版音频与 TTS：三个静默缺陷 + 一条『平台侧无解』的确证」条目早前引用的 **172.94 MB 不可复现**；当次签名态、干净重解析依赖后的 A/B 基线为 **38.70 MB**，增量为 **38.53 MB**。差异原因当时未查明，历史记录保留。

**2026-10-05 订正**：上述数字只适用当次 A/B，不描述当前产物；ADR 0048 已按本次检查的 HAP 大小、修改时间与 SHA-256 更新证据。测试收据的语音能力与录音兜底判断另见 `test/BASELINE.md` 2026-10-05「鸿蒙音频文档核验与历史结论订正」条目。
