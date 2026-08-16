fn main() {
    let root = std::path::PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").unwrap());
    let path = root.join("contract/BACKEND_COMMIT");
    println!("cargo:rerun-if-changed=contract/BACKEND_COMMIT");
    println!("cargo:rerun-if-changed=anki/.git");
    let commit = std::fs::read_to_string(&path)
        .unwrap_or_else(|_| "967aa0d578fc75181e292e95326f9b58698da25c".to_string());
    let commit = commit.trim().to_string();
    println!("cargo:rustc-env=TURNA_ANKI_BACKEND_COMMIT={commit}");

    if let Some(head) = read_anki_head(&root) {
        if head != commit {
            let msg = format!("BACKEND_COMMIT {commit} != anki submodule HEAD {head}");
            if std::env::var("TURNA_ANKI_ALLOW_PIN_DRIFT").ok().as_deref() == Some("1") {
                println!("cargo:warning={msg}");
            } else {
                panic!("{msg}");
            }
        }
    }
}

fn read_anki_head(root: &std::path::Path) -> Option<String> {
    let git = root.join("anki/.git");
    let gitdir = if git.is_file() {
        let content = std::fs::read_to_string(&git).ok()?;
        let line = content.lines().next()?;
        let rel = line.strip_prefix("gitdir:")?.trim();
        root.join("anki").join(rel)
    } else if git.is_dir() {
        git
    } else {
        return None;
    };
    let head = std::fs::read_to_string(gitdir.join("HEAD")).ok()?;
    let head = head.trim();
    if let Some(r) = head.strip_prefix("ref:") {
        std::fs::read_to_string(gitdir.join(r.trim()))
            .ok()
            .map(|s| s.trim().to_string())
    } else {
        Some(head.to_string())
    }
}
