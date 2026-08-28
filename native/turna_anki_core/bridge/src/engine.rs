//! Collection engine state machine. Handles are never raw Collection pointers.

use std::collections::HashMap;
use std::collections::HashSet;
use std::path::Path;
use std::path::PathBuf;
use std::sync::atomic::AtomicBool;
use std::sync::atomic::AtomicU64;
use std::sync::atomic::Ordering;
use std::sync::Arc;
use std::sync::Mutex;

use anki::collection::Collection;
use anki::collection::CollectionBuilder;
use anki::scheduler::states::SchedulingStates;
use anki::ProgressState;
use serde::Deserialize;
use serde::Serialize;

pub const STATUS_OK: i32 = 0;
pub const STATUS_UNIMPLEMENTED: i32 = 10;
pub const STATUS_INVALID_HANDLE: i32 = 11;
pub const STATUS_INVALID_ARGUMENT: i32 = 12;
pub const STATUS_BACKEND_PANIC: i32 = 13;
pub const STATUS_INVALID_STATE: i32 = 16;
pub const STATUS_COLLECTION_ALREADY_OPEN: i32 = 17;
pub const STATUS_COLLECTION_LOCKED: i32 = 18;
pub const STATUS_COLLECTION_OPEN_FAILED: i32 = 19;
pub const STATUS_PACKAGE_NOT_FOUND: i32 = 20;
pub const STATUS_PACKAGE_INVALID: i32 = 21;
pub const STATUS_IMPORT_CANCELLED: i32 = 22;
pub const STATUS_CARD_NOT_FOUND: i32 = 23;
pub const STATUS_RENDER_FAILED: i32 = 24;
pub const STATUS_QUEUE_EMPTY: i32 = 25;
pub const STATUS_SCHEDULING_CONTEXT_STALE: i32 = 26;
pub const STATUS_ANSWER_FAILED: i32 = 27;
pub const STATUS_UNDO_UNAVAILABLE: i32 = 28;
pub const STATUS_IO_ERROR: i32 = 29;
pub const STATUS_COLLECTION_CORRUPT: i32 = 30;
pub const STATUS_CONTRACT_VERSION_MISMATCH: i32 = 31;
pub const STATUS_INTERNAL_ERROR: i32 = 32;
pub const STATUS_PAGE_TOKEN_STALE: i32 = 33;
pub const STATUS_TYPED_FIELD_NOT_FOUND: i32 = 34;
pub const STATUS_TYPED_CLOZE_EMPTY: i32 = 35;
pub const STATUS_PROJECTION_SNAPSHOT_STALE: i32 = 36;

