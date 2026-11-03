//! Rust port of `packages/local-bin/bin/pic-notify`.
//!
//! Screenshot notification bridge: copies the path to the clipboard, writes the
//! preview JSON both the pleamar toast and the legacy quickshell toast poll,
//! touches the legacy semaphore and falls back to `notify-send` when the IPC
//! round trip fails. `identify`, `date`, `wl-copy`, `timeout`, `pleamar`,
//! `quickshell` and `notify-send` stay subprocesses; the channel label, the
//! human-readable size, the timestamp parsing and the JSON are native.

#![forbid(unsafe_code)]

use std::io::Write;
use std::os::unix::ffi::OsStrExt;
use std::path::Path;
use std::time::SystemTime;

use local_bin_desktop::env;
use local_bin_desktop::helptext::PIC_NOTIFY_USAGE;
use local_bin_desktop::proc::{Cmd, Sink};
use local_bin_desktop::text;

fn main() {
    let mut arguments = std::env::args_os();
    let argv0 = arguments.next().unwrap_or_default();
    let program = env::invocation_name(&argv0);
    let img = arguments
        .next()
        .map(|value| value.as_bytes().to_vec())
        .unwrap_or_default();

    // The original prints its header for -h/--help as well, but keeps status 1.
    if img.is_empty() || img == b"-h" || img == b"--help" {
        env::out_str(PIC_NOTIFY_USAGE);
        std::process::exit(1);
    }

    // ── Clipboard ──────────────────────────────────────────────────────────
    // `echo "$img" | sed -e "s/.bmp$/.png/" | wl-copy`
    let mut clipboard = bmp_to_png(&img);
    clipboard.push(b'\n');
    let _ = Cmd::new("wl-copy")
        .stdin(local_bin_desktop::proc::Input::Bytes(&clipboard))
        .diag(&program, 18)
        .run();

    // ── Metadata (identify -ping, header only) ─────────────────────────────
    let mut width: Vec<u8> = Vec::new();
    let mut height: Vec<u8> = Vec::new();
    let mut depth: Vec<u8> = Vec::new();
    let mut channel = Vec::new();
    if env::which(b"identify") {
        let identified = Cmd::new("identify")
            .args(["-ping", "-format", "%w %h %z %[channels]"])
            .arg_bytes(&img)
            .stdout(Sink::Capture)
            .stderr(Sink::Null)
            .run();
        let stripped = text::strip_trailing_newlines(&identified.stdout);
        let fields = text::read_fields(text::first_line(stripped), 4);
        width = fields[0].clone();
        height = fields[1].clone();
        depth = fields[2].clone();
        let mut channel_raw = fields[3].clone();
        if width.is_empty() {
            width.clear();
            height.clear();
            depth.clear();
            channel_raw.clear();
        }
        channel = channel_label(&channel_raw);
    }

    // ── File size (human readable) ─────────────────────────────────────────
    let size_bytes = std::fs::metadata(std::ffi::OsStr::from_bytes(&img))
        .map(|metadata| metadata.len() as i64)
        .unwrap_or(0);
    let size_human = human_size(size_bytes);

    // ── Depth description ──────────────────────────────────────────────────
    let mut depth_text = Vec::new();
    if !depth.is_empty() {
        depth_text.extend_from_slice(&depth);
        depth_text.extend_from_slice(b"-bit");
        if !channel.is_empty() {
            depth_text.push(b' ');
            depth_text.extend_from_slice(&channel);
        }
    }

    // ── Timestamp from the file name, else from the mtime ──────────────────
    let timestamp = timestamp(&img);

    // ── Write the JSON event for both toast implementations ────────────────
    let json = event_json(&img, &width, &height, &size_human, &depth_text, &timestamp);
    let cache = env::var_nonempty("XDG_CACHE_HOME").unwrap_or_else(|| {
        let mut home = env::var_or_empty("HOME");
        home.extend_from_slice(b"/.cache");
        home
    });
    let mut pleamar_dir = cache.clone();
    pleamar_dir.extend_from_slice(b"/pleamar");
    write_event(&pleamar_dir, &json);
    let mut quickshell_dir = env::var_or_empty("HOME");
    quickshell_dir.extend_from_slice(b"/.cache/quickshell");
    write_event(&quickshell_dir, &json);
    let mut semaphore = quickshell_dir.clone();
    semaphore.extend_from_slice(b"/screenshot-event");
    touch(std::ffi::OsStr::from_bytes(&semaphore));

    // ── Fallback: notify-send when neither IPC endpoint answers ────────────
    let mut answered = Cmd::new("timeout")
        .args(["2", "pleamar", "--say", "toast", "describe"])
        .stdout(Sink::Null)
        .stderr(Sink::Null)
        .run()
        .code
        == 0;
    if !answered {
        answered = Cmd::new("timeout")
            .args(["2", "quickshell", "ipc", "show"])
            .stdout(Sink::Null)
            .stderr(Sink::Null)
            .run()
            .code
            == 0;
    }
    if answered || !env::which(b"notify-send") {
        std::process::exit(0);
    }

    let home = env::var_or_empty("HOME");
    let short = if home.is_empty() {
        let mut short = b"~".to_vec();
        short.extend_from_slice(&img);
        short
    } else {
        text::replace_first(&img, &home, b"~")
    };
    let mut body = Vec::new();
    body.extend_from_slice(if width.is_empty() { b"0" } else { &width });
    body.extend_from_slice("×".as_bytes());
    body.extend_from_slice(if height.is_empty() { b"0" } else { &height });
    body.extend_from_slice(b"  \xc2\xb7  ");
    body.extend_from_slice(size_human.as_bytes());
    if !depth_text.is_empty() {
        body.extend_from_slice(b"  \xc2\xb7  ");
        body.extend_from_slice(&depth_text);
    }
    // The shell string keeps a literal `\n` here; notify-send shows it as-is.
    body.extend_from_slice(b"\\n");
    body.extend_from_slice(&short);
    if !timestamp.is_empty() {
        body.extend_from_slice(b"\\n");
        body.extend_from_slice(&timestamp);
    }

    let outcome = Cmd::new("notify-send")
        .args(["-h", "string:fgcolor:#6C7E96", "-a", "screenshot", "-i"])
        .arg_bytes(&img)
        .arg("📸 Screenshot")
        .arg_bytes(&body)
        .diag(&program, 127)
        .run();
    std::process::exit(outcome.code);
}

