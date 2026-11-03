//! vsmlrt-models: fetch vs-mlrt (vsncnn) ONNX models into /zero/ai.
//!
//! Port of `packages/local-bin/bin/vsmlrt-models` (POSIX sh): downloads the
//! release archive through the sing-box SOCKS5 proxy (GitHub is blocked on this
//! host), extracts it with 7zz into `$VSMLRT_MODELS` (default
//! `/zero/ai/imgproc/vsmlrt-<version>`) and prints the Ready-to-paste VapourSynth
//! snippet. The archive work stays in `curl`/`7zz`; the temp directory and the
//! cleanup are native.

use std::fs;
use std::io::Read;
use std::path::Path;
use std::process::{Command, Stdio};

use local_bin_system as sh;

fn temp_directory() -> String {
    let directory = sh::env_or("TMPDIR", "/tmp");
    for _ in 0..100 {
        let mut bytes = [0u8; 10];
        let random = fs::File::open("/dev/urandom")
            .and_then(|mut file| file.read_exact(&mut bytes).map(|_| bytes));
        let bytes = random.unwrap_or([0u8; 10]);
        let suffix: String = bytes
            .iter()
            .map(|byte| {
                const ALPHABET: &[u8] =
                    b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
                ALPHABET[*byte as usize % ALPHABET.len()] as char
            })
            .collect();
        let candidate = format!("{directory}/tmp.{suffix}");
        match fs::create_dir(&candidate) {
            Ok(()) => return candidate,
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(_) => return candidate,
        }
    }
    format!("{directory}/tmp.XXXXXXXXXX")
}

fn main() {
    let arguments = sh::args();
    let version = arguments
        .first()
        .filter(|value| !value.is_empty())
        .cloned()
        .unwrap_or_else(|| "v15.16".to_string());
    let destination = sh::env_nonempty("VSMLRT_MODELS")
        .unwrap_or_else(|| format!("/zero/ai/imgproc/vsmlrt-{version}"));
    let url = format!(
        "https://github.com/AmusementClub/vs-mlrt/releases/download/{version}/models.{version}.7z"
    );
    let temporary = temp_directory();

    sh::out_str_line(&format!("Downloading models {version} ..."));
    // GitHub is blocked on this host: go through the sing-box socks proxy.
    let downloaded = Command::new("curl")
        .args([
            "-L",
            "--fail",
            "-x",
            "socks5h://127.0.0.1:10808",
            "-o",
            &format!("{temporary}/models.7z"),
            &url,
        ])
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status();
    match downloaded {
        Ok(status) if status.success() => {}
        Ok(status) => std::process::exit(sh::status_code(status)),
        Err(_) => std::process::exit(127),
    }

    if let Err(error) = fs::create_dir_all(&destination) {
        sh::err_line(&format!(
            "mkdir: cannot create directory '{destination}': {error}"
        ));
        std::process::exit(1);
    }
    let extracted = Command::new("7zz")
        .args(["x", "-y", &format!("-o{destination}"), "models.7z"])
        .current_dir(Path::new(&temporary))
        .stdout(Stdio::null())
        .stderr(Stdio::inherit())
        .status();
    match extracted {
        Ok(status) if status.success() => {}
        Ok(status) => std::process::exit(sh::status_code(status)),
        Err(_) => std::process::exit(127),
    }
    if let Err(error) = fs::remove_dir_all(&temporary) {
        sh::err_line(&format!("rm: cannot remove '{temporary}': {error}"));
        std::process::exit(1);
    }

    sh::out_str_line(&format!("Models installed to {destination}"));
    sh::out_str_line("Example VS script (interpolation):");
    sh::out_str_line("  import vapoursynth as vs");
    sh::out_str_line(&format!(
        "  core = vs.core; core.std.LoadPlugin(path=\"{destination}/../../lib/libvsncnn.so\")"
    ));
}
