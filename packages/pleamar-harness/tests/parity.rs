//! Shell-vs-port parity harness.
//!
//! Each scenario runs the unmodified copy of the original script in
//! `tests/parity/original/` and the ported binary against the same fake tools,
//! the same scene fixture and the same zombie scene pid, then compares:
//!
//! - stdout and stderr after normalising the per-case project path,
//! - the exit code,
//! - every artifact under `tests/` (bytes and relative path),
//! - the argv of the contract tools (`pleamar`, `pleamar-wm`, `ps`,
//!   `systemctl`, `systemd-run`, `grim`, `sway`, `cage`, `timeout`, `setsid`,
//!   `date`, `mktemp`, `sleep`, `column`) as a sorted multiset — background
//!   spawns make the order non-deterministic, the multiset is not.
//!
//! The fixture roots differ, so both outputs carry their own absolute paths;
//! normalisation replaces each root with `<PROJECT>`.

mod support;

use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Output, Stdio};

use support::{stderr, stdout, Case};

#[derive(Clone, Copy)]
enum Tool {
    Measure,
    DescribeSnap,
    Smoke,
}

impl Tool {
    fn script(self) -> &'static str {
        match self {
            Tool::Measure => "measure",
            Tool::DescribeSnap => "describe-snap",
            Tool::Smoke => "smoke",
        }
    }

    fn case(self, label: &str) -> Case {
        match self {
            Tool::Measure => Case::measure(label),
            Tool::DescribeSnap => Case::describe_snap(label),
            Tool::Smoke => Case::smoke(label),
        }
    }
}

struct Zombie {
    child: Child,
    pid: u32,
}

impl Zombie {
    fn new() -> Self {
        let child = Command::new("sh")
            .arg("-c")
            .arg("exit 0")
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .expect("spawn zombie");
        let pid = child.id();
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(2);
        while std::time::Instant::now() < deadline {
            if let Ok(stat) = fs::read_to_string(format!("/proc/{pid}/stat")) {
                if stat
                    .rsplit(')')
                    .next()
                    .map_or(false, |rest| rest.trim_start().starts_with('Z'))
                {
                    break;
                }
            }
            std::thread::sleep(std::time::Duration::from_millis(5));
        }
        Self { child, pid }
    }
}

impl Drop for Zombie {
    fn drop(&mut self) {
        let _ = self.child.wait();
    }
}

fn install_script(case: &Case, tool: Tool) {
    let name = format!("{}.sh", tool.script());
    let source = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/parity/original")
        .join(&name);
    let scripts = case.project.join("scripts");
    fs::create_dir_all(&scripts).expect("create scripts dir");
    fs::copy(source, scripts.join(&name)).expect("copy original script");
}

fn pair(
    tool: Tool,
    label: &str,
    zombie: &Zombie,
    setup: impl Fn(&mut Case),
) -> (Case, Case, PathBuf) {
    let mut shell = tool.case(&format!("parity-shell-{label}"));
    let mut rust = tool.case(&format!("parity-rust-{label}"));
    install_script(&shell, tool);
    install_script(&rust, tool);
    setup(&mut shell);
    setup(&mut rust);
    let hello = format!("id 1 pid {}", zombie.pid);
    let pid = zombie.pid.to_string();
    for case in [&mut shell, &mut rust] {
        case.set("FAKE_HELLO", &hello);
        case.set("FAKE_SCENE_PID", &pid);
    }
    let script = shell
        .project
        .join("scripts")
        .join(format!("{}.sh", tool.script()));
    (shell, rust, script)
}

fn normalise(text: &str, case: &Case) -> String {
    let text = text.replace(&case.project.display().to_string(), "<PROJECT>");
    let text = text.replace(&case.dir.display().to_string(), "<CASE>");
    normalise_unit_pids(&text)
}

/// `--systemd` names the transient unit with the harness's own pid (`$$` in
/// the shell, `process::id()` here). It is intentionally not the same number,
/// so both sides are folded to `<PID>` before comparing.
fn normalise_unit_pids(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(start) = rest.find("pleamar-snap-") {
        out.push_str(&rest[..start]);
        let after = &rest[start..];
        let end = after
            .find(|character: char| character.is_whitespace() || character == ']')
            .unwrap_or(after.len());
        let token = &after[..end];
        if let Some(dash) = token.rfind('-') {
            let (head, tail) = token.split_at(dash + 1);
            if !tail.is_empty() && tail.chars().all(|character| character.is_ascii_digit()) {
                out.push_str(head);
                out.push_str("<PID>");
                rest = &after[end..];
                continue;
            }
        }
        out.push_str(token);
        rest = &after[end..];
    }
    out.push_str(rest);
    out
}

