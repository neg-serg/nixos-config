//! End-to-end tests for `pleamar-measure`.

mod support;

use std::fs;

use support::{stderr, stdout, Case};

fn case(label: &str) -> Case {
    let case = Case::measure(label);
    case
}

#[test]
fn measures_one_scene_and_writes_the_three_artifacts() {
    let case = case("ok");
    let output = case.run(&["--scene", "bar", "--seconds", "2", "--interval", "1"]);
    assert_eq!(output.status.code(), Some(0), "stderr: {}", stderr(&output));

    let out = stdout(&output);
    assert!(
        out.contains("measure: hermetic environment under "),
        "{out}"
    );
    assert!(
        out.contains("measure: starting the scene in pleamar-wm headless"),
        "{out}"
    );
    assert!(
        out.contains(&format!(
            "measure: measuring scene 'bar' (pid {}) for 2s, every 1s",
            case.zombie_pid
        )),
        "{out}"
    );
    assert!(out.contains("measure: tsv: "), "{out}");
    assert!(out.contains("measure: report: report line"), "{out}");
    assert!(out.contains("measure: ok: 3 samples in "), "{out}");
    assert_eq!(stderr(&output), "");

    let tsv = case.read("tests/evidence/2026-01-02-bar.tsv");
    let rows: Vec<&str> = tsv.lines().collect();
    assert_eq!(
        rows[0],
        "t_s\tpid\trss_kb\tps_cpu_pct\tcpu_pct\tthreads\tpss_kb\tcg_mem_bytes\tcg_mem_peak_bytes\tcg_cpu_usec\tcg_cpu_pct"
    );
    assert_eq!(rows.len(), 4);
    assert!(rows[1].starts_with(&format!("0\t{}\t1234\t1.5\t-\t7\t", case.zombie_pid)));
    assert!(rows[2].starts_with(&format!("1\t{}\t1234\t1.5\t0.00\t7\t", case.zombie_pid)));
    assert_eq!(
        rows[2].split('\t').nth(7),
        Some("-"),
        "no cgroup without --unit"
    );
    assert_eq!(
        case.read("tests/evidence/2026-01-02-bar.md"),
        "report line\n"
    );
    assert!(fs::metadata(case.project.join("tests/evidence/2026-01-02-bar.log")).is_ok());

    let pleamar = case.calls_of("pleamar");
    assert_eq!(
        pleamar,
        vec![
            "pleamar [--say] [bar] [describe]".to_string(),
            "pleamar [--say] [bar] [hello]".to_string(),
            format!(
                "pleamar [--report] [bar] [--seconds] [2] [--out] [{}]",
                case.project
                    .join("tests/evidence/2026-01-02-bar.md")
                    .display()
            ),
            "pleamar [--say] [bar] [quit]".to_string(),
        ]
    );
    let wm = case.calls_of("pleamar-wm");
    assert_eq!(wm.len(), 1);
    assert!(wm[0].contains("[headless] [--seconds] [32]"), "{}", wm[0]);
    assert!(case.exists("tests/evidence/2026-01-02-bar.tsv"));
}

#[test]
fn a_missing_pleamar_is_bad_usage() {
    let case = case("missing-tool");
    case.remove_fake("pleamar");
    let output = case.run(&["bar"]);
    assert_eq!(output.status.code(), Some(2));
    assert_eq!(stdout(&output), "");
    assert_eq!(
        stderr(&output),
        "measure: error: pleamar not found (PLEAMAR_BIN='pleamar'). This harness never builds it: build/install pleamar, put it on PATH, or set PLEAMAR_BIN=/path/to/pleamar\n"
    );
}

#[test]
fn seconds_and_interval_must_be_positive_integers() {
    let case = case("bad-uint");
    let output = case.run(&["--seconds", "0"]);
    assert_eq!(output.status.code(), Some(2));
    assert_eq!(
        stderr(&output),
        "measure: error: --seconds must be at least 1\n"
    );
    let output = case.run(&["--seconds", "1x"]);
    assert_eq!(output.status.code(), Some(2));
    assert_eq!(
        stderr(&output),
        "measure: error: --seconds must be a positive integer (got '1x')\n"
    );
    let output = case.run(&["--interval", "-1"]);
    assert_eq!(
        stderr(&output),
        "measure: error: --interval must be a positive integer (got '-1')\n"
    );
}

