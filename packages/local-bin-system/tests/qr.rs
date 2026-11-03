//! Hermetic tests for the `qr` port: the three screenshot modes, the QR scan
//! result path (newline stripping, `convert`, the notification with the temp
//! icon), `gen`'s redirect and the `need` warnings.

mod support;

use support::{exited, stderr, stdout, Case};

const BIN: &str = env!("CARGO_BIN_EXE_qr");

const GRIM: &str = r#"#!/bin/sh
printf 'cmd grim\n' >> "$FAKE_ARGV_LOG"
for argument in "$@"; do printf '  %s\n' "$argument" >> "$FAKE_ARGV_LOG"; done
if [ "${FAKE_GRIM_FAIL:-0}" = 1 ]; then exit 1; fi
case "$1" in
  -g)
    if [ "$3" = "-" ]; then printf 'pngdata'; else printf 'pngdata' > "$3"; fi
    ;;
  -)
    printf 'pngdata'
    ;;
esac
exit "${FAKE_GRIM_CODE:-0}"
"#;

const SLURP: &str = r#"#!/bin/sh
printf 'cmd slurp\n' >> "$FAKE_ARGV_LOG"
printf '%s\n' "${FAKE_GEOM:-10,20 100x100}"
"#;

const COPY_RAW: &str = r#"#!/bin/sh
printf 'cmd wl-copy\n' >> "$FAKE_ARGV_LOG"
for argument in "$@"; do printf '  %s\n' "$argument" >> "$FAKE_ARGV_LOG"; done
while IFS= read -r -N 1 character; do printf '%s' "$character" >> "$FAKE_CLIP"; done
"#;

const PASTE: &str = r#"#!/bin/sh
printf 'cmd wl-paste\n' >> "$FAKE_ARGV_LOG"
printf '%s' "${FAKE_PASTE:-text}"
"#;

const NOTIFY: &str = r#"#!/bin/sh
printf 'cmd notify-send\n' >> "$FAKE_ARGV_LOG"
for argument in "$@"; do printf '  %s\n' "$argument" >> "$FAKE_ARGV_LOG"; done
exit "${FAKE_NOTIFY_CODE:-0}"
"#;

const QRENCODE: &str = r#"#!/bin/sh
printf 'cmd qrencode\n' >> "$FAKE_ARGV_LOG"
for argument in "$@"; do printf '  %s\n' "$argument" >> "$FAKE_ARGV_LOG"; done
printf '%s' "${FAKE_QRENCODE_OUT:-QR}"
exit "${FAKE_QRENCODE_CODE:-0}"
"#;

const ZBARIMG: &str = r#"#!/bin/sh
printf 'cmd zbarimg\n' >> "$FAKE_ARGV_LOG"
for argument in "$@"; do printf '  %s\n' "$argument" >> "$FAKE_ARGV_LOG"; done
printf '%s' "${FAKE_SCAN:-}"
exit "${FAKE_SCAN_CODE:-0}"
"#;

const CONVERT: &str = r#"#!/bin/sh
printf 'cmd convert\n' >> "$FAKE_ARGV_LOG"
for argument in "$@"; do printf '  %s\n' "$argument" >> "$FAKE_ARGV_LOG"; done
exit 0
"#;

fn fixture(label: &str) -> Case {
    let case = Case::new(label, BIN);
    case.write_fake("grim", GRIM);
    case.write_fake("slurp", SLURP);
    case.write_fake("wl-copy", COPY_RAW);
    case.write_fake("wl-paste", PASTE);
    case.write_fake("notify-send", NOTIFY);
    case.write_fake("qrencode", QRENCODE);
    case.write_fake("zbarimg", ZBARIMG);
    case.write_fake("convert", CONVERT);
    case
}

fn temp_entries(case: &Case) -> Vec<String> {
    std::fs::read_dir(&case.tmp)
        .map(|entries| {
            entries
                .flatten()
                .map(|entry| entry.file_name().to_string_lossy().into_owned())
                .collect()
        })
        .unwrap_or_default()
}

#[test]
fn help_matches_the_header() {
    let case = fixture("help");
    let output = case.run(&["--help"]);
    assert_eq!(exited(&output), 0);
    assert_eq!(
        stdout(&output),
        concat!(
            "qr: quick QR and screenshot helper\n",
            "Usage:\n",
            "  qr gen          # generate QR from current selection to ~/tmp/qrcode.png\n",
            "  qr select       # select region → clipboard (PNG) + notify\n",
            "  qr qr           # select region → scan QR → copy result + notify\n",
            "  qr              # screenshot entire desktop → clipboard (PNG) + notify\n",
            "  qr -h|--help    # this help\n",
        )
    );
    assert_eq!(stderr(&output), "");
}

#[test]
fn missing_optional_tools_only_warn_before_help() {
    let case = Case::new("warnings", BIN);
    let output = case.run(&["--help"]);
    assert_eq!(exited(&output), 0);
    assert_eq!(
        stderr(&output),
        "qr: missing grim\nqr: missing slurp\nqr: missing wl-copy\n"
    );
}

#[test]
fn the_default_mode_screenshots_the_whole_desktop() {
    let case = fixture("default");
    let output = case.run(&[]);
    assert_eq!(exited(&output), 0);
    assert_eq!(case.clip_log(), "pngdata");
    let argv = case.argv_log();
    assert!(argv.starts_with("cmd grim\n  -\n"), "{argv}");
    assert!(
        argv.contains("cmd wl-copy\n  --type\n  image/png\n"),
        "{argv}"
    );
    assert!(
        argv.contains("cmd notify-send\n  Screenshot\n  Screenshot taken\n"),
        "{argv}"
    );
}