fn artifacts(case: &Case) -> BTreeMap<String, Vec<u8>> {
    let mut files = BTreeMap::new();
    let tests = case.project.join("tests");
    collect(&tests, &tests, &mut files);
    files
}

fn collect(root: &Path, directory: &Path, files: &mut BTreeMap<String, Vec<u8>>) {
    let entries = match fs::read_dir(directory) {
        Ok(entries) => entries,
        Err(_) => return,
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            collect(root, &path, files);
        } else if path.is_file() {
            let relative = path
                .strip_prefix(root)
                .unwrap()
                .to_string_lossy()
                .into_owned();
            files.insert(relative, fs::read(&path).unwrap_or_default());
        }
    }
}

const CONTRACT_TOOLS: &[&str] = &[
    "pleamar",
    "pleamar-wm",
    "ps",
    "systemctl",
    "systemd-run",
    "grim",
    "sway",
    "cage",
    "timeout",
    "setsid",
    "date",
    "mktemp",
    "sleep",
    "column",
    "pgrep",
    "getconf",
];

/// Process pids are per-implementation (the runner, the compositor) while the
/// sampled scene pid is shared. Fold only the trailing `-p PID` operand so the
/// argv shape stays comparable.
fn normalise_pid_argument(tool: &str, line: String) -> String {
    if tool != "ps" {
        return line;
    }
    let marker = "[-p] [";
    let Some(index) = line.find(marker) else {
        return line;
    };
    let start = index + marker.len();
    let Some(end) = line[start..].find(']') else {
        return line;
    };
    let pid = &line[start..start + end];
    if pid.is_empty() || !pid.chars().all(|character| character.is_ascii_digit()) {
        return line;
    }
    format!("{}<PID>{}", &line[..start], &line[start + end..])
}

fn compare(label: &str, shell: &Case, rust: &Case, shell_out: &Output, rust_out: &Output) {
    assert_eq!(
        shell_out.status.code(),
        rust_out.status.code(),
        "{label}: exit code\nshell stdout:\n{}\nshell stderr:\n{}\nrust stdout:\n{}\nrust stderr:\n{}",
        stdout(shell_out),
        stderr(shell_out),
        stdout(rust_out),
        stderr(rust_out)
    );
    let shell_stdout = normalise(&stdout(shell_out), shell);
    let rust_stdout = normalise(&stdout(rust_out), rust);
    assert_eq!(
        shell_stdout,
        rust_stdout,
        "{label}: stdout differs\nshell stderr:\n{}\nrust stderr:\n{}",
        stderr(shell_out),
        stderr(rust_out)
    );
    let shell_stderr = normalise(&stderr(shell_out), shell);
    let rust_stderr = normalise(&stderr(rust_out), rust);
    assert_eq!(shell_stderr, rust_stderr, "{label}: stderr differs");

    let shell_files = artifacts(shell);
    let rust_files = artifacts(rust);
    assert_eq!(
        shell_files.keys().collect::<Vec<_>>(),
        rust_files.keys().collect::<Vec<_>>(),
        "{label}: artifact file list differs"
    );
    for (name, shell_bytes) in &shell_files {
        let rust_bytes = &rust_files[name];
        assert_eq!(
            shell_bytes,
            rust_bytes,
            "{label}: artifact {name} differs\nshell:\n{}\nrust:\n{}",
            String::from_utf8_lossy(shell_bytes),
            String::from_utf8_lossy(rust_bytes)
        );
    }

    for tool in CONTRACT_TOOLS {
        let mut shell_calls: Vec<String> = shell
            .calls_of(tool)
            .into_iter()
            .map(|line| normalise_pid_argument(tool, normalise(&line, shell)))
            .collect();
        let mut rust_calls: Vec<String> = rust
            .calls_of(tool)
            .into_iter()
            .map(|line| normalise_pid_argument(tool, normalise(&line, rust)))
            .collect();
        shell_calls.sort();
        rust_calls.sort();
        if *tool == "sleep" {
            // Socket polling is timing-dependent: how many 0.1 s turns a
            // compositor takes to appear is not a contract. The set of sleep
            // durations is.
            shell_calls.dedup();
            rust_calls.dedup();
        }
        assert_eq!(
            shell_calls, rust_calls,
            "{label}: argv multiset for {tool} differs"
        );
    }
}

fn run_pair(
    label: &str,
    args: &[&str],
    shell: &Case,
    rust: &Case,
    script: &Path,
    extra_shell: &[(&str, &str)],
    extra_rust: &[(&str, &str)],
) {
    let shell_out = shell.run_shell(script, args, extra_shell);
    let rust_out = rust.run_rust(args, extra_rust);
    compare(label, shell, rust, &shell_out, &rust_out);
}

