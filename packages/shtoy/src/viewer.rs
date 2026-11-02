//! Locating and running `esshader`.
//!
//! The shell used `command -v esshader` (`require`) and then
//! `esshader -f -s FILE [-l] [-k N] [-0 FILE ...]` with inherited stdio,
//! waiting for it and exiting with its status. A signal-death became the usual
//! shell status 128+signal, which `wait` returns and `set -e` propagates.

use std::ffi::OsString;
use std::io::ErrorKind;
use std::os::unix::fs::PermissionsExt;
use std::os::unix::process::ExitStatusExt;
use std::path::{Path, PathBuf};
use std::process::Command;

use crate::env::Env;
use crate::Die;
use crate::PROG;

/// `command -v`: first executable regular file on `PATH`.
pub fn find_program(name: &str, environment: &Env) -> Option<PathBuf> {
    let path = environment.get("PATH")?;
    for directory in std::env::split_paths(path) {
        let candidate = directory.join(name);
        if is_executable(&candidate) {
            return Some(candidate);
        }
    }
    None
}

fn is_executable(path: &Path) -> bool {
    match std::fs::metadata(path) {
        Ok(metadata) => metadata.is_file() && metadata.permissions().mode() & 0o111 != 0,
        Err(_) => false,
    }
}

/// Spawn the viewer with inherited stdio and return the status `main` should
/// use: the exit code, or 128+signal when it was killed. A spawn failure after
/// the PATH lookup is reported like the shell's exec failure and mapped to the
/// conventional 127 (not found) / 126 (not executable).
pub fn run(program: &Path, arguments: &[OsString]) -> Result<i32, Die> {
    match Command::new(program).args(arguments).status() {
        Ok(status) => {
            if let Some(code) = status.code() {
                Ok(code)
            } else if let Some(signal) = status.signal() {
                Ok(128 + signal)
            } else {
                Ok(1)
            }
        }
        Err(error) => {
            let code = if error.kind() == ErrorKind::NotFound {
                127
            } else {
                126
            };
            eprintln!("{PROG}: {}: {error}", program.display());
            Ok(code)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::find_program;
    use crate::env::Env;
    use crate::test_support::TempDir;
    use std::os::unix::fs::PermissionsExt;

    #[test]
    fn finds_an_executable_on_path_and_ignores_non_executables() {
        let root = TempDir::new("viewer-which");
        let program = root.path().join("esshader");
        std::fs::write(&program, b"#!/bin/sh\nexit 0\n").unwrap();
        let environment = Env::from_vars([("PATH", root.path().to_string_lossy().into_owned())]);
        assert_eq!(find_program("esshader", &environment), None);

        let mut permissions = std::fs::metadata(&program).unwrap().permissions();
        permissions.set_mode(0o755);
        std::fs::set_permissions(&program, permissions).unwrap();
        assert_eq!(find_program("esshader", &environment), Some(program));
    }

    #[test]
    fn missing_path_means_not_found() {
        let environment = Env::from_vars(Vec::<(&str, &str)>::new());
        assert_eq!(find_program("esshader", &environment), None);
    }
}
