//! End-to-end tests for `pleamar-smoke`.

mod support;

use std::fs;

use support::{stderr, stdout, Case};

fn case(label: &str) -> Case {
    let mut case = Case::smoke(label);
    case.set("FAKE_CHECK_OUT", "scene ok\n");
    case
}

fn row_prefix(name: &str, check: &str, render: &str, png: &str) -> String {
    format!("{:<6}  {:<6}  {:<13}  {:<10}  ", name, check, render, png)
}

fn header() -> String {
    format!(
        "{:<6}  {:<6}  {:<13}  {:<10}  {}",
        "SCENE", "CHECK", "RENDER", "PNG", "NOTE"
    )
}

fn no_renderer(case: &Case) {
    case.remove_fake("pleamar-wm");
    case.remove_fake("grim");
    case.remove_fake("sway");
    case.remove_fake("cage");
}

#[test]
fn renders_the_matrix_with_pleamar_wm_and_writes_the_png_and_log() {
    let case = case("wm");
    let output = case.run(&["--seconds", "4", "--min-bytes", "1024"]);
    assert_eq!(output.status.code(), Some(0), "stderr: {}", stderr(&output));
    let out = stdout(&output);
    assert!(out.contains("smoke: hermetic environment under "), "{out}");
    assert!(
        out.contains("smoke: rendering bar with pleamar-wm headless (4s, shot at 2s)"),
        "{out}"
    );
    assert_eq!(stderr(&output), "");
    assert!(out.contains(&header()), "{out}");
    assert!(
        out.contains(&format!(
            "{}scene ok",
            row_prefix("bar", "ok", "ok", "2048B")
        )),
        "{out}"
    );
    assert!(
        out.contains(&format!(
            "smoke: renderer: pleamar-wm ({}); artifacts in {}/tests/shots/2026-01-02",
            case.bin.join("pleamar-wm").display(),
            case.project.display()
        )),
        "{out}"
    );
    assert!(out.contains("smoke: ok: 1 scene(s) checked, 1 rendered"));
    assert!(case.exists("tests/shots/2026-01-02/bar.png"));
    assert!(case.exists("tests/shots/2026-01-02/bar.log"));
    assert_eq!(
        fs::metadata(case.project.join("tests/shots/2026-01-02/bar.png"))
            .unwrap()
            .len(),
        2048
    );
    let check = case.calls_of("pleamar");
    assert_eq!(
        check
            .iter()
            .filter(|line| line.contains("[--check]"))
            .count(),
        1
    );
    let wm = case.calls_of("pleamar-wm");
    assert_eq!(wm.len(), 1);
    assert!(wm[0].contains("[headless] [--seconds] [4]"), "{}", wm[0]);
}

#[test]
fn no_renderer_still_runs_the_compile_matrix() {
    let case = case("no-renderer");
    no_renderer(&case);
    let output = case.run(&[]);
    assert_eq!(output.status.code(), Some(0), "stderr: {}", stderr(&output));
    let out = stdout(&output);
    assert!(
        out.contains(&format!(
            "{}scene ok",
            row_prefix("bar", "ok", "no-renderer", "-")
        )),
        "{out}"
    );
    assert!(out.contains("smoke: renderer: none"), "{out}");
    assert!(stderr(&output).contains("smoke: warning: no renderer available:"));
    assert!(!case.exists("tests/shots/2026-01-02/bar.png"));
}

#[test]
fn require_render_without_a_renderer_is_exit_two() {
    let case = case("require-render");
    no_renderer(&case);
    let output = case.run(&["--require-render"]);
    assert_eq!(output.status.code(), Some(2));
    assert!(
        stderr(&output).starts_with(
            "smoke: error: no renderer available: tried pleamar-wm (PLEAMAR_WM_BIN='pleamar-wm')"
        ),
        "{}",
        stderr(&output)
    );
}

#[test]
fn a_nonzero_renderer_exit_with_a_valid_png_fails_the_render_column() {
    let case = case("render-exit");
    let output = case.run_with(&["--seconds", "4"], &[("FAKE_WM_CODE", "7")]);
    assert_eq!(output.status.code(), Some(1));
    let out = stdout(&output);
    assert!(
        out.contains(&format!(
            "{}scene ok",
            row_prefix("bar", "ok", "FAIL(exit 7)", "2048B")
        )),
        "{out}"
    );
    assert!(out.contains("smoke: FAILED: 1 scene(s) checked, 0 rendered ok"));
}

#[test]
fn a_too_small_png_is_a_failure_with_the_size_in_the_note() {
    let case = case("small-png");
    let output = case.run_with(
        &["--seconds", "4", "--min-bytes", "4096"],
        &[("FAKE_WM_PNG_MODE", "none")],
    );
    assert_eq!(output.status.code(), Some(1));
    let out = stdout(&output);
    assert!(
        out.contains(&format!(
            "{}no PNG written (exit 0)",
            row_prefix("bar", "ok", "FAIL", "-")
        )),
        "{out}"
    );
    let mut case = Case::smoke("small-bytes");
    case.set("FAKE_CHECK_OUT", "scene ok\n");
    let output = case.run_with(
        &["--seconds", "4", "--min-bytes", "4096"],
        &[("FAKE_WM_PNG_MODE", "small")],
    );
    assert_eq!(output.status.code(), Some(1));
    assert!(
        stdout(&output).contains("PNG too small (8B < 4096B) (exit 0)"),
        "{}",
        stdout(&output)
    );
}

