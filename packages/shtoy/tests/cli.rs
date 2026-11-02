//! End-to-end CLI tests for the local (non-network) paths.
//!
//! Every test builds a sandbox with XDG dirs, HOME and TMPDIR under a temporary
//! directory, clears the inherited environment and puts a fake `esshader` on
//! PATH. The fake records its arguments and a copy of the shader it was given,
//! so the tests can assert the exact rewrite and viewer invocation. No test
//! touches the network, and no test uses the user's real cache or config.

use std::ffi::OsStr;
use std::fs;
use std::io::Write;
use std::os::unix::fs::PermissionsExt;
use std::path::PathBuf;
use std::process::{Command, Output, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};

const BIN: &str = env!("CARGO_BIN_EXE_shtoy");
const HELP: &str = include_str!("../src/help.txt");

static COUNTER: AtomicU64 = AtomicU64::new(0);

struct Sandbox {
    root: PathBuf,
    cache: PathBuf,
    config: PathBuf,
    tmp: PathBuf,
    bin: PathBuf,
    capture: PathBuf,
}

impl Sandbox {
    fn new(label: &str) -> Self {
        let root = std::env::temp_dir().join(format!(
            "shtoy-cli-{label}-{}-{}",
            std::process::id(),
            COUNTER.fetch_add(1, Ordering::Relaxed)
        ));
        let cache = root.join("cache");
        let config = root.join("config");
        let tmp = root.join("tmp");
        let bin = root.join("bin");
        let capture = root.join("capture");
        for directory in [&cache, &config, &tmp, &bin, &capture] {
            fs::create_dir_all(directory).expect("sandbox directory");
        }
        Self {
            root,
            cache,
            config,
            tmp,
            bin,
            capture,
        }
    }

    fn command(&self) -> Command {
        let mut command = Command::new(BIN);
        command
            .env_clear()
            .env("HOME", &self.root)
            .env("XDG_CACHE_HOME", &self.cache)
            .env("XDG_CONFIG_HOME", &self.config)
            .env("TMPDIR", &self.tmp)
            .env("PATH", &self.bin)
            .env("LC_ALL", "C")
            .env("SHTOY_TEST_CAPTURE", &self.capture);
        command
    }

    fn run(&self, arguments: &[&OsStr]) -> Output {
        self.command().args(arguments).output().expect("run shtoy")
    }

    fn run_str(&self, arguments: &[&str]) -> Output {
        let arguments: Vec<&OsStr> = arguments.iter().map(OsStr::new).collect();
        self.run(&arguments)
    }

    fn install_esshader(&self, exit_code: i32) {
        // Resolved from the test process's PATH: the fake viewer runs with the
        // sandbox PATH, which holds no system tools of its own.
        let cp = find_system_program("cp");
        let script = format!(
            "#!/bin/sh\n\
             printf '%s\\n' \"$@\" > \"$SHTOY_TEST_CAPTURE/args\"\n\
             previous=\n\
             for argument in \"$@\"; do\n\
               if [ \"$previous\" = \"-s\" ]; then {cp} \"$argument\" \"$SHTOY_TEST_CAPTURE/shader\"; fi\n\
               previous=$argument\n\
             done\n\
             exit {exit_code}\n",
            cp = cp.display()
        );
        let program = self.bin.join("esshader");
        fs::write(&program, script).expect("write fake esshader");
        let mut permissions = fs::metadata(&program).unwrap().permissions();
        permissions.set_mode(0o755);
        fs::set_permissions(&program, permissions).unwrap();
    }

    fn write_shader(&self, name: &str, source: &[u8]) -> PathBuf {
        let path = self.root.join(name);
        fs::write(&path, source).expect("write shader");
        path
    }

    fn cached_shader(&self, id: &str, source: &[u8]) -> PathBuf {
        let directory = self.cache.join("shtoy");
        fs::create_dir_all(&directory).unwrap();
        let path = directory.join(format!("{id}.frag"));
        fs::write(&path, source).unwrap();
        path
    }

    fn shipped_shader(&self, id: &str, source: &[u8]) {
        let directory = self.config.join("shtoy/shaders");
        fs::create_dir_all(&directory).unwrap();
        fs::write(directory.join(format!("{id}.frag")), source).unwrap();
    }

    fn captured_args(&self) -> Vec<String> {
        let text = fs::read_to_string(self.capture.join("args")).expect("captured args");
        text.lines().map(str::to_string).collect()
    }

    fn captured_shader(&self) -> Vec<u8> {
        fs::read(self.capture.join("shader")).expect("captured shader")
    }
}

fn find_system_program(name: &str) -> PathBuf {
    let path = std::env::var_os("PATH").expect("test process PATH");
    for directory in std::env::split_paths(&path) {
        let candidate = directory.join(name);
        if candidate.is_file() {
            return candidate;
        }
    }
    panic!("{name} not found on the test process PATH");
}

