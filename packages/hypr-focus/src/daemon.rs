//! Hyprland focus history daemon.
//!
//! Listens to Hyprland IPC events via `hyprland::event_listener::EventListener`,
//! tracks window focus history (LRU, max 20), and writes the previous window
//! address to a state file for the `switch` command to consume.
//!
//! Ported from the Python `hypr-focus-hist` daemon.

use hyprland::event_listener::EventListener;
use hyprland::shared::Address;
use std::io::Write;
use std::sync::{Arc, Mutex};

// ---------------------------------------------------------------------------
// Logging
// ---------------------------------------------------------------------------

/// Append a timestamped line to `/tmp/hypr-focus-hist.log`.
fn log_msg(msg: &str) {
    let path = "/tmp/hypr-focus-hist.log";
    let Ok(mut file) = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
    else {
        return;
    };
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default();
    let total_secs = now.as_secs() % 86400;
    let ts = format!(
        "{:02}:{:02}:{:02}.{:03}",
        total_secs / 3600,
        (total_secs % 3600) / 60,
        total_secs % 60,
        now.subsec_millis()
    );
    let _ = writeln!(file, "[{ts}] {msg}");
}

// ---------------------------------------------------------------------------
// Desktop notifications
// ---------------------------------------------------------------------------

/// Show a desktop notification via `notify-send`.
fn notify(msg: &str) {
    let _ = std::process::Command::new("notify-send")
        .args(["-a", "hypr-focus", msg])
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status();
}

// ---------------------------------------------------------------------------
// State file path & I/O
// ---------------------------------------------------------------------------

/// Compute the state file path:
/// `$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/focus-history`
fn state_path() -> String {
    let sig = std::env::var("HYPRLAND_INSTANCE_SIGNATURE").unwrap_or_default();
    let runtime = std::env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| {
        // Fallback: parse UID from /proc/self/status
        let uid = std::fs::read_to_string("/proc/self/status")
            .ok()
            .and_then(|s| {
                s.lines()
                    .find(|l| l.starts_with("Uid:"))
                    .and_then(|l| l.split_whitespace().nth(1))
                    .and_then(|s| s.parse::<u32>().ok())
            })
            .unwrap_or(1000);
        format!("/run/user/{uid}")
    });
    format!("{runtime}/hypr/{sig}/focus-history")
}

/// Write an address to the state file (plain text).
fn write_state(path: &str, addr: &str) {
    if let Err(e) = std::fs::write(path, addr) {
        log_msg(&format!("Failed to write state: {e}"));
    }
}

/// Remove the state file.
fn remove_state(path: &str) {
    let _ = std::fs::remove_file(path);
}

/// Format an `Address` with a `0x` prefix.
///
/// The `hyprland` crate stores addresses without the `0x` prefix internally;
/// the state file and `hyprctl dispatch focuswindow address:…` expect it.
fn fmt_addr(addr: &Address) -> String {
    let s = addr.to_string();
    if s.starts_with("0x") || s.starts_with("0X") {
        s
    } else {
        format!("0x{s}")
    }
}

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

/// Build and return the `activewindow` handler.
///
/// Tracks the focused window address, maintains a most-recently-used order,
/// and writes the *previous* address to the state file for `switch`.
fn make_active_window_handler(
    history: Arc<Mutex<Vec<String>>>,
    state: String,
) -> impl Fn(Option<hyprland::event_listener::WindowEventData>) + 'static {
    move |data| {
        let Some(ref wdata) = data else { return };
        let addr = fmt_addr(&wdata.address);

        let mut hist = match history.lock() {
            Ok(h) => h,
            Err(e) => {
                log_msg(&format!("lock error: {e}"));
                return;
            }
        };

        // Skip consecutive duplicates (same window focused twice in a row).
        if hist.last().map(|s| s.as_str()) == Some(&addr) {
            return;
        }

        log_msg(&format!(
            "activewindow addr={addr} history_len={}",
            hist.len()
        ));

        // LRU reorder: remove existing entry so it moves to the end.
        if let Some(pos) = hist.iter().position(|x| x == &addr) {
            hist.remove(pos);
        }
        hist.push(addr);

        // Trim to max 20 entries (keep the most recent ones).
        if hist.len() > 20 {
            let excess = hist.len() - 20;
            hist.drain(0..excess);
        }

        // Write the previous window address (the entry before the latest).
        if hist.len() >= 2 {
            let prev = hist[hist.len() - 2].clone();
            log_msg(&format!("writing state: {prev}"));
            write_state(&state, &prev);
        }
    }
}

/// Build and return the `closewindow` handler.
///
/// Removes the closed window from history and updates the state file.
fn make_window_closed_handler(
    history: Arc<Mutex<Vec<String>>>,
    state: String,
) -> impl Fn(Address) + 'static {
    move |addr| {
        let addr_str = fmt_addr(&addr);
        log_msg(&format!("closewindow addr={addr_str}"));

        let mut hist = match history.lock() {
            Ok(h) => h,
            Err(e) => {
                log_msg(&format!("lock error: {e}"));
                return;
            }
        };

        // Remove all occurrences of the closed address.
        hist.retain(|h| h != &addr_str);

        // Update state file:
        // - 2+ remaining → write the second-to-last
        // - 1 remaining  → write the only entry
        // - empty        → remove state file
        if hist.len() >= 2 {
            write_state(&state, &hist[hist.len() - 2]);
        } else if !hist.is_empty() {
            write_state(&state, &hist[0]);
        } else {
            remove_state(&state);
        }
    }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Start the focus tracking daemon.
///
/// Creates an `EventListener`, registers handlers for window focus changes
/// and window closures, and enters a blocking event loop. On connection
/// failure it sleeps for 2 seconds and reconnects automatically.
pub fn run() -> hyprland::Result<()> {
    log_msg("daemon starting");

    let state = state_path();
    log_msg(&format!("state path: {state}"));

    // Ensure the parent directory exists.
    if let Some(parent) = std::path::Path::new(&state).parent() {
        let _ = std::fs::create_dir_all(parent);
    }

    loop {
        let mut listener = EventListener::new();

        let history: Arc<Mutex<Vec<String>>> = Arc::new(Mutex::new(Vec::new()));

        listener.add_active_window_changed_handler(make_active_window_handler(
            Arc::clone(&history),
            state.clone(),
        ));

        listener.add_window_closed_handler(make_window_closed_handler(
            history,
            state.clone(),
        ));

        log_msg("starting event listener");
        if let Err(e) = listener.start_listener() {
            log_msg(&format!("connection lost: {e}"));
            notify(&format!("Hyprland connection lost: {e}"));
            std::thread::sleep(std::time::Duration::from_secs(2));
            continue;
        }

        break;
    }

    Ok(())
}
