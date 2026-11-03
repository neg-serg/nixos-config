//! Rust port of `packages/local-bin/bin/read_documents`.
//!
//! `fd` lists the PDF/DJVU/EPUB files one level below `~/dw`, vicinae's dmenu
//! picks one, and zathura opens it. The original always runs the three
//! `command -v` probes and warns for each missing tool; the pipeline still runs
//! and the selection ends up empty, which is why a cancel and a missing tool
//! both exit 1.

#![forbid(unsafe_code)]

use std::ffi::OsString;
use std::os::unix::ffi::{OsStrExt, OsStringExt};

use local_bin_zsh::{capture, err_str, home, out_str, raw_args, run, Site, Stderr, Stdin, Stdout};

const USAGE: &str = include_str!("read_documents_usage.txt");
const PROMPT: &str = "⟬doc⟭ ❯>";

fn main() {
    let arguments = raw_args();
    if let Some(first) = arguments.first() {
        if matches!(first.as_bytes(), b"-h" | b"--help") {
            out_str(USAGE);
            return;
        }
    }

    if local_bin_zsh::which_str("fd").is_none() {
        err_str("read_documents: fd not found\n");
    }
    if local_bin_zsh::which_str("vicinae").is_none() {
        err_str("read_documents: vicinae not found\n");
    }
    if local_bin_zsh::which_str("zathura").is_none() {
        err_str("read_documents: zathura not found\n");
    }

    // `~/dw/` keeps its trailing slash: it is a literal argv element.
    let mut directory = home();
    directory.push("/dw/");
    let fd_arguments = [
        OsString::from("."),
        directory,
        OsString::from("-d"),
        OsString::from("1"),
        OsString::from("-t"),
        OsString::from("f"),
        OsString::from("-e"),
        OsString::from("pdf"),
        OsString::from("-e"),
        OsString::from("djvu"),
        OsString::from("-e"),
        OsString::from("epub"),
    ];
    let listed = capture(
        Site::Top(13),
        "fd",
        &fd_arguments,
        Stdin::Null,
        Stderr::Null,
    );
    let selection = capture(
        Site::Top(14),
        "vicinae",
        &[
            OsString::from("dmenu"),
            OsString::from("-p"),
            OsString::from(PROMPT),
        ],
        Stdin::Bytes(listed.stdout),
        Stderr::Inherit,
    )
    .text();

    // `[ -n "$sel" ] && zathura "$sel"` — the whole selection is one argument,
    // newlines included, exactly as the unquoted-variable-free shell passes it.
    if selection.is_empty() {
        std::process::exit(1);
    }
    let status = run(
        Site::Top(15),
        "zathura",
        &[OsString::from_vec(selection)],
        Stdin::Inherit,
        Stdout::Inherit,
        Stderr::Inherit,
    );
    std::process::exit(status);
}