#[test]
fn unknown_options_and_second_scenes_are_usage_errors() {
    let case = case("usage");
    let output = case.run(&["--bogus"]);
    assert_eq!(output.status.code(), Some(2));
    assert_eq!(
        stderr(&output),
        "measure: error: unknown option: --bogus (try --help)\n"
    );
    let output = case.run(&["bar", "proof"]);
    assert_eq!(
        stderr(&output),
        "measure: error: more than one scene given\n"
    );
}

#[test]
fn scene_discovery_reports_an_ambiguous_tree() {
    let case = case("ambiguous");
    case.scene("proof", "zone proof\n");
    let output = case.run(&[]);
    assert_eq!(output.status.code(), Some(2));
    assert!(
        stdout(&output).contains(
            "measure: several scenes found; name one of them:\nmeasure:   bar\nmeasure:   proof\n"
        ),
        "{}",
        stdout(&output)
    );
    assert_eq!(
        stderr(&output),
        "measure: error: cannot resolve the scene (pass a name like 'proof' or a .plm path)\n"
    );
}

#[test]
fn part_files_are_not_scenes() {
    let case = case("part-file");
    case.raw_scene("shells/bar/part.plm", "part shared\n");
    let output = case.run(&["--seconds", "1"]);
    assert_eq!(output.status.code(), Some(0), "stderr: {}", stderr(&output));
    assert!(stdout(&output).contains("scene 'bar'"));
}

#[test]
fn a_dead_scene_is_a_failure_after_the_partial_table() {
    let mut case = case("dead-scene");
    case.set("FAKE_HELLO", "pid 4000000");
    let output = case.run(&["bar", "--seconds", "3"]);
    assert_eq!(output.status.code(), Some(1));
    let err = stderr(&output);
    assert!(
        err.contains(
            "measure: scene process 4000000 exited during measurement (0 samples written to "
        ),
        "{err}"
    );
    let tsv = case.read("tests/evidence/2026-01-02-bar.tsv");
    assert_eq!(tsv.lines().count(), 1, "only the header is kept");
}

#[test]
fn a_failed_report_is_a_failure() {
    let case = case("report-fail");
    let output = case.run_with(&["bar", "--seconds", "1"], &[("FAKE_REPORT_CODE", "3")]);
    assert_eq!(output.status.code(), Some(1));
    assert!(
        stderr(&output).contains("measure: pleamar --report failed (exit 3; see "),
        "{}",
        stderr(&output)
    );
}

#[test]
fn no_runner_available_is_a_tool_error() {
    let mut case = case("no-runner");
    case.set("PLEAMAR_WM_BIN", "/nonexistent/pleamar-wm");
    let output = case.run(&["bar"]);
    assert_eq!(output.status.code(), Some(2));
    assert_eq!(
        stderr(&output),
        "measure: error: no scene runner available for a hermetic run: pleamar-wm not found (PLEAMAR_WM_BIN='/nonexistent/pleamar-wm'); pass --live to start the scene in the current session, or --unit to measure a running unit\n"
    );
}

#[test]
fn live_without_a_display_is_a_tool_error() {
    let mut case = case("live-no-display");
    case.set("PLEAMAR_WM_BIN", "/nonexistent/pleamar-wm");
    let output = case.run(&["bar", "--live"]);
    assert_eq!(output.status.code(), Some(2));
    let err = stderr(&output);
    assert!(
        err.contains("measure: warning: using the ambient environment (--live)\n"),
        "{err}"
    );
    assert!(
        stdout(&output).contains("measure: --live was given but WAYLAND_DISPLAY is unset"),
        "{}",
        stdout(&output)
    );
}

#[test]
fn soft_keeps_an_existing_icd_and_warns_when_the_file_is_missing() {
    let case = case("soft");
    let output = case.run_with(
        &["bar", "--seconds", "1", "--soft"],
        &[("VK_ICD_FILENAMES", "/tmp/existing.json")],
    );
    assert_eq!(output.status.code(), Some(0));
    assert!(stdout(&output).contains(
        "measure: --soft: VK_ICD_FILENAMES is already set, keeping it (/tmp/existing.json)"
    ));
    let case = Case::measure("soft-missing");
    let output = case.run_with(
        &["bar", "--seconds", "1", "--soft"],
        &[("PLEAMAR_SOFT_ICD", "/nonexistent/lvp.json")],
    );
    assert_eq!(output.status.code(), Some(0));
    assert!(stderr(&output).contains(
        "measure: warning: --soft: /nonexistent/lvp.json does not exist; continuing without software Vulkan"
    ));
}

