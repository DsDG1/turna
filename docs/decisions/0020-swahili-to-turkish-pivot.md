# ADR 0020: Pivot the target language from Swahili to Turkish

- **Status:** Accepted
- **Date:** 2026-07-12
- **Supersedes:** [ADR 0001 — TTS language code](./0001-tts-language-code.md) (the `'sw'` decision), and abandons [ADR 0002 — Kannada→Swahili content replacement](./0002-content-replacement-progress-policy.md)

## Context

Varnamala was built Swahili-first: the enum, TTS language code, course loader
class (`SwahiliCourse`), asset directory (`assets/courses/swahili/`), database
file (`course.swahili.db`), bundled Piper Swahili voice, and ~16 hardcoded UI
strings all carried "swahili" / `'sw'` as the language identity. The bundled
vocabulary was still Kannada placeholder content; real Swahili vocabulary was
deferred to a future "content round" (see `future4.md` and ADR 0018).

The project pivots: **abandon Swahili and target Turkish instead.** There is no
real course content yet, so this round is a *framework re-skin* only — rewire
the whole stack to Turkish and ship an empty/minimal Turkish course scaffold.
Authoring real Turkish vocabulary, sections, and lessons is a separate later
round.

## Decision

1. **Scope:** framework re-skin + a minimal Turkish course scaffold
   (`assets/courses/turkish/` with one section, one legacy lesson, empty
   vocab/grammar/expressions). No real content authoring this round.

2. **TTS:** system / Google TTS only, language code `'tr'` (locale candidates
   `tr-TR` / `tr_TR`). **Remove the bundled Piper Swahili model entirely** —
   delete `lib/service/piper_swahili_tts.dart`, `lib/service/piper_tts_worker.dart`,
   the `assets/voices/swahili/` model, the `sherpa_onnx` dependency, the
   `TtsEngine` enum + engine toggle in settings, and the Piper fallback path in
   `AudioController`. If a future build wants an offline Turkish voice, a
   Turkish Piper model would be re-bundled as a new decision.

3. **Naming:** rename Swahili-specific identifiers to generic + Turkish, so
   future multi-language support is not blocked by a misleading single-language
   name:
   - `enum TargetLanguage { swahili }` → `{ turkish }`
   - `class SwahiliCourse` → `class CourseLoader` (generic)
   - `baseDir = 'assets/courses/swahili'` → `'assets/courses/turkish'`
   - parse/load helpers: `parseSwahiliSection` → `parseSection`,
     `loadSwahiliVocabulary` → `loadVocabulary`, `validateSwahiliCourse` →
     `validateCourse`, etc.
   - vocab/grammar/expression global maps: `swahiliVocabById` → `vocabById`,
     `swahiliGrammarPointById` → `grammarPointById`, `swahiliExpressionsById` →
     `expressionsById`
   - `SwahiliVocabAudioResolver` → `VocabAudioResolverImpl`
   - alphabet maps: `swahiliSounds/Vowels/Consonants` → `alphabetSounds/Vowels/Consonants`
   - DB filename `course.swahili.db` → `course.db`
   - default language preference `"swahili"` → `"turkish"`
   - `TtsPreferredStatus.swahiliDataMissing` → `turkishVoiceMissing`

4. **Content version:** the Turkish scaffold ships `index.json` version `5` +
   `expressions.json` version `1` (composite `5+1`), so existing installs
   reseed on upgrade via the existing content-version gate.

## Consequences

- The framework now points at Turkish with an empty course; real Turkish
  content is the next round's job (tracked as "future5 / content" in
  `CLAUDE.md`).
- Historical docs (`future2/3/4.md`, `dreamplan.md`, `Reference.md`, ADRs
  0001–0019, `docs/authoring/*`) are left as the historical record and are **not
  rewritten**; this ADR supersedes the live decisions they describe.
- The `transfer.md` plan at the repo root records the migration steps taken.
- Old persisted prefs (`currentLanguage = "swahili"`, `settings.ttsEngine`):
  the language fallback in `language_provider.dart` resolves unknown values to
  `TargetLanguage.turkish`; the `ttsEngine` pref key is retained for back-compat
  reads but the toggle UI is removed.

## Verification

- `flutter analyze` clean; `flutter test` green (380 tests); Python tool tests
  green (13 tests).
- `python3 tool/course_cli.py validate --course-dir assets/courses/turkish`
  passes against the scaffold.
- App boots past `CourseReadyGuard` with the empty Turkish course; splash /
  dictionary / settings copy all say "Turkish".