#[test]
fn help_texts_are_identical() {
    let zombie = Zombie::new();
    for tool in [Tool::Measure, Tool::DescribeSnap, Tool::Smoke] {
        let (shell, rust, script) = pair(tool, "help", &zombie, |_| {});
        run_pair("help", &["--help"], &shell, &rust, &script, &[], &[]);
    }
}

#[test]
fn measure_success_is_identical() {
    let zombie = Zombie::new();
    let (shell, rust, script) = pair(Tool::Measure, "ok", &zombie, |_| {});
    run_pair(
        "measure-ok",
        &["--scene", "bar", "--seconds", "3", "--interval", "1"],
        &shell,
        &rust,
        &script,
        &[],
        &[],
    );
}

#[test]
fn measure_dead_scene_is_identical() {
    let zombie = Zombie::new();
    let (shell, rust, script) = pair(Tool::Measure, "dead", &zombie, |_| {});
    // A pid that does not exist: the loop notices on the first check.
    let extra = [("FAKE_HELLO", "pid 4000000")];
    run_pair(
        "measure-dead",
        &["bar", "--seconds", "2"],
        &shell,
        &rust,
        &script,
        &extra,
        &extra,
    );
}

#[test]
fn measure_report_failure_is_identical() {
    let zombie = Zombie::new();
    let (shell, rust, script) = pair(Tool::Measure, "report-fail", &zombie, |_| {});
    let extra = [("FAKE_REPORT_CODE", "3")];
    run_pair(
        "measure-report-fail",
        &["bar", "--seconds", "1"],
        &shell,
        &rust,
        &script,
        &extra,
        &extra,
    );
}

#[test]
fn measure_scene_discovery_is_identical() {
    let zombie = Zombie::new();
    let (shell, rust, script) = pair(Tool::Measure, "discovery", &zombie, |case| {
        case.scene("proof", "zone proof\n");
    });
    run_pair("measure-discovery", &[], &shell, &rust, &script, &[], &[]);
}

#[test]
fn measure_unit_mode_is_identical() {
    let zombie = Zombie::new();
    let (shell, rust, script) = pair(Tool::Measure, "unit", &zombie, |_| {});
    let mainpid = zombie.pid.to_string();
    // The original hardcodes /sys/fs/cgroup, so both warn and leave the
    // columns empty here; the port's PLEAMAR_CGROUP_ROOT seam is covered by
    // the measure tests instead.
    let extra = [
        ("FAKE_MAINPID", mainpid.as_str()),
        ("FAKE_CONTROLGROUP", "/test.slice"),
    ];
    run_pair(
        "measure-unit",
        &["--unit", "pleamar-bar.service", "--seconds", "2"],
        &shell,
        &rust,
        &script,
        &extra,
        &extra,
    );
}

#[test]
fn describe_update_and_verify_are_identical() {
    let zombie = Zombie::new();
    let (shell, rust, script) = pair(Tool::DescribeSnap, "update", &zombie, |_| {});
    run_pair(
        "describe-update",
        &["--update", "bar"],
        &shell,
        &rust,
        &script,
        &[],
        &[],
    );
    run_pair(
        "describe-verify",
        &["bar"],
        &shell,
        &rust,
        &script,
        &[],
        &[],
    );
}

#[test]
fn describe_drift_and_rewrite_are_identical() {
    let zombie = Zombie::new();
    let (shell, rust, script) = pair(Tool::DescribeSnap, "drift", &zombie, |case| {
        case.snapshot("bar", "{\n  \"bar\": 1,\n  \"clock\": \"HH:MM\"\n}\n");
    });
    let json = shell.dir.join("new.json");
    fs::write(&json, "{\"bar\":2,\"baz\":3,\"clock\":\"10:00\"}\n").unwrap();
    let rust_json = rust.dir.join("new.json");
    fs::write(&rust_json, "{\"bar\":2,\"baz\":3,\"clock\":\"10:00\"}\n").unwrap();
    let shell_extra = [("FAKE_DESCRIBE_JSON_FILE", json.to_str().unwrap())];
    let rust_extra = [("FAKE_DESCRIBE_JSON_FILE", rust_json.to_str().unwrap())];
    let shell_out = shell.run_shell(&script, &["bar"], &shell_extra);
    let rust_out = rust.run_rust(&["bar"], &rust_extra);
    compare("describe-drift", &shell, &rust, &shell_out, &rust_out);
    let shell_out = shell.run_shell(&script, &["--update", "bar"], &shell_extra);
    let rust_out = rust.run_rust(&["--update", "bar"], &rust_extra);
    compare("describe-rewrite", &shell, &rust, &shell_out, &rust_out);
}

