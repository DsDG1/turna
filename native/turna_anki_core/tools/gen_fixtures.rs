//! Generate official-rslib Anki fixture packages for Phase 0.
//!
//! Small packages are written next to `manifest.json`. Large packages go
//! to `generated/` (gitignored) because they are rebuilt on demand.

use std::fs;
use std::path::Path;
use std::path::PathBuf;
use std::process::Command;

use anki::collection::CollectionBuilder;
use anki::import_export::package::ExportAnkiPackageOptions;
use anki::prelude::*;
use anki::search::SortMode;
use serde_json::json;
use sha2::Digest;
use sha2::Sha256;

// Single source: the workspace build.rs reads `contract/BACKEND_COMMIT` and
// injects it — this bin must never carry its own pinned commit again.
const BACKEND_COMMIT: &str = env!("TURNA_ANKI_BACKEND_COMMIT");
const FIXTURE_VERSION: u32 = 1;

fn main() {
    let mut out = None;
    let mut large: Option<u32> = None;
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--out" => out = args.next().map(PathBuf::from),
            "--large" => {
                large = args.next().and_then(|s| s.parse().ok()).or(Some(5_000));
            }
            "--help" | "-h" => {
                eprintln!("usage: turna_anki_gen_fixtures --out <dir> [--large [count]]");
                return;
            }
            other => {
                eprintln!("unknown arg: {other}");
                std::process::exit(2);
            }
        }
    }
    let out = out.unwrap_or_else(|| {
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../test/fixtures/anki_official")
    });
    if let Err(err) = run(&out, large) {
        eprintln!("gen_fixtures failed: {err:?}");
        std::process::exit(1);
    }
}

fn run(out: &Path, large: Option<u32>) -> Result<()> {
    let packages_dir = out.join("packages");
    let expected_dir = out.join("expected");
    fs::create_dir_all(&packages_dir).expect("packages dir");
    fs::create_dir_all(&expected_dir).expect("expected dir");

    if let Some(count) = large {
        let generated = out.join("generated");
        fs::create_dir_all(&generated).expect("generated dir");
        let large_pkg = build_large(&generated, count)?;
        let large_manifest = json!({
            "fixtureVersion": FIXTURE_VERSION,
            "generatedWithAnkiCommit": BACKEND_COMMIT,
            "packages": [large_pkg],
        });
        fs::write(
            generated.join("manifest.json"),
            serde_json::to_vec_pretty(&large_manifest).unwrap(),
        )
        .expect("write generated manifest");
        println!("wrote {}", generated.join("manifest.json").display());
        return Ok(());
    }

    let packages = vec![
        build_unicode(&packages_dir, &expected_dir)?,
        build_reversed(&packages_dir, &expected_dir)?,
        build_optional_reversed(&packages_dir, &expected_dir)?,
        build_cloze(&packages_dir, &expected_dir)?,
        build_frontside_css(&packages_dir, &expected_dir)?,
        build_media(&packages_dir, &expected_dir)?,
        build_typed(&packages_dir, &expected_dir)?,
        build_scheduling(&packages_dir, &expected_dir)?,
        build_legacy(&packages_dir, &expected_dir)?,
        build_recognition_typein(&packages_dir, &expected_dir)?,
        build_recognition_optionpool(&packages_dir, &expected_dir)?,
        build_recognition_zh_composite(&packages_dir, &expected_dir)?,
    ];

    let git_describe = Command::new("git")
        .args(["-C", "anki", "describe", "--tags", "--always"])
        .current_dir(env!("CARGO_MANIFEST_DIR"))
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .unwrap_or_else(|| BACKEND_COMMIT.to_string());

    let manifest = json!({
        "fixtureVersion": FIXTURE_VERSION,
        "generatedWithAnkiCommit": BACKEND_COMMIT,
        "generatedWithAnkiDescribe": git_describe.trim(),
        "normalization": "official-html-as-rendered; no timestamp stripping required for these stock templates",
        "note": "Package SHA-256 is of the frozen committed artifact. Regenerating with official rslib assigns new card IDs and changes the hash; update the manifest after an intentional regen.",
        "packages": packages,
    });
    fs::write(
        out.join("manifest.json"),
        serde_json::to_vec_pretty(&manifest).unwrap(),
    )
    .expect("write manifest");
    println!("wrote {}", out.join("manifest.json").display());
    Ok(())
}