pub const OP_OPEN_COLLECTION: u32 = 2;
pub const OP_CLOSE_COLLECTION: u32 = 3;
pub const OP_CHECK_COLLECTION: u32 = 4;
pub const OP_IMPORT_PACKAGE: u32 = 5;
pub const OP_LATEST_PROGRESS: u32 = 6;
pub const OP_CANCEL_OPERATION: u32 = 7;
pub const OP_LIST_DECK_TREE: u32 = 8;
pub const OP_SEARCH_CARDS: u32 = 9;
pub const OP_RENDER_CARD: u32 = 10;
pub const OP_SET_CURRENT_DECK: u32 = 11;
pub const OP_GET_REVIEW_QUEUE: u32 = 12;
pub const OP_DESCRIBE_NEXT_STATES: u32 = 13;
pub const OP_ANSWER_CARD: u32 = 14;
pub const OP_GET_UNDO_STATUS: u32 = 15;
pub const OP_UNDO: u32 = 16;
pub const OP_CREATE_BACKUP: u32 = 17;
pub const OP_SEARCH_CARDS_PAGE: u32 = 18;
pub const OP_GET_NOTE_CARDS_BATCH: u32 = 19;
pub const OP_GET_CARD_DESCRIPTORS_BATCH: u32 = 20;
pub const OP_RESTORE_BACKUP: u32 = 21;
pub const OP_COMPARE_TYPED_ANSWER: u32 = 22;
pub const OP_EXTRACT_CLOZE_FOR_TYPING: u32 = 23;
pub const OP_GET_PROJECTION_SCHEMAS: u32 = 24;
pub const OP_BEGIN_PROJECTION_READ: u32 = 25;
pub const OP_GET_PROJECTION_ROWS_BATCH: u32 = 26;
pub const OP_REDO: u32 = 27;
pub const OP_BURY_OR_SUSPEND_CARDS: u32 = 28;
pub const OP_COUNTS_FOR_DECK_TODAY: u32 = 29;
pub const OP_CONGRATS_INFO: u32 = 30;
pub const OP_DELETE_NOTES: u32 = 31;
pub const OP_DELETE_CARDS: u32 = 32;
pub const OP_STATS_FOR_CARDS_BATCH: u32 = 33;
pub const OP_SCHEDULE_CARDS_AS_NEW: u32 = 34;
pub const OP_ANSWER_AHEAD_CARDS: u32 = 35;
pub const OP_ENSURE_TODAY_NEW_QUOTA: u32 = 36;
pub const STATUS_REDO_UNAVAILABLE: i32 = 37;
pub const STATUS_DECK_NOT_FOUND: i32 = 38;
pub const STATUS_SCHEDULER_BUSY: i32 = 39;
pub const STATUS_SCHEDULER_CAPABILITY_MISSING: i32 = 40;
pub const STATUS_ANSWER_COMMIT_UNKNOWN: i32 = 41;

pub const MAX_REQUEST_BYTES: usize = 1_048_576;
pub const MAX_RESPONSE_BYTES: usize = 8_388_608;
pub const MAX_RENDER_HTML_BYTES: usize = 4_194_304;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum EngineState {
    Created,
    Open,
    Closed,
}

