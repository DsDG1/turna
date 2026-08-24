fn main() {
    let root = std::path::PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").unwrap());
    let path = root.join("contract/BACKEND_COMMIT");
    println!("cargo:rerun-if-changed=contract/BACKEND_COMMIT");
    println!("cargo:rerun-if-changed=anki/.git");
    println!("cargo:rerun-if-changed=patches");
    verify_patches_applied(&root);
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

/// Fail the build when any documented patch is missing from the `anki/` tree.
///
/// A fresh clone (or a `git -C anki checkout -- .`) leaves the submodule
/// unpatched; without this check that surfaces as opaque compile errors in
/// rslib. Patches are the single source of truth here — the marker lines to
/// look for are derived from the `+` lines of each `patches/*.patch`.
fn verify_patches_applied(root: &std::path::Path) {
    let patches_dir = root.join("patches");
    let entries = match std::fs::read_dir(&patches_dir) {
        Ok(entries) => entries,
        Err(err) => panic!("cannot read {}: {err}", patches_dir.display()),
    };
    let mut checked = 0;
    for entry in entries.flatten() {
        let name = entry.file_name().to_string_lossy().to_string();
        if !name.ends_with(".patch") || !entry.path().is_file() {
            continue;
        }
        checked += 1;
        let content = std::fs::read_to_string(entry.path())
            .unwrap_or_else(|err| panic!("read {name}: {err}"));
        let mut target: Option<String> = None;
        let mut added: Vec<String> = Vec::new();
        for line in content.lines() {
            if let Some(rest) = line.strip_prefix("diff --git a/") {
                if let Some(path) = rest.split(" b/").next() {
                    target = Some(path.trim().to_string());
                }
            } else if line.starts_with('+') && !line.starts_with("+++") {
                added.push(line[1..].to_string());
            }
        }
        let target = target.unwrap_or_else(|| panic!("{name}: no `diff --git` target found"));
        let file = root.join("anki").join(&target);
        let body = std::fs::read_to_string(&file).unwrap_or_else(|_| {
            panic!(
                "{name}: anki/{target} is missing; is the submodule checked out \
                 and are the patches applied? Run build-android/apply_patches.sh"
            )
        });
        for line in added.iter().filter(|line| !line.trim().is_empty()) {
            if !body
                .lines()
                .any(|candidate| candidate.trim() == line.trim())
            {
                panic!(
                    "{name}: expected change not present in anki/{target}:\n    {line}\n\
                     Run build-android/apply_patches.sh (see patches/README.md)."
                );
            }
        }
    }
    if checked == 0 {
        panic!("no patches/*.patch found; the anki/ pin requires the documented patches");
    }
}
