//! Rust port of `packages/local-bin/bin/screenrec`, extended with sound.
//!
//! Toggles a wf-recorder capture. `date`, `slurp`, `hyprctl`, `wf-recorder`,
//! `ffmpeg`, `sleep` and `notify-send` stay subprocesses with the original
//! argv; the pidfile handling, the `/proc/<pid>/comm` ownership check, the
//! output/region matching, the geometry arithmetic and the recorder state file
//! are native. SIGINT delivery and the liveness probe go through `nix` because
//! std can only kill children it still owns (the recorder of a previous
//! invocation is not one of them).
//!
//! ## Sound
//!
//! Every recording carries the microphone and the system output, mixed. A
//! second ffmpeg child captures `@DEFAULT_SOURCE@` and `@DEFAULT_MONITOR@`,
//! mixes them (`amix` + limiter) into a Matroska audio sidecar next to the
//! video, and the stop path muxes that sidecar into the final `.mp4`. wf-recorder
//! 0.6 accepts one audio device per run (measured: two `--audio` arguments
//! record only the last), so the mix cannot live inside the recorder.
//!
//! Matroska, not m4a: a SIGINT must be able to finalize the sidecar (an MP4
//! trailer is written only on a clean exit, and a recorder killed by anything
//! else would leave a 44-byte file).
//!
//! ## Subcommands
//!
//! - `screenrec [screen|area]` — toggle, as before.
//! - `screenrec stop` — stop, or clear a stale state without starting anything.
//! - `screenrec status [--watch [SECONDS]]` — one JSON line per second (or once):
//!   `{"screen":bool,"audio":bool,"elapsed":N,"pid":N}`. The bar polls the two
//!   files above itself (so it keeps working across a binary that predates this
//!   subcommand); `status` is the same answer for a shell or a probe.

#![forbid(unsafe_code)]

use std::ffi::OsStr;
use std::io::Write;
use std::os::unix::ffi::OsStrExt;
use std::path::Path;
use std::process::{Command, Stdio};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use nix::sys::signal::{kill, Signal};
use nix::unistd::Pid;

use local_bin_desktop::env;
use local_bin_desktop::json::Json;
use local_bin_desktop::proc::{Cmd, Input, Sink};
use local_bin_desktop::text;

fn main() {
    let mut arguments = std::env::args_os();
    let argv0 = arguments.next().unwrap_or_default();
    let program = env::invocation_name(&argv0);
    let mode = arguments
        .next()
        .map(|value| value.as_bytes().to_vec())
        .unwrap_or_else(|| b"screen".to_vec());

    // `status` is a read-only probe and must not create directories or touch the
    // recorder: it is what every bar instance polls.
    if mode == b"status" {
        status(arguments);
        return;
    }

    // The original creates the recordings directory before the toggle check.
    let mut directory = env::var_or_empty("HOME");
    directory.extend_from_slice(b"/vid/recordings");
    if std::fs::create_dir_all(OsStr::from_bytes(&directory)).is_err() {
        std::process::exit(1);
    }

    if is_recording(&program) {
        stop_recording(&program);
    } else if mode == b"stop" {
        // Nothing is recording: drop a stale sidecar and state, but never start.
        cleanup_stale_audio();
        clear_state();
        let _ = std::fs::remove_file(OsStr::from_bytes(&pidfile()));
    } else {
        // An interrupted run can leave the audio sidecar alive after its video
        // recorder died; it would keep recording the room forever.
        cleanup_stale_audio();
        start_recording(&program, &mode);
    }
}

fn pidfile() -> Vec<u8> {
    let mut path = b"/tmp/wf-recorder-".to_vec();
    path.extend_from_slice(&env::var_or_empty("USER"));
    path.extend_from_slice(b".pid");
    path
}

/// The sidecar's own state: the two paths, when the take started and which
/// process is recording its sound. One JSON object, replaced atomically.
struct State {
    video: Vec<u8>,
    audio: Vec<u8>,
    started: u64,
    audio_pid: i32,
}

fn statefile() -> Vec<u8> {
    let mut path = b"/tmp/wf-recorder-".to_vec();
    path.extend_from_slice(&env::var_or_empty("USER"));
    path.extend_from_slice(b".json");
    path
}

fn now_seconds() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs())
        .unwrap_or(0)
}

