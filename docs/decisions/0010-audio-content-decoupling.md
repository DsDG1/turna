# ADR 0010 — 音频 / 内容解耦（`VocabAudioResolver`）

> 状态：Accepted ｜ 日期：2026-07-11 ｜ 关联：future4 Phase 18、ADR 0007
## 决策

1. 新增 `VocabAudioResolver`（`lib/domain/audio/vocab_audio_resolver.dart`），返回 `ResolvedVocabAudio { audioAsset?, speakText }`。
2. 交付 `SwahiliVocabAudioResolver`（`@LazySingleton(as: VocabAudioResolver)`），由既有 `swahiliVocabById` map 支撑。
3. `AudioController` 只依赖接口，不再 import 斯瓦希里词表。
4. 路径判定与 `assets/` / 前导 `/` 的归一化放在 `AudioController` 上（`isAssetPath`、`normalizeAssetPath`、`speakListenContent`）；渲染器改调这些 API，不再各自重写启发式。
5. **本阶段不引入第二种语言。** 该抽象只把依赖箭头反转，好让将来注册另一个 `VocabAudioResolver` 时不必动音频栈。
## 理由

`AudioController.speakWord` 直接 import `swahili_vocab.dart` 并查 `swahiliVocabById`，把音频栈耦合到单语言 map；未来多语言内容必须改控制器。

另外，`ListenOnlyRenderer` 里塞了路径启发式（`contains('/')` / `startsWith('assets')`）——那属于资源播放旁边，不属于 UI 渲染器。
## 影响与边界

- 单测可注入 map 支撑的 fake resolver，`speakWord` 路由测试不再需要改动全局词表。
- 将来真正加入第二种语言是 DI 注册 + 内容包问题，不是重写 `AudioController`。
- 只听渲染器的代码更短，且不再含路径字符串判断。
