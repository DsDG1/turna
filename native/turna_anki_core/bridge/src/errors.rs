//! Stable Turna error codes. Business errors belong in the JSON envelope.

use crate::engine::STATUS_ANSWER_FAILED;
use crate::engine::STATUS_BACKEND_PANIC;
use crate::engine::STATUS_CARD_NOT_FOUND;
use crate::engine::STATUS_COLLECTION_ALREADY_OPEN;
use crate::engine::STATUS_COLLECTION_CORRUPT;
use crate::engine::STATUS_COLLECTION_LOCKED;
use crate::engine::STATUS_COLLECTION_OPEN_FAILED;
use crate::engine::STATUS_CONTRACT_VERSION_MISMATCH;
use crate::engine::STATUS_IMPORT_CANCELLED;
use crate::engine::STATUS_INTERNAL_ERROR;
use crate::engine::STATUS_INVALID_ARGUMENT;
use crate::engine::STATUS_INVALID_HANDLE;
use crate::engine::STATUS_INVALID_STATE;
use crate::engine::STATUS_IO_ERROR;
use crate::engine::STATUS_PACKAGE_INVALID;
use crate::engine::STATUS_PACKAGE_NOT_FOUND;
use crate::engine::STATUS_PAGE_TOKEN_STALE;
use crate::engine::STATUS_QUEUE_EMPTY;
use crate::engine::STATUS_RENDER_FAILED;
use crate::engine::STATUS_SCHEDULING_CONTEXT_STALE;
use crate::engine::STATUS_UNDO_UNAVAILABLE;
use crate::engine::STATUS_UNIMPLEMENTED;

pub fn code_for_status(status: i32) -> &'static str {
    match status {
        STATUS_UNIMPLEMENTED => "UNIMPLEMENTED",
        STATUS_INVALID_HANDLE => "INVALID_HANDLE",
        STATUS_INVALID_ARGUMENT => "INVALID_ARGUMENT",
        STATUS_BACKEND_PANIC => "BACKEND_PANIC",
        STATUS_INVALID_STATE => "INVALID_STATE",
        STATUS_COLLECTION_ALREADY_OPEN => "COLLECTION_ALREADY_OPEN",
        STATUS_COLLECTION_LOCKED => "COLLECTION_LOCKED",
        STATUS_COLLECTION_OPEN_FAILED => "COLLECTION_OPEN_FAILED",
        STATUS_PACKAGE_NOT_FOUND => "PACKAGE_NOT_FOUND",
        STATUS_PACKAGE_INVALID => "PACKAGE_INVALID",
        STATUS_IMPORT_CANCELLED => "IMPORT_CANCELLED",
        STATUS_CARD_NOT_FOUND => "CARD_NOT_FOUND",
        STATUS_RENDER_FAILED => "RENDER_FAILED",
        STATUS_QUEUE_EMPTY => "QUEUE_EMPTY",
        STATUS_SCHEDULING_CONTEXT_STALE => "SCHEDULING_CONTEXT_STALE",
        STATUS_ANSWER_FAILED => "ANSWER_FAILED",
        STATUS_UNDO_UNAVAILABLE => "UNDO_UNAVAILABLE",
        STATUS_IO_ERROR => "IO_ERROR",
        STATUS_COLLECTION_CORRUPT => "COLLECTION_CORRUPT",
        STATUS_CONTRACT_VERSION_MISMATCH => "CONTRACT_VERSION_MISMATCH",
        STATUS_PAGE_TOKEN_STALE => "PAGE_TOKEN_STALE",
        STATUS_INTERNAL_ERROR => "INTERNAL_ERROR",
        _ => "INTERNAL_ERROR",
    }
}

pub fn message_key_for_status(status: i32) -> &'static str {
    match status {
        STATUS_PACKAGE_INVALID => "official_anki.package_invalid",
        STATUS_PACKAGE_NOT_FOUND => "official_anki.package_not_found",
        STATUS_IMPORT_CANCELLED => "official_anki.import_cancelled",
        STATUS_CONTRACT_VERSION_MISMATCH => "official_anki.contract_version_mismatch",
        STATUS_PAGE_TOKEN_STALE => "official_anki.page_token_stale",
        _ => "official_anki.backend_error",
    }
}

pub fn recoverable(status: i32) -> bool {
    matches!(
        status,
        STATUS_IMPORT_CANCELLED | STATUS_PAGE_TOKEN_STALE | STATUS_INVALID_STATE
    )
}
