//! Minimal C ABI for the official Anki core spike.
//!
//! P0-001 only exports the contract version probe. Collection / import /
//! render / scheduler operations land in later P0 tasks.

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
}
