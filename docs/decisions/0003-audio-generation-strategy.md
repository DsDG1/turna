# ADR 0003: Audio Generation Strategy

- **Status**: Accepted
- **Date**: 2026-07-10
- **Related**: `future3.md` Phase 15, Phase 16, Phase 20

## Context

Varnamala is a local-first, offline language-learning app. The Swahili course needs audio for:

- **Word pronunciation** in `ShowWord` interactions.
- **Expression playback** in expression review and example sentences.
- **Listening comprehension** via `listenAndPick`, `typeTheWord`, and `listenOnly` interactions in listening lessons.

The app already bundles a Piper Swahili TTS model (`sw_CD-lanfrica-medium`) via `sherpa_onnx` and uses it at runtime (`lib/service/piper_swahili_tts.dart`). For individual words and expressions, this runtime TTS is sufficient: learners tap a word and hear it synthesized on demand, without bundling a separate MP3 per entry.

However, listening-lesson interactions need longer or contextual audio prompts that must play reliably and without the per-call latency of runtime synthesis. These prompts are referenced by `audioAsset` fields inside `listeningPhases`. Currently the bundled course JSON has almost no such `audioAsset` references, and the few that exist point to files that do not exist under `assets/sounds/`.

We need a strategy for producing, storing, and maintaining audio assets that:

1. Keeps the app offline-first with no cloud TTS API calls at runtime.
2. Gives content contributors a repeatable way to generate audio in bulk.
3. Leaves room for high-quality human recordings to replace or supplement TTS.
4. Keeps APK/AAB size reasonable as the course grows.

## Decision

We will use a **hybrid strategy: listening-lesson MP3 assets + runtime Piper TTS for everything else**.

### 1. Offline assets only for listening lessons

Only `audioAsset` references inside `listeningPhases` of `listening` template lessons point to bundled `.mp3` files. Individual `WordEntry` and `Expression` items do **not** have offline audio assets; their pronunciation is synthesized at runtime (system/Google TTS by default, or the bundled Piper model when offline mode is selected).

### 2. Bulk generation with the bundled Piper model

Listening-lesson audio assets are generated in bulk using the same `sw_CD-lanfrica-medium` Piper model that the app bundles for runtime TTS. This guarantees consistency between pre-generated listening audio and fallback pronunciation audio.

- **Primary tool**: `tool/generate_audio.py`.
- **Preferred backend**: `sherpa-onnx` Python API (matches the Flutter runtime).
- **Fallback backend**: `piper` command-line executable if available.
- **Output format**: `.mp3` (mono or stereo, 44.1 kHz).
- **Directory layout**:
  - `assets/sounds/swahili/listening/{assetId}.mp3`
- **What gets generated**: only `audioAsset` values referenced by `listeningPhases` that are **not** also a `wordId` or `expressionId`.

### 3. No cloud TTS APIs

We do not use Google Cloud TTS, Azure Speech, Amazon Polly, or similar services. They require network access, credentials, and ongoing cost, all of which conflict with the project's local-first principles.

### 4. Human recordings for listening content

Contributors may submit human recordings for listening-lesson prompts. The submission format is documented in `docs/audio-recording-guidelines.md`.

- File format: MP3, 44.1 kHz.
- Naming must match the `audioAsset` value and be placed in `assets/sounds/swahili/listening/`.
- Recordings should avoid background noise and keep leading/trailing silence under 0.3 seconds.

### 5. Fallback chain at runtime

When an interaction needs audio:

1. If the interaction is a listening lesson item with an `audioAsset` and the file exists in the bundle, play it.
2. For individual words, expressions, or any interaction without a usable offline asset, follow the user-selected TTS engine (`SettingsProvider.ttsEngine`):
   - **`system` (default):** use the device local TTS via `flutter_tts` first. On Android, prefer the Google TTS engine (`com.google.android.tts`) when installed, then resolve a usable Swahili locale (`sw` / `sw-KE` / `sw-TZ`). If system TTS throws, fall back to the bundled Piper Swahili model.
   - **`offline`:** use the bundled Piper Swahili model first; if Piper fails or is unavailable, fall back to system TTS.
3. Listening-lesson **pre-generated** assets remain Piper-generated offline files (or human recordings). That path is independent of the runtime system-vs-Piper preference above.

## Consequences

### Pros

- **System voice first**: Default runtime speech uses the device/Google TTS, which is usually already installed and higher quality than a small offline model.
- **Offline fallback**: Piper remains available when the user chooses offline mode or system TTS fails.
- **Offline-first listening**: Pre-generated listening assets need no network.
- **Contributor-friendly**: A CSV/word list can be turned into listening audio with one CLI command.
- **Future-proof**: Human recordings can replace TTS files one-by-one without changing the data model.

### Cons

- **APK size**: Listening passages still add size, but far less than one MP3 per word/expression.
- **Quality ceiling**: Piper is good but not native-speaker quality; human recordings are needed for premium listening content.
- **Regeneration cost**: Content replacement (e.g., Phase 20 Kannada → Swahili) still requires re-running the generation script for listening assets.

### Mitigations

- Use the int8-quantized Piper model and MP3 compression.
- Evaluate per-section asset bundles or optional downloads if listening assets grow large.
- Keep a manifest of generated listening files so CI can fail if a listening `audioAsset` reference has no matching file.

## Implementation notes

- `tool/generate_audio.py` scans section JSON for `audioAsset` references inside `listeningPhases`, skips assets that match a `wordId` or `expressionId`, and delegates the remaining listening entries to the available TTS backend.
- `tool/course_cli.py audio-manifest` scans listening-lesson `audioAsset` references and reports whether each file is present.
- `pubspec.yaml` lists only `assets/sounds/swahili/listening/` so Flutter includes listening assets in the build.
- Phase 16 will generate audio for the pilot listening lesson and validate playback end-to-end.
- Phase 20 will regenerate all listening audio after the Kannada placeholders are replaced with real Swahili vocabulary.

## Alternatives considered

- **MP3 for every word/expression**: Provides uniform playback but dramatically increases bundle size and regeneration cost; rejected in favor of runtime TTS for individual entries.
- **Runtime TTS only**: Avoids pre-generation entirely but makes listening interactions slower and inconsistent with offline-first quality expectations; rejected for listening lessons.
- **Cloud TTS at build time**: Could use higher-quality voices, but requires credentials and network during builds; violates local-first principles.
- **Coqui TTS / Mozilla TTS**: Viable alternatives, but the app already bundles and tests the Piper `sw_CD-lanfrica-medium` model; switching would require re-evaluating model quality and runtime integration.

## Related code

- `lib/service/piper_swahili_tts.dart` — bundled Piper runtime TTS
- `lib/application/audio_controller.dart` — offline asset vs. TTS routing
- `tool/generate_audio.py` — bulk generation script
- `tool/course_cli.py audio-manifest` — asset reference status report
- `docs/audio-recording-guidelines.md` — human recording submission format
