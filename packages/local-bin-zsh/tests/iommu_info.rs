//! Hermetic tests for the `iommu-info` port.
//!
//! The sysfs tree is a fixture under the per-case temporary root (pointed to by
//! LOCAL_BIN_ZSH_IOMMU_ROOT) and lspci is a fake, so the suite never reads or
//! resets the host's real IOMMU groups.

mod support;

use std::fs;

use support::{exited, stderr, stdout, Case};

const BIN: &str = env!("CARGO_BIN_EXE_iommu-info");
const USAGE: &str = "\
iommu-info: list or reset IOMMU groups
Usage: iommu-info [r|reset]
  Without args: list IOMMU groups and devices. With 'r' or 'reset':
  show groups highlighting devices supporting reset.
";

const LSPCI: &str = r#"#!/bin/sh
{ printf 'lspci\n'; for a in "$@"; do printf 'ARG %s\n' "$a"; done; } >> "$FAKE_LOG_DIR/lspci.argv"
printf 'dev %s\n' "$2"
printf '%s' "${FAKE_LSPCI_ERR-}" >&2
exit "${FAKE_LSPCI_CODE:-0}"
"#;

fn fixture(label: &str) -> (Case, std::path::PathBuf) {
    let case = Case::new(label, BIN);
    let root = case.path("iommu_groups");
    fs::create_dir_all(&root).expect("create fixture root");
    case.write_fake("lspci", LSPCI);
    (case, root)
}

fn add_group(root: &std::path::Path, group: &str, devices: &[(&str, bool)]) {
    let devices_dir = root.join(group).join("devices");
    fs::create_dir_all(&devices_dir).expect("create devices dir");
    for (device, resettable) in devices {
        let path = devices_dir.join(device);
        fs::create_dir_all(&path).expect("create device dir");
        if *resettable {
            fs::write(path.join("reset"), "1").expect("write reset attribute");
        }
    }
}

fn run(case: &Case, root: &std::path::Path, arguments: &[&str]) -> std::process::Output {
    case.command()
        .env("LOCAL_BIN_ZSH_IOMMU_ROOT", root)
        .args(arguments)
        .output()
        .expect("run iommu-info")
}

#[test]
fn help_prints_the_header_without_touching_lspci() {
    let (case, root) = fixture("iommu-help");
    for argument in ["-h", "--help"] {
        let output = run(&case, &root, &[argument]);
        assert_eq!(exited(&output), 0, "{argument}");
        assert_eq!(stdout(&output), USAGE, "{argument}");
        assert_eq!(stderr(&output), "", "{argument}");
        assert_eq!(case.argv("lspci"), "", "{argument}");
    }
}

#[test]
fn a_missing_groups_tree_warns_and_exits_zero() {
    let case = Case::new("iommu-missing-root", BIN);
    let root = case.path("absent");
    let output = run(&case, &root, &[]);
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), "");
    assert_eq!(
        stderr(&output),
        "iommu-info: lspci not found\niommu-info: no /sys/kernel/iommu_groups\n"
    );
}

#[test]
fn lists_groups_in_glob_order_with_lspci_argv() {
    let (case, root) = fixture("iommu-list");
    add_group(&root, "0", &[("0000:00:01.0", false)]);
    add_group(&root, "1", &[("0000:00:02.0", false)]);
    add_group(
        &root,
        "10",
        &[("0000:00:03.0", false), ("0000:00:03.1", false)],
    );
    fs::create_dir_all(root.join(".hidden")).expect("create dotfile group");

    let output = run(&case, &root, &[]);
    assert_eq!(exited(&output), 0);
    assert_eq!(
        stdout(&output),
        "IOMMU Group 0 dev 0000:00:01.0\n\
         IOMMU Group 1 dev 0000:00:02.0\n\
         IOMMU Group 10 dev 0000:00:03.0\n\
         IOMMU Group 10 dev 0000:00:03.1\n"
    );
    assert_eq!(
        case.argv("lspci"),
        "lspci\nARG -nns\nARG 0000:00:01.0\n\
         lspci\nARG -nns\nARG 0000:00:02.0\n\
         lspci\nARG -nns\nARG 0000:00:03.0\n\
         lspci\nARG -nns\nARG 0000:00:03.1\n"
    );
}

