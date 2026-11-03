//! Rust port of `packages/local-bin/bin/audio-diag`.
//!
//! Checks audio routing health and unity (0 dB) on trantor: the default sink,
//! the single path into the RME AES pair, unity volumes, the RME hardware mixer,
//! and the anti-recurrence guards. Every `pw-link`/`wpctl`/`amixer`/`pgrep`/
//! `systemctl`/`date` call stays a subprocess with the original argv; the
//! `awk`/`sed`/`grep`/`sort`/`cut` pipelines over their output are native.
//!
//! Exit codes are the script's: 0 all good, 1 at least one FAIL, 2 a required
//! tool (`pw-link`, `wpctl`, `amixer`) was missing. `set -u` and the absence of
//! `set -e` are reflected in the flow: only `date` has a visible missing-tool
//! diagnostic, every other probe redirects stderr.

use std::ffi::OsStr;
use std::fs;
use std::os::unix::ffi::OsStrExt;
use std::path::Path;

use local_bin_audio::env;
use local_bin_audio::proc::{Cmd, Sink};
use local_bin_audio::text;

fn main() {
    let mut arguments = std::env::args_os();
    let argv0 = arguments.next().unwrap_or_default();
    let program = env::invocation_name(&argv0);

    let mut report = Report {
        failures: 0,
        essential: 0,
    };

    // `echo "==== audio-diag ($(date '+%F %T')) ===="`
    let date = Cmd::new("date")
        .arg("+%F %T")
        .stdout(Sink::Capture)
        .diag(&program, 36)
        .run();
    let mut header = b"==== audio-diag (".to_vec();
    header.extend_from_slice(text::strip_trailing_newlines(&date.stdout));
    header.extend_from_slice(b") ====\n");
    env::out(&header);

    // `need pw-link; need wpctl; need amixer`
    report.need(b"pw-link");
    report.need(b"wpctl");
    report.need(b"amixer");

    let links = collect_links(&program);

    // 1. Default sink must be game-stereo.
    let status = wpctl_status(&program, 59);
    let default_sink = status
        .split(|byte| *byte == b'\n')
        .any(|line| ordered_contains(line, &[b"*", b"game-stereo", b"Audio/Sink"]));
    if default_sink {
        report.pass(b"default sink = game-stereo");
    } else {
        report.fail(b"default sink is not game-stereo");
    }

    // 2. Exactly one source into each RME AES (AUX2/AUX3) playback port, and it
    //    must be the game-stereo loopback.
    let mut aes_ports: Vec<Vec<u8>> = links
        .iter()
        .filter_map(|line| {
            let fields = link_fields(line);
            if fields.len() < 2 {
                return None;
            }
            let destination = fields[1];
            if destination.ends_with(b":playback_AUX2") || destination.ends_with(b":playback_AUX3")
            {
                Some(destination.to_vec())
            } else {
                None
            }
        })
        .collect();
    aes_ports.sort();
    aes_ports.dedup();
    let aes_text = join_lines(&aes_ports);

    if aes_text.is_empty() {
        if env::which(b"pw-link") {
            report.info(b"no RME AES (AUX2/AUX3) ports linked - RME may be absent or idle");
        }
    } else {
        // `for p in $AES_PORTS`: unquoted, so the shell word-splits on the
        // default IFS. Port names with spaces are split the same way here.
        for port in text::words(&aes_text) {
            let sources = sources_of(&links, port);
            let sources_text = strip_join(&sources);
            let count = text::count_nonempty_lines(&sources_text);
            let loopback = sources_text
                .split(|byte| *byte == b'\n')
                .any(|line| line.starts_with(b"playback.game-stereo:output_"));
            let suffix = after_last_colon(port);
            if count == 1 && loopback {
                let mut message = b"AES ".to_vec();
                message.extend_from_slice(suffix);
                message.extend_from_slice(b" <- single source (playback.game-stereo loopback)");
                report.pass(&message);
            } else {
                let mut message = b"AES ".to_vec();
                message.extend_from_slice(suffix);
                message.extend_from_slice(b" has ");
                message.extend_from_slice(count.to_string().as_bytes());
                message.extend_from_slice(
                    b" source(s) (expected exactly 1 = playback.game-stereo:output_*)",
                );
                report.fail(&message);
                for line in sources_text.split(|byte| *byte == b'\n') {
                    let mut src = b"      src: ".to_vec();
                    src.extend_from_slice(line);
                    src.push(b'\n');
                    env::out(&src);
                }
            }
        }
    }

    // No direct app -> RME playback link.
    let mut direct: Vec<Vec<u8>> = Vec::new();
    for line in &links {
        let fields = link_fields(line);
        if fields.len() < 2 {
            continue;
        }
        if aux_digits(fields[1]) && !fields[0].starts_with(b"playback.game-stereo:output_") {
            let mut entry = fields[0].to_vec();
            entry.extend_from_slice(b" -> ");
            entry.extend_from_slice(fields[1]);
            direct.push(entry);
        }
    }
    if !direct.is_empty() {
        report.fail(b"direct app -> RME playback links (double route)");
        for line in &direct {
            let mut output = b"      link: ".to_vec();
            output.extend_from_slice(line);
            output.push(b'\n');
            env::out(&output);
        }
    } else {
        report.pass(b"no direct app -> RME playback links");
    }

    // 3. Unity (0 dB) in PipeWire for the nodes in the chain.
    let game_sink = extract_id(
        &wpctl_status(&program, 101),
        &[b"game-stereo", b"Audio/Sink"],
    );
    let rme_sink = extract_id(&wpctl_status(&program, 102), &[b"RME AIO Pro", b"Pro"]);
    let loop_id = extract_id(&wpctl_status(&program, 103), &[b"playback.game-stereo"]);

    for (name, id) in [
        (b"game-stereo".as_slice(), game_sink),
        (b"rme-pro".as_slice(), rme_sink),
        (b"loopback".as_slice(), loop_id),
    ] {
        if id.is_empty() {
            continue;
        }
        if vol_ok(&program, &id) {
            let mut message = b"volume ".to_vec();
            message.extend_from_slice(name);
            message.extend_from_slice(b" (id ");
            message.extend_from_slice(&id);
            message.extend_from_slice(b") = 1.00, not muted");
            report.pass(&message);
        } else {
            let volume = get_volume(&program, &id, 119);
            let mut message = b"volume ".to_vec();
            message.extend_from_slice(name);
            message.extend_from_slice(b" (id ");
            message.extend_from_slice(&id);
            message.extend_from_slice(b") not at unity/muted: ");
            message.extend_from_slice(text::strip_trailing_newlines(&volume));
            report.fail(&message);
        }
    }

    if vol_ok(&program, b"@DEFAULT_AUDIO_SINK@") {
        report.pass(b"default sink volume = 1.00, not muted");
    } else {
        let volume = get_volume(&program, b"@DEFAULT_AUDIO_SINK@", 127);
        let mut message = b"default sink not at unity: ".to_vec();
        message.extend_from_slice(text::strip_trailing_newlines(&volume));
        report.fail(&message);
    }

    // 4. RME hardware mixer unity (Chn controls = 64, per hdspe.nix).
    let cards = fs::read("/proc/asound/cards").unwrap_or_default();
    let hdsp = cards
        .split(|byte| *byte == b'\n')
        .find(|line| text::contains(line, b"HDSPe") || text::contains(line, b"RME AIO"))
        .and_then(|line| text::words(line).first().map(|word| word.to_vec()))
        .unwrap_or_default();
    if hdsp.is_empty() {
        report.info(b"RME HDSPe card not detected - skipping hardware mixer check");
    } else {
        let contents = Cmd::new("amixer")
            .arg("-c")
            .arg_bytes(&hdsp)
            .arg("contents")
            .stdout(Sink::Capture)
            .stderr(Sink::Null)
            .diag(&program, 135)
            .run()
            .stdout;
        let values = mixer_values(&contents);
        let channel_text = strip_join(&values);
        let total = text::count_nonempty_lines(&channel_text);
        let bad = channel_text
            .split(|byte| *byte == b'\n')
            .filter(|line| {
                let field = text::words(line).first().copied().unwrap_or_default();
                match std::str::from_utf8(field)
                    .ok()
                    .and_then(|value| value.parse::<i64>().ok())
                {
                    Some(value) => value != 64,
                    None => true,
                }
            })
            .count();
        if total >= 16 && bad == 0 {
            let mut message = b"RME mixer Chn (".to_vec();
            message.extend_from_slice(total.to_string().as_bytes());
            message.extend_from_slice(b" controls) all = 64 (unity)");
            report.pass(&message);
        } else {
            let mut message = b"RME mixer Chn: ".to_vec();
            message.extend_from_slice(bad.to_string().as_bytes());
            message.extend_from_slice(b" of ");
            message.extend_from_slice(total.to_string().as_bytes());
            message.extend_from_slice(b" not 64 (unity)");
            report.fail(&message);
        }
    }

    // 5. Anti-recurrence guards (informational - WARN only).
    let home = env::var_or_empty("HOME");
    let mut wireplumber = home.clone();
    wireplumber.extend_from_slice(b"/.config/wireplumber");
    let mut paths = vec![wireplumber, b"/etc/wireplumber".to_vec()];
    let extra = env::var_or_empty("XDG_DATA_DIRS");
    if !extra.is_empty() {
        paths.push(extra);
    }
    if search_paths(&paths, b"restore-target") {
        report.pass(b"restore-target=false present in wireplumber config");
    } else {
        report.warn(
            b"restore-target=false NOT found in wireplumber config (re-link guard may be inactive)",
        );
    }

    if legacy_unit_present() {
        report.warn(b"legacy unit rme-route-all/aes-dedup present");
    } else {
        report.pass(b"no rme-route-all / aes-dedup unit");
    }
    if Cmd::new("pgrep")
        .args(["-af", "rme-route-all|aes-dedup"])
        .stdout(Sink::Null)
        .stderr(Sink::Null)
        .diag(&program, 163)
        .run()
        .code
        == 0
    {
        report.warn(b"rme-route-all / aes-dedup process running");
    } else {
        report.pass(b"no rme-route-all / aes-dedup process");
    }

    let mpd = Cmd::new("systemctl")
        .args(["show", "mpd"])
        .stdout(Sink::Capture)
        .stderr(Sink::Null)
        .diag(&program, 169)
        .run();
    if text::contains(&mpd.stdout, b"PULSE_SINK=game-stereo") {
        report.pass(b"mpd pinned to game-stereo (PULSE_SINK)");
    } else {
        report.warn(b"mpd not pinned to game-stereo (PULSE_SINK missing)");
    }

    let mut footer = b"==== audio-diag done: ".to_vec();
    footer.extend_from_slice(report.failures.to_string().as_bytes());
    footer.extend_from_slice(b" FAIL(s) ====\n");
    env::out(&footer);

    if report.essential > 0 {
        std::process::exit(2);
    }
    std::process::exit(if report.failures == 0 { 0 } else { 1 });
}

