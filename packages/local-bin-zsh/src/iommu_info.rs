//! Rust port of `packages/local-bin/bin/iommu-info`.
//!
//! Lists IOMMU groups (device BDF plus `lspci -nns`) or, for an argument
//! starting with `r`, shows the groups with `[RESET]` markers where the kernel
//! exposes a `reset` attribute. The original only reads sysfs; this port does
//! the same and never writes a reset file.
//!
//! `LOCAL_BIN_ZSH_IOMMU_ROOT` overrides the sysfs root so the test suite can
//! enumerate a fixture tree instead of the host's groups. It defaults to
//! `/sys/kernel/iommu_groups`; the diagnostic text keeps naming the real path,
//! exactly like the shell original.

#![forbid(unsafe_code)]

use std::ffi::OsString;
use std::fs;
use std::os::unix::ffi::OsStrExt;
use std::path::{Path, PathBuf};

use local_bin_zsh::{
    err_str, out, out_str, raw_args, run, var_nonempty, which_str, Site, Stderr, Stdin, Stdout,
};

const USAGE: &str = include_str!("iommu_info_usage.txt");
const DEFAULT_ROOT: &str = "/sys/kernel/iommu_groups";
const LSPCI_LINE: u32 = 5;
const LSPCI_RESET_LINE: u32 = 10;

/// Entries of a sysfs-style directory, sorted the way zsh sorts a glob and
/// without dotfiles (the `*` patterns do not match a leading dot).
fn glob_entries(directory: &Path) -> Vec<PathBuf> {
    let mut entries: Vec<PathBuf> = match fs::read_dir(directory) {
        Ok(read_dir) => read_dir
            .filter_map(|entry| entry.ok())
            .map(|entry| entry.path())
            .filter(|path| {
                path.file_name()
                    .map(|name| !name.as_bytes().starts_with(b"."))
                    .unwrap_or(false)
            })
            .collect(),
        Err(_) => Vec::new(),
    };
    entries.sort_by(|left, right| {
        left.file_name()
            .map(|name| name.as_bytes().to_vec())
            .cmp(&right.file_name().map(|name| name.as_bytes().to_vec()))
    });
    entries
}

fn group_label(group: &Path) -> Vec<u8> {
    group
        .file_name()
        .map(|name| name.as_bytes().to_vec())
        .unwrap_or_default()
}

fn lspci(device: &Path, site: Site) -> i32 {
    let device = match device.file_name() {
        Some(name) => name.to_os_string(),
        None => return 0,
    };
    run(
        site,
        "lspci",
        &[OsString::from("-nns"), device],
        Stdin::Inherit,
        Stdout::Inherit,
        Stderr::Inherit,
    )
}

fn valid_groups(root: &Path) -> i32 {
    let mut status = 0;
    for group in glob_entries(root) {
        for device in glob_entries(&group.join("devices")) {
            let mut prefix = b"IOMMU Group ".to_vec();
            prefix.extend_from_slice(&group_label(&group));
            prefix.push(b' ');
            out(&prefix);
            status = lspci(&device, Site::Func("valid_groups", LSPCI_LINE));
        }
    }
    status
}

fn reset_groups(root: &Path) -> i32 {
    let mut status = 0;
    for group in glob_entries(root) {
        if !group.is_dir() {
            continue;
        }
        let mut header = b"IOMMU group ".to_vec();
        header.extend_from_slice(&group_label(&group));
        header.push(b'\n');
        out(&header);
        let mut devices = 0;
        for device in glob_entries(&group.join("devices")) {
            // `[[ -e ]]` follows symlinks, so a dangling device link is skipped.
            if fs::metadata(&device).is_err() {
                status = 0;
                continue;
            }
            devices += 1;
            if fs::metadata(device.join("reset")).is_ok() {
                out(b"[RESET]");
            }
            out(b"\t");
            status = lspci(&device, Site::Func("reset_groups", LSPCI_RESET_LINE));
        }
        // With no devices the trailing `echo` is the last command of the
        // iteration, and the function status is its (successful) status.
        if devices == 0 {
            status = 0;
        }
    }
    status
}

fn main() {
    let arguments = raw_args();
    if let Some(first) = arguments.first() {
        if matches!(first.as_bytes(), b"-h" | b"--help") {
            out_str(USAGE);
            return;
        }
    }

    // The original warns but keeps going; the spawn itself then produces the
    // usual zsh diagnostic for every device it cannot enumerate.
    if which_str("lspci").is_none() {
        err_str("iommu-info: lspci not found\n");
    }

    let root = var_nonempty("LOCAL_BIN_ZSH_IOMMU_ROOT")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(DEFAULT_ROOT));
    if !root.is_dir() {
        err_str("iommu-info: no /sys/kernel/iommu_groups\n");
        std::process::exit(0);
    }

    let reset = arguments
        .first()
        .map(|argument| argument.as_bytes().starts_with(b"r"))
        .unwrap_or(false);
    let status = if reset {
        reset_groups(&root)
    } else {
        valid_groups(&root)
    };
    std::process::exit(status);
}
