//! Stable C ABI. Panic must not unwind across FFI.

use std::collections::HashSet;
use std::os::raw::c_uint;
use std::panic::AssertUnwindSafe;
use std::ptr;
use std::sync::atomic::AtomicU64;
use std::sync::atomic::Ordering;
use std::sync::Mutex;

pub const STATUS_OK: i32 = 0;
pub const STATUS_UNIMPLEMENTED: i32 = 10;
pub const STATUS_INVALID_HANDLE: i32 = 11;
#[allow(dead_code)]
pub const STATUS_INVALID_ARGUMENT: i32 = 12;
pub const STATUS_BACKEND_PANIC: i32 = 13;

#[repr(C)]
pub struct TurnaAnkiBuffer {
    pub ptr: *mut u8,
    pub len: usize,
}

#[repr(C)]
pub struct TurnaAnkiResult {
    pub status: i32,
    pub buffer: TurnaAnkiBuffer,
}

static NEXT_HANDLE: AtomicU64 = AtomicU64::new(1);
static HANDLES: Mutex<Option<HashSet<u64>>> = Mutex::new(None);

fn empty_buffer() -> TurnaAnkiBuffer {
    TurnaAnkiBuffer {
        ptr: ptr::null_mut(),
        len: 0,
    }
}

fn ok_bytes(mut bytes: Vec<u8>) -> TurnaAnkiResult {
    if bytes.is_empty() {
        return TurnaAnkiResult {
            status: STATUS_OK,
            buffer: empty_buffer(),
        };
    }
    let ptr = bytes.as_mut_ptr();
    let len = bytes.len();
    std::mem::forget(bytes);
    TurnaAnkiResult {
        status: STATUS_OK,
        buffer: TurnaAnkiBuffer { ptr, len },
    }
}

fn err(status: i32) -> TurnaAnkiResult {
    TurnaAnkiResult {
        status,
        buffer: empty_buffer(),
    }
}

fn guard(f: impl FnOnce() -> TurnaAnkiResult) -> TurnaAnkiResult {
    match std::panic::catch_unwind(AssertUnwindSafe(f)) {
        Ok(result) => result,
        Err(_) => err(STATUS_BACKEND_PANIC),
    }
}

fn with_handles<T>(f: impl FnOnce(&mut HashSet<u64>) -> T) -> Result<T, TurnaAnkiResult> {
    let mut guard = HANDLES
        .lock()
        .map_err(|_| err(STATUS_BACKEND_PANIC))?;
    let set = guard.get_or_insert_with(HashSet::new);
    Ok(f(set))
}

/// Force official Collection/sqlite into the Android cdylib.
/// `CollectionBuilder::default()` alone is tiny and gets DCE'd; `build()`
/// pulls rusqlite and the rest of rslib.
fn touch_rslib() {
    static ONCE: std::sync::Once = std::sync::Once::new();
    ONCE.call_once(|| {
        if let Ok(col) = anki::collection::CollectionBuilder::default().build() {
            let _ = col.close(None);
        }
    });
}

#[no_mangle]
pub extern "C" fn turna_anki_engine_new(
    _config: *const u8,
    _config_len: usize,
) -> TurnaAnkiResult {
    guard(|| {
        touch_rslib();
        let handle = NEXT_HANDLE.fetch_add(1, Ordering::Relaxed);
        match with_handles(|set| {
            set.insert(handle);
        }) {
            Ok(()) => ok_bytes(handle.to_le_bytes().to_vec()),
            Err(result) => result,
        }
    })
}

fn require_handle(handle: u64) -> Result<(), TurnaAnkiResult> {
    if handle == 0 {
        return Err(err(STATUS_INVALID_HANDLE));
    }
    match with_handles(|set| set.contains(&handle)) {
        Ok(true) => Ok(()),
        Ok(false) => Err(err(STATUS_INVALID_HANDLE)),
        Err(result) => Err(result),
    }
}

#[no_mangle]
pub extern "C" fn turna_anki_engine_open(
    handle: u64,
    _request: *const u8,
    _request_len: usize,
) -> TurnaAnkiResult {
    guard(|| match require_handle(handle) {
        Ok(()) => err(STATUS_UNIMPLEMENTED),
        Err(result) => result,
    })
}

#[no_mangle]
pub extern "C" fn turna_anki_call(
    handle: u64,
    _operation: c_uint,
    _request: *const u8,
    _request_len: usize,
) -> TurnaAnkiResult {
    guard(|| match require_handle(handle) {
        Ok(()) => err(STATUS_UNIMPLEMENTED),
        Err(result) => result,
    })
}

#[no_mangle]
pub extern "C" fn turna_anki_cancel(handle: u64) -> TurnaAnkiResult {
    guard(|| match require_handle(handle) {
        Ok(()) => err(STATUS_UNIMPLEMENTED),
        Err(result) => result,
    })
}

#[no_mangle]
pub extern "C" fn turna_anki_engine_close(handle: u64) -> TurnaAnkiResult {
    guard(|| {
        if handle == 0 {
            return err(STATUS_INVALID_HANDLE);
        }
        match with_handles(|set| set.remove(&handle)) {
            Ok(true) => TurnaAnkiResult {
                status: STATUS_OK,
                buffer: empty_buffer(),
            },
            Ok(false) => err(STATUS_INVALID_HANDLE),
            Err(result) => result,
        }
    })
}

/// # Safety
/// `ptr` must be null or a pointer previously returned by this library with
/// the same `len`. Capacity equals `len` by construction.
#[no_mangle]
pub unsafe extern "C" fn turna_anki_buffer_free(ptr: *mut u8, len: usize) {
    if ptr.is_null() {
        return;
    }
    drop(Vec::from_raw_parts(ptr, len, len));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn engine_new_close_and_free_round_trip() {
        let created = turna_anki_engine_new(ptr::null(), 0);
        assert_eq!(created.status, STATUS_OK);
        assert!(!created.buffer.ptr.is_null());
        assert_eq!(created.buffer.len, 8);
        let handle = unsafe { u64::from_le_bytes(*(created.buffer.ptr as *const [u8; 8])) };
        unsafe { turna_anki_buffer_free(created.buffer.ptr, created.buffer.len) };

        let call = turna_anki_call(handle, 0, ptr::null(), 0);
        assert_eq!(call.status, STATUS_UNIMPLEMENTED);

        let closed = turna_anki_engine_close(handle);
        assert_eq!(closed.status, STATUS_OK);

        let again = turna_anki_engine_close(handle);
        assert_eq!(again.status, STATUS_INVALID_HANDLE);
    }

    #[test]
    fn invalid_handle_is_rejected() {
        let result = turna_anki_call(0, 1, ptr::null(), 0);
        assert_eq!(result.status, STATUS_INVALID_HANDLE);
    }
}
