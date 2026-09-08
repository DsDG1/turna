//! Paged Card queries and minimal descriptors. No field/HTML payloads.

use std::collections::HashMap;

use serde::Deserialize;
use serde::Serialize;
use serde_json::json;
use serde_json::Value;
use sha2::Digest;
use sha2::Sha256;

use anki::prelude::*;
use anki::search::SortMode;

use crate::engine::parse_req;
use crate::engine::parse_req_or_default;
use crate::engine::slot;
use crate::engine::STATUS_BACKEND_PANIC;
use crate::engine::STATUS_CARD_NOT_FOUND;
use crate::engine::STATUS_INTERNAL_ERROR;
use crate::engine::STATUS_INVALID_ARGUMENT;
use crate::engine::STATUS_PAGE_TOKEN_STALE;
use crate::ops::map_anki_error;
use crate::ops::require_open;

const DEFAULT_PAGE: usize = 200;
const MAX_PAGE: usize = 1000;
const MAX_BATCH: usize = 1000;
/// Id lists are inlined into `IN (...)` lists (ids are u64-deserialized
/// integers, no injection surface — same approach rslib itself uses). 500
/// keeps every statement well under SQLite's variable limit.
const SQL_CHUNK: usize = 500;

/// Splits `tags` exactly like rslib's `split_tags`: ASCII space or
/// ideographic space, empty segments dropped.
pub(crate) fn split_note_tags(raw: &str) -> Vec<String> {
    raw.split([' ', '\u{3000}'])
        .filter(|tag| !tag.is_empty())
        .map(str::to_string)
        .collect()
}

