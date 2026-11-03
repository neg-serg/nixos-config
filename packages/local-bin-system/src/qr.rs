//! qr: quick QR and screenshot helper.
//!
//! Port of `packages/local-bin/bin/qr` (POSIX sh). `grim`, `slurp`,
//! `wl-copy`, `notify-send`, `qrencode`, `zbarimg` and `convert` keep their
//! original argv and order. The temporary file `mktemp -t maimscript-XXXXXX`
//! produced is created natively (still under `TMPDIR`) and cleaned up on every
//! path the original cleaned it up on.

use std::fs;
use std::io::Write;
use std::os::unix::fs::PermissionsExt;
use std::process::{Command, Stdio};

use local_bin_system as sh;

const USAGE: &str = "qr: quick QR and screenshot helper
Usage:
  qr gen          # generate QR from current selection to ~/tmp/qrcode.png
  qr select       # select region → clipboard (PNG) + notify
  qr qr           # select region → scan QR → copy result + notify
  qr              # screenshot entire desktop → clipboard (PNG) + notify
  qr -h|--help    # this help
";

fn prog() -> String {
    sh::prog("qr")
}

fn notify(title: &str, body: &str) -> i32 {
    match Command::new("notify-send").args([title, body]).status() {
        Ok(status) => sh::status_code(status),
        Err(_) => 127,
    }
}

fn capture_trimmed(program: &str, arguments: &[&str]) -> String {
    match sh::capture(program, arguments, false) {
        Some(output) => String::from_utf8_lossy(&output.stdout)
            .trim_end_matches('\n')
            .to_string(),
        None => String::new(),
    }
}

/// `clip [-t MIME]`: write stdin to the Wayland clipboard.
fn clip(mimetype: Option<&str>, payload: &[u8]) -> i32 {
    let mut command = Command::new("wl-copy");
    if let Some(mimetype) = mimetype {
        command.args(["--type", mimetype]);
    }
    let mut child = match command
        .stdin(Stdio::piped())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .spawn()
    {
        Ok(child) => child,
        Err(_) => return 127,
    };
    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(payload);
    }
    match child.wait() {
        Ok(status) => sh::status_code(status),
        Err(_) => 1,
    }
}

/// `grim -g "$(slurp)" -` piped into the clipboard.
fn region_screenshot() {
    let geometry = capture_trimmed("slurp", &[]);
    let output = sh::capture("grim", &["-g", &geometry, "-"], false)
        .map(|captured| captured.stdout)
        .unwrap_or_default();
    let _ = clip(Some("image/png"), &output);
}

fn temp_file() -> String {
    use std::io::Read;
    let directory = sh::env_or("TMPDIR", "/tmp");
    for _ in 0..100 {
        let suffix: String = {
            let mut bytes = [0u8; 6];
            let random = fs::File::open("/dev/urandom")
                .and_then(|mut file| file.read_exact(&mut bytes).map(|_| bytes));
            let bytes = random.unwrap_or([0u8; 6]);
            bytes
                .iter()
                .map(|byte| {
                    const ALPHABET: &[u8] =
                        b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
                    ALPHABET[*byte as usize % ALPHABET.len()] as char
                })
                .collect()
        };
        let candidate = format!("{directory}/maimscript-{suffix}");
        match fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&candidate)
        {
            Ok(_) => {
                let _ = fs::set_permissions(&candidate, fs::Permissions::from_mode(0o600));
                return candidate;
            }
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(_) => return candidate,
        }
    }
    format!("{directory}/maimscript-XXXXXX")
}

fn command_gen() {
    sh::need(&prog(), "qrencode");
    let home = sh::home();
    let _ = fs::create_dir_all(format!("{home}/tmp"));
    let text = capture_trimmed("wl-paste", &[]);
    let destination = format!("{home}/tmp/qrcode.png");
    let output_file = match fs::File::create(&destination) {
        Ok(file) => file,
        Err(_) => {
            sh::err_line(&format!("qr: cannot write {destination}"));
            std::process::exit(1);
        }
    };
    let status = Command::new("qrencode")
        .args(["-l", "H", "-d", "75", "-s", "10", "-o", "-", &text])
        .stdout(Stdio::from(output_file))
        .stderr(Stdio::inherit())
        .status();
    match status {
        Ok(status) => std::process::exit(sh::status_code(status)),
        Err(_) => std::process::exit(127),
    }
}

fn command_scan() {
    sh::need(&prog(), "zbarimg");
    let temporary = temp_file();
    let geometry = capture_trimmed("slurp", &[]);
    let screenshot = Command::new("grim")
        .args(["-g", &geometry, &temporary])
        .status();
    match screenshot {
        Ok(status) if status.success() => {}
        _ => {
            let _ = fs::remove_file(&temporary);
            std::process::exit(1);
        }
    }
    let scan = sh::capture("zbarimg", &["--quiet", "--raw", &temporary], false)
        .map(|captured| String::from_utf8_lossy(&captured.stdout).replace('\n', ""))
        .unwrap_or_default();
    if scan.is_empty() {
        notify("Screenshot", "No scan data found");
    } else {
        let _ = clip(None, format!("{scan}\n").as_bytes());
        if sh::which("convert").is_some() {
            let _ = sh::run_inherit("convert", &[&temporary, "-resize", "75x75", &temporary]);
        }
        let body = format!("{scan}\\n(copied to clipboard)");
        let _ = Command::new("notify-send")
            .args(["-i", &temporary, "QR", &body])
            .status();
    }
    let _ = fs::remove_file(&temporary);
}

fn main() {
    sh::need(&prog(), "grim");
    sh::need(&prog(), "slurp");
    sh::need(&prog(), "wl-copy");

    let arguments = sh::args();
    match arguments.first().map(String::as_str).unwrap_or("") {
        "-h" | "--help" => {
            sh::out_str(USAGE);
        }
        "gen" => command_gen(),
        "select" => {
            region_screenshot();
            let status = notify("Screenshot", "Screenshot taken");
            std::process::exit(status);
        }
        "qr" => command_scan(),
        _ => {
            let output = sh::capture("grim", &["-"], false)
                .map(|captured| captured.stdout)
                .unwrap_or_default();
            let _ = clip(Some("image/png"), &output);
            let status = notify("Screenshot", "Screenshot taken");
            std::process::exit(status);
        }
    }
}