#[test]
fn describe_systemd_is_identical() {
    let zombie = Zombie::new();
    let (shell, rust, script) = pair(Tool::DescribeSnap, "systemd", &zombie, |_| {});
    let extra = [("WAYLAND_DISPLAY", "wayland-1")];
    run_pair(
        "describe-systemd",
        &["--systemd", "--update", "bar"],
        &shell,
        &rust,
        &script,
        &extra,
        &extra,
    );
}

#[test]
fn smoke_no_renderer_is_identical() {
    let zombie = Zombie::new();
    let (shell, rust, script) = pair(Tool::Smoke, "no-renderer", &zombie, |case| {
        case.remove_fake("pleamar-wm");
        case.remove_fake("grim");
        case.remove_fake("sway");
        case.remove_fake("cage");
        case.set("FAKE_CHECK_OUT", "scene ok\n");
    });
    run_pair(
        "smoke-no-renderer",
        &["--seconds", "4"],
        &shell,
        &rust,
        &script,
        &[],
        &[],
    );
}

#[test]
fn smoke_wm_render_is_identical() {
    let zombie = Zombie::new();
    let (shell, rust, script) = pair(Tool::Smoke, "wm", &zombie, |case| {
        case.set("FAKE_CHECK_OUT", "scene ok\n");
    });
    run_pair(
        "smoke-wm",
        &["--seconds", "4"],
        &shell,
        &rust,
        &script,
        &[],
        &[],
    );
}

#[test]
fn smoke_compile_failure_is_identical() {
    let zombie = Zombie::new();
    let (shell, rust, script) = pair(Tool::Smoke, "check", &zombie, |case| {
        case.set("FAKE_CHECK_CODE", "1");
        case.set("FAKE_CHECK_OUT", "error: unknown key\n");
    });
    run_pair(
        "smoke-check",
        &["--seconds", "4"],
        &shell,
        &rust,
        &script,
        &[],
        &[],
    );
}

#[test]
fn smoke_sway_render_is_identical() {
    let zombie = Zombie::new();
    let (shell, rust, script) = pair(Tool::Smoke, "sway", &zombie, |case| {
        case.set("FAKE_CHECK_OUT", "scene ok\n");
        case.set("PLEAMAR_WM_BIN", "/nonexistent/pleamar-wm");
    });
    run_pair(
        "smoke-sway",
        &["--seconds", "4"],
        &shell,
        &rust,
        &script,
        &[],
        &[],
    );
}

#[test]
fn describe_plain_masking_is_identical() {
    let zombie = Zombie::new();
    let (shell, rust, script) = pair(Tool::DescribeSnap, "plain", &zombie, |_| {});
    let body = "tree   \nclock 09:51\n«Media: Track» at 12,34 567×890\n«Weather +5 °C»\nvolume \"-50 dB\"\nlevel 5 dB\n";
    let shell_plain = shell.dir.join("plain.txt");
    fs::write(&shell_plain, body).unwrap();
    let rust_plain = rust.dir.join("plain.txt");
    fs::write(&rust_plain, body).unwrap();
    let shell_extra = [
        ("FAKE_DESCRIBE_JSON_CODE", "1"),
        ("FAKE_DESCRIBE_PLAIN_FILE", shell_plain.to_str().unwrap()),
    ];
    let rust_extra = [
        ("FAKE_DESCRIBE_JSON_CODE", "1"),
        ("FAKE_DESCRIBE_PLAIN_FILE", rust_plain.to_str().unwrap()),
    ];
    let shell_out = shell.run_shell(&script, &["--update", "bar"], &shell_extra);
    let rust_out = rust.run_rust(&["--update", "bar"], &rust_extra);
    compare("describe-plain", &shell, &rust, &shell_out, &rust_out);
}

#[test]
fn measure_live_is_identical() {
    let zombie = Zombie::new();
    let (shell, rust, script) = pair(Tool::Measure, "live", &zombie, |case| {
        case.set("PLEAMAR_WM_BIN", "/nonexistent/pleamar-wm");
    });
    let extra = [("WAYLAND_DISPLAY", "wayland-1")];
    run_pair(
        "measure-live",
        &["bar", "--seconds", "2", "--live"],
        &shell,
        &rust,
        &script,
        &extra,
        &extra,
    );
}

#[test]
fn smoke_require_render_failure_is_identical() {
    let zombie = Zombie::new();
    let (shell, rust, script) = pair(Tool::Smoke, "require", &zombie, |case| {
        case.remove_fake("pleamar-wm");
        case.remove_fake("grim");
        case.remove_fake("sway");
        case.remove_fake("cage");
    });
    run_pair(
        "smoke-require",
        &["--require-render", "--seconds", "4"],
        &shell,
        &rust,
        &script,
        &[],
        &[],
    );
}
