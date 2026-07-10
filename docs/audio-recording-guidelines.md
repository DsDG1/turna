# Audio Recording Guidelines for Contributors

This document describes how to submit human-recorded audio for the Swahili course. Human recordings can replace or supplement TTS-generated files produced by `tool/generate_audio.py`.

## When to contribute recordings

- You are a native or fluent Swahili speaker.
- The TTS output for a specific word, expression, or listening phrase sounds unnatural.
- You want to provide a more natural alternative for a high-frequency phrase.

## File format

- **Container**: MP3
- **Sample rate**: 44.1 kHz
- **Channels**: Mono preferred; stereo accepted
- **Bit rate**: 128 kbps or higher
- **Leading / trailing silence**: ≤ 0.3 seconds each

## Naming and directory layout

The filename must exactly match the `audioAsset` value used in the course JSON, plus the `.mp3` extension.

| Content type | JSON field | Output directory | Example asset id | Example file |
|---|---|---|---|---|
| Word | `WordEntry.audioAsset` | `assets/sounds/swahili/words/` | `w-habari` | `assets/sounds/swahili/words/w-habari.mp3` |
| Expression | `Expression.audioAsset` | `assets/sounds/swahili/expressions/` | `e-habari-za-asubuhi` | `assets/sounds/swahili/expressions/e-habari-za-asubuhi.mp3` |
| Listening / lesson | `audioAsset` on interaction or phase | `assets/sounds/swahili/listening/` | `section:foundations` | `assets/sounds/swahili/listening/section:foundations.mp3` |

Use the same id that already appears in the course JSON. Do not invent new ids unless you also update the JSON.

## Recording quality checklist

- [ ] Record in a quiet environment with minimal background noise.
- [ ] Use a pop filter or keep the microphone 10–20 cm from your mouth.
- [ ] Speak at a natural, learner-friendly pace (not too fast).
- [ ] Avoid exaggerated intonation; aim for clear, neutral pronunciation.
- [ ] Normalize volume so the file is neither too quiet nor clipped.
- [ ] Trim leading and trailing silence to under 0.3 seconds.
- [ ] Export as MP3 with the settings listed above.

## How to submit

1. Place the MP3 file in the correct subdirectory under `assets/sounds/swahili/`.
2. Make sure the corresponding `audioAsset` field in `vocab.json`, `expressions.json`, or the section JSON is set to the same id.
3. Run the validation tools:
   ```bash
   python tool/course_cli.py validate
   python tool/course_cli.py audio-manifest --output /tmp/manifest.csv
   ```
4. Open a pull request. The CI workflow `course_validation.yml` will verify the course still passes validation.

## Replacing TTS-generated files

If a TTS-generated MP3 already exists for the same asset id, your human recording should overwrite it. Commit the replacement and mention in the PR description that it replaces a TTS file.

## Batch submissions

For more than a few files, organize them by directory and include a summary in the PR:

```
Contributed human recordings for Unit 1 Greetings:
- assets/sounds/swahili/words/w-habari.mp3
- assets/sounds/swahili/words/w-nzuri.mp3
- assets/sounds/swahili/expressions/e-habari-za-asubuhi.mp3
```

## Legal / licensing

By submitting audio, you confirm that:

- The recording is your own voice or you have permission to submit it.
- You grant the project a perpetual, royalty-free license to distribute the recording as part of Varnamala.
- The recording does not include copyrighted background music or other third-party material.
