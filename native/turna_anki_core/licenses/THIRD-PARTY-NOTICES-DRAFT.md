# Third-party notices (draft)

Status: **draft for P0-012**. This is not a complete legal inventory.

## Official Anki core

- Project: [ankitects/anki](https://github.com/ankitects/anki)
- Pinned commit: `967aa0d578fc75181e292e95326f9b58698da25c`
- License: GNU Affero General Public License v3 or later
- Copy: `licenses/ANKI-LICENSE`

Turna links `rslib` through `bridge/`. Shipping a release binary that
includes this crate requires a corresponding source offer and notices.
Turna already uses GPLv3; that does **not** automatically satisfy AGPL
distribution obligations.

## Not yet inventoried

- Rust transitive crates from the pinned Anki workspace (`cargo license` / `cargo deny`)
- Official reviewer Web assets (not bundled in Phase 0)
- Any Turna patch against `anki/` (none yet)

P0-012 must replace this draft with a complete list and a
`GO` / `GO WITH CONDITIONS` / `NO-GO PENDING LEGAL REVIEW` conclusion.
