//! Finding the pleamar tree.
//!
//! The shell scripts derived `PROJECT_DIR` from `BASH_SOURCE`, which is not
//! available to a binary in the Nix store. The port reads `PLEAMAR_ROOT`
//! (the pleamar tree, or the repository root containing `files/pleamar`) and
//! otherwise walks up from the current directory until a `flake.nix`, then
//! uses `<flake root>/files/pleamar`. This is the only structural deviation.

use std::env;
use std::fs;
use std::path::{Path, PathBuf};

const HINT: &str = "set PLEAMAR_ROOT to the pleamar tree (the directory holding shells/ and tests/) or run from inside the repository";

/// The project directory the scripts called `PROJECT_DIR` (`files/pleamar`).
pub fn project_root() -> Result<PathBuf, String> {
    if let Some(value) = env::var_os("PLEAMAR_ROOT") {
        if !value.is_empty() {
            let mut path = PathBuf::from(value);
            if !path.is_absolute() {
                path = env::current_dir()
                    .map_err(|error| format!("cannot read the current directory: {error}"))?
                    .join(path);
            }
            if path.join("shells").is_dir() {
                return Ok(path);
            }
            let nested = path.join("files/pleamar");
            if nested.join("shells").is_dir() {
                return Ok(nested);
            }
            return Err(format!(
                "PLEAMAR_ROOT='{}' does not look like the pleamar tree (no shells/); {HINT}",
                path.display()
            ));
        }
    }

    let mut directory = env::current_dir()
        .map_err(|error| format!("cannot read the current directory: {error}"))?;
    loop {
        if directory.join("flake.nix").is_file() {
            let project = directory.join("files/pleamar");
            if project.join("shells").is_dir() {
                return Ok(project);
            }
            return Err(format!(
                "found the flake at {} but {} does not exist; {HINT}",
                directory.join("flake.nix").display(),
                project.display()
            ));
        }
        if !directory.pop() {
            break;
        }
    }
    Err(format!(
        "cannot locate the pleamar tree from {}; {HINT}",
        env::current_dir()
            .map(|path| path.display().to_string())
            .unwrap_or_else(|_| "?".to_string())
    ))
}

/// True when `path` is a regular file that can be executed.
pub fn is_executable(path: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    match fs::metadata(path) {
        Ok(metadata) => metadata.is_file() && metadata.permissions().mode() & 0o111 != 0,
        Err(_) => false,
    }
}