impl Drop for Sandbox {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.root);
    }
}

fn stdout(output: &Output) -> String {
    String::from_utf8_lossy(&output.stdout).into_owned()
}

fn stderr(output: &Output) -> String {
    String::from_utf8_lossy(&output.stderr).into_owned()
}

fn code(output: &Output) -> i32 {
    output.status.code().expect("exit code")
}

#[test]
fn help_is_the_verbatim_shell_header() {
    let sandbox = Sandbox::new("help");
    let output = sandbox.run_str(&["--help"]);
    assert_eq!(stdout(&output), HELP);
    assert_eq!(stderr(&output), "");
    assert_eq!(code(&output), 0);

    for alias in ["-h", "help", "?"] {
        let output = sandbox.run_str(&[alias]);
        assert_eq!(stdout(&output), HELP, "alias {alias}");
        assert_eq!(code(&output), 0);
    }
}

#[test]
fn list_puts_cached_first_then_unshadowed_shipped_ids() {
    let sandbox = Sandbox::new("list");
    sandbox.cached_shader("ltffzl", b"cached");
    sandbox.cached_shader("Alpha", b"cached");
    sandbox.shipped_shader("ltffzl", b"shipped shadow");
    sandbox.shipped_shader("mtyGWy", b"shipped");
    sandbox.shipped_shader("Zed", b"shipped");

    let output = sandbox.run_str(&["--list"]);
    assert_eq!(
        stdout(&output),
        "Alpha\nltffzl\nZed (shipped)\nmtyGWy (shipped)\n"
    );
    assert_eq!(stderr(&output), "");
    assert_eq!(code(&output), 0);
}

#[test]
fn list_with_no_shaders_reports_the_shell_error() {
    let sandbox = Sandbox::new("list-empty");
    let output = sandbox.run_str(&["--list"]);
    assert_eq!(stdout(&output), "");
    assert_eq!(stderr(&output), "shtoy: no cached or shipped shaders\n");
    assert_eq!(code(&output), 1);
}

#[test]
fn list_ignores_a_positional_argument() {
    let sandbox = Sandbox::new("list-arg");
    sandbox.cached_shader("AbCd12", b"cached");
    let output = sandbox.run_str(&["--list", "ignored"]);
    assert_eq!(stdout(&output), "AbCd12\n");
    assert_eq!(code(&output), 0);
}

#[test]
fn save_prints_the_cached_path_for_ids_and_urls() {
    let sandbox = Sandbox::new("save");
    let cached = sandbox.cached_shader("AbCd12", b"cached");
    for argument in [
        "AbCd12",
        "https://www.shadertoy.com/view/AbCd12",
        "https://www.shadertoy.com/view/AbCd12/",
        "https://www.shadertoy.com/view/AbCd12?x=1",
        "https://example.com/view/AbCd12#fragment",
    ] {
        let output = sandbox.run_str(&["--save", argument]);
        assert_eq!(
            stdout(&output),
            format!("{}\n", cached.display()),
            "argument {argument}"
        );
        assert_eq!(stderr(&output), "", "argument {argument}");
        assert_eq!(code(&output), 0, "argument {argument}");
    }
}

#[test]
fn save_for_an_uncached_id_reports_the_shell_message() {
    let sandbox = Sandbox::new("save-missing");
    let output = sandbox.run_str(&["--save", "AbCd12"]);
    assert_eq!(stdout(&output), "");
    assert_eq!(
        stderr(&output),
        "shtoy: no cached copy of AbCd12 — copy the shader source on https://www.shadertoy.com/view/AbCd12, then run: shtoy --import AbCd12\n"
    );
    assert_eq!(code(&output), 1);
}

#[test]
fn save_rejects_a_stream() {
    let sandbox = Sandbox::new("save-stream");
    let output = sandbox.run_str(&["--save", "-"]);
    assert_eq!(
        stderr(&output),
        "shtoy: --save takes a Shadertoy id or URL, not a stream\n"
    );
    assert_eq!(code(&output), 1);
}

#[test]
fn save_and_import_reject_a_file() {
    let sandbox = Sandbox::new("file-modes");
    let shader = sandbox.write_shader("local.frag", b"void mainImage(){}");
    let path = shader.to_string_lossy().into_owned();
    for arguments in [
        vec!["--save", &path],
        vec!["--import", &path],
        vec!["--mirror", &path],
    ] {
        let output = sandbox.run_str(&arguments);
        assert_eq!(
            stderr(&output),
            "shtoy: --import/--mirror/--save take a Shadertoy id or URL, not a file\n"
        );
        assert_eq!(code(&output), 1);
    }
}

