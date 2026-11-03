//! Rust port of `packages/local-bin/bin/screenrec`.
//!
//! Toggles a wf-recorder capture. `date`, `slurp`, `hyprctl`, `wf-recorder`,
//! `sleep` and `notify-send` stay subprocesses with the original argv; the
//! pidfile handling, the `/proc/<pid>/comm` ownership check, the output/region
//! matching and the geometry arithmetic are native. SIGINT delivery and the
//! liveness probe go through `nix` because std can only kill children it still
//! owns (the recorder of a previous invocation is not one of them).

#![forbid(unsafe_code)]

use std::ffi::OsStr;
use std::os::unix::ffi::OsStrExt;
use std::path::Path;
use std::process::{Command, Stdio};

use nix::sys::signal::{kill, Signal};
use nix::unistd::Pid;

use local_bin_desktop::env;
use local_bin_desktop::json::Json;
use local_bin_desktop::proc::{Cmd, Sink};
use local_bin_desktop::text;

fn main() {
    let mut arguments = std::env::args_os();
    let argv0 = arguments.next().unwrap_or_default();
    let program = env::invocation_name(&argv0);
    let mode = arguments
        .next()
        .map(|value| value.as_bytes().to_vec())
        .unwrap_or_else(|| b"screen".to_vec());

    // The original creates the recordings directory before the toggle check.
    let mut directory = env::var_or_empty("HOME");
    directory.extend_from_slice(b"/vid/recordings");
    if std::fs::create_dir_all(OsStr::from_bytes(&directory)).is_err() {
        std::process::exit(1);
    }

    if is_recording(&program) {
        stop_recording(&program);
    } else {
        start_recording(&program, &mode);
    }
}

fn pidfile() -> Vec<u8> {
    let mut path = b"/tmp/wf-recorder-".to_vec();
    path.extend_from_slice(&env::var_or_empty("USER"));
    path.extend_from_slice(b".pid");
    path
}

/// `is_recording`: the pidfile names a live process whose comm is `wf-recorder`
/// (a reused PID must not make the toggle signal an unrelated process).
fn is_recording(_program: &[u8]) -> bool {
    let path = pidfile();
    let path = Path::new(OsStr::from_bytes(&path));
    if !path.is_file() {
        return false;
    }
    let pid = match std::fs::read(path) {
        Ok(contents) => text::strip_trailing_newlines(&contents).to_vec(),
        Err(_) => return false,
    };
    if pid.is_empty() {
        return false;
    }
    let mut comm = b"/proc/".to_vec();
    comm.extend_from_slice(&pid);
    comm.extend_from_slice(b"/comm");
    match std::fs::read(OsStr::from_bytes(&comm)) {
        Ok(contents) => text::strip_trailing_newlines(&contents) == b"wf-recorder",
        Err(_) => false,
    }
}

fn stop_recording(program: &[u8]) {
    let path = pidfile();
    if is_recording(program) {
        let pid = std::fs::read(OsStr::from_bytes(&path))
            .map(|contents| text::strip_trailing_newlines(&contents).to_vec())
            .unwrap_or_default();
        let numeric = std::str::from_utf8(&pid)
            .ok()
            .and_then(|text| text.trim().parse::<i32>().ok());
        if let Some(pid) = numeric {
            // wf-recorder finalizes the mp4 on SIGINT.
            let _ = kill(Pid::from_raw(pid), Signal::SIGINT);
        }
        let mut waited = 0;
        while numeric
            .map(|pid| kill(Pid::from_raw(pid), None).is_ok())
            .unwrap_or(false)
            && waited < 50
        {
            let pause = Cmd::new("sleep").arg("0.1").diag(program, 37).run();
            if pause.code != 0 {
                std::process::exit(pause.code);
            }
            waited += 1;
        }
        let _ = std::fs::remove_file(OsStr::from_bytes(&path));
        notify("Recording stopped");
        std::process::exit(0);
    }
    // Stale pidfile from a recorder that died on its own.
    let _ = std::fs::remove_file(OsStr::from_bytes(&path));
}