struct Report {
    failures: u32,
    essential: u32,
}

impl Report {
    fn pass(&self, message: &[u8]) {
        self.line(b"ok    ", message);
    }

    fn warn(&self, message: &[u8]) {
        self.line(b"WARN  ", message);
    }

    fn fail(&mut self, message: &[u8]) {
        self.failures += 1;
        self.line(b"FAIL  ", message);
    }

    fn info(&self, message: &[u8]) {
        self.line(b"      ", message);
    }

    fn line(&self, prefix: &[u8], message: &[u8]) {
        let mut line = prefix.to_vec();
        line.extend_from_slice(message);
        line.push(b'\n');
        env::out(&line);
    }

    /// `need TOOL`: a missing essential tool warns and sets the exit-2 flag.
    fn need(&mut self, tool: &[u8]) -> bool {
        if env::which(tool) {
            return true;
        }
        self.essential += 1;
        let mut message = b"tool '".to_vec();
        message.extend_from_slice(tool);
        message.extend_from_slice(b"' not found");
        self.warn(&message);
        false
    }
}

/// `pw-link -l 2>/dev/null | awk '...' | sort -u`: each entry is `source|dest`.
fn collect_links(program: &[u8]) -> Vec<Vec<u8>> {
    let output = Cmd::new("pw-link")
        .arg("-l")
        .stdout(Sink::Capture)
        .stderr(Sink::Null)
        .diag(program, 46)
        .run()
        .stdout;
    let mut entries: Vec<Vec<u8>> = Vec::new();
    let mut current: Option<Vec<u8>> = None;
    for line in output.split(|byte| *byte == b'\n') {
        if line.is_empty() {
            continue;
        }
        if line[0] != b' ' {
            current = Some(line.to_vec());
            continue;
        }
        if let Some(target) = strip_arrow(line, b"|->") {
            if let Some(source) = &current {
                let mut entry = source.clone();
                entry.push(b'|');
                entry.extend_from_slice(&target);
                entries.push(entry);
            }
        } else if let Some(source) = strip_arrow(line, b"|<-") {
            if let Some(target) = &current {
                let mut entry = source;
                entry.push(b'|');
                entry.extend_from_slice(target);
                entries.push(entry);
            }
        }
    }
    entries.sort();
    entries.dedup();
    entries
}

