//! Rust port of `packages/local-bin/bin/unlock`.
//!
//! Unlocks the SSH keys through `expect`, feeding the passphrase from `pass`.
//! `ssh-agent`, `pass` and `expect` stay subprocesses; the `eval` of the agent's
//! `sh` output is done natively (the two exported variables are handed to the
//! children, and the agent's `echo Agent pid N;` line is printed).

#![forbid(unsafe_code)]

use local_bin_desktop::env;
use local_bin_desktop::proc::{Cmd, Sink};

fn main() {
    let mut arguments = std::env::args_os();
    let argv0 = arguments.next().unwrap_or_default();
    let program = env::invocation_name(&argv0);
    let _ = arguments;

    let mut overrides: Vec<(Vec<u8>, Vec<u8>)> = Vec::new();

    if env::var_bytes("SSH_AUTH_SOCK")
        .unwrap_or_default()
        .is_empty()
    {
        // `eval "$(ssh-agent -s)"`: assignments are exported, the trailing
        // `echo Agent pid ...;` writes to stdout.
        let agent = Cmd::new("ssh-agent")
            .arg("-s")
            .stdout(Sink::Capture)
            .diag(&program, 10)
            .run();
        for line in agent.stdout.split(|byte| *byte == b'\n') {
            if let Some((name, value)) = parse_assignment(line) {
                overrides.push((name, value));
            } else if let Some(text) = parse_echo(line) {
                env::out(&text);
                env::out(b"\n");
            }
        }
    }

    // `pp0="$(pass show ssh-key)"` — no `set -e` here, a failure leaves it empty.
    let mut passphrase = Cmd::new("pass")
        .args(["show", "ssh-key"])
        .stdout(Sink::Capture)
        .diag(&program, 15)
        .envs_from(&overrides)
        .run();
    passphrase.stdout = strip(&passphrase.stdout);

    // Work key: quiet probe first, then the value (unused, but the original
    // asks pass for it, so the side effects stay identical).
    let probe = Cmd::new("pass")
        .args(["show", "wrk/ssh-key"])
        .stdout(Sink::Null)
        .stderr(Sink::Null)
        .envs_from(&overrides)
        .run();
    if probe.code == 0 {
        let _ = Cmd::new("pass")
            .args(["show", "wrk/ssh-key"])
            .stdout(Sink::Capture)
            .diag(&program, 17)
            .envs_from(&overrides)
            .run();
    }

    // expect << EOF ... EOF (the heredoc is expanded by the shell: $HOME and
    // $pp0 are substituted here, and `\r` stays a two-byte Tcl escape).
    let mut script = Vec::new();
    script.extend_from_slice(b"    spawn ssh-add ");
    script.extend_from_slice(&env::var_or_empty("HOME"));
    script.extend_from_slice(b"/.ssh/id_neg\n");
    script.extend_from_slice(b"    expect \"Enter passphrase\"\n");
    script.extend_from_slice(b"    send \"");
    script.extend_from_slice(&passphrase.stdout);
    script.extend_from_slice(b"\\r\"\n");
    script.extend_from_slice(b"    expect eof\n");

    let outcome = Cmd::new("expect")
        .stdin(local_bin_desktop::proc::Input::Bytes(&script))
        .diag(&program, 21)
        .envs_from(&overrides)
        .run();
    std::process::exit(outcome.code);
}

/// `NAME=VALUE; export NAME;` from ssh-agent's `-s` output.
fn parse_assignment(line: &[u8]) -> Option<(Vec<u8>, Vec<u8>)> {
    let export = b"; export ";
    let position = local_bin_desktop::text::find(line, export)?;
    let assignment = &line[..position];
    let equals = assignment.iter().position(|byte| *byte == b'=')?;
    let name = &assignment[..equals];
    let value = &assignment[equals + 1..];
    let suffix = &line[position + export.len()..];
    if suffix == [name, b";"].concat() {
        Some((name.to_vec(), value.to_vec()))
    } else {
        None
    }
}

/// `echo TEXT;` from ssh-agent's `-s` output.
fn parse_echo(line: &[u8]) -> Option<Vec<u8>> {
    let rest = line.strip_prefix(b"echo ")?;
    let text = rest.strip_suffix(b";")?;
    Some(text.to_vec())
}

fn strip(bytes: &[u8]) -> Vec<u8> {
    local_bin_desktop::text::strip_trailing_newlines(bytes).to_vec()
}