/// `sed -e "s/.bmp$/.png/"`: any single byte followed by `bmp` at the end.
fn bmp_to_png(path: &[u8]) -> Vec<u8> {
    if path.len() >= 4 && path.ends_with(b"bmp") {
        let mut result = path[..path.len() - 4].to_vec();
        result.extend_from_slice(b".png");
        return result;
    }
    path.to_vec()
}

/// `%[channels]` is a bare count on ImageMagick 6 and a channel-set name plus a
/// count on 7 ("srgba 4.0"); the trailing number wins when present, the name is
/// the fallback for both spellings.
fn channel_label(raw: &[u8]) -> Vec<u8> {
    let mut number: Vec<u8> = Vec::new();
    for token in text::words(raw) {
        let token = match token.iter().position(|byte| *byte == b'.') {
            Some(position) => &token[..position],
            None => token,
        };
        if !token.is_empty() && token.iter().all(|byte| byte.is_ascii_digit()) {
            number = token.to_vec();
        }
    }
    match number.as_slice() {
        b"1" => return b"Gray".to_vec(),
        b"2" => return b"Gray+Alpha".to_vec(),
        b"3" => return b"RGB".to_vec(),
        b"4" => return b"RGBA".to_vec(),
        b"" => {
            let starts = |prefix: &[u8]| raw.starts_with(prefix);
            if starts(b"srgba") || starts(b"rgba") {
                return b"RGBA".to_vec();
            }
            if starts(b"graya") || starts(b"greya") {
                return b"Gray+Alpha".to_vec();
            }
            if starts(b"gray") || starts(b"grey") {
                return b"Gray".to_vec();
            }
            if starts(b"srgb") || starts(b"rgb") {
                return b"RGB".to_vec();
            }
            return Vec::new();
        }
        other => {
            let mut label = other.to_vec();
            label.extend_from_slice(b"ch");
            return label;
        }
    }
}

/// awk's `printf "%.1f GB" / "%.2f MB" / "%.0f KB"` on the byte count.
fn human_size(bytes: i64) -> String {
    if bytes >= 1_073_741_824 {
        format!("{:.1} GB", bytes as f64 / 1_073_741_824.0)
    } else if bytes >= 1_048_576 {
        format!("{:.2} MB", bytes as f64 / 1_048_576.0)
    } else {
        format!("{:.0} KB", bytes as f64 / 1024.0)
    }
}

