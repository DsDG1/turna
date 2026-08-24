//! Contract 1.2 read-only projection queries. Never returns qfmt/afmt/CSS,
//! revlog, or scheduling.

use serde::Deserialize;
use serde_json::json;
use serde_json::Value;
use sha2::Digest;
use sha2::Sha256;

use anki::prelude::*;
use anki::search::SortMode;

use crate::engine::slot;
use crate::engine::Engine;
use crate::engine::MAX_RESPONSE_BYTES;
use crate::engine::STATUS_BACKEND_PANIC;
use crate::engine::STATUS_INVALID_ARGUMENT;
use crate::engine::STATUS_INVALID_STATE;
use crate::engine::STATUS_PROJECTION_SNAPSHOT_STALE;
use crate::ops::map_anki_error;

const DEFAULT_SAMPLE_LIMIT: usize = 3;
const MAX_SAMPLE_LIMIT: usize = 10;
const DEFAULT_BATCH: usize = 200;
const MAX_BATCH: usize = 500;
const MAX_FIELD_BYTES: usize = 8 * 1024;

#[derive(Debug, Clone)]
pub struct ProjectionSnapshot {
    pub token: String,
    pub collection_generation: u64,
    pub card_set_fingerprint: String,
    pub mapping_version: i64,
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

fn source_fingerprint(note: &Note, deck_path: &[String], ordinal: u16) -> String {
    let mut hasher = Sha256::new();
    hasher.update(note.guid.as_bytes());
    hasher.update([0]);
    hasher.update(ordinal.to_le_bytes());
    hasher.update([0]);
    for part in deck_path {
        hasher.update(part.as_bytes());
        hasher.update([0]);
    }
    for field in note.fields() {
        hasher.update(field.as_bytes());
        hasher.update([0]);
    }
    for tag in &note.tags {
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
    let parsed: SchemaRequest = if request.is_empty() {
        SchemaRequest {
            notetype_ids: Vec::new(),
            include_samples: false,
            sample_limit: None,
        }
    } else {
        serde_json::from_slice(request).map_err(|_| STATUS_INVALID_ARGUMENT)?
    };
    let sample_limit = parsed
        .sample_limit
        .unwrap_or(DEFAULT_SAMPLE_LIMIT)
        .clamp(1, MAX_SAMPLE_LIMIT);
    let slot = slot(handle)?;
    let mut engine = slot.engine.lock().map_err(|_| STATUS_BACKEND_PANIC)?;
    if engine.state != crate::engine::EngineState::Open {
        return Err(STATUS_INVALID_STATE);
    }
    let col = engine.collection.as_mut().ok_or(STATUS_INVALID_STATE)?;
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
        serde_json::from_slice(request).map_err(|_| STATUS_INVALID_ARGUMENT)?;
    if parsed.card_set_fingerprint.is_empty() {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    let slot = slot(handle)?;
    let mut engine = slot.engine.lock().map_err(|_| STATUS_BACKEND_PANIC)?;
    if engine.state != crate::engine::EngineState::Open {
        return Err(STATUS_INVALID_STATE);
    }
    let generation = engine.page_generation;
    let token = token_for(
        generation,
        &parsed.card_set_fingerprint,
        parsed.mapping_version,
    );
    engine.projection_snapshot = Some(ProjectionSnapshot {
        token: token.clone(),
        collection_generation: generation,
        card_set_fingerprint: parsed.card_set_fingerprint,
        mapping_version: parsed.mapping_version,
    });
    Ok(json!({
        "snapshotToken": token,
        "collectionGeneration": generation,
        "backendCommit": crate::contract::backend_commit(),
    }))
}

fn require_snapshot<'a>(engine: &'a Engine, token: &str) -> Result<&'a ProjectionSnapshot, i32> {
    let snap = engine
        .projection_snapshot
        .as_ref()
        .ok_or(STATUS_PROJECTION_SNAPSHOT_STALE)?;
    if snap.token != token
        || snap.collection_generation != engine.page_generation
        || snap.card_set_fingerprint.is_empty()
    {
        return Err(STATUS_PROJECTION_SNAPSHOT_STALE);
    }
    let _ = snap.mapping_version;
    Ok(snap)
}

pub fn get_projection_rows_batch(handle: u64, request: &[u8]) -> Result<Value, i32> {
    let parsed: RowsRequest =
        serde_json::from_slice(request).map_err(|_| STATUS_INVALID_ARGUMENT)?;
    if parsed.card_ids.len() > MAX_BATCH {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    let card_ids = if parsed.card_ids.is_empty() {
        Vec::new()
    } else {
        parsed.card_ids.clone()
    };
    if card_ids.len() > MAX_BATCH {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    let slot = slot(handle)?;
    let mut engine = slot.engine.lock().map_err(|_| STATUS_BACKEND_PANIC)?;
    if engine.state != crate::engine::EngineState::Open {
        return Err(STATUS_INVALID_STATE);
    }
    let _ = require_snapshot(&engine, &parsed.snapshot_token)?;
    let col = engine.collection.as_mut().ok_or(STATUS_INVALID_STATE)?;
    let mut rows = Vec::new();
    let mut missing = Vec::new();
    let take = card_ids.into_iter().take(MAX_BATCH.max(DEFAULT_BATCH));
    for card_id in take {
        let Some(card) = col
            .storage
            .get_card(CardId(card_id))
            .map_err(map_anki_error)?
        else {
            missing.push(card_id);
            continue;
        };
        let Some(note) = col
            .storage
            .get_note(card.note_id())
            .map_err(map_anki_error)?
        else {
            missing.push(card_id);
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::engine::alloc_engine;
    use crate::engine::dispatch;
    use crate::engine::free_engine;
    use crate::engine::open_collection;
    use crate::engine::OpenRequest;
    use crate::engine::OP_BEGIN_PROJECTION_READ;
    use crate::engine::OP_GET_PROJECTION_ROWS_BATCH;
    use crate::engine::OP_GET_PROJECTION_SCHEMAS;
    use crate::engine::OP_IMPORT_PACKAGE;
    use std::fs;
    use std::path::PathBuf;
    use std::time::SystemTime;
    use std::time::UNIX_EPOCH;

    fn fixture_root() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../contract/fixtures")
            .canonicalize()
            .unwrap_or_else(|_| {
                PathBuf::from(env!("CARGO_MANIFEST_DIR"))
                    .join("../../test/fixtures/anki_official/packages")
            })
    }

    fn package_path(name: &str) -> PathBuf {
        let contract = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../test/fixtures/anki_official/packages")
            .join(name);
        if contract.exists() {
            return contract;
        }
        fixture_root().join(name)
    }

    fn temp_open() -> (PathBuf, u64) {
        let root = std::env::temp_dir().join(format!(
            "turna-proj-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let body = serde_json::to_vec(&serde_json::json!({
            "collection_path": root.join("collection.anki2").to_string_lossy(),
            "media_folder": root.join("collection.media").to_string_lossy(),
            "media_db": root.join("collection.media.db2").to_string_lossy(),
            "check_integrity": false,
        }))
        .unwrap();
        let _ = OpenRequest {
            collection_path: String::new(),
            media_folder: String::new(),
            media_db: String::new(),
            check_integrity: false,
            allowed_root: None,
        };
        let handle = alloc_engine().unwrap();
        open_collection(handle, &body).unwrap();
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
        crate::engine::bump_page_generation(&mut slot(handle).unwrap().engine.lock().unwrap());
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
