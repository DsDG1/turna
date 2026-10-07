# ADR 0048 — OHOS 伴生版音频播放与 TTS 交付（原生通道，不 fork 依赖）

- 状态：**音效已修复并真机验收；CoreSpeechKit 已判定不可用，改由 sherpa-onnx 承担朗读**（2026-10-07）
- 日期：2026-10-04
- 核验订正：2026-10-05（`ohos/anki-core-probe` 工作区；包含核验前已有的未提交音频改动）
- **真机结论：2026-10-07**（见文末「2026-10-07 真机验收」）
- 关联：[ADR 0047](./0047-ohos-companion-lite-build.md)（§2.3 显式降级条件、§5.5 override ratchet）、[ADR 0041](./0041-ohos-product-eol.md)
- 编号说明：0047 之后的下一个可用编号。

## 背景

伴生版采用独立的原生音频与 TTS 通道，保留 Android / iOS 的既有后端：

1. 当前伴生版没有注册 `audioplayers` / `flutter_tts` 的 OHOS 插件；由 `EntryAbility.configureFlutterEngine` 注册 Turna 自维护的 `AudioPlugin` / `TtsPlugin`。
2. ADR 0047 §5.5 与架构门禁禁止 override 这两个包。本 ADR 保留该约束。
3. 原文将 `InitializationSettings` 的公开 API 分叉归到 `flutter_tts`，应撤回；ADR 0047 §7.3 的该例属于 `flutter_local_notifications`，不能用作所有 TTS 移植路线均不可行的证据。

自维护 ArkTS 通道沿用仓库内 `RdbPlugin` / `FilePickerPlugin` 的接线方式。通道与接口存在，不等同于播放能力已通过真机验收。

**目标**：支持机器合成朗读与已有媒体文件播放。课程录音可作为内容来源，但必须核实内容确实提供并打包了录音，不能将其写成默认存在的兜底。

## 决策

### 1. Dart 接缝 + 手写 ArkTS 插件，零 override

- `lib/service/audio_backend.dart`：`AudioSlot`（`effects` / `speech`，**保留原双槽语义**）、`AudioBackend`、`AudioplayersAudioBackend`（Android / iOS）、`OhosAudioBackend`、`createAudioBackends()`。
- `lib/service/speech_backend.dart`：`SpeechBackend`、`FlutterTtsSpeechBackend`（Android / iOS）、`OhosSpeechBackend`、`mapFlutterTtsRateToPercent`。
- `SpeechBackend` 必须是**共享单例**：它携带已绑定的 locale 与 rate，多实例会让「可用性检查」和「真正朗读」对不上同一个引擎状态。
- 页面通过 `AudioController` 播放；音频后端由 `AudioModule` 装配，TTS 可用性检查也通过共享的 `SpeechBackend` 消费平台能力。
- 通道名两端各写一份字面量（`me.dsdogs.turna/audio`、`me.dsdogs.turna/tts`），由门禁断言**双端一致**——这是真实踩过的坑：RDB 通道名对不上时，平台消息无人应答，表现为**白屏**而非报错（W4 真因①）。

**工厂闭包而非直接构造**：接收 `AudioPlayer` 工厂闭包的是 `createAudioBackends()`；`OhosAudioBackend` 接收 `slot` 和可选 `MethodChannel`。平台选择发生在调用工厂之前，避免伴生版构造没有对应插件的 `AudioPlayer`。原文将工厂参数归给 `OhosAudioBackend`，与当前签名不符。

### 2. 当前资产投递：Flutter bundle → 缓存文件 → 文件描述符

当前 `OhosAudioBackend.playAsset` 的主路径：

```text
rootBundle.load('assets/…')
→ base64 → stageBytes → cacheDir/turna_audio/<name>
→ playFile → fs.openSync → createMediaSourceWithFd
→ createAVPlayer(callback) → setMediaSource → prepare → getTrackDescription → play
```

`AudioPlugin.playUrl` 优先使用缓存文件的 fd；仅创建 fd 媒体源失败时回退到 `file://` URL。缓存文件 fd 与 HAP rawfile fd 是不同来源，不能继续用「不用文件描述符」描述当前实现。原生 `playAsset` / `assetPath` 的 rawfile 读取分支仍存在，但已不是 Dart 的 bundled asset 主路径。

当前每次播放新建 AVPlayer，不复用 `reset()`。**「播完 release」是未实现的资源管理目标**：代码没有播放完成的状态监听，`stopSlot` 也只停止、不释放旧播放器。文件句柄应覆盖实际播放周期，停止与释放的顺序、并发切换均需验证，不能将资源管理写成已完成。

### 3. TTS：CoreSpeechKit，参数靠探测而非假设

