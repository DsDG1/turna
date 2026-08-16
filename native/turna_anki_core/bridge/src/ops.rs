//! Official Collection operations: import, query, render, queue, answer, undo.

use std::path::PathBuf;
use std::time::Instant;

use anki::card::CardQueueNumber;
use anki::card_rendering::extract_av_tags;
use anki::error::AnkiError;
use anki::import_export::package::ImportAnkiPackageOptions;
use anki::prelude::*;
use anki::scheduler::answering::CardAnswer;
use anki::scheduler::answering::Rating;
use anki::search::SortMode;
use anki::services::CollectionService;
use anki::timestamp::TimestampMillis;
use serde::Deserialize;
use serde_json::json;
use serde_json::Value;

use crate::engine::slot;
use crate::engine::AnswerToken;
use crate::engine::BusyGuard;
use crate::engine::Engine;
use crate::engine::EngineSlot;
use crate::engine::EngineState;
use crate::engine::MAX_REQUEST_BYTES;
use crate::engine::OP_ANSWER_CARD;
use crate::engine::OP_CANCEL_OPERATION;
use crate::engine::OP_DESCRIBE_NEXT_STATES;
use crate::engine::OP_GET_REVIEW_QUEUE;
use crate::engine::OP_GET_UNDO_STATUS;
use crate::engine::OP_IMPORT_PACKAGE;
use crate::engine::OP_LATEST_PROGRESS;
use crate::engine::OP_LIST_DECK_TREE;
use crate::engine::OP_RENDER_CARD;
use crate::engine::OP_SEARCH_CARDS;
use crate::engine::OP_SET_CURRENT_DECK;
use crate::engine::OP_UNDO;
use crate::engine::STATUS_ANSWER_FAILED;
use crate::engine::STATUS_BACKEND_PANIC;
use crate::engine::STATUS_CARD_NOT_FOUND;
use crate::engine::STATUS_COLLECTION_CORRUPT;
use crate::engine::STATUS_IMPORT_CANCELLED;
use crate::engine::STATUS_INTERNAL_ERROR;
use crate::engine::STATUS_INVALID_ARGUMENT;
use crate::engine::STATUS_INVALID_STATE;
use crate::engine::STATUS_IO_ERROR;
use crate::engine::STATUS_PACKAGE_INVALID;
use crate::engine::STATUS_PACKAGE_NOT_FOUND;
use crate::engine::STATUS_QUEUE_EMPTY;
use crate::engine::STATUS_RENDER_FAILED;
use crate::engine::STATUS_SCHEDULING_CONTEXT_STALE;
use crate::engine::STATUS_UNDO_UNAVAILABLE;
use crate::engine::STATUS_UNIMPLEMENTED;

#[derive(Debug, Deserialize)]
struct ImportRequest {
    package_path: String,
    #[serde(default)]
    merge_notetypes: bool,
    #[serde(default)]
    update_notes: i32,
    #[serde(default)]
    update_notetypes: i32,
    #[serde(default = "default_true")]
    with_scheduling: bool,
    #[serde(default = "default_true")]
    with_deck_configs: bool,
}

fn default_true() -> bool {
    true
}

#[derive(Debug, Deserialize)]
struct RenderRequest {
    card_id: i64,
    #[serde(default)]
    browser: bool,
}

#[derive(Debug, Deserialize)]
struct SearchRequest {
    #[serde(default)]
    search: String,
}

#[derive(Debug, Deserialize)]
struct DeckRequest {
    #[serde(default = "default_deck")]
    deck_id: i64,
}

fn default_deck() -> i64 {
    1
}

#[derive(Debug, Deserialize)]
struct QueueRequest {
    #[serde(default = "default_fetch")]
    fetch_limit: usize,
}

fn default_fetch() -> usize {
    10
}

#[derive(Debug, Deserialize)]
struct TokenRequest {
    answer_token: u64,
}

#[derive(Debug, Deserialize)]
struct AnswerRequest {
    card_id: i64,
    rating: String,
    answer_token: u64,
}

pub fn dispatch_op(handle: u64, operation: u32, request: &[u8]) -> Result<Value, i32> {
    match operation {
        OP_IMPORT_PACKAGE => import_package(handle, request),
        OP_LATEST_PROGRESS => latest_progress(handle),
        OP_CANCEL_OPERATION => request_cancel(handle),
        OP_LIST_DECK_TREE => list_deck_tree(handle),
        OP_SEARCH_CARDS => search_cards(handle, request),
        OP_RENDER_CARD => render_card(handle, request),
        OP_SET_CURRENT_DECK => set_current_deck(handle, request),
        OP_GET_REVIEW_QUEUE => get_review_queue(handle, request),
        OP_DESCRIBE_NEXT_STATES => describe_next_states(handle, request),
        OP_ANSWER_CARD => answer_card(handle, request),
        OP_GET_UNDO_STATUS => get_undo_status(handle),
        OP_UNDO => undo(handle),
        _ => {
            let slot = slot(handle)?;
            if slot.busy.load(std::sync::atomic::Ordering::Acquire) {
                return Err(STATUS_INVALID_STATE);
            }
            let engine = slot.engine.lock().map_err(|_| STATUS_BACKEND_PANIC)?;
            if engine.state != EngineState::Open {
                return Err(STATUS_INVALID_STATE);
            }
            Err(STATUS_UNIMPLEMENTED)
        }
    }
}

