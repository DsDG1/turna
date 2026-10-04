# ADR 0048 — OHOS 伴生版音频播放与 TTS 交付（原生通道，不 fork 依赖）

- 状态：已接受
- 日期：2026-10-04
- 关联：[ADR 0047](./0047-ohos-companion-lite-build.md)（§2.3 显式降级条件、§5.5 override ratchet）、[ADR 0041](./0041-ohos-product-eol.md)
- 编号说明：0047 之后的下一个可用编号。

## 背景

伴生版要出声，但两侧都不给路：

1. `audioplayers` / `flutter_tts` 官方包**没有 OHOS target**，装上即通道无人应答。
2. ADR 0047 §5.5 **永禁** override 这两个包（ratchet，且不与本规则相关的改动不得顺手放宽）。
3. fork 也不可行：`flutter_tts` 的 `InitializationSettings` 之类是**公开 API 分叉**，官方 SDK 下硬编译错误（同 §7.3 移除 `flutter_local_notifications` 的同一条理由），而 fork 一个 pub 包正是 ADR 0041 明令删除的东西。

于是只剩「自己写」。这不是偏好问题：仓库里已有 `RdbPlugin` / `FilePickerPlugin` 两个手写 ArkTS 插件，**同一范式**是既有事实，不是新发明。

**基线校准**：Android 侧用的是 Google TTS，即**机器合成**，不是人声录音。所以本 ADR 的目标不是「更好听」，是**同等量级的机器合成**。任何把课程录音当唯一解的论证都是错的目标函数。

## 决策

### 1. Dart 接缝 + 手写 ArkTS 插件，零 override

- `lib/service/audio_backend.dart`：`AudioSlot`（`effects` / `speech`，**保留原双槽语义**）、`AudioBackend`、`AudioplayersAudioBackend`（Android / iOS）、`OhosAudioBackend`、`createAudioBackends()`。
- `lib/service/speech_backend.dart`：`SpeechBackend`、`FlutterTtsSpeechBackend`（Android / iOS）、`OhosSpeechBackend`、`mapFlutterTtsRateToPercent`。
- `SpeechBackend` 必须是**共享单例**：它携带已绑定的 locale 与 rate，多实例会让「可用性检查」和「真正朗读」对不上同一个引擎状态。
- `AudioController` 是**唯一**知道平台接缝的消费方。页面层只见 `AudioController`。
- 通道名两端各写一份字面量（`me.dsdogs.turna/audio`、`me.dsdogs.turna/tts`），由门禁断言**双端一致**——这是真实踩过的坑：RDB 通道名对不上时，平台消息无人应答，表现为**白屏**而非报错（W4 真因①）。

**工厂闭包而非直接构造**：`OhosAudioBackend` 的构造参数是 `AudioPlayer` 的**工厂闭包**，不是 `AudioPlayer`。直接构造会让 DI getter 在 OHOS 上真的去 new 一个 `AudioPlayer` 并调 `init`，抛 `MissingPluginException`——而 DI getter 的异常会变成 **uncaught framework error**。详见真机事实表最后一行的实测形态。

### 2. 资产投递：拷贝到沙箱再播，不用 raw fd

`getRawFileContent` 读出字节 → 写 `cacheDir/turna_audio/<name>` → `createMediaSourceWithUrl('file://…')`。

**为什么不用 raw fd**：raw fd 的 `close` 与播放器实际消费之间存在时序窗口，窗口内被回收就是**截断后的半个音频**——不报错，只是后半段没了。这类失败无法在真机之外复现，也就无法用测试挡住。

**每次播放新建 AVPlayer，播完 release**，不复用 `reset()`：AVPlayer 状态机在异常路径上会静默卡死，而卡死同样是静音。

### 3. TTS：CoreSpeechKit，参数靠探测而非假设

- `createEngine` 的 `person` **不能假设为 0**。设备实测 `person: 0` + `en-US` 返回 `1002300003 create param is error,person not support!`；换 `zh-CN` 才通过。改为**候选探测阶梯**（person 0–7 × 语言候选）并把命中结果缓存进进程。
- 语音列表取**命名空间级** `textToSpeech.listVoices`（`@since 19`），且分成 `installed` / `supported` 两组分别取回（online = 0 与 1 各一次）。engine 实例上的 `listVoices` **只报已装**，拿不到可下载集合——用错 API 会把「可下载」误报成「没有」。
- rate 换算放 Dart 纯函数（`percent = 50 + (rate - 0.5) * 100`，clamp 0..100，0.5→50、1.0→100），因为**无设备也能单测**。
- 删除 `OhosDegradation.textToSpeech`：它当初存在的理由是「包没有 OHOS 插件」，现在理由不成立了。留着会把一个能用的功能标成降级，**并且把真实回归藏在「已知限制」标签后面**。

## 真机事实（HUAWEI Mate 90 Pro Max / API 26 / HarmonyOS 7.0.0.109）