- `TtsPlugin.probeEngine` 当前按 `PERSON_CANDIDATES` 与语言候选初始化离线引擎，命中后缓存语言和 person。候选集合是否覆盖当前设备的有效音色、每个组合能否出声，尚未真机复验；历史 person 报错不作为当前设备能力结论。
- `TtsPlugin.voices` 查询 namespace 的在线／离线列表，并查询 engine 的离线列表，回包保持 `installed` / `supported` 两个键。这是**现有通道协议**；键名不证明安装状态。本机 SDK 将两个 `listVoices` 都描述为查询支持的语种音色，`VoiceInfo` 另有 `status`。当前 `toVoiceEntry` 只保留 language / person，丢弃 status，原文「engine 只报已装、namespace 报可下载」缺少依据，撤回。
- `OhosSpeechBackend.mapFlutterTtsRateToPercent` 保留当前纯函数换算；该换算与 `SpeakParams.extraParams` 中 `rate` 的平台语义、实际语速尚未验证。纯函数单测通过不能证明平台接受该字段或按预期发音。
- 当前 `OhosDegradation` 不列音频／TTS，表示伴生版已接入对应实现，**不表示真机出声或所有语言均已验收**。`TtsPlugin.speak` 在请求被接受后返回成功，后续 `onError` 只记原生日志，Dart 侧成功结果不能证明合成完成。

## 历史设备记录（2026-10-04，未在本次核验中复现）

原文记录设备为 HUAWEI Mate 90 Pro Max / API 26 / HarmonyOS 7.0.0.109。以下保留历史观测，**本次没有连接设备，未重新获取原始返回值，也未确认当前安装包**。这些记录不能推广为全部鸿蒙设备的限制，也不能直接解释当前版本无声。

| 观测 | 结果 |
|---|---|
| `createEngine(zh-CN, person 0)` | **成功** |
| `createEngine(en-US, person 0)` | 失败 `1002300003 … person not support!` |
| `createEngine(tr)` | 失败 `1002300002 … language not support!` |
| engine `listVoices`（原文标为「已装」） | 原文记录 `[zh_CN, en_US]`；安装状态解释撤回 |
| namespace `listVoices`（原文标为「可下载」） | 原文记录 online 0 ∪ 1 为 `[zh_CN, en_US]`；可下载集合解释撤回 |
| 资产路径漏 `assets/` 段 | `9001005 GetRawFileContent failed`，8 个音效**全部静音** |
| `createAVPlayer()` 的 promise 重载 | 返回 `undefined` → `Cannot read property then of undefined` |
| OHOS 上构造 `AudioPlayer` | `MissingPluginException(No implementation found for method init …)`，从 DI getter 抛出为 uncaught |

`TtsAvailabilityChecker._resolveHarmonyOsLanguage` 当前保留精确匹配与 `-` / `_` 分隔的基础子标签匹配。它只验证返回标签的匹配，不能证明目标语音可合成或可播放。本机媒体 SDK 声明了 Callback 与 Promise 两种 `createAVPlayer` 重载；历史 `undefined` 观测需要设备复现，不能据此断言当前系统的 Promise 重载必然失效。

## 土耳其语：当前内容路径与待验证能力

原文「平台侧没有土耳其语，下载也拿不到」的确定性判断撤回。本次没有真机语音查询、初始化、下载或朗读结果，不能判断当前设备是否支持 `tr`，也不能用历史列表代替验证。

2026-10-05 检查当前源码及 HAP：土耳其语词表均有 148 个词条，非空 `audioAsset` 为 0。`VocabAudioResolverImpl.resolve` 不会为它们提供词条录音，`AudioController._speakWord` 最终会尝试 TTS。**课程录音并未承担这份内置词表的朗读兜底**；已有媒体播放通道不能替代内容资源的实际交付。

若当前设备缺少可用土耳其语语音，这条 TTS 路径会失败；这是条件判断，尚未证明它就是本次真机无声的根因。UI 应呈现实际返回的语音信息，并区分查询失败、状态未知、目标语言不可用和播放失败。

## 如何满足 ADR 0047 §2.3「不做隐式降级」

两条判据，均有门禁：

1. **如实呈现**：设置页与闪屏页在伴生版只讲「设备有哪些语音」，不出现引擎 / 商店 / 语音包语义。
2. **不提供无法兑现的按钮**：`openSystemTtsSettings` 在非 Android **恒返回 `false`**（它发的是 Android `Intent`），`openGoogleTtsInstallPage` 需要商店应用。二者在伴生版都是**静默空操作**——按钮点下去对话框关掉、什么都没发生。故在伴生版**不渲染**它们，而不是渲染一个失败的按钮。

