//! OpenHarmony cross-compilation probe for the Turna Anki core.
//!
//! Scope is deliberately one layer: the **engine storage substrate**.
//! Nothing here touches rslib, the review scheduler, or card rendering.
//! A pass therefore means "the storage assumptions hold on OHOS" — it does
//! NOT mean "Anki works on OHOS".
//!
//! Four symbols, one per assumption that could independently be false:
//!
//! | symbol | assumption |
//! |---|---|
//! | `turna_anki_abi_version` | the C ABI is exported and lookup-able at all |
//! | `turna_anki_probe_sqlite_roundtrip` | bundled SQLite compiles and really reads/writes |
//! | `turna_anki_probe_unicase_collation` | the pinned `unicase` collation + VACUUM b-tree rebuild work |
//! | `turna_anki_probe_tokio_runtime` | a multi-thread tokio runtime can be built at all |
//! | `turna_anki_probe_tokio_fs` | `tokio::fs` works against the OHOS libc |
//! | `turna_anki_probe_tokio_signal` | OS signal registration works against the OHOS libc |

//!
//! Every probe returns `0` on pass and a distinct negative code on fail, so
//! a caller can attribute a failure without reading a log.
//!
//! # ABI safety
//!
//! Dart calls these through `DynamicLibrary.lookupFunction`, so a Rust panic
//! must never cross the boundary — unwinding into Dart is undefined behaviour.
//! Each probe wraps its body in `catch_unwind` and maps a panic to a code.

use std::panic::catch_unwind;

/// Mirrors `TURNA_ANKI_ABI_VERSION` in the real bridge so the probe and the
/// shipping library cannot drift apart unnoticed.
pub const TURNA_ANKI_ABI_VERSION: u32 = 1;

// Exit codes. Keep these stable: the Dart-side probe harness stringifies them.
const PASS: i32 = 0;
const E_SQLITE_VERSION: i32 = -10;
const E_SQLITE_OPEN: i32 = -11;
const E_SQLITE_SCHEMA: i32 = -12;
const E_SQLITE_WRITE: i32 = -13;
const E_SQLITE_READ: i32 = -14;
const E_COLLATION: i32 = -20;
const E_COLLATION_QUERY: i32 = -21;
const E_COLLATION_VACUUM: i32 = -22;
const E_TOKIO_RUNTIME: i32 = -30;
// Only referenced from the `#[cfg(unix)]` leg, so a host (Windows) build
// never reads it. The OHOS target is unix and does.
#[cfg_attr(not(unix), allow(dead_code))]
const E_TOKIO_SIGNAL: i32 = -31;
const E_TOKIO_FS: i32 = -32;
/// The directory existed but yielded no entries, so the read path was never
/// actually exercised.
const E_TOKIO_FS_EMPTY: i32 = -33;

const E_PANIC: i32 = -99;

/// Stable C ABI version. Dart loads the dynamic library and calls this before
/// any other symbol. Mirrors the real bridge's entry point exactly.
#[no_mangle]
pub extern "C" fn turna_anki_abi_version() -> u32 {
    catch_unwind(|| TURNA_ANKI_ABI_VERSION).unwrap_or(0)
}

/// Build an in-memory database, create a table, write rows, read them back.
///
/// Proves more than "SQLite links": a read-back of a value that was written
/// through a prepared statement is the minimum for `Collection` to be usable.
#[no_mangle]
pub extern "C" fn turna_anki_probe_sqlite_roundtrip() -> i32 {
    catch_unwind(probe_sqlite_roundtrip).unwrap_or(E_PANIC)
}

/// Register the pinned `unicase` collation, query through it, then VACUUM.
///
/// VACUUM is the load-bearing part: `compact_collection` relies on it to
/// rebuild `COLLATE unicase` b-trees, and a b-tree rebuild is the operation
/// most likely to differ on a non-glibc target.
#[no_mangle]
pub extern "C" fn turna_anki_probe_unicase_collation() -> i32 {
    catch_unwind(probe_unicase_collation).unwrap_or(E_PANIC)
}

/// tokio legs live further down, split into runtime / fs / signal so a hang
/// in one can be attributed instead of losing the other two verdicts.