#[test]
fn an_unknown_subcommand_falls_back_to_the_full_screenshot() {
    let case = fixture("unknown");
    let output = case.run(&["bogus"]);
    assert_eq!(exited(&output), 0);
    assert!(case.argv_log().starts_with("cmd grim\n  -\n"));
}

#[test]
fn select_captures_a_region() {
    let case = fixture("select");
    let output = case.run_env(&["select"], &[("FAKE_GEOM", "1,2 3x4")]);
    assert_eq!(exited(&output), 0);
    let argv = case.argv_log();
    assert!(argv.contains("cmd slurp\n"), "{argv}");
    assert!(argv.contains("cmd grim\n  -g\n  1,2 3x4\n  -\n"), "{argv}");
    assert_eq!(case.clip_log(), "pngdata");
}

#[test]
fn gen_writes_the_png_under_home_tmp() {
    let case = fixture("gen");
    let output = case.run_env(&["gen"], &[("FAKE_PASTE", "hello world")]);
    assert_eq!(exited(&output), 0);
    assert_eq!(stdout(&output), "");
    let png = case.home.join("tmp/qrcode.png");
    assert_eq!(case.read_at(&png), "QR");
    assert!(case
        .argv_log()
        .contains("cmd qrencode\n  -l\n  H\n  -d\n  75\n  -s\n  10\n  -o\n  -\n  hello world\n"));
}

#[test]
fn gen_propagates_the_qrencode_status() {
    let case = fixture("gen-fail");
    let output = case.run_env(&["gen"], &[("FAKE_QRENCODE_CODE", "6")]);
    assert_eq!(exited(&output), 6);
}

#[test]
fn gen_without_qrencode_exits_127() {
    let case = fixture("gen-missing");
    case.remove_fake("qrencode");
    let output = case.run(&["gen"]);
    assert_eq!(exited(&output), 127);
    assert!(stderr(&output).contains("qr: missing qrencode"));
}

#[test]
fn scan_copies_the_result_and_notifies_with_the_icon() {
    let case = fixture("scan");
    let output = case.run_env(&["qr"], &[("FAKE_SCAN", "SCANRESULT\n")]);
    assert_eq!(exited(&output), 0);
    assert_eq!(case.clip_log(), "SCANRESULT\n");
    let argv = case.argv_log();
    assert!(argv.contains("cmd zbarimg\n  --quiet\n  --raw\n"), "{argv}");
    assert!(argv.contains("cmd convert\n"), "{argv}");
    assert!(argv.contains("  -i\n"), "{argv}");
    assert!(
        argv.contains("  QR\n  SCANRESULT\\n(copied to clipboard)\n"),
        "{argv}"
    );
    assert!(temp_entries(&case).is_empty(), "{:?}", temp_entries(&case));
}

#[test]
fn scan_strips_every_newline_like_tr() {
    let case = fixture("scan-newlines");
    let _ = case.run_env(&["qr"], &[("FAKE_SCAN", "A\nB\nC\n")]);
    assert_eq!(case.clip_log(), "ABC\n");
}

#[test]
fn scan_without_data_only_notifies() {
    let case = fixture("scan-empty");
    let output = case.run_env(&["qr"], &[("FAKE_SCAN", "")]);
    assert_eq!(exited(&output), 0);
    assert_eq!(case.clip_log(), "");
    let argv = case.argv_log();
    assert!(
        argv.contains("cmd notify-send\n  Screenshot\n  No scan data found\n"),
        "{argv}"
    );
    assert!(!argv.contains("cmd wl-copy"));
    assert!(temp_entries(&case).is_empty());
}

#[test]
fn scan_without_convert_skips_the_resize() {
    let case = fixture("scan-no-convert");
    case.remove_fake("convert");
    let _ = case.run_env(&["qr"], &[("FAKE_SCAN", "X")]);
    assert!(!case.argv_log().contains("cmd convert"));
    assert_eq!(case.clip_log(), "X\n");
}

#[test]
fn a_failed_grim_cleans_up_and_exits_1() {
    let case = fixture("scan-grim-fail");
    let output = case.run_env(&["qr"], &[("FAKE_GRIM_FAIL", "1")]);
    assert_eq!(exited(&output), 1);
    assert!(temp_entries(&case).is_empty(), "{:?}", temp_entries(&case));
    assert!(!case.argv_log().contains("cmd zbarimg"));
}

#[test]
fn the_temporary_file_lives_in_tmpdir() {
    let case = fixture("tmpdir");
    let _ = case.run_env(&["qr"], &[("FAKE_SCAN", "X")]);
    // The file is removed, but grim was pointed into TMPDIR.
    assert!(
        case.argv_log().contains(&format!(
            "cmd grim\n  -g\n  10,20 100x100\n  {}/maimscript-",
            case.tmp.to_string_lossy()
        )),
        "{}",
        case.argv_log()
    );
}

#[test]
fn notify_status_is_the_default_mode_status() {
    let case = fixture("notify-status");
    let output = case.run_env(&[], &[("FAKE_NOTIFY_CODE", "3")]);
    assert_eq!(exited(&output), 3);
}
