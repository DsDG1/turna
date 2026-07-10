# ADR 0003: Audio Generation Strategy

- **Status**: Accepted
- **Date**: 2026-07-10
- **Related**: `future3.md` Phase 15, Phase 16, Phase 20

## Context

Varnamala is a local-first, offline language-learning app. The Swahili course needs audio for:

- Word pronunciation in `ShowWord` interactions.
- Expression playback in expression review and example sentences.
- `listenAndPick`, `typeTheWord`, and `listenOnly` interactions in listening lessons.

The app already bundles a Piper Swahili TTS model (`sw_CD-lanfrica-medium`) via `sherpa_onnx` and uses it at runtime when no offline audio asset is available (`lib/service/piper_swahili_tts.dart`). However, the bundled course JSON currently has almost no `audioAsset` references, and the few that exist point to files that do not exist under `assets/sounds/`.

We need a strategy for producing, storing, and maintaining audio assets that:

1. Keeps the app offline-first with no cloud TTS API calls at runtime.
2. Gives content contributors a repeatable way to generate audio in bulk.
3. Leaves room for high-quality human recordings to replace or supplement TTS.
4. Keeps APK/AAB size reasonable as the course grows.

## Decision

We will use a **hybrid strategy: local bulk pre-generation + runtime Piper TTS fallback**.

### 1. Offline assets are the default

Every `WordEntry`, `Expression`, and listening-lesson audio reference should point to a bundled `.mp3` file whenever possible. The app already prefers offline assets in `AudioController.speakWord` and `speakFromAsset`; missing assets transparently fall back to runtime TTS.

### 2. Bulk generation with the bundled Piper model

Audio assets are generated in bulk using the same `sw_CD-lanfrica-medium` Piper model that the app bundles for runtime TTS. This guarantees consistency between pre-generated audio and fallback audio.

- **Primary tool**: `tool/generate_audio.py`.
- **Preferred backend**: `sherpa-onnx` Python API (matches the Flutter runtime).
- **Fallback backend**: `piper` command-line executable if available.
- **Output format**: `.mp3` (mono or stereo, 44.1 kHz).
- **Directory layout**:
  - `assets/sounds/swahili/words/{wordId}.mp3`
  - `assets/sounds/swahili/expressions/{expressionId}.mp3`
  - `assets/sounds/swahili/listening/{assetId}.mp3`

### 3. No cloud TTS APIs

We do not use Google Cloud TTS, Azure Speech, Amazon Polly, or similar services. They require network access, credentials, and ongoing cost, all of which conflict with the project's local-first principles.

### 4. Human recordings as a first-class alternative

Contributors may submit human recordings in place of TTS-generated files. The submission format is documented in `docs/audio-recording-guidelines.md`.

- File format: MP3, 44.1 kHz.
- Naming must match the `audioAsset` value and be placed in the correct subdirectory.
- Recordings should avoid background noise and keep leading/trailing silence under 0.3 seconds.

### 5. Fallback chain at runtime

When an interaction needs audio:

1. If `audioAsset` is present and the file exists in the bundle, play it.
2. Otherwise, if the current target language is Swahili and the bundled Piper model initialized successfully, synthesize with Piper.
3. Otherwise, fall back to `flutter_tts` with the device's Swahili voice.

## Consequences

### Pros

- **Consistency**: Pre-generated and fallback audio use the same Piper voice.
- **Offline-first**: No network required for audio playback.
- **Contributor-friendly**: A CSV/word list can be turned into audio with one CLI command.
- **Future-proof**: Human recordings can replace TTS files one-by-one without changing the data model.

### Cons

- **APK size**: Each word needs an MP3. For 500 words plus expressions and listening passages, audio may become the largest part of the bundle.
- **Quality ceiling**: Piper is good but not native-speaker quality; human recordings are needed for premium content.
- **Regeneration cost**: Every content replacement (e.g., Phase 20 Kannada → Swahili) requires re-running the generation script.

### Mitigations

- Use the int8-quantized Piper model and MP3 compression.
- Evaluate per-section asset bundles or optional downloads once the course grows beyond a few hundred assets.
- Keep a manifest of generated files so CI can fail if an `audioAsset` reference has no matching file.

## Implementation notes

- `tool/generate_audio.py` reads the bundled course JSON, decides the target path for each entry, and delegates to the available TTS backend.
- `tool/course_cli.py audio-manifest` scans all `audioAsset` references and reports whether each file is present.
- `pubspec.yaml` lists `assets/sounds/swahili/words/`, `assets/sounds/swahili/expressions/`, and `assets/sounds/swahili/listening/` so Flutter includes them in the build.
- Phase 16 will generate audio for the pilot set of 10–15 words + 5–10 expressions and validate playback end-to-end.
- Phase 20 will regenerate all audio after the Kannada placeholders are replaced with real Swahili vocabulary.

## Alternatives considered

- **Runtime TTS only**: Avoids pre-generation entirely but makes listening interactions slower and inconsistent with offline-first quality expectations.
- **Cloud TTS at build time**: Could use higher-quality voices, but requires credentials and network during builds; violates local-first principles.
- **Coqui TTS / Mozilla TTS**: Viable alternatives, but the app already bundles and tests the Piper `sw_CD-lanfrica-medium` model; switching would require re-evaluating model quality and runtime integration.

## Related code

- `lib/service/piper_swahili_tts.dart` — bundled Piper runtime TTS
- `lib/application/audio_controller.dart` — offline asset vs. TTS routing
- `tool/generate_audio.py` — bulk generation script
- `tool/course_cli.py audio-manifest` — asset reference status report
- `docs/audio-recording-guidelines.md` — human recording submission format
