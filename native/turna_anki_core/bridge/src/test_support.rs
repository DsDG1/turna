//! Shared bridge test helpers — one temp-open, one fixture resolver, one
//! pagination walker. These were three-to-four per-module copies (doc 40
//! R4 test governance). Compiled only under `cfg(test)`.

use std::path::PathBuf;
use std::time::SystemTime;
use std::time::UNIX_EPOCH;

use crate::engine::alloc_engine;
use crate::engine::dispatch;
use crate::engine::open_collection;
use crate::engine::OP_IMPORT_PACKAGE;
use crate::engine::OP_SEARCH_CARDS_PAGE;
use crate::engine::OpenRequest;
use serde_json::json;
use serde_json::Value;

/// Open a fresh engine on a throwaway collection. `tag` keeps the temp
/// dirs disjoint between test modules (and the thread id keeps them
/// disjoint between parallel tests).
pub(crate) fn temp_open(tag: &str) -> (PathBuf, u64, Vec<u8>) {
    let root = std::env::temp_dir().join(format!(
        "turna-bridge-{tag}-{}-{:?}-{}",
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
    let body = serde_json::to_vec(&json!({
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

/// Open a fresh engine and import the named fixture package.
pub(crate) fn temp_open_imported(tag: &str, package: &str) -> (PathBuf, u64) {
    let (root, handle, _) = temp_open(tag);
    dispatch(
        handle,
        OP_IMPORT_PACKAGE,
        &serde_json::to_vec(&json!({
            "package_path": package_path(package).to_string_lossy(),
        }))
        .unwrap(),
    )
    .unwrap();
    (root, handle)
}

/// Root of the checked-in fixture tree (`test/fixtures/anki_official`).
pub(crate) fn packages_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../test/fixtures/anki_official")
}

/// Resolve a fixture `.apkg` package file.
pub(crate) fn package_path(name: &str) -> PathBuf {
    packages_root().join("packages").join(name)
}

/// Resolve a golden expected-render JSON file.
pub(crate) fn expected_path(name: &str) -> PathBuf {
    packages_root().join("expected").join(name)
}

/// Walk SEARCH_CARDS_PAGE to the end and return every card id.
pub(crate) fn page_all_card_ids(handle: u64) -> Vec<i64> {
    let mut ids = Vec::new();
    let mut token: Option<String> = None;
    loop {
        let mut body = json!({"search": "", "page_size": 1000});
        if let Some(t) = token.as_deref() {
            body["page_token"] = json!(t);
        }
        let page = dispatch(handle, OP_SEARCH_CARDS_PAGE, &serde_json::to_vec(&body).unwrap())
            .unwrap();
        ids.extend(
            page["cardIds"]
                .as_array()
                .unwrap()
                .iter()
                .map(|v| v.as_i64().unwrap()),
        );
        token = page["nextPageToken"].as_str().map(|s| s.to_string());
        if token.is_none() {
            break;
        }
    }
    ids
}