struct Col {
    col: Collection,
    root: PathBuf,
}

impl Col {
    fn open() -> Result<Self> {
        let root = std::env::temp_dir().join(format!(
            "turna-anki-fix-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(&root).expect("temp collection");
        let col = CollectionBuilder::new(root.join("collection.anki2"))
            .set_media_paths(
                root.join("collection.media"),
                root.join("collection.media.db2"),
            )
            .build()?;
        Ok(Self { col, root })
    }

    fn notetype(&mut self, name: &str) -> Result<Notetype> {
        self.col
            .get_notetype_by_name(name)?
            .map(|nt| (*nt).clone())
            .or_invalid(name)
    }

    fn add_basic(&mut self, notetype: &str, guid: &str, fields: &[&str]) -> Result<NoteId> {
        let nt = self.notetype(notetype)?;
        let mut note = nt.new_note();
        note.guid = guid.to_string();
        for (idx, field) in fields.iter().enumerate() {
            note.set_field(idx, *field)?;
        }
        self.col.add_note(&mut note, DeckId(1))?;
        Ok(note.id)
    }

    fn export(
        &mut self,
        path: &Path,
        legacy: bool,
        with_scheduling: bool,
        with_media: bool,
    ) -> Result<usize> {
        self.col.export_apkg(
            path,
            ExportAnkiPackageOptions {
                with_scheduling,
                with_deck_configs: true,
                with_media,
                legacy,
            },
            "",
            None,
        )
    }

    fn render_all(&mut self) -> Result<Vec<serde_json::Value>> {
        let ids = self.col.search_cards("", SortMode::NoOrder)?;
        let mut cards = Vec::new();
        for id in ids {
            let rendered = self.col.render_existing_card(id, false, false)?;
            cards.push(json!({
                "cardId": id.0,
                "questionHtml": rendered.question(),
                "answerHtml": rendered.answer(),
                "css": rendered.css,
                "isEmpty": rendered.is_empty,
            }));
        }
        Ok(cards)
    }
}

impl Drop for Col {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.root);
    }
}

fn sha256_file(path: &Path) -> Result<String> {
    let bytes = fs::read(path).expect("read package");
    Ok(hex::encode(Sha256::digest(bytes)))
}

fn write_package(
    packages_dir: &Path,
    expected_dir: &Path,
    file: &str,
    expected_notes: u32,
    expected_cards: u32,
    assertions: Vec<&str>,
    legacy: bool,
    with_scheduling: bool,
    with_media: bool,
    build: impl FnOnce(&mut Col) -> Result<()>,
) -> Result<serde_json::Value> {
    let mut col = Col::open()?;
    build(&mut col)?;
    let rendered = col.render_all()?;
    let package_path = packages_dir.join(file);
    let notes = col.export(&package_path, legacy, with_scheduling, with_media)?;
    if notes != expected_notes as usize {
        panic!("note count {notes} != {expected_notes}");
    }
    if rendered.len() != expected_cards as usize {
        panic!("card count {} != {expected_cards}", rendered.len());
    }
    let expected_path = expected_dir.join(file.replace(".apkg", ".json"));
    fs::write(
        &expected_path,
        serde_json::to_vec_pretty(&json!({
            "file": file,
            "cards": rendered,
        }))
        .unwrap(),
    )
    .expect("write expected");
    let sha = sha256_file(&package_path)?;
    println!(
        "  {file} notes={notes} cards={} sha256={sha}",
        rendered.len()
    );
    Ok(json!({
        "file": file,
        "sha256": sha,
        "expectedNotes": expected_notes,
        "expectedCards": expected_cards,
        "legacy": legacy,
        "withScheduling": with_scheduling,
        "withMedia": with_media,
        "expected": format!("expected/{}", expected_path.file_name().unwrap().to_string_lossy()),
        "assertions": assertions,
    }))
}