#[derive(Debug, Deserialize)]
pub struct OpenRequest {
    pub collection_path: String,
    pub media_folder: String,
    pub media_db: String,
    #[serde(default)]
    pub check_integrity: bool,
    #[serde(default)]
    pub allowed_root: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct LifecycleResponse {
    pub state: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub created: Option<bool>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TokenConsumption {
    Pending,
    InFlight,
    Committed,
    FailedUnwritten,
    Unknown,
}

pub struct AnswerToken {
    pub session_id: String,
    pub queue_epoch: u64,
    pub card_id: i64,
    pub states: SchedulingStates,
    pub consumption: TokenConsumption,
}

pub struct PageSnapshot {
    pub generation: u64,
    pub fingerprint: String,
    pub ids: Arc<Vec<i64>>,
}

pub struct Engine {
    pub state: EngineState,
    pub collection: Option<Collection>,
    pub collection_path: Option<PathBuf>,
    pub media_folder: Option<PathBuf>,
    pub media_db: Option<PathBuf>,
    pub session: u64,
    pub session_id: String,
    pub queue_epoch: u64,
    pub next_token: u64,
    pub tokens: HashMap<String, AnswerToken>,
    pub committed_mutations: HashSet<String>,
    pub debug_fail_before_answer: bool,
    pub debug_fail_after_commit: bool,
    pub allow_injected_answered_at: bool,
    pub page_generation: u64,
    pub page_snapshot: Option<PageSnapshot>,
    pub projection_snapshot: Option<crate::projection::ProjectionSnapshot>,
    pub allowed_root: Option<PathBuf>,
}

impl Engine {
    fn new() -> Self {
        Self {
            state: EngineState::Created,
            collection: None,
            collection_path: None,
            media_folder: None,
            media_db: None,
            session: 1,
            session_id: "session-1".to_string(),
            queue_epoch: 1,
            next_token: 1,
            tokens: HashMap::new(),
            committed_mutations: HashSet::new(),
            debug_fail_before_answer: false,
            debug_fail_after_commit: false,
            allow_injected_answered_at: false,
            page_generation: 1,
            page_snapshot: None,
            projection_snapshot: None,
            allowed_root: None,
        }
    }

    pub fn invalidate_tokens(&mut self) {
        self.tokens.clear();
        self.session = self.session.wrapping_add(1);
        if self.session == 0 {
            self.session = 1;
        }
        self.queue_epoch = self.queue_epoch.wrapping_add(1);
        if self.queue_epoch == 0 {
            self.queue_epoch = 1;
        }
        self.session_id = format!("session-{}", self.session);
    }

    pub fn begin_queue_epoch(&mut self) {
        self.invalidate_tokens();
    }
}

pub struct EngineSlot {
    pub engine: Mutex<Engine>,
    pub progress: Arc<Mutex<ProgressState>>,
    pub busy: AtomicBool,
}

static NEXT_HANDLE: AtomicU64 = AtomicU64::new(1);
static REGISTRY: Mutex<Option<HashMap<u64, Arc<EngineSlot>>>> = Mutex::new(None);
/// Serializes open/reclaim so two handles cannot both pass the "not open
/// elsewhere" check against the same collection path.
static OPEN_GATE: Mutex<()> = Mutex::new(());

fn with_registry<T>(f: impl FnOnce(&mut HashMap<u64, Arc<EngineSlot>>) -> T) -> Result<T, i32> {
    let mut guard = REGISTRY.lock().map_err(|_| STATUS_BACKEND_PANIC)?;
    let map = guard.get_or_insert_with(HashMap::new);
    Ok(f(map))
}

pub fn alloc_engine() -> Result<u64, i32> {
    let handle = NEXT_HANDLE.fetch_add(1, Ordering::Relaxed);
    with_registry(|map| {
        map.insert(
            handle,
            Arc::new(EngineSlot {
                engine: Mutex::new(Engine::new()),
                progress: Arc::new(Mutex::new(ProgressState::default())),
                busy: AtomicBool::new(false),
            }),
        );
    })?;
    Ok(handle)
}

pub fn slot(handle: u64) -> Result<Arc<EngineSlot>, i32> {
    if handle == 0 {
        return Err(STATUS_INVALID_HANDLE);
    }
    with_registry(|map| map.get(&handle).cloned())?.ok_or(STATUS_INVALID_HANDLE)
}

fn engine_arc(handle: u64) -> Result<Arc<EngineSlot>, i32> {
    slot(handle)
}

pub fn free_engine(handle: u64) -> Result<(), i32> {
    let slot = with_registry(|map| map.remove(&handle))?.ok_or(STATUS_INVALID_HANDLE)?;
    let mut engine = slot.engine.lock().map_err(|_| STATUS_BACKEND_PANIC)?;
    close_collection_inner(&mut engine)?;
    Ok(())
}

#[allow(dead_code)]
pub fn live_handle_count() -> Result<usize, i32> {
    with_registry(|map| map.len())
}

pub struct BusyGuard<'a> {
    flag: &'a AtomicBool,
}

impl<'a> BusyGuard<'a> {
    pub fn acquire(slot: &'a EngineSlot) -> Result<Self, i32> {
        if slot
            .busy
            .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
            .is_err()
        {
            return Err(STATUS_INVALID_STATE);
        }
        Ok(Self { flag: &slot.busy })
    }
}

impl Drop for BusyGuard<'_> {
    fn drop(&mut self) {
        self.flag.store(false, Ordering::Release);
    }
}

