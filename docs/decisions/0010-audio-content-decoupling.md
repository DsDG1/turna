# ADR 0010: Audio / content decoupling (`VocabAudioResolver`)

- **Status**: Accepted
- **Date**: 2026-07-11
- **Related**: future4 Phase 18, ADR 0007

## Context

`AudioController.speakWord` imported `swahili_vocab.dart` and looked up
`swahiliVocabById` directly. That couples the audio stack to a single language
map and makes multi-language content (future) require editing the controller.

Separately, `ListenOnlyRenderer` contained path heuristics (`contains('/')` /
`startsWith('assets')`) that belong next to asset playback, not in a UI
renderer.

## Decision

1. Introduce `VocabAudioResolver` (`lib/domain/audio/vocab_audio_resolver.dart`)
   with `ResolvedVocabAudio { audioAsset?, speakText }`.
2. Ship `SwahiliVocabAudioResolver` as `@LazySingleton(as: VocabAudioResolver)`,
   backed by the existing `swahiliVocabById` map.
3. `AudioController` depends only on the interface; it no longer imports
   Swahili vocab.
4. Path detection + `assets/` / leading-`/` normalization live on
   `AudioController` (`isAssetPath`, `normalizeAssetPath`,
   `speakListenContent`). Renderers call those APIs instead of re-implementing
   heuristics.
5. **This phase does not introduce a second language.** The abstraction only
   reverses the dependency arrow so a future language can register another
   `VocabAudioResolver` without touching the audio stack.

## Consequences

- Unit tests inject a map-backed fake resolver; no global vocab mutation needed
  for `speakWord` routing tests.
- Adding a real second language later is a DI registration + content pack
  problem, not an `AudioController` rewrite.
- Renderer code for listen-only is shorter and free of path string checks.
