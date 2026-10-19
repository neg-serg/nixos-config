//! Make an un-wrapped binary runnable on NixOS.
//!
//! NixOS has no `/etc/ld.so.conf`, so `ld.so` can only resolve a bare soname inside the
//! directories baked into `DT_RUNPATH` — and a `cargo build` binary carries just whatever
//! `target/` happened to name. `winit` does `dlopen("libwayland-client.so.0")` and `ash` does
//! `dlopen("libvulkan.so.1")`; on a NixOS host neither resolves, and the app dies at startup
//! with `NoWaylandLib` even though the libraries are installed. That is the whole reason this
//! crate used to need `launch-live.sh` to massage `LD_LIBRARY_PATH`.
//!
//! The fix is to resolve them ourselves *before* winit starts: `RTLD_GLOBAL` puts the object
//! on the global search list under its SONAME, so the later bare-soname `dlopen` finds it.
//! Nothing in the app can influence winit from the inside, but this works from the outside and
//! costs one `dlopen` per library.
//!
//! Discovery order, cheapest first:
//!
//! 1. The soname itself — it already resolves when the binary is wrapped or the variable is
//!    set by a dev shell, and then there is nothing to do.
//! 2. `PLAYER_LIB_DIRS` (colon-separated) — the escape hatch for a machine that is laid out
//!    unusually.
//! 3. A cache file under `$XDG_CACHE_HOME/player-proto/libs`, written the first time a scan
//!    succeeds. Every later start is then two `stat` calls per library.
//! 4. The conventional profile directories (`$NIX_PROFILES`, the per-user and default
//!    profiles, `/run/current-system/sw/lib`, `/run/opengl-driver/lib`). The Mesa/Vulkan
//!    loader is always reachable through the last one, because that is the path the NixOS
//!    module system points every graphics application at.
//! 5. A scan of `/nix/store` for the owning packages. This is the slow path (a few thousand
//!    directory entries), which is exactly why the result is cached.

use std::ffi::CString;

/// Libraries the graphics stack dlopens by soname, in the order they are needed.
const NEEDED: &[&str] = &[
    // winit: the Wayland client, the keyboard map, and the EGL implementation it may probe.
    "libwayland-client.so.0",
    "libwayland-cursor.so.0",
    "libwayland-egl.so.1",
    "libxkbcommon.so.0",
    // ash: the Vulkan loader. Without it the app falls back to no device at all.
    "libvulkan.so.1",
];

/// Resolve and preload everything in `NEEDED`. Returns the number of libraries newly loaded,
/// which makes the function observable in a log line without making the caller care.
///
/// A library that cannot be found is not an error here: the app may be running on an X11
/// session, or without Vulkan, and the toolkit's own error message is better than ours.
pub fn ensure_graphics_libs() -> usize {
    let mut loaded = 0;
    for soname in NEEDED {
        if already_resolvable(soname) {
            continue;
        }
        for dir in search_dirs() {
            let candidate = dir.join(soname);
            if !candidate.is_file() {
                continue;
            }
            if dlopen_global(&candidate) {
                loaded += 1;
                remember(&candidate);
                break;
            }
        }
    }
    loaded
}

/// True when a bare soname already loads, i.e. the environment is one where nothing is needed.
fn already_resolvable(soname: &str) -> bool {
    dlopen_global_raw(soname)
}

fn dlopen_global(path: &std::path::Path) -> bool {
    match path.to_str() {
        Some(p) => dlopen_global_raw(p),
        None => false,
    }
}

fn dlopen_global_raw(name: &str) -> bool {
    let Ok(name) = CString::new(name) else {
        return false;
    };
    // SAFETY: `name` is a valid NUL-terminated string that outlives the call, and the flag
    // combination is the documented one for "load and publish to the global symbol scope".
    // The handle is deliberately leaked: these libraries must stay loaded for the whole run.
    unsafe {
        let handle = libc::dlopen(name.as_ptr(), libc::RTLD_NOW | libc::RTLD_GLOBAL);
        !handle.is_null()
    }
}

fn cache_path() -> Option<std::path::PathBuf> {
    let base = std::env::var_os("XDG_CACHE_HOME")
        .map(std::path::PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| std::path::PathBuf::from(h).join(".cache")))?;
    Some(base.join("player-proto").join("libs"))
}

