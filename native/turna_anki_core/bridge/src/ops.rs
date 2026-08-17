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
use anki_proto::scheduler::bury_or_suspend_cards_request::Mode as BuryOrSuspendMode;
use anki_proto::scheduler::unbury_deck_request::Mode as UnburyDeckMode;
use anki::search::SortMode;
use anki::decks::DeckKind;
use anki::services::CollectionService;
use anki::services::SchedulerService;
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
use crate::engine::OP_COMPARE_TYPED_ANSWER;
use crate::engine::OP_DESCRIBE_NEXT_STATES;
use crate::engine::OP_EXTRACT_CLOZE_FOR_TYPING;
use crate::engine::OP_BURY_OR_SUSPEND_CARDS;
use crate::engine::OP_CONGRATS_INFO;
use crate::engine::OP_COUNTS_FOR_DECK_TODAY;
use crate::engine::OP_GET_REVIEW_QUEUE;
use crate::engine::OP_GET_UNDO_STATUS;
use crate::engine::OP_IMPORT_PACKAGE;
use crate::engine::OP_LATEST_PROGRESS;
use crate::engine::OP_LIST_DECK_TREE;
use crate::engine::OP_REDO;
use crate::engine::OP_RENDER_CARD;
use crate::engine::OP_SEARCH_CARDS;
use crate::engine::OP_SET_CURRENT_DECK;
use crate::engine::OP_UNDO;
use crate::engine::STATUS_DECK_NOT_FOUND;
use crate::engine::STATUS_REDO_UNAVAILABLE;
use crate::engine::MAX_RENDER_HTML_BYTES;
use crate::engine::MAX_RESPONSE_BYTES;
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
#[serde(rename_all = "camelCase")]
struct RenderRequest {
    #[serde(alias = "card_id")]
    card_id: i64,
    #[serde(default)]
    browser: bool,
    #[serde(default = "default_true", alias = "include_av_tags")]
    include_av_tags: bool,
}