fn start_recording(program: &[u8], mode: &[u8]) {
    let mut directory = env::var_or_empty("HOME");
    directory.extend_from_slice(b"/vid/recordings");
    let stamp = Cmd::new("date")
        .arg("+%Y%m%d-%H.%M.%S")
        .stdout(Sink::Capture)
        .diag(program, 79)
        .run();
    if stamp.code != 0 {
        std::process::exit(stamp.code);
    }
    let stamp = text::strip_trailing_newlines(&stamp.stdout).to_vec();
    let mut filename = directory.clone();
    filename.extend_from_slice(b"/rec-");
    filename.extend_from_slice(&stamp);
    filename.extend_from_slice(b".mp4");

    let mut geometry: Vec<u8> = Vec::new();
    let mut gx: Vec<u8> = Vec::new();
    let mut gy: Vec<u8> = Vec::new();
    let mut gw: Vec<u8> = Vec::new();
    let mut gh: Vec<u8> = Vec::new();
    if mode == b"area" {
        // `slurp -f '%x %y %w %h' 2>/dev/null` in a process substitution:
        // the tool's stderr (and bash's not-found message) goes to /dev/null.
        let region = Cmd::new("slurp")
            .args(["-f", "%x %y %w %h"])
            .stdout(Sink::Capture)
            .stderr(Sink::Null)
            .run();
        // `read` assigns the partial line but fails at EOF without a newline,
        // and `|| exit 0` turns that into a silent cancel.
        if !region.stdout.contains(&b'\n') {
            std::process::exit(0);
        }
        let fields = text::read_fields(text::first_line(&region.stdout), 4);
        gx = fields[0].clone();
        gy = fields[1].clone();
        gw = fields[2].clone();
        gh = fields[3].clone();
        if gx.is_empty() || gh.is_empty() {
            std::process::exit(0);
        }
        geometry.extend_from_slice(&gx);
        geometry.push(b',');
        geometry.extend_from_slice(&gy);
        geometry.push(b' ');
        geometry.extend_from_slice(&gw);
        geometry.push(b'x');
        geometry.extend_from_slice(&gh);
    }

    let mut output = focused_output();
    if !geometry.is_empty() && !output.is_empty() {
        if let Some(rect) = focused_output_rect() {
            let fields = text::words(&rect);
            if fields.len() >= 4 {
                if let (
                    Some(mx),
                    Some(my),
                    Some(mw),
                    Some(mh),
                    Some(gx),
                    Some(gy),
                    Some(gw),
                    Some(gh),
                ) = (
                    integer(fields[0]),
                    integer(fields[1]),
                    integer(fields[2]),
                    integer(fields[3]),
                    integer(&gx),
                    integer(&gy),
                    integer(&gw),
                    integer(&gh),
                ) {
                    if gx < mx || gy < my || gx + gw > mx + mw || gy + gh > my + mh {
                        output.clear();
                    }
                }
            }
        }
    }

    let mut args: Vec<std::ffi::OsString> = vec![
        "-c".into(),
        "libx264rgb".into(),
        "-r".into(),
        "60".into(),
        "-p".into(),
        "crf=20".into(),
        "-p".into(),
        "preset=superfast".into(),
        "-f".into(),
        env::os_string(&filename),
    ];
    if !geometry.is_empty() {
        args.push("-g".into());
        args.push(env::os_string(&geometry));
    }
    if !output.is_empty() {
        args.push("-o".into());
        args.push(env::os_string(&output));
    }

    let child = Command::new("wf-recorder")
        .args(&args)
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .spawn();
    let mut child = match child {
        Ok(child) => Some(child),
        Err(_) => {
            env::err(&env::not_found_message(program, 110, b"wf-recorder"));
            None
        }
    };

    // wf-recorder can die right away (unwritable output, busy capture device):
    // only a recorder that is actually alive earns a pidfile and a toast.
    let pause = Cmd::new("sleep").arg("0.3").diag(program, 115).run();
    if pause.code != 0 {
        std::process::exit(pause.code);
    }
    let alive = match child.as_mut() {
        Some(child) => matches!(child.try_wait(), Ok(None)),
        None => false,
    };
    if !alive {
        notify("Recording failed to start");
        std::process::exit(1);
    }
    let pid = child.as_ref().map(|child| child.id()).unwrap_or(0);
    let mut pid_text = pid.to_string().into_bytes();
    pid_text.push(b'\n');
    let _ = std::fs::write(OsStr::from_bytes(&pidfile()), pid_text);
    notify("Recording started...");
}

