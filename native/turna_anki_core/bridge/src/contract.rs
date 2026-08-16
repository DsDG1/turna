//! Turna-owned contract v1 JSON envelope.
//!
//! The C ABI is transport only. Business errors live in this envelope so
//! adding an error code does not change the C layout.

use serde::Deserialize;
use serde::Serialize;
use serde_json::json;
use serde_json::Value;
use std::time::Instant;

use crate::engine;
use crate::errors;

pub const CONTRACT_MAJOR: u32 = 1;
pub const CONTRACT_MINOR: u32 = 0;
pub const OP_ENGINE_INFO: u32 = 1;
const MAX_REQUEST_ID_BYTES: usize = 128;
const MAX_ENVELOPE_PAYLOAD_BYTES: usize = 1_048_576;

pub fn backend_commit() -> &'static str {
    option_env!("TURNA_ANKI_BACKEND_COMMIT").unwrap_or("967aa0d578fc75181e292e95326f9b58698da25c")
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ContractVersion {
    pub major: u32,
    pub minor: u32,
}

impl ContractVersion {
    pub fn v1() -> Self {
        Self {
            major: CONTRACT_MAJOR,
            minor: CONTRACT_MINOR,
        }
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EnvelopeRequest {
    pub contract_version: ContractVersion,
    #[serde(default)]
    pub request_id: String,
    #[serde(default)]
    pub operation: String,
    #[serde(default)]
    pub payload: Value,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EnvelopeError {
    pub code: String,
    pub message_key: String,
    pub recoverable: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub retry_after_millis: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub debug_details: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EngineMeta {
    pub abi_version: u32,
    pub backend_commit: String,
    pub contract_major: u32,
    pub contract_minor: u32,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EnvelopeResponse {
    pub contract_version: ContractVersion,
    pub request_id: String,
    pub ok: bool,
    pub payload: Option<Value>,
    pub error: Option<EnvelopeError>,
    pub engine: EngineMeta,
    pub duration_millis: u64,
}

pub fn looks_like_envelope(bytes: &[u8]) -> bool {
    if bytes.is_empty() {
        return false;
    }
    serde_json::from_slice::<Value>(bytes)
        .ok()
        .and_then(|v| v.get("contractVersion").cloned())
        .is_some()
}

pub fn engine_meta() -> EngineMeta {
    EngineMeta {
        abi_version: crate::TURNA_ANKI_ABI_VERSION,
        backend_commit: backend_commit().to_string(),
        contract_major: CONTRACT_MAJOR,
        contract_minor: CONTRACT_MINOR,
    }
}

pub fn engine_info_payload() -> Value {
    json!({
        "abiVersion": crate::TURNA_ANKI_ABI_VERSION,
        "backendCommit": backend_commit(),
        "contractMajor": CONTRACT_MAJOR,
        "contractMinor": CONTRACT_MINOR,
        "capabilities": [
            "ENGINE_INFO",
            "OPEN_COLLECTION",
            "CLOSE_COLLECTION",
            "CHECK_COLLECTION",
            "CREATE_BACKUP",
            "RESTORE_BACKUP",
            "IMPORT_PACKAGE",
            "LATEST_PROGRESS",
            "CANCEL_OPERATION",
            "LIST_DECK_TREE",
            "SEARCH_CARDS_PAGE",
            "GET_NOTE_CARDS_BATCH",
            "GET_CARD_DESCRIPTORS_BATCH"
        ],
    })
}

pub fn encode_ok(request_id: &str, payload: Value, started: Instant) -> Value {
    serde_json::to_value(EnvelopeResponse {
        contract_version: ContractVersion::v1(),
        request_id: request_id.to_string(),
        ok: true,
        payload: Some(payload),
        error: None,
        engine: engine_meta(),
        duration_millis: started.elapsed().as_millis() as u64,
    })
    .expect("envelope is serializable")
}

pub fn encode_err(request_id: &str, status: i32, started: Instant) -> Value {
    serde_json::to_value(EnvelopeResponse {
        contract_version: ContractVersion::v1(),
        request_id: request_id.to_string(),
        ok: false,
        payload: None,
        error: Some(EnvelopeError {
            code: errors::code_for_status(status).to_string(),
            message_key: errors::message_key_for_status(status).to_string(),
            recoverable: errors::recoverable(status),
            retry_after_millis: None,
            debug_details: None,
        }),
        engine: engine_meta(),
        duration_millis: started.elapsed().as_millis() as u64,
    })
    .expect("envelope is serializable")
}

fn operation_name_to_id(name: &str) -> Option<u32> {
    match name {
        "ENGINE_INFO" => Some(OP_ENGINE_INFO),
        "OPEN_COLLECTION" => Some(engine::OP_OPEN_COLLECTION),
        "CLOSE_COLLECTION" => Some(engine::OP_CLOSE_COLLECTION),
        "CHECK_COLLECTION" => Some(engine::OP_CHECK_COLLECTION),
        "CREATE_BACKUP" => Some(engine::OP_CREATE_BACKUP),
        "IMPORT_PACKAGE" => Some(engine::OP_IMPORT_PACKAGE),
        "LATEST_PROGRESS" => Some(engine::OP_LATEST_PROGRESS),
        "CANCEL_OPERATION" => Some(engine::OP_CANCEL_OPERATION),
        "LIST_DECK_TREE" => Some(engine::OP_LIST_DECK_TREE),
        "SEARCH_CARDS" => Some(engine::OP_SEARCH_CARDS),
        "SEARCH_CARDS_PAGE" => Some(engine::OP_SEARCH_CARDS_PAGE),
        "GET_NOTE_CARDS_BATCH" => Some(engine::OP_GET_NOTE_CARDS_BATCH),
        "GET_CARD_DESCRIPTORS_BATCH" => Some(engine::OP_GET_CARD_DESCRIPTORS_BATCH),
        "RESTORE_BACKUP" => Some(engine::OP_RESTORE_BACKUP),
        "RENDER_CARD" => Some(engine::OP_RENDER_CARD),
        "SET_CURRENT_DECK" => Some(engine::OP_SET_CURRENT_DECK),
        "GET_REVIEW_QUEUE" => Some(engine::OP_GET_REVIEW_QUEUE),
        "DESCRIBE_NEXT_STATES" => Some(engine::OP_DESCRIBE_NEXT_STATES),
        "ANSWER_CARD" => Some(engine::OP_ANSWER_CARD),
        "GET_UNDO_STATUS" => Some(engine::OP_GET_UNDO_STATUS),
        "UNDO" => Some(engine::OP_UNDO),
        _ => None,
    }
}

fn payload_bytes(payload: &Value) -> Result<Vec<u8>, i32> {
    let object = match payload {
        Value::Null => json!({}),
        Value::Object(_) => payload.clone(),
        _ => return Err(engine::STATUS_INVALID_ARGUMENT),
    };
    let bytes = serde_json::to_vec(&object).map_err(|_| engine::STATUS_INVALID_ARGUMENT)?;
    if bytes.len() > MAX_ENVELOPE_PAYLOAD_BYTES {
        return Err(engine::STATUS_INVALID_ARGUMENT);
    }
    Ok(bytes)
}

fn validate_request_id(request_id: &str) -> Result<(), i32> {
    if request_id.is_empty() || request_id.len() > MAX_REQUEST_ID_BYTES {
        return Err(engine::STATUS_INVALID_ARGUMENT);
    }
    if !request_id
        .bytes()
        .all(|b| b.is_ascii_graphic() || b == b' ')
    {
        return Err(engine::STATUS_INVALID_ARGUMENT);
    }
    Ok(())
}

/// Production entry: contract v1 envelope in, envelope out.
/// Raw Spike JSON is not accepted on `turna_anki_call`. Host tests that need
/// the raw payload must call `engine::dispatch` directly.
pub fn dispatch_call(handle: u64, operation: u32, bytes: &[u8]) -> Result<Value, i32> {
    let started = Instant::now();
    if !looks_like_envelope(bytes) {
        return Err(engine::STATUS_INVALID_ARGUMENT);
    }
    let parsed: EnvelopeRequest =
        serde_json::from_slice(bytes).map_err(|_| engine::STATUS_INVALID_ARGUMENT)?;
    validate_request_id(&parsed.request_id)?;
    if parsed.contract_version.major != CONTRACT_MAJOR {
        return Ok(encode_err(
            &parsed.request_id,
            engine::STATUS_CONTRACT_VERSION_MISMATCH,
            started,
        ));
    }
    if parsed.operation.is_empty() {
        return Ok(encode_err(
            &parsed.request_id,
            engine::STATUS_INVALID_ARGUMENT,
            started,
        ));
    }
    let named = match operation_name_to_id(&parsed.operation) {
        Some(id) => id,
        None => {
            return Ok(encode_err(
                &parsed.request_id,
                engine::STATUS_UNIMPLEMENTED,
                started,
            ));
        }
    };
    if named != operation {
        return Ok(encode_err(
            &parsed.request_id,
            engine::STATUS_INVALID_ARGUMENT,
            started,
        ));
    }
    if named == OP_ENGINE_INFO {
        return Ok(encode_ok(
            &parsed.request_id,
            engine_info_payload(),
            started,
        ));
    }
    let payload_bytes = payload_bytes(&parsed.payload)?;
    match engine::dispatch(handle, named, &payload_bytes) {
        Ok(payload) => Ok(encode_ok(&parsed.request_id, payload, started)),
        Err(status)
            if status == engine::STATUS_INVALID_HANDLE
                || status == engine::STATUS_BACKEND_PANIC =>
        {
            Err(status)
        }
        Err(status) => Ok(encode_err(&parsed.request_id, status, started)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::path::PathBuf;

    fn fixture(name: &str) -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("contract/fixtures")
            .join(name)
    }

    fn load_json(name: &str) -> Value {
        serde_json::from_str(&fs::read_to_string(fixture(name)).unwrap()).unwrap()
    }

    fn engine_info_request() -> Vec<u8> {
        serde_json::to_vec(&json!({
            "contractVersion": {"major": 1, "minor": 0},
            "requestId": "engine-info",
            "operation": "ENGINE_INFO",
            "payload": {}
        }))
        .unwrap()
    }

    #[test]
    fn engine_info_returns_build_injected_commit() {
        let response = dispatch_call(0, OP_ENGINE_INFO, &engine_info_request()).unwrap();
        assert_eq!(response["ok"], true);
        assert_eq!(response["payload"]["backendCommit"], backend_commit());
        assert_eq!(response["engine"]["backendCommit"], backend_commit());
        assert_eq!(response["engine"]["contractMajor"], 1);
        assert!(!backend_commit().is_empty());
        assert_ne!(backend_commit(), "unknown");
        assert_eq!(response["requestId"], "engine-info");
        assert!(response["error"].is_null());
    }

    #[test]
    fn raw_spike_payload_is_rejected() {
        assert_eq!(
            dispatch_call(0, OP_ENGINE_INFO, b"").unwrap_err(),
            engine::STATUS_INVALID_ARGUMENT
        );
        assert_eq!(
            dispatch_call(0, OP_ENGINE_INFO, br#"{"operation":"ENGINE_INFO"}"#).unwrap_err(),
            engine::STATUS_INVALID_ARGUMENT
        );
    }

    #[test]
    fn name_id_mismatch_is_rejected() {
        let request = json!({
            "contractVersion": {"major": 1, "minor": 0},
            "requestId": "req-mismatch",
            "operation": "ENGINE_INFO",
            "payload": {}
        });
        let response = dispatch_call(
            0,
            engine::OP_IMPORT_PACKAGE,
            &serde_json::to_vec(&request).unwrap(),
        )
        .unwrap();
        assert_eq!(response["ok"], false);
        assert_eq!(response["error"]["code"], "INVALID_ARGUMENT");
        assert_eq!(response["requestId"], "req-mismatch");
        assert!(response["payload"].is_null());
    }

    #[test]
    fn unknown_operation_does_not_fall_back_to_numeric_id() {
        let request = json!({
            "contractVersion": {"major": 1, "minor": 0},
            "requestId": "req-unknown",
            "operation": "NOT_A_REAL_OP",
            "payload": {}
        });
        let response =
            dispatch_call(0, OP_ENGINE_INFO, &serde_json::to_vec(&request).unwrap()).unwrap();
        assert_eq!(response["ok"], false);
        assert_eq!(response["error"]["code"], "UNIMPLEMENTED");
        assert_eq!(response["requestId"], "req-unknown");
    }

    #[test]
    fn empty_request_id_is_rejected() {
        let request = json!({
            "contractVersion": {"major": 1, "minor": 0},
            "requestId": "",
            "operation": "ENGINE_INFO",
            "payload": {}
        });
        assert_eq!(
            dispatch_call(0, OP_ENGINE_INFO, &serde_json::to_vec(&request).unwrap()).unwrap_err(),
            engine::STATUS_INVALID_ARGUMENT
        );
    }

    #[test]
    fn unknown_major_is_rejected() {
        let request = json!({
            "contractVersion": {"major": 2, "minor": 0},
            "requestId": "req-major",
            "operation": "ENGINE_INFO",
            "payload": {}
        });
        let response =
            dispatch_call(0, OP_ENGINE_INFO, &serde_json::to_vec(&request).unwrap()).unwrap();
        assert_eq!(response["ok"], false);
        assert_eq!(response["error"]["code"], "CONTRACT_VERSION_MISMATCH");
        assert_eq!(response["requestId"], "req-major");
    }

    #[test]
    fn unknown_response_fields_are_ignored_on_decode() {
        let mut golden = load_json("response_engine_info.json");
        golden["futureField"] = json!("ignore-me");
        let decoded: EnvelopeResponse = serde_json::from_value(golden).unwrap();
        assert!(decoded.ok);
        assert_eq!(decoded.engine.contract_major, 1);
    }

    #[test]
    fn missing_contract_version_is_not_an_envelope() {
        assert!(!looks_like_envelope(br#"{"operation":"ENGINE_INFO"}"#));
        assert!(looks_like_envelope(
            br#"{"contractVersion":{"major":1,"minor":0}}"#
        ));
    }

    #[test]
    fn golden_engine_info_request_round_trip() {
        let request = load_json("request_engine_info.json");
        let bytes = serde_json::to_vec(&request).unwrap();
        let parsed: EnvelopeRequest = serde_json::from_slice(&bytes).unwrap();
        assert_eq!(parsed.operation, "ENGINE_INFO");
        let encoded = serde_json::to_value(&parsed.contract_version).unwrap();
        assert_eq!(encoded["major"], 1);
    }

    #[test]
    fn import_package_envelope_wraps_payload() {
        let request = json!({
            "contractVersion": {"major": 1, "minor": 0},
            "requestId": "req-import",
            "operation": "IMPORT_PACKAGE",
            "payload": {"package_path": "rel.apkg"}
        });
        let handle = engine::alloc_engine().unwrap();
        let response = dispatch_call(
            handle,
            engine::OP_IMPORT_PACKAGE,
            &serde_json::to_vec(&request).unwrap(),
        )
        .unwrap();
        engine::free_engine(handle).unwrap();
        assert_eq!(response["ok"], false);
        assert_eq!(response["error"]["code"], "INVALID_ARGUMENT");
        assert_eq!(response["requestId"], "req-import");
        assert_eq!(response["engine"]["backendCommit"], backend_commit());
    }
}
