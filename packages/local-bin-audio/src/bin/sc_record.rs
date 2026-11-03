//! Rust port of `packages/local-bin/bin/sc-record`.
//!
//! Records the SuperCollider output by tapping the `playback.game-stereo` node
//! for `secs` seconds. `pw-link` (the engine probe) and `timeout pw-record`
//! stay subprocesses with the original argv; the `${1:?}`/`${2:-60}` parameter
//! handling and the `grep '^SuperCollider:out_1'` probe are native. The shell's
//! `set -e` means a `timeout` exit (124 when the recording window elapses) ends
//! the script before the final message; the port keeps that.

use local_bin_audio::env;
use local_bin_audio::proc::{Cmd, Sink};

fn main() {
    let mut arguments = std::env::args_os();
    let argv0 = arguments.next().unwrap_or_default();
    let program = env::invocation_name(&argv0);

    let out = match arguments.next() {
        Some(value) if !env::os_bytes(&value).is_empty() => env::os_bytes(&value).to_vec(),
        _ => env::parameter_error(&program, 10, b"1", b"usage: sc-record <out.wav> [seconds]"),
    };
    let secs = match arguments.next() {
        Some(value) if !env::os_bytes(&value).is_empty() => env::os_bytes(&value).to_vec(),
        _ => b"60".to_vec(),
    };

    // `pw-link -o 2>/dev/null | grep -q '^SuperCollider:out_1'` under
    // `pipefail`: a failed `pw-link` also selects the error branch.
    let link = Cmd::new("pw-link")
        .arg("-o")
        .stdout(Sink::Capture)
        .stderr(Sink::Null)
        .diag(&program, 13)
        .run();
    let linked = link.code == 0
        && link
            .stdout
            .split(|byte| *byte == b'\n')
            .any(|line| line.starts_with(b"SuperCollider:out_1"));
    if !linked {
        env::err_str("sc-record: SuperCollider out_1 not found — engine not running?\n");
        std::process::exit(1);
    }

    let mut recording = b"sc-record: recording ".to_vec();
    recording.extend_from_slice(&secs);
    recording.extend_from_slice(b"s -> ");
    recording.extend_from_slice(&out);
    recording.push(b'\n');
    env::out(&recording);

    let status = Cmd::new("timeout")
        .arg_bytes(&secs)
        .arg("pw-record")
        .arg("--target")
        .arg("playback.game-stereo")
        .arg_bytes(&out)
        .diag(&program, 19)
        .run();
    if status.code != 0 {
        std::process::exit(status.code);
    }

    let mut done = b"sc-record: done -> ".to_vec();
    done.extend_from_slice(&out);
    done.push(b'\n');
    env::out(&done);
}