#[test]
fn keep_tmp_leaves_the_sandbox_and_the_default_removes_it() {
    let case = case("keep-tmp");
    let output = case.run(&["bar", "--seconds", "1", "--keep-tmp"]);
    assert_eq!(output.status.code(), Some(0));
    let out = stdout(&output);
    let line = out
        .lines()
        .find(|line| line.starts_with("measure: hermetic environment under "))
        .expect("hermetic line");
    let temp = line.trim_start_matches("measure: hermetic environment under ");
    assert!(case.tmp.join(temp.rsplit('/').next().unwrap()).is_dir());

    let case = Case::measure("drop-tmp");
    let output = case.run(&["bar", "--seconds", "1"]);
    assert_eq!(output.status.code(), Some(0));
    let out = stdout(&output);
    let line = out
        .lines()
        .find(|line| line.starts_with("measure: hermetic environment under "))
        .expect("hermetic line");
    let name = line
        .trim_start_matches("measure: hermetic environment under ")
        .rsplit('/')
        .next()
        .unwrap()
        .to_string();
    assert!(!case.tmp.join(name).exists());
}

#[test]
fn unit_mode_samples_the_main_pid_and_its_cgroup_without_starting_a_scene() {
    let case = case("unit");
    let cgroup = case.dir.join("cgroup/test.slice");
    fs::create_dir_all(&cgroup).unwrap();
    fs::write(cgroup.join("memory.current"), "4096\n").unwrap();
    fs::write(cgroup.join("memory.peak"), "8192\n").unwrap();
    fs::write(cgroup.join("cpu.stat"), "usage_usec 1000\n").unwrap();
    let cgroup_root = case.dir.join("cgroup");
    let output = case.run_with(
        &["--unit", "pleamar-bar.service", "--seconds", "2"],
        &[
            ("FAKE_MAINPID", &case.zombie_pid.to_string()),
            ("FAKE_CONTROLGROUP", "/test.slice"),
            ("PLEAMAR_CGROUP_ROOT", cgroup_root.to_str().unwrap()),
        ],
    );
    assert_eq!(output.status.code(), Some(0), "stderr: {}", stderr(&output));
    assert!(stderr(&output).contains(
        "measure: warning: measuring unit 'pleamar-bar.service' in the ambient session; the scene is not started or stopped"
    ));
    let tsv = case.read("tests/evidence/2026-01-02-bar.tsv");
    let rows: Vec<&str> = tsv.lines().collect();
    assert_eq!(rows.len(), 4);
    let columns: Vec<&str> = rows[1].split('\t').collect();
    assert_eq!(columns[7], "4096");
    assert_eq!(columns[8], "8192");
    assert_eq!(columns[9], "1000");
    assert_eq!(columns[10], "-");
    let columns: Vec<&str> = rows[2].split('\t').collect();
    assert_eq!(columns[9], "1000");
    assert_eq!(columns[10], "0.00");
    assert!(case.calls_of("pleamar-wm").is_empty());
    assert!(!case
        .calls_of("pleamar")
        .iter()
        .any(|line| line.contains("[quit]")));
    let systemctl = case.calls_of("systemctl");
    assert!(
        systemctl.contains(
            &"systemctl [--user] [show] [-p] [MainPID] [--value] [pleamar-bar.service]".to_string()
        ),
        "{systemctl:?}"
    );
}

#[test]
fn a_missing_cgroup_warns_and_leaves_the_columns_empty() {
    let case = case("unit-no-cgroup");
    let output = case.run_with(
        &["--unit", "pleamar-bar.service", "--seconds", "1"],
        &[
            ("FAKE_MAINPID", &case.zombie_pid.to_string()),
            ("FAKE_CONTROLGROUP", "/missing.slice"),
        ],
    );
    assert_eq!(output.status.code(), Some(0), "stderr: {}", stderr(&output));
    assert!(stderr(&output).contains(
        "measure: warning: cgroup directory /sys/fs/cgroup/missing.slice does not exist; cgroup columns will be empty"
    ));
    let tsv = case.read("tests/evidence/2026-01-02-bar.tsv");
    assert_eq!(tsv.lines().nth(1).unwrap().split('\t').nth(7), Some("-"));
}