#[test]
fn file_shader_is_passed_to_the_viewer_and_its_status_is_propagated() {
    let sandbox = Sandbox::new("file-run");
    sandbox.install_esshader(7);
    let shader = sandbox.write_shader(
        "local.frag",
        b"void mainImage(out vec4 c, in vec2 u) { c = vec4(1.0); }\n",
    );
    let path = shader.to_string_lossy().into_owned();

    let output = sandbox.run_str(&[&path]);
    assert_eq!(stdout(&output), "");
    assert_eq!(stderr(&output), format!("shtoy: running {path}\n"));
    assert_eq!(code(&output), 7);
    assert_eq!(sandbox.captured_args(), vec!["-f", "-s", path.as_str()]);
    assert_eq!(sandbox.captured_shader(), fs::read(&shader).unwrap());
}

#[test]
fn stdin_shader_is_copied_to_a_temporary_file() {
    let sandbox = Sandbox::new("stdin-run");
    sandbox.install_esshader(0);
    let source = b"void mainImage(out vec4 c, in vec2 u) { c = vec4(0.5); }\n";

    let mut child = sandbox
        .command()
        .arg("-")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn shtoy");
    child
        .stdin
        .take()
        .expect("stdin")
        .write_all(source)
        .expect("write stdin");
    let output = child.wait_with_output().expect("wait for shtoy");

    assert_eq!(code(&output), 0);
    assert_eq!(sandbox.captured_shader(), source);
    let arguments = sandbox.captured_args();
    assert_eq!(arguments.len(), 3);
    assert_eq!(&arguments[..2], ["-f", "-s"]);
    assert!(arguments[2].starts_with(sandbox.tmp.to_string_lossy().as_ref()));
    assert!(arguments[2].ends_with(".frag"));
    assert_eq!(
        stderr(&output),
        format!("shtoy: running {}\n", arguments[2])
    );
}

#[test]
fn version_lines_and_frame_defines_are_rewritten_byte_for_byte() {
    let sandbox = Sandbox::new("rewrite");
    sandbox.install_esshader(0);
    let shader = sandbox.write_shader(
        "versioned.frag",
        b"#version 300 es\nfloat f = iFrame;\nfloat d = iTimeDelta;\n",
    );
    let path = shader.to_string_lossy().into_owned();

    let output = sandbox.run_str(&[&path]);
    assert_eq!(code(&output), 0);
    assert_eq!(
        sandbox.captured_shader(),
        b"#define iFrame int(iTime * 60.0)\n#define iTimeDelta (1.0 / 60.0)\nfloat f = iFrame;\nfloat d = iTimeDelta;\n"
    );
    let arguments = sandbox.captured_args();
    assert_eq!(&arguments[..2], ["-f", "-s"]);
    assert_ne!(arguments[2], path);
    assert!(arguments[2].starts_with(sandbox.tmp.to_string_lossy().as_ref()));
    assert_eq!(
        stderr(&output),
        format!("shtoy: running {}\n", arguments[2])
    );
}

#[test]
fn texture2d_selects_legacy_and_unbound_channels_are_noted() {
    let sandbox = Sandbox::new("legacy");
    sandbox.install_esshader(0);
    let shader = sandbox.write_shader(
        "legacy.frag",
        b"void mainImage(out vec4 c, in vec2 u) { c = texture2D(iChannel0, u); }\n",
    );
    let path = shader.to_string_lossy().into_owned();

    let output = sandbox.run_str(&[&path]);
    assert_eq!(code(&output), 0);
    assert_eq!(
        stderr(&output),
        format!(
            "shtoy: note: {path} samples iChannel0 with no texture bound (--channel 0 FILE)\n\
             shtoy: GLES2/GLSL 100 requested by source (texture2D)\n\
             shtoy: running {path}\n"
        )
    );
    assert_eq!(
        sandbox.captured_args(),
        vec!["-f", "-s", path.as_str(), "-l"]
    );
}

#[test]
fn channels_keyboard_and_explicit_legacy_keep_the_shell_argument_order() {
    let sandbox = Sandbox::new("channels");
    sandbox.install_esshader(0);
    let shader = sandbox.write_shader(
        "channels.frag",
        b"void mainImage(out vec4 c, in vec2 u) { c = vec4(iChannel2); }\n",
    );
    let texture = sandbox.root.join("texture.png");
    fs::write(&texture, b"png").unwrap();
    let shader_path = shader.to_string_lossy().into_owned();
    let texture_path = texture.to_string_lossy().into_owned();

    let output = sandbox.run_str(&[
        "--legacy",
        "--channel",
        "2",
        &texture_path,
        "--keyboard",
        "0",
        &shader_path,
    ]);
    assert_eq!(code(&output), 0);
    assert_eq!(
        sandbox.captured_args(),
        vec![
            "-f",
            "-s",
            shader_path.as_str(),
            "-l",
            "-k",
            "0",
            "-2",
            texture_path.as_str(),
        ]
    );
    assert_eq!(stderr(&output), format!("shtoy: running {shader_path}\n"));
}

