//! Contract 1.2+ read-only projection queries. Never returns qfmt/afmt/CSS
//! text, revlog, or scheduling. Contract 1.9 adds derived `templateFacts`
//! (field ords + filter booleans per template face); raw template text
//! stays inside the engine and only structural facts leave it.

use std::collections::HashMap;

use regex::Regex;
use serde::Deserialize;
use serde_json::json;
use serde_json::Value;
use sha2::Digest;
use sha2::Sha256;

use anki::notetype::CardRequirementKind;
use anki::prelude::*;
use anki::search::SortMode;
use anki::template::FieldRequirements;
use anki::template::ParsedTemplate;

use crate::engine::slot;
use crate::engine::Engine;
use crate::engine::parse_req;
use crate::engine::parse_req_or_default;
use crate::engine::MAX_RESPONSE_BYTES;
use crate::engine::STATUS_BACKEND_PANIC;
use crate::engine::STATUS_INVALID_ARGUMENT;
use crate::engine::STATUS_INTERNAL_ERROR;
use crate::engine::STATUS_PROJECTION_SNAPSHOT_STALE;
use crate::ops::map_anki_error;
use crate::ops::require_open;
use crate::query::split_note_tags;

const DEFAULT_SAMPLE_LIMIT: usize = 3;
const MAX_SAMPLE_LIMIT: usize = 30;
const MAX_BATCH: usize = 500;
const MAX_FIELD_BYTES: usize = 8 * 1024;
/// See `query::SQL_CHUNK`: inlined id lists chunked under the variable cap.
const SQL_CHUNK: usize = 500;

