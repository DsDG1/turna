//! Minimal C ABI for the official Anki core spike.
//!
//! P0-006 implements Collection open/close/check and handle lifecycle.
//! Import/render/scheduler operations still land in later P0 tasks.

mod abi;
mod engine;

pub use abi::turna_anki_buffer_free;
pub use abi::turna_anki_call;
pub use abi::turna_anki_cancel;
pub use abi::turna_anki_engine_close;
pub use abi::turna_anki_engine_new;
pub use abi::turna_anki_engine_open;

pub const TURNA_ANKI_ABI_VERSION: u32 = 1;

/// Stable C ABI version. Dart loads the dynamic library and calls this
/// before any other symbol.
#[no_mangle]
pub extern "C" fn turna_anki_abi_version() -> u32 {
    TURNA_ANKI_ABI_VERSION
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn abi_version_is_one() {
        assert_eq!(turna_anki_abi_version(), 1);
    }

    #[test]
    fn collection_builder_is_visible_and_closes() {
        let col = anki::collection::CollectionBuilder::default()
            .build()
            .expect("in-memory Collection");
        col.close(None).expect("close in-memory Collection");
    }

    #[test]
    fn import_apkg_is_callable_and_rejects_missing_file() {
        let mut builder = anki::collection::CollectionBuilder::new(":memory:");
        builder.set_media_paths("/tmp/turna-anki-spike-media", "/tmp/turna-anki-spike-media.db");
        let mut col = builder.build().expect("in-memory Collection");
        let err = col
            .import_apkg(
                "/no/such/turna-spike.apkg",
                anki::import_export::package::ImportAnkiPackageOptions::default(),
            )
            .expect_err("missing package must fail");
        let _ = format!("{err:?}");
        col.close(None).expect("close after failed import");
    }
}
