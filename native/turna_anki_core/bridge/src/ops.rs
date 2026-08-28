//! Official Collection operations: import, query, render, queue, answer, undo.

use std::path::PathBuf;
use std::time::Instant;

use anki::card::CardQueueNumber;
use anki::card_rendering::extract_av_tags;
use anki::decks::DeckKind;
use anki::error::AnkiError;
use anki::import_export::package::ImportAnkiPackageOptions;
use anki::prelude::*;
use anki::scheduler::answering::CardAnswer;
use anki::scheduler::answering::Rating;
use anki::search::SortMode;
use anki::services::CardsService;
use anki::services::CollectionService;
use anki::services::SchedulerService;
use anki::services::StatsService;
use anki::timestamp::TimestampMillis;
use anki_proto::scheduler::bury_or_suspend_cards_request::Mode as BuryOrSuspendMode;
use anki_proto::scheduler::unbury_deck_request::Mode as UnburyDeckMode;
use serde::Deserialize;
use serde_json::json;
use serde_json::Value;

use crate::engine::slot;
use crate::engine::AnswerToken;
use crate::engine::BusyGuard;
use crate::engine::Engine;
use crate::engine::EngineSlot;
use crate::engine::EngineState;
use crate::engine::TokenConsumption;
use crate::engine::MAX_RENDER_HTML_BYTES;
use crate::engine::MAX_REQUEST_BYTES;
use crate::engine::MAX_RESPONSE_BYTES;
use crate::engine::OP_ANSWER_CARD;
use crate::engine::OP_BURY_OR_SUSPEND_CARDS;
use crate::engine::OP_CANCEL_OPERATION;
use crate::engine::OP_COMPARE_TYPED_ANSWER;
use crate::engine::OP_CONGRATS_INFO;
use crate::engine::OP_COUNTS_FOR_DECK_TODAY;
use crate::engine::OP_DELETE_CARDS;
use crate::engine::OP_DELETE_NOTES;
use crate::engine::OP_DESCRIBE_NEXT_STATES;
use crate::engine::OP_EXTRACT_CLOZE_FOR_TYPING;
use crate::engine::OP_GET_REVIEW_QUEUE;
use crate::engine::OP_GET_UNDO_STATUS;
use crate::engine::OP_IMPORT_PACKAGE;
use crate::engine::OP_LATEST_PROGRESS;
use crate::engine::OP_LIST_DECK_TREE;
use crate::engine::OP_REDO;
use crate::engine::OP_RENDER_CARD;
use crate::engine::OP_SCHEDULE_CARDS_AS_NEW;
use crate::engine::OP_ANSWER_AHEAD_CARDS;
use crate::engine::OP_ENSURE_TODAY_NEW_QUOTA;
use crate::engine::OP_SEARCH_CARDS;
use crate::engine::OP_SET_CURRENT_DECK;
use crate::engine::OP_STATS_FOR_CARDS_BATCH;
use crate::engine::OP_UNDO;
use crate::engine::STATUS_ANSWER_COMMIT_UNKNOWN;
use crate::engine::STATUS_ANSWER_FAILED;
use crate::engine::STATUS_BACKEND_PANIC;
use crate::engine::STATUS_CARD_NOT_FOUND;
use crate::engine::STATUS_COLLECTION_CORRUPT;
use crate::engine::STATUS_DECK_NOT_FOUND;
use crate::engine::STATUS_IMPORT_CANCELLED;
use crate::engine::STATUS_INTERNAL_ERROR;
use crate::engine::STATUS_INVALID_ARGUMENT;
use crate::engine::STATUS_INVALID_STATE;
use crate::engine::STATUS_IO_ERROR;
use crate::engine::STATUS_PACKAGE_INVALID;
use crate::engine::STATUS_PACKAGE_NOT_FOUND;
use crate::engine::STATUS_QUEUE_EMPTY;
use crate::engine::STATUS_REDO_UNAVAILABLE;
use crate::engine::STATUS_RENDER_FAILED;
use crate::engine::STATUS_SCHEDULER_BUSY;
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
    #[serde(default, alias = "intraday_learning_only")]
    intraday_learning_only: bool,
}