/// `grep -oE '[0-9]{8}-[0-9]{2}\.[0-9]{2}\.[0-9]{2}'` rewritten into
/// `YYYY-MM-DD HH:MM:SS`, else `date -d @<mtime> '+%F %T'`.
fn timestamp(img: &[u8]) -> Vec<u8> {
    let base = text::basename(img);
    let matches = timestamp_matches(base);
    if !matches.is_empty() {
        let mut result = Vec::new();
        for (index, capture) in matches.iter().enumerate() {
            if index > 0 {
                result.push(b'\n');
            }
            let text = std::str::from_utf8(capture).unwrap_or_default();
            result.extend_from_slice(
                format!(
                    "{}-{}-{} {}:{}:{}",
                    &text[0..4],
                    &text[4..6],
                    &text[6..8],
                    &text[9..11],
                    &text[12..14],
                    &text[15..17]
                )
                .as_bytes(),
            );
        }
        return result;
    }
    let epoch = std::fs::metadata(std::ffi::OsStr::from_bytes(img))
        .ok()
        .and_then(|metadata| metadata.modified().ok())
        .map(|time| {
            time.duration_since(std::time::UNIX_EPOCH)
                .map(|duration| duration.as_secs())
                .unwrap_or(0)
        })
        .map(|seconds| seconds.to_string())
        .unwrap_or_default();
    let date = Cmd::new("date")
        .arg("-d")
        .arg(format!("@{epoch}"))
        .arg("+%F %T")
        .stdout(Sink::Capture)
        .stderr(Sink::Null)
        .run();
    if date.code != 0 {
        return Vec::new();
    }
    text::strip_trailing_newlines(&date.stdout).to_vec()
}

/// All non-overlapping matches of the timestamp shape, left to right.
fn timestamp_matches(base: &[u8]) -> Vec<Vec<u8>> {
    let length = 17;
    let mut matches = Vec::new();
    let mut index = 0;
    while index + length <= base.len() {
        let window = &base[index..index + length];
        let digits =
            |from: usize, to: usize| window[from..to].iter().all(|byte| byte.is_ascii_digit());
        if digits(0, 8)
            && window[8] == b'-'
            && digits(9, 11)
            && window[11] == b'.'
            && digits(12, 14)
            && window[14] == b'.'
            && digits(15, 17)
        {
            matches.push(window.to_vec());
            index += length;
        } else {
            index += 1;
        }
    }
    matches
}

/// The event heredoc, byte for byte (2-space layout, trailing newline).
fn event_json(
    img: &[u8],
    width: &[u8],
    height: &[u8],
    size_human: &str,
    depth: &[u8],
    timestamp: &[u8],
) -> Vec<u8> {
    let mut escaped = Vec::with_capacity(img.len());
    for byte in img {
        match byte {
            b'\\' => escaped.extend_from_slice(b"\\\\"),
            _ => escaped.push(*byte),
        }
    }
    let mut escaped_path = Vec::with_capacity(escaped.len());
    for byte in &escaped {
        match byte {
            b'"' => escaped_path.extend_from_slice(b"\\\""),
            _ => escaped_path.push(*byte),
        }
    }
    let mut json = Vec::new();
    json.extend_from_slice(b"{\n  \"path\": \"");
    json.extend_from_slice(&escaped_path);
    json.extend_from_slice(b"\",\n  \"w\": ");
    json.extend_from_slice(if width.is_empty() { b"0" } else { width });
    json.extend_from_slice(b",\n  \"h\": ");
    json.extend_from_slice(if height.is_empty() { b"0" } else { height });
    json.extend_from_slice(b",\n  \"sizeHr\": \"");
    json.extend_from_slice(size_human.as_bytes());
    json.extend_from_slice(b"\",\n  \"depth\": \"");
    json.extend_from_slice(depth);
    json.extend_from_slice(b"\",\n  \"ts\": \"");
    json.extend_from_slice(timestamp);
    json.extend_from_slice(b"\"\n}\n");
    json
}

/// `mkdir -p DIR; cat > tmp; mv tmp DIR/screenshot-event.json` — the rename
/// stays atomic, failures are non-fatal like in the shell.
fn write_event(dir: &[u8], json: &[u8]) {
    let directory = Path::new(std::ffi::OsStr::from_bytes(dir));
    let _ = std::fs::create_dir_all(directory);
    let mut temp = dir.to_vec();
    temp.extend_from_slice(b"/.screenshot-event.json.tmp");
    let temp = std::ffi::OsStr::from_bytes(&temp);
    if std::fs::write(temp, json).is_ok() {
        let mut target = dir.to_vec();
        target.extend_from_slice(b"/screenshot-event.json");
        let _ = std::fs::rename(temp, std::ffi::OsStr::from_bytes(&target));
    }
}

/// `touch`: create when missing, otherwise bump the modification time.
fn touch(path: &std::ffi::OsStr) {
    if !Path::new(path).exists() {
        let _ = std::fs::write(path, b"");
        return;
    }
    if let Ok(mut file) = std::fs::OpenOptions::new().write(true).open(path) {
        let _ = file.set_times(std::fs::FileTimes::new().set_modified(SystemTime::now()));
        let _ = file.flush();
    }
}
