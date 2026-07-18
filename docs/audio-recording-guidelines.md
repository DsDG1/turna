# Audio Recording Guidelines for Contributors

This document describes how to submit human-recorded audio for the **Turkish** course. Human recordings can replace or supplement TTS-generated files produced by `tool/generate_audio.py`.

## TTS background (what is already automated)

Varnamala uses **runtime TTS** (`flutter_tts`, language code `tr`; Android prefers `com.google.android.tts`) for individual vocabulary words and expressions. No offline TTS model is bundled — see [ADR 0020](./decisions/0020-swahili-to-turkish-pivot.md) for the audio strategy.

For **listening lessons** only, we pre-generate longer-phrase / dialogue audio with MiniMax TTS via `tool/generate_audio.py` and bundle the MP3s under `assets/sounds/turkish/listening/`. These files may be mixed with BGM by `tool/mix_listening_a1.py` (see [`listening-show-format.md`](./authoring/listening-show-format.md)).

Because human voice sounds more natural than TTS for dialogues and broadcast-style listening content, contributors may replace those generated MP3s with their own recordings. **Human recordings are only accepted for listening-lesson / longer-phrase content** — single words and short expressions stay on runtime TTS.

## When to contribute recordings

- You are a native or fluent Turkish speaker.
- The TTS output for a specific listening-lesson phrase or dialogue sounds unnatural.
- You want to provide a more natural alternative for a high-frequency listening phrase.

## File format

- **Container**: MP3
- **Sample rate**: 44.1 kHz
- **Channels**: Mono preferred; stereo accepted
- **Bit rate**: 128 kbps or higher
- **Leading / trailing silence**: ≤ 0.3 seconds each

## Naming and directory layout

The filename must exactly match the `audioAsset` value used in the listening lesson JSON, plus the `.mp3` extension.

| Content type | JSON field | Output directory | Example asset id | Example file |
|---|---|---|---|---|
| Listening / lesson | `audioAsset` on interaction or phase | `assets/sounds/turkish/listening/` | `l-greetings` | `assets/sounds/turkish/listening/l-greetings.mp3` |

Use the same id that already appears in the course JSON. Do not invent new ids unless you also update the JSON.

> The `assets/sounds/turkish/listening/` tree also contains show-format subdirectories (`bgm/`, `debut/`, `fin/`) used by the listening "broadcast" layout for BGM, intro, and outro assets. These are generated/mixed assets — put human voice recordings in the listening root as shown above, not in those subdirectories.

## Recording quality checklist

- [ ] Record in a quiet environment with minimal background noise.
- [ ] Use a pop filter or keep the microphone 10–20 cm from your mouth.
- [ ] Speak at a natural, learner-friendly pace (not too fast).
- [ ] Avoid exaggerated intonation; aim for clear, neutral pronunciation.
- [ ] Normalize volume so the file is neither too quiet nor clipped.
- [ ] Trim leading and trailing silence to under 0.3 seconds.
- [ ] Export as MP3 with the settings listed above.

## How to submit

1. Place the MP3 file in `assets/sounds/turkish/listening/`.
2. Make sure the corresponding `audioAsset` field in the listening lesson JSON is set to the same id.
3. Run the validation tools:
   ```bash
   python tool/course_cli.py validate
   python tool/course_cli.py audio-manifest --output /tmp/manifest.csv
   ```
4. Open a pull request. The CI workflow `course_validation.yml` will verify the course still passes validation.

## Replacing TTS-generated files

If a MiniMax-TTS-generated MP3 already exists for the same listening asset id, your human recording should overwrite it. Commit the replacement and mention in the PR description that it replaces a TTS file.

## Batch submissions

For more than a few files, organize them by directory and include a summary in the PR:

```
Contributed human recordings for Unit 1 Listening:
- assets/sounds/turkish/listening/l-greetings.mp3
- assets/sounds/turkish/listening/u-greetings-dialogue.mp3
```

## Legal / licensing

By submitting audio, you confirm that:

- The recording is your own voice or you have permission to submit it.
- You grant the project a perpetual, royalty-free license to distribute the recording as part of Varnamala.
- The recording does not include copyrighted background music or other third-party material.
