//! The Hyprland event stream.
//!
//! `kbd.sh` asked `socat` to read `.socket2.sock` into a FIFO that the worker
//! held open read-write, because bash cannot poll a socket and stdin at the
//! same time. The Rust port keeps the same external contract: the socket is
//! found the shell's way (`--socket`, `$HYPRLAND_INSTANCE_SIGNATURE`,
//! `$XDG_RUNTIME_DIR/hypr/*`, `/tmp/hypr/*`), `socat` is spawned with the same
//! argv, and a FIFO is still the transfer channel, so a fake `socat` sees
//! exactly what the shell's did. A reader thread drains the FIFO into a
//! channel; the event loop drains the channel.
//!
//! Every failure degrades to polling `hyprctl`: one error sample names the
//! reason, and the heartbeat keeps the scene alive.

use std::env;
use std::fs::{self, File, OpenOptions};
use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::mpsc::{self, Receiver};
use std::thread;

/// Event names that mean the layout/submap may have moved. The compositor
/// used several spellings across releases; the shell matched all of them.
const EVENT_NAMES: &[&str] = &[
    "activelayout",
    "activelayoutv2",
    "keyboard-layout",
    "keyboard_layout",
    "keyboard",
    "submap",
    "submapv2",
];

pub const SOCKET_UNAVAILABLE: &str = "hyprland event socket not available; polling hyprctl";
pub const SOCAT_MISSING: &str = "socat not found; polling hyprctl";
pub const PIPE_FAILED: &str = "cannot create the event pipe; polling hyprctl";
pub const SOCKET_CLOSED: &str = "hyprland event socket closed; polling hyprctl";

/// What one drain pass produced.
pub enum Drain {
    /// Nothing queued, or the stream is already off.
    Idle,
    /// `socat` ended; the caller emits the fallback error sample.
    Closed,
    /// Complete lines read since the previous pass.
    Events(Vec<String>),
}

/// `line` names one of the events the worker reacts to (`${line%%>>*}`).
pub fn matches_event(line: &str) -> bool {
    let name = match line.split_once(">>") {
        Some((name, _)) => name,
        None => line,
    };
    EVENT_NAMES.contains(&name)
}

/// The live event stream, or the memory of why there is none.
pub struct EventSocket {
    override_path: String,
    socat: String,
    child: Option<Child>,
    events: Option<Receiver<String>>,
    active: bool,
}

impl EventSocket {
    pub fn new(override_path: String, socat: String) -> Self {
        Self {
            override_path,
            socat,
            child: None,
            events: None,
            active: false,
        }
    }

    /// Start the stream. `Some(message)` is the shell's fallback error sample
    /// text; the worker continues on the heartbeat path either way.
    pub fn start(&mut self) -> Option<&'static str> {
        if self.active {
            return None;
        }
        let socket = match resolve_socket(&self.override_path) {
            Some(socket) => socket,
            None => return Some(SOCKET_UNAVAILABLE),
        };
        if !crate::hypr::is_executable(&self.socat) {
            return Some(SOCAT_MISSING);
        }

        // `${TMPDIR:-/tmp}/pleamar-kbd.$$.fifo`, created by the same external
        // `mkfifo` the shell called.
        let fifo = env::temp_dir().join(format!("pleamar-kbd.{}.fifo", std::process::id()));
        let created = Command::new("mkfifo")
            .arg(&fifo)
            .stderr(Stdio::null())
            .status();
        if !matches!(created, Ok(status) if status.success()) {
            return Some(PIPE_FAILED);
        }
        // Open read-write before `socat` starts: opening a FIFO for writing
        // blocks until a reader exists, and an O_RDWR reader never reports
        // EOF just because the writer side is between opens.
        let reader = match OpenOptions::new().read(true).write(true).open(&fifo) {
            Ok(file) => file,
            Err(_) => {
                let _ = fs::remove_file(&fifo);
                return Some(PIPE_FAILED);
            }
        };
        let writer = match reader.try_clone() {
            Ok(file) => file,
            Err(_) => {
                let _ = fs::remove_file(&fifo);
                return Some(PIPE_FAILED);
            }
        };
        let child = Command::new(&self.socat)
            .arg("-u")
            .arg(format!("UNIX-CONNECT:{}", socket.display()))
            .arg("-")
            .stdout(Stdio::from(writer))
            .stderr(Stdio::null())
            .spawn();
        let child = match child {
            Ok(child) => child,
            Err(_) => {
                let _ = fs::remove_file(&fifo);
                return Some(PIPE_FAILED);
            }
        };
        // The descriptor is what keeps the pipe alive now, not the name.
        let _ = fs::remove_file(&fifo);

        let (sender, receiver) = mpsc::channel();
        thread::spawn(move || read_lines(reader, sender));

