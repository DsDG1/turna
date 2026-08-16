# Official Anki spike fixtures

These packages were **created by the pinned official `rslib`**, not by Turna’s
legacy decoder. Content is invented study text (Chinese / Turkish / Sanskrit /
emoji). No private user decks.

| File | Notes | Cards | What it proves |
|---|---:|---:|---|
| `01-basic-unicode.apkg` | 1 | 1 | CJK, Turkish, Devanagari, NFC accents, emoji, `&amp;` |
| `02-basic-reversed.apkg` | 1 | 2 | Basic and reversed card directions |
| `03-optional-reversed.apkg` | 2 | 3 | Optional reverse field on / off |
| `04-cloze-multi-ord.apkg` | 1 | 2 | Cloze c1 / c2 ordinals |
| `05-frontside-css.apkg` | 1 | 1 | `FrontSide` + custom CSS |
| `06-media-paths.apkg` | 1 | 1 | Spaces, CJK, `#`, `%`, parentheses in filenames |
| `07-typed-answer.apkg` | 1 | 1 | `[[type:Back]]` typed-answer template |
| `08-scheduling.apkg` | 1 | 1 | Export with official scheduling fields |
| `09-legacy-package.apkg` | 1 | 1 | Official `legacy=true` (`.anki2`) package |

Large packages are **not committed**. Generate them when needed:

```text
./tool/official_anki_spike/generate_fixtures.sh --large 5000
./tool/official_anki_spike/generate_fixtures.sh --large 100000
```

Output: `generated/10-large-generated-<n>.apkg` (gitignored).

## Regeneration

```text
./tool/official_anki_spike/generate_fixtures.sh
dart run tool/official_anki_spike/verify_fixture_results.dart
```

Official export assigns new card IDs on every run, so the `.apkg` SHA-256
changes. After an intentional regen, commit the new packages, `expected/*.json`,
and `manifest.json` together.

`--large` only writes `generated/` and does not rewrite the frozen small set.

## Verification

`manifest.json` records SHA-256, note/card counts, and official render
assertions. `expected/*.json` is the official `render_existing_card` HTML
from the same generation run.

## License

Project-authored fixture text. Anki stock notetypes come from the pinned
AGPL `rslib` used to export the packages.