pub fn open_collection(handle: u64, request: &[u8]) -> Result<LifecycleResponse, i32> {
    let parsed: OpenRequest =
        serde_json::from_slice(request).map_err(|_| STATUS_INVALID_ARGUMENT)?;
    let paths = validate_paths(&parsed)?;

    let _gate = OPEN_GATE.lock().map_err(|_| STATUS_BACKEND_PANIC)?;
    let slot = engine_arc(handle)?;
    {
        let engine = slot.engine.lock().map_err(|_| STATUS_BACKEND_PANIC)?;
        if engine.state == EngineState::Open {
            return Err(STATUS_COLLECTION_ALREADY_OPEN);
        }
    }

    // Dead FlutterEngine / killed worker can leave an Open handle in REGISTRY.
    // Reclaim idle holders so a new session can open without force-stop.
    reclaim_other_open_holders(handle, &paths.collection)?;
    if path_open_elsewhere(handle, &paths.collection)? {
        return Err(STATUS_COLLECTION_LOCKED);
    }

    let mut engine = slot.engine.lock().map_err(|_| STATUS_BACKEND_PANIC)?;
    if engine.state == EngineState::Open {
        return Err(STATUS_COLLECTION_ALREADY_OPEN);
    }

    let existed = paths.collection.exists();
    create_parents(&paths)?;
    {
        let mut progress = slot.progress.lock().map_err(|_| STATUS_BACKEND_PANIC)?;
        progress.reset();
    }
    let built = CollectionBuilder::new(&paths.collection)
        .set_media_paths(&paths.media_folder, &paths.media_db)
        .set_check_integrity(parsed.check_integrity)
        .set_shared_progress_state(Arc::clone(&slot.progress))
        .build()
        .map_err(|_| STATUS_COLLECTION_OPEN_FAILED)?;
    engine.collection = Some(built);
    engine.collection_path = Some(paths.collection);
    engine.media_folder = Some(paths.media_folder);
    engine.media_db = Some(paths.media_db);
    engine.allowed_root = paths.allowed_root;
    engine.state = EngineState::Open;
    engine.page_generation = engine.page_generation.wrapping_add(1).max(1);
    engine.page_snapshot = None;
    engine.projection_snapshot = None;
    engine.committed_mutations.clear();
    engine.invalidate_tokens();
    Ok(LifecycleResponse {
        state: "open",
        created: Some(!existed),
    })
}

pub fn close_collection(handle: u64) -> Result<LifecycleResponse, i32> {
    let slot = engine_arc(handle)?;
    let mut engine = slot.engine.lock().map_err(|_| STATUS_BACKEND_PANIC)?;
    if engine.state != EngineState::Open {
        return Err(STATUS_INVALID_STATE);
    }
    close_collection_inner(&mut engine)?;
    engine.invalidate_tokens();
    Ok(LifecycleResponse {
        state: "closed",
        created: None,
    })
}

pub fn check_collection(handle: u64) -> Result<LifecycleResponse, i32> {
    let slot = engine_arc(handle)?;
    let mut engine = slot.engine.lock().map_err(|_| STATUS_BACKEND_PANIC)?;
    match engine.state {
        EngineState::Open => {
            let col = engine.collection.as_mut().ok_or(STATUS_INVALID_STATE)?;
            crate::ops::integrity_ok(col)?;
            Ok(LifecycleResponse {
                state: "open",
                created: None,
            })
        }
        EngineState::Created | EngineState::Closed => Err(STATUS_INVALID_STATE),
    }
}

pub fn bump_page_generation(engine: &mut Engine) {
    engine.page_generation = engine.page_generation.wrapping_add(1).max(1);
    engine.page_snapshot = None;
    engine.projection_snapshot = None;
}

