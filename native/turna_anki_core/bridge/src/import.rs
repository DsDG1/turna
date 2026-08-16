//! Official import helpers: backup checkpoints and import-token minting.

use serde::Deserialize;
use serde_json::json;
use serde_json::Value;
use std::fs;
use std::path::PathBuf;
use std::time::SystemTime;
use std::time::UNIX_EPOCH;

use crate::engine::slot;
use crate::engine::EngineState;
use crate::engine::STATUS_BACKEND_PANIC;
use crate::engine::STATUS_INVALID_ARGUMENT;
use crate::engine::STATUS_INVALID_STATE;
use crate::engine::STATUS_IO_ERROR;

#[derive(Debug, Deserialize)]
struct BackupRequest {
    #[serde(default)]
    backup_id: Option<String>,
}

pub fn create_backup(handle: u64, request: &[u8]) -> Result<Value, i32> {
    let parsed: BackupRequest = if request.is_empty() {
        BackupRequest { backup_id: None }
    } else {
        serde_json::from_slice(request).unwrap_or(BackupRequest { backup_id: None })
    };
    let slot = slot(handle)?;
    let engine = slot.engine.lock().map_err(|_| STATUS_BACKEND_PANIC)?;
    if engine.state != EngineState::Open {
        return Err(STATUS_INVALID_STATE);
    }
    let collection = engine
        .collection_path
        .as_ref()
        .ok_or(STATUS_INVALID_STATE)?;
    if !collection.is_file() {
        return Err(STATUS_INVALID_STATE);
    }
    let backup_id = parsed.backup_id.unwrap_or_else(|| {
        format!(
            "bk-{}",
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map(|d| d.as_millis())
                .unwrap_or(0)
        )
    });
    if backup_id.contains('/') || backup_id.contains('\\') || backup_id.contains('\0') {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    let backup_dir = collection
        .parent()
        .ok_or(STATUS_INVALID_ARGUMENT)?
        .join("backups");
    fs::create_dir_all(&backup_dir).map_err(|_| STATUS_IO_ERROR)?;
    let dest: PathBuf = backup_dir.join(format!("{backup_id}.anki2"));
    fs::copy(collection, &dest).map_err(|_| STATUS_IO_ERROR)?;
    Ok(json!({
        "backupId": backup_id,
        "bytes": dest.metadata().map(|m| m.len()).unwrap_or(0),
    }))
}
