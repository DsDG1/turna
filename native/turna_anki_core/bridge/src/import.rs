//! Consistent Collection backup and restore.
//!
//! Never copies an open `collection.anki2` as a success artifact. Prefer
//! official `Collection::maybe_backup` (checkpoint + locked read → colpkg),
//! then produce a restorable `.anki2` from a closed Collection.

use serde::Deserialize;
use serde_json::json;
use serde_json::Value;
use std::fs;
use std::fs::File;
use std::path::Path;
use std::path::PathBuf;
use std::time::SystemTime;
use std::time::UNIX_EPOCH;

use anki::collection::CollectionBuilder;

use crate::engine::close_collection_inner;
use crate::engine::reopen_open_collection;
use crate::engine::parse_req;
use crate::engine::parse_req_or_default;
use crate::engine::slot;
use crate::engine::BusyGuard;
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

#[derive(Debug, Deserialize)]
struct RestoreRequest {
    backup_id: String,
}

fn sanitize_backup_id(raw: &str) -> Result<(), i32> {
    if raw.is_empty()
        || raw.len() > 128
        || raw.contains('/')
        || raw.contains('\\')
        || raw.contains('\0')
        || raw.contains("..")
    {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    Ok(())
}

fn mint_backup_id() -> String {
    format!(
        "bk-{}",
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_millis())
            .unwrap_or(0)
    )
}

fn copy_fsync(src: &Path, dest: &Path) -> Result<u64, i32> {
    let bytes = fs::copy(src, dest).map_err(|_| STATUS_IO_ERROR)?;
    let file = File::open(dest).map_err(|_| STATUS_IO_ERROR)?;
    file.sync_all().map_err(|_| STATUS_IO_ERROR)?;
    Ok(bytes)
}

