//! Rust port of `packages/local-bin/bin/jam`.
//!
//! One command for the live-coding session: Vital standalone (user service),
//! the SuperCollider scene through `sc-live`, the MIDI bridge, plus `stop` and
//! `status`. The shell's `set -e` behaviour is kept for `systemctl` and `sleep`;
//! background starts (`sc-live`, `midi-bridge` probes) do not abort. `pw-link`,
//! `pgrep`, `aconnect`, `systemctl` and `sleep` stay subprocesses with the
//! original argv.

use local_bin_audio::env;
use local_bin_audio::proc::{Cmd, Input, Sink};
use local_bin_audio::text;

fn main() {
    let mut arguments = std::env::args_os();
    let argv0 = arguments.next().unwrap_or_default();
    let program = env::invocation_name(&argv0);
    let command = arguments
        .next()
        .map(|value| env::os_bytes(&value).to_vec())
        .unwrap_or_else(|| b"start".to_vec());

    match command.as_slice() {
        b"start" | b"" => start(&program),
        b"stop" => stop(&program),
        b"status" => show_status(&program),
        _ => {
            env::err_str("usage: jam [start|stop|status]\n");
            std::process::exit(2);
        }
    }
}

fn start(program: &[u8]) {
    start_vital(program);
    start_engine(program);
    bridge(program);
    env::out_str("\n");
    env::out_str(
        "Done. Patterns live in live.scd (nvim):  Pbind / Ndef / SynthDef — send <leader>sb\n",
    );
}

fn start_vital(program: &[u8]) {
    if vital_up(program) {
        env::out_str("✓ Vital is already running\n");
        return;
    }
    env::out_str("▶ Starting Vital...\n");
    let started = Cmd::new("systemctl")
        .args(["--user", "start", "vital-standalone"])
        .diag(program, 30)
        .run();
    if started.code != 0 {
        std::process::exit(started.code);
    }
    for _ in 0..10 {
        if vital_up(program) {
            break;
        }
        let slept = Cmd::new("sleep").arg("1").diag(program, 33).run();
        if slept.code != 0 {
            std::process::exit(slept.code);
        }
    }
    if vital_up(program) {
        env::out_str("✓ Vital is ready\n");
    } else {
        env::out_str("✗ Vital did not start — systemctl --user status vital-standalone\n");
    }
}

fn start_engine(program: &[u8]) {
    if engine_up(program) {
        env::out_str("✓ The SC engine is already running (scsynth on the bus)\n");
        return;
    }
    env::out_str("▶ Opening the SuperCollider live scene (scnvim; s.boot inside)...\n");
    env::out_str("  → in nvim press <leader>sc (start sclang) and <leader>sb (boot + patterns)\n");
    let scene = bin_path(b"sc-live");
    let _ = Cmd::from_bytes(&scene)
        .stdin(Input::Null)
        .diag(program, 45)
        .spawn_async();
    let slept = Cmd::new("sleep").arg("2").diag(program, 46).run();
    if slept.code != 0 {
        std::process::exit(slept.code);
    }
    env::out_str("  (the engine comes up once s.boot runs in live.scd)\n");
}

fn bridge(program: &[u8]) {
    let bridge = bin_path(b"midi-bridge");
    let connected = Cmd::from_bytes(&bridge)
        .stdout(Sink::Null)
        .stderr(Sink::Null)
        .diag(program, 52)
        .run();
    if connected.code == 0 {
        env::out_str("✓ MIDI: SuperCollider → Midi Through → Vital\n");
    } else {
        env::out_str("⚠ The MIDI bridge did not come up — check that the engine is running\n");
    }
}

fn stop(program: &[u8]) {
    env::out_str("▶ Stopping Vital...\n");
    let _ = Cmd::new("systemctl")
        .args(["--user", "stop", "vital-standalone"])
        .stderr(Sink::Null)
        .diag(program, 82)
        .run();
    env::out_str("✓ Stopped (close the SC session in nvim: <leader>sx)\n");
}

fn show_status(program: &[u8]) {
    env::out_str("=== Vital ===\n");
    if vital_up(program) {
        env::out_str("  running\n");
    } else {
        env::out_str("  not running (jam or systemctl --user start vital-standalone)\n");
    }
    env::out_str("=== SC engine ===\n");
    if engine_up(program) {
        env::out_str("  scsynth is running (SuperCollider:out_1/2 visible)\n");
    } else {
        env::out_str("  not running (jam → live.scd → <leader>sc, <leader>sb)\n");
    }
    env::out_str("=== MIDI ===\n");
    let listing = Cmd::new("aconnect")
        .arg("-l")
        .stdout(Sink::Capture)
        .stderr(Sink::Null)
        .diag(program, 65)
        .run();
    if text::contains(&listing.stdout, b"Connecting To: 14:0") {
        env::out_str("  the bridge is connected\n");
    } else {
        env::out_str("  the bridge is NOT connected (jam)\n");
    }
}

/// `[[ "$(pw-link -o 2>/dev/null)" == *"SuperCollider:out_1"* ]]`.
fn engine_up(program: &[u8]) -> bool {
    let links = Cmd::new("pw-link")
        .arg("-o")
        .stdout(Sink::Capture)
        .stderr(Sink::Null)
        .diag(program, 18)
        .run();
    text::contains(&links.stdout, b"SuperCollider:out_1")
}

/// `pgrep -f '/bin/Vital' >/dev/null 2>&1`.
fn vital_up(program: &[u8]) -> bool {
    Cmd::new("pgrep")
        .arg("-f")
        .arg("/bin/Vital")
        .stdout(Sink::Null)
        .stderr(Sink::Null)
        .diag(program, 22)
        .run()
        .code
        == 0
}

fn bin_path(name: &[u8]) -> Vec<u8> {
    let mut path = env::var_or_empty("HOME");
    path.extend_from_slice(b"/.local/bin/");
    path.extend_from_slice(name);
    path
}
