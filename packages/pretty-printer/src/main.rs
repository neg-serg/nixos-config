//! `ppinfo` — pretty file info: size and line count per path.
//!
//! Port of the `ppinfo` entry point (`neg_pretty_printer/cli.py`) together with
//! the `FileInfoPrinter` half of the library.

#[path = "lib.rs"]
mod lib;

use std::path::Path;

fn exists_file(filename: &str) {
    let size = std::fs::metadata(filename)
        .map(|meta| meta.len())
        .unwrap_or(0);
    println!(
        "{}{}{}{}{}",
        lib::prefix(),
        lib::fancy_file(filename),
        lib::delim(),
        lib::size(&size.to_string(), None, Some("")),
        lib::filelen(&lib::wc_lines(Path::new(filename)).to_string())
    );
}

fn nonexists_file(filename: &str) {
    println!(
        "{}{}{}{}",
        lib::prefix(),
        lib::fancy_file(filename),
        lib::delim(),
        lib::wrapped(filename)
    );
}

fn current_dir(filename: &str) {
    println!(
        "{}{}{}{}",
        lib::prefix(),
        lib::wrapped("current dir"),
        lib::delim(),
        lib::wrapped(filename)
    );
}

fn directory(filename: &str) {
    println!(
        "{}{}{}{}",
        lib::prefix(),
        lib::fancy_file(filename),
        lib::delim(),
        lib::wrapped(filename)
    );
}

fn main() -> std::process::ExitCode {
    let paths: Vec<String> = std::env::args().skip(1).collect();
    if paths.is_empty() {
        let cwd = std::env::current_dir()
            .map(|path| path.display().to_string())
            .unwrap_or_default();
        current_dir(&cwd);
        return std::process::ExitCode::SUCCESS;
    }
    for path in paths {
        let candidate = Path::new(&path);
        if candidate.is_dir() {
            directory(&path);
        } else if candidate.exists() {
            exists_file(&path);
        } else {
            nonexists_file(&path);
        }
    }
    std::process::ExitCode::SUCCESS
}
