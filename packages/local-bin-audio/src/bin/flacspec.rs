//! Rust port of `packages/local-bin/bin/flacspec`.
//!
//! Renders a spectrogram for every `*.flac` in the current directory with
//! `sox` and moves the PNG into `Spectrograms/`. The `*.flac` expansion and the
//! `${file%.*}.flac.png` name (`a.flac` -> `a.flac.png`) are native; `sox`,
//! `mkdir` and `mv` stay subprocesses with the original argv. The loop keeps
//! the shell's exit status: the last processed file decides it.

use std::ffi::OsStr;
use std::fs;
use std::os::unix::ffi::OsStrExt;

use local_bin_audio::env;
use local_bin_audio::helptext::FLACSPEC_USAGE;
use local_bin_audio::proc::Cmd;

fn main() {
    let mut arguments = std::env::args_os();
    let argv0 = arguments.next().unwrap_or_default();
    let program = env::invocation_name(&argv0);

    // `help_from_header 2 2 "$@"`: only `-h`/`--help` as the first argument.
    if let Some(first) = arguments.next() {
        let first = env::os_bytes(&first);
        if first == b"-h" || first == b"--help" {
            env::out_str(FLACSPEC_USAGE);
            return;
        }
    }

    // `need sox` warns (and keeps going) when the tool is missing.
    if !env::which(b"sox") {
        env::err_str("flacspec: missing sox\n");
    }

    // `mkdir -p -- Spectrograms` stays external; a failure does not abort the
    // shell original (it has no `set -e`), so the status is discarded.
    let _ = Cmd::new("mkdir")
        .arg("-p")
        .arg("--")
        .arg("Spectrograms")
        .diag(&program, 13)
        .run();

    // `for file in *.flac`: no dotfiles, only regular files (symlinks followed
    // by `[ -f ]`), expanded in the C-locale byte order the tests use.
    let mut files: Vec<Vec<u8>> = Vec::new();
    if let Ok(entries) = fs::read_dir(".") {
        for entry in entries.flatten() {
            let name = entry.file_name();
            let bytes = env::os_bytes(&name);
            if bytes.first() == Some(&b'.') || !bytes.ends_with(b".flac") {
                continue;
            }
            files.push(bytes.to_vec());
        }
    }
    files.sort();

    let mut status = 0;
    for name in &files {
        let path = std::path::Path::new(OsStr::from_bytes(name));
        if !fs::metadata(path)
            .map(|meta| meta.is_file())
            .unwrap_or(false)
        {
            // `[ -f "$file" ] || continue` leaves the loop status at 0.
            status = 0;
            continue;
        }
        // `${file%.*}.flac.png`: stripping the shortest `.*` suffix from a
        // name that ends in `.flac` leaves the stem, then the suffix is added.
        let stem_length = name.len() - b".flac".len();
        let mut outfile = name[..stem_length].to_vec();
        outfile.extend_from_slice(b".flac.png");

        let sox = Cmd::from_bytes(b"sox")
            .arg_bytes(name)
            .arg("-n")
            .arg("spectrogram")
            .arg("-o")
            .arg_bytes(&outfile)
            .diag(&program, 17)
            .run();
        status = sox.code;
        if sox.code == 0 {
            let moved = Cmd::new("mv")
                .arg("--")
                .arg_bytes(&outfile)
                .arg("Spectrograms/")
                .diag(&program, 17)
                .run();
            status = moved.code;
        }
    }
    std::process::exit(status);
}