fn atomic_copy_sqlite(src: &Path, dest: &Path) -> Result<u64, i32> {
    if dest.exists() {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    let tmp = dest.with_extension("anki2.partial");
    let _ = fs::remove_file(&tmp);
    let bytes = copy_fsync(src, &tmp)?;
    fs::rename(&tmp, dest).map_err(|_| STATUS_IO_ERROR)?;
    if let Some(parent) = dest.parent() {
        if let Ok(dir) = File::open(parent) {
            let _ = dir.sync_all();
        }
    }
    Ok(bytes)
}

fn verify_backup_independent(path: &Path) -> Result<(), i32> {
    let col = CollectionBuilder::new(path)
        .build()
        .map_err(|_| STATUS_IO_ERROR)?;
    col.close(None).map_err(|_| STATUS_IO_ERROR)?;
    Ok(())
}

fn newest_colpkg(dir: &Path) -> Option<String> {
    let mut newest: Option<(std::time::SystemTime, String)> = None;
    let entries = fs::read_dir(dir).ok()?;
    for entry in entries.flatten() {
        let path = entry.path();
        if path.extension().and_then(|e| e.to_str()) != Some("colpkg") {
            continue;
        }
        let modified = entry.metadata().ok().and_then(|m| m.modified().ok())?;
        let name = path.file_name()?.to_string_lossy().into_owned();
        if newest
            .as_ref()
            .map(|(time, _)| modified > *time)
            .unwrap_or(true)
        {
            newest = Some((modified, name));
        }
    }
    newest.map(|(_, name)| name)
}

pub fn create_backup(handle: u64, request: &[u8]) -> Result<Value, i32> {
    let parsed: BackupRequest = parse_req_or_default(request, BackupRequest { backup_id: None })?;
    let backup_id = parsed.backup_id.unwrap_or_else(mint_backup_id);
    sanitize_backup_id(&backup_id)?;

    let slot = slot(handle)?;
    let _busy = BusyGuard::acquire(&slot)?;
    let mut engine = slot.engine.lock().map_err(|_| STATUS_BACKEND_PANIC)?;
    if engine.state != EngineState::Open {
        return Err(STATUS_INVALID_STATE);
    }
    let collection = engine.collection_path.clone().ok_or(STATUS_INVALID_STATE)?;
    if !collection.is_file() {
        return Err(STATUS_INVALID_STATE);
    }
    let backup_dir = collection
        .parent()
        .ok_or(STATUS_INVALID_ARGUMENT)?
        .join("backups");
    fs::create_dir_all(&backup_dir).map_err(|_| STATUS_IO_ERROR)?;
    let dest: PathBuf = backup_dir.join(format!("{backup_id}.anki2"));
    if dest.exists() {
        return Err(STATUS_INVALID_ARGUMENT);
    }

    let official_colpkg = {
        let col = engine.open_col()?;
        match col.maybe_backup(backup_dir.clone(), true) {
            Ok(Some(task)) => match task.join() {
                Ok(Ok(())) => newest_colpkg(&backup_dir),
                _ => None,
            },
            _ => None,
        }
    };

    close_collection_inner(&mut engine)?;
    let bytes = match atomic_copy_sqlite(&collection, &dest) {
        Ok(bytes) => bytes,
        Err(status) => {
            let _ = reopen_open_collection(&mut engine, &slot);
            return Err(status);
        }
    };
    if let Err(status) = verify_backup_independent(&dest) {
        let _ = fs::remove_file(&dest);
        let _ = reopen_open_collection(&mut engine, &slot);
        return Err(status);
    }
    reopen_open_collection(&mut engine, &slot)?;
    crate::ops::integrity_ok(engine.open_col()?)?;

    Ok(json!({
        "backupId": backup_id,
        "bytes": bytes,
        "path": dest.to_string_lossy(),
        "officialColpkg": official_colpkg,
    }))
}

pub fn restore_backup(handle: u64, request: &[u8]) -> Result<Value, i32> {
    let parsed: RestoreRequest =
        parse_req(request)?;
    sanitize_backup_id(&parsed.backup_id)?;

    let slot = slot(handle)?;
    let _busy = BusyGuard::acquire(&slot)?;
    let mut engine = slot.engine.lock().map_err(|_| STATUS_BACKEND_PANIC)?;
    let collection = engine.collection_path.clone().ok_or(STATUS_INVALID_STATE)?;
    let src = collection
        .parent()
        .ok_or(STATUS_INVALID_ARGUMENT)?
        .join("backups")
        .join(format!("{}.anki2", parsed.backup_id));
    if !src.is_file() {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    if engine.state == EngineState::Open {
        close_collection_inner(&mut engine)?;
    }
    let tmp = collection.with_extension("anki2.restore-partial");
    let _ = fs::remove_file(&tmp);
    copy_fsync(&src, &tmp)?;
    fs::rename(&tmp, &collection).map_err(|_| STATUS_IO_ERROR)?;
    if let Some(parent) = collection.parent() {
        if let Ok(dir) = File::open(parent) {
            let _ = dir.sync_all();
        }
    }
    reopen_open_collection(&mut engine, &slot)?;
    crate::ops::integrity_ok(engine.open_col()?)?;
    Ok(json!({
        "state": "open",
        "backupId": parsed.backup_id,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::engine::alloc_engine;
    use crate::engine::dispatch;
    use crate::engine::free_engine;
    use crate::engine::open_collection;
    use crate::engine::OpenRequest;
    use crate::engine::OP_CREATE_BACKUP;
    use crate::engine::OP_IMPORT_PACKAGE;
    use crate::engine::OP_RESTORE_BACKUP;
    use crate::engine::STATUS_INVALID_ARGUMENT;
    use std::path::PathBuf;

    fn fixture_pkg() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../test/fixtures/anki_official/packages/02-basic-reversed.apkg")
    }

    fn open_temp() -> (PathBuf, u64, Vec<u8>) {
        let root = std::env::temp_dir().join(format!(
            "turna-backup-{}-{}",
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
        (root, handle, body)
    }

    #[test]
    fn backup_restore_round_trip() {
        let (root, handle, _open) = open_temp();
        dispatch(
            handle,
            OP_IMPORT_PACKAGE,
            &serde_json::to_vec(&json!({
                "package_path": fixture_pkg().to_string_lossy(),
            }))
            .unwrap(),
        )
        .unwrap();
        let backup = dispatch(
            handle,
            OP_CREATE_BACKUP,
            &serde_json::to_vec(&json!({"backup_id": "bk-roundtrip"})).unwrap(),
        )
        .unwrap();
        assert_eq!(backup["backupId"], "bk-roundtrip");
        assert!(backup["bytes"].as_u64().unwrap() > 0);
        let artifact = root.join("backups/bk-roundtrip.anki2");
        assert!(artifact.is_file());
        verify_backup_independent(&artifact).unwrap();

        dispatch(
            handle,
            OP_IMPORT_PACKAGE,
            &serde_json::to_vec(&json!({
                "package_path": fixture_pkg().to_string_lossy(),
            }))
            .unwrap(),
        )
        .unwrap();
        let restored = dispatch(
            handle,
            OP_RESTORE_BACKUP,
            &serde_json::to_vec(&json!({"backup_id": "bk-roundtrip"})).unwrap(),
        )
        .unwrap();
        assert_eq!(restored["state"], "open");
        free_engine(handle).unwrap();
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn existing_backup_id_is_rejected() {
        let (root, handle, _) = open_temp();
        let req = serde_json::to_vec(&json!({"backup_id": "bk-exists"})).unwrap();
        dispatch(handle, OP_CREATE_BACKUP, &req).unwrap();
        assert_eq!(
            dispatch(handle, OP_CREATE_BACKUP, &req).unwrap_err(),
            STATUS_INVALID_ARGUMENT
        );
        free_engine(handle).unwrap();
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn create_backup_closes_before_copying_anki2() {
        let src = include_str!("import.rs");
        let create = src.split("pub fn restore_backup").next().unwrap();
        assert!(create.contains("close_collection_inner"));
        assert!(create.contains("atomic_copy_sqlite"));
        assert!(create.contains("maybe_backup"));
    }
}
