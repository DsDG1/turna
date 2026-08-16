fn main() {
    let root = std::path::PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").unwrap());
    let path = root.join("contract/BACKEND_COMMIT");
    println!("cargo:rerun-if-changed=contract/BACKEND_COMMIT");
    let commit = std::fs::read_to_string(&path)
        .unwrap_or_else(|_| "967aa0d578fc75181e292e95326f9b58698da25c".to_string());
    println!(
        "cargo:rustc-env=TURNA_ANKI_BACKEND_COMMIT={}",
        commit.trim()
    );
}