fn build_unicode(packages: &Path, expected: &Path) -> Result<serde_json::Value> {
    write_package(
        packages,
        expected,
        "01-basic-unicode.apkg",
        1,
        1,
        vec![
            "question-contains:你好",
            "question-contains:merhaba",
            "question-contains:İstanbul",
            "question-contains:नमस्ते",
            "question-contains:café",
            "question-contains:🙂",
            "answer-contains:&amp;",
            "answer-contains:Türkiye",
        ],
        false,
        false,
        false,
        |col| {
            col.add_basic(
                "Basic",
                "turnafix000001",
                &[
                    "你好 merhaba İstanbul नमस्ते café e\u{0301} 🙂",
                    "Türkiye &amp; friends",
                ],
            )?;
            Ok(())
        },
    )
}

fn build_reversed(packages: &Path, expected: &Path) -> Result<serde_json::Value> {
    write_package(
        packages,
        expected,
        "02-basic-reversed.apkg",
        1,
        2,
        vec![
            "question-contains:teşekkürler",
            "answer-contains:谢谢",
            "question-contains:谢谢",
            "answer-contains:teşekkürler",
        ],
        false,
        false,
        false,
        |col| {
            col.add_basic(
                "Basic (and reversed card)",
                "turnafix000002",
                &["teşekkürler", "谢谢"],
            )?;
            Ok(())
        },
    )
}

fn build_optional_reversed(packages: &Path, expected: &Path) -> Result<serde_json::Value> {
    write_package(
        packages,
        expected,
        "03-optional-reversed.apkg",
        2,
        3,
        vec!["question-contains:evet", "question-contains:hayır"],
        false,
        false,
        false,
        |col| {
            col.add_basic(
                "Basic (optional reversed card)",
                "turnafix000003",
                &["evet", "yes", "1"],
            )?;
            col.add_basic(
                "Basic (optional reversed card)",
                "turnafix000004",
                &["hayır", "no", ""],
            )?;
            Ok(())
        },
    )
}

fn build_cloze(packages: &Path, expected: &Path) -> Result<serde_json::Value> {
    write_package(
        packages,
        expected,
        "04-cloze-multi-ord.apkg",
        1,
        2,
        vec![
            "question-contains:data-ordinal=\"1\"",
            "question-contains:data-ordinal=\"2\"",
            "question-contains:Türkiye",
            "question-contains:安卡拉",
        ],
        false,
        false,
        false,
        |col| {
            col.add_basic(
                "Cloze",
                "turnafix000005",
                &["The capital of {{c1::Türkiye}} is {{c2::安卡拉}}.", ""],
            )?;
            Ok(())
        },
    )
}

fn build_frontside_css(packages: &Path, expected: &Path) -> Result<serde_json::Value> {
    write_package(
        packages,
        expected,
        "05-frontside-css.apkg",
        1,
        1,
        vec![
            "question-contains:FrontSideProbe",
            "answer-contains:FrontSideProbe",
            "css-contains:.turna-fixture",
        ],
        false,
        false,
        false,
        |col| {
            let mut nt = col.notetype("Basic")?;
            nt.config
                .css
                .push_str("\n.turna-fixture { color: #123456; }\n");
            col.col.update_notetype(&mut nt, true)?;
            col.add_basic(
                "Basic",
                "turnafix000006",
                &["FrontSideProbe", "BackSideProbe"],
            )?;
            Ok(())
        },
    )
}

fn build_media(packages: &Path, expected: &Path) -> Result<serde_json::Value> {
    write_package(
        packages,
        expected,
        "06-media-paths.apkg",
        1,
        1,
        vec![
            "question-contains:hello world.png",
            "answer-contains:paren (1).mp3",
            "question-contains:中文图片.jpg",
        ],
        false,
        false,
        true,
        |col| {
            let media = col.col.media()?;
            let names = [
                ("hello world.png", b"png-bytes" as &[u8]),
                ("中文图片.jpg", b"jpg-bytes"),
                ("hash#tag.bin", b"hash-bytes"),
                ("percent%20.txt", b"pct-bytes"),
                ("paren (1).mp3", b"mp3-bytes"),
            ];
            for (name, data) in names {
                media.add_file(name, data)?;
            }
            col.add_basic(
                "Basic",
                "turnafix000007",
                &[
                    r#"<img src="hello world.png"><img src="中文图片.jpg">"#,
                    r#"[sound:paren (1).mp3] # % ( )"#,
                ],
            )?;
            Ok(())
        },
    )
}