#[derive(Debug, Deserialize)]
struct SearchRequest {
    #[serde(default)]
    search: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DeckRequest {
    #[serde(default = "default_deck", alias = "deck_id")]
    deck_id: i64,
}

fn default_deck() -> i64 {
    1
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct QueueRequest {
    #[serde(default = "default_fetch", alias = "fetch_limit")]
    fetch_limit: usize,
}

fn default_fetch() -> usize {
    10
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct TokenRequest {
    #[serde(alias = "answer_token")]
    answer_token: String,
    #[serde(default)]
    #[allow(dead_code)]
    session_id: Option<String>,
    #[serde(default)]
    #[allow(dead_code)]
    queue_epoch: Option<u64>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct AnswerRequest {
    #[serde(alias = "card_id")]
    card_id: i64,
    rating: String,
    #[serde(alias = "answer_token")]
    answer_token: String,
    #[serde(default)]
    session_id: Option<String>,
    #[serde(default)]
    queue_epoch: Option<u64>,
    #[serde(default)]
    answered_at_millis: Option<i64>,
    #[serde(default)]
    milliseconds_taken: u32,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct BuryOrSuspendRequest {
    action: String,
    #[serde(default)]
    card_ids: Vec<i64>,
    #[serde(default)]
    deck_id: Option<i64>,
}

const MAX_ELAPSED_MS: u32 = 24 * 60 * 60 * 1000;
const MAX_BURY_IDS: usize = 100;

pub fn dispatch_op(handle: u64, operation: u32, request: &[u8]) -> Result<Value, i32> {
    match operation {
        OP_IMPORT_PACKAGE => import_package(handle, request),
        OP_LATEST_PROGRESS => latest_progress(handle),
        OP_CANCEL_OPERATION => request_cancel(handle),
        OP_LIST_DECK_TREE => list_deck_tree(handle),
        OP_SEARCH_CARDS => search_cards(handle, request),
        OP_RENDER_CARD => render_card(handle, request),
        OP_COMPARE_TYPED_ANSWER => crate::typed::compare_typed_answer(handle, request),
        OP_EXTRACT_CLOZE_FOR_TYPING => crate::typed::extract_cloze_op(handle, request),
        OP_SET_CURRENT_DECK => set_current_deck(handle, request),
        OP_GET_REVIEW_QUEUE => get_review_queue(handle, request),
        OP_DESCRIBE_NEXT_STATES => describe_next_states(handle, request),
        OP_ANSWER_CARD => answer_card(handle, request),
        OP_GET_UNDO_STATUS => get_undo_status(handle),
        OP_UNDO => undo(handle),
        OP_REDO => redo(handle),
        OP_BURY_OR_SUSPEND_CARDS => bury_or_suspend(handle, request),
        OP_COUNTS_FOR_DECK_TODAY => counts_for_deck_today(handle, request),
        OP_CONGRATS_INFO => congrats_info(handle),
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

pub(crate) fn require_open<'a>(
    slot: &'a EngineSlot,
) -> Result<std::sync::MutexGuard<'a, Engine>, i32> {
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
    if request.len() > MAX_REQUEST_BYTES {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    let parsed: RenderRequest =
        serde_json::from_slice(request).map_err(|_| STATUS_INVALID_ARGUMENT)?;
    if parsed.card_id <= 0 {
        return Err(STATUS_INVALID_ARGUMENT);
    }
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
    if question.len() > MAX_RENDER_HTML_BYTES || answer.len() > MAX_RENDER_HTML_BYTES {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    let (q_display, q_tags) = if parsed.include_av_tags {
        extract_av_tags(question.clone(), true, col.tr())
    } else {
        (question.clone(), Vec::new())
    };
    let (a_display, a_tags) = if parsed.include_av_tags {
        extract_av_tags(answer.clone(), false, col.tr())
    } else {
        (answer.clone(), Vec::new())
    };
    let typed = crate::typed::typed_hint_json(col, parsed.card_id, &question, &answer)?;
    let card = col
        .storage
        .get_card(CardId(parsed.card_id))
        .map_err(|_| STATUS_RENDER_FAILED)?
        .ok_or(STATUS_CARD_NOT_FOUND)?;
    let template_ordinal = card.template_idx();
    let body_class = crate::display::body_class_for_ordinal(template_ordinal);
    let question_display = crate::display::encode_display_html(&q_display);
    let answer_display = crate::display::encode_display_html(&a_display);
    let css = crate::display::encode_display_css(&rendered.css);
    let payload = json!({
        "cardId": parsed.card_id,
        "questionHtml": question,
        "answerHtml": answer,
        "questionDisplayHtml": question_display,
        "answerDisplayHtml": answer_display,
        "css": css,
        "latexSvg": rendered.latex_svg,
        "isEmpty": rendered.is_empty,
        "questionAvTags": q_tags.iter().map(proto_av_tag_json).collect::<Vec<_>>(),
        "answerAvTags": a_tags.iter().map(proto_av_tag_json).collect::<Vec<_>>(),
        "typedAnswer": typed,
        "templateOrdinal": template_ordinal,
        "bodyClass": body_class,
    });
    let encoded = serde_json::to_vec(&payload).map_err(|_| STATUS_INTERNAL_ERROR)?;
    if encoded.len() > MAX_RESPONSE_BYTES {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    Ok(payload)
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
    if parsed.fetch_limit < 1 || parsed.fetch_limit > 100 {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    let slot = slot(handle)?;
    let mut engine = require_open(&slot)?;
    engine.begin_queue_epoch();
    let session_id = engine.session_id.clone();
    let queue_epoch = engine.queue_epoch;
    let col = engine.collection.as_mut().ok_or(STATUS_INVALID_STATE)?;
    let queued = col
        .get_queued_cards(parsed.fetch_limit, false)
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
    let mut cards = Vec::new();
    for (card_id, note_id, deck_id, ord, kind, states, labels) in prepared {
        let token = format!("tok-{}-{}-{}", session_id, queue_epoch, engine.next_token);
        engine.next_token = engine.next_token.wrapping_add(1).max(1);
        engine.tokens.insert(
            token.clone(),
            AnswerToken {
                session_id: session_id.clone(),
                queue_epoch,
                card_id,
                states,
            },
        );
        cards.push(json!({
            "cardId": card_id,
            "noteId": note_id,
            "deckId": deck_id,
            "templateOrdinal": ord,
            "queueKind": kind,
            "answerToken": token,
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
        "sessionId": session_id,
        "queueEpoch": queue_epoch,
        "newCount": new_count,
        "learningCount": learning_count,
        "reviewCount": review_count,
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
    if token.session_id != engine.session_id || token.queue_epoch != engine.queue_epoch {
        return Err(STATUS_SCHEDULING_CONTEXT_STALE);
    }
    let states = token.states.clone();
    let col = engine.collection.as_mut().ok_or(STATUS_INVALID_STATE)?;
    let labels = col.describe_next_states(&states).map_err(map_anki_error)?;
    Ok(json!({
        "answerToken": parsed.answer_token,
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
    if parsed.milliseconds_taken > MAX_ELAPSED_MS {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    let rating = parse_rating(&parsed.rating)?;
    let slot = slot(handle)?;
    let mut engine = require_open(&slot)?;
    let token = engine
        .tokens
        .remove(&parsed.answer_token)
        .ok_or(STATUS_SCHEDULING_CONTEXT_STALE)?;
    if token.session_id != engine.session_id
        || token.queue_epoch != engine.queue_epoch
        || token.card_id != parsed.card_id
    {
        return Err(STATUS_SCHEDULING_CONTEXT_STALE);
    }
    if let Some(session_id) = parsed.session_id.as_deref() {
        if session_id != token.session_id {
            return Err(STATUS_SCHEDULING_CONTEXT_STALE);
        }
    }
    if let Some(epoch) = parsed.queue_epoch {
        if epoch != token.queue_epoch {
            return Err(STATUS_SCHEDULING_CONTEXT_STALE);
        }
    }
    let new_state = match rating {
        Rating::Again => token.states.again,
        Rating::Hard => token.states.hard,
        Rating::Good => token.states.good,
        Rating::Easy => token.states.easy,
    };
    let answered_at = parsed
        .answered_at_millis
        .map(TimestampMillis)
        .unwrap_or_else(TimestampMillis::now);
    let col = engine.collection.as_mut().ok_or(STATUS_INVALID_STATE)?;
    let mut answer = CardAnswer {
        card_id: CardId(parsed.card_id),
        current_state: token.states.current,
        new_state,
        rating,
        answered_at,
        milliseconds_taken: parsed.milliseconds_taken,
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
    engine.invalidate_tokens();
    Ok(json!({
        "cardId": parsed.card_id,
        "queue": queue_name(card.queue_number()),
        "revlogCount": revlog,
        "millisecondsTaken": parsed.milliseconds_taken,
    }))
}

fn get_undo_status(handle: u64) -> Result<Value, i32> {
    let slot = slot(handle)?;
    let engine = require_open(&slot)?;
    let col = engine.collection.as_ref().ok_or(STATUS_INVALID_STATE)?;
    let status = col.undo_status();
    Ok(json!({
        "canUndo": status.undo.is_some(),
        "canRedo": status.redo.is_some(),
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
    let result = match col.undo() {
        Ok(_) => Ok(json!({ "undone": true })),
        Err(AnkiError::UndoEmpty) => Err(STATUS_UNDO_UNAVAILABLE),
        Err(err) => Err(map_anki_error(err)),
    };
    engine.invalidate_tokens();
    result
}

fn redo(handle: u64) -> Result<Value, i32> {
    let slot = slot(handle)?;
    let mut engine = require_open(&slot)?;
    let col = engine.collection.as_mut().ok_or(STATUS_INVALID_STATE)?;
    let result = match col.redo() {
        Ok(_) => Ok(json!({ "redone": true })),
        Err(AnkiError::UndoEmpty) => Err(STATUS_REDO_UNAVAILABLE),
        Err(err) => Err(map_anki_error(err)),
    };
    engine.invalidate_tokens();
    result
}

fn bury_or_suspend(handle: u64, request: &[u8]) -> Result<Value, i32> {
    let parsed: BuryOrSuspendRequest =
        serde_json::from_slice(request).map_err(|_| STATUS_INVALID_ARGUMENT)?;
    if parsed.card_ids.len() > MAX_BURY_IDS {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    let mut ids = parsed.card_ids;
    ids.sort_unstable();
    ids.dedup();
    if ids.iter().any(|id| *id <= 0) {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    let slot = slot(handle)?;
    let mut engine = require_open(&slot)?;
    let col = engine.collection.as_mut().ok_or(STATUS_INVALID_STATE)?;
    let deck = col.get_current_deck().map_err(map_anki_error)?;
    if matches!(deck.kind, DeckKind::Filtered(_)) {
        return Err(STATUS_INVALID_STATE);
    }
    let card_ids: Vec<CardId> = ids.iter().copied().map(CardId).collect();
    match parsed.action.as_str() {
        "bury_card" => {
            col.bury_or_suspend_cards(&card_ids, BuryOrSuspendMode::BuryUser)
                .map_err(map_anki_error)?;
        }
        "bury_siblings" => {
            if card_ids.len() != 1 {
                return Err(STATUS_INVALID_ARGUMENT);
            }
            let card = col
                .storage
                .get_card(card_ids[0])
                .map_err(map_anki_error)?
                .ok_or(STATUS_CARD_NOT_FOUND)?;
            col.bury_or_suspend_cards(&card_ids, BuryOrSuspendMode::BuryUser)
                .map_err(map_anki_error)?;
            let _ = card;
        }
        "unbury_deck" => {
            let deck_id = DeckId(parsed.deck_id.unwrap_or(deck.id.0));
            col.unbury_deck(deck_id, UnburyDeckMode::All)
                .map_err(map_anki_error)?;
        }
        "suspend_cards" => {
            col.bury_or_suspend_cards(&card_ids, BuryOrSuspendMode::Suspend)
                .map_err(map_anki_error)?;
        }
        "unsuspend_cards" => {
            col.unbury_or_unsuspend_cards(&card_ids)
                .map_err(map_anki_error)?;
        }
        _ => return Err(STATUS_INVALID_ARGUMENT),
    }
    engine.invalidate_tokens();
    Ok(json!({
        "action": parsed.action,
        "cardIds": ids,
    }))
}

fn counts_for_deck_today(handle: u64, request: &[u8]) -> Result<Value, i32> {
    let parsed: DeckRequest = if request.is_empty() {
        DeckRequest { deck_id: 1 }
    } else {
        serde_json::from_slice(request).map_err(|_| STATUS_INVALID_ARGUMENT)?
    };
    let slot = slot(handle)?;
    let mut engine = require_open(&slot)?;
    let col = engine.collection.as_mut().ok_or(STATUS_INVALID_STATE)?;
    let counts = SchedulerService::counts_for_deck_today(
        col,
        anki_proto::decks::DeckId { did: parsed.deck_id },
    )
    .map_err(|_| STATUS_DECK_NOT_FOUND)?;
    Ok(json!({
        "deckId": parsed.deck_id,
        "newStudied": counts.new,
        "reviewStudied": counts.review,
    }))
}

fn congrats_info(handle: u64) -> Result<Value, i32> {
    let slot = slot(handle)?;
    let mut engine = require_open(&slot)?;
    let col = engine.collection.as_mut().ok_or(STATUS_INVALID_STATE)?;
    let info = col.congrats_info().map_err(map_anki_error)?;
    Ok(json!({
        "learnRemaining": info.learn_remaining,
        "reviewRemaining": info.review_remaining,
        "newRemaining": info.new_remaining,
        "haveSchedBuried": info.have_sched_buried,
        "haveUserBuried": info.have_user_buried,
        "isFilteredDeck": info.is_filtered_deck,
        "secsUntilNextLearn": info.secs_until_next_learn,
    }))
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
            "turna-ops-{}-{:?}-{}",
            std::process::id(),
            std::thread::current().id(),
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
            ("03-optional-reversed.apkg", "03-optional-reversed.json"),
            ("04-cloze-multi-ord.apkg", "04-cloze-multi-ord.json"),
            ("05-frontside-css.apkg", "05-frontside-css.json"),
            ("06-media-paths.apkg", "06-media-paths.json"),
            ("07-typed-answer.apkg", "07-typed-answer.json"),
            ("08-scheduling.apkg", "08-scheduling.json"),
            ("09-legacy-package.apkg", "09-legacy-package.json"),
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
                    got["questionHtml"] == exp["questionHtml"]
                        && got["answerHtml"] == exp["answerHtml"]
                        && got["css"] == exp["css"]
                });
                assert!(
                    match_one.is_some(),
                    "{pkg} missing golden\nexpected Q: {}\ngot: {:?}",
                    exp["questionHtml"],
                    rendered
                        .iter()
                        .map(|g| g["questionHtml"].as_str().unwrap_or(""))
                        .collect::<Vec<_>>()
                );
            }
            if pkg == "06-media-paths.apkg" {
                let av = rendered[0]["answerAvTags"].as_array().unwrap();
                assert!(
                    av.iter().any(|tag| {
                        tag["kind"].as_str() == Some("sound_or_video")
                            && tag["filename"].as_str() == Some("paren (1).mp3")
                    }),
                    "{av:?}"
                );
                assert!(!rendered[0]["answerDisplayHtml"]
                    .as_str()
                    .unwrap_or("")
                    .contains("[sound:"));
            }
            if pkg == "05-frontside-css.apkg" {
                assert!(rendered[0]["css"]
                    .as_str()
                    .unwrap()
                    .contains(".turna-fixture"));
                assert!(rendered[0]["answerHtml"]
                    .as_str()
                    .unwrap()
                    .contains("FrontSideProbe"));
            }
            if pkg == "04-cloze-multi-ord.apkg" {
                let qs: Vec<_> = rendered
                    .iter()
                    .map(|c| c["questionHtml"].as_str().unwrap())
                    .collect();
                assert!(qs.iter().any(|q| q.contains("data-ordinal=\"1\"")));
                assert!(qs.iter().any(|q| q.contains("data-ordinal=\"2\"")));
            }
            let body = rendered[0]["bodyClass"].as_str().unwrap_or("");
            assert!(body.starts_with("card card"), "{pkg} bodyClass={body}");
            assert!(!body.contains("isWin") && !body.contains("isMac") && !body.contains("isLin"));
            assert!(rendered[0]["templateOrdinal"].as_u64().is_some(), "{pkg}");
            if pkg == "07-typed-answer.apkg" {
                let typed = &rendered[0]["typedAnswer"];
                assert_eq!(typed["marker"], "[[type:Back]]");
                assert_eq!(typed["combining"], true);
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
        let queue = call(handle, OP_GET_REVIEW_QUEUE, json!({"fetchLimit": 10})).unwrap();
        let first = &queue["cards"][0];
        let card_id = first["cardId"].as_i64().unwrap();
        let token = first["answerToken"].as_str().unwrap();
        let session_id = queue["sessionId"].as_str().unwrap();
        let epoch = queue["queueEpoch"].as_u64().unwrap();
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
            json!({
                "cardId": card_id,
                "rating": "good",
                "answerToken": token,
                "sessionId": session_id,
                "queueEpoch": epoch,
                "millisecondsTaken": 8421
            }),
        )
        .unwrap();
        assert_ne!(answered["queue"], before_card["queue"]);
        assert!(answered["revlogCount"].as_u64().unwrap() >= 1);
        assert_eq!(answered["millisecondsTaken"], 8421);

        let undo_status = call(handle, OP_GET_UNDO_STATUS, json!({})).unwrap();
        assert_eq!(undo_status["can_undo"], true);

        assert_eq!(
            call(
                handle,
                OP_ANSWER_CARD,
                json!({"cardId": card_id, "rating": "good", "answerToken": token}),
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

        let queue2 = call(handle, OP_GET_REVIEW_QUEUE, json!({"fetchLimit": 10})).unwrap();
        let token2 = queue2["cards"][0]["answerToken"].as_str().unwrap();
        let card2 = queue2["cards"][0]["cardId"].as_i64().unwrap();
        call(
            handle,
            OP_ANSWER_CARD,
            json!({
                "cardId": card2,
                "rating": "good",
                "answerToken": token2,
                "millisecondsTaken": 1200
            }),
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
                json!({"cardId": card2, "rating": "good", "answerToken": token2}),
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
    fn redo_bury_counts_and_congrats_use_official_apis() {
        let (root, handle, _) = temp_open();
        import(handle, &package_path("08-scheduling.apkg"), true).unwrap();
        call(handle, OP_SET_CURRENT_DECK, json!({"deckId": 1})).unwrap();
        let queue = call(handle, OP_GET_REVIEW_QUEUE, json!({"fetchLimit": 1})).unwrap();
        let card_id = queue["cards"][0]["cardId"].as_i64().unwrap();
        let token = queue["cards"][0]["answerToken"].as_str().unwrap();
        call(
            handle,
            OP_ANSWER_CARD,
            json!({
                "cardId": card_id,
                "rating": "good",
                "answerToken": token,
                "millisecondsTaken": 1500
            }),
        )
        .unwrap();
        call(handle, OP_UNDO, json!({})).unwrap();
        call(handle, OP_REDO, json!({})).unwrap();
        let counts = call(handle, OP_COUNTS_FOR_DECK_TODAY, json!({"deckId": 1})).unwrap();
        assert!(counts["newStudied"].as_i64().is_some() || counts["reviewStudied"].as_i64().is_some());
        let congrats = call(handle, OP_CONGRATS_INFO, json!({})).unwrap();
        assert!(congrats.get("isFilteredDeck").is_some());
        let queue2 = call(handle, OP_GET_REVIEW_QUEUE, json!({"fetchLimit": 1})).unwrap();
        let cid2 = queue2["cards"][0]["cardId"].as_i64().unwrap();
        call(
            handle,
            OP_BURY_OR_SUSPEND_CARDS,
            json!({"action": "suspend_cards", "cardIds": [cid2]}),
        )
        .unwrap();
        assert_eq!(
            call(handle, OP_GET_REVIEW_QUEUE, json!({"fetchLimit": 0})).unwrap_err(),
            STATUS_INVALID_ARGUMENT
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
        let queued = call(handle, OP_GET_REVIEW_QUEUE, json!({"fetchLimit": 10}));
        let queue_ms = q0.elapsed().as_micros();
        let mut answer_ms = 0u128;
        let mut undo_ms = 0u128;
        if let Ok(queue) = queued {
            let cid = queue["cards"][0]["cardId"].as_i64().unwrap();
            let token = queue["cards"][0]["answerToken"].as_str().unwrap();
            let a0 = Instant::now();
            let _ = call(
                handle,
                OP_ANSWER_CARD,
                json!({"cardId": cid, "rating": "good", "answerToken": token, "millisecondsTaken": 500}),
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

    #[test]
    fn typed_answer_uses_official_compare_and_cloze_extract() {
        let (root, handle, _) = temp_open();
        import(handle, &package_path("07-typed-answer.apkg"), false).unwrap();
        let searched = call(handle, OP_SEARCH_CARDS, json!({"search": ""})).unwrap();
        let card_id = searched["cards"][0]["card_id"].as_i64().unwrap();
        let rendered = call(handle, OP_RENDER_CARD, json!({"cardId": card_id})).unwrap();
        assert_eq!(rendered["typedAnswer"]["marker"], "[[type:Back]]");
        let compared = call(
            handle,
            OP_COMPARE_TYPED_ANSWER,
            json!({
                "cardId": card_id,
                "marker": "[[type:Back]]",
                "provided": "typed-back"
            }),
        )
        .unwrap();
        assert_eq!(compared["hasExpected"], true);
        let html = compared["comparisonHtml"].as_str().unwrap();
        assert!(html.contains("typeans"), "{html}");
        assert!(html.contains("typeGood") || html.contains("typed-back"), "{html}");

        let missing = call(
            handle,
            OP_COMPARE_TYPED_ANSWER,
            json!({
                "cardId": card_id,
                "marker": "[[type:NoSuchField]]",
                "provided": "x"
            }),
        )
        .unwrap_err();
        assert_eq!(missing, crate::engine::STATUS_TYPED_FIELD_NOT_FOUND);

        import(handle, &package_path("04-cloze-multi-ord.apkg"), false).unwrap();
        let extracted = call(
            handle,
            OP_EXTRACT_CLOZE_FOR_TYPING,
            json!({"text": "The capital of {{c1::Türkiye}} is {{c2::安卡拉}}.", "ordinal": 1}),
        )
        .unwrap();
        assert_eq!(extracted["text"], "Türkiye");
        let empty = call(
            handle,
            OP_EXTRACT_CLOZE_FOR_TYPING,
            json!({"text": "{{c2::foo}}", "ordinal": 1}),
        )
        .unwrap_err();
        assert_eq!(empty, crate::engine::STATUS_TYPED_CLOZE_EMPTY);
        free_engine(handle).unwrap();
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn render_missing_card_and_closed_collection_are_structured() {
        let (root, handle, _) = temp_open();
        assert_eq!(
            call(handle, OP_RENDER_CARD, json!({"cardId": 1})).unwrap_err(),
            STATUS_CARD_NOT_FOUND
        );
        close_collection(handle).unwrap();
        assert_eq!(
            call(handle, OP_RENDER_CARD, json!({"cardId": 1})).unwrap_err(),
            crate::engine::STATUS_INVALID_STATE
        );
        free_engine(handle).unwrap();
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn alloc_free_returns_handle_count_to_baseline() {
        let handles: Vec<u64> = (0..20).map(|_| alloc_engine().unwrap()).collect();
        let mid = crate::engine::live_handle_count().unwrap();
        for handle in handles {
            free_engine(handle).unwrap();
        }
        let after = crate::engine::live_handle_count().unwrap();
        assert!(
            after + 20 <= mid + 4,
            "owned handles leaked mid={mid} after={after}"
        );
    }

    #[test]
    fn engine_info_capabilities_include_render_ops() {
        let info = crate::contract::engine_info_payload();
        let caps = info["capabilities"].as_array().unwrap();
        for name in [
            "RENDER_CARD",
            "COMPARE_TYPED_ANSWER",
            "EXTRACT_CLOZE_FOR_TYPING",
            "GET_PROJECTION_SCHEMAS",
            "BEGIN_PROJECTION_READ",
            "GET_PROJECTION_ROWS_BATCH",
            "LIST_DECK_TREE",
            "GET_REVIEW_QUEUE",
            "ANSWER_CARD",
            "REDO",
            "BURY_OR_SUSPEND_CARDS",
            "COUNTS_FOR_DECK_TODAY",
            "CONGRATS_INFO",
        ] {
            assert!(
                caps.iter().any(|c| c.as_str() == Some(name)),
                "missing {name} in {caps:?}"
            );
        }
        assert_eq!(info["contractMinor"], 3);
    }
}
