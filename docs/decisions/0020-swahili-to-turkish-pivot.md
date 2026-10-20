# ADR 0020 — Pivot the target language from Swahili to Turkish

> **Status:** Accepted ｜ **Date:** 2026-07-12
>
> **Supersedes:** [ADR 0001 — TTS 语言码](./0001-tts-language-code.md)（`'sw'` 那一项决定），并放弃 [ADR 0002 — 卡纳达语→斯瓦希里语内容替换](./0002-content-replacement-progress-policy.md)
## 决策

1. **Scope:** framework re-skin + a minimal Turkish course scaffold (`assets/courses/turkish/` with one section, one legacy lesson, empty vocab/grammar/expressions). No real content authoring this round.

2. **TTS:** system / Google TTS only, language code `'tr'` (locale candidates `tr-TR` / `tr_TR`). **Remove the bundled Piper Swahili model entirely** — delete `lib/service/piper_swahili_tts.dart`, `lib/service/piper_tts_worker.dart`, the `assets/voices/swahili/` model, the `sherpa_onnx` dependency, the `TtsEngine` enum + engine toggle in settings, and the Piper fallback path in `AudioController`. If a future build wants an offline Turkish voice, a Turkish Piper model would be re-bundled as a new decision.

3. **Naming:** rename Swahili-specific identifiers to generic + Turkish, so future multi-language support is not blocked by a misleading single-language name:

- `enum TargetLanguage { swahili }` → `{ turkish }`
- `class SwahiliCourse` → `class CourseLoader` (generic)
- `baseDir = 'assets/courses/swahili'` → `'assets/courses/turkish'`
- parse/load helpers: `parseSwahiliSection` → `parseSection`, `loadSwahiliVocabulary` → `loadVocabulary`, `validateSwahiliCourse` → `validateCourse`, etc.
- vocab/grammar/expression global maps: `swahiliVocabById` → `vocabById`, `swahiliGrammarPointById` → `grammarPointById`, `swahiliExpressionsById` → `expressionsById`
- `SwahiliVocabAudioResolver` → `VocabAudioResolverImpl`
- alphabet maps: `swahiliSounds/Vowels/Consonants` → `alphabetSounds/Vowels/Consonants`
- DB filename `course.swahili.db` → `course.db`
- default language preference `"swahili"` → `"turkish"`
- `TtsPreferredStatus.swahiliDataMissing` → `turkishVoiceMissing`

4. **Content version:** the Turkish scaffold ships `index.json` version `5` + `expressions.json` version `1` (composite `5+1`), so existing installs reseed on upgrade via the existing content-version gate.
## 理由

Varnamala was built Swahili-first: the enum, TTS language code, course loader class (`SwahiliCourse`), asset directory (`assets/courses/swahili/`), database file (`course.swahili.db`), bundled Piper Swahili voice, and ~16 hardcoded UI strings all carried "swahili" / `'sw'` as the language identity. The bundled vocabulary was still Kannada placeholder content; real Swahili vocabulary was deferred to a future "content round" (the plan of the day is gone; this ADR records the decision it produced).
## 影响与边界

- The framework now points at Turkish with an empty course; real Turkish content is the next round's job (tracked as "future5 / content" in `CLAUDE.md`（已删）).
- The historical planning docs of the day were left unrewritten as the historical record; this ADR supersedes the live decisions they described. They have since been removed by the docs cleanup, so this ADR is now their only surviving record.
- Old persisted prefs (`currentLanguage = "swahili"`, `settings.ttsEngine`): the language fallback in `language_provider.dart` resolves unknown values to `TargetLanguage.turkish`; the `ttsEngine` pref key is retained for back-compat reads but the toggle UI is removed.
### Verification

- `flutter analyze` clean; `flutter test` green (380 tests); Python tool tests green (13 tests).