fn read_state() -> Option<State> {
    let bytes = std::fs::read(OsStr::from_bytes(&statefile())).ok()?;
    let json = Json::parse(&bytes).ok()?;
    let video = json.get("video")?.as_str()?.to_vec();
    let audio = json
        .get("audio")
        .and_then(Json::as_str)
        .map(|value| value.to_vec())
        .unwrap_or_default();
    let started = json.get("started").and_then(Json::as_number).unwrap_or(0.0);
    let audio_pid = json
        .get("audio_pid")
        .and_then(Json::as_number)
        .unwrap_or(0.0);
    Some(State {
        video,
        audio,
        started: started.max(0.0) as u64,
        audio_pid: audio_pid.max(0.0) as i32,
    })
}

/// A JSON string literal; the paths come from HOME and `date`, but a quote in
/// HOME would otherwise corrupt the state the bar reads.
fn json_quote(value: &[u8], out: &mut Vec<u8>) {
    out.push(b'"');
    for &byte in value {
        match byte {
            b'"' => out.extend_from_slice(b"\\\""),
            b'\\' => out.extend_from_slice(b"\\\\"),
            b'\n' => out.extend_from_slice(b"\\n"),
            b'\r' => out.extend_from_slice(b"\\r"),
            b'\t' => out.extend_from_slice(b"\\t"),
            0x00..=0x1f => {
                out.extend_from_slice(format!("\\u{byte:04x}").as_bytes());
            }
            _ => out.push(byte),
        }
    }
    out.push(b'"');
}

fn state_bytes(state: &State) -> Vec<u8> {
    let mut out = Vec::new();
    out.extend_from_slice(b"{\"video\":");
    json_quote(&state.video, &mut out);
    out.extend_from_slice(b",\"audio\":");
    json_quote(&state.audio, &mut out);
    out.extend_from_slice(
        format!(
            ",\"started\":{},\"audio_pid\":{}}}",
            state.started, state.audio_pid
        )
        .as_bytes(),
    );
    out
}

/// Write through a sibling temp file: the bar polls the path from another
/// process, so a half-written JSON object must never be visible.
fn write_state(state: &State) {
    let path = statefile();
    let mut temporary = path.clone();
    temporary.extend_from_slice(b".tmp");
    if std::fs::write(OsStr::from_bytes(&temporary), state_bytes(state)).is_err() {
        return;
    }
    let _ = std::fs::rename(OsStr::from_bytes(&temporary), OsStr::from_bytes(&path));
}

fn clear_state() {
    let _ = std::fs::remove_file(OsStr::from_bytes(&statefile()));
}

/// `/proc/<pid>/comm`, with the newline the kernel appends removed.
fn process_comm(pid: i32) -> Option<Vec<u8>> {
    let mut path = b"/proc/".to_vec();
    path.extend_from_slice(pid.to_string().as_bytes());
    path.extend_from_slice(b"/comm");
    std::fs::read(OsStr::from_bytes(&path))
        .ok()
        .map(|contents| text::strip_trailing_newlines(&contents).to_vec())
}

fn process_alive(pid: i32, comm: &[u8]) -> bool {
    pid > 0 && process_comm(pid).map(|own| own == comm).unwrap_or(false)
}

/// `recorder_pid`: the pidfile names a live process whose comm is `wf-recorder`
/// (a reused PID must not make the toggle signal an unrelated process).
fn recorder_pid() -> Option<i32> {
    let path = pidfile();
    let contents = std::fs::read(OsStr::from_bytes(&path)).ok()?;
    let pid = text::strip_trailing_newlines(&contents);
    let pid = std::str::from_utf8(pid).ok()?.trim().parse::<i32>().ok()?;
    if process_alive(pid, b"wf-recorder") {
        Some(pid)
    } else {
        None
    }
}

/// `is_recording`: see [`recorder_pid`].
fn is_recording(_program: &[u8]) -> bool {
    recorder_pid().is_some()
}