| 观测 | 结果 |
|---|---|
| `createEngine(zh-CN, person 0)` | **成功** |
| `createEngine(en-US, person 0)` | 失败 `1002300003 … person not support!` |
| `createEngine(tr)` | 失败 `1002300002 … language not support!` |
| `listVoices` 已装 | `[zh_CN, en_US]` |
| `listVoices` 可下载（online 0 ∪ 1） | `[zh_CN, en_US]`——**与已装集合相同** |
| 资产路径漏 `assets/` 段 | `9001005 GetRawFileContent failed`，8 个音效**全部静音** |
| `createAVPlayer()` 的 promise 重载 | 返回 `undefined` → `Cannot read property then of undefined` |
| OHOS 上构造 `AudioPlayer` | `MissingPluginException(No implementation found for method init …)`，从 DI getter 抛出为 uncaught |

设备语音标签用下划线（`zh_CN` / `en_US`），而 App 侧候选是 `tr` / `tr-TR` / `tr_TR`，故语言解析需**基础子标签兜底匹配**，否则精确匹配永远落空。

## 明确不交付：土耳其语 TTS

这不是「还没做」，是**平台侧没有**：`listVoices` 的已装集合与可下载集合**都不含 `tr`**，所以 `textToSpeech.downloadVoice` 也拿不到——API 存在 ≠ 该设备供给该语音。处置：

1. 课程自带录音（`assets/courses/<dir>/media/` + 词汇音频解析）承担课程朗读，这条通道与设备语音无关，在所有鸿蒙机型上成立。
2. UI **如实说明**当前设备语音列表，不承诺做不到的事。

## 如何满足 ADR 0047 §2.3「不做隐式降级」

两条判据，均有门禁：

1. **如实呈现**：设置页与闪屏页在伴生版只讲「设备有哪些语音」，不出现引擎 / 商店 / 语音包语义。
2. **不提供无法兑现的按钮**：`openSystemTtsSettings` 在非 Android **恒返回 `false`**（它发的是 Android `Intent`），`openGoogleTtsInstallPage` 需要商店应用。二者在伴生版都是**静默空操作**——按钮点下去对话框关掉、什么都没发生。故在伴生版**不渲染**它们，而不是渲染一个失败的按钮。

门禁：`test/l10n/voice_copy_platform_test.dart`（**9 例**）——3 例纯函数（语音列表渲染，含空列表显式为「无」）、3 例文案断言（伴生版文案不含 Google / Play / 商店字样；且必须保留「课程自带录音仍可播放」这句）、3 例源码扫描（按钮受平台守卫；闪屏伴生分支内**不含**两个空操作调用）。源码扫描是必需的，因为 `isHarmonyOsTarget` 比较 `defaultTargetPlatform.name == 'ohos'`，而 `TargetPlatform.ohos` 只存在于 OHOS 引擎 fork，宿主 SDK 上**无法**让该分支被执行。已**反向验证**：在伴生分支里加回 `openSystemTtsSettings` 即红。

## 候选后续（**已实测，见 [ADR 0049](./0049-ohos-turkish-tts-sherpa-feasibility.md)**）

sherpa-onnx 在鸿蒙上可行且成本不高：ohpm 已发布**预编译 HAR** `sherpa_onnx`（1.13.3，含 `OfflineTts` / `generateAsync` 的 ArkTS 绑定），无需交叉编译、无需自写 NAPI。**已实测**：安装成功、ArkTS 声明在本工程解析成功、原生库进包、同条件 A/B 体积增量 **38.53 MB**（38.70 → 77.23 MB）。土耳其语声音 `vits-piper-tr_TR-dfki-medium`（1 说话人 / 22050 Hz）有 int8 变体（模型 18.7 MB），但 `espeak-ng-data`（17.2 MB）**运行时强制存在**。

**结论：本批不实施**，因为剩下的未知（真机出声、首词延迟与 RTF、模型能否走沙盒路径而非 rawfile）与**该声音的许可条款**都需真机 / 网络才能关掉。详见 ADR 0049。

## 验证状态

**已实测（真机）**：`createEngine` 探测阶梯命中、语音列表双集合返回、资产路径修正、promise 重载缺陷、DI 构造缺陷。

**仅代码 + 构建，未真机**：音效在真机上播放不再报 `9001005` —— 修法已构建通过（`flutter build hap` 产出 `entry-default-signed.hap`，实测 **172.94 MB**），但播放结果需真机触发一次音效确认，而本批收尾时**无真机**。在补上这一条之前，**不得**声称音效已修复。

## 撤销条件

1. 上游为 `audioplayers` / `flutter_tts` 提供官方 OHOS target → 删两个插件，Dart 侧实现退化为薄封装（接缝保留，`Ohos*Backend` 整个移除）。
2. 平台为 `tr` 提供可下载语音 → 本 ADR 的「不交付」段作废，`_resolveHarmonyOsLanguage` 的候选表加入 `tr` 即可，无需改结构。
3. `OhosDegradation` 重新出现音频 / TTS 条目 → 说明接缝被绕过，本 ADR 的接缝形状失效，须重新评估。