/// `sub(/^[[:space:]]*\|->[[:space:]]*/, "", line)`, the arrow trimmed.
fn strip_arrow(line: &[u8], arrow: &[u8]) -> Option<Vec<u8>> {
    let mut index = 0;
    while index < line.len() && line[index].is_ascii_whitespace() {
        index += 1;
    }
    if !line[index..].starts_with(arrow) {
        return None;
    }
    index += arrow.len();
    while index < line.len() && line[index].is_ascii_whitespace() {
        index += 1;
    }
    Some(line[index..].to_vec())
}

/// `awk -F'|' -v p=... '$2 == p { print $1 }'`.
fn sources_of<'a>(links: &'a [Vec<u8>], port: &[u8]) -> Vec<Vec<u8>> {
    links
        .iter()
        .filter_map(|line| {
            let fields = link_fields(line);
            if fields.len() >= 2 && fields[1] == port {
                Some(fields[0].to_vec())
            } else {
                None
            }
        })
        .collect()
}

fn link_fields(line: &[u8]) -> Vec<&[u8]> {
    line.split(|byte| *byte == b'|').collect()
}

fn after_last_colon(port: &[u8]) -> &[u8] {
    match port.iter().rposition(|byte| *byte == b':') {
        Some(position) => &port[position + 1..],
        None => port,
    }
}

