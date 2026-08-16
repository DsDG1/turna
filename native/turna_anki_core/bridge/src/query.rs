//! Paged Card queries and minimal descriptors. No field/HTML payloads.

use serde::Deserialize;
use serde::Serialize;
use serde_json::json;
use serde_json::Value;
use sha2::Digest;
use sha2::Sha256;

use anki::notes::NoteId;
use anki::prelude::*;
use anki::search::SortMode;

use crate::engine::slot;
use crate::engine::STATUS_BACKEND_PANIC;
use crate::engine::STATUS_CARD_NOT_FOUND;
use crate::engine::STATUS_INVALID_ARGUMENT;
use crate::engine::STATUS_INVALID_STATE;
use crate::engine::STATUS_PAGE_TOKEN_STALE;
use crate::ops::map_anki_error;

const DEFAULT_PAGE: usize = 200;
const MAX_PAGE: usize = 1000;
const MAX_BATCH: usize = 1000;

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
    let parsed: PageRequest = if request.is_empty() {
        PageRequest {
            search: String::new(),
            page_size: None,
            page_token: None,
        }
    } else {
        serde_json::from_slice(request).map_err(|_| STATUS_INVALID_ARGUMENT)?
    };
    let page_size = parsed.page_size.unwrap_or(DEFAULT_PAGE).clamp(1, MAX_PAGE);
    let slot = slot(handle)?;
    let mut engine = slot.engine.lock().map_err(|_| STATUS_BACKEND_PANIC)?;
    if engine.state != crate::engine::EngineState::Open {
        return Err(STATUS_INVALID_STATE);
    }
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
    let col = engine.collection.as_mut().ok_or(STATUS_INVALID_STATE)?;
    let mut ids = col
        .search_cards(parsed.search.as_str(), SortMode::NoOrder)
        .map_err(map_anki_error)?;
    ids.sort_by_key(|id| id.0);
    let start = ids.iter().position(|id| id.0 > after).unwrap_or(ids.len());
    let end = (start + page_size).min(ids.len());
    let page = &ids[start..end];
    let mut card_ids = Vec::with_capacity(page.len());
    for id in page {
        card_ids.push(id.0);
    }
    let next = if end < ids.len() {
        Some(encode_token(&PageToken {
            generation,
            fingerprint: expected_fp,
            after_card_id: page.last().map(|id| id.0).unwrap_or(after),
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
    let parsed: NoteBatchRequest =
        serde_json::from_slice(request).map_err(|_| STATUS_INVALID_ARGUMENT)?;
    if parsed.note_ids.len() > MAX_BATCH {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    let slot = slot(handle)?;
    let mut engine = slot.engine.lock().map_err(|_| STATUS_BACKEND_PANIC)?;
    if engine.state != crate::engine::EngineState::Open {
        return Err(STATUS_INVALID_STATE);
    }
    let col = engine.collection.as_mut().ok_or(STATUS_INVALID_STATE)?;
    let mut notes = Vec::new();
    for note_id in parsed.note_ids {
        let cards = col
            .storage
            .all_cards_of_note(NoteId(note_id))
            .map_err(map_anki_error)?;
        notes.push(json!({
            "noteId": note_id,
            "cardIds": cards.iter().map(|card| card.id().0).collect::<Vec<_>>(),
        }));
    }
    Ok(json!({ "notes": notes }))
}

pub fn get_card_descriptors_batch(handle: u64, request: &[u8]) -> Result<Value, i32> {
    let parsed: CardBatchRequest =
        serde_json::from_slice(request).map_err(|_| STATUS_INVALID_ARGUMENT)?;
    if parsed.card_ids.len() > MAX_BATCH {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    let slot = slot(handle)?;
    let mut engine = slot.engine.lock().map_err(|_| STATUS_BACKEND_PANIC)?;
    if engine.state != crate::engine::EngineState::Open {
        return Err(STATUS_INVALID_STATE);
    }
    let col = engine.collection.as_mut().ok_or(STATUS_INVALID_STATE)?;
    let mut cards = Vec::new();
    for card_id in parsed.card_ids {
        let card = col
            .storage
            .get_card(CardId(card_id))
            .map_err(map_anki_error)?
            .ok_or(STATUS_CARD_NOT_FOUND)?;
        let note = col
            .storage
            .get_note(card.note_id())
            .map_err(map_anki_error)?
            .ok_or(STATUS_CARD_NOT_FOUND)?;
        cards.push(json!({
            "cardId": card.id().0,
            "noteId": card.note_id().0,
            "deckId": card.deck_id().0,
            "noteGuid": note.guid,
            "templateOrd": card.template_idx(),
        }));
    }
    Ok(json!({ "cards": cards }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::engine::alloc_engine;
    use crate::engine::dispatch;
    use crate::engine::free_engine;
    use crate::engine::open_collection;
    use crate::engine::OpenRequest;
    use crate::engine::OP_GET_CARD_DESCRIPTORS_BATCH;
    use crate::engine::OP_IMPORT_PACKAGE;
    use crate::engine::OP_SEARCH_CARDS_PAGE;
    use crate::engine::STATUS_PAGE_TOKEN_STALE;
    use std::path::PathBuf;
    use std::time::SystemTime;
    use std::time::UNIX_EPOCH;

    fn fixture_pkg() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../test/fixtures/anki_official/packages/02-basic-reversed.apkg")
    }

    fn open_imported() -> (PathBuf, u64) {
        let root = std::env::temp_dir().join(format!(
            "turna-query-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let request = OpenRequest {
            collection_path: root.join("collection.anki2").to_string_lossy().into(),
            media_folder: root.join("collection.media").to_string_lossy().into(),
            media_db: root.join("collection.media.db2").to_string_lossy().into(),
            check_integrity: false,
            allowed_root: None,
        };
        let body = serde_json::to_vec(&serde_json::json!({
            "collection_path": request.collection_path,
            "media_folder": request.media_folder,
            "media_db": request.media_db,
        }))
        .unwrap();
        let handle = alloc_engine().unwrap();
        open_collection(handle, &body).unwrap();
        dispatch(
            handle,
            OP_IMPORT_PACKAGE,
            &serde_json::to_vec(&json!({
                "package_path": fixture_pkg().to_string_lossy(),
            }))
            .unwrap(),
        )
        .unwrap();
        (root, handle)
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