pub fn request_cancel(handle: u64) -> Result<Value, i32> {
    let slot = slot(handle)?;
    {
        let mut progress = slot.progress.lock().map_err(|_| STATUS_BACKEND_PANIC)?;
        progress.want_abort = true;
    }
    Ok(json!({
        "cancelling": true,
        "message_key": "cancelling",
        "can_cancel": true,
    }))
}

fn latest_progress(handle: u64) -> Result<Value, i32> {
    let slot = slot(handle)?;
    let progress = slot.progress.lock().map_err(|_| STATUS_BACKEND_PANIC)?;
    Ok(json!({
        "operation_kind": if slot.busy.load(std::sync::atomic::Ordering::Acquire) {
            "import"
        } else {
            "idle"
        },
        "can_cancel": slot.busy.load(std::sync::atomic::Ordering::Acquire),
        "want_abort": progress.want_abort,
        "has_progress": progress.last_progress.is_some(),
        "message_key": "progress",
    }))
}

fn require_open<'a>(slot: &'a EngineSlot) -> Result<std::sync::MutexGuard<'a, Engine>, i32> {
    if slot.busy.load(std::sync::atomic::Ordering::Acquire) {
        return Err(STATUS_INVALID_STATE);
    }
    let engine = slot.engine.lock().map_err(|_| STATUS_BACKEND_PANIC)?;
    if engine.state != EngineState::Open || engine.collection.is_none() {
        return Err(STATUS_INVALID_STATE);
    }
    Ok(engine)
}