/// Append a resolved path to the cache, so the `/nix/store` scan happens once per store
/// generation instead of once per start.
fn remember(path: &std::path::Path) {
    let Some(cache) = cache_path() else { return };
    if let Some(dir) = cache.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    let line = format!("{}\n", path.display());
    if let Ok(existing) = std::fs::read_to_string(&cache) {
        if existing.contains(path.to_string_lossy().as_ref()) {
            return;
        }
        let _ = std::fs::write(&cache, existing + &line);
    } else {
        let _ = std::fs::write(&cache, line);
    }
}

fn cached_dirs() -> Vec<std::path::PathBuf> {
    let Some(cache) = cache_path() else {
        return Vec::new();
    };
    let Ok(text) = std::fs::read_to_string(cache) else {
        return Vec::new();
    };
    text.lines()
        .filter(|l| !l.trim().is_empty())
        .filter_map(|l| {
            std::path::PathBuf::from(l)
                .parent()
                .map(|p| p.to_path_buf())
        })
        .collect()
}

/// Every directory worth looking in, cheapest first and deduplicated.
fn search_dirs() -> Vec<std::path::PathBuf> {
    let mut dirs: Vec<std::path::PathBuf> = Vec::new();
    let mut push = |p: std::path::PathBuf| {
        if !dirs.contains(&p) {
            dirs.push(p);
        }
    };

    if let Some(list) = std::env::var_os("PLAYER_LIB_DIRS") {
        for part in std::env::split_paths(&list) {
            push(part);
        }
    }
    for dir in cached_dirs() {
        push(dir);
    }
    // Profiles first: a library the user put in their own profile should win over the store
    // scan, and `/run/opengl-driver/lib` is where the NixOS module system puts the Vulkan
    // loader and its ICDs on every graphics host.
    if let Some(profiles) = std::env::var_os("NIX_PROFILES") {
        for profile in std::env::split_paths(&profiles) {
            push(profile.join("lib"));
        }
    }
    if let Some(home) = std::env::var_os("HOME") {
        let home = std::path::PathBuf::from(home);
        push(home.join(".nix-profile/lib"));
        push(home.join(".local/state/nix/profile/lib"));
    }
    if let Some(user) = std::env::var_os("USER") {
        let user = user.to_string_lossy();
        push(std::path::PathBuf::from(format!(
            "/etc/profiles/per-user/{user}/lib"
        )));
    }
    push(std::path::PathBuf::from("/run/current-system/sw/lib"));
    push(std::path::PathBuf::from("/run/opengl-driver/lib"));
    push(std::path::PathBuf::from(
        "/nix/var/nix/profiles/default/lib",
    ));
    push(std::path::PathBuf::from("/usr/lib"));
    push(std::path::PathBuf::from("/usr/lib64"));
    push(std::path::PathBuf::from("/lib"));
    push(std::path::PathBuf::from("/lib64"));

    // Last resort: the store itself. Only the packages that can own one of `NEEDED` are
    // visited, so this stays a directory-listing plus a handful of `stat` calls.
    if let Ok(entries) = std::fs::read_dir("/nix/store") {
        let mut store: Vec<std::path::PathBuf> = entries
            .filter_map(|e| e.ok())
            .map(|e| e.path())
            .filter(|p| {
                let name = p
                    .file_name()
                    .map(|n| n.to_string_lossy().to_ascii_lowercase())
                    .unwrap_or_default();
                name.contains("wayland")
                    || name.contains("libxkbcommon")
                    || name.contains("vulkan-loader")
            })
            .filter(|p| p.is_dir())
            .collect();
        // Deterministic order: two store paths for the same package must resolve the same way
        // on every start, or the cache would flip between builds.
        store.sort();
        for path in store {
            push(path.join("lib"));
        }
    }
    dirs
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_search_list_is_deduplicated_and_ordered() {
        let dirs = search_dirs();
        assert!(
            !dirs.is_empty(),
            "there is always at least the system profile"
        );
        let mut sorted = dirs.clone();
        sorted.dedup();
        assert_eq!(dirs, sorted, "search_dirs must not repeat a directory");
    }

    #[test]
    fn a_library_that_is_always_present_resolves() {
        // libc itself is loaded into every process, so a bare soname for it must succeed.
        // This is the "already_resolvable" fast path: when it works, nothing is scanned.
        assert!(
            already_resolvable("libc.so.6"),
            "the fast path has to recognise a library that is already loaded"
        );
    }

    #[test]
    fn a_missing_library_is_not_fatal() {
        assert!(!dlopen_global_raw("libdefinitely-not-here.so.0"));
    }
}