fn default_fetch() -> usize {
    1
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
    milliseconds_taken: i64,
    #[serde(default, alias = "client_mutation_id")]
    client_mutation_id: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct BuryOrSuspendRequest {
    #[serde(default)]
    mode: Option<String>,
    #[serde(default)]
    action: Option<String>,
    #[serde(default)]
    card_ids: Vec<i64>,
    #[serde(default)]
    note_ids: Vec<i64>,
    #[serde(default)]
    deck_id: Option<i64>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DeleteNotesRequest {
    #[serde(default)]
    note_ids: Vec<i64>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DeleteCardsRequest {
    #[serde(default)]
    card_ids: Vec<i64>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct StatsForCardsRequest {
    #[serde(default)]
    card_ids: Vec<i64>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ScheduleCardsAsNewRequest {
    #[serde(default)]
    card_ids: Vec<i64>,
}

const MAX_ELAPSED_MS: u32 = 24 * 60 * 60 * 1000;
const MAX_BURY_IDS: usize = 100;
const MAX_DELETE_NOTE_IDS: usize = 10_000;
const MAX_DELETE_CARD_IDS: usize = 10_000;
const MAX_STATS_CARD_IDS: usize = 200;
const MAX_SCHEDULE_AS_NEW_IDS: usize = 10_000;

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
        OP_DELETE_NOTES => delete_notes(handle, request),
        OP_DELETE_CARDS => delete_cards(handle, request),
        OP_STATS_FOR_CARDS_BATCH => stats_for_cards_batch(handle, request),
        OP_SCHEDULE_CARDS_AS_NEW => schedule_cards_as_new(handle, request),
        OP_ANSWER_AHEAD_CARDS => answer_ahead_cards(handle, request),
        OP_ENSURE_TODAY_NEW_QUOTA => ensure_today_new_quota(handle, request),
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
    if parsed.deck_id <= 0 {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    let slot = slot(handle)?;
    let mut engine = require_open(&slot)?;
    {
        let col = engine.collection.as_mut().ok_or(STATUS_INVALID_STATE)?;
        if col
            .get_deck(DeckId(parsed.deck_id))
            .map_err(map_anki_error)?
            .is_none()
        {
            return Err(STATUS_DECK_NOT_FOUND);
        }
        col.set_current_deck(DeckId(parsed.deck_id))
            .map_err(map_anki_error)?;
    }
    engine.invalidate_tokens();
    Ok(json!({
        "deckId": parsed.deck_id,
        "queueEpoch": engine.queue_epoch,
    }))
}

fn get_review_queue(handle: u64, request: &[u8]) -> Result<Value, i32> {
    let parsed: QueueRequest = if request.is_empty() {
        QueueRequest {
            fetch_limit: 1,
            intraday_learning_only: false,
        }
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
        .get_queued_cards(parsed.fetch_limit, parsed.intraday_learning_only)
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
                consumption: TokenConsumption::Pending,
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
    if parsed.milliseconds_taken < 0 || parsed.milliseconds_taken > i64::from(MAX_ELAPSED_MS) {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    let milliseconds_taken = parsed.milliseconds_taken as u32;
    let rating = parse_rating(&parsed.rating)?;
    let slot = slot(handle)?;
    let mut engine = require_open(&slot)?;
    if let Some(mutation_id) = parsed.client_mutation_id.as_deref() {
        if !mutation_id.is_empty() && engine.committed_mutations.contains(mutation_id) {
            return Err(STATUS_SCHEDULING_CONTEXT_STALE);
        }
    }
    {
        let token = engine
            .tokens
            .get(&parsed.answer_token)
            .ok_or(STATUS_SCHEDULING_CONTEXT_STALE)?;
        match token.consumption {
            TokenConsumption::Committed => return Err(STATUS_SCHEDULING_CONTEXT_STALE),
            TokenConsumption::InFlight => return Err(STATUS_SCHEDULER_BUSY),
            TokenConsumption::Unknown => return Err(STATUS_ANSWER_COMMIT_UNKNOWN),
            TokenConsumption::Pending | TokenConsumption::FailedUnwritten => {}
        }
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
    }
    let states = engine
        .tokens
        .get(&parsed.answer_token)
        .ok_or(STATUS_SCHEDULING_CONTEXT_STALE)?
        .states
        .clone();
    if let Some(token) = engine.tokens.get_mut(&parsed.answer_token) {
        token.consumption = TokenConsumption::InFlight;
    }
    if engine.debug_fail_before_answer {
        if let Some(token) = engine.tokens.get_mut(&parsed.answer_token) {
            token.consumption = TokenConsumption::FailedUnwritten;
        }
        return Err(STATUS_ANSWER_FAILED);
    }
    let pre_revlog = {
        let col = engine.collection.as_mut().ok_or(STATUS_INVALID_STATE)?;
        revlog_count(col, parsed.card_id)?
    };
    let answered_at = if engine.allow_injected_answered_at {
        parsed
            .answered_at_millis
            .map(TimestampMillis)
            .unwrap_or_else(TimestampMillis::now)
    } else {
        TimestampMillis::now()
    };
    let new_state = match rating {
        Rating::Again => states.again,
        Rating::Hard => states.hard,
        Rating::Good => states.good,
        Rating::Easy => states.easy,
    };
    let answer_result = {
        let col = engine.collection.as_mut().ok_or(STATUS_INVALID_STATE)?;
        let mut answer = CardAnswer {
            card_id: CardId(parsed.card_id),
            current_state: states.current,
            new_state,
            rating,
            answered_at,
            milliseconds_taken,
            custom_data: None,
            from_queue: true,
        };
        match col.answer_card(&mut answer) {
            Ok(output) => Ok(output),
            Err(err) => {
                let post_revlog = revlog_count(col, parsed.card_id).unwrap_or(pre_revlog);
                if post_revlog > pre_revlog {
                    Err(err)
                } else {
                    // Isolated review (allowedCardIds) may grade a card that is
                    // not the study-queue head. Anki then rejects from_queue.
                    answer.from_queue = false;
                    match col.answer_card(&mut answer) {
                        Ok(output) => {
                            col.clear_study_queues();
                            Ok(output)
                        }
                        Err(retry_err) => Err(retry_err),
                    }
                }
            }
        }
    };
    match answer_result {
        Ok(_) => {
            if engine.debug_fail_after_commit {
                if let Some(token) = engine.tokens.get_mut(&parsed.answer_token) {
                    token.consumption = TokenConsumption::Unknown;
                }
                return Err(STATUS_ANSWER_COMMIT_UNKNOWN);
            }
            let (queue, revlog) = {
                let col = engine.collection.as_mut().ok_or(STATUS_INVALID_STATE)?;
                let card = col
                    .storage
                    .get_card(CardId(parsed.card_id))
                    .map_err(map_anki_error)?
                    .ok_or(STATUS_CARD_NOT_FOUND)?;
                let revlog = revlog_count(col, parsed.card_id)?;
                (queue_name(card.queue_number()), revlog)
            };
            if let Some(token) = engine.tokens.get_mut(&parsed.answer_token) {
                token.consumption = TokenConsumption::Committed;
            }
            if let Some(mutation_id) = parsed.client_mutation_id.as_deref() {
                if !mutation_id.is_empty() {
                    engine.committed_mutations.insert(mutation_id.to_string());
                }
            }
            engine.invalidate_tokens();
            Ok(json!({
                "clientMutationId": parsed.client_mutation_id,
                "cardId": parsed.card_id,
                "rating": parsed.rating,
                "queue": queue,
                "revlogCount": revlog,
                "queueEpoch": engine.queue_epoch,
                "committed": true,
                "millisecondsTaken": milliseconds_taken,
            }))
        }
        Err(_) => {
            let post_revlog = engine
                .collection
                .as_mut()
                .and_then(|col| revlog_count(col, parsed.card_id).ok())
                .unwrap_or(pre_revlog);
            if post_revlog > pre_revlog {
                if let Some(token) = engine.tokens.get_mut(&parsed.answer_token) {
                    token.consumption = TokenConsumption::Unknown;
                }
                Err(STATUS_ANSWER_COMMIT_UNKNOWN)
            } else {
                if let Some(token) = engine.tokens.get_mut(&parsed.answer_token) {
                    token.consumption = TokenConsumption::FailedUnwritten;
                }
                Err(STATUS_ANSWER_FAILED)
            }
        }
    }
}

fn get_undo_status(handle: u64) -> Result<Value, i32> {
    let slot = slot(handle)?;
    let engine = require_open(&slot)?;
    let col = engine.collection.as_ref().ok_or(STATUS_INVALID_STATE)?;
    let status = col.undo_status();
    Ok(json!({
        "canUndo": status.undo.is_some(),
        "canRedo": status.redo.is_some(),
        "undoLabel": status.undo.as_ref().map(|op| format!("{op:?}")),
        "redoLabel": status.redo.as_ref().map(|op| format!("{op:?}")),
        "can_undo": status.undo.is_some(),
        "can_redo": status.redo.is_some(),
    }))
}

fn undo(handle: u64) -> Result<Value, i32> {
    let slot = slot(handle)?;
    let mut engine = require_open(&slot)?;
    let result = {
        let col = engine.collection.as_mut().ok_or(STATUS_INVALID_STATE)?;
        match col.undo() {
            Ok(_) => Ok(()),
            Err(AnkiError::UndoEmpty) => Err(STATUS_UNDO_UNAVAILABLE),
            Err(err) => Err(map_anki_error(err)),
        }
    };
    result?;
    engine.invalidate_tokens();
    Ok(json!({
        "ok": true,
        "undone": true,
        "queueEpoch": engine.queue_epoch,
    }))
}

fn redo(handle: u64) -> Result<Value, i32> {
    let slot = slot(handle)?;
    let mut engine = require_open(&slot)?;
    let result = {
        let col = engine.collection.as_mut().ok_or(STATUS_INVALID_STATE)?;
        match col.redo() {
            Ok(_) => Ok(()),
            Err(AnkiError::UndoEmpty) => Err(STATUS_REDO_UNAVAILABLE),
            Err(err) => Err(map_anki_error(err)),
        }
    };
    result?;
    engine.invalidate_tokens();
    Ok(json!({
        "ok": true,
        "redone": true,
        "queueEpoch": engine.queue_epoch,
    }))
}

fn bury_or_suspend(handle: u64, request: &[u8]) -> Result<Value, i32> {
    let parsed: BuryOrSuspendRequest =
        serde_json::from_slice(request).map_err(|_| STATUS_INVALID_ARGUMENT)?;
    if parsed.card_ids.len() + parsed.note_ids.len() > MAX_BURY_IDS {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    let mode = parsed
        .mode
        .as_deref()
        .or(parsed.action.as_deref())
        .unwrap_or("");
    let slot = slot(handle)?;
    let mut engine = require_open(&slot)?;
    let mut ids = parsed.card_ids;
    if parsed.note_ids.iter().any(|id| *id <= 0) || ids.iter().any(|id| *id <= 0) {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    {
        let col = engine.collection.as_mut().ok_or(STATUS_INVALID_STATE)?;
        for note_id in &parsed.note_ids {
            let found = col
                .search_cards(format!("nid:{note_id}").as_str(), SortMode::NoOrder)
                .map_err(map_anki_error)?;
            ids.extend(found.into_iter().map(|id| id.0));
        }
    }
    ids.sort_unstable();
    ids.dedup();
    if ids.len() > MAX_BURY_IDS {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    let col = engine.collection.as_mut().ok_or(STATUS_INVALID_STATE)?;
    let deck = col.get_current_deck().map_err(map_anki_error)?;
    if matches!(deck.kind, DeckKind::Filtered(_)) {
        return Err(STATUS_INVALID_STATE);
    }
    let card_ids: Vec<CardId> = ids.iter().copied().map(CardId).collect();
    match mode {
        "buryUser" | "bury_card" => {
            col.bury_or_suspend_cards(&card_ids, BuryOrSuspendMode::BuryUser)
                .map_err(map_anki_error)?;
        }
        "burySched" | "bury_siblings" => {
            col.bury_or_suspend_cards(&card_ids, BuryOrSuspendMode::BurySched)
                .map_err(map_anki_error)?;
        }
        "suspend" | "suspend_cards" => {
            col.bury_or_suspend_cards(&card_ids, BuryOrSuspendMode::Suspend)
                .map_err(map_anki_error)?;
        }
        "restoreCards" | "unsuspend_cards" => {
            col.unbury_or_unsuspend_cards(&card_ids)
                .map_err(map_anki_error)?;
        }
        "unburyDeckAll" | "unbury_deck" => {
            let deck_id = DeckId(parsed.deck_id.unwrap_or(deck.id.0));
            col.unbury_deck(deck_id, UnburyDeckMode::All)
                .map_err(map_anki_error)?;
        }
        "unburyDeckSchedOnly" => {
            let deck_id = DeckId(parsed.deck_id.unwrap_or(deck.id.0));
            col.unbury_deck(deck_id, UnburyDeckMode::SchedOnly)
                .map_err(map_anki_error)?;
        }
        "unburyDeckUserOnly" => {
            let deck_id = DeckId(parsed.deck_id.unwrap_or(deck.id.0));
            col.unbury_deck(deck_id, UnburyDeckMode::UserOnly)
                .map_err(map_anki_error)?;
        }
        _ => return Err(STATUS_INVALID_ARGUMENT),
    }
    engine.invalidate_tokens();
    Ok(json!({
        "mode": mode,
        "cardIds": ids,
        "queueEpoch": engine.queue_epoch,
    }))
}

/// Hard-delete for one imported source: removes the given notes and every
/// card that uses them. Note-scoped (not deck-scoped) so decks shared with
/// other sources — the default deck, or same-named decks merged at import —
/// never lose cards they do not own. Callers batch ids to stay under
/// [MAX_DELETE_NOTE_IDS] and the envelope payload cap.
fn delete_notes(handle: u64, request: &[u8]) -> Result<Value, i32> {
    let parsed: DeleteNotesRequest =
        serde_json::from_slice(request).map_err(|_| STATUS_INVALID_ARGUMENT)?;
    if parsed.note_ids.is_empty() || parsed.note_ids.len() > MAX_DELETE_NOTE_IDS {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    if parsed.note_ids.iter().any(|id| *id <= 0) {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    let slot = slot(handle)?;
    let mut engine = require_open(&slot)?;
    let nids: Vec<NoteId> = parsed.note_ids.iter().copied().map(NoteId).collect();
    let removed_cards = {
        let col = engine.collection.as_mut().ok_or(STATUS_INVALID_STATE)?;
        col.remove_notes(&nids).map_err(map_anki_error)?.output
    };
    engine.invalidate_tokens();
    Ok(json!({
        "ok": true,
        "removedCards": removed_cards,
        "queueEpoch": engine.queue_epoch,
    }))
}

/// Removes only the requested cards. Missing cards are ignored and notes are
/// removed only after their final card is gone, making retries idempotent and
/// preserving notes shared by another imported source.
fn delete_cards(handle: u64, request: &[u8]) -> Result<Value, i32> {
    let parsed: DeleteCardsRequest =
        serde_json::from_slice(request).map_err(|_| STATUS_INVALID_ARGUMENT)?;
    if parsed.card_ids.is_empty() || parsed.card_ids.len() > MAX_DELETE_CARD_IDS {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    if parsed.card_ids.iter().any(|id| *id <= 0) {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    let slot = slot(handle)?;
    let mut engine = require_open(&slot)?;
    let removed = {
        let col = engine.collection.as_mut().ok_or(STATUS_INVALID_STATE)?;
        CardsService::remove_cards(
            col,
            anki_proto::cards::RemoveCardsRequest {
                card_ids: parsed.card_ids,
            },
        )
        .map_err(map_anki_error)?
        .count
    };
    engine.invalidate_tokens();
    Ok(json!({
        "ok": true,
        "removedCards": removed,
        "queueEpoch": engine.queue_epoch,
    }))
}

fn stats_for_cards_batch(handle: u64, request: &[u8]) -> Result<Value, i32> {
    let mut parsed: StatsForCardsRequest =
        serde_json::from_slice(request).map_err(|_| STATUS_INVALID_ARGUMENT)?;
    if parsed.card_ids.is_empty() || parsed.card_ids.len() > MAX_STATS_CARD_IDS {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    if parsed.card_ids.iter().any(|id| *id <= 0) {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    parsed.card_ids.sort_unstable();
    parsed.card_ids.dedup();
    let requested_card_count = parsed.card_ids.len();
    let search = format!(
        "cid:{}",
        parsed
            .card_ids
            .iter()
            .map(i64::to_string)
            .collect::<Vec<_>>()
            .join(",")
    );

    let slot = slot(handle)?;
    let mut engine = require_open(&slot)?;
    let col = engine.collection.as_mut().ok_or(STATUS_INVALID_STATE)?;
    let found_card_count = col
        .search_cards(search.as_str(), SortMode::NoOrder)
        .map_err(map_anki_error)?
        .len();
    let graphs = StatsService::graphs(col, anki_proto::stats::GraphsRequest { search, days: 0 })
        .map_err(map_anki_error)?;

    let counts = graphs
        .card_counts
        .and_then(|counts| counts.excluding_inactive)
        .unwrap_or_default();
    let today = graphs.today.unwrap_or_default();
    let future = graphs.future_due.unwrap_or_default();
    let retention = graphs
        .true_retention
        .and_then(|stats| stats.all_time)
        .unwrap_or_default();

    let mut forecast_due_today = 0u32;
    let mut forecast_due_7_days = 0u32;
    let mut forecast_due_30_days = 0u32;
    for (day, count) in future.future_due {
        if day <= 0 {
            forecast_due_today = forecast_due_today.saturating_add(count);
        }
        if day <= 7 {
            forecast_due_7_days = forecast_due_7_days.saturating_add(count);
        }
        if day <= 30 {
            forecast_due_30_days = forecast_due_30_days.saturating_add(count);
        }
    }

    let revlog_count = graphs
        .reviews
        .map(|reviews| {
            reviews.count.values().fold(0u32, |total, value| {
                total
                    .saturating_add(value.learn)
                    .saturating_add(value.relearn)
                    .saturating_add(value.young)
                    .saturating_add(value.mature)
                    .saturating_add(value.filtered)
            })
        })
        .unwrap_or_default();
    let retention_passed = retention
        .young_passed
        .saturating_add(retention.mature_passed);
    let retention_failed = retention
        .young_failed
        .saturating_add(retention.mature_failed);

    Ok(json!({
        "requestedCardCount": requested_card_count,
        "foundCardCount": found_card_count,
        "newCards": counts.new_cards,
        "learningCards": counts.learn.saturating_add(counts.relearn),
        "reviewCards": counts.young.saturating_add(counts.mature),
        "suspendedCards": counts.suspended,
        "buriedCards": counts.buried,
        "todayAnswerCount": today.answer_count,
        "todayLearnCount": today.learn_count,
        "todayReviewCount": today.review_count,
        "todayRelearnCount": today.relearn_count,
        "forecastDueToday": forecast_due_today,
        "forecastDue7Days": forecast_due_7_days,
        "forecastDue30Days": forecast_due_30_days,
        "revlogCount": revlog_count,
        "retentionPassed": retention_passed,
        "retentionFailed": retention_failed,
    }))
}

fn schedule_cards_as_new(handle: u64, request: &[u8]) -> Result<Value, i32> {
    let mut parsed: ScheduleCardsAsNewRequest =
        serde_json::from_slice(request).map_err(|_| STATUS_INVALID_ARGUMENT)?;
    if parsed.card_ids.is_empty() || parsed.card_ids.len() > MAX_SCHEDULE_AS_NEW_IDS {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    if parsed.card_ids.iter().any(|id| *id <= 0) {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    parsed.card_ids.sort_unstable();
    parsed.card_ids.dedup();
    let search = format!(
        "cid:{}",
        parsed
            .card_ids
            .iter()
            .map(i64::to_string)
            .collect::<Vec<_>>()
            .join(",")
    );
    let slot = slot(handle)?;
    let mut engine = require_open(&slot)?;
    let scheduled = {
        let col = engine.collection.as_mut().ok_or(STATUS_INVALID_STATE)?;
        let ids = col
            .search_cards(search.as_str(), SortMode::NoOrder)
            .map_err(map_anki_error)?;
        col.reschedule_cards_as_new(&ids, false, true, true, None)
            .map_err(map_anki_error)?;
        ids.len()
    };
    engine.invalidate_tokens();
    Ok(json!({
        "ok": true,
        "scheduledCards": scheduled,
        "queueEpoch": engine.queue_epoch,
    }))
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct AheadAnswerItem {
    card_id: i64,
    rating: String,
    #[serde(default)]
    milliseconds_taken: i64,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct AheadRequest {
    answers: Vec<AheadAnswerItem>,
}

fn answer_ahead_cards(handle: u64, request: &[u8]) -> Result<Value, i32> {
    let parsed: AheadRequest =
        serde_json::from_slice(request).map_err(|_| STATUS_INVALID_ARGUMENT)?;
    if parsed.answers.is_empty() || parsed.answers.len() > 100 {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    for item in &parsed.answers {
        if item.card_id <= 0 {
            return Err(STATUS_INVALID_ARGUMENT);
        }
        parse_rating(&item.rating)?;
        if item.milliseconds_taken < 0 || item.milliseconds_taken > i64::from(MAX_ELAPSED_MS) {
            return Err(STATUS_INVALID_ARGUMENT);
        }
    }

    let slot = slot(handle)?;
    let mut engine = require_open(&slot)?;
    let col = engine.collection.as_mut().ok_or(STATUS_INVALID_STATE)?;
    let previous_deck = col.get_current_deck().map_err(map_anki_error)?.id;

    let search = parsed
        .answers
        .iter()
        .map(|item| format!("cid:{}", item.card_id))
        .collect::<Vec<_>>()
        .join(" OR ");

    let mut update = col
        .get_or_create_filtered_deck(anki::decks::DeckId(0))
        .map_err(map_anki_error)?;
    update.human_name = "Turna redo".to_string();
    update.allow_empty = true;
    update.config.reschedule = true;
    update.config.search_terms.clear();
    update.config.search_terms.push(anki::decks::FilteredSearchTerm {
        search,
        limit: parsed.answers.len() as i32,
        order: anki::decks::FilteredSearchOrder::Added as i32,
    });
    let filtered_id = col
        .add_or_update_filtered_deck(update)
        .map_err(map_anki_error)?
        .output;

    let mut remaining: std::collections::HashMap<i64, (Rating, u32)> = parsed
        .answers
        .iter()
        .filter_map(|item| {
            parse_rating(&item.rating)
                .ok()
                .map(|rating| (item.card_id, (rating, item.milliseconds_taken.max(0) as u32)))
        })
        .collect();

    let mut answered = 0usize;
    let queued = col
        .get_queued_cards(parsed.answers.len().max(1), false)
        .map_err(map_anki_error)?;
    for queued_card in queued.cards {
        let card_id = queued_card.card.id().0;
        let Some((rating, milliseconds_taken)) = remaining.remove(&card_id) else {
            continue;
        };
        let new_state = match rating {
            Rating::Again => queued_card.states.again,
            Rating::Hard => queued_card.states.hard,
            Rating::Good => queued_card.states.good,
            Rating::Easy => queued_card.states.easy,
        };
        let mut answer = CardAnswer {
            card_id: queued_card.card.id(),
            current_state: queued_card.states.current,
            new_state,
            rating,
            answered_at: TimestampMillis::now(),
            milliseconds_taken,
            custom_data: None,
            from_queue: true,
        };
        match col.answer_card(&mut answer) {
            Ok(_) => answered += 1,
            Err(_) => {
                answer.from_queue = false;
                col.answer_card(&mut answer).map_err(map_anki_error)?;
                col.clear_study_queues();
                answered += 1;
            }
        }
    }

    let _ = col.empty_filtered_deck(filtered_id);
    let _ = col.remove_decks_and_child_decks(&[filtered_id]);
    let _ = col.set_current_deck(previous_deck);
    engine.invalidate_tokens();
    Ok(json!({ "answeredCards": answered }))
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct EnsureNewQuotaRequest {
    deck_id: i64,
    needed_new: i64,
}

fn ensure_today_new_quota(handle: u64, request: &[u8]) -> Result<Value, i32> {
    let parsed: EnsureNewQuotaRequest =
        serde_json::from_slice(request).map_err(|_| STATUS_INVALID_ARGUMENT)?;
    if parsed.deck_id <= 0 || parsed.needed_new < 0 || parsed.needed_new > 9999 {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    if parsed.needed_new == 0 {
        return Ok(json!({ "extendedBy": 0 }));
    }
    let slot = slot(handle)?;
    let mut engine = require_open(&slot)?;
    let col = engine.collection.as_mut().ok_or(STATUS_INVALID_STATE)?;
    let studied = SchedulerService::counts_for_deck_today(
        col,
        anki_proto::decks::DeckId {
            did: parsed.deck_id,
        },
    )
    .map_err(|_| STATUS_DECK_NOT_FOUND)?
    .new as i64;
    let deck = col
        .get_deck(DeckId(parsed.deck_id))
        .map_err(map_anki_error)?
        .ok_or(STATUS_DECK_NOT_FOUND)?;
    let extend = deck
        .normal()
        .map(|normal| normal.extend_new as i64)
        .unwrap_or(0);
    let per_day = deck
        .config_id()
        .and_then(|id| col.get_deck_config(id).ok().flatten())
        .map(|conf| conf.inner.new_per_day as i64)
        .unwrap_or(20);
    let remaining = (per_day + extend - studied).max(0);
    if remaining >= parsed.needed_new {
        return Ok(json!({ "extendedBy": 0 }));
    }
    let remaining_without_extend = per_day - studied;
    let new_extend = (parsed.needed_new - remaining_without_extend).clamp(1, 9999);
    col.custom_study(anki_proto::scheduler::CustomStudyRequest {
        deck_id: parsed.deck_id,
        value: Some(
            anki_proto::scheduler::custom_study_request::Value::NewLimitDelta(
                new_extend as i32,
            ),
        ),
    })
    .map_err(map_anki_error)?;
    engine.invalidate_tokens();
    Ok(json!({ "extendedBy": new_extend }))
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
        anki_proto::decks::DeckId {
            did: parsed.deck_id,
        },
    )
    .map_err(|_| STATUS_DECK_NOT_FOUND)?;
    Ok(json!({
        "deckId": parsed.deck_id,
        "new": counts.new,
        "review": counts.review,
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
        "deckDescription": info.deck_description,
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
    fn answer_non_head_card_retries_off_queue() {
        let (root, handle, _) = temp_open();
        import(handle, &package_path("04-cloze-multi-ord.apkg"), false).unwrap();
        let decks = call(handle, OP_LIST_DECK_TREE, json!({})).unwrap();
        let deck_id = decks["decks"]
            .as_array()
            .unwrap()
            .iter()
            .find(|deck| deck["deckId"].as_i64().unwrap_or(0) > 0)
            .and_then(|deck| deck["deckId"].as_i64())
            .unwrap();
        call(handle, OP_SET_CURRENT_DECK, json!({"deckId": deck_id})).unwrap();
        let queue = call(handle, OP_GET_REVIEW_QUEUE, json!({"fetchLimit": 10})).unwrap();
        let cards = queue["cards"].as_array().unwrap();
        assert!(
            cards.len() >= 2,
            "04-cloze-multi-ord should queue 2+ cards, got {}",
            cards.len()
        );
        let skipped = &cards[1];
        let card_id = skipped["cardId"].as_i64().unwrap();
        let token = skipped["answerToken"].as_str().unwrap();
        let session_id = queue["sessionId"].as_str().unwrap();
        let epoch = queue["queueEpoch"].as_u64().unwrap();
        let answered = call(
            handle,
            OP_ANSWER_CARD,
            json!({
                "cardId": card_id,
                "rating": "good",
                "answerToken": token,
                "sessionId": session_id,
                "queueEpoch": epoch,
                "millisecondsTaken": 1500
            }),
        )
        .expect("non-head answer should retry off-queue instead of ANSWER_FAILED");
        assert_eq!(answered["committed"], true);
        assert_eq!(answered["cardId"], card_id);
        assert!(answered["revlogCount"].as_u64().unwrap() >= 1);
        free_engine(handle).unwrap();
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn delete_notes_removes_source_notes_and_cards() {
        let (root, handle, _) = temp_open();
        let imported = import(handle, &package_path("08-scheduling.apkg"), true).unwrap();
        let note_ids: Vec<i64> = imported["new_note_ids"]
            .as_array()
            .unwrap()
            .iter()
            .map(|v| v.as_i64().unwrap())
            .collect();
        assert!(!note_ids.is_empty());
        let before = call(handle, OP_SEARCH_CARDS, json!({"search": ""})).unwrap();
        let before_count = before["cards"].as_array().unwrap().len();
        assert!(before_count > 0);

        assert_eq!(
            call(handle, OP_DELETE_NOTES, json!({"noteIds": []})).unwrap_err(),
            STATUS_INVALID_ARGUMENT
        );
        assert_eq!(
            call(handle, OP_DELETE_NOTES, json!({"noteIds": [0]})).unwrap_err(),
            STATUS_INVALID_ARGUMENT
        );

        let deleted = call(handle, OP_DELETE_NOTES, json!({"noteIds": note_ids})).unwrap();
        assert_eq!(
            deleted["removedCards"].as_u64().unwrap(),
            before_count as u64
        );
        let after = call(handle, OP_SEARCH_CARDS, json!({"search": ""})).unwrap();
        assert!(after["cards"].as_array().unwrap().is_empty());
        free_engine(handle).unwrap();
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn card_scoped_delete_stats_and_schedule_reset_are_exact() {
        let (root, handle, _) = temp_open();
        import(handle, &package_path("04-cloze-multi-ord.apkg"), true).unwrap();
        let searched = call(handle, OP_SEARCH_CARDS, json!({"search": ""})).unwrap();
        let card_ids: Vec<i64> = searched["cards"]
            .as_array()
            .unwrap()
            .iter()
            .map(|card| card["card_id"].as_i64().unwrap())
            .collect();
        assert!(card_ids.len() >= 2);

        let stats = call(
            handle,
            OP_STATS_FOR_CARDS_BATCH,
            json!({"cardIds": card_ids}),
        )
        .unwrap();
        assert_eq!(stats["foundCardCount"], card_ids.len());

        let reset = call(
            handle,
            OP_SCHEDULE_CARDS_AS_NEW,
            json!({"cardIds": card_ids}),
        )
        .unwrap();
        assert_eq!(reset["scheduledCards"], card_ids.len());

        let deleted = call(handle, OP_DELETE_CARDS, json!({"cardIds": [card_ids[0]]})).unwrap();
        assert_eq!(deleted["removedCards"], 1);
        let after = call(handle, OP_SEARCH_CARDS, json!({"search": ""})).unwrap();
        assert_eq!(after["cards"].as_array().unwrap().len(), card_ids.len() - 1);

        free_engine(handle).unwrap();
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn redo_bury_counts_and_congrats_use_official_apis() {
        let (root, handle, _) = temp_open();
        import(handle, &package_path("08-scheduling.apkg"), true).unwrap();
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
        assert!(
            counts["newStudied"].as_i64().is_some() || counts["reviewStudied"].as_i64().is_some()
        );
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
        assert_eq!(
            call(
                handle,
                OP_BURY_OR_SUSPEND_CARDS,
                json!({"action": "not-a-real-action", "cardIds": [cid2]}),
            )
            .unwrap_err(),
            STATUS_INVALID_ARGUMENT
        );
        free_engine(handle).unwrap();
        let _ = fs::remove_dir_all(root);
    }

    fn card_public_summary(
        col: &Collection,
        card_id: i64,
    ) -> (i64, i64, i64, i64, i64, i64, i64, i64) {
        let (queue, due, ivl, reps, lapses): (i64, i64, i64, i64, i64) = col
            .storage
            .db()
            .query_row(
                "select queue, due, ivl, reps, lapses from cards where id = ?",
                [card_id],
                |row| {
                    Ok((
                        row.get(0)?,
                        row.get(1)?,
                        row.get(2)?,
                        row.get(3)?,
                        row.get(4)?,
                    ))
                },
            )
            .unwrap();
        let revlog_count: i64 = col
            .storage
            .db()
            .query_row(
                "select count(*) from revlog where cid = ?",
                [card_id],
                |row| row.get(0),
            )
            .unwrap();
        let last_ease: i64 = col
            .storage
            .db()
            .query_row(
                "select coalesce((select ease from revlog where cid = ? order by id desc limit 1), -1)",
                [card_id],
                |row| row.get(0),
            )
            .unwrap();
        let last_time: i64 = col
            .storage
            .db()
            .query_row(
                "select coalesce((select time from revlog where cid = ? order by id desc limit 1), -1)",
                [card_id],
                |row| row.get(0),
            )
            .unwrap();
        (
            queue,
            due,
            ivl,
            reps,
            lapses,
            revlog_count,
            last_ease,
            last_time,
        )
    }

    fn summary_via_handle(handle: u64, card_id: i64) -> (i64, i64, i64, i64, i64, i64, i64, i64) {
        let slot = slot(handle).unwrap();
        let engine = slot.engine.lock().unwrap();
        let col = engine.collection.as_ref().unwrap();
        card_public_summary(col, card_id)
    }

    fn last_revlog_count(handle: u64, card_id: i64) -> i64 {
        summary_via_handle(handle, card_id).5
    }

    #[test]
    fn token_survives_confirmed_unwritten_failure_and_unknown_does_not_replay() {
        let (root, handle, _) = temp_open();
        import(handle, &package_path("08-scheduling.apkg"), true).unwrap();
        call(handle, OP_SET_CURRENT_DECK, json!({"deckId": 1})).unwrap();
        let queue = call(handle, OP_GET_REVIEW_QUEUE, json!({"fetchLimit": 1})).unwrap();
        let card_id = queue["cards"][0]["cardId"].as_i64().unwrap();
        let token = queue["cards"][0]["answerToken"]
            .as_str()
            .unwrap()
            .to_string();
        let session_id = queue["sessionId"].as_str().unwrap().to_string();
        let epoch = queue["queueEpoch"].as_u64().unwrap();
        let before = last_revlog_count(handle, card_id);
        {
            let slot = slot(handle).unwrap();
            let mut engine = slot.engine.lock().unwrap();
            engine.debug_fail_before_answer = true;
        }
        assert_eq!(
            call(
                handle,
                OP_ANSWER_CARD,
                json!({
                    "cardId": card_id,
                    "rating": "good",
                    "answerToken": token,
                    "sessionId": session_id,
                    "queueEpoch": epoch,
                    "millisecondsTaken": 1200
                }),
            )
            .unwrap_err(),
            STATUS_ANSWER_FAILED
        );
        assert_eq!(last_revlog_count(handle, card_id), before);
        {
            let slot = slot(handle).unwrap();
            let mut engine = slot.engine.lock().unwrap();
            engine.debug_fail_before_answer = false;
        }
        let committed = call(
            handle,
            OP_ANSWER_CARD,
            json!({
                "cardId": card_id,
                "rating": "good",
                "answerToken": token,
                "sessionId": session_id,
                "queueEpoch": epoch,
                "millisecondsTaken": 1200,
                "clientMutationId": "mut-1"
            }),
        )
        .unwrap();
        assert_eq!(committed["committed"], true);
        assert_eq!(committed["millisecondsTaken"], 1200);
        assert!(committed["queueEpoch"].as_u64().unwrap() > epoch);
        let after = last_revlog_count(handle, card_id);
        assert_eq!(after, before + 1);
        assert_eq!(
            call(
                handle,
                OP_ANSWER_CARD,
                json!({
                    "cardId": card_id,
                    "rating": "good",
                    "answerToken": token,
                    "clientMutationId": "mut-1",
                    "millisecondsTaken": 10
                }),
            )
            .unwrap_err(),
            STATUS_SCHEDULING_CONTEXT_STALE
        );
        assert_eq!(last_revlog_count(handle, card_id), after);

        let queue2 = call(handle, OP_GET_REVIEW_QUEUE, json!({"fetchLimit": 1})).unwrap();
        let card2 = queue2["cards"][0]["cardId"].as_i64().unwrap();
        let token2 = queue2["cards"][0]["answerToken"]
            .as_str()
            .unwrap()
            .to_string();
        let before2 = last_revlog_count(handle, card2);
        {
            let slot = slot(handle).unwrap();
            let mut engine = slot.engine.lock().unwrap();
            engine.debug_fail_after_commit = true;
        }
        assert_eq!(
            call(
                handle,
                OP_ANSWER_CARD,
                json!({
                    "cardId": card2,
                    "rating": "easy",
                    "answerToken": token2,
                    "millisecondsTaken": 900
                }),
            )
            .unwrap_err(),
            STATUS_ANSWER_COMMIT_UNKNOWN
        );
        let unknown_count = last_revlog_count(handle, card2);
        assert!(unknown_count >= before2 + 1);
        assert_eq!(
            call(
                handle,
                OP_ANSWER_CARD,
                json!({
                    "cardId": card2,
                    "rating": "easy",
                    "answerToken": token2,
                    "millisecondsTaken": 900
                }),
            )
            .unwrap_err(),
            STATUS_ANSWER_COMMIT_UNKNOWN
        );
        assert_eq!(last_revlog_count(handle, card2), unknown_count);
        free_engine(handle).unwrap();
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn four_ratings_elapsed_bounds_and_deck_switch_stale() {
        for rating in ["again", "hard", "good", "easy"] {
            let (root, handle, _) = temp_open();
            import(handle, &package_path("08-scheduling.apkg"), true).unwrap();
            let set = call(handle, OP_SET_CURRENT_DECK, json!({"deckId": 1})).unwrap();
            assert!(set.get("deckId").is_some());
            assert!(set["queueEpoch"].as_u64().is_some());
            let queue = call(handle, OP_GET_REVIEW_QUEUE, json!({"fetchLimit": 1})).unwrap();
            let card_id = queue["cards"][0]["cardId"].as_i64().unwrap();
            let token = queue["cards"][0]["answerToken"].as_str().unwrap();
            let answered = call(
                handle,
                OP_ANSWER_CARD,
                json!({
                    "cardId": card_id,
                    "rating": rating,
                    "answerToken": token,
                    "millisecondsTaken": 0
                }),
            )
            .unwrap();
            assert_eq!(answered["millisecondsTaken"], 0);
            assert_eq!(answered["rating"], rating);
            assert_eq!(answered["committed"], true);
            free_engine(handle).unwrap();
            let _ = fs::remove_dir_all(root);
        }

        let (root, handle, _) = temp_open();
        import(handle, &package_path("08-scheduling.apkg"), true).unwrap();
        call(handle, OP_SET_CURRENT_DECK, json!({"deckId": 1})).unwrap();
        let queue = call(handle, OP_GET_REVIEW_QUEUE, json!({"fetchLimit": 1})).unwrap();
        let card_id = queue["cards"][0]["cardId"].as_i64().unwrap();
        let token = queue["cards"][0]["answerToken"]
            .as_str()
            .unwrap()
            .to_string();
        call(handle, OP_SET_CURRENT_DECK, json!({"deckId": 1})).unwrap();
        assert_eq!(
            call(
                handle,
                OP_ANSWER_CARD,
                json!({
                    "cardId": card_id,
                    "rating": "good",
                    "answerToken": token,
                    "millisecondsTaken": 100
                }),
            )
            .unwrap_err(),
            STATUS_SCHEDULING_CONTEXT_STALE
        );
        assert_eq!(
            call(
                handle,
                OP_ANSWER_CARD,
                json!({
                    "cardId": card_id,
                    "rating": "good",
                    "answerToken": token,
                    "millisecondsTaken": -1
                }),
            )
            .unwrap_err(),
            STATUS_INVALID_ARGUMENT
        );
        assert_eq!(
            call(
                handle,
                OP_ANSWER_CARD,
                json!({
                    "cardId": card_id,
                    "rating": "good",
                    "answerToken": token,
                    "millisecondsTaken": 24 * 60 * 60 * 1000 + 1
                }),
            )
            .unwrap_err(),
            STATUS_INVALID_ARGUMENT
        );
        assert_eq!(
            call(handle, OP_SET_CURRENT_DECK, json!({"deckId": 9_999_999})).unwrap_err(),
            STATUS_DECK_NOT_FOUND
        );
        free_engine(handle).unwrap();
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn bridge_matches_direct_rslib_public_card_and_revlog() {
        const ANSWERED_AT: i64 = 1_700_000_123_000;
        for rating_name in ["again", "hard", "good", "easy"] {
            let (root_a, handle, _) = temp_open();
            import(handle, &package_path("08-scheduling.apkg"), true).unwrap();
            close_collection(handle).unwrap();
            let root_b = root_a.parent().unwrap().join(format!(
                "{}-direct",
                root_a.file_name().unwrap().to_string_lossy()
            ));
            fs::create_dir_all(&root_b).unwrap();
            fs::copy(
                root_a.join("collection.anki2"),
                root_b.join("collection.anki2"),
            )
            .unwrap();
            if root_a.join("collection.media.db2").exists() {
                let _ = fs::copy(
                    root_a.join("collection.media.db2"),
                    root_b.join("collection.media.db2"),
                );
            }
            let open_body = serde_json::to_vec(&json!({
                "collection_path": root_a.join("collection.anki2").to_string_lossy(),
                "media_folder": root_a.join("collection.media").to_string_lossy(),
                "media_db": root_a.join("collection.media.db2").to_string_lossy(),
                "check_integrity": false,
            }))
            .unwrap();
            open_collection(handle, &open_body).unwrap();
            {
                let slot = slot(handle).unwrap();
                let mut engine = slot.engine.lock().unwrap();
                engine.allow_injected_answered_at = true;
            }
            call(handle, OP_SET_CURRENT_DECK, json!({"deckId": 1})).unwrap();
            let queue = call(handle, OP_GET_REVIEW_QUEUE, json!({"fetchLimit": 1})).unwrap();
            let card_id = queue["cards"][0]["cardId"].as_i64().unwrap();
            let token = queue["cards"][0]["answerToken"].as_str().unwrap();
            call(
                handle,
                OP_ANSWER_CARD,
                json!({
                    "cardId": card_id,
                    "rating": rating_name,
                    "answerToken": token,
                    "millisecondsTaken": 3210,
                    "answeredAtMillis": ANSWERED_AT
                }),
            )
            .unwrap();
            let bridge = summary_via_handle(handle, card_id);

            let mut direct =
                anki::collection::CollectionBuilder::new(root_b.join("collection.anki2"))
                    .set_media_paths(
                        root_b.join("collection.media"),
                        root_b.join("collection.media.db2"),
                    )
                    .build()
                    .unwrap();
            direct.set_current_deck(DeckId(1)).unwrap();
            let queued = direct.get_queued_cards(1, false).unwrap();
            let queued_card = queued.cards.into_iter().next().expect("direct queue");
            assert_eq!(queued_card.card.id().0, card_id);
            let states = queued_card.states;
            let rating = parse_rating(rating_name).unwrap();
            let new_state = match rating {
                Rating::Again => states.again,
                Rating::Hard => states.hard,
                Rating::Good => states.good,
                Rating::Easy => states.easy,
            };
            direct
                .answer_card(&mut CardAnswer {
                    card_id: CardId(card_id),
                    current_state: states.current,
                    new_state,
                    rating,
                    answered_at: TimestampMillis(ANSWERED_AT),
                    milliseconds_taken: 3210,
                    custom_data: None,
                    from_queue: true,
                })
                .unwrap();
            let direct_summary = card_public_summary(&direct, card_id);
            assert_eq!(bridge, direct_summary, "rating={rating_name}");
            drop(direct);
            free_engine(handle).unwrap();
            let _ = fs::remove_dir_all(root_a);
            let _ = fs::remove_dir_all(root_b);
        }

        let (root_a, handle, _) = temp_open();
        import(handle, &package_path("08-scheduling.apkg"), true).unwrap();
        close_collection(handle).unwrap();
        let root_b = root_a.parent().unwrap().join(format!(
            "{}-undo",
            root_a.file_name().unwrap().to_string_lossy()
        ));
        fs::create_dir_all(&root_b).unwrap();
        fs::copy(
            root_a.join("collection.anki2"),
            root_b.join("collection.anki2"),
        )
        .unwrap();
        let open_body = serde_json::to_vec(&json!({
            "collection_path": root_a.join("collection.anki2").to_string_lossy(),
            "media_folder": root_a.join("collection.media").to_string_lossy(),
            "media_db": root_a.join("collection.media.db2").to_string_lossy(),
            "check_integrity": false,
        }))
        .unwrap();
        open_collection(handle, &open_body).unwrap();
        {
            let slot = slot(handle).unwrap();
            let mut engine = slot.engine.lock().unwrap();
            engine.allow_injected_answered_at = true;
        }
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
                "millisecondsTaken": 1800,
                "answeredAtMillis": ANSWERED_AT
            }),
        )
        .unwrap();
        call(handle, OP_UNDO, json!({})).unwrap();
        call(handle, OP_REDO, json!({})).unwrap();
        let bridge = summary_via_handle(handle, card_id);

        let mut direct = anki::collection::CollectionBuilder::new(root_b.join("collection.anki2"))
            .set_media_paths(
                root_b.join("collection.media"),
                root_b.join("collection.media.db2"),
            )
            .build()
            .unwrap();
        direct.set_current_deck(DeckId(1)).unwrap();
        let queued = direct.get_queued_cards(1, false).unwrap();
        let queued_card = queued.cards.into_iter().next().unwrap();
        let states = queued_card.states;
        direct
            .answer_card(&mut CardAnswer {
                card_id: CardId(card_id),
                current_state: states.current,
                new_state: states.good,
                rating: Rating::Good,
                answered_at: TimestampMillis(ANSWERED_AT),
                milliseconds_taken: 1800,
                custom_data: None,
                from_queue: true,
            })
            .unwrap();
        direct.undo().unwrap();
        direct.redo().unwrap();
        assert_eq!(bridge, card_public_summary(&direct, card_id));
        drop(direct);

        let empty = call(handle, OP_GET_REVIEW_QUEUE, json!({"fetchLimit": 1}));
        if empty.is_err() {
            assert_eq!(empty.unwrap_err(), STATUS_QUEUE_EMPTY);
            let congrats = call(handle, OP_CONGRATS_INFO, json!({})).unwrap();
            assert!(congrats.get("learnRemaining").is_some());
            assert!(congrats.get("deckDescription").is_some());
        }
        free_engine(handle).unwrap();
        let _ = fs::remove_dir_all(root_a);
        let _ = fs::remove_dir_all(root_b);
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
            call(handle, OP_REDO, json!({})).unwrap_err(),
            STATUS_REDO_UNAVAILABLE
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
        assert!(
            html.contains("typeGood") || html.contains("typed-back"),
            "{html}"
        );

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
    fn alloc_free_returns_owned_handles_to_invalid() {
        use std::collections::HashSet;
        let handles: Vec<u64> = (0..20).map(|_| alloc_engine().unwrap()).collect();
        let unique: HashSet<u64> = handles.iter().copied().collect();
        assert_eq!(unique.len(), 20, "duplicate handles issued");
        for handle in &handles {
            assert!(
                crate::engine::slot(*handle).is_ok(),
                "owned handle {handle} missing after alloc"
            );
        }
        for handle in handles {
            free_engine(handle).unwrap();
            assert!(
                matches!(
                    crate::engine::slot(handle),
                    Err(crate::engine::STATUS_INVALID_HANDLE)
                ),
                "handle {handle} still live after free"
            );
            assert_eq!(
                free_engine(handle).unwrap_err(),
                crate::engine::STATUS_INVALID_HANDLE
            );
        }
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
            "DELETE_NOTES",
            "DELETE_CARDS",
            "STATS_FOR_CARDS_BATCH",
            "SCHEDULE_CARDS_AS_NEW",
            "ANSWER_AHEAD_CARDS",
            "ENSURE_TODAY_NEW_QUOTA",
        ] {
            assert!(
                caps.iter().any(|c| c.as_str() == Some(name)),
                "missing {name} in {caps:?}"
            );
        }
        assert_eq!(info["contractMinor"], 8);
    }
}
