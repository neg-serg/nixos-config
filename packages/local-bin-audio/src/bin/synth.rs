//! Rust port of `packages/local-bin/bin/synth`.
//!
//! Run-or-raise a synth: Surge XT standalone, Vital (user service) or Renoise
//! for yabridge VSTs. `pgrep`, `systemctl`, `nohup` and `hyprctl` stay
//! subprocesses with the original argv. The `sed` name normalisation is native,
//! and so is the `hyprctl clients -j | jq ... | head -1` address selection: the
//! script only ever calls it with anchored class prefixes (`^Surge`,
//! `^Renoise`) plus an optional title substring, which `local_bin_audio::json` reads
//! directly instead of spawning `jq`.

use local_bin_audio::env;
use local_bin_audio::json;
use local_bin_audio::proc::{Cmd, Input, Sink};
use local_bin_audio::text;

fn main() {
    let mut arguments = std::env::args_os();
    let argv0 = arguments.next().unwrap_or_default();
    let program = env::invocation_name(&argv0);
    let name = match arguments.next() {
        Some(value) if !env::os_bytes(&value).is_empty() => env::os_bytes(&value).to_vec(),
        _ => env::parameter_error(&program, 13, b"1", b"usage: synth <name>"),
    };
    let plain = plain_name(&name);

    match plain.as_slice() {
        b"Surge_XT" | b"SurgeXT" | b"surge" => {
            if pgrep(&program, b"/bin/Surge XT", 30) {
                if raise_window(&program, b"^Surge", b"Surge XT") {
                    env::out_str("synth: Surge XT raised\n");
                } else {
                    env::out_str("synth: Surge XT already running\n");
                }
            } else {
                env::out_str("synth: starting Surge XT standalone ...\n");
                start_background(b"/run/current-system/sw/bin/Surge XT", &program, 34);
                env::out_str("synth: Surge XT started\n");
            }
        }
        b"Vital" | b"vital" => {
            if pgrep(&program, b"/bin/Vital", 39) {
                env::out_str("synth: Vital already running\n");
            } else {
                env::out_str("synth: starting Vital (vital-standalone) ...\n");
                let started = Cmd::new("systemctl")
                    .args(["--user", "start", "vital-standalone"])
                    .diag(&program, 43)
                    .run();
                if started.code != 0 {
                    std::process::exit(started.code);
                }
                env::out_str("synth: Vital started\n");
            }
        }
        _ => {
            if pgrep(&program, b"renoise", 51) {
                if raise_window(&program, b"^Renoise", b"") {
                    let mut message = b"synth: Renoise raised (".to_vec();
                    message.extend_from_slice(&name);
                    message.extend_from_slice(b" as VST)\n");
                    env::out(&message);
                } else {
                    let mut message = b"synth: Renoise already running (".to_vec();
                    message.extend_from_slice(&name);
                    message.extend_from_slice(b" as VST)\n");
                    env::out(&message);
                }
            } else {
                let mut starting = b"synth: starting Renoise (".to_vec();
                starting.extend_from_slice(&name);
                starting.extend_from_slice(b" via yabridge as regular VST3) ...\n");
                env::out(&starting);
                start_background(b"renoise", &program, 55);
                let mut started = "synth: Renoise started — add ".as_bytes().to_vec();
                started.extend_from_slice(&name);
                started.extend_from_slice(b" on a track FX chain (VST3)\n");
                env::out(&started);
            }
        }
    }
}

/// `plain=$(printf '%s' "$name" | sed 's/^vst[23]://; s/  */_/g')`.
fn plain_name(name: &[u8]) -> Vec<u8> {
    let mut rest = name;
    if let Some(stripped) = rest.strip_prefix(b"vst2:") {
        rest = stripped;
    } else if let Some(stripped) = rest.strip_prefix(b"vst3:") {
        rest = stripped;
    }
    let mut result = Vec::with_capacity(rest.len());
    let mut index = 0;
    while index < rest.len() {
        if rest[index] == b' ' {
            result.push(b'_');
            while index < rest.len() && rest[index] == b' ' {
                index += 1;
            }
        } else {
            result.push(rest[index]);
            index += 1;
        }
    }
    result
}

/// `pgrep -f PATTERN >/dev/null 2>&1`.
fn pgrep(program: &[u8], pattern: &[u8], line: u32) -> bool {
    Cmd::new("pgrep")
        .arg("-f")
        .arg_bytes(pattern)
        .stdout(Sink::Null)
        .stderr(Sink::Null)
        .diag(program, line)
        .run()
        .code
        == 0
}

/// `nohup PROGRAM >/dev/null 2>&1 &`: the tool is still spawned through
/// `nohup` (same argv), so signal dispositions match the original.
fn start_background(tool: &[u8], program: &[u8], line: u32) {
    let _ = Cmd::new("nohup")
        .arg_bytes(tool)
        .stdin(Input::Null)
        .stdout(Sink::Null)
        .stderr(Sink::Null)
        .diag(program, line)
        .spawn_async();
}

/// `raise_window CLASS TITLE`: focus the first window whose class matches the
/// anchored prefix and whose title contains TITLE; returns whether one was
/// found and focused.
fn raise_window(program: &[u8], class: &[u8], title: &[u8]) -> bool {
    if !env::which(b"hyprctl") {
        return false;
    }
    let clients = Cmd::new("hyprctl")
        .args(["clients", "-j"])
        .stdout(Sink::Capture)
        .stderr(Sink::Null)
        .diag(program, 21)
        .run();
    let address = match json::parse(&clients.stdout) {
        Some(value) => first_matching_address(&value, class, title),
        None => None,
    };
    let Some(address) = address else {
        return false;
    };
    if address.is_empty() {
        return false;
    }
    let mut target = b"address:".to_vec();
    target.extend_from_slice(&address);
    let _ = Cmd::new("hyprctl")
        .arg("dispatch")
        .arg("focuswindow")
        .arg_bytes(&target)
        .stdout(Sink::Null)
        .stderr(Sink::Null)
        .diag(program, 23)
        .run();
    true
}

/// The `select(...) | .address` part of the original jq filter, limited to the
/// forms the script passes: `^PREFIX` class tests and a literal title substring.
fn first_matching_address(value: &json::Value, class: &[u8], title: &[u8]) -> Option<Vec<u8>> {
    for entry in value.as_array()? {
        let Some(entry_class) = entry.get(b"class").and_then(|value| value.as_bytes()) else {
            continue;
        };
        if !class_matches(class, entry_class) {
            continue;
        }
        if !title.is_empty() {
            let entry_title = entry
                .get(b"title")
                .and_then(|value| value.as_bytes())
                .unwrap_or_default();
            if !text::contains(entry_title, title) {
                continue;
            }
        }
        let Some(address) = entry.get(b"address").and_then(|value| value.as_bytes()) else {
            continue;
        };
        return Some(address.to_vec());
    }
    None
}

fn class_matches(pattern: &[u8], class: &[u8]) -> bool {
    match pattern.strip_prefix(b"^") {
        Some(prefix) => class.starts_with(prefix),
        None => text::contains(class, pattern),
    }
}