fn build_typed(packages: &Path, expected: &Path) -> Result<serde_json::Value> {
    write_package(
        packages,
        expected,
        "07-typed-answer.apkg",
        1,
        1,
        vec![
            "question-contains:[[type:Back]]",
            "question-contains:typed-front",
            "answer-contains:[[type:Back]]",
        ],
        false,
        false,
        false,
        |col| {
            col.add_basic(
                "Basic (type in the answer)",
                "turnafix000008",
                &["typed-front", "typed-back"],
            )?;
            Ok(())
        },
    )
}

fn build_scheduling(packages: &Path, expected: &Path) -> Result<serde_json::Value> {
    write_package(
        packages,
        expected,
        "08-scheduling.apkg",
        1,
        1,
        vec!["question-contains:sched-front"],
        false,
        true,
        false,
        |col| {
            col.add_basic("Basic", "turnafix000009", &["sched-front", "sched-back"])?;
            Ok(())
        },
    )
}

fn build_legacy(packages: &Path, expected: &Path) -> Result<serde_json::Value> {
    write_package(
        packages,
        expected,
        "09-legacy-package.apkg",
        1,
        1,
        vec!["question-contains:legacy-front"],
        true,
        false,
        false,
        |col| {
            col.add_basic("Basic", "turnafix000010", &["legacy-front", "legacy-back"])?;
            Ok(())
        },
    )
}

/// Add a custom notetype with the given fields and (name, qfmt, afmt)
/// templates. Used by the doc 37 recognition fixtures so template-derived
/// facts ({{type:}} filters, per-face field references) exercise the
/// recognizer against real collection data.
fn add_custom_notetype(
    col: &mut Col,
    name: &str,
    fields: &[&str],
    templates: &[(&str, &str, &str)],
) -> Result<()> {
    let mut nt = anki::notetype::Notetype::default();
    nt.name = name.to_string();
    for (idx, field) in fields.iter().enumerate() {
        nt.fields.push(anki::notetype::NoteField {
            ord: Some(idx as u32),
            name: field.to_string(),
            config: anki::notetype::NoteFieldConfig::default(),
        });
    }
    for (idx, (template_name, qfmt, afmt)) in templates.iter().enumerate() {
        nt.templates.push(anki::notetype::CardTemplate {
            ord: Some(idx as u32),
            mtime_secs: TimestampSecs::default(),
            usn: Usn::default(),
            name: template_name.to_string(),
            config: anki::notetype::CardTemplateConfig {
                q_format: qfmt.to_string(),
                a_format: afmt.to_string(),
                ..Default::default()
            },
        });
    }
    col.col.add_notetype(&mut nt, false)?;
    Ok(())
}

fn build_recognition_typein(packages: &Path, expected: &Path) -> Result<serde_json::Value> {
    write_package(
        packages,
        expected,
        "11-recognition-typein.apkg",
        2,
        2,
        vec![
            "question-contains:听写",
            "answer-contains:spell-probe",
            "templatefacts-typein:true",
        ],
        false,
        false,
        false,
        |col| {
            add_custom_notetype(
                col,
                "听写卡",
                &["提示", "拼写答案"],
                &[("Card 1", "{{提示}}", "{{FrontSide}}<hr>{{拼写答案}}{{type:拼写答案}}")],
            )?;
            col.add_basic("听写卡", "turnafix000011", &["听写：spell-probe", "答案甲"])?;
            col.add_basic("听写卡", "turnafix000012", &["听写：second-probe", "答案乙"])?;
            Ok(())
        },
    )
}

fn build_recognition_optionpool(packages: &Path, expected: &Path) -> Result<serde_json::Value> {
    write_package(
        packages,
        expected,
        "12-recognition-optionpool.apkg",
        2,
        2,
        vec![
            "question-contains:首都",
            "answer-contains:巴黎",
            "recognizer:choice",
        ],
        false,
        false,
        false,
        |col| {
            add_custom_notetype(
                col,
                "题库单选",
                &["题干", "选项", "答案"],
                &[("Card 1", "{{题干}}", "{{题干}}<hr>{{答案}}")],
            )?;
            col.add_basic(
                "题库单选",
                "turnafix000013",
                &["法国的首都是哪里？", "巴黎|伦敦|柏林|马德里", "巴黎"],
            )?;
            col.add_basic(
                "题库单选",
                "turnafix000014",
                &["土耳其的首都是哪里？", "安卡拉|伊斯坦布尔|伊兹密尔|科尼亚", "安卡拉"],
            )?;
            Ok(())
        },
    )
}