#[derive(Debug, Deserialize)]
struct PageRequest {
    #[serde(default)]
    search: String,
    #[serde(default)]
    page_size: Option<usize>,
    #[serde(default)]
    page_token: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
struct PageToken {
    generation: u64,
    fingerprint: String,
    after_card_id: i64,
}

#[derive(Debug, Deserialize)]
struct NoteBatchRequest {
    note_ids: Vec<i64>,
}

#[derive(Debug, Deserialize)]
struct CardBatchRequest {
    card_ids: Vec<i64>,
}

fn fingerprint(search: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(search.as_bytes());
    hex::encode(hasher.finalize())
}

fn decode_token(raw: &str) -> Result<PageToken, i32> {
    let bytes = hex::decode(raw).map_err(|_| STATUS_INVALID_ARGUMENT)?;
    serde_json::from_slice(&bytes).map_err(|_| STATUS_INVALID_ARGUMENT)
}

fn encode_token(token: &PageToken) -> Result<String, i32> {
    let bytes = serde_json::to_vec(token).map_err(|_| STATUS_BACKEND_PANIC)?;
    Ok(hex::encode(bytes))
}

pub fn search_cards_page(handle: u64, request: &[u8]) -> Result<Value, i32> {
    let parsed: PageRequest = parse_req_or_default(
        request,
        PageRequest {
            search: String::new(),
            page_size: None,
            page_token: None,
        },
    )?;
    let page_size = parsed.page_size.unwrap_or(DEFAULT_PAGE).clamp(1, MAX_PAGE);
    let slot = slot(handle)?;
    let mut engine = require_open(&slot)?;
    let generation = engine.page_generation;
    let expected_fp = fingerprint(&parsed.search);
    let after = if let Some(raw) = parsed.page_token.as_deref() {
        let token = decode_token(raw)?;
        if token.generation != generation || token.fingerprint != expected_fp {
            return Err(STATUS_PAGE_TOKEN_STALE);
        }
        token.after_card_id
    } else {
        0
    };
    let ids = if let Some(snapshot) = engine.page_snapshot.as_ref() {
        if snapshot.generation == generation && snapshot.fingerprint == expected_fp {
            Some(std::sync::Arc::clone(&snapshot.ids))
        } else {
            None
        }
    } else {
        None
    };
    let ids = if let Some(ids) = ids {
        ids
    } else {
        let col = engine.open_col()?;
        let mut found = col
            .search_cards(parsed.search.as_str(), SortMode::NoOrder)
            .map_err(map_anki_error)?;
        found.sort_by_key(|id| id.0);
        let raw: Vec<i64> = found.into_iter().map(|id| id.0).collect();
        let arc = std::sync::Arc::new(raw);
        engine.page_snapshot = Some(crate::engine::PageSnapshot {
            generation,
            fingerprint: expected_fp.clone(),
            ids: std::sync::Arc::clone(&arc),
        });
        arc
    };
    let start = ids.iter().position(|id| *id > after).unwrap_or(ids.len());
    let end = (start + page_size).min(ids.len());
    let page = &ids[start..end];
    let card_ids = page.to_vec();
    let next = if end < ids.len() {
        Some(encode_token(&PageToken {
            generation,
            fingerprint: expected_fp,
            after_card_id: page.last().copied().unwrap_or(after),
        })?)
    } else {
        None
    };
    Ok(json!({
        "cardIds": card_ids,
        "nextPageToken": next,
        "pageSize": page_size,
        "totalHint": ids.len(),
    }))
}

pub fn get_note_cards_batch(handle: u64, request: &[u8]) -> Result<Value, i32> {
    let parsed: NoteBatchRequest = parse_req(request)?;
    if parsed.note_ids.len() > MAX_BATCH {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    let slot = slot(handle)?;
    let mut engine = require_open(&slot)?;
    let col = engine.open_col()?;
    let by_note = note_cards_by_note(col, &parsed.note_ids)?;
    let notes = parsed
        .note_ids
        .iter()
        .map(|note_id| {
            let empty = Vec::new();
            let card_ids = by_note.get(note_id).unwrap_or(&empty);
            json!({
                "noteId": note_id,
                "cardIds": card_ids,
            })
        })
        .collect::<Vec<_>>();
    Ok(json!({ "notes": notes }))
}

/// One `SELECT id, nid FROM cards WHERE nid IN (...) ORDER BY nid, ord`
/// per 500-note chunk (doc 38 P3-1) instead of `all_cards_of_note` per note.
pub(crate) fn note_cards_by_note(
    col: &Collection,
    note_ids: &[i64],
) -> Result<HashMap<i64, Vec<i64>>, i32> {
    let mut by_note: HashMap<i64, Vec<i64>> = HashMap::new();
    let db = col.storage.db();
    for chunk in note_ids.chunks(SQL_CHUNK) {
        let placeholders = vec!["?"; chunk.len()].join(",");
        let sql =
            format!("SELECT id, nid FROM cards WHERE nid IN ({placeholders}) ORDER BY nid, ord");
        let mut stmt = db.prepare(&sql).map_err(|_| STATUS_INTERNAL_ERROR)?;
        let rows = stmt
            .query_map(rusqlite::params_from_iter(chunk.iter()), |row| {
                Ok((row.get::<_, i64>(0)?, row.get::<_, i64>(1)?))
            })
            .map_err(|_| STATUS_INTERNAL_ERROR)?;
        for row in rows {
            let (card_id, note_id) = row.map_err(|_| STATUS_INTERNAL_ERROR)?;
            by_note.entry(note_id).or_default().push(card_id);
        }
    }
    Ok(by_note)
}

pub(crate) struct CardDescriptorRow {
    pub note_id: i64,
    pub deck_id: i64,
    pub template_ord: i64,
    pub queue: i64,
    pub flags: i64,
    pub note_guid: String,
    pub note_tags: String,
    pub notetype_id: i64,
}

pub fn get_card_descriptors_batch(handle: u64, request: &[u8]) -> Result<Value, i32> {
    let parsed: CardBatchRequest = parse_req(request)?;
    if parsed.card_ids.len() > MAX_BATCH {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    let slot = slot(handle)?;
    let mut engine = require_open(&slot)?;
    let col = engine.open_col()?;
    let rows = card_descriptor_rows(col, &parsed.card_ids)?;
    // The per-card getter errored on any missing card/note; keep that
    // fail-fast instead of silently shrinking the batch.
    for card_id in &parsed.card_ids {
        if !rows.contains_key(card_id) {
            return Err(STATUS_CARD_NOT_FOUND);
        }
    }
    let cards = parsed
        .card_ids
        .iter()
        .map(|card_id| {
            let row = &rows[card_id];
            let queue = row.queue;
            let tags = split_note_tags(&row.note_tags);
            json!({
                "cardId": card_id,
                "noteId": row.note_id,
                "deckId": row.deck_id,
                "noteGuid": row.note_guid,
                "templateOrd": row.template_ord,
                "queue": queue,
                "suspended": queue == -1,
                "buried": queue == -2 || queue == -3,
                "flag": row.flags & 0b111,
                "marked": tags.iter().any(|tag| tag.eq_ignore_ascii_case("marked")),
                "tags": tags,
                "notetypeId": row.notetype_id,
            })
        })
        .collect::<Vec<_>>();
    Ok(json!({ "cards": cards }))
}

/// One JOIN per 500-card chunk (doc 38 P3-2) instead of get_card + get_note
/// per card. `templateOrd` reads `cards.ord`, the column rslib's
/// `row_to_card` loads into `Card::template_idx`.
pub(crate) fn card_descriptor_rows(
    col: &Collection,
    card_ids: &[i64],
) -> Result<HashMap<i64, CardDescriptorRow>, i32> {
    let mut rows: HashMap<i64, CardDescriptorRow> = HashMap::new();
    let db = col.storage.db();
    for chunk in card_ids.chunks(SQL_CHUNK) {
        let placeholders = vec!["?"; chunk.len()].join(",");
        let sql = format!(
            "SELECT c.id, c.nid, c.did, c.ord, c.queue, c.flags, n.guid, n.tags, n.mid \
             FROM cards c JOIN notes n ON n.id = c.nid WHERE c.id IN ({placeholders})"
        );
        let mut stmt = db.prepare(&sql).map_err(|_| STATUS_INTERNAL_ERROR)?;
        let found = stmt
            .query_map(rusqlite::params_from_iter(chunk.iter()), |row| {
                Ok((
                    row.get::<_, i64>(0)?,
                    CardDescriptorRow {
                        note_id: row.get(1)?,
                        deck_id: row.get(2)?,
                        template_ord: row.get(3)?,
                        queue: row.get(4)?,
                        flags: row.get(5)?,
                        note_guid: row.get(6)?,
                        note_tags: row.get(7)?,
                        notetype_id: row.get(8)?,
                    },
                ))
            })
            .map_err(|_| STATUS_INTERNAL_ERROR)?;
        for row in found {
            let (card_id, descriptor) = row.map_err(|_| STATUS_INTERNAL_ERROR)?;
            rows.insert(card_id, descriptor);
        }
    }
    Ok(rows)
}

/// Doc 38 P3: the pre-batching per-item implementations, kept verbatim as
/// the parity oracle for the SQL implementations above. Delete at the next
/// rslib pin refresh once the parity tests have passed on the toolchain
/// host.
#[cfg(test)]
mod reference {
    use super::*;
    use crate::ops::map_anki_error;
    use anki::notes::NoteId;
    use anki::services::CardsService;
    use anki::services::NotesService;

    pub fn note_cards_batch(col: &mut Collection, note_ids: &[i64]) -> Result<Value, i32> {
        let mut notes = Vec::new();
        for note_id in note_ids {
            let cards = col
                .storage
                .all_cards_of_note(NoteId(*note_id))
                .map_err(map_anki_error)?;
            notes.push(json!({
                "noteId": note_id,
                "cardIds": cards.iter().map(|card| card.id().0).collect::<Vec<_>>(),
            }));
        }
        Ok(json!({ "notes": notes }))
    }

    pub fn card_descriptors_batch(col: &mut Collection, card_ids: &[i64]) -> Result<Value, i32> {
        let mut cards = Vec::new();
        for card_id in card_ids {
            let card = CardsService::get_card(col, anki_proto::cards::CardId { cid: *card_id })
                .map_err(map_anki_error)?;
            let note = NotesService::get_note(col, anki_proto::notes::NoteId { nid: card.note_id })
                .map_err(map_anki_error)?;
            let queue = card.queue;
            let tags = note.tags;
            cards.push(json!({
                "cardId": card.id,
                "noteId": card.note_id,
                "deckId": card.deck_id,
                "noteGuid": note.guid,
                "templateOrd": card.template_idx,
                "queue": queue,
                "suspended": queue == -1,
                "buried": queue == -2 || queue == -3,
                "flag": card.flags & 0b111,
                "marked": tags.iter().any(|tag| tag.eq_ignore_ascii_case("marked")),
                "tags": tags,
            }));
        }
        Ok(json!({ "cards": cards }))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::engine::dispatch;
    use crate::engine::free_engine;
    use crate::engine::OP_GET_CARD_DESCRIPTORS_BATCH;
    use crate::engine::OP_IMPORT_PACKAGE;
    use crate::engine::OP_SEARCH_CARDS_PAGE;
    use crate::engine::STATUS_PAGE_TOKEN_STALE;
    use std::path::PathBuf;

    fn fixture_pkg() -> PathBuf {
        crate::test_support::package_path("02-basic-reversed.apkg")
    }

    fn open_imported() -> (PathBuf, u64) {
        crate::test_support::temp_open_imported("query", "02-basic-reversed.apkg")
    }

    /// Doc 38 P2: mutating ops bump `page_generation`, so an old page token
    /// must fail with PAGE_TOKEN_STALE and the next cold search must see the
    /// post-mutation world instead of the cached snapshot.
    #[test]
    fn delete_notes_rebuilds_page_snapshot_and_stales_old_token() {
        let (root, handle) = open_imported();
        let first = dispatch(
            handle,
            OP_SEARCH_CARDS_PAGE,
            &serde_json::to_vec(&json!({"search": "", "page_size": 1})).unwrap(),
        )
        .unwrap();
        let token = first["nextPageToken"].as_str().unwrap().to_string();
        let total_before = first["totalHint"].as_u64().unwrap();

        let card_id = first["cardIds"][0].as_i64().unwrap();
        let descriptors = dispatch(
            handle,
            crate::engine::OP_GET_CARD_DESCRIPTORS_BATCH,
            &serde_json::to_vec(&json!({"card_ids": [card_id]})).unwrap(),
        )
        .unwrap();
        let note_id = descriptors["cards"][0]["noteId"].as_i64().unwrap();
        dispatch(
            handle,
            crate::engine::OP_DELETE_NOTES,
            &serde_json::to_vec(&json!({"noteIds": [note_id]})).unwrap(),
        )
        .unwrap();

        let stale = dispatch(
            handle,
            OP_SEARCH_CARDS_PAGE,
            &serde_json::to_vec(&json!({"search": "", "page_size": 1, "page_token": token}))
                .unwrap(),
        )
        .unwrap_err();
        assert_eq!(stale, STATUS_PAGE_TOKEN_STALE);
        let after = dispatch(
            handle,
            OP_SEARCH_CARDS_PAGE,
            &serde_json::to_vec(&json!({"search": "", "page_size": 1000})).unwrap(),
        )
        .unwrap();
        // The deleted note may own more than one card (reversed templates),
        // so assert the count dropped rather than an exact delta.
        assert!(after["totalHint"].as_u64().unwrap() < total_before);
        free_engine(handle).unwrap();
        let _ = std::fs::remove_dir_all(root);
    }

    /// Doc 38 P2 (V1): `get_review_queue` goes through
    /// `begin_queue_epoch -> invalidate_tokens` only. It must NOT touch the
    /// page snapshot, or browsing cache would die on every queue fetch.
    #[test]
    fn get_review_queue_keeps_page_snapshot_cached() {
        let (root, handle) = open_imported();
        dispatch(
            handle,
            OP_SEARCH_CARDS_PAGE,
            &serde_json::to_vec(&json!({"search": "", "page_size": 1})).unwrap(),
        )
        .unwrap();
        for _ in 0..2 {
            let _ = dispatch(
                handle,
                crate::engine::OP_GET_REVIEW_QUEUE,
                &serde_json::to_vec(&json!({"fetchLimit": 1})).unwrap(),
            );
        }
        let slot_arc = slot(handle).unwrap();
        let engine = slot_arc.engine.lock().unwrap();
        assert!(
            engine.page_snapshot.is_some(),
            "queue fetches must not clear the page snapshot"
        );
        drop(engine);
        free_engine(handle).unwrap();
        let _ = std::fs::remove_dir_all(root);
    }

    fn open_imported_pkg(name: &str) -> (PathBuf, u64) {
        crate::test_support::temp_open_imported("query", name)
    }

    fn page_all_card_ids(handle: u64) -> Vec<i64> {
        crate::test_support::page_all_card_ids(handle)
    }

    /// Doc 38 P3 parity: the SQL batch implementations must be byte-equal
    /// (JSON) to the per-item reference on every fixture package, and must
    /// keep the reference's fail-fast on missing ids.
    #[test]
    fn batch_reads_match_reference_implementations() {
        for pkg in [
            "01-basic-unicode.apkg",
            "02-basic-reversed.apkg",
            "04-cloze-multi-ord.apkg",
            "07-typed-answer.apkg",
        ] {
            let (root, handle) = open_imported_pkg(pkg);
            let card_ids = page_all_card_ids(handle);
            assert!(!card_ids.is_empty(), "{pkg}");

            let descriptors = dispatch(
                handle,
                OP_GET_CARD_DESCRIPTORS_BATCH,
                &serde_json::to_vec(&json!({"card_ids": card_ids})).unwrap(),
            )
            .unwrap();
            let mut note_ids: Vec<i64> = descriptors["cards"]
                .as_array()
                .unwrap()
                .iter()
                .map(|card| card["noteId"].as_i64().unwrap())
                .collect();
            note_ids.sort_unstable();
            note_ids.dedup();

            let got_notes = dispatch(
                handle,
                crate::engine::OP_GET_NOTE_CARDS_BATCH,
                &serde_json::to_vec(&json!({"note_ids": note_ids})).unwrap(),
            )
            .unwrap();
            let want_notes = {
                let slot_arc = slot(handle).unwrap();
                let mut engine = slot_arc.engine.lock().unwrap();
                let col = engine.collection.as_mut().unwrap();
                reference::note_cards_batch(col, &note_ids).unwrap()
            };
            assert_eq!(got_notes, want_notes, "{pkg} note cards");

            let got_descriptors = dispatch(
                handle,
                OP_GET_CARD_DESCRIPTORS_BATCH,
                &serde_json::to_vec(&json!({"card_ids": card_ids})).unwrap(),
            )
            .unwrap();
            let want_descriptors = {
                let slot_arc = slot(handle).unwrap();
                let mut engine = slot_arc.engine.lock().unwrap();
                let col = engine.collection.as_mut().unwrap();
                reference::card_descriptors_batch(col, &card_ids).unwrap()
            };
            assert_eq!(got_descriptors, want_descriptors, "{pkg} descriptors");

            let ghost = card_ids[0].max(900_000_000_000);
            let missing = dispatch(
                handle,
                OP_GET_CARD_DESCRIPTORS_BATCH,
                &serde_json::to_vec(&json!({"card_ids": [ghost]})).unwrap(),
            );
            assert_eq!(
                missing.unwrap_err(),
                crate::engine::STATUS_CARD_NOT_FOUND,
                "{pkg} missing card"
            );

            free_engine(handle).unwrap();
            let _ = std::fs::remove_dir_all(root);
        }
    }

    #[test]
    fn paged_search_has_no_note_fields_and_stale_token_fails() {
        let (root, handle) = open_imported();
        let first = dispatch(
            handle,
            OP_SEARCH_CARDS_PAGE,
            &serde_json::to_vec(&json!({"search": "", "page_size": 1})).unwrap(),
        )
        .unwrap();
        assert_eq!(first["cardIds"].as_array().unwrap().len(), 1);
        assert!(first.get("notes").is_none());
        assert!(first.get("fields").is_none());
        let token = first["nextPageToken"].as_str().unwrap().to_string();
        let second = dispatch(
            handle,
            OP_SEARCH_CARDS_PAGE,
            &serde_json::to_vec(&json!({"search": "", "page_size": 1, "page_token": token}))
                .unwrap(),
        )
        .unwrap();
        assert_eq!(second["cardIds"].as_array().unwrap().len(), 1);
        assert_ne!(first["cardIds"][0], second["cardIds"][0]);

        let card_id = first["cardIds"][0].as_i64().unwrap();
        let descriptors = dispatch(
            handle,
            OP_GET_CARD_DESCRIPTORS_BATCH,
            &serde_json::to_vec(&json!({"card_ids": [card_id]})).unwrap(),
        )
        .unwrap();
        let card = &descriptors["cards"][0];
        assert!(card.get("cardId").is_some());
        assert!(card.get("noteGuid").is_some());
        assert!(card.get("fields").is_none());
        assert!(card.get("qfmt").is_none());
        assert!(card.get("css").is_none());

        dispatch(
            handle,
            OP_IMPORT_PACKAGE,
            &serde_json::to_vec(&json!({
                "package_path": fixture_pkg().to_string_lossy(),
            }))
            .unwrap(),
        )
        .unwrap();
        let stale = dispatch(
            handle,
            OP_SEARCH_CARDS_PAGE,
            &serde_json::to_vec(&json!({"search": "", "page_size": 1, "page_token": token}))
                .unwrap(),
        )
        .unwrap_err();
        assert_eq!(stale, STATUS_PAGE_TOKEN_STALE);
        free_engine(handle).unwrap();
        let _ = std::fs::remove_dir_all(root);
    }
}