#[test]
fn reset_mode_marks_reset_capable_devices_with_a_tab_prefix() {
    let (case, root) = fixture("iommu-reset");
    add_group(
        &root,
        "0",
        &[("0000:00:01.0", false), ("0000:00:01.1", true)],
    );
    add_group(&root, "1", &[("0000:00:02.0", true)]);

    let output = run(&case, &root, &["r"]);
    assert_eq!(exited(&output), 0);
    assert_eq!(
        stdout(&output),
        "IOMMU group 0\n\
         \tdev 0000:00:01.0\n\
         [RESET]\tdev 0000:00:01.1\n\
         IOMMU group 1\n\
         [RESET]\tdev 0000:00:02.0\n"
    );
    assert_eq!(
        case.argv("lspci"),
        "lspci\nARG -nns\nARG 0000:00:01.0\n\
         lspci\nARG -nns\nARG 0000:00:01.1\n\
         lspci\nARG -nns\nARG 0000:00:02.0\n"
    );
}

#[test]
fn reset_is_selected_by_the_r_prefix_and_skips_non_directories() {
    let (case, root) = fixture("iommu-reset-prefix");
    add_group(&root, "0", &[("0000:00:01.0", false)]);
    fs::write(root.join("not-a-directory"), "x").expect("write file entry");

    for argument in ["reset", "rubbish"] {
        let output = run(&case, &root, &[argument]);
        assert_eq!(exited(&output), 0, "{argument}");
        assert_eq!(stdout(&output), "IOMMU group 0\n\tdev 0000:00:01.0\n");
    }
}

#[test]
fn missing_lspci_warns_and_reports_zsh_style_diagnostics_per_device() {
    let case = Case::new("iommu-no-lspci", BIN);
    let root = case.path("iommu_groups");
    add_group(
        &root,
        "0",
        &[("0000:00:01.0", false), ("0000:00:01.1", false)],
    );

    let output = run(&case, &root, &[]);
    // The last lspci attempt is the last command the shell runs.
    assert_eq!(exited(&output), 127);
    assert_eq!(stdout(&output), "IOMMU Group 0 IOMMU Group 0 ");
    assert_eq!(
        stderr(&output),
        "iommu-info: lspci not found\n\
         valid_groups:5: command not found: lspci\n\
         valid_groups:5: command not found: lspci\n"
    );

    let output = run(&case, &root, &["reset"]);
    assert_eq!(exited(&output), 127);
    assert_eq!(
        stderr(&output),
        "iommu-info: lspci not found\n\
         reset_groups:10: command not found: lspci\n\
         reset_groups:10: command not found: lspci\n"
    );
}

#[test]
fn empty_groups_and_dangling_devices_do_not_change_the_status() {
    let (case, root) = fixture("iommu-empty");
    fs::create_dir_all(root.join("0").join("devices")).expect("create empty group");

    let output = run(&case, &root, &[]);
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), "");
    assert_eq!(case.argv("lspci"), "");

    let output = run(&case, &root, &["reset"]);
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), "IOMMU group 0\n");

    // A dangling symlink matches the reset glob but fails `[[ -e ]]`.
    std::os::unix::fs::symlink("/nonexistent-target", root.join("0/devices/dangling"))
        .expect("create dangling symlink");
    let output = run(&case, &root, &["reset"]);
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), "IOMMU group 0\n");
    assert_eq!(case.argv("lspci"), "");

    // valid_groups does not stat the device entries, so a dangling link still
    // reaches lspci with its basename.
    let output = run(&case, &root, &[]);
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), "IOMMU Group 0 dev dangling\n");
}
