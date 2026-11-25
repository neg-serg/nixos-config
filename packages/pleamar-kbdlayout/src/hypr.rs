//! The Hyprland side: locating `hyprctl`, running the three queries the shell
//! ran, and turning failures into the shell's error text.
//!
//! The argv is identical to `kbd.sh` because the compositor is the external
//! contract: `hyprctl -j devices`, `hyprctl submap`,
//! `hyprctl switchxkblayout DEVICE DIRECTION`. Tests and the parity harness
//! substitute a fake executable through `PLEAMAR_HYPRCTL`.

use std::env;
use std::ffi::OsStr;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use std::process::{Command, Stdio};

use serde_json::Value;

use crate::caps;
use crate::sample;

pub const DEVICES_FAILED: &str = "hyprctl -j devices failed (is Hyprland running?)";
pub const DEVICES_NOT_JSON: &str = "hyprctl -j devices did not return JSON";

/// The compositor's query interface.
#[derive(Clone, Debug)]
pub struct Hyprctl {
    pub program: String,
}

/// `command -v`: a regular, executable file found on `PATH`, or an explicit
/// path that itself is executable. A directory named like the program is not a
/// command.
pub fn is_executable(program: &str) -> bool {
    is_executable_in(program, env::var_os("PATH").as_deref())
}

fn is_executable_in(program: &str, path: Option<&OsStr>) -> bool {
    if program.is_empty() {
        return false;
    }
    if program.contains('/') {
        return executable_file(Path::new(program));
    }
    match path {
        Some(path) => {
            env::split_paths(path).any(|directory| executable_file(&directory.join(program)))
        }
        None => false,
    }
}

fn executable_file(path: &Path) -> bool {
    fs::metadata(path)
        .map(|metadata| metadata.is_file() && metadata.permissions().mode() & 0o111 != 0)
        .unwrap_or(false)
}

impl Hyprctl {
    /// Query the devices, the submap and the LED state and render the `data`
    /// object. `Err` is the message of an error sample; the worker stays alive.
    pub fn build_status(&self, led_root: &Path) -> Result<String, String> {
        let output = Command::new(&self.program)
            .args(["-j", "devices"])
            .stderr(Stdio::null())
            .output();
        let stdout = match output {
            Ok(output) if output.status.success() => output.stdout,
            _ => return Err(DEVICES_FAILED.to_string()),
        };
        let text = String::from_utf8_lossy(&stdout);
        // `jq -e .`: invalid JSON fails, and `-e` also fails for `null` and
        // `false` (the only falsy JSON values).
        let devices: Value = match serde_json::from_str(text.as_ref()) {
            Ok(Value::Null) | Ok(Value::Bool(false)) | Err(_) => {
                return Err(DEVICES_NOT_JSON.to_string())
            }
            Ok(value) => value,
        };
        let submap = self.submap();
        let caps = caps::caps_locked(led_root);
        Ok(sample::render_data(&devices, &submap, caps))
    }

    /// `hyprctl submap` with `tr -d '\r\n'`, then the `default`/`reset`
    /// normalization. A failed query reports "" and does not fail the sample.
    fn submap(&self) -> String {
        let output = Command::new(&self.program)
            .arg("submap")
            .stderr(Stdio::null())
            .output();
        match output {
            Ok(output) if output.status.success() => {
                let text = String::from_utf8_lossy(&output.stdout);
                let cleaned: String = text
                    .chars()
                    .filter(|character| *character != '\r' && *character != '\n')
                    .collect();
                if cleaned == "default" || cleaned == "reset" {
                    String::new()
                } else {
                    cleaned
                }
            }
            _ => String::new(),
        }
    }

    /// `hyprctl switchxkblayout DEVICE DIRECTION`. On failure the message is
    /// the shell's: the last line of the combined output, after command
    /// substitution stripped the trailing newlines.
    pub fn switch_layout(&self, device: &str, direction: &str) -> Result<(), String> {
        let output = Command::new(&self.program)
            .arg("switchxkblayout")
            .arg(device)
            .arg(direction)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .output();
        let failed = |last_line: &str| {
            format!("hyprctl switchxkblayout {device} {direction} failed: {last_line}")
        };
        match output {
            Ok(output) if output.status.success() => Ok(()),
            Ok(output) => {
                // The shell merged stdout and stderr with `2>&1`; a separate
                // capture cannot preserve the interleaving, so the stream that
                // carried the diagnosis wins (stderr first, then stdout).
                let stderr = String::from_utf8_lossy(&output.stderr);
                let stdout = String::from_utf8_lossy(&output.stdout);
                let combined = if stderr.is_empty() { stdout } else { stderr };
                let trimmed = combined.trim_end_matches('\n');
                let last_line = trimmed.rsplit('\n').next().unwrap_or("");
                Err(failed(last_line))
            }
            Err(_) => Err(failed("")),
        }
    }
}
