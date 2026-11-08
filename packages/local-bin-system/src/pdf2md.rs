//! pdf2md: PDF/DOCX/HTML/images → Markdown through docling.
//!
//! Port of `packages/local-bin/bin/pdf2md` (POSIX sh). The wrapper adds the
//! explicit `--to md`, honors `-o`/`--output=`, keeps the model cache on
//! `/zero/ai/ocr`, and hands every other argument to docling unchanged.
//!
//! The docling executable is compiled in by `default.nix`
//! (`LOCAL_BIN_SYSTEM_DOCLING`) because the original wrapper had the store path
//! substituted at install time; a plain `docling` on `PATH` is the fallback for
//! the cargo test build.

use std::path::Path;
use std::process::{Command, Stdio};

use local_bin_system as sh;

const USAGE: &str = "pdf2md: PDF/DOCX/HTML/images → Markdown through docling, entirely from the
nix store (pkgs.python3Packages.docling, wired in modules/cli/ocr.nix).

Replaces the old `marker` wrapper: marker-pdf was a hand-kept pip venv in
~/src/ai-tools whose interpreter died on a python 3.12 → 3.14 bump
(`ModuleNotFoundError: No module named 'marker'`).

Layout/table weights are HuggingFace assets kept in /zero/ai/ocr (the \"all AI
assets on /zero/ai\" convention), so a store GC never touches them. Tesseract was
removed on 2026-11-08, so scanned pages no longer have a classic fallback: run
them through the `ocr` wrapper (PaddleOCR-VL) or `pic-ocr` instead.

Usage:
  pdf2md file.pdf              # → ./file.md
  pdf2md -o out/ a.pdf b.pdf   # → out/a.md, out/b.md
  pdf2md --to json file.pdf    # every docling flag passes through
";

fn docling() -> String {
    option_env!("LOCAL_BIN_SYSTEM_DOCLING")
        .filter(|value| !value.is_empty())
        .unwrap_or("docling")
        .to_string()
}

fn run(arguments: &[String]) -> ! {
    let binary = docling();
    let mut command = Command::new(&binary);
    command.args(arguments);
    if Path::new("/zero/ai/ocr").is_dir() && sh::env_nonempty("HF_HOME").is_none() {
        command.env("HF_HOME", "/zero/ai/ocr");
    }
    command
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit());
    match command.status() {
        Ok(status) => std::process::exit(sh::status_code(status)),
        Err(_) => std::process::exit(127),
    }
}

fn main() {
    let arguments = sh::args();
    if arguments.is_empty() || arguments[0] == "-h" || arguments[0] == "--help" {
        sh::out_str(USAGE);
        return;
    }

    let mut forwarded = vec!["--to".to_string(), "md".to_string()];
    match arguments[0].as_str() {
        "-o" | "--output" => {
            if arguments.len() < 2 {
                sh::err_line("pdf2md: -o needs a directory");
                std::process::exit(2);
            }
            forwarded.push("--output".to_string());
            forwarded.push(arguments[1].clone());
            forwarded.extend_from_slice(&arguments[2..]);
        }
        first if first.starts_with("--output=") => {
            forwarded.push("--output".to_string());
            forwarded.push(first["--output=".len()..].to_string());
            forwarded.extend_from_slice(&arguments[1..]);
        }
        _ => forwarded.extend_from_slice(&arguments),
    }
    run(&forwarded);
}
