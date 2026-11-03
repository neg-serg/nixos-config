//! nix-updates: show diffs between booted/current system profiles.
//!
//! Port of `packages/local-bin/bin/nix-updates` (POSIX sh). Both tools keep
//! their argv — `nix profile diff-closures --profile
//! /nix/var/nix/profiles/system` and `dix /run/booted-system
//! /run/current-system` (when `dix` is on PATH) — and both failures are
//! deliberately ignored, like the `|| true` in the original.

use std::process::Command;

use local_bin_system as sh;

const USAGE: &str = "nix-updates: show diffs between booted/current system profiles
Usage: nix-updates
";

fn main() {
    let arguments = sh::args();
    if arguments
        .first()
        .map(|value| value == "-h" || value == "--help")
        .unwrap_or(false)
    {
        sh::out_str(USAGE);
        return;
    }

    sh::need(&sh::prog("nix-updates"), "nix");
    let _ = Command::new("nix")
        .args([
            "profile",
            "diff-closures",
            "--profile",
            "/nix/var/nix/profiles/system",
        ])
        .status();
    if sh::which("dix").is_some() {
        let _ = Command::new("dix")
            .args(["/run/booted-system", "/run/current-system"])
            .status();
    }
}