/// `:playback_AUX[0-9]+$`.
fn aux_digits(destination: &[u8]) -> bool {
    const MARKER: &[u8] = b":playback_AUX";
    let Some(position) = destination
        .windows(MARKER.len())
        .rposition(|window| window == MARKER)
    else {
        return false;
    };
    let digits = &destination[position + MARKER.len()..];
    !digits.is_empty() && digits.iter().all(|byte| byte.is_ascii_digit())
}

/// Join with newlines and strip trailing newlines, the `$(...)` shape.
fn join_lines(lines: &[Vec<u8>]) -> Vec<u8> {
    let mut text = Vec::new();
    for (index, line) in lines.iter().enumerate() {
        if index > 0 {
            text.push(b'\n');
        }
        text.extend_from_slice(line);
    }
    text
}

fn strip_join(lines: &[Vec<u8>]) -> Vec<u8> {
    let joined = join_lines(lines);
    text::strip_trailing_newlines(&joined).to_vec()
}

/// `wpctl status 2>/dev/null`.
fn wpctl_status(program: &[u8], line: u32) -> Vec<u8> {
    Cmd::new("wpctl")
        .arg("status")
        .stdout(Sink::Capture)
        .stderr(Sink::Null)
        .diag(program, line)
        .run()
        .stdout
}

/// `sed -n '/<pattern>/{s/^[^0-9]*\([0-9]\+\).*/\1/p;q}'`: the first digit run
/// of the first matching line, or empty.
fn extract_id(status: &[u8], needles: &[&[u8]]) -> Vec<u8> {
    for line in status.split(|byte| *byte == b'\n') {
        if ordered_contains(line, needles) {
            return first_digits(line);
        }
    }
    Vec::new()
}

fn first_digits(line: &[u8]) -> Vec<u8> {
    let Some(start) = line.iter().position(|byte| byte.is_ascii_digit()) else {
        return Vec::new();
    };
    line[start..]
        .iter()
        .take_while(|byte| byte.is_ascii_digit())
        .copied()
        .collect()
}

/// `.*A.*B.*`: `needles` appear in order.
fn ordered_contains(line: &[u8], needles: &[&[u8]]) -> bool {
    let mut rest = line;
    for needle in needles {
        match text::find(rest, needle) {
            Some(position) => rest = &rest[position + needle.len()..],
            None => return false,
        }
    }
    true
}

/// `wpctl get-volume ID 2>/dev/null`.
fn get_volume(program: &[u8], id: &[u8], line: u32) -> Vec<u8> {
    Cmd::new("wpctl")
        .arg("get-volume")
        .arg_bytes(id)
        .stdout(Sink::Capture)
        .stderr(Sink::Null)
        .diag(program, line)
        .run()
        .stdout
}

/// `sed -n 's/.*Volume: \([0-9.]*\).*/\1/p'` over the get-volume output.
fn volume_value(output: &[u8]) -> Vec<u8> {
    let mut collected = Vec::new();
    for line in output.split(|byte| *byte == b'\n') {
        // sed's leading `.*` is greedy: the last "Volume: " in the line wins.
        let Some(position) = line
            .windows(b"Volume: ".len())
            .rposition(|window| window == b"Volume: ")
        else {
            continue;
        };
        let start = position + b"Volume: ".len();
        let mut end = start;
        while end < line.len() && (line[end].is_ascii_digit() || line[end] == b'.') {
            end += 1;
        }
        collected.extend_from_slice(&line[start..end]);
        collected.push(b'\n');
    }
    text::strip_trailing_newlines(&collected).to_vec()
}