/// `notify-send -u low "Screen Recording" "$1"` with both streams of the tool
/// discarded; a wedged notification daemon must never abort a recording.
fn notify(message: &str) {
    let _ = Cmd::new("notify-send")
        .args(["-u", "low", "Screen Recording"])
        .arg(message)
        .stderr(Sink::Null)
        .run();
}

/// The output whose picture the recorder should take: hyprctl's focused output,
/// or the only one wf-recorder lists.
fn focused_output() -> Vec<u8> {
    let mut name: Vec<u8> = Vec::new();
    if env::which(b"hyprctl") && env::which(b"jq") {
        let monitors = Cmd::new("hyprctl")
            .args(["-j", "monitors"])
            .stdout(Sink::Capture)
            .stderr(Sink::Null)
            .run();
        if let Ok(Json::Arr(items)) = Json::parse(&monitors.stdout) {
            for item in items {
                let focused = item.get("focused").map(Json::truthy).unwrap_or(false);
                if focused {
                    // `jq -r .name`: a missing member prints `null`.
                    name = item
                        .get("name")
                        .map(|value| text::first_line(&value.raw()).to_vec())
                        .unwrap_or_else(|| b"null".to_vec());
                    break;
                }
            }
        }
    }
    if !name.is_empty() {
        return name;
    }
    let listed = Cmd::new("wf-recorder")
        .arg("-L")
        .stdout(Sink::Capture)
        .stderr(Sink::Null)
        .run();
    let count = listed
        .stdout
        .split(|byte| *byte == b'\n')
        .filter(|line| text::find(line, b"Name:").is_some())
        .count();
    if count == 1 {
        // The original asks `wf-recorder -L` a second time for the name; the
        // extra invocation is part of the observable argv.
        let listed = Cmd::new("wf-recorder")
            .arg("-L")
            .stdout(Sink::Capture)
            .stderr(Sink::Null)
            .run();
        for line in listed.stdout.split(|byte| *byte == b'\n') {
            if text::find(line, b"Name:").is_some() {
                let fields = text::words(line);
                if fields.len() >= 3 {
                    name = fields[2].to_vec();
                }
                break;
            }
        }
    }
    name
}

/// `"x y width height"` of the focused output, used only to test whether a
/// selection lies completely inside it.
fn focused_output_rect() -> Option<Vec<u8>> {
    if !(env::which(b"hyprctl") && env::which(b"jq")) {
        return None;
    }
    let monitors = Cmd::new("hyprctl")
        .args(["-j", "monitors"])
        .stdout(Sink::Capture)
        .stderr(Sink::Null)
        .run();
    let items = match Json::parse(&monitors.stdout) {
        Ok(Json::Arr(items)) => items,
        _ => return None,
    };
    for item in items {
        let focused = item.get("focused").map(Json::truthy).unwrap_or(false);
        if !focused {
            continue;
        }
        let mut rect = Vec::new();
        for (index, key) in ["x", "y", "width", "height"].iter().enumerate() {
            if index > 0 {
                rect.push(b' ');
            }
            match item.get(key) {
                Some(value) => rect.extend_from_slice(&value.raw()),
                None => rect.extend_from_slice(b"null"),
            }
        }
        return Some(text::first_line(&rect).to_vec());
    }
    None
}

fn integer(bytes: &[u8]) -> Option<i64> {
    std::str::from_utf8(bytes)
        .ok()
        .and_then(|text| text.trim().parse::<i64>().ok())
}
