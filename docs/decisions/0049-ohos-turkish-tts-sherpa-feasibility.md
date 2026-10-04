# ADR 0049 — 土耳其语 TTS：sherpa-onnx 可行性实测（**结论：可行但本批不做**，留待有真机时续）

- 状态：部分接受（可行性已实测通过；**实施决策推迟**到有真机可测时）
- 日期：2026-10-04
- 关联：[ADR 0048](./0048-ohos-companion-audio-tts.md)（本 ADR 是它「候选后续」一段的展开）
- 编号说明：0048 之后的下一个可用编号。

## 背景

[ADR 0048](./0048-ohos-companion-audio-tts.md) 在 Mate 90 Pro Max / API 26 上确证：`listVoices` 的**已装集合与可下载集合都不含 `tr`**，故 CoreSpeechKit 路线下土耳其语无解，由课程自带录音承担。当时留了一个候选：sherpa-onnx 有官方预编译 HAR 且有土耳其语声音。本 ADR 把它从「候选」推进到「实测过」，以便后续决策不必重做调研。

**先校准目标函数**（这条决定了整份评估的取向）：Android 侧基线是 **Google TTS，机器合成**，不是人声录音。所以「要不要引入一个 2021 年的单说话人 VITS 声音」不是质量问题，而是**工程成本问题**。本 ADR 因此不评价音质，只算成本与风险。

## 实测结论（本机，签名态，同条件 A/B）

| 项 | 观测 |
|---|---|
| `ohpm install sherpa_onnx@1.13.3` | **成功**。registry `latest` 即 1.13.3；官方示例 pin 的 **1.13.8 在 ohpm 上 404**（下载 `sherpa_onnx-1.13.8.har` 返回 404），故版本必须锁 1.13.3 |
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

## 成本（决策用，均为实测或已核实的数字）

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
2. **与既有结论不冲突**：ADR 0048 已确立「土耳其语由课程自带录音承担」，该结论在有真机前不会被推翻。sherpa 是**增量**，不是替代——CoreSpeechKit 继续负责 zh / en（零字节、零依赖）。
3. **许可未核实**。这是可以在有网络时十分钟关掉的问题，但不该在没关掉之前写代码。

因此把它记为**待续的 P2**，并把实施前的必做项列死（见下），避免下次接手时重新调研。

## 若实施，形态应当是

- **不替换** `OhosSpeechBackend`，而是新增第三个实现（`SherpaSpeechBackend`）挂在**同一个** `SpeechBackend` 接口后面。CoreSpeechKit 仍是首选，sherpa 只在「设备没有目标语言语音」时兜底。
- 复用 ADR 0048 已建的接缝与门禁形状：通道名双端一致断言、`AudioController` 不得直连插件、伴生版文案不得出现商店语义。
- 限定 arm64 ABI（省 20.4 MB），且把该限制写成断言，否则会静默回退成两套都打进去。
- 语音速控：sherpa 用 `GenerationConfig.speed`，与 `flutter_tts` 的 rate 不是同一量纲，**换算必须是 Dart 纯函数**（同 ADR 0048 的 rate 换算），不能散在 ArkTS 里。
- `generateAsync` 需配 `sourceOption.workers`，否则阻塞 UI 线程。

## 实施前的必做项（按顺序，前两项无网络也能做）

1. 核对该声音模型的 `LICENSE`（在模型压缩包内），确认可商用。
2. 把 ABI 限制写成门禁（先红后绿：临时去掉限制即失败）。
3. 取得真机，实测：模型能否从沙盒绝对路径加载；首词延迟与 RTF；真机出声。
4. 据 3 的结果在「内置 / 下载」之间定案，并写下理由。
5. 补 ADR 0048 的「候选后续」一段，指向本文并标记已实施。

## 顺带订正的一处事实

本 ADR 顺带发现 [ADR 0048](./0048-ohos-companion-audio-tts.md) 与 `test/BASELINE.md` 2026-10-04 音频条目引用的 hap 体积 **172.94 MB 不可复现**：同一份源码在签名态、干净重解析依赖后实测为 **38.70 MB**，且与 W4 / W5 条目记录的 172.7 MB 差约 95 MB。原因**未查明，不猜**（已排除「手动 `ohpm install` 触发 prune 删掉 ABI 模块」这一假设——清空 `oh_modules` 与 lock 后重新解析，结果不变且仍只有 arm64）。**以 38.70 MB 为准**，38.53 MB 的 A/B 增量是在该基线上测得，故不受影响。