#[test]
fn a_unit_without_mainpid_is_not_running() {
    let case = case("unit-dead");
    let output = case.run(&["--unit", "pleamar-bar.service"]);
    assert_eq!(output.status.code(), Some(2));
    assert_eq!(
        stderr(&output),
        "measure: warning: measuring unit 'pleamar-bar.service' in the ambient session; the scene is not started or stopped\nmeasure: error: unit 'pleamar-bar.service' is not running (no MainPID)\n"
    );
}

#[test]
fn unit_mode_needs_the_ambient_runtime_dir() {
    let case = case("unit-no-runtime");
    let output = case.run_with(
        &["--unit", "pleamar-bar.service"],
        &[("XDG_RUNTIME_DIR", "")],
    );
    assert_eq!(output.status.code(), Some(2));
    assert_eq!(
        stderr(&output),
        "measure: error: --unit needs XDG_RUNTIME_DIR (the unit's session) to reach pleamar --say\n"
    );
}

#[test]
fn live_starts_the_scene_through_pleamar_not_headless() {
    let case = case("live");
    let output = case.run_with(
        &["bar", "--seconds", "1", "--live"],
        &[
            ("WAYLAND_DISPLAY", "wayland-1"),
            ("PLEAMAR_WM_BIN", "/nonexistent/pleamar-wm"),
        ],
    );
    assert_eq!(output.status.code(), Some(0), "stderr: {}", stderr(&output));
    assert!(stdout(&output).contains("measure: starting the scene in the current session (--live)"));
    assert!(stderr(&output).contains("measure: warning: using the ambient environment (--live)"));
    let setsid = case.calls_of("setsid");
    assert_eq!(setsid.len(), 1);
    assert!(setsid[0].contains("[--scene] ["), "{}", setsid[0]);
    assert!(setsid[0].contains("bar.plm"), "{}", setsid[0]);
    assert!(
        setsid[0].contains("[--no-hud] [--seconds] [31]"),
        "{}",
        setsid[0]
    );
    assert!(case.calls_of("pleamar-wm").is_empty());
}

#[test]
fn an_existing_soft_icd_is_exported() {
    let case = case("soft-existing");
    let icd = case.dir.join("lvp_icd.x86_64.json");
    fs::write(&icd, "{}").unwrap();
    let output = case.run_with(
        &["bar", "--seconds", "1", "--soft"],
        &[("PLEAMAR_SOFT_ICD", icd.to_str().unwrap())],
    );
    assert_eq!(output.status.code(), Some(0));
    assert!(stdout(&output).contains(&format!(
        "measure: --soft: VK_ICD_FILENAMES={} (Mesa lavapipe)",
        icd.display()
    )));
}

#[test]
fn help_wins_when_it_comes_before_an_unknown_option() {
    let case = case("help");
    let output = case.run(&["--help", "--bogus"]);
    assert_eq!(output.status.code(), Some(0));
    assert!(stdout(&output).starts_with("measure.sh - run one scene"));
    let output = case.run(&["--bogus", "--help"]);
    assert_eq!(output.status.code(), Some(2));
}

#[test]
fn a_plm_path_and_a_custom_out_dir_are_accepted() {
    let case = case("path-out");
    let scene = case.project.join("shells/bar/bar.plm");
    let out = case.dir.join("evidence");
    let output = case.run(&[
        scene.to_str().unwrap(),
        "--seconds",
        "1",
        "--out",
        out.to_str().unwrap(),
    ]);
    assert_eq!(output.status.code(), Some(0), "stderr: {}", stderr(&output));
    assert!(
        stdout(&output).contains("measure: measuring scene 'bar'"),
        "{}",
        stdout(&output)
    );
    assert!(out.join("2026-01-02-bar.tsv").is_file());
    assert!(out.join("2026-01-02-bar.md").is_file());
    assert!(out.join("2026-01-02-bar.log").is_file());
}
