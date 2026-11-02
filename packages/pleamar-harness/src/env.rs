//! Path lookup, the hermetic sandbox and `--soft`, shared by all three tools.

use std::env;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;

use crate::ctx::{Ctx, Halt};

/// The shell's `resolve_bin`: a value with a slash is used verbatim when it is
/// executable, a bare name is searched in `PATH` the way `command -v` did.
pub fn resolve_bin(value: &str) -> Option<String> {
    if value.is_empty() {
        return None;
    }
    if value.contains('/') {
        if super::repo::is_executable(Path::new(value)) {
            return Some(value.to_string());
        }
        return None;
    }
    let path = env::var_os("PATH")?;
    for directory in env::split_paths(&path) {
        let candidate = if directory.as_os_str().is_empty() {
            PathBuf::from(value)
        } else {
            directory.join(value)
        };
        if super::repo::is_executable(&candidate) {
            return Some(candidate.to_string_lossy().into_owned());
        }
    }
    None
}

/// `mktemp -d "${PLEAMAR_TMPDIR:-/tmp}/pleamar-<tool>.XXXXXX"`.
pub fn mktemp(tool: &str) -> Result<PathBuf, Halt> {
    let base = match env::var("PLEAMAR_TMPDIR") {
        Ok(value) if !value.is_empty() => value,
        _ => "/tmp".to_string(),
    };
    let template = format!("{base}/pleamar-{tool}.XXXXXX");
    let mut command = Command::new("mktemp");
    command.arg("-d").arg(&template);
    let output = command
        .output()
        .map_err(|error| Halt::Fail(format!("mktemp failed: {error}")))?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr)
            .trim_end()
            .to_string();
        return Err(Halt::Fail(if stderr.is_empty() {
            "mktemp failed".to_string()
        } else {
            stderr
        }));
    }
    let text = String::from_utf8_lossy(&output.stdout);
    let path = super::proc::trim_newlines(&text).to_string();
    if path.is_empty() {
        return Err(Halt::Fail("mktemp returned an empty directory".to_string()));
    }
    Ok(PathBuf::from(path))
}

/// The directories the shell created under the sandbox root, and the 0700 on
/// the runtime dir.
pub fn create_sandbox(temp: &Path) -> std::io::Result<()> {
    for name in [
        "home",
        "config",
        "data",
        "cache",
        "state",
        "run",
        "pleamar-config",
    ] {
        fs::create_dir_all(temp.join(name))?;
    }
    fs::set_permissions(temp.join("run"), fs::Permissions::from_mode(0o700))
}

/// `--soft`: lavapipe when the ICD exists, never overriding a value already in
/// the environment.
pub fn apply_soft(ctx: &Ctx, soft: bool) {
    if !soft {
        return;
    }
    if let Ok(value) = env::var("VK_ICD_FILENAMES") {
        if !value.is_empty() {
            ctx.say(format!(
                "--soft: VK_ICD_FILENAMES is already set, keeping it ({value})"
            ));
            return;
        }
    }
    let icd = match env::var("PLEAMAR_SOFT_ICD") {
        Ok(value) if !value.is_empty() => value,
        _ => "/run/opengl-driver/share/vulkan/icd.d/lvp_icd.x86_64.json".to_string(),
    };
    if Path::new(&icd).is_file() {
        env::set_var("VK_ICD_FILENAMES", &icd);
        ctx.say(format!("--soft: VK_ICD_FILENAMES={icd} (Mesa lavapipe)"));
    } else {
        ctx.warn(format!(
            "--soft: {icd} does not exist; continuing without software Vulkan"
        ));
    }
}

/// Export the hermetic HOME/XDG environment and clear the live display.
pub fn enter_sandbox(temp: &Path) {
    env::set_var("HOME", temp.join("home"));
    env::set_var("XDG_CONFIG_HOME", temp.join("config"));
    env::set_var("XDG_DATA_HOME", temp.join("data"));
    env::set_var("XDG_CACHE_HOME", temp.join("cache"));
    env::set_var("XDG_STATE_HOME", temp.join("state"));
    env::set_var("XDG_RUNTIME_DIR", temp.join("run"));
    env::set_var("PLEAMAR_CONFIG", temp.join("pleamar-config"));
    env::remove_var("WAYLAND_DISPLAY");
    env::remove_var("WAYLAND_SOCKET");
}

/// `date +FORMAT`, with the trailing newline stripped as command substitution
/// did. The harness keeps `date` external so tests can pin the clock.
pub fn date(format: &str) -> String {
    let value = super::proc::stdout_silent("date", &[format]).unwrap_or_default();
    super::proc::trim_newlines(&value).to_string()
}

/// `getconf CLK_TCK`, falling back to 100 like the scripts.
pub fn clock_ticks() -> String {
    let value = super::proc::stdout_silent("getconf", &["CLK_TCK"]).unwrap_or_default();
    let value = super::proc::trim_newlines(&value).to_string();
    if value.is_empty() {
        "100".to_string()
    } else {
        value
    }
}

/// `id -u`, used only when `XDG_RUNTIME_DIR` is unset and `--systemd` needs the
/// real user manager.
pub fn user_id() -> String {
    let value = super::proc::stdout_silent("id", &["-u"]).unwrap_or_default();
    super::proc::trim_newlines(&value).to_string()
}
