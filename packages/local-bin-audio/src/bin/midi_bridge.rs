//! Rust port of `packages/local-bin/bin/midi-bridge`.
//!
//! Connects SuperCollider's `out0` MIDI port to Renoise (if its ALSA client is
//! present) and to `Midi Through` (the legacy Vital route). `aconnect` stays a
//! subprocess with the original argv; the `aconnect -l` parsing that used to be
//! `awk` (client headers, port lines, first field) is native. `set -e` is kept:
//! a failing `aconnect -l` ends the script with that status.

use local_bin_audio::env;
use local_bin_audio::proc::{Cmd, Sink};
use local_bin_audio::text;

fn main() {
    let mut arguments = std::env::args_os();
    let argv0 = arguments.next().unwrap_or_default();
    let program = env::invocation_name(&argv0);

    let listing = aconnect(&program, 8);
    let sc = match client_id(&listing, &[b"SuperCollider"]) {
        Some(id) => id,
        None => {
            env::err_str("midi-bridge: no SuperCollider MIDI client (engine not started?)\n");
            std::process::exit(1);
        }
    };

    let listing = aconnect(&program, 33);
    match client_id(&listing, &[b"Renoise", b"renoise"]) {
        Some(renoise) => link(
            &program,
            &sc,
            &renoise,
            &[b"midi in", b"Midi In", b"in0"],
            b"Renoise",
        ),
        None => env::out_str("midi-bridge: Renoise not running — SC MIDI -> Renoise skipped\n"),
    }

    let listing = aconnect(&program, 41);
    match client_id(&listing, &[b"Midi Through"]) {
        Some(through) => link(
            &program,
            &sc,
            &through,
            &[b"Midi Through Port-0"],
            b"Vital (Midi Through)",
        ),
        None => env::out_str("midi-bridge: Vital not running — SC MIDI -> Midi Through skipped\n"),
    }
}

/// `aconnect -l` under `set -e -o pipefail`: the captured listing or the
/// script's exit status.
fn aconnect(program: &[u8], line: u32) -> Vec<u8> {
    let outcome = Cmd::new("aconnect")
        .arg("-l")
        .stdout(Sink::Capture)
        .diag(program, line)
        .run();
    if outcome.code != 0 {
        std::process::exit(outcome.code);
    }
    outcome.stdout
}

/// `link <dst> <patterns> <label>`: resolve both port ids and connect them.
fn link(program: &[u8], sc: &[u8], dst: &[u8], patterns: &[&[u8]], label: &[u8]) {
    let listing = aconnect(program, 18);
    let destination_port = client_port(&listing, dst, patterns);
    let listing = aconnect(program, 20);
    let source_port = client_port(&listing, sc, &[b"out0"]);

    if source_port.is_none() || destination_port.is_none() {
        let mut message = b"midi-bridge: ".to_vec();
        message.extend_from_slice(label);
        message.extend_from_slice(b" skipped (ports not found: SC out0=[");
        message.extend_from_slice(source_port.as_deref().unwrap_or_default());
        message.extend_from_slice(b"], ");
        message.extend_from_slice(label);
        message.extend_from_slice(b" in=[");
        message.extend_from_slice(destination_port.as_deref().unwrap_or_default());
        message.extend_from_slice(b"])\n");
        env::out(&message);
        return;
    }

    let mut source = sc.to_vec();
    source.push(b':');
    source.extend_from_slice(source_port.as_deref().unwrap_or_default());
    let mut target = dst.to_vec();
    target.push(b':');
    target.extend_from_slice(destination_port.as_deref().unwrap_or_default());

    // `err=$(aconnect A B 2>&1)`: both streams are captured; aconnect writes
    // its diagnostics on stderr, so the concatenation reproduces the payload.
    let outcome = Cmd::new("aconnect")
        .arg_bytes(&source)
        .arg_bytes(&target)
        .stdout(Sink::Capture)
        .stderr(Sink::Capture)
        .diag(program, 25)
        .run();
    let mut combined = outcome.stdout;
    combined.extend_from_slice(&outcome.stderr);
    let combined = text::strip_trailing_newlines(&combined);

    if outcome.code == 0 {
        let mut message = b"midi-bridge: connected SC MIDI -> ".to_vec();
        message.extend_from_slice(label);
        message.push(b'\n');
        env::out(&message);
    } else {
        let mut message = b"midi-bridge: failed to connect SC MIDI -> ".to_vec();
        message.extend_from_slice(label);
        message.extend_from_slice(b": ");
        message.extend_from_slice(combined);
        message.push(b'\n');
        env::err(&message);
    }
}

/// `awk '/^client [0-9]+: .NAME./ {...}'`: the first client whose `-l` line
/// carries the name with one character on each side (the quotes in real
/// listings), as the client number.
fn client_id(listing: &[u8], names: &[&[u8]]) -> Option<Vec<u8>> {
    for line in listing.split(|byte| *byte == b'\n') {
        let Some(rest) = line.strip_prefix(b"client ") else {
            continue;
        };
        let digits = rest
            .iter()
            .position(|byte| !byte.is_ascii_digit())
            .unwrap_or(rest.len());
        if digits == 0 {
            continue;
        }
        let Some(after) = rest[digits..].strip_prefix(b": ") else {
            continue;
        };
        if dot_name_dot(after, names) {
            return Some(rest[..digits].to_vec());
        }
    }
    None
}

/// The `.$name.` part of the awk pattern: an occurrence with at least one
/// character before and after it on the line.
fn dot_name_dot(rest: &[u8], names: &[&[u8]]) -> bool {
    for name in names {
        let mut offset = 0;
        while let Some(position) = text::find(&rest[offset..], name) {
            let absolute = offset + position;
            if absolute >= 1 && absolute + name.len() < rest.len() {
                return true;
            }
            offset = absolute + 1;
        }
    }
    false
}

/// `awk -v c=ID '... $0 ~ "client " c ":" {inside=1} inside && $0 ~ p {print $1; exit}'`
/// with `p` an alternation of literal substrings.
fn client_port(listing: &[u8], client: &[u8], patterns: &[&[u8]]) -> Option<Vec<u8>> {
    let mut header = b"client ".to_vec();
    header.extend_from_slice(client);
    header.push(b':');
    let mut inside = false;
    for line in listing.split(|byte| *byte == b'\n') {
        if text::contains(line, &header) {
            inside = true;
        }
        if inside && patterns.iter().any(|pattern| text::contains(line, pattern)) {
            return text::words(line).first().map(|word| word.to_vec());
        }
    }
    None
}