fn build_recognition_zh_composite(packages: &Path, expected: &Path) -> Result<serde_json::Value> {
    write_package(
        packages,
        expected,
        "13-recognition-zh-composite.apkg",
        2,
        2,
        vec![
            "question-contains:复合",
            "answer-contains:composite",
            "recognizer:basicPair",
        ],
        false,
        false,
        false,
        |col| {
            add_custom_notetype(
                col,
                "复合字段卡",
                &["词汇表汉字", "词汇表释义", "读音标注"],
                &[("Card 1", "{{词汇表汉字}}", "{{FrontSide}}<hr>{{词汇表释义}}{{读音标注}}")],
            )?;
            col.add_basic("复合字段卡", "turnafix000015", &["复合", "composite", "fùhé"])?;
            col.add_basic("复合字段卡", "turnafix000016", &["结构", "structure", "jiégòu"])?;
            Ok(())
        },
    )
}

/// Large fixture: notes spread across a three-level `S{i}::U{j}::L{k}` deck
/// tree. Real decks are trees — the first on-device night showed a flat
/// 100k single deck is a UI-overload artifact, not a realistic shape
/// (docs/ankiUpdate/v2-first-device-findings.md F3). Shape: ~100 cards per
/// leaf; leaves = clamp(ceil(count/100), 1, 1000) laid out row-major over a
/// 10×10 section×unit grid (1000 leaves = S0..S9 × U0..U9 × L0..L9), the
/// remainder goes to the last leaf. Three `::` segments hit the v2 view
/// rebuilder's path derivation (section=first, unit=second, lesson=last)
/// and — being a multi-level tree — the import writes no derived placement
/// override key, exercising the pure path-derivation branch.
fn build_large(generated: &Path, count: u32) -> Result<serde_json::Value> {
    let file = format!("10-large-generated-{count}.apkg");
    let mut col = Col::open()?;
    let nt = col.notetype("Basic")?;
    let leaves = count.div_ceil(100).clamp(1, 1000);
    let cards_per_leaf = count.div_ceil(leaves);
    let mut leaf_ids = Vec::with_capacity(leaves as usize);
    for leaf in 0..leaves {
        let section = leaf / 100;
        let unit = (leaf / 10) % 10;
        let lesson = leaf % 10;
        let name = format!("S{section}::U{unit}::L{lesson}");
        leaf_ids.push(col.col.get_or_create_normal_deck(&name)?.id);
    }
    let last_leaf = leaf_ids.last().copied().unwrap_or(DeckId(1));
    let mut requests = Vec::with_capacity(count as usize);
    for index in 0..count {
        let mut note = nt.new_note();
        note.guid = format!("turnalrg{index:010}");
        note.set_field(0, format!("Q{index}"))?;
        note.set_field(1, format!("A{index}"))?;
        let leaf = (index / cards_per_leaf) as usize;
        requests.push(anki::notes::AddNoteRequest {
            note,
            deck_id: if leaf < leaf_ids.len() {
                leaf_ids[leaf]
            } else {
                last_leaf
            },
        });
    }
    col.col.add_notes(&mut requests)?;
    let path = generated.join(&file);
    let notes = col.export(&path, false, false, false)?;
    if notes != count as usize {
        panic!("large note count mismatch: {notes} != {count}");
    }
    let sha = sha256_file(&path)?;
    println!("  {file} notes={notes} sha256={sha}");
    Ok(json!({
        "file": format!("generated/{file}"),
        "sha256": sha,
        "expectedNotes": count,
        "expectedCards": count,
        "legacy": false,
        "generated": true,
        "deckTree": {
            "shape": "S{s}::U{u}::L{l}",
            "leaves": leaves,
            "cardsPerLeaf": cards_per_leaf,
        },
        "assertions": ["question-contains:Q0"],
    }))
}
