//! Stable C ABI. Panic must not unwind across FFI.

use std::os::raw::c_uint;
use std::panic::AssertUnwindSafe;
use std::ptr;

use crate::engine;

pub const STATUS_OK: i32 = engine::STATUS_OK;
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

/// Allocate a C buffer with `capacity == length` via `Box<[u8]>`.
/// Callers must free with [`turna_anki_buffer_free`].
fn ok_bytes(bytes: Vec<u8>) -> TurnaAnkiResult {
    if bytes.is_empty() {
        return TurnaAnkiResult {
            status: STATUS_OK,
            buffer: empty_buffer(),
        };
    }
    let boxed = bytes.into_boxed_slice();
    let len = boxed.len();
    let ptr = Box::into_raw(boxed) as *mut u8;
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

fn encode_ok(response: serde_json::Value) -> TurnaAnkiResult {
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

const MAX_FFI_REQUEST_BYTES: usize = 8 * 1024 * 1024;

/// Request bytes live only for this FFI entry. Never store the slice on Engine.
fn request_bytes<'a>(ptr: *const u8, len: usize) -> Result<&'a [u8], i32> {
    if len == 0 {
        return Ok(&[]);
    }
    if ptr.is_null() || len > MAX_FFI_REQUEST_BYTES {
        return Err(STATUS_INVALID_ARGUMENT);
    }
    // Safety: the C caller keeps [ptr, ptr+len) valid for this call only.
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
pub extern "C" fn turna_anki_engine_new(_config: *const u8, _config_len: usize) -> TurnaAnkiResult {
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
            Ok(response) => match serde_json::to_value(response) {
                Ok(value) => encode_ok(value),
                Err(_) => err(STATUS_BACKEND_PANIC),
            },
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
        Ok(bytes) => match crate::contract::dispatch_call(handle, operation, bytes) {
            Ok(response) => encode_ok(response),
            Err(status) => err(status),
        },
        Err(status) => err(status),
    })
}

#[no_mangle]
pub extern "C" fn turna_anki_cancel(handle: u64) -> TurnaAnkiResult {
    guard(|| match crate::ops::request_cancel(handle) {
        Ok(value) => encode_ok(value),
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
/// the same `len`. Layout is `Box<[u8]>` (`capacity == length`).
#[no_mangle]
pub unsafe extern "C" fn turna_anki_buffer_free(ptr: *mut u8, len: usize) {
    let _ = std::panic::catch_unwind(AssertUnwindSafe(|| {
        if ptr.is_null() {
            return;
        }
        drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(ptr, len)));
    }));
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
        assert_eq!(again.status, engine::STATUS_INVALID_HANDLE);
    }

    #[test]
    fn invalid_handle_is_rejected() {
        let body = br#"{"package_path":"/tmp/missing-turna.apkg"}"#;
        let result = turna_anki_call(
            0,
            crate::engine::OP_IMPORT_PACKAGE,
            body.as_ptr(),
            body.len(),
        );
        assert_eq!(result.status, engine::STATUS_INVALID_HANDLE);
    }

    #[test]
    fn null_nonzero_request_is_rejected() {
        let result = turna_anki_call(1, 1, ptr::null(), 4);
        assert_eq!(result.status, STATUS_INVALID_ARGUMENT);
    }

    #[test]
    fn oversize_request_is_rejected() {
        let one = 1u8;
        let result = turna_anki_call(1, 1, &one, MAX_FFI_REQUEST_BYTES + 1);
        assert_eq!(result.status, STATUS_INVALID_ARGUMENT);
    }

    #[test]
    fn empty_and_non_exact_capacity_alloc_free() {
        let empty = ok_bytes(Vec::new());
        assert!(empty.buffer.ptr.is_null());
        assert_eq!(empty.buffer.len, 0);
        unsafe { turna_anki_buffer_free(empty.buffer.ptr, empty.buffer.len) };

        let tiny = ok_bytes(vec![0x2a]);
        assert_eq!(tiny.buffer.len, 1);
        unsafe { turna_anki_buffer_free(tiny.buffer.ptr, tiny.buffer.len) };

        let mut grown = Vec::with_capacity(64);
        grown.extend_from_slice(b"turna-anki-abi");
        assert!(grown.capacity() > grown.len());
        let result = ok_bytes(grown);
        assert_eq!(result.buffer.len, 14);
        unsafe { turna_anki_buffer_free(result.buffer.ptr, result.buffer.len) };
    }

    #[test]
    fn one_hundred_thousand_alloc_free_cycles() {
        for i in 0..100_000u32 {
            let payload = i.to_le_bytes().to_vec();
            let result = ok_bytes(payload);
            unsafe { turna_anki_buffer_free(result.buffer.ptr, result.buffer.len) };
        }
    }

    #[test]
    fn panic_becomes_transport_status() {
        let result = guard(|| panic!("ffi must not unwind"));
        assert_eq!(result.status, STATUS_BACKEND_PANIC);
        assert!(result.buffer.ptr.is_null());
    }

    #[test]
    fn request_bytes_are_not_static() {
        let data = [1u8, 2, 3];
        let slice = request_bytes(data.as_ptr(), data.len()).unwrap();
        assert_eq!(slice, &data);
        // Compiling this test with a non-'static lifetime is the assertion.
        let _borrowed: &[u8] = slice;
    }
}