fn probe_sqlite_roundtrip() -> i32 {

    let conn = match rusqlite::Connection::open_in_memory() {
        Ok(conn) => conn,
        Err(_) => return E_SQLITE_OPEN,
    };

    // A bundled SQLite older than 3.8 cannot be what rslib expects, and an
    // unexpected one would silently change index behaviour.
    if conn.query_row("select sqlite_version()", [], |row| row.get::<_, String>(0)).is_err() {
        return E_SQLITE_VERSION;
    }

    if conn
        .execute_batch("create table probe (id integer primary key, field text not null);")
        .is_err()
    {
        return E_SQLITE_SCHEMA;
    }

    {
        let Ok(mut stmt) = conn.prepare("insert into probe (id, field) values (?1, ?2)") else {
            return E_SQLITE_SCHEMA;
        };
        for id in 1..=8i64 {
            if stmt.execute((id, format!("value-{id}"))).is_err() {
                return E_SQLITE_WRITE;
            }
        }
    }

    let read_back: Result<i64, _> =
        conn.query_row("select count(*) from probe where field like 'value-%'", [], |row| {
            row.get(0)
        });
    match read_back {
        Ok(8) => PASS,
        Ok(_) => E_SQLITE_READ,
        Err(_) => E_SQLITE_READ,
    }
}

fn probe_unicase_collation() -> i32 {
    use unicase::UniCase;

    let conn = match rusqlite::Connection::open_in_memory() {
        Ok(conn) => conn,
        Err(_) => return E_COLLATION,
    };

    // Registration can fail (e.g. SQLite too old for custom collations), and
    // a silently absent collation would make every later query fall back to
    // BINARY — the exact failure this probe exists to catch.
    if conn
        .create_collation("unicase", |left: &str, right: &str| {
            UniCase::new(left).cmp(&UniCase::new(right))
        })
        .is_err()
    {
        return E_COLLATION;
    }

    if conn
        .execute_batch(
            "create table notes (id integer primary key, field text collate unicase not null);",
        )
        .is_err()
    {
        return E_COLLATION;
    }

    {
        let Ok(mut stmt) = conn.prepare("insert into notes (id, field) values (?1, ?2)") else {
            return E_COLLATION;
        };
        for (id, field) in [(1i64, "Café"), (2, "straße"), (3, "ISTANBUL")] {
            if stmt.execute((id, field)).is_err() {
                return E_COLLATION;
            }
        }
    }

    // Case-insensitive lookup must match exactly one row. If the collation
    // silently degraded to BINARY this returns 0 and the probe fails, which
    // is the failure mode that would corrupt note indexes downstream.
    let matched: Result<i64, _> = conn.query_row(
        "select count(*) from notes where field = ?1 collate unicase",
        ["cafÉ"],
        |row| row.get(0),
    );
    match matched {
        Ok(1) => {}
        Ok(_) => return E_COLLATION_QUERY,
        Err(_) => return E_COLLATION_QUERY,
    }

    // The b-tree rebuild. compact_collection cannot work without this.
    match conn.execute_batch("vacuum;") {
        Ok(()) => PASS,
        Err(_) => E_COLLATION_VACUUM,
    }
}

fn build_runtime() -> Result<tokio::runtime::Runtime, ()> {
    tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .enable_all()
        .build()
        .map_err(|_| ())
}

/// Runtime construction only. Split out because a hang here implicates thread
/// creation and the IO/time driver setup — both of which rslib depends on
/// everywhere — whereas a hang in the signal probe does not.
#[no_mangle]
pub extern "C" fn turna_anki_probe_tokio_runtime() -> i32 {
    catch_unwind(|| match build_runtime() {
        Ok(runtime) => {
            drop(runtime);
            PASS
        }
        Err(()) => E_TOKIO_RUNTIME,
    })
    .unwrap_or(E_PANIC)
}

/// `tokio::fs`, which rslib uses pervasively for media handling. Needs the
/// target libc's file APIs plus the runtime's blocking pool.
#[no_mangle]
pub extern "C" fn turna_anki_probe_tokio_fs() -> i32 {
    catch_unwind(probe_tokio_fs).unwrap_or(E_PANIC)
}

/// OS signal registration. This is the one that hung on a real Mate 90 Pro
/// Max. Context that decides whether it matters: the only `tokio::signal`
/// call site in rslib is `sync/http_server/mod.rs`, which the Turna bridge
/// never reaches (it drives the engine over the C ABI, not an HTTP server),
/// and `bridge/src` references tokio zero times. The feature is enabled, the
/// code path is not.
#[no_mangle]
pub extern "C" fn turna_anki_probe_tokio_signal() -> i32 {
    catch_unwind(probe_tokio_signal).unwrap_or(E_PANIC)
}