/// One status line, the shape the `status` subcommand documents.
fn status_line() -> Vec<u8> {
    let Some(pid) = recorder_pid() else {
        return b"{\"screen\":false}".to_vec();
    };
    let state = read_state();
    let elapsed = state
        .as_ref()
        .filter(|state| state.started > 0)
        .map(|state| now_seconds().saturating_sub(state.started))
        .unwrap_or(0);
    let audio = state
        .as_ref()
        .map(|state| process_alive(state.audio_pid, b"ffmpeg"))
        .unwrap_or(false);
    format!(
        "{{\"screen\":true,\"audio\":{},\"elapsed\":{elapsed},\"pid\":{pid}}}",
        if audio { "true" } else { "false" }
    )
    .into_bytes()
}

/// `status [--watch [SECONDS]]`: one line, then a line every SECONDS while
/// `--watch` holds. A closed stdout (the bar scene went away) ends it.
fn status(mut arguments: std::env::ArgsOs) {
    let mut watch = false;
    let mut interval = 1u64;
    let mut wants_interval = false;
    while let Some(argument) = arguments.next() {
        let bytes = argument.as_bytes();
        if bytes == b"--watch" {
            watch = true;
            wants_interval = true;
        } else if let Some(value) = bytes.strip_prefix(b"--watch=") {
            watch = true;
            interval = parse_interval(value).unwrap_or(1);
        } else if wants_interval {
            interval = parse_interval(bytes).unwrap_or(1);
            wants_interval = false;
        }
    }
    if interval == 0 {
        interval = 1;
    }
    if interval > 60 {
        interval = 60;
    }
    loop {
        let line = status_line();
        let written = {
            let mut stdout = std::io::stdout().lock();
            stdout
                .write_all(&line)
                .and_then(|_| stdout.write_all(b"\n"))
                .and_then(|_| stdout.flush())
                .is_ok()
        };
        if !written {
            return;
        }
        if !watch {
            return;
        }
        std::thread::sleep(Duration::from_secs(interval));
    }
}

fn parse_interval(bytes: &[u8]) -> Option<u64> {
    std::str::from_utf8(bytes)
        .ok()
        .map(str::trim)
        .and_then(|value| value.parse::<u64>().ok())
}

fn stop_recording(program: &[u8]) {
    let path = pidfile();
    if is_recording(program) {
        let state = read_state();
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

        // The sidecar finalizes its Matroska trailer on SIGINT too. It is a
        // separate process, so it has to be stopped before the mux reads it.
        let mut audio_ready = false;
        if let Some(state) = state.as_ref() {
            if state.audio_pid > 0 {
                let _ = kill(Pid::from_raw(state.audio_pid), Signal::SIGINT);
                let mut waited = 0;
                while kill(Pid::from_raw(state.audio_pid), None).is_ok() && waited < 50 {
                    let pause = Cmd::new("sleep").arg("0.1").diag(program, 37).run();
                    if pause.code != 0 {
                        std::process::exit(pause.code);
                    }
                    waited += 1;
                }
                audio_ready = !state.audio.is_empty()
                    && Path::new(OsStr::from_bytes(&state.audio)).is_file()
                    && Path::new(OsStr::from_bytes(&state.video)).is_file();
            }
        }

        let muxed = if audio_ready {
            match state.as_ref() {
                Some(state) => mux_audio(&state.video, &state.audio),
                None => false,
            }
        } else {
            false
        };
        clear_state();
        if audio_ready && !muxed {
            // The take is still saved: the video and its sidecar are both on
            // disk, and the owner can mux them by hand.
            notify("Recording stopped (audio kept beside the video)");
        } else {
            notify("Recording stopped");
        }
        std::process::exit(0);
    }
    // Stale pidfile from a recorder that died on its own; its sidecar may still
    // be running, and nothing would ever stop it.
    cleanup_stale_audio();
    clear_state();
    let _ = std::fs::remove_file(OsStr::from_bytes(&path));
}

/// Stop an audio sidecar whose video recorder is gone. Only a process whose
/// comm is still `ffmpeg` is signalled: the state file may be old enough for the
/// PID to have been reused.
fn cleanup_stale_audio() {
    let Some(state) = read_state() else {
        return;
    };
    if !process_alive(state.audio_pid, b"ffmpeg") {
        return;
    }
    let _ = kill(Pid::from_raw(state.audio_pid), Signal::SIGINT);
    let mut waited = 0;
    while kill(Pid::from_raw(state.audio_pid), None).is_ok() && waited < 20 {
        std::thread::sleep(Duration::from_millis(100));
        waited += 1;
    }
}

