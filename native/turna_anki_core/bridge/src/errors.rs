//! Stable Turna error codes. Business errors belong in the JSON envelope.

use crate::engine::STATUS_ANSWER_COMMIT_UNKNOWN;
use crate::engine::STATUS_ANSWER_FAILED;
use crate::engine::STATUS_BACKEND_PANIC;
use crate::engine::STATUS_CARD_NOT_FOUND;
use crate::engine::STATUS_COLLECTION_ALREADY_OPEN;
use crate::engine::STATUS_COLLECTION_CORRUPT;
use crate::engine::STATUS_COLLECTION_LOCKED;
use crate::engine::STATUS_COLLECTION_OPEN_FAILED;
use crate::engine::STATUS_CONTRACT_VERSION_MISMATCH;
use crate::engine::STATUS_DECK_NOT_FOUND;
use crate::engine::STATUS_IMPORT_CANCELLED;
use crate::engine::STATUS_INTERNAL_ERROR;
use crate::engine::STATUS_INVALID_ARGUMENT;
use crate::engine::STATUS_INVALID_HANDLE;
use crate::engine::STATUS_INVALID_STATE;
use crate::engine::STATUS_IO_ERROR;
use crate::engine::STATUS_PACKAGE_INVALID;
use crate::engine::STATUS_PACKAGE_NOT_FOUND;
use crate::engine::STATUS_PAGE_TOKEN_STALE;
use crate::engine::STATUS_PROJECTION_SNAPSHOT_STALE;
use crate::engine::STATUS_QUEUE_EMPTY;
use crate::engine::STATUS_REDO_UNAVAILABLE;
use crate::engine::STATUS_RENDER_FAILED;
use crate::engine::STATUS_SCHEDULER_BUSY;
use crate::engine::STATUS_SCHEDULING_CONTEXT_STALE;
use crate::engine::STATUS_TYPED_CLOZE_EMPTY;
use crate::engine::STATUS_TYPED_FIELD_NOT_FOUND;
use crate::engine::STATUS_UNDO_UNAVAILABLE;
use crate::engine::STATUS_UNIMPLEMENTED;

/// The single status surface: (wire status, stable code, human message
/// key). `code_for_status` / `message_key_for_status` derive from this — a
/// status without a message key falls back to `official_anki.backend_error`.
const ERROR_TABLE: &[(i32, &str, Option<&str>)] = &[
    (STATUS_UNIMPLEMENTED, "UNIMPLEMENTED", None),
    (STATUS_INVALID_HANDLE, "INVALID_HANDLE", None),
    (STATUS_INVALID_ARGUMENT, "INVALID_ARGUMENT", None),
    (STATUS_BACKEND_PANIC, "BACKEND_PANIC", None),
    (STATUS_INVALID_STATE, "INVALID_STATE", Some("official_anki.invalid_state")),
    (STATUS_COLLECTION_ALREADY_OPEN, "COLLECTION_ALREADY_OPEN", None),
    (STATUS_COLLECTION_LOCKED, "COLLECTION_LOCKED", None),
    (STATUS_COLLECTION_OPEN_FAILED, "COLLECTION_OPEN_FAILED", None),
    (STATUS_PACKAGE_NOT_FOUND, "PACKAGE_NOT_FOUND", Some("official_anki.package_not_found")),
    (STATUS_PACKAGE_INVALID, "PACKAGE_INVALID", Some("official_anki.package_invalid")),
    (STATUS_IMPORT_CANCELLED, "IMPORT_CANCELLED", Some("official_anki.import_cancelled")),
    (STATUS_CARD_NOT_FOUND, "CARD_NOT_FOUND", Some("official_anki.card_not_found")),
    (STATUS_RENDER_FAILED, "RENDER_FAILED", Some("official_anki.render_failed")),
    (STATUS_QUEUE_EMPTY, "QUEUE_EMPTY", Some("official_anki.queue_empty")),
    (STATUS_SCHEDULING_CONTEXT_STALE, "SCHEDULING_CONTEXT_STALE", Some("official_anki.scheduling_context_stale")),
    (STATUS_ANSWER_FAILED, "ANSWER_FAILED", Some("official_anki.answer_failed")),
    (STATUS_ANSWER_COMMIT_UNKNOWN, "ANSWER_COMMIT_UNKNOWN", Some("official_anki.answer_commit_unknown")),
    (STATUS_UNDO_UNAVAILABLE, "UNDO_UNAVAILABLE", Some("official_anki.undo_unavailable")),
    (STATUS_IO_ERROR, "IO_ERROR", None),
    (STATUS_COLLECTION_CORRUPT, "COLLECTION_CORRUPT", None),
    (STATUS_CONTRACT_VERSION_MISMATCH, "CONTRACT_VERSION_MISMATCH", Some("official_anki.contract_version_mismatch")),
    (STATUS_PAGE_TOKEN_STALE, "PAGE_TOKEN_STALE", Some("official_anki.page_token_stale")),
    (STATUS_TYPED_FIELD_NOT_FOUND, "TYPED_FIELD_NOT_FOUND", Some("official_anki.typed_field_not_found")),
    (STATUS_TYPED_CLOZE_EMPTY, "TYPED_CLOZE_EMPTY", Some("official_anki.typed_cloze_empty")),
    (STATUS_PROJECTION_SNAPSHOT_STALE, "PROJECTION_SNAPSHOT_STALE", Some("official_anki.projection_snapshot_stale")),
    (STATUS_REDO_UNAVAILABLE, "REDO_UNAVAILABLE", Some("official_anki.redo_unavailable")),
    (STATUS_DECK_NOT_FOUND, "DECK_NOT_FOUND", Some("official_anki.deck_not_found")),
    (STATUS_SCHEDULER_BUSY, "SCHEDULER_BUSY", Some("official_anki.scheduler_busy")),
    (STATUS_INTERNAL_ERROR, "INTERNAL_ERROR", None),
];

pub fn code_for_status(status: i32) -> &'static str {
    ERROR_TABLE
        .iter()
        .find(|(s, _, _)| *s == status)
        .map(|(_, code, _)| *code)
        .unwrap_or("INTERNAL_ERROR")
}

pub fn message_key_for_status(status: i32) -> &'static str {
    ERROR_TABLE
        .iter()
        .find(|(s, _, _)| *s == status)
        .and_then(|(_, _, key)| *key)
        .unwrap_or("official_anki.backend_error")
}

pub fn recoverable(status: i32) -> bool {
    matches!(
        status,
        STATUS_IMPORT_CANCELLED
            | STATUS_PAGE_TOKEN_STALE
            | STATUS_PROJECTION_SNAPSHOT_STALE
            | STATUS_INVALID_STATE
            | STATUS_QUEUE_EMPTY
            | STATUS_SCHEDULING_CONTEXT_STALE
            | STATUS_ANSWER_FAILED
            | STATUS_ANSWER_COMMIT_UNKNOWN
            | STATUS_SCHEDULER_BUSY
    )
}