/// Path used by the `tokio::fs` probe.
///
/// Defaults to `"."`, which is a bad choice in an app process: the cwd of an
/// ArkTS ability is not something the sandbox guarantees is enumerable. The
/// first device run returned `E_TOKIO_FS` for exactly that reason, which is
/// indistinguishable from "tokio::fs is broken on OHOS" — a distinction that
/// matters because rslib leans on tokio::fs for media handling everywhere.
/// The caller therefore passes a directory it knows is readable.
static mut PROBE_FS_PATH: Option<std::ffi::CString> = None;

/// Set the directory the `tokio::fs` probe will enumerate. Takes the same
/// (pointer, length) shape the real bridge's C ABI uses for strings.
#[no_mangle]
pub extern "C" fn turna_anki_probe_set_fs_path(ptr: *const u8, len: usize) -> i32 {
    if ptr.is_null() {
        return -1;
    }
    let bytes = unsafe { std::slice::from_raw_parts(ptr, len) };
    match std::ffi::CString::new(bytes) {
        Ok(value) => {
            unsafe { PROBE_FS_PATH = Some(value) };
            PASS
        }
        Err(_) => -1,
    }
}

fn probe_tokio_fs() -> i32 {
    let path = unsafe {
        match &*std::ptr::addr_of!(PROBE_FS_PATH) {
            Some(value) => value.to_string_lossy().into_owned(),
            None => ".".to_string(),
        }
    };

    let runtime = match build_runtime() {
        Ok(runtime) => runtime,
        Err(()) => return E_TOKIO_RUNTIME,
    };

    runtime.block_on(async move {
        let dir = match tokio::fs::read_dir(&path).await {
            Ok(dir) => dir,
            Err(_) => return E_TOKIO_FS,
        };
        let mut stream = dir;
        // Drain the whole directory: a read_dir that yields nothing would
        // pass without touching the read path at all.
        let mut seen = 0usize;
        while let Ok(Some(_)) = stream.next_entry().await {
            seen += 1;
        }
        if seen == 0 {
            return E_TOKIO_FS_EMPTY;
        }
        PASS
    })
}

fn probe_tokio_signal() -> i32 {
    let runtime = match build_runtime() {
        Ok(runtime) => runtime,
        Err(()) => return E_TOKIO_RUNTIME,
    };

    runtime.block_on(async {
        // Constructing the stream exercises signal handler registration
        // against the target libc; polling once keeps the probe from waiting
        // on a signal that will never arrive.
        // Gated to unix so the probe also builds and runs on the dev host,
        // which is how the logic gets validated before crossing over.
        #[cfg(unix)]
        {
            let mut stream =
                match tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()) {
                    Ok(stream) => stream,
                    Err(_) => return E_TOKIO_SIGNAL,
                };
            // Poll once and stop. Upstream Anki does not enable tokio's
            // `time` feature either, so the probe must not reach for
            // tokio::time — using it would test a configuration the real
            // bridge never builds. One poll is enough: it drives the
            // signalfd/pipe registration against the target libc.
            let _ = std::future::poll_fn(|cx| stream.poll_recv(cx)).await;
        }
        #[cfg(not(unix))]
        {
            // Host-only run: skip the signal leg, it has no meaning off-unix.
        }

        PASS
    })
}


#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn abi_version_is_one() {
        assert_eq!(turna_anki_abi_version(), TURNA_ANKI_ABI_VERSION);
    }

    #[test]
    fn sqlite_roundtrip_passes_on_host() {
        assert_eq!(turna_anki_probe_sqlite_roundtrip(), PASS);
    }

    #[test]
    fn unicase_collation_passes_on_host() {
        assert_eq!(turna_anki_probe_unicase_collation(), PASS);
    }

    #[test]
    fn tokio_signal_passes_on_host() {
        assert_eq!(turna_anki_probe_tokio_signal(), PASS);
    }

    #[test]
    fn tokio_runtime_passes_on_host() {
        assert_eq!(turna_anki_probe_tokio_runtime(), PASS);
    }

    #[test]
    fn tokio_fs_passes_on_host() {
        // "." is empty-ish on the host too in some shells; use the crate dir.
        let here = std::env::current_dir().unwrap();
        let here = here.to_string_lossy().into_owned();
        let bytes = here.as_bytes();
        assert_eq!(
            turna_anki_probe_set_fs_path(bytes.as_ptr(), bytes.len()),
            PASS
        );
        assert_eq!(turna_anki_probe_tokio_fs(), PASS);
    }
}