#[derive(Debug, Clone)]
pub struct ProjectionSnapshot {
    pub token: String,
    pub collection_generation: u64,
    pub card_set_fingerprint: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct SchemaRequest {
    #[serde(default)]
    notetype_ids: Vec<i64>,
    #[serde(default)]
    include_samples: bool,
    #[serde(default)]
    sample_limit: Option<usize>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct BeginReadRequest {
    card_set_fingerprint: String,
    #[serde(default)]
    mapping_version: i64,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RowsRequest {
    card_ids: Vec<i64>,
    snapshot_token: String,
}

fn truncate_field(raw: &str) -> (String, bool) {
    if raw.len() <= MAX_FIELD_BYTES {
        return (raw.to_string(), false);
    }
    let mut end = MAX_FIELD_BYTES;
    while end > 0 && !raw.is_char_boundary(end) {
        end -= 1;
    }
    (raw[..end].to_string(), true)
}

fn schema_fingerprint(name: &str, field_names: &[String], template_names: &[String]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(name.as_bytes());
    hasher.update([0]);
    for field in field_names {
        hasher.update(field.as_bytes());
        hasher.update([0]);
    }
    for template in template_names {
        hasher.update(template.as_bytes());
        hasher.update([0]);
    }
    hex::encode(hasher.finalize())
}

/// Field ords whose non-emptiness the template face depends on, computed
/// exactly like rslib's `Notetype::updated_requirements` (question side) so
/// the derived facts can never disagree with the stored `config.reqs`.
fn template_field_ords(text: &str, field_map: &HashMap<&str, u16>) -> Vec<u16> {
    let Ok(parsed) = ParsedTemplate::from_text(text) else {
        return Vec::new();
    };
    let mut ords = match parsed.requirements(field_map) {
        FieldRequirements::Any(set) | FieldRequirements::All(set) => {
            set.into_iter().collect::<Vec<u16>>()
        }
        FieldRequirements::None => Vec::new(),
    };
    ords.sort_unstable();
    ords
}

/// Field names referenced through `{{<filter>:…}}` on a template face.
fn filter_field_targets(text: &str, filter: &str) -> Vec<String> {
    let marker = format!("{{{{{filter}:");
    let mut out = Vec::new();
    let mut rest = text;
    while let Some(pos) = rest.find(&marker) {
        let after = &rest[pos + marker.len()..];
        let Some(end) = after.find("}}") else {
            break;
        };
        // Filters chain left-to-right (`{{tts:en_US:Field}}`); the field is
        // always the last `:`-separated segment.
        if let Some(field) = after[..end].rsplit(':').next() {
            let field = field.trim();
            if !field.is_empty() && !out.iter().any(|f: &String| f == field) {
                out.push(field.to_string());
            }
        }
        rest = &after[end + 2..];
    }
    out
}

fn template_has_script(text: &str) -> bool {
    text.contains("<script")
        || text.contains("javascript:")
        || {
            static RE: std::sync::LazyLock<Regex> =
                std::sync::LazyLock::new(|| Regex::new(r"(?i)on[a-z]+\s*=").unwrap());
            RE.is_match(text)
        }
}

fn template_has_complex_html(text: &str) -> bool {
    static RE: std::sync::LazyLock<Regex> = std::sync::LazyLock::new(|| {
        Regex::new(r"(?i)<(table|svg|audio|video|iframe|canvas|object|embed|form|input|button)\b")
            .unwrap()
    });
    RE.is_match(text)
}

/// Derived per-notetype structural facts for recognition (contract 1.9).
/// Key names deliberately avoid the `forbidden_keys` vocabulary; nothing
/// here can reconstruct the template text.
fn template_facts(nt: &anki::notetype::Notetype) -> Value {
    let field_map: HashMap<&str, u16> = nt
        .fields
        .iter()
        .enumerate()
        .map(|(idx, field)| (field.name.as_str(), idx as u16))
        .collect();
    let mut hasher = Sha256::new();
    let mut templates = Vec::new();
    for (ord, template) in nt.templates.iter().enumerate() {
        let q = &template.config.q_format;
        let a = &template.config.a_format;
        hasher.update(template.name.as_bytes());
        hasher.update([0]);
        hasher.update(q.as_bytes());
        hasher.update([0]);
        hasher.update(a.as_bytes());
        hasher.update([0]);
        let mut tts = filter_field_targets(q, "tts");
        tts.extend(filter_field_targets(a, "tts"));
        let mut hint = filter_field_targets(q, "hint");
        hint.extend(filter_field_targets(a, "hint"));
        let script = template_has_script(q) || template_has_script(a);
        let complex = template_has_complex_html(q) || template_has_complex_html(a);
        hasher.update([u8::from(script), u8::from(complex)]);
        templates.push(json!({
            "ord": ord as u32,
            "name": template.name,
            "frontFields": template_field_ords(q, &field_map),
            "backFields": template_field_ords(a, &field_map),
            "filters": {
                "typeIn": q.contains("{{type:") || a.contains("{{type:"),
                "tts": tts,
                "hint": hint,
                "script": script,
                "complexHtml": complex,
            },
        }));
    }
    let mut reqs = Vec::new();
    for req in &nt.config.reqs {
        hasher.update(req.card_ord.to_le_bytes());
        hasher.update([req.kind as u8]);
        for ord in &req.field_ords {
            hasher.update(ord.to_le_bytes());
        }
        hasher.update([0]);
        let kind = match CardRequirementKind::try_from(req.kind) {
            Ok(CardRequirementKind::All) => "ALL",
            Ok(CardRequirementKind::Any) => "ANY",
            _ => "NONE",
        };
        let mut field_ords = req.field_ords.clone();
        field_ords.sort_unstable();
        reqs.push(json!({
            "cardOrd": req.card_ord,
            "kind": kind,
            "fieldOrds": field_ords,
        }));
    }
    json!({
        "hash": hex::encode(hasher.finalize()),
        "templates": templates,
        "reqs": reqs,
    })
}

#[cfg(test)]
fn source_fingerprint(note: &Note, deck_path: &[String], ordinal: u16) -> String {
    source_fingerprint_parts(
        &note.guid,
        &note.fields(),
        &note.tags,
        deck_path,
        ordinal,
    )
}

fn source_fingerprint_parts(
    guid: &str,
    fields: &[String],
    tags: &[String],
    deck_path: &[String],
    ordinal: u16,
) -> String {
    let mut hasher = Sha256::new();
    hasher.update(guid.as_bytes());
    hasher.update([0]);
    hasher.update(ordinal.to_le_bytes());
    hasher.update([0]);
    for part in deck_path {
        hasher.update(part.as_bytes());
        hasher.update([0]);
    }
    for field in fields {
        hasher.update(field.as_bytes());
        hasher.update([0]);
    }
    for tag in tags {
        hasher.update(tag.as_bytes());
        hasher.update([1]);
    }
    hex::encode(hasher.finalize())
}

fn token_for(generation: u64, fingerprint: &str, mapping_version: i64) -> String {
    let mut hasher = Sha256::new();
    hasher.update(generation.to_le_bytes());
    hasher.update(fingerprint.as_bytes());
    hasher.update(mapping_version.to_le_bytes());
    hex::encode(hasher.finalize())
}

fn forbidden_keys(value: &Value) -> bool {
    match value {
        Value::Object(map) => map.keys().any(|k| {
            matches!(
                k.as_str(),
                "qfmt" | "afmt" | "css" | "revlog" | "scheduling" | "queue" | "due"
            ) || map.values().any(forbidden_keys)
        }),
        Value::Array(items) => items.iter().any(forbidden_keys),
        _ => false,
    }
}

pub fn get_projection_schemas(handle: u64, request: &[u8]) -> Result<Value, i32> {
    let parsed: SchemaRequest = parse_req_or_default(
        request,
        SchemaRequest {
            notetype_ids: Vec::new(),
            include_samples: false,
            sample_limit: None,
        },
    )?;
    let sample_limit = parsed
        .sample_limit
        .unwrap_or(DEFAULT_SAMPLE_LIMIT)
        .clamp(1, MAX_SAMPLE_LIMIT);
    let slot = slot(handle)?;
    let mut engine = require_open(&slot)?;
    let col = engine.open_col()?;
    let wanted = if parsed.notetype_ids.is_empty() {
        col.storage
            .get_notetype_use_counts()
            .map_err(map_anki_error)?
            .into_iter()
            .map(|(id, _, _)| id)
            .collect::<Vec<_>>()
    } else {
        parsed
            .notetype_ids
            .into_iter()
            .map(NotetypeId)
            .collect::<Vec<_>>()
    };
    let mut schemas = Vec::new();
    for ntid in wanted {
        let Some(nt) = col.get_notetype(ntid).map_err(map_anki_error)? else {
            continue;
        };
        let field_names: Vec<String> = nt.fields.iter().map(|f| f.name.clone()).collect();
        let template_names: Vec<String> = nt.templates.iter().map(|t| t.name.clone()).collect();
        let kind = if nt.config.kind() == anki::notetype::NotetypeKind::Cloze {
            "cloze"
        } else {
            "normal"
        };
        let fingerprint = schema_fingerprint(&nt.name, &field_names, &template_names);
        let mut schema = json!({
            "notetypeId": ntid.0,
            "name": nt.name,
            "kind": kind,
            "fieldNames": field_names,
            "templateNames": template_names,
            "schemaFingerprint": fingerprint,
            "templateFacts": template_facts(&nt),
        });
        if parsed.include_samples {
            let search = format!("mid:{}", ntid.0);
            let note_ids = col
                .search_notes(&search, SortMode::NoOrder)
                .map_err(map_anki_error)?;
            let mut samples = Vec::new();
            for nid in note_ids.into_iter().take(sample_limit) {
                let Some(note) = col.storage.get_note(nid).map_err(map_anki_error)? else {
                    continue;
                };
                let mut fields = Vec::new();
                let mut truncated = false;
                for field in note.fields() {
                    let (value, cut) = truncate_field(field);
                    truncated |= cut;
                    fields.push(json!(value));
                }
                samples.push(json!({
                    "noteId": nid.0,
                    "fields": fields,
                    "truncated": truncated,
                }));
            }
            schema["samples"] = json!(samples);
        }
        schemas.push(schema);
    }
    let payload = json!({ "schemas": schemas });
    if forbidden_keys(&payload) {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    Ok(payload)
}

pub fn begin_projection_read(handle: u64, request: &[u8]) -> Result<Value, i32> {
    let parsed: BeginReadRequest =
        parse_req(request)?;
    if parsed.card_set_fingerprint.is_empty() {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    let slot = slot(handle)?;
    let mut engine = require_open(&slot)?;
    let generation = engine.content_generation;
    let token = token_for(
        generation,
        &parsed.card_set_fingerprint,
        parsed.mapping_version,
    );
    engine.projection_snapshot = Some(ProjectionSnapshot {
        token: token.clone(),
        collection_generation: generation,
        card_set_fingerprint: parsed.card_set_fingerprint,
    });
    Ok(json!({
        "snapshotToken": token,
        "collectionGeneration": generation,
        "backendCommit": crate::contract::backend_commit(),
    }))
}

pub(crate) struct ProjectionCardSql {
    pub note_id: i64,
    pub deck_id: i64,
    pub template_ord: i64,
}

pub(crate) struct ProjectionNoteSql {
    pub guid: String,
    pub notetype_id: i64,
    pub tags: String,
    /// `notes.flds` split on `\x1f` — Anki's stable field separator.
    pub fields: Vec<String>,
}

/// Cards for the batch in one chunked `IN (...)` sweep (doc 38 P3-3).
pub(crate) fn projection_card_rows(
    col: &Collection,
    card_ids: &[i64],
) -> Result<HashMap<i64, ProjectionCardSql>, i32> {
    let mut rows: HashMap<i64, ProjectionCardSql> = HashMap::new();
    let db = col.storage.db();
    for chunk in card_ids.chunks(SQL_CHUNK) {
        let placeholders = vec!["?"; chunk.len()].join(",");
        let sql =
            format!("SELECT id, nid, did, ord FROM cards WHERE id IN ({placeholders})");
        let mut stmt = db.prepare(&sql).map_err(|_| STATUS_INTERNAL_ERROR)?;
        let found = stmt
            .query_map(rusqlite::params_from_iter(chunk.iter()), |row| {
                Ok((
                    row.get::<_, i64>(0)?,
                    ProjectionCardSql {
                        note_id: row.get(1)?,
                        deck_id: row.get(2)?,
                        template_ord: row.get(3)?,
                    },
                ))
            })
            .map_err(|_| STATUS_INTERNAL_ERROR)?;
        for row in found {
            let (card_id, card) = row.map_err(|_| STATUS_INTERNAL_ERROR)?;
            rows.insert(card_id, card);
        }
    }
    Ok(rows)
}

/// Notes for the batch in one chunked `IN (...)` sweep (doc 38 P3-3).
pub(crate) fn projection_note_rows(
    col: &Collection,
    note_ids: &[i64],
) -> Result<HashMap<i64, ProjectionNoteSql>, i32> {
    let mut rows: HashMap<i64, ProjectionNoteSql> = HashMap::new();
    let db = col.storage.db();
    for chunk in note_ids.chunks(SQL_CHUNK) {
        let placeholders = vec!["?"; chunk.len()].join(",");
        let sql = format!(
            "SELECT id, guid, mid, tags, flds FROM notes WHERE id IN ({placeholders})"
        );
        let mut stmt = db.prepare(&sql).map_err(|_| STATUS_INTERNAL_ERROR)?;
        let found = stmt
            .query_map(rusqlite::params_from_iter(chunk.iter()), |row| {
                Ok((
                    row.get::<_, i64>(0)?,
                    ProjectionNoteSql {
                        guid: row.get(1)?,
                        notetype_id: row.get(2)?,
                        tags: row.get(3)?,
                        fields: row
                            .get::<_, String>(4)?
                            .split('\x1f')
                            .map(str::to_string)
                            .collect(),
                    },
                ))
            })
            .map_err(|_| STATUS_INTERNAL_ERROR)?;
        for row in found {
            let (note_id, note) = row.map_err(|_| STATUS_INTERNAL_ERROR)?;
            rows.insert(note_id, note);
        }
    }
    Ok(rows)
}

fn require_snapshot<'a>(engine: &'a Engine, token: &str) -> Result<&'a ProjectionSnapshot, i32> {
    let snap = engine
        .projection_snapshot
        .as_ref()
        .ok_or(STATUS_PROJECTION_SNAPSHOT_STALE)?;
    if snap.token != token
        || snap.collection_generation != engine.content_generation
        || snap.card_set_fingerprint.is_empty()
    {
        return Err(STATUS_PROJECTION_SNAPSHOT_STALE);
    }
    Ok(snap)
}

pub fn get_projection_rows_batch(handle: u64, request: &[u8]) -> Result<Value, i32> {
    let parsed: RowsRequest =
        parse_req(request)?;
    if parsed.card_ids.len() > MAX_BATCH {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    let card_ids = parsed.card_ids;
    let slot = slot(handle)?;
    let mut engine = require_open(&slot)?;
    let _ = require_snapshot(&engine, &parsed.snapshot_token)?;
    let col = engine.open_col()?;
    let card_rows = projection_card_rows(col, &card_ids)?;
    let mut note_ids: Vec<i64> = card_rows.values().map(|row| row.note_id).collect();
    note_ids.sort_unstable();
    note_ids.dedup();
    let note_rows = projection_note_rows(col, &note_ids)?;
    let mut deck_paths: HashMap<i64, Vec<String>> = HashMap::new();
    let mut rows = Vec::new();
    let mut missing = Vec::new();
    for card_id in card_ids {
        let Some(card) = card_rows.get(&card_id) else {
            missing.push(card_id);
            continue;
        };
        let Some(note) = note_rows.get(&card.note_id) else {
            missing.push(card_id);
            continue;
        };
        let deck_path = match deck_paths.entry(card.deck_id) {
            std::collections::hash_map::Entry::Vacant(entry) => {
                let path = match col.get_deck(DeckId(card.deck_id)).map_err(map_anki_error)? {
                    Some(deck) => deck
                        .name
                        .human_name()
                        .split("::")
                        .map(|s| s.to_string())
                        .collect::<Vec<_>>(),
                    None => vec!["Recovered".to_string()],
                };
                entry.insert(path)
            }
            std::collections::hash_map::Entry::Occupied(entry) => entry.into_mut(),
        };
        // The fingerprint hashes the raw (untruncated) fields — the truncated
        // copies below are display-only, and the reference implementation
        // hashes `Note::fields()` directly.
        let ordinal: u16 = card.template_ord.clamp(0, u16::MAX as i64) as u16;
        let tags = split_note_tags(&note.tags);
        let fingerprint = source_fingerprint_parts(
            &note.guid,
            &note.fields,
            &tags,
            deck_path,
            ordinal,
        );
        let mut fields = Vec::new();
        let mut truncated = false;
        for field in &note.fields {
            let (value, cut) = truncate_field(field);
            truncated |= cut;
            fields.push(value);
        }
        rows.push(json!({
            "cardId": card_id,
            "noteId": card.note_id,
            "noteGuid": note.guid,
            "notetypeId": note.notetype_id,
            "deckId": card.deck_id,
            "deckPath": deck_path,
            "templateOrdinal": ordinal,
            "tags": tags,
            "fields": fields,
            "truncated": truncated,
            "sourceFingerprint": fingerprint,
        }));
    }
    let payload = json!({
        "rows": rows,
        "missingCardIds": missing,
    });
    if forbidden_keys(&payload) {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    let encoded = serde_json::to_vec(&payload).map_err(|_| STATUS_BACKEND_PANIC)?;
    if encoded.len() > MAX_RESPONSE_BYTES {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    Ok(payload)
}

/// Doc 38 P3 parity oracle: the pre-batching per-row implementation, kept
/// verbatim. Delete at the next rslib pin refresh once the parity test has
/// passed on the toolchain host.
#[cfg(test)]
fn reference_rows(col: &mut Collection, card_ids: &[i64]) -> Result<Value, i32> {
    let mut rows = Vec::new();
    let mut missing = Vec::new();
    for card_id in card_ids {
        let Some(card) = col
            .storage
            .get_card(CardId(*card_id))
            .map_err(map_anki_error)?
        else {
            missing.push(*card_id);
            continue;
        };
        let Some(note) = col
            .storage
            .get_note(card.note_id())
            .map_err(map_anki_error)?
        else {
            missing.push(*card_id);
            continue;
        };
        let deck_path = match col.get_deck(card.deck_id()).map_err(map_anki_error)? {
            Some(deck) => deck
                .name
                .human_name()
                .split("::")
                .map(|s| s.to_string())
                .collect::<Vec<_>>(),
            None => vec!["Recovered".to_string()],
        };
        let mut fields = Vec::new();
        let mut truncated = false;
        for field in note.fields() {
            let (value, cut) = truncate_field(field);
            truncated |= cut;
            fields.push(value);
        }
        let ordinal = card.template_idx();
        let fingerprint = source_fingerprint(&note, &deck_path, ordinal);
        rows.push(json!({
            "cardId": card_id,
            "noteId": note.id.0,
            "noteGuid": note.guid,
            "notetypeId": note.notetype_id.0,
            "deckId": card.deck_id().0,
            "deckPath": deck_path,
            "templateOrdinal": ordinal,
            "tags": note.tags,
            "fields": fields,
            "truncated": truncated,
            "sourceFingerprint": fingerprint,
        }));
    }
    Ok(json!({
        "rows": rows,
        "missingCardIds": missing,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::engine::dispatch;
    use crate::engine::free_engine;
    use crate::engine::OP_BEGIN_PROJECTION_READ;
    use crate::engine::OP_GET_PROJECTION_ROWS_BATCH;
    use crate::engine::OP_GET_PROJECTION_SCHEMAS;
    use crate::engine::OP_IMPORT_PACKAGE;
    use std::fs;
    use std::path::PathBuf;

    fn package_path(name: &str) -> PathBuf {
        crate::test_support::package_path(name)
    }

    fn temp_open() -> (PathBuf, u64) {
        let (root, handle, _) = crate::test_support::temp_open("proj");
        (root, handle)
    }

    fn call(handle: u64, op: u32, body: Value) -> Result<Value, i32> {
        dispatch(handle, op, &serde_json::to_vec(&body).unwrap())
    }

    #[test]
    fn projection_schema_and_rows_omit_forbidden_fields() {
        let pkg = package_path("01-basic-unicode.apkg");
        if !pkg.exists() {
            return;
        }
        let (root, handle) = temp_open();
        call(
            handle,
            OP_IMPORT_PACKAGE,
            json!({
                "package_path": pkg.to_string_lossy(),
                "with_scheduling": false,
                "with_deck_configs": true,
            }),
        )
        .unwrap();
        let schemas = call(
            handle,
            OP_GET_PROJECTION_SCHEMAS,
            json!({ "includeSamples": true, "sampleLimit": 3 }),
        )
        .unwrap();
        assert!(!forbidden_keys(&schemas));
        let first = &schemas["schemas"][0];
        assert!(first.get("qfmt").is_none());
        assert!(first.get("afmt").is_none());
        assert!(first.get("css").is_none());
        assert!(first["samples"].as_array().unwrap().len() <= 3);

        let begin = call(
            handle,
            OP_BEGIN_PROJECTION_READ,
            json!({ "cardSetFingerprint": "abc", "mappingVersion": 1 }),
        )
        .unwrap();
        let token = begin["snapshotToken"].as_str().unwrap();
        let rows = call(
            handle,
            OP_GET_PROJECTION_ROWS_BATCH,
            json!({ "cardIds": [1, 2, 3, 999999], "snapshotToken": token }),
        )
        .unwrap();
        assert!(!forbidden_keys(&rows));
        assert!(rows["missingCardIds"].as_array().is_some());
        free_engine(handle).unwrap();
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn template_facts_derive_structure_without_raw_templates() {
        let pkg = package_path("01-basic-unicode.apkg");
        if !pkg.exists() {
            return;
        }
        let (root, handle) = temp_open();
        call(
            handle,
            OP_IMPORT_PACKAGE,
            json!({
                "package_path": pkg.to_string_lossy(),
                "with_scheduling": false,
                "with_deck_configs": true,
            }),
        )
        .unwrap();
        let schemas = call(handle, OP_GET_PROJECTION_SCHEMAS, json!({})).unwrap();
        let first = &schemas["schemas"][0];
        let facts = &first["templateFacts"];
        assert!(facts["hash"].as_str().unwrap().len() == 64);
        // Basic front template renders with Front only; the answer side
        // references Front (via FrontSide is special, not a field) and Back.
        let template = &facts["templates"][0];
        assert_eq!(template["frontFields"], json!([0]));
        assert_eq!(template["backFields"], json!([0, 1]));
        assert_eq!(template["filters"]["typeIn"], json!(false));
        assert_eq!(facts["reqs"][0]["kind"], json!("ANY"));
        assert_eq!(facts["reqs"][0]["fieldOrds"], json!([0]));
        // The derived object must never leak raw template text keys.
        assert!(!forbidden_keys(&json!({ "templateFacts": facts })));
        free_engine(handle).unwrap();
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn template_facts_flag_typein_filter() {
        let pkg = package_path("07-typed-answer.apkg");
        if !pkg.exists() {
            return;
        }
        let (root, handle) = temp_open();
        call(
            handle,
            OP_IMPORT_PACKAGE,
            json!({
                "package_path": pkg.to_string_lossy(),
                "with_scheduling": false,
                "with_deck_configs": true,
            }),
        )
        .unwrap();
        let schemas = call(handle, OP_GET_PROJECTION_SCHEMAS, json!({})).unwrap();
        let first = &schemas["schemas"][0];
        let facts = &first["templateFacts"];
        assert_eq!(facts["templates"][0]["filters"]["typeIn"], json!(true));
        free_engine(handle).unwrap();
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn sample_limit_clamps_to_30() {
        let pkg = package_path("01-basic-unicode.apkg");
        if !pkg.exists() {
            return;
        }
        let (root, handle) = temp_open();
        call(
            handle,
            OP_IMPORT_PACKAGE,
            json!({
                "package_path": pkg.to_string_lossy(),
                "with_scheduling": false,
                "with_deck_configs": true,
            }),
        )
        .unwrap();
        let schemas = call(
            handle,
            OP_GET_PROJECTION_SCHEMAS,
            json!({ "includeSamples": true, "sampleLimit": 100 }),
        )
        .unwrap();
        let first = &schemas["schemas"][0];
        assert!(first["samples"].as_array().unwrap().len() <= MAX_SAMPLE_LIMIT);
        free_engine(handle).unwrap();
        let _ = fs::remove_dir_all(root);
    }

    /// Doc 38 P2: answering only bumps `page_generation`; the content
    /// generation (and therefore this snapshot) survives. Deleting the note
    /// bumps the content generation and must stale the snapshot.
    #[test]
    fn answer_keeps_projection_snapshot_but_delete_invalidates() {
        let pkg = package_path("08-scheduling.apkg");
        if !pkg.exists() {
            return;
        }
        let (root, handle) = temp_open();
        call(
            handle,
            OP_IMPORT_PACKAGE,
            json!({
                "package_path": pkg.to_string_lossy(),
                "with_scheduling": true,
                "with_deck_configs": true,
            }),
        )
        .unwrap();
        let begin = call(
            handle,
            OP_BEGIN_PROJECTION_READ,
            json!({ "cardSetFingerprint": "abc", "mappingVersion": 1 }),
        )
        .unwrap();
        let token = begin["snapshotToken"].as_str().unwrap().to_string();

        call(handle, crate::engine::OP_SET_CURRENT_DECK, json!({"deckId": 1})).unwrap();
        let queue = call(
            handle,
            crate::engine::OP_GET_REVIEW_QUEUE,
            json!({"fetchLimit": 1}),
        )
        .unwrap();
        let card_id = queue["cards"][0]["cardId"].as_i64().unwrap();
        let answer_token = queue["cards"][0]["answerToken"].as_str().unwrap();
        call(
            handle,
            crate::engine::OP_ANSWER_CARD,
            json!({
                "cardId": card_id,
                "rating": "good",
                "answerToken": answer_token,
                "millisecondsTaken": 1000
            }),
        )
        .unwrap();

        let rows = call(
            handle,
            OP_GET_PROJECTION_ROWS_BATCH,
            json!({ "cardIds": [card_id], "snapshotToken": token }),
        )
        .unwrap();
        assert_eq!(rows["rows"].as_array().unwrap().len(), 1);

        let descriptors = call(
            handle,
            crate::engine::OP_GET_CARD_DESCRIPTORS_BATCH,
            json!({ "card_ids": [card_id] }),
        )
        .unwrap();
        let note_id = descriptors["cards"][0]["noteId"].as_i64().unwrap();
        call(
            handle,
            crate::engine::OP_DELETE_NOTES,
            json!({ "noteIds": [note_id] }),
        )
        .unwrap();
        let err = call(
            handle,
            OP_GET_PROJECTION_ROWS_BATCH,
            json!({ "cardIds": [card_id], "snapshotToken": token }),
        )
        .unwrap_err();
        assert_eq!(err, STATUS_PROJECTION_SNAPSHOT_STALE);
        free_engine(handle).unwrap();
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn stale_snapshot_after_reimport() {
        let pkg = package_path("01-basic-unicode.apkg");
        if !pkg.exists() {
            return;
        }
        let (root, handle) = temp_open();
        call(
            handle,
            OP_IMPORT_PACKAGE,
            json!({
                "package_path": pkg.to_string_lossy(),
                "with_scheduling": false,
                "with_deck_configs": true,
            }),
        )
        .unwrap();
        let begin = call(
            handle,
            OP_BEGIN_PROJECTION_READ,
            json!({ "cardSetFingerprint": "abc", "mappingVersion": 1 }),
        )
        .unwrap();
        let token = begin["snapshotToken"].as_str().unwrap().to_string();
        crate::engine::bump_content_generation(
            &mut slot(handle).unwrap().engine.lock().unwrap(),
        );
        let err = call(
            handle,
            OP_GET_PROJECTION_ROWS_BATCH,
            json!({ "cardIds": [1], "snapshotToken": token }),
        )
        .unwrap_err();
        assert_eq!(err, STATUS_PROJECTION_SNAPSHOT_STALE);
        free_engine(handle).unwrap();
        let _ = fs::remove_dir_all(root);
    }

    /// Doc 38 P3 parity: SQL row batching must equal the per-row reference
    /// (fields/deckPath/tags/fingerprints) on fixture packages, including
    /// missing-card reporting.
    #[test]
    fn projection_rows_batch_matches_reference() {
        for pkg in [
            "01-basic-unicode.apkg",
            "02-basic-reversed.apkg",
            "04-cloze-multi-ord.apkg",
            "07-typed-answer.apkg",
        ] {
            let file = package_path(pkg);
            if !file.exists() {
                continue;
            }
            let (root, handle) = temp_open();
            call(
                handle,
                OP_IMPORT_PACKAGE,
                json!({
                    "package_path": file.to_string_lossy(),
                    "with_scheduling": false,
                    "with_deck_configs": true,
                }),
            )
            .unwrap();
            let begin = call(
                handle,
                OP_BEGIN_PROJECTION_READ,
                json!({ "cardSetFingerprint": "abc", "mappingVersion": 1 }),
            )
            .unwrap();
            let token = begin["snapshotToken"].as_str().unwrap();

            let mut card_ids = Vec::new();
            let mut page_token: Option<String> = None;
            loop {
                let mut body = json!({"search": "", "page_size": 1000});
                if let Some(t) = page_token.as_deref() {
                    body["page_token"] = json!(t);
                }
                let page = call(
                    handle,
                    crate::engine::OP_SEARCH_CARDS_PAGE,
                    body,
                )
                .unwrap();
                card_ids.extend(
                    page["cardIds"]
                        .as_array()
                        .unwrap()
                        .iter()
                        .map(|v| v.as_i64().unwrap()),
                );
                page_token = page["nextPageToken"].as_str().map(|s| s.to_string());
                if page_token.is_none() {
                    break;
                }
            }
            assert!(!card_ids.is_empty(), "{pkg}");
            // One deliberately missing id exercises missingCardIds parity.
            let ghost = card_ids[0].max(900_000_000_000);
            let request_ids = [card_ids.clone(), vec![ghost]].concat();

            let got = call(
                handle,
                OP_GET_PROJECTION_ROWS_BATCH,
                json!({ "cardIds": request_ids, "snapshotToken": token }),
            )
            .unwrap();
            let want = {
                let slot_arc = slot(handle).unwrap();
                let mut engine = slot_arc.engine.lock().unwrap();
                let col = engine.collection.as_mut().unwrap();
                reference_rows(col, &request_ids).unwrap()
            };
            assert_eq!(got, want, "{pkg} rows");

            free_engine(handle).unwrap();
            let _ = fs::remove_dir_all(root);
        }
    }

    #[test]
    fn batch_rejects_more_than_500() {
        let ids: Vec<i64> = (1..=501).collect();
        let err = get_projection_rows_batch(
            0,
            &serde_json::to_vec(&json!({ "cardIds": ids, "snapshotToken": "x" })).unwrap(),
        )
        .unwrap_err();
        assert_eq!(err, STATUS_INVALID_ARGUMENT);
    }

    #[test]
    fn field_truncation_marks_truncated() {
        let long = "x".repeat(MAX_FIELD_BYTES + 8);
        let (cut, truncated) = truncate_field(&long);
        assert!(truncated);
        assert_eq!(cut.len(), MAX_FIELD_BYTES);
    }
}