fn import_package(handle: u64, request: &[u8]) -> Result<Value, i32> {
    if request.len() > MAX_REQUEST_BYTES {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    let parsed: ImportRequest =
        serde_json::from_slice(request).map_err(|_| STATUS_INVALID_ARGUMENT)?;
    let path = PathBuf::from(&parsed.package_path);
    if !path.is_absolute() {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    let slot = slot(handle)?;
    if !path.exists() {
        return Err(STATUS_PACKAGE_NOT_FOUND);
    }
    let _busy = BusyGuard::acquire(&slot)?;
    let mut engine = slot.engine.lock().map_err(|_| STATUS_BACKEND_PANIC)?;
    if engine.state != EngineState::Open {
        return Err(STATUS_INVALID_STATE);
    }
    let options = ImportAnkiPackageOptions {
        merge_notetypes: parsed.merge_notetypes,
        update_notes: parsed.update_notes,
        update_notetypes: parsed.update_notetypes,
        with_scheduling: parsed.with_scheduling,
        with_deck_configs: parsed.with_deck_configs,
    };
    let started = Instant::now();
    let imported = {
        let col = engine.collection.as_mut().ok_or(STATUS_INVALID_STATE)?;
        col.import_apkg(&path, options)
    };
    let elapsed = started.elapsed().as_millis() as u64;
    match imported {
        Ok(output) => {
            let log = output.output;
            let (note_ids, card_ids) = {
                let col = engine.collection.as_mut().ok_or(STATUS_INVALID_STATE)?;
                (
                    col.search_notes("", SortMode::NoOrder)
                        .map_err(map_anki_error)?,
                    col.search_cards("", SortMode::NoOrder)
                        .map_err(map_anki_error)?,
                )
            };
            crate::engine::bump_page_generation(&mut engine);
            Ok(json!({
                "new_note_ids": log_ids(&log.new),
                "updated_note_ids": log_ids(&log.updated),
                "duplicate_note_ids": log_ids(&log.duplicate),
                "conflicting_note_ids": log_ids(&log.conflicting),
                "missing_notetype_note_ids": log_ids(&log.missing_notetype),
                "elapsed_millis": elapsed,
                "warnings": Vec::<String>::new(),
                "note_count": note_ids.len(),
                "card_count": card_ids.len(),
                "found_notes": log.found_notes,
                "operationToken": format!("op-{handle}-{elapsed}"),
            }))
        }
        Err(AnkiError::Interrupted) => Err(STATUS_IMPORT_CANCELLED),
        Err(err) => Err(map_import_error(err)),
    }
}

fn list_deck_tree(handle: u64) -> Result<Value, i32> {
    let slot = slot(handle)?;
    let mut engine = require_open(&slot)?;
    let col = engine.collection.as_mut().ok_or(STATUS_INVALID_STATE)?;
    let tree = col.deck_tree(None).map_err(map_anki_error)?;
    let mut decks = Vec::new();
    let mut stack = vec![tree];
    while let Some(node) = stack.pop() {
        decks.push(json!({
            "deckId": node.deck_id,
            "deck_id": node.deck_id,
            "name": node.name,
            "level": node.level,
            "new_count": node.new_count,
            "learn_count": node.learn_count,
            "review_count": node.review_count,
        }));
        for child in node.children.into_iter().rev() {
            stack.push(child);
        }
    }
    Ok(json!({ "decks": decks }))
}

fn log_ids(notes: &[anki::import_export::LogNote]) -> Vec<i64> {
    notes
        .iter()
        .filter_map(|note| note.id.as_ref().map(|id| id.nid))
        .collect()
}

fn search_cards(handle: u64, request: &[u8]) -> Result<Value, i32> {
    let parsed: SearchRequest = if request.is_empty() {
        SearchRequest {
            search: String::new(),
        }
    } else {
        serde_json::from_slice(request).map_err(|_| STATUS_INVALID_ARGUMENT)?
    };
    let slot = slot(handle)?;
    let mut engine = require_open(&slot)?;
    let col = engine.collection.as_mut().ok_or(STATUS_INVALID_STATE)?;
    let ids = col
        .search_cards(parsed.search.as_str(), SortMode::NoOrder)
        .map_err(map_anki_error)?;
    let note_ids = col
        .search_notes("", SortMode::NoOrder)
        .map_err(map_anki_error)?;

    let mut cards = Vec::with_capacity(ids.len());
    for id in ids {
        let card = col
            .storage
            .get_card(id)
            .map_err(map_anki_error)?
            .ok_or(STATUS_CARD_NOT_FOUND)?;
        cards.push(json!({
            "card_id": card.id().0,
            "note_id": card.note_id().0,
            "deck_id": card.deck_id().0,
            "template_ordinal": card.template_idx(),
            "queue": queue_name(card.queue_number()),
        }));
    }

    let mut notes = Vec::with_capacity(note_ids.len());
    for nid in note_ids {
        let note = col
            .storage
            .get_note(nid)
            .map_err(map_anki_error)?
            .ok_or(STATUS_CARD_NOT_FOUND)?;
        notes.push(json!({
            "note_id": nid.0,
            "fields": note.fields(),
        }));
    }
    Ok(json!({ "cards": cards, "notes": notes }))
}

fn render_card(handle: u64, request: &[u8]) -> Result<Value, i32> {
    let parsed: RenderRequest =
        serde_json::from_slice(request).map_err(|_| STATUS_INVALID_ARGUMENT)?;
    let slot = slot(handle)?;
    let mut engine = require_open(&slot)?;
    let col = engine.collection.as_mut().ok_or(STATUS_INVALID_STATE)?;
    let rendered = col
        .render_existing_card(CardId(parsed.card_id), parsed.browser, false)
        .map_err(|err| {
            if matches!(
                err,
                AnkiError::NotFound { .. } | AnkiError::InvalidInput { .. }
            ) {
                STATUS_CARD_NOT_FOUND
            } else {
                STATUS_RENDER_FAILED
            }
        })?;
    let question = rendered.question().into_owned();
    let answer = rendered.answer().into_owned();
    let (q_text, q_tags) = extract_av_tags(question.clone(), true, col.tr());
    let (a_text, a_tags) = extract_av_tags(answer.clone(), false, col.tr());
    Ok(json!({
        "card_id": parsed.card_id,
        "question_html": question,
        "answer_html": answer,
        "css": rendered.css,
        "latex_svg": rendered.latex_svg,
        "is_empty": rendered.is_empty,
        "question_text_without_av": q_text,
        "answer_text_without_av": a_text,
        "question_av_tags": q_tags.iter().map(proto_av_tag_json).collect::<Vec<_>>(),
        "answer_av_tags": a_tags.iter().map(proto_av_tag_json).collect::<Vec<_>>(),
    }))
}

fn proto_av_tag_json(tag: &anki_proto::card_rendering::AvTag) -> Value {
    match tag.value.as_ref() {
        Some(anki_proto::card_rendering::av_tag::Value::SoundOrVideo(name)) => json!({
            "kind": "sound_or_video",
            "filename": name,
        }),
        Some(anki_proto::card_rendering::av_tag::Value::Tts(tts)) => json!({
            "kind": "tts",
            "fieldText": tts.field_text,
            "lang": tts.lang,
            "voices": tts.voices,
            "speed": tts.speed,
            "otherArgs": tts.other_args,
        }),
        None => json!({
            "kind": "unknown",
        }),
    }
}

fn set_current_deck(handle: u64, request: &[u8]) -> Result<Value, i32> {
    let parsed: DeckRequest = if request.is_empty() {
        DeckRequest { deck_id: 1 }
    } else {
        serde_json::from_slice(request).map_err(|_| STATUS_INVALID_ARGUMENT)?
    };
    let slot = slot(handle)?;
    let mut engine = require_open(&slot)?;
    let col = engine.collection.as_mut().ok_or(STATUS_INVALID_STATE)?;
    col.set_current_deck(DeckId(parsed.deck_id))
        .map_err(map_anki_error)?;
    Ok(json!({ "deck_id": parsed.deck_id }))
}

fn get_review_queue(handle: u64, request: &[u8]) -> Result<Value, i32> {
    let parsed: QueueRequest = if request.is_empty() {
        QueueRequest { fetch_limit: 10 }
    } else {
        serde_json::from_slice(request).map_err(|_| STATUS_INVALID_ARGUMENT)?
    };
    let slot = slot(handle)?;
    let mut engine = require_open(&slot)?;
    let col = engine.collection.as_mut().ok_or(STATUS_INVALID_STATE)?;
    let queued = col
        .get_queued_cards(parsed.fetch_limit.max(1), false)
        .map_err(map_anki_error)?;
    let mut prepared = Vec::new();
    for queued_card in queued.cards {
        let labels = col
            .describe_next_states(&queued_card.states)
            .map_err(map_anki_error)?;
        prepared.push((
            queued_card.card.id().0,
            queued_card.card.note_id().0,
            queued_card.card.deck_id().0,
            queued_card.card.template_idx(),
            format!("{:?}", queued_card.kind).to_ascii_lowercase(),
            queued_card.states,
            labels,
        ));
    }
    let new_count = queued.new_count;
    let learning_count = queued.learning_count;
    let review_count = queued.review_count;
    let session = engine.session;
    let mut cards = Vec::new();
    for (card_id, note_id, deck_id, ord, kind, states, labels) in prepared {
        let token = engine.next_token;
        engine.next_token = engine.next_token.wrapping_add(1).max(1);
        engine.tokens.insert(
            token,
            AnswerToken {
                session,
                card_id,
                states,
            },
        );
        cards.push(json!({
            "card_id": card_id,
            "note_id": note_id,
            "deck_id": deck_id,
            "template_ordinal": ord,
            "queue_kind": kind,
            "answer_token": token,
            "labels": {
                "again": labels.first().cloned().unwrap_or_default(),
                "hard": labels.get(1).cloned().unwrap_or_default(),
                "good": labels.get(2).cloned().unwrap_or_default(),
                "easy": labels.get(3).cloned().unwrap_or_default(),
            },
        }));
    }
    if cards.is_empty() {
        return Err(STATUS_QUEUE_EMPTY);
    }
    Ok(json!({
        "new_count": new_count,
        "learning_count": learning_count,
        "review_count": review_count,
        "cards": cards,
    }))
}

fn describe_next_states(handle: u64, request: &[u8]) -> Result<Value, i32> {
    let parsed: TokenRequest =
        serde_json::from_slice(request).map_err(|_| STATUS_INVALID_ARGUMENT)?;
    let slot = slot(handle)?;
    let mut engine = require_open(&slot)?;
    let token = engine
        .tokens
        .get(&parsed.answer_token)
        .ok_or(STATUS_SCHEDULING_CONTEXT_STALE)?;
    if token.session != engine.session {
        return Err(STATUS_SCHEDULING_CONTEXT_STALE);
    }
    let states = token.states.clone();
    let col = engine.collection.as_mut().ok_or(STATUS_INVALID_STATE)?;
    let labels = col.describe_next_states(&states).map_err(map_anki_error)?;
    Ok(json!({
        "answer_token": parsed.answer_token,
        "labels": {
            "again": labels.first().cloned().unwrap_or_default(),
            "hard": labels.get(1).cloned().unwrap_or_default(),
            "good": labels.get(2).cloned().unwrap_or_default(),
            "easy": labels.get(3).cloned().unwrap_or_default(),
        },
    }))
}

fn answer_card(handle: u64, request: &[u8]) -> Result<Value, i32> {
    let parsed: AnswerRequest =
        serde_json::from_slice(request).map_err(|_| STATUS_INVALID_ARGUMENT)?;
    let rating = parse_rating(&parsed.rating)?;
    let slot = slot(handle)?;
    let mut engine = require_open(&slot)?;
    let token = engine
        .tokens
        .remove(&parsed.answer_token)
        .ok_or(STATUS_SCHEDULING_CONTEXT_STALE)?;
    if token.session != engine.session || token.card_id != parsed.card_id {
        return Err(STATUS_SCHEDULING_CONTEXT_STALE);
    }
    let new_state = match rating {
        Rating::Again => token.states.again,
        Rating::Hard => token.states.hard,
        Rating::Good => token.states.good,
        Rating::Easy => token.states.easy,
    };
    let col = engine.collection.as_mut().ok_or(STATUS_INVALID_STATE)?;
    let mut answer = CardAnswer {
        card_id: CardId(parsed.card_id),
        current_state: token.states.current,
        new_state,
        rating,
        answered_at: TimestampMillis::now(),
        milliseconds_taken: 0,
        custom_data: None,
        from_queue: true,
    };
    col.answer_card(&mut answer)
        .map_err(|_| STATUS_ANSWER_FAILED)?;
    let card = col
        .storage
        .get_card(CardId(parsed.card_id))
        .map_err(map_anki_error)?
        .ok_or(STATUS_CARD_NOT_FOUND)?;
    let revlog = revlog_count(col, parsed.card_id)?;
    Ok(json!({
        "card_id": parsed.card_id,
        "queue": queue_name(card.queue_number()),
        "revlog_count": revlog,
    }))
}

fn get_undo_status(handle: u64) -> Result<Value, i32> {
    let slot = slot(handle)?;
    let engine = require_open(&slot)?;
    let col = engine.collection.as_ref().ok_or(STATUS_INVALID_STATE)?;
    let status = col.undo_status();
    Ok(json!({
        "can_undo": status.undo.is_some(),
        "can_redo": status.redo.is_some(),
        "undo": status.undo.map(|op| format!("{op:?}")),
        "redo": status.redo.map(|op| format!("{op:?}")),
    }))
}

fn undo(handle: u64) -> Result<Value, i32> {
    let slot = slot(handle)?;
    let mut engine = require_open(&slot)?;
    let col = engine.collection.as_mut().ok_or(STATUS_INVALID_STATE)?;
    match col.undo() {
        Ok(_) => Ok(json!({ "undone": true })),
        Err(AnkiError::UndoEmpty) => Err(STATUS_UNDO_UNAVAILABLE),
        Err(err) => Err(map_anki_error(err)),
    }
}

fn revlog_count(col: &Collection, card_id: i64) -> Result<usize, i32> {
    col.storage
        .db()
        .query_row(
            "select count(*) from revlog where cid = ?",
            [card_id],
            |row| row.get::<_, i64>(0),
        )
        .map(|n| n as usize)
        .map_err(|_| STATUS_INTERNAL_ERROR)
}

fn queue_name(queue: CardQueueNumber) -> &'static str {
    match queue {
        CardQueueNumber::New => "new",
        CardQueueNumber::Learning => "learning",
        CardQueueNumber::Review => "review",
        CardQueueNumber::Invalid => "invalid",
    }
}

fn parse_rating(name: &str) -> Result<Rating, i32> {
    match name.to_ascii_lowercase().as_str() {
        "again" => Ok(Rating::Again),
        "hard" => Ok(Rating::Hard),
        "good" => Ok(Rating::Good),
        "easy" => Ok(Rating::Easy),
        _ => Err(STATUS_INVALID_ARGUMENT),
    }
}

fn map_import_error(err: AnkiError) -> i32 {
    match err {
        AnkiError::Interrupted => STATUS_IMPORT_CANCELLED,
        _ => STATUS_PACKAGE_INVALID,
    }
}

pub(crate) fn map_anki_error(err: AnkiError) -> i32 {
    match err {
        AnkiError::Interrupted => STATUS_IMPORT_CANCELLED,
        AnkiError::UndoEmpty => STATUS_UNDO_UNAVAILABLE,
        AnkiError::NotFound { .. } => STATUS_CARD_NOT_FOUND,
        AnkiError::FileIoError { .. } => STATUS_IO_ERROR,
        AnkiError::InvalidInput { .. } => STATUS_INVALID_ARGUMENT,
        AnkiError::DbError { .. } => STATUS_COLLECTION_CORRUPT,
        AnkiError::CollectionNotOpen => STATUS_INVALID_STATE,
        _ => STATUS_INTERNAL_ERROR,
    }
}

pub fn integrity_ok(col: &mut Collection) -> Result<bool, i32> {
    CollectionService::check_database(col)
        .map(|_| true)
        .map_err(|_| STATUS_COLLECTION_CORRUPT)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::engine::alloc_engine;
    use crate::engine::check_collection;
    use crate::engine::close_collection;
    use crate::engine::dispatch;
    use crate::engine::free_engine;
    use crate::engine::open_collection;
    use crate::engine::OpenRequest;
    use crate::engine::STATUS_INVALID_HANDLE;
    use serde_json::Value;
    use std::fs;
    use std::path::Path;
    use std::time::Instant;
    use std::time::SystemTime;
    use std::time::UNIX_EPOCH;

    fn fixture_root() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../test/fixtures/anki_official")
    }

    fn package_path(name: &str) -> PathBuf {
        fixture_root().join("packages").join(name)
    }

    fn expected_path(name: &str) -> PathBuf {
        fixture_root().join("expected").join(name)
    }

    fn manifest() -> Value {
        let text = fs::read_to_string(fixture_root().join("manifest.json")).unwrap();
        serde_json::from_str(&text).unwrap()
    }

    fn temp_open() -> (PathBuf, u64, Vec<u8>) {
        let root = std::env::temp_dir().join(format!(
            "turna-ops-{}-{}",
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
            "check_integrity": request.check_integrity,
        }))
        .unwrap();
        let handle = alloc_engine().unwrap();
        open_collection(handle, &body).unwrap();
        (root, handle, body)
    }

    fn call(handle: u64, op: u32, body: Value) -> Result<Value, i32> {
        dispatch(handle, op, &serde_json::to_vec(&body).unwrap())
    }

    fn import(handle: u64, file: &Path, with_scheduling: bool) -> Result<Value, i32> {
        call(
            handle,
            OP_IMPORT_PACKAGE,
            json!({
                "package_path": file.to_string_lossy(),
                "with_scheduling": with_scheduling,
                "with_deck_configs": true,
            }),
        )
    }

    #[test]
    fn import_all_small_fixtures_matches_manifest_and_unicode() {
        let packages = manifest()["packages"].as_array().unwrap().clone();
        for pkg in packages {
            let file = package_path(pkg["file"].as_str().unwrap());
            let (root, handle, _) = temp_open();
            let imported = import(
                handle,
                &file,
                pkg["withScheduling"].as_bool().unwrap_or(false),
            )
            .unwrap_or_else(|status| panic!("{} status {status}", file.display()));
            assert_eq!(
                imported["note_count"].as_u64().unwrap(),
                pkg["expectedNotes"].as_u64().unwrap(),
                "{}",
                file.display()
            );
            assert_eq!(
                imported["card_count"].as_u64().unwrap(),
                pkg["expectedCards"].as_u64().unwrap(),
                "{}",
                file.display()
            );
            assert!(!imported["new_note_ids"].as_array().unwrap().is_empty());

            let searched = call(handle, OP_SEARCH_CARDS, json!({"search": ""})).unwrap();
            if file.file_name().unwrap() == "01-basic-unicode.apkg" {
                let fields = searched["notes"][0]["fields"].as_array().unwrap();
                let joined = fields
                    .iter()
                    .map(|f| f.as_str().unwrap())
                    .collect::<Vec<_>>()
                    .join(" ");
                assert!(joined.contains("你好"));
                assert!(joined.contains("नमस्ते"));
                assert!(joined.contains("🙂"));
            }
            free_engine(handle).unwrap();
            let _ = fs::remove_dir_all(root);
        }
    }

    #[test]
    fn invalid_and_missing_packages_are_structured() {
        let (root, handle, _) = temp_open();
        assert_eq!(
            import(handle, Path::new("/no/such/turna-spike.apkg"), false).unwrap_err(),
            STATUS_PACKAGE_NOT_FOUND
        );
        let junk = root.join("not-a-zip.apkg");
        fs::write(&junk, b"not a zip").unwrap();
        assert_eq!(
            import(handle, &junk, false).unwrap_err(),
            STATUS_PACKAGE_INVALID
        );
        assert_eq!(
            dispatch(handle, OP_IMPORT_PACKAGE, br#"{"package_path":"rel.apkg"}"#).unwrap_err(),
            STATUS_INVALID_ARGUMENT
        );
        assert_eq!(
            import(0, Path::new("/no/such/turna-spike.apkg"), false).unwrap_err(),
            STATUS_INVALID_HANDLE
        );
        check_collection(handle).unwrap();
        free_engine(handle).unwrap();
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn render_goldens_match_official_html() {
        let cases = [
            ("01-basic-unicode.apkg", "01-basic-unicode.json"),
            ("02-basic-reversed.apkg", "02-basic-reversed.json"),
            ("04-cloze-multi-ord.apkg", "04-cloze-multi-ord.json"),
            ("05-frontside-css.apkg", "05-frontside-css.json"),
            ("06-media-paths.apkg", "06-media-paths.json"),
        ];
        for (pkg, expected_name) in cases {
            let (root, handle, _) = temp_open();
            import(handle, &package_path(pkg), false).unwrap();
            let searched = call(handle, OP_SEARCH_CARDS, json!({"search": ""})).unwrap();
            let mut rendered = Vec::new();
            for card in searched["cards"].as_array().unwrap() {
                let card_id = card["card_id"].as_i64().unwrap();
                let one = call(
                    handle,
                    OP_RENDER_CARD,
                    json!({"card_id": card_id, "browser": false}),
                )
                .unwrap();
                rendered.push(one);
            }
            let expected: Value =
                serde_json::from_str(&fs::read_to_string(expected_path(expected_name)).unwrap())
                    .unwrap();
            let expected_cards = expected["cards"].as_array().unwrap();
            assert_eq!(rendered.len(), expected_cards.len(), "{pkg}");
            for exp in expected_cards {
                let match_one = rendered.iter().find(|got| {
                    got["question_html"] == exp["questionHtml"]
                        && got["answer_html"] == exp["answerHtml"]
                        && got["css"] == exp["css"]
                });
                assert!(
                    match_one.is_some(),
                    "{pkg} missing golden\nexpected Q: {}\ngot: {:?}",
                    exp["questionHtml"],
                    rendered
                        .iter()
                        .map(|g| g["question_html"].as_str().unwrap_or(""))
                        .collect::<Vec<_>>()
                );
            }
            if pkg == "06-media-paths.apkg" {
                let av = rendered[0]["answer_av_tags"].as_array().unwrap();
                assert!(
                    av.iter().any(|tag| {
                        tag["kind"].as_str() == Some("sound_or_video")
                            && tag["filename"].as_str() == Some("paren (1).mp3")
                    }),
                    "{av:?}"
                );
                assert!(!rendered[0]["answer_text_without_av"]
                    .as_str()
                    .unwrap_or("")
                    .contains("[sound:"));
            }
            if pkg == "05-frontside-css.apkg" {
                assert!(rendered[0]["css"]
                    .as_str()
                    .unwrap()
                    .contains(".turna-fixture"));
                assert!(rendered[0]["answer_html"]
                    .as_str()
                    .unwrap()
                    .contains("FrontSideProbe"));
            }
            if pkg == "04-cloze-multi-ord.apkg" {
                let qs: Vec<_> = rendered
                    .iter()
                    .map(|c| c["question_html"].as_str().unwrap())
                    .collect();
                assert!(qs.iter().any(|q| q.contains("data-ordinal=\"1\"")));
                assert!(qs.iter().any(|q| q.contains("data-ordinal=\"2\"")));
            }
            free_engine(handle).unwrap();
            let _ = fs::remove_dir_all(root);
        }
    }

    #[test]
    fn queue_good_undo_reopen_and_stale_token() {
        let (root, handle, open_body) = temp_open();
        import(handle, &package_path("08-scheduling.apkg"), true).unwrap();
        call(handle, OP_SET_CURRENT_DECK, json!({"deck_id": 1})).unwrap();
        let queue = call(handle, OP_GET_REVIEW_QUEUE, json!({"fetch_limit": 10})).unwrap();
        let first = &queue["cards"][0];
        let card_id = first["card_id"].as_i64().unwrap();
        let token = first["answer_token"].as_u64().unwrap();
        let labels = &first["labels"];
        assert!(!labels["again"].as_str().unwrap().is_empty());
        assert!(!labels["hard"].as_str().unwrap().is_empty());
        assert!(!labels["good"].as_str().unwrap().is_empty());
        assert!(!labels["easy"].as_str().unwrap().is_empty());

        let before = call(handle, OP_SEARCH_CARDS, json!({"search": ""})).unwrap();
        let before_card = before["cards"]
            .as_array()
            .unwrap()
            .iter()
            .find(|c| c["card_id"] == card_id)
            .unwrap()
            .clone();
        let answered = call(
            handle,
            OP_ANSWER_CARD,
            json!({"card_id": card_id, "rating": "good", "answer_token": token}),
        )
        .unwrap();
        assert_ne!(answered["queue"], before_card["queue"]);
        assert!(answered["revlog_count"].as_u64().unwrap() >= 1);

        let undo_status = call(handle, OP_GET_UNDO_STATUS, json!({})).unwrap();
        assert_eq!(undo_status["can_undo"], true);

        assert_eq!(
            call(
                handle,
                OP_ANSWER_CARD,
                json!({"card_id": card_id, "rating": "good", "answer_token": token}),
            )
            .unwrap_err(),
            STATUS_SCHEDULING_CONTEXT_STALE
        );

        call(handle, OP_UNDO, json!({})).unwrap();
        let after_undo = call(handle, OP_SEARCH_CARDS, json!({"search": ""})).unwrap();
        let undone = after_undo["cards"]
            .as_array()
            .unwrap()
            .iter()
            .find(|c| c["card_id"] == card_id)
            .unwrap();
        assert_eq!(undone["queue"], before_card["queue"]);
        assert_eq!(undone["due"], before_card["due"]);

        let queue2 = call(handle, OP_GET_REVIEW_QUEUE, json!({"fetch_limit": 10})).unwrap();
        let token2 = queue2["cards"][0]["answer_token"].as_u64().unwrap();
        let card2 = queue2["cards"][0]["card_id"].as_i64().unwrap();
        call(
            handle,
            OP_ANSWER_CARD,
            json!({"card_id": card2, "rating": "good", "answer_token": token2}),
        )
        .unwrap();
        let persisted_queue = call(handle, OP_SEARCH_CARDS, json!({"search": ""})).unwrap();
        let persisted = persisted_queue["cards"]
            .as_array()
            .unwrap()
            .iter()
            .find(|c| c["card_id"] == card2)
            .unwrap()
            .clone();

        close_collection(handle).unwrap();
        open_collection(handle, &open_body).unwrap();
        let reopened = call(handle, OP_SEARCH_CARDS, json!({"search": ""})).unwrap();
        let again = reopened["cards"]
            .as_array()
            .unwrap()
            .iter()
            .find(|c| c["card_id"] == card2)
            .unwrap();
        assert_eq!(again["queue"], persisted["queue"]);

        assert_eq!(
            call(
                handle,
                OP_ANSWER_CARD,
                json!({"card_id": card2, "rating": "good", "answer_token": token2}),
            )
            .unwrap_err(),
            STATUS_SCHEDULING_CONTEXT_STALE
        );
        assert_eq!(
            call(handle, OP_UNDO, json!({})).unwrap_err(),
            STATUS_UNDO_UNAVAILABLE
        );

        free_engine(handle).unwrap();
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn cancel_import_does_not_report_success_and_collection_checks() {
        let (root, handle, open_body) = temp_open();
        let large = fixture_root().join("generated/10-large-generated-5000.apkg");
        let target = if large.exists() {
            large
        } else {
            package_path("01-basic-unicode.apkg")
        };
        let cancel_handle = handle;
        let canceler = std::thread::spawn(move || {
            for _ in 0..2_000 {
                let _ = request_cancel(cancel_handle);
                std::thread::sleep(std::time::Duration::from_micros(50));
            }
        });
        let err = import(handle, &target, false).unwrap_err();
        let _ = canceler.join();
        assert_eq!(err, STATUS_IMPORT_CANCELLED);
        {
            let slot = slot(handle).unwrap();
            let mut engine = slot.engine.lock().unwrap();
            let col = engine.collection.as_mut().unwrap();
            assert!(integrity_ok(col).unwrap());
        }
        close_collection(handle).unwrap();
        open_collection(handle, &open_body).unwrap();
        check_collection(handle).unwrap();
        free_engine(handle).unwrap();
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn empty_undo_and_missing_card_are_structured() {
        let (root, handle, _) = temp_open();
        assert_eq!(
            call(handle, OP_UNDO, json!({})).unwrap_err(),
            STATUS_UNDO_UNAVAILABLE
        );
        assert_eq!(
            call(handle, OP_RENDER_CARD, json!({"card_id": 1})).unwrap_err(),
            STATUS_CARD_NOT_FOUND
        );
        assert_eq!(
            dispatch(9_999_999, OP_SEARCH_CARDS, b"{}").unwrap_err(),
            STATUS_INVALID_HANDLE
        );
        free_engine(handle).unwrap();
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn host_metrics_record_import_render_queue() {
        let large = fixture_root().join("generated/10-large-generated-5000.apkg");
        let pkg = if large.exists() {
            large
        } else {
            package_path("01-basic-unicode.apkg")
        };
        let (root, handle, _) = temp_open();
        let t0 = Instant::now();
        let imported = import(handle, &pkg, false).unwrap();
        let import_ms = t0.elapsed().as_millis();
        let searched = call(handle, OP_SEARCH_CARDS, json!({"search": ""})).unwrap();
        let card_id = searched["cards"][0]["card_id"].as_i64().unwrap();
        let first = Instant::now();
        call(handle, OP_RENDER_CARD, json!({"card_id": card_id})).unwrap();
        let first_render_ms = first.elapsed().as_micros();
        let mut samples = Vec::new();
        for _ in 0..100 {
            let start = Instant::now();
            call(handle, OP_RENDER_CARD, json!({"card_id": card_id})).unwrap();
            samples.push(start.elapsed().as_micros());
        }
        samples.sort_unstable();
        let p50 = samples[49];
        let p95 = samples[94];
        let p99 = samples[98];
        call(handle, OP_SET_CURRENT_DECK, json!({"deck_id": 1})).ok();
        let q0 = Instant::now();
        let queued = call(handle, OP_GET_REVIEW_QUEUE, json!({"fetch_limit": 10}));
        let queue_ms = q0.elapsed().as_micros();
        let mut answer_ms = 0u128;
        let mut undo_ms = 0u128;
        if let Ok(queue) = queued {
            let cid = queue["cards"][0]["card_id"].as_i64().unwrap();
            let token = queue["cards"][0]["answer_token"].as_u64().unwrap();
            let a0 = Instant::now();
            let _ = call(
                handle,
                OP_ANSWER_CARD,
                json!({"card_id": cid, "rating": "good", "answer_token": token}),
            );
            answer_ms = a0.elapsed().as_micros();
            let u0 = Instant::now();
            let _ = call(handle, OP_UNDO, json!({}));
            undo_ms = u0.elapsed().as_micros();
        }
        eprintln!(
            "TURNA_SPIKE_METRICS import_ms={import_ms} notes={} cards={} first_render_us={first_render_ms} warm_p50_us={p50} warm_p95_us={p95} warm_p99_us={p99} queue_us={queue_ms} answer_us={answer_ms} undo_us={undo_ms}",
            imported["note_count"],
            imported["card_count"],
        );
        if let Ok(path) = std::env::var("TURNA_SPIKE_METRICS") {
            fs::write(
                path,
                format!(
                    "import_ms={import_ms}\nnotes={}\ncards={}\nfirst_render_us={first_render_ms}\nwarm_p50_us={p50}\nwarm_p95_us={p95}\nwarm_p99_us={p99}\nqueue_us={queue_ms}\nanswer_us={answer_ms}\nundo_us={undo_ms}\npackage={}\n",
                    imported["note_count"],
                    imported["card_count"],
                    pkg.display()
                ),
            )
            .unwrap();
        }
        free_engine(handle).unwrap();
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn import_100k_or_record_nogo() {
        let pkg = fixture_root().join("generated/10-large-generated-100000.apkg");
        if !pkg.exists() {
            eprintln!("TURNA_SPIKE_100K missing {}", pkg.display());
            return;
        }
        let (root, handle, _) = temp_open();
        let t0 = Instant::now();
        let imported = import(handle, &pkg, false);
        let import_ms = t0.elapsed().as_millis();
        match imported {
            Ok(value) => {
                eprintln!(
                    "TURNA_SPIKE_100K ok import_ms={import_ms} notes={} cards={}",
                    value["note_count"], value["card_count"]
                );
                if let Ok(path) = std::env::var("TURNA_SPIKE_100K") {
                    fs::write(
                        path,
                        format!(
                            "status=ok\nimport_ms={import_ms}\nnotes={}\ncards={}\npackage={}\n",
                            value["note_count"],
                            value["card_count"],
                            pkg.display()
                        ),
                    )
                    .unwrap();
                }
                assert_eq!(value["note_count"], 100000);
                assert_eq!(value["card_count"], 100000);
            }
            Err(status) => {
                eprintln!("TURNA_SPIKE_100K nogo status={status} import_ms={import_ms}");
                if let Ok(path) = std::env::var("TURNA_SPIKE_100K") {
                    fs::write(
                        path,
                        format!("status=nogo\nnative_status={status}\nimport_ms={import_ms}\n"),
                    )
                    .unwrap();
                }
                panic!("100k import failed status={status}");
            }
        }
        free_engine(handle).unwrap();
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn duplicate_import_classifies_log() {
        let (root, handle, _) = temp_open();
        let file = package_path("01-basic-unicode.apkg");
        let first = import(handle, &file, false).unwrap();
        assert!(!first["new_note_ids"].as_array().unwrap().is_empty());
        let second = import(handle, &file, false).unwrap();
        assert!(
            !second["duplicate_note_ids"].as_array().unwrap().is_empty()
                || second["note_count"] == first["note_count"]
        );
        free_engine(handle).unwrap();
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn official_av_tags_distinguish_sound_and_tts() {
        let col = anki::collection::CollectionBuilder::default()
            .build()
            .unwrap();
        let html = "[sound:hello.mp3] [anki:tts lang=en_US]Hello[/anki:tts]";
        let (text, tags) = extract_av_tags(html.to_string(), true, col.tr());
        let mapped: Vec<Value> = tags.iter().map(proto_av_tag_json).collect();
        assert!(
            mapped
                .iter()
                .any(|tag| { tag["kind"] == "sound_or_video" && tag["filename"] == "hello.mp3" }),
            "{mapped:?}"
        );
        assert!(
            mapped.iter().any(|tag| {
                tag["kind"] == "tts" && tag["lang"] == "en_US" && tag["fieldText"] == "Hello"
            }),
            "{mapped:?}"
        );
        assert!(!text.contains("[sound:"));
        assert!(!text.contains("[anki:tts"));
        col.close(None).unwrap();
    }
}
