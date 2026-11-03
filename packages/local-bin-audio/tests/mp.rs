//! Hermetic tests for the `mp` port: the help dispatch, the `find | xargs` and
//! file-list pipelines, the `mpv` redirection and the background argv.

mod support;

use support::{text, Sandbox};

const BIN: &str = env!("CARGO_BIN_EXE_mp");

const FIND: &str = "printf '%s\\0' \"${FAKE_FIND_OUT:-media dir/c.wav}\"\n";
const XARGS: &str = r#"payload="$HOME/xargs.stdin"
while IFS= read -r -d '' item; do printf '%s\0' "$item" >> "$payload"; done
exit "${FAKE_XARGS_CODE:-0}"
"#;
const MKDIR: &str = "exit \"${FAKE_MKDIR_CODE:-0}\"\n";
const MPV: &str = "printf 'mpv-out\\n'\nprintf 'mpv-err\\n' >&2\nexit \"${FAKE_MPV_CODE:-0}\"\n";

fn fixture(label: &str) -> Sandbox {
    let sandbox = Sandbox::new(label, BIN);
    sandbox.fake("find", FIND);
    sandbox.fake("xargs", XARGS);
    sandbox.fake("mkdir", MKDIR);
    sandbox.fake("mpv", MPV);
    std::fs::create_dir_all(sandbox.home.join("tmp")).expect("create HOME/tmp");
    sandbox
}

fn wait_for(sandbox: &Sandbox, relative: &str) -> Vec<u8> {
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    loop {
        let path = sandbox.home.join(relative);
        if let Ok(bytes) = std::fs::read(&path) {
            if !bytes.is_empty() || std::time::Instant::now() >= deadline {
                return bytes;
            }
        }
        if std::time::Instant::now() >= deadline {
            return Vec::new();
        }
        std::thread::sleep(std::time::Duration::from_millis(20));
    }
}

#[test]
fn help_prints_the_header() {
    let sandbox = fixture("help");
    for flag in ["-h", "--help"] {
        let outcome = sandbox.run(&[flag]);
        assert_eq!(outcome.code, 0);
        assert_eq!(
            text(&outcome.stdout),
            "mp: play with mpv and print media info for inputs concurrently\n\
             Usage: mp FILES...\n\
             \u{20}\u{20}Spawns vid-info for provided files/dirs and plays them via mpv.\n"
        );
        assert_eq!(outcome.stderr, b"");
    }
    assert_eq!(sandbox.log(), "");
}

#[test]
fn file_arguments_drive_the_background_pipeline() {
    let sandbox = fixture("files");
    sandbox.write("a.mp3", b"a");
    sandbox.write("b.flac", b"b");
    sandbox.write("notes.txt", b"x");
    let outcome = sandbox.run(&["a.mp3", "b.flac", "notes.txt"]);
    assert_eq!(outcome.code, 0, "stderr={:?}", text(&outcome.stderr));
    assert_eq!(outcome.stdout, b"");
    assert_eq!(outcome.stderr, b"");
    let vid_info = format!("{}/.local/bin/vid-info", sandbox.home.display());
    let log = sandbox.wait_log("xargs");
    assert!(
        log.contains(&format!("xargs\t-0\t-n10\t-P\t10\t{vid_info}\n")),
        "{log}"
    );
    let payload = wait_for(&sandbox, "xargs.stdin");
    assert_eq!(payload, b"a.mp3\0b.flac\0notes.txt\0");
    assert_eq!(
        text(&sandbox.read_home("tmp/mpv.log")),
        "mpv-out\nmpv-err\n"
    );
    assert_eq!(
        sandbox.log_lines_for("mkdir"),
        vec![format!("mkdir\t-p\t--\t{}/tmp", sandbox.home.display())]
    );
    assert!(sandbox.log_lines_for("find").is_empty());
    assert_eq!(
        sandbox.log_lines_for("mpv"),
        vec!["mpv\t--quiet\t--\ta.mp3\tb.flac\tnotes.txt"]
    );
}

#[test]
fn directory_arguments_feed_find_into_xargs() {
    let sandbox = fixture("dirs");
    std::fs::create_dir_all(sandbox.case.join("media dir")).expect("create media directory");
    let outcome = sandbox.run(&["media dir"]);
    let vid_info = format!("{}/.local/bin/vid-info", sandbox.home.display());
    assert_eq!(outcome.code, 0);
    let log = sandbox.wait_log("find");
    assert!(
        log.contains("find\t--\tmedia dir\t-maxdepth\t1\t-type\tf\t-print0\n"),
        "{log}"
    );
    assert!(log.contains("xargs\t-0\t-n10\t-P\t10\tvid-info\n"), "{log}");
    assert!(
        log.contains(&format!("xargs\t-0\t-n10\t-P\t10\t{vid_info}\n")),
        "{log}"
    );
    assert_eq!(wait_for(&sandbox, "xargs.stdin"), b"media dir/c.wav\0");
}

#[test]
fn no_arguments_still_run_the_file_pipeline() {
    let sandbox = fixture("empty");
    let outcome = sandbox.run(&[]);
    assert_eq!(outcome.code, 0);
    let vid_info = format!("{}/.local/bin/vid-info", sandbox.home.display());
    let log = sandbox.wait_log("xargs");
    assert!(log.contains(&format!("\t{vid_info}\n")), "{log}");
    assert_eq!(sandbox.log_lines_for("mpv"), vec!["mpv\t--quiet\t--"]);
}

#[test]
fn the_mpv_status_is_the_exit_status() {
    let sandbox = fixture("status");
    sandbox.write("a.mp3", b"a");
    let outcome = sandbox.run_env(&["a.mp3"], &[("FAKE_MPV_CODE", "9")]);
    assert_eq!(outcome.code, 9);
}

#[test]
fn a_missing_mpv_reports_into_the_log_and_exits_127() {
    let sandbox = fixture("no-mpv");
    sandbox.write("a.mp3", b"a");
    sandbox.remove_fake("mpv");
    let outcome = sandbox.run(&["a.mp3"]);
    assert_eq!(outcome.code, 127);
    let log = text(&sandbox.read_home("tmp/mpv.log"));
    assert!(
        log.contains(&format!(
            "{}: line 26: mpv: command not found\n",
            sandbox.program().display()
        )),
        "{log}"
    );
}

#[test]
fn an_unopenable_log_file_is_a_redirect_error() {
    let sandbox = fixture("blocked-log");
    std::fs::remove_dir_all(sandbox.home.join("tmp")).expect("remove HOME/tmp");
    std::fs::write(sandbox.home.join("tmp"), b"not a directory\n").expect("block the log dir");
    let outcome = sandbox.run(&[]);
    assert_eq!(outcome.code, 1);
    assert_eq!(
        text(&outcome.stderr),
        format!(
            "{}: line 26: {}/tmp/mpv.log: Not a directory\n",
            sandbox.program().display(),
            sandbox.home.display()
        )
    );
    assert!(sandbox.log_lines_for("mpv").is_empty());
}

#[test]
fn a_failing_mkdir_does_not_block_mpv() {
    let sandbox = fixture("mkdir-fail");
    let outcome = sandbox.run_env(&[], &[("FAKE_MKDIR_CODE", "1")]);
    assert_eq!(outcome.code, 0);
}