pub fn reopen_open_collection(engine: &mut Engine, slot: &EngineSlot) -> Result<(), i32> {
    let collection = engine.collection_path.clone().ok_or(STATUS_INVALID_STATE)?;
    let media_folder = engine.media_folder.clone().ok_or(STATUS_INVALID_STATE)?;
    let media_db = engine.media_db.clone().ok_or(STATUS_INVALID_STATE)?;
    {
        let mut progress = slot.progress.lock().map_err(|_| STATUS_BACKEND_PANIC)?;
        progress.reset();
    }
    let built = CollectionBuilder::new(&collection)
        .set_media_paths(&media_folder, &media_db)
        .set_shared_progress_state(Arc::clone(&slot.progress))
        .build()
        .map_err(|_| STATUS_COLLECTION_OPEN_FAILED)?;
    engine.collection = Some(built);
    engine.state = EngineState::Open;
    engine.page_generation = engine.page_generation.wrapping_add(1).max(1);
    engine.page_snapshot = None;
    engine.projection_snapshot = None;
    engine.invalidate_tokens();
    Ok(())
}

pub fn dispatch(handle: u64, operation: u32, request: &[u8]) -> Result<serde_json::Value, i32> {
    if request.len() > MAX_REQUEST_BYTES {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    match operation {
        OP_OPEN_COLLECTION => to_json(open_collection(handle, request)?),
        OP_CLOSE_COLLECTION => to_json(close_collection(handle)?),
        OP_CHECK_COLLECTION => to_json(check_collection(handle)?),
        OP_CREATE_BACKUP => crate::import::create_backup(handle, request),
        OP_RESTORE_BACKUP => crate::import::restore_backup(handle, request),
        OP_SEARCH_CARDS_PAGE => crate::query::search_cards_page(handle, request),
        OP_GET_NOTE_CARDS_BATCH => crate::query::get_note_cards_batch(handle, request),
        OP_GET_CARD_DESCRIPTORS_BATCH => crate::query::get_card_descriptors_batch(handle, request),
        OP_GET_PROJECTION_SCHEMAS => crate::projection::get_projection_schemas(handle, request),
        OP_BEGIN_PROJECTION_READ => crate::projection::begin_projection_read(handle, request),
        OP_GET_PROJECTION_ROWS_BATCH => {
            crate::projection::get_projection_rows_batch(handle, request)
        }
        other => crate::ops::dispatch_op(handle, other, request),
    }
}

fn to_json<T: Serialize>(value: T) -> Result<serde_json::Value, i32> {
    serde_json::to_value(value).map_err(|_| STATUS_BACKEND_PANIC)
}

pub(crate) fn close_collection_inner(engine: &mut Engine) -> Result<(), i32> {
    if let Some(col) = engine.collection.take() {
        col.close(None).map_err(|_| STATUS_COLLECTION_OPEN_FAILED)?;
    }
    if engine.state == EngineState::Open {
        engine.state = EngineState::Closed;
    }
    Ok(())
}

struct ValidatedPaths {
    collection: PathBuf,
    media_folder: PathBuf,
    media_db: PathBuf,
    allowed_root: Option<PathBuf>,
}

fn contains_nul(path: &str) -> bool {
    path.as_bytes().contains(&0)
}

fn resolve_path(raw: &str) -> Result<PathBuf, i32> {
    if raw.is_empty() || contains_nul(raw) {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    let path = PathBuf::from(raw);
    if !path.is_absolute() {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    if path.exists() {
        return path.canonicalize().map_err(|_| STATUS_INVALID_ARGUMENT);
    }
    let mut ancestor = path.as_path();
    let mut missing = Vec::new();
    while !ancestor.exists() {
        let name = ancestor.file_name().ok_or(STATUS_INVALID_ARGUMENT)?;
        missing.push(name.to_os_string());
        ancestor = ancestor.parent().ok_or(STATUS_INVALID_ARGUMENT)?;
    }
    let mut resolved = ancestor
        .canonicalize()
        .map_err(|_| STATUS_INVALID_ARGUMENT)?;
    for part in missing.into_iter().rev() {
        resolved.push(part);
    }
    Ok(resolved)
}

fn ensure_inside_root(path: &Path, root: &Path) -> Result<(), i32> {
    let root_canon = if root.exists() {
        root.canonicalize().map_err(|_| STATUS_INVALID_ARGUMENT)?
    } else {
        return Err(STATUS_INVALID_ARGUMENT);
    };
    if !path.starts_with(&root_canon) {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    Ok(())
}

fn validate_paths(request: &OpenRequest) -> Result<ValidatedPaths, i32> {
    let collection = resolve_path(&request.collection_path)?;
    let media_folder = resolve_path(&request.media_folder)?;
    let media_db = resolve_path(&request.media_db)?;
    if collection == media_folder || collection == media_db || media_folder == media_db {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    if media_folder.starts_with(&collection) || collection.starts_with(&media_folder) {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    let allowed_root = match request.allowed_root.as_deref() {
        Some(root) => {
            let resolved = resolve_path(root)?;
            ensure_inside_root(&collection, &resolved)?;
            ensure_inside_root(&media_folder, &resolved)?;
            ensure_inside_root(&media_db, &resolved)?;
            Some(resolved)
        }
        None => None,
    };
    Ok(ValidatedPaths {
        collection,
        media_folder,
        media_db,
        allowed_root,
    })
}

fn create_parents(paths: &ValidatedPaths) -> Result<(), i32> {
    if let Some(parent) = paths.collection.parent() {
        std::fs::create_dir_all(parent).map_err(|_| STATUS_COLLECTION_OPEN_FAILED)?;
    }
    std::fs::create_dir_all(&paths.media_folder).map_err(|_| STATUS_COLLECTION_OPEN_FAILED)?;
    if let Some(parent) = paths.media_db.parent() {
        std::fs::create_dir_all(parent).map_err(|_| STATUS_COLLECTION_OPEN_FAILED)?;
    }
    Ok(())
}

fn other_slots(self_handle: u64) -> Result<Vec<Arc<EngineSlot>>, i32> {
    with_registry(|map| {
        map.iter()
            .filter(|(id, _)| **id != self_handle)
            .map(|(_, arc)| Arc::clone(arc))
            .collect::<Vec<_>>()
    })
}

fn path_open_elsewhere(self_handle: u64, collection: &Path) -> Result<bool, i32> {
    for slot in other_slots(self_handle)? {
        let engine = slot.engine.lock().map_err(|_| STATUS_BACKEND_PANIC)?;
        if engine.state == EngineState::Open
            && engine
                .collection_path
                .as_deref()
                .is_some_and(|open| open == collection)
        {
            return Ok(true);
        }
    }
    Ok(false)
}

fn reclaim_other_open_holders(self_handle: u64, collection: &Path) -> Result<(), i32> {
    for slot in other_slots(self_handle)? {
        let mut engine = slot.engine.lock().map_err(|_| STATUS_BACKEND_PANIC)?;
        if engine.state != EngineState::Open
            || !engine
                .collection_path
                .as_deref()
                .is_some_and(|open| open == collection)
        {
            continue;
        }
        // Same collection. An idle holder is a dead-session leftover and may
        // be reclaimed; a busy one is mid-operation (import / answer / render)
        // and closing its Collection under it would surface INVALID_STATE
        // inside that op — report locked and let the caller retry.
        if slot.busy.load(Ordering::Acquire) {
            return Err(STATUS_COLLECTION_LOCKED);
        }
        close_collection_inner(&mut engine)?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn temp_paths() -> (PathBuf, OpenRequest) {
        let root = std::env::temp_dir().join(format!(
            "turna-life-{}-{}",
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
        (root, request)
    }

    fn encode(request: &OpenRequest) -> Vec<u8> {
        serde_json::to_vec(&serde_json::json!({
            "collection_path": request.collection_path,
            "media_folder": request.media_folder,
            "media_db": request.media_db,
            "check_integrity": request.check_integrity,
            "allowed_root": request.allowed_root,
        }))
        .unwrap()
    }

    #[test]
    fn open_close_reopen_creates_files() {
        let (root, request) = temp_paths();
        let handle = alloc_engine().unwrap();
        let opened = open_collection(handle, &encode(&request)).unwrap();
        assert_eq!(opened.state, "open");
        assert_eq!(opened.created, Some(true));
        assert!(Path::new(&request.collection_path).exists());
        assert!(Path::new(&request.media_folder).is_dir());
        assert!(check_collection(handle).is_ok());

        assert_eq!(close_collection(handle).unwrap().state, "closed");
        assert_eq!(
            open_collection(handle, &encode(&request)).unwrap().created,
            Some(false)
        );
        free_engine(handle).unwrap();
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn double_open_is_already_open() {
        let (root, request) = temp_paths();
        let handle = alloc_engine().unwrap();
        open_collection(handle, &encode(&request)).unwrap();
        assert_eq!(
            open_collection(handle, &encode(&request)).unwrap_err(),
            STATUS_COLLECTION_ALREADY_OPEN
        );
        free_engine(handle).unwrap();
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn second_handle_reclaims_idle_first() {
        let (root, request) = temp_paths();
        let first = alloc_engine().unwrap();
        let second = alloc_engine().unwrap();
        open_collection(first, &encode(&request)).unwrap();
        let opened = open_collection(second, &encode(&request)).unwrap();
        assert_eq!(opened.state, "open");
        assert_eq!(opened.created, Some(false));
        assert_eq!(close_collection(first).unwrap_err(), STATUS_INVALID_STATE);
        assert!(check_collection(second).is_ok());
        free_engine(first).unwrap();
        free_engine(second).unwrap();
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn reclaim_then_original_handle_can_reopen() {
        let (root, request) = temp_paths();
        let first = alloc_engine().unwrap();
        let second = alloc_engine().unwrap();
        let body = encode(&request);
        open_collection(first, &body).unwrap();
        open_collection(second, &body).unwrap();
        assert_eq!(close_collection(second).unwrap().state, "closed");
        assert_eq!(open_collection(first, &body).unwrap().created, Some(false));
        free_engine(first).unwrap();
        free_engine(second).unwrap();
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn allowed_root_rejects_escape() {
        let (root, mut request) = temp_paths();
        std::fs::create_dir_all(&root).unwrap();
        request.allowed_root = Some(root.to_string_lossy().into());
        request.collection_path = "/tmp/turna-escape-collection.anki2".into();
        let handle = alloc_engine().unwrap();
        assert_eq!(
            open_collection(handle, &encode(&request)).unwrap_err(),
            STATUS_INVALID_ARGUMENT
        );
        free_engine(handle).unwrap();
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn invalid_handle_and_relative_paths() {
        assert!(matches!(engine_arc(0), Err(STATUS_INVALID_HANDLE)));
        assert_eq!(free_engine(9_999_999).unwrap_err(), STATUS_INVALID_HANDLE);
        let handle = alloc_engine().unwrap();
        let bad = br#"{"collection_path":"rel.anki2","media_folder":"/tmp/a","media_db":"/tmp/b"}"#;
        assert_eq!(
            open_collection(handle, bad).unwrap_err(),
            STATUS_INVALID_ARGUMENT
        );
        assert_eq!(close_collection(handle).unwrap_err(), STATUS_INVALID_STATE);
        free_engine(handle).unwrap();
    }

    #[test]
    fn one_hundred_open_close_cycles() {
        let (root, request) = temp_paths();
        let handle = alloc_engine().unwrap();
        let body = encode(&request);
        let before = fd_count();
        for _ in 0..100 {
            open_collection(handle, &body).unwrap();
            close_collection(handle).unwrap();
        }
        let after = fd_count();
        free_engine(handle).unwrap();
        let _ = std::fs::remove_dir_all(root);
        assert!(
            after <= before + 8,
            "fd count grew from {before} to {after}"
        );
    }

    fn fd_count() -> usize {
        std::fs::read_dir("/proc/self/fd")
            .map(|entries| entries.count())
            .unwrap_or(0)
    }
}