#[test]
fn missing_esshader_uses_the_require_message_after_the_notes() {
    let sandbox = Sandbox::new("no-esshader");
    let shader = sandbox.write_shader("plain.frag", b"void mainImage(){}\n");
    let path = shader.to_string_lossy().into_owned();

    let output = sandbox.run_str(&[&path]);
    assert_eq!(stdout(&output), "");
    assert_eq!(stderr(&output), "shtoy: missing dependency: esshader\n");
    assert_eq!(code(&output), 1);
}

#[test]
fn argument_errors_match_the_shell_diagnostics() {
    let sandbox = Sandbox::new("errors");
    let shader = sandbox.write_shader("plain.frag", b"void mainImage(){}\n");
    let path = shader.to_string_lossy().into_owned();
    let texture = sandbox.root.join("texture.png");
    fs::write(&texture, b"png").unwrap();
    let texture_path = texture.to_string_lossy().into_owned();

    let cases: Vec<(Vec<&str>, &str, i32)> = vec![
        (
            vec!["--bogus"],
            "shtoy: unknown option: --bogus (see --help)",
            1,
        ),
        (
            vec!["some-file.frag", "-h"],
            "shtoy: unknown option: -h (see --help)",
            1,
        ),
        (vec![], "shtoy: no shader given (see --help)", 1),
        (
            vec!["one", "two"],
            "shtoy: more than one shader given: one, two",
            1,
        ),
        (
            vec!["--channel"],
            "shtoy: --channel needs a number and a file",
            1,
        ),
        (
            vec!["--channel", "0"],
            "shtoy: --channel needs a number and a file",
            1,
        ),
        (
            vec!["--channel", "9", "x"],
            "shtoy: channel number must be 0..3, got: 9",
            1,
        ),
        (
            vec!["--channel", "0", "/no/such/texture.png"],
            "shtoy: channel texture not found: /no/such/texture.png",
            1,
        ),
        (
            vec!["--keyboard"],
            "shtoy: --keyboard needs a channel number",
            1,
        ),
        (
            vec!["--keyboard", "x"],
            "shtoy: channel number must be 0..3, got: x",
            1,
        ),
        (
            vec!["/no/such/file", "and-another"],
            "shtoy: more than one shader given: /no/such/file, and-another",
            1,
        ),
        (
            vec!["--keyboard", "1", "--channel", "1", &texture_path],
            "shtoy: channel 1 is bound to both a texture and the keyboard",
            1,
        ),
        (
            vec!["/no/such/file"],
            "shtoy: not a file, and not a Shadertoy id: /no/such/file",
            1,
        ),
    ];

    for (arguments, expected, expected_code) in cases {
        let output = sandbox.run_str(&arguments);
        let mut stderr_text = stderr(&output);
        if !stderr_text.ends_with('\n') {
            stderr_text.push('\n');
        }
        assert_eq!(stdout(&output), "", "{arguments:?}");
        assert_eq!(stderr_text, format!("{expected}\n"), "{arguments:?}");
        assert_eq!(code(&output), expected_code, "{arguments:?}");
    }

    let _ = path;
}

#[test]
fn double_dash_makes_the_rest_positional() {
    let sandbox = Sandbox::new("double-dash");
    sandbox.install_esshader(0);
    let shader = sandbox.write_shader("plain.frag", b"void mainImage(){}\n");
    let path = shader.to_string_lossy().into_owned();

    let output = sandbox.run_str(&["--", &path]);
    assert_eq!(code(&output), 0);
    assert_eq!(sandbox.captured_args(), vec!["-f", "-s", path.as_str()]);

    let output = sandbox.run_str(&["--", &path, "extra"]);
    assert_eq!(
        stderr(&output),
        format!("shtoy: more than one shader given: {path}, extra\n")
    );
    assert_eq!(code(&output), 1);
}

#[test]
fn shipped_shader_is_run_without_copying_it_to_the_cache() {
    let sandbox = Sandbox::new("shipped");
    sandbox.install_esshader(0);
    sandbox.shipped_shader("mtyGWy", b"void mainImage(){}\n");

    let output = sandbox.run_str(&["https://www.shadertoy.com/view/mtyGWy"]);
    assert_eq!(code(&output), 0);
    let shipped = sandbox
        .config
        .join("shtoy/shaders/mtyGWy.frag")
        .to_string_lossy()
        .into_owned();
    assert_eq!(sandbox.captured_args(), vec!["-f", "-s", shipped.as_str()]);
    assert!(!sandbox.cache.join("shtoy/mtyGWy.frag").exists());
}
