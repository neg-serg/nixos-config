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

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::sync::Mutex;
    use std::time::{SystemTime, UNIX_EPOCH};

    /// A freshly written executable must not be handed to `exec` while
    /// another test thread is between `fork` and `exec`: the forked child
    /// temporarily holds a write descriptor to it and Linux answers ETXTBSY.
    /// Serializing the fake-compositor tests removes the window.
    static EXCLUSIVE: Mutex<()> = Mutex::new(());

    fn exclusive() -> std::sync::MutexGuard<'static, ()> {
        EXCLUSIVE.lock().unwrap_or_else(|error| error.into_inner())
    }

    struct TempDir(PathBuf);

    impl TempDir {
        fn new(label: &str) -> Self {
            static SEQUENCE: AtomicU64 = AtomicU64::new(0);
            let nanos = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map(|duration| duration.as_nanos())
                .unwrap_or(0);
            let path = std::env::temp_dir().join(format!(
                "pleamar-kbdlayout-hypr-{label}-{}-{nanos}-{}",
                std::process::id(),
                SEQUENCE.fetch_add(1, Ordering::Relaxed)
            ));
            fs::create_dir_all(&path).expect("test directory");
            Self(path)
        }

        fn path(&self) -> &Path {
            &self.0
        }
    }

    impl Drop for TempDir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    #[cfg(unix)]
    fn write_script(directory: &Path, name: &str, body: &str) -> PathBuf {
        let path = directory.join(name);
        fs::write(&path, body).expect("script");
        let mut permissions = fs::metadata(&path).expect("metadata").permissions();
        permissions.set_mode(0o755);
        fs::set_permissions(&path, permissions).expect("chmod");
        path
    }

    const DEVICES: &str = r#"{"keyboards":[{"name":"kbd-main","main":true,"layout":"us,ru","active_layout_index":1,"active_keymap":"Russian"}]}"#;
    const EXPECTED: &str = concat!(
        r#"{"device":"kbd-main","main":true,"index":1,"keymap":"Russian","code":"ru","#,
        r#""layouts":["us","ru"],"submap":"","caps":false,"#,
        r#""keyboards":[{"name":"kbd-main","main":true}]}"#
    );

    /// A fake hyprctl whose `-j devices` answer is `devices`, whose `submap`
    /// answer is `submap`, and whose switching records argv into `$1.log`.
    fn fake(directory: &Path, devices: &str, submap: &str, switch_status: i32) -> Hyprctl {
        let log = directory.join("argv.log");
        let script = format!(
            "#!/bin/sh\n\
             case \"$1\" in\n\
               -j) cat <<'JSON'\n{devices}\nJSON\n;;\n\
               submap) printf '%s\\n' '{submap}' ;;\n\
               switchxkblayout) printf '%s %s\\n' \"$2\" \"$3\" >> '{}'; exit {switch_status} ;;\n\
             esac\n",
            log.display()
        );
        let path = write_script(directory, "hyprctl", &script);
        Hyprctl {
            program: path.to_string_lossy().into_owned(),
        }
    }

    #[test]
    fn builds_the_reference_data_object() {
        let _guard = exclusive();
        let directory = TempDir::new("status");
        let hyprctl = fake(directory.path(), DEVICES, "default", 0);
        let leds = directory.path().join("leds");
        assert_eq!(hyprctl.build_status(&leds).expect("status"), EXPECTED);
    }

    #[test]
    fn default_and_reset_submaps_become_empty() {
        let _guard = exclusive();
        let directory = TempDir::new("submap-default");
        let hyprctl = fake(directory.path(), DEVICES, "default", 0);
        let leds = directory.path().join("leds");
        assert!(hyprctl
            .build_status(&leds)
            .expect("status")
            .contains(r#""submap":"""#));

        let directory = TempDir::new("submap-reset");
        let hyprctl = fake(directory.path(), DEVICES, "reset", 0);
        let leds = directory.path().join("leds");
        assert!(hyprctl
            .build_status(&leds)
            .expect("status")
            .contains(r#""submap":"""#));

        let directory = TempDir::new("submap-other");
        let hyprctl = fake(directory.path(), DEVICES, "resize", 0);
        let leds = directory.path().join("leds");
        assert!(hyprctl
            .build_status(&leds)
            .expect("status")
            .contains(r#""submap":"resize""#));
    }

    #[test]
    fn devices_failure_is_the_shell_message() {
        let _guard = exclusive();
        let directory = TempDir::new("devices-fail");
        let path = write_script(directory.path(), "hyprctl", "#!/bin/sh\nexit 1\n");
        let hyprctl = Hyprctl {
            program: path.to_string_lossy().into_owned(),
        };
        assert_eq!(
            hyprctl.build_status(&directory.path().join("leds")),
            Err(DEVICES_FAILED.to_string())
        );
    }

    #[test]
    fn invalid_devices_json_is_the_shell_message() {
        let _guard = exclusive();
        for payload in ["", "not json", "null", "false"] {
            let directory = TempDir::new("devices-json");
            let script = format!("#!/bin/sh\nprintf '%s\\n' '{payload}'\n");
            // `printf '%s\n' 'null'` and friends are valid shell; an empty
            // payload still prints one newline, which jq rejected as well.
            let path = write_script(directory.path(), "hyprctl", &script);
            let hyprctl = Hyprctl {
                program: path.to_string_lossy().into_owned(),
            };
            assert_eq!(
                hyprctl.build_status(&directory.path().join("leds")),
                Err(DEVICES_NOT_JSON.to_string()),
                "payload {payload:?}"
            );
        }
    }

    #[test]
    fn switching_records_the_same_argv_and_succeeds() {
        let _guard = exclusive();
        let directory = TempDir::new("switch");
        let hyprctl = fake(directory.path(), DEVICES, "default", 0);
        hyprctl
            .switch_layout("kbd-main", "next")
            .expect("switch succeeds");
        let log = fs::read_to_string(directory.path().join("argv.log")).expect("argv log");
        assert_eq!(log, "kbd-main next\n");
    }

    #[test]
    fn switching_failure_uses_the_last_output_line() {
        let _guard = exclusive();
        let directory = TempDir::new("switch-fail");
        let script = "#!/bin/sh\nprintf 'line one\\nsecond line\\n'\nexit 7\n";
        let path = write_script(directory.path(), "hyprctl", script);
        let hyprctl = Hyprctl {
            program: path.to_string_lossy().into_owned(),
        };
        assert_eq!(
            hyprctl.switch_layout("current", "next"),
            Err("hyprctl switchxkblayout current next failed: second line".to_string())
        );
    }

    #[test]
    fn switching_failure_without_output_keeps_the_empty_tail() {
        let _guard = exclusive();
        let directory = TempDir::new("switch-empty");
        let script = "#!/bin/sh\nexit 1\n";
        let path = write_script(directory.path(), "hyprctl", script);
        let hyprctl = Hyprctl {
            program: path.to_string_lossy().into_owned(),
        };
        assert_eq!(
            hyprctl.switch_layout("k", "prev"),
            Err("hyprctl switchxkblayout k prev failed: ".to_string())
        );
    }

    #[test]
    fn executable_lookup_accepts_files_and_rejects_plain_names() {
        let _guard = exclusive();
        let directory = TempDir::new("which");
        let script = write_script(directory.path(), "hyprctl", "#!/bin/sh\nexit 0\n");
        assert!(is_executable(&script.to_string_lossy()));
        let plain = directory.path().join("plain");
        fs::write(&plain, "text").expect("file");
        assert!(!is_executable(&plain.to_string_lossy()));
        assert!(!is_executable(""));
        assert!(!is_executable("pleamar-kbdlayout-no-such-program"));

        let path = OsStr::new(directory.path().as_os_str());
        assert!(is_executable_in("hyprctl", Some(path)));
        assert!(!is_executable_in(
            "pleamar-kbdlayout-no-such-program",
            Some(path)
        ));
        assert!(!is_executable_in("hyprctl", None));
    }
}