        self.child = Some(child);
        self.events = Some(receiver);
        self.active = true;
        None
    }

    /// Read whatever the socket queued. The child is checked before the queued
    /// lines, exactly like the shell's `kill -0` check, so a dead `socat` is
    /// reported once and the heartbeat takes over.
    pub fn drain(&mut self) -> Drain {
        if !self.active {
            return Drain::Idle;
        }
        let exited = match self.child.as_mut() {
            Some(child) => match child.try_wait() {
                Ok(Some(_)) => true,
                Ok(None) => false,
                Err(_) => true,
            },
            None => true,
        };
        if exited {
            self.child = None;
            self.events = None;
            self.active = false;
            return Drain::Closed;
        }
        let mut lines = Vec::new();
        if let Some(receiver) = &self.events {
            while let Ok(line) = receiver.try_recv() {
                lines.push(line);
            }
        }
        if lines.is_empty() {
            Drain::Idle
        } else {
            Drain::Events(lines)
        }
    }

    /// Take the `socat` child down and leave no FIFO behind; safe to call more
    /// than once, and also runs from `Drop`.
    pub fn cleanup(&mut self) {
        if let Some(mut child) = self.child.take() {
            let _ = child.kill();
            let _ = child.wait();
        }
        self.events = None;
        self.active = false;
    }
}

impl Drop for EventSocket {
    fn drop(&mut self) {
        self.cleanup();
    }
}

fn read_lines(reader: File, sender: mpsc::Sender<String>) {
    let mut reader = BufReader::new(reader);
    let mut buffer = Vec::new();
    loop {
        buffer.clear();
        match reader.read_until(b'\n', &mut buffer) {
            Ok(0) => break,
            Ok(_) => {
                if buffer.last() == Some(&b'\n') {
                    buffer.pop();
                }
                let line = String::from_utf8_lossy(&buffer).into_owned();
                if sender.send(line).is_err() {
                    break;
                }
            }
            Err(error) if error.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(_) => break,
        }
    }
}

fn is_socket(path: &Path) -> bool {
    use std::os::unix::fs::FileTypeExt;
    fs::metadata(path)
        .map(|metadata| metadata.file_type().is_socket())
        .unwrap_or(false)
}

/// The shell's `resolve_socket`: an explicit override wins (and fails closed),
/// the instance signature names two fixed candidates, and without a signature
/// the first `hypr/*/.socket2.sock` in the runtime dir or `/tmp` is used.
fn resolve_socket(override_path: &str) -> Option<PathBuf> {
    if !override_path.is_empty() {
        let path = PathBuf::from(override_path);
        return if is_socket(&path) { Some(path) } else { None };
    }

    let runtime = runtime_dir();
    if let Some(signature) = env::var_os("HYPRLAND_INSTANCE_SIGNATURE") {
        if !signature.is_empty() {
            let signature = signature.to_string_lossy();
            for base in [runtime.join("hypr"), PathBuf::from("/tmp/hypr")] {
                let candidate = base.join(signature.as_ref()).join(".socket2.sock");
                if is_socket(&candidate) {
                    return Some(candidate);
                }
            }
            return None;
        }
    }

    for base in [runtime.join("hypr"), PathBuf::from("/tmp/hypr")] {
        if let Some(candidate) = first_socket(&base) {
            return Some(candidate);
        }
    }
    None
}

fn runtime_dir() -> PathBuf {
    match env::var_os("XDG_RUNTIME_DIR") {
        Some(value) if !value.is_empty() => PathBuf::from(value),
        _ => PathBuf::from(format!("/run/user/{}", current_uid())),
    }
}

fn current_uid() -> String {
    // The shell interpolated `$(id -u)`; `std` has no uid accessor and the
    // worker already talks to external programs (`hyprctl`, `socat`).
    Command::new("id")
        .arg("-u")
        .output()
        .ok()
        .filter(|output| output.status.success())
        .map(|output| String::from_utf8_lossy(&output.stdout).trim().to_string())
        .unwrap_or_default()
}

/// `hypr/*/.socket2.sock`, sorted like the shell's glob expansion.
fn first_socket(base: &Path) -> Option<PathBuf> {
    let mut directories: Vec<PathBuf> = fs::read_dir(base)
        .ok()?
        .flatten()
        .map(|entry| entry.path())
        .collect();
    directories.sort();
    for directory in directories {
        let candidate = directory.join(".socket2.sock");
        if is_socket(&candidate) {
            return Some(candidate);
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn event_names_match_the_shell_case() {
        assert!(matches_event("activelayout>>us,English"));
        assert!(matches_event("activelayoutv2>>0,us"));
        assert!(matches_event("keyboard-layout>>us"));
        assert!(matches_event("keyboard_layout>>us"));
        assert!(matches_event("keyboard>>us"));
        assert!(matches_event("submap>>resize"));
        assert!(matches_event("submapv2>>resize"));
        assert!(matches_event("activelayout"));
        assert!(!matches_event("windowtitle>>x"));
        assert!(!matches_event("activelayoutx>>us"));
        assert!(!matches_event(""));
    }

    #[test]
    fn missing_override_is_unavailable() {
        // An empty override means "discover"; a non-empty one that is not a
        // socket fails closed instead of falling through to discovery.
        assert_eq!(resolve_socket("/nonexistent/pleamar.sock"), None);
    }

    #[test]
    fn a_bound_unix_socket_is_accepted_as_an_override() {
        use std::os::unix::net::UnixListener;
        let directory = std::env::temp_dir().join(format!(
            "pleamar-kbdlayout-socket-{}-{}",
            std::process::id(),
            crate::protocol::now_ms()
        ));
        fs::create_dir_all(&directory).expect("directory");
        let path = directory.join(".socket2.sock");
        let listener = UnixListener::bind(&path).expect("bind");
        assert!(resolve_socket(&path.to_string_lossy()).is_some());
        drop(listener);
        let _ = fs::remove_dir_all(&directory);
    }
}