/// `rec-<stamp>.mux.mp4` beside the video, so the final rename stays inside one
/// filesystem.
fn mux_path(video: &[u8]) -> Vec<u8> {
    let mut path = video.to_vec();
    let slash = path
        .iter()
        .rposition(|byte| *byte == b'/')
        .map_or(0, |at| at + 1);
    if let Some(dot) = path[slash..]
        .iter()
        .rposition(|byte| *byte == b'.')
        .map(|at| slash + at)
    {
        path.truncate(dot);
    }
    path.extend_from_slice(b".mux.mp4");
    path
}

/// Put the audio sidecar into the final mp4. `-c copy` on both streams: the
/// video is already encoded by wf-recorder and the audio by the sidecar, so the
/// stop path costs a remux, not an encode.
fn mux_audio(video: &[u8], audio: &[u8]) -> bool {
    let output = mux_path(video);
    let _ = std::fs::remove_file(OsStr::from_bytes(&output));
    let outcome = Cmd::new("ffmpeg")
        .args(["-hide_banner", "-loglevel", "error", "-nostdin", "-y"])
        .arg("-i")
        .arg_bytes(video)
        .arg("-i")
        .arg_bytes(audio)
        .args([
            "-map",
            "0:v:0",
            "-map",
            "1:a:0",
            "-c",
            "copy",
            "-movflags",
            "+faststart",
        ])
        .arg_bytes(&output)
        .stdin(Input::Null)
        .stdout(Sink::Null)
        .stderr(Sink::Null)
        .run();
    if outcome.code != 0 || !Path::new(OsStr::from_bytes(&output)).is_file() {
        let _ = std::fs::remove_file(OsStr::from_bytes(&output));
        return false;
    }
    if std::fs::rename(OsStr::from_bytes(&output), OsStr::from_bytes(video)).is_err() {
        return false;
    }
    let _ = std::fs::remove_file(OsStr::from_bytes(audio));
    true
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
    let mut audio_filename = directory.clone();
    audio_filename.extend_from_slice(b"/rec-");
    audio_filename.extend_from_slice(&stamp);
    audio_filename.extend_from_slice(b".mka");

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

    // The sound is a second process: wf-recorder 0.6 takes one audio device and
    // records only the last one when asked twice, so the microphone and the
    // system output are mixed here and muxed in on stop. `-nostdin` keeps the
    // toggle's terminal out of ffmpeg's hands; stderr stays inherited so a
    // device that disappears is visible in the journal.
    let mut audio_child = Command::new("ffmpeg")
        .args([
            "-hide_banner",
            "-loglevel",
            "error",
            "-nostdin",
            "-f",
            "pulse",
            "-i",
            "@DEFAULT_SOURCE@",
            "-f",
            "pulse",
            "-i",
            "@DEFAULT_MONITOR@",
            "-filter_complex",
            "[0:a][1:a]amix=inputs=2:duration=longest:dropout_transition=0:normalize=0,alimiter=level=0:limit=0.95[a]",
            "-map",
            "[a]",
            "-c:a",
            "aac",
            "-b:a",
            "192k",
            "-y",
        ])
        .arg(env::os_string(&audio_filename))
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::inherit())
        .spawn()
        .ok();

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
        // The sidecar may already be recording; a failed take must not leave it
        // behind.
        if let Some(mut audio) = audio_child {
            let _ = audio.kill();
            let _ = audio.wait();
        }
        notify("Recording failed to start");
        std::process::exit(1);
    }
    let pid = child.as_ref().map(|child| child.id()).unwrap_or(0);
    let audio_pid = match audio_child.as_mut() {
        Some(audio) => match audio.try_wait() {
            Ok(None) => audio.id() as i32,
            _ => 0,
        },
        None => 0,
    };
    let mut pid_text = pid.to_string().into_bytes();
    pid_text.push(b'\n');
    let _ = std::fs::write(OsStr::from_bytes(&pidfile()), pid_text);
    write_state(&State {
        video: filename,
        audio: if audio_pid > 0 {
            audio_filename
        } else {
            Vec::new()
        },
        started: now_seconds(),
        audio_pid,
    });
    notify(if audio_pid > 0 {
        "Recording started..."
    } else {
        "Recording started (no audio)"
    });
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
