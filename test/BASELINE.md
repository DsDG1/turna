# Test Baseline

Generated: 2026-07-12 (MiniMax TTS migration; see ADR 0020)

## Results
- `flutter test`: **385 passed**
- `flutter analyze`: only info-level lint (no errors)
- Python: `python3 -m unittest discover -s test -p "*_test.py"` — 14 passed
- `tool/course_cli.py validate` passes against the 8-section Turkish course

## Notes
- Turkish course (`assets/courses/turkish/`) now ships **8 sections** with the
  CEFR progression A1/A1/A1/A2/B1/B1/B2/B2, wired with inter-section
  prerequisites. Section 1 ships a real **intro greetings lesson** (`s1-l2`,
  template `intro`, 3 subLessons: meet words / choose / practice) backed by
  8 vocab words + 2 expressions. Sections 2–8 are metadata-only placeholders
  (1 unit / 1 legacy MCQ lesson each, no vocab refs); full content authoring
  is a future round.
- Grammar points intentionally empty (`grammar_points.json`); this keeps a
  legitimately-empty table for the seeder-idempotent "empty table ≠ reseed"
  regression path.
- `seeder_idempotent_test.dart` asserts vocab + expressions are non-empty
  (real content) while grammar is empty; `course_cli_test.py` asserts the
  vocab CSV has a header + data rows (e.g. `w-merhaba`).
- Piper Swahili TTS + `sherpa_onnx` removed; TTS is system/Google `'tr'` only.

## Previous baselines
- MiniMax migration = 385; Pre-pivot = 373; Phase 24 = 372; Phase 23 = 358; Phase 22 = 350; Phase 21 = 342.