门禁：`test/l10n/voice_copy_platform_test.dart` 覆盖语音列表文案与空操作按钮守卫；`test/application/anki_official/ohos_eol_architecture_guard_test.dart` 覆盖通道名、回包键与查询模式的代码形状。它们**不验证安装状态语义、录音资源是否存在或真机出声**。「课程自带录音仍可播放」是当前受门禁保护的文案，不证明内置词表有录音；修正文案与对应测试属于后续代码工作，本次仅订正文档。

## 候选后续（历史可行性记录，见 [ADR 0049](./0049-ohos-turkish-tts-sherpa-feasibility.md)）

sherpa-onnx 的 HAR 安装、声明解析与包体 A/B 结果保留在 ADR 0049 的 2026-10-04 记录中。**本次未重新验证依赖版本、模型许可、设备加载或实际发音**；历史构建可行性不能当作已经交付土耳其语朗读的证据。

**结论：本批不实施**，因为剩下的未知（真机出声、首词延迟与 RTF、模型能否走沙盒路径而非 rawfile）与**该声音的许可条款**都需真机 / 网络才能关掉。详见 ADR 0049。

## 2026-10-05 核验结果

核验范围是当前工作区与既有构建产物，未构建或部署新 HAP，未修改应用或测试源码。`hdc list targets` 多次返回 `[Empty]`，本次**没有真机证据**。

### 产物与源码

- 对象：`build/ohos/hap/entry-default-signed.hap`，本地修改时间 2026-10-05 03:19:45，大小 40,588,711 字节。
- SHA-256：`c94bb19b1d2e1e77a5f8659b2a05c3dca9a7814ef4b08e78d5f4cbf3a3359f48`。体积仅描述此产物；原文 172.94 MB 不再代表当前构建。
- 8 个错误／升级音效全部存在，逐个文件与当前源资源的字节一致。因此不能将此 HAP 的音效无声直接归因于音效未打包。
- `ets/modules.abc` 含 `stageBytes`、`createMediaSourceWithFd`、`ping`、`TurnaSpeakListener` 字符串，仅证明相关代码进入产物。
- 磁盘上的 9 个 `assets/sounds/turkish/listening/` MP3 未进入此 HAP；本次未证明当前教学入口实际引用它们，不能据此解释全部课程无声。

### 模拟原生接口的控制流程验证

用本机 SDK 的 TypeScript 转译器加载未修改的 `AudioPlugin.ets` / `TtsPlugin.ets`，以模拟对象替代原生媒体、TTS 与文件 API。**覆盖的是插件控制流程，不是 ArkTS 真机运行、解码或听感**。

| 场景 | 实际结果 |
|---|---|
| 媒体源 Promise 待定时触发播放器 `error` | 通道回复 0 次、句柄关闭 0 次；`error` 未调用 `fail`，准备阶段播放器尚未记入槽位 |
| 媒体源 Promise 拒绝（对照） | 回复 `PLAY_ERROR`，证明 Promise catch 与原生 error 事件的处理不同 |
| 音频完成 | 没有 `stateChange` 监听，release 0 次 |
| 下一段音频替换旧播放器 | 旧播放器 stop 1 次、release 0 次 |
| TTS 接受请求后触发 `onError` | Dart 仍只有 `success(true)`，后续失败只记原生日志 |

以上验证说明错误反馈与资源释放存在缺口，**未证明这些缺口已在用户设备上触发**。临时验证脚本不属于已入库的永久回归门禁。

### Dart 检查与证据边界

匹配当前包配置的 OHOS SDK 对 `audio_backend.dart`、`speech_backend.dart`、`tts_availability_checker.dart`、`AudioController`、`AudioModule` 做定向分析，结果 `No issues found`。

原有 `test/service/audio_backend_test.dart` 与 `test/service/speech_backend_test.dart` 定向执行为 **32 通过、3 失败**。失败源于音频测试仍模拟直接 `playAsset` 的旧协议；当前实现先读 bundle，再要求 `stageBytes` 返回路径。该测试结果不能描述为全绿，也不证明原生发音成功。全量提交门禁本次未重跑；历史全绿记录不代表当前工作区。

本机 SDK 依据是 `@hms.ai.textToSpeech.d.ts` 的 `TextToSpeechEngine.listVoices`、namespace `listVoices`、`VoiceQuery`、`VoiceInfo`，以及 `@ohos.multimedia.media.d.ts` 的 `createAVPlayer`。官方网页本次连接关闭，未取得更细的参数说明，因此不据二手镜像断言特定 person 编号或 `SpeakParams` 字段行为。

历史测试收据原文保留；本次订正见 `test/BASELINE.md` 2026-10-05「鸿蒙音频文档核验与历史结论订正」条目。

## 真机待验收

