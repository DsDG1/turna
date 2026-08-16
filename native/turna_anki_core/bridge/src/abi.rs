//! Stable C ABI. Panic must not unwind across FFI.

use std::os::raw::c_uint;
use std::panic::AssertUnwindSafe;
use std::ptr;

use crate::engine;

pub const STATUS_OK: i32 = engine::STATUS_OK;
pub const STATUS_UNIMPLEMENTED: i32 = engine::STATUS_UNIMPLEMENTED;
pub const STATUS_INVALID_HANDLE: i32 = engine::STATUS_INVALID_HANDLE;
pub const STATUS_INVALID_ARGUMENT: i32 = engine::STATUS_INVALID_ARGUMENT;
pub const STATUS_BACKEND_PANIC: i32 = engine::STATUS_BACKEND_PANIC;

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

fn encode_ok(response: engine::LifecycleResponse) -> TurnaAnkiResult {
    match serde_json::to_vec(&response) {
        Ok(bytes) => ok_bytes(bytes),
        Err(_) => err(STATUS_BACKEND_PANIC),
    }
}

fn guard(f: impl FnOnce() -> TurnaAnkiResult) -> TurnaAnkiResult {
    match std::panic::catch_unwind(AssertUnwindSafe(f)) {
        Ok(result) => result,
        Err(_) => err(STATUS_BACKEND_PANIC),
    }
}

fn request_bytes(ptr: *const u8, len: usize) -> Result<&'static [u8], i32> {
    if len == 0 {
        return Ok(&[]);
    }
    if ptr.is_null() {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    Ok(unsafe { std::slice::from_raw_parts(ptr, len) })
}

/// Force official Collection/sqlite into the Android cdylib.
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
        match engine::alloc_engine() {
            Ok(handle) => ok_bytes(handle.to_le_bytes().to_vec()),
            Err(status) => err(status),
        }
    })
}

#[no_mangle]
pub extern "C" fn turna_anki_engine_open(
    handle: u64,
    request: *const u8,
    request_len: usize,
) -> TurnaAnkiResult {
    guard(|| match request_bytes(request, request_len) {
        Ok(bytes) => match engine::open_collection(handle, bytes) {
            Ok(response) => encode_ok(response),
            Err(status) => err(status),
        },
        Err(status) => err(status),
    })
}

#[no_mangle]
pub extern "C" fn turna_anki_call(
    handle: u64,
    operation: c_uint,
    request: *const u8,
    request_len: usize,
) -> TurnaAnkiResult {
    guard(|| match request_bytes(request, request_len) {
        Ok(bytes) => match engine::dispatch(handle, operation, bytes) {
            Ok(response) => encode_ok(response),
            Err(status) => err(status),
        },
        Err(status) => err(status),
    })
}

#[no_mangle]
pub extern "C" fn turna_anki_cancel(handle: u64) -> TurnaAnkiResult {
    guard(|| match engine::engine_exists(handle) {
        Ok(true) => err(STATUS_UNIMPLEMENTED),
        Ok(false) => err(STATUS_INVALID_HANDLE),
        Err(status) => err(status),
    })
}

#[no_mangle]
pub extern "C" fn turna_anki_engine_close(handle: u64) -> TurnaAnkiResult {
    guard(|| match engine::free_engine(handle) {
        Ok(()) => TurnaAnkiResult {
            status: STATUS_OK,
            buffer: empty_buffer(),
        },
        Err(status) => err(status),
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