/// The `vol_ok` function: `Volume: 1.00`, not muted, within 0.999..=1.001.
fn vol_ok(program: &[u8], id: &[u8]) -> bool {
    let value = volume_value(&get_volume(program, id, 107));
    let muted_output = get_volume(program, id, 108);
    let muted = contains_case_insensitive(&muted_output, b"MUTED");
    let value = if value.is_empty() {
        b"0".to_vec()
    } else {
        value
    };
    let number = text::awk_number(&value);
    number >= 0.999 && number <= 1.001 && !muted
}

fn contains_case_insensitive(haystack: &[u8], needle: &[u8]) -> bool {
    if needle.is_empty() {
        return true;
    }
    haystack.windows(needle.len()).any(|window| {
        window
            .iter()
            .zip(needle.iter())
            .all(|(left, right)| left.eq_ignore_ascii_case(right))
    })
}

/// `grep -A2 "name='Chn'" | grep -o ': values=[0-9]*' | cut -d= -f2`.
fn mixer_values(contents: &[u8]) -> Vec<Vec<u8>> {
    let lines: Vec<&[u8]> = contents.split(|byte| *byte == b'\n').collect();
    let mut included = vec![false; lines.len()];
    for (index, line) in lines.iter().enumerate() {
        if text::contains(line, b"name='Chn'") {
            for offset in 0..=2 {
                if let Some(slot) = included.get_mut(index + offset) {
                    *slot = true;
                }
            }
        }
    }
    let mut values = Vec::new();
    for (index, line) in lines.iter().enumerate() {
        if !included[index] {
            continue;
        }
        let mut offset = 0;
        while let Some(position) = text::find(&line[offset..], b": values=") {
            let start = offset + position + b": values=".len();
            let mut end = start;
            while end < line.len() && line[end].is_ascii_digit() {
                end += 1;
            }
            values.push(line[start..end].to_vec());
            offset = start;
            if offset >= line.len() {
                break;
            }
        }
    }
    values
}

/// `grep -rlq 'restore-target' PATH... 2>/dev/null`.
fn search_paths(paths: &[Vec<u8>], needle: &[u8]) -> bool {
    for path in paths {
        if path.is_empty() {
            continue;
        }
        if path_contains(Path::new(OsStr::from_bytes(path)), needle) {
            return true;
        }
    }
    false
}

/// `grep -r`: the command-line operand may be a symlink (followed), but
/// symlinks met during the walk are skipped.
fn path_contains(path: &Path, needle: &[u8]) -> bool {
    let metadata = match fs::metadata(path) {
        Ok(metadata) => metadata,
        Err(_) => return false,
    };
    if metadata.is_dir() {
        return directory_contains(path, needle);
    }
    if metadata.is_file() {
        return file_contains(path, needle);
    }
    false
}

fn directory_contains(directory: &Path, needle: &[u8]) -> bool {
    let entries = match fs::read_dir(directory) {
        Ok(entries) => entries,
        Err(_) => return false,
    };
    for entry in entries.flatten() {
        let file_type = match entry.file_type() {
            Ok(file_type) => file_type,
            Err(_) => continue,
        };
        if file_type.is_dir() {
            if directory_contains(&entry.path(), needle) {
                return true;
            }
        } else if file_type.is_file() && file_contains(&entry.path(), needle) {
            return true;
        }
    }
    false
}

fn file_contains(path: &Path, needle: &[u8]) -> bool {
    match fs::read(path) {
        Ok(bytes) => text::contains(&bytes, needle),
        Err(_) => false,
    }
}

/// The `nullglob` array `/etc/systemd/user/*rme-route-all* /etc/systemd/user/*aes-dedup*`.
fn legacy_unit_present() -> bool {
    let entries = match fs::read_dir("/etc/systemd/user") {
        Ok(entries) => entries,
        Err(_) => return false,
    };
    entries.flatten().any(|entry| {
        let name = entry.file_name();
        let bytes = env::os_bytes(&name);
        !bytes.starts_with(b".")
            && (text::contains(bytes, b"rme-route-all") || text::contains(bytes, b"aes-dedup"))
    })
}