1. 记录实际设备、系统、安装包版本与构建类型；核对音效开关、感官减负、媒体音量与输出路由。
2. 分别验证通道 `ping`、bundle 字节数、暂存文件内容与 AVPlayer 状态、音轨、播放进度、error / audioInterrupt 事件，确认实际听感。
3. 重新检查 Callback / Promise 创建播放器的返回行为，不沿用历史 `undefined` 结论。
4. 保留语音查询的完整 language / person / status、查询模式与异常，验证安装状态解释及实际初始化能力。
5. 分别朗读中文、英文、土耳其语，记录请求参数与 `onStart` / `onComplete` / `onError`，确认实际听感。

在补齐这些证据前，不声称音效已修复、TTS 已交付、当前设备不支持土耳其语或鸿蒙平台上土耳其语无解。

## 撤销条件

1. 上游为 `audioplayers` / `flutter_tts` 提供官方 OHOS target → 删两个插件，Dart 侧实现退化为薄封装（接缝保留，`Ohos*Backend` 整个移除）。
2. 真机确认目标语言可用或引入第三方合成后端 → 按实际语音查询、初始化与发音结果更新能力状态。当前 `languageCandidates` 已生成 `tr` 候选，不能将问题简化为「加入 tr 即可」。
3. `OhosDegradation` 或 UI 的能力表述变化 → 同步核对实现与验收证据；枚举增删本身不能证明能力成功或接缝被绕过。

## 2026-10-07 真机验收

真机：HUAWEI Mate 40 Pro（CMM-AL10）/ OpenHarmony 7.0.0.109 / API 26。本节只记结论与被推翻的判断，实现细节与逐条根因见 [ADR 0049](./0049-ohos-turkish-tts-sherpa-feasibility.md) 的「2026-10-07 实施与真机验收」。

### 音效：已修复

历史四个真因**全部不是当前根因**——它们都在上游，且已被证明绕过（通道 ping 有回包、字节数逐个比对一致、fd 源创建成功）。真正卡住的是第五个：

**`player.setMediaSource(source)` 在这台设备上永不完成**，promise 不落定、`stateChange` 与 `error` 事件也都不触发。3/3 次播放形态完全一致。改法：`player.fdSrc = { fd, offset, length }` 直接赋值 + **全程不 await 任何 promise**、只用 `stateChange` 驱动（`initialized → prepare → prepared → play`）。证据：`playing → completed`，实播 3.3 秒，音轨数 1。

这与仓库已知的三个「promise 访问器在 API 26 上变沉默」是同一族（`getRawFileContent`、`ResultSet.getColumnNames()`、`getColumnTypeSync` 行外调用），`AVPlayer.setMediaSource` 是第四个。

配套修掉两处：启动探针从「只暂存」改为「真播放并等 `completed`」——原来它在 `playing` 后 50 ms 就自己 `release()`，把要证明的声音掐掉了；以及把 Dart 侧结果回声到 hilog（Dart logger 在此 embedding 上不进设备日志，且 app domain 缓冲区会轮转，「某行没出现」不能当证据）。

### TTS：CoreSpeechKit 判定不可用

- **`VoiceInfo.status` 必须看。** 该设备真实音色是 `zh_CN person=13 (INSTALLED)`、`zh_CN person=21 (GA)`、`en_US person=8 (GA)`；**没有土耳其语**。
- **历史「英语不支持」结论是错的。** `PERSON_CANDIDATES = [0..7]` 全是无效 id，真实 id 是 13 / 21 / 8。`en-US/0..7` 全被拒与语言无关，`zh-CN person 0` 被「接受」后是个空引擎。已改为从 `listVoices` 读真实音色（`INSTALLED` 优先）。
- **`speak` 不能用调用方的语言标签覆盖引擎自身的。** `zh_CN` 与 `zh-CN` 是同一语言的两种写法，混用得到的是沉默而非报错。
- **即便如此，CoreSpeechKit 在这台设备上对任何语言都不出声**，包括设备自称 `INSTALLED` 的中文音色：`speak` 返回 true、`onComplete` 在 ~44 ms 后触发两次、`onError` 一次不出现。已退出候选，改由 sherpa-onnx 承担（ADR 0049）。

因此本文 §「候选后续」已实施：`SpeechBackend` 在伴生版的主实现是 `SherpaSpeechBackend`，合成出的 WAV 交给已注册的 speech `AudioBackend` 播放。伴生版出声不再依赖系统语音包。

### 遗留

`test/service/audio_backend_test.dart` 原有 3 例断言的是已被废弃的「一次 `playAsset` 直发」协议（即 staging 未搬到 Dart 侧时的形状），长期红着。已于 2026-10-07 按真实协议重写并补 `rootBundle` 打桩，`flutter test --exclude-tags golden` 2118 通过 / 0 失败。