#[test]
fn a_file_without_png_magic_is_a_failure() {
    let case = case("bad-magic");
    let output = case.run_with(&["--seconds", "4"], &[("FAKE_WM_PNG_MODE", "bad")]);
    assert_eq!(output.status.code(), Some(1));
    assert!(
        stdout(&output).contains("not a PNG (bad magic) (exit 0)"),
        "{}",
        stdout(&output)
    );
}

#[test]
fn a_compile_failure_skips_the_render() {
    let case = case("check-fail");
    let output = case.run_with(
        &["--seconds", "4"],
        &[
            ("FAKE_CHECK_CODE", "1"),
            ("FAKE_CHECK_OUT", "error: unknown key\nmore\n"),
        ],
    );
    assert_eq!(output.status.code(), Some(1));
    let out = stdout(&output);
    assert!(
        out.contains(&format!(
            "{}error: unknown key",
            row_prefix("bar", "FAIL", "skip(check)", "-")
        )),
        "{out}"
    );
    assert!(out.contains("smoke: FAILED: 1 scene(s) checked, 0 rendered ok"));
    assert!(case.calls_of("pleamar-wm").is_empty());
}

#[test]
fn part_files_are_skipped_and_named_on_stdout() {
    let case = case("part");
    case.scene("proof", "zone proof\n");
    case.raw_scene("shells/proof/shared.plm", "part shared\n");
    let output = case.run(&["--seconds", "4"]);
    assert_eq!(output.status.code(), Some(0), "stderr: {}", stderr(&output));
    assert!(
        stdout(&output).contains("smoke: skipping part file: shells/proof/shared.plm"),
        "{}",
        stdout(&output)
    );
    let check_calls = case
        .calls_of("pleamar")
        .into_iter()
        .filter(|line| line.contains("[--check]"))
        .count();
    assert_eq!(check_calls, 2);
}

#[test]
fn scene_filter_and_empty_trees_are_diagnosed() {
    let case = case("filter");
    case.scene("proof", "zone proof\n");
    let output = case.run(&["--scene", "bar", "--seconds", "4"]);
    assert_eq!(output.status.code(), Some(0), "stderr: {}", stderr(&output));
    assert!(!stdout(&output).contains("proof"));
    let output = case.run(&["--scene", "missing"]);
    assert_eq!(output.status.code(), Some(2));
    assert!(
        stderr(&output).contains("smoke: error: no scene named 'missing' under "),
        "{}",
        stderr(&output)
    );

    let empty = Case::smoke("empty");
    fs::remove_dir_all(empty.project.join("shells/bar")).unwrap();
    let output = empty.run(&[]);
    assert_eq!(output.status.code(), Some(2));
    assert!(
        stderr(&output).contains("smoke: error: no scenes found under "),
        "{}",
        stderr(&output)
    );
}

#[test]
fn flags_are_validated_like_the_script() {
    let case = case("flags");
    let output = case.run(&["--seconds", "1"]);
    assert_eq!(output.status.code(), Some(2));
    assert_eq!(
        stderr(&output),
        "smoke: error: --seconds must be at least 2 for a shot to fit in the session\n"
    );
    let output = case.run(&["--min-bytes", "x"]);
    assert_eq!(
        stderr(&output),
        "smoke: error: --min-bytes must be a positive integer (got 'x')\n"
    );
    let output = case.run(&["extra"]);
    assert_eq!(output.status.code(), Some(2));
    assert_eq!(
        stderr(&output),
        "smoke: error: unknown argument: extra (try --help)\n"
    );
    let missing = Case::smoke("missing");
    missing.remove_fake("pleamar");
    let output = missing.run(&[]);
    assert_eq!(output.status.code(), Some(2));
    assert!(
        stderr(&output).starts_with("smoke: error: pleamar not found (PLEAMAR_BIN='pleamar')"),
        "{}",
        stderr(&output)
    );
}

#[test]
fn custom_out_dir_and_live_environment() {
    let case = case("out");
    let custom = case.dir.join("shots");
    let output = case.run_with(
        &[
            "--seconds",
            "4",
            "--out",
            custom.to_str().unwrap(),
            "--live",
        ],
        &[],
    );
    assert_eq!(output.status.code(), Some(0), "stderr: {}", stderr(&output));
    assert!(stderr(&output).contains(
        "smoke: warning: using the ambient environment (--live); rendering stays headless"
    ));
    assert!(custom.join("2026-01-02/bar.png").is_file());
    assert!(stdout(&output).contains(&format!(
        "smoke: renderer: pleamar-wm ({}); artifacts in {}/2026-01-02",
        case.bin.join("pleamar-wm").display(),
        custom.display()
    )));
}

#[test]
fn sway_is_the_wlroots_fallback_and_renders_through_grim() {
    let mut case = case("sway");
    case.set("PLEAMAR_WM_BIN", "/nonexistent/pleamar-wm");
    let output = case.run(&["--seconds", "4"]);
    assert_eq!(output.status.code(), Some(0), "stderr: {}", stderr(&output));
    let out = stdout(&output);
    assert!(
        out.contains("smoke: rendering bar with headless sway (4s, shot after 2s)"),
        "{out}"
    );
    assert!(out.contains("smoke: renderer: sway ("), "{out}");
    assert!(case.exists("tests/shots/2026-01-02/bar.png"));
    let sway = case.calls_of("sway");
    assert_eq!(sway.len(), 1);
    assert!(sway[0].contains("[-c] [/dev/null]"), "{}", sway[0]);
    assert_eq!(case.calls_of("grim").len(), 1);
    assert!(case
        .calls_of("pleamar")
        .iter()
        .any(|line| line.contains("[--scene]")));
}

#[test]
fn cage_runs_the_scene_inside_the_nested_compositor() {
    let mut case = case("cage");
    case.set("PLEAMAR_WM_BIN", "/nonexistent/pleamar-wm");
    case.remove_fake("sway");
    let output = case.run(&["--seconds", "4"]);
    assert_eq!(output.status.code(), Some(0), "stderr: {}", stderr(&output));
    let out = stdout(&output);
    assert!(
        out.contains("smoke: rendering bar with headless cage (4s, shot after 2s)"),
        "{out}"
    );
    let cage = case.calls_of("cage");
    assert_eq!(cage.len(), 1);
    assert!(cage[0].contains("[--] ["), "{}", cage[0]);
    assert!(cage[0].contains("[--scene] ["), "{}", cage[0]);
    assert_eq!(case.calls_of("grim").len(), 1);
}

#[test]
fn a_wlroots_compositor_without_a_socket_is_a_render_failure() {
    let mut case = case("no-socket");
    case.set("PLEAMAR_WM_BIN", "/nonexistent/pleamar-wm");
    case.fake(
        "sway",
        "#!/bin/sh\nprintf 'sway' >> \"$FAKE_LOG\"\nprintf '\\n' >> \"$FAKE_LOG\"\nperl -e 'select(undef, undef, undef, 0.2)'\nexit 0\n",
    );
    let output = case.run(&["--seconds", "4"]);
    assert_eq!(output.status.code(), Some(1));
    assert!(
        stderr(&output).contains("smoke: sway did not create a Wayland socket; see "),
        "{}",
        stderr(&output)
    );
    assert!(
        stdout(&output).contains(&format!(
            "{}no PNG written (exit 1)",
            row_prefix("bar", "ok", "FAIL", "-")
        )),
        "{}",
        stdout(&output)
    );
}

#[test]
fn the_renderer_priority_is_pleamar_wm_then_grim_sway_cage() {
    let case = case("priority");
    let output = case.run(&["--seconds", "4"]);
    assert_eq!(output.status.code(), Some(0));
    assert!(stdout(&output).contains("smoke: renderer: pleamar-wm"));
    let mut case = Case::smoke("priority-grim");
    case.set("FAKE_CHECK_OUT", "scene ok\n");
    case.set("PLEAMAR_WM_BIN", "/nonexistent/pleamar-wm");
    case.remove_fake("grim");
    let output = case.run(&["--seconds", "4"]);
    assert_eq!(output.status.code(), Some(0));
    assert!(stdout(&output).contains("smoke: renderer: none"));
    assert!(case.calls_of("sway").is_empty());
}

#[test]
fn keep_tmp_is_honoured() {
    let case = case("keep-tmp");
    let output = case.run(&["--seconds", "4", "--keep-tmp"]);
    assert_eq!(output.status.code(), Some(0));
    let line = stdout(&output)
        .lines()
        .find(|line| line.starts_with("smoke: hermetic environment under "))
        .unwrap()
        .to_string();
    let name = line.rsplit('/').next().unwrap().to_string();
    assert!(case.tmp.join(name).is_dir());
    let case = Case::smoke("drop-tmp");
    let output = case.run(&["--seconds", "4"]);
    assert_eq!(output.status.code(), Some(0));
    let line = stdout(&output)
        .lines()
        .find(|line| line.starts_with("smoke: hermetic environment under "))
        .unwrap()
        .to_string();
    let name = line.rsplit('/').next().unwrap().to_string();
    assert!(!case.tmp.join(name).exists());
}

#[test]
fn a_stale_png_cannot_mask_a_render_failure() {
    let case = case("stale");
    let output = case.run(&["--seconds", "4"]);
    assert_eq!(output.status.code(), Some(0), "stderr: {}", stderr(&output));
    let png = case.project.join("tests/shots/2026-01-02/bar.png");
    assert!(png.is_file());
    let output = case.run_with(&["--seconds", "4"], &[("FAKE_WM_PNG_MODE", "none")]);
    assert_eq!(output.status.code(), Some(1));
    assert!(!png.exists(), "the stale shot was removed");
    assert!(
        stdout(&output).contains("no PNG written (exit 0)"),
        "{}",
        stdout(&output)
    );
}
