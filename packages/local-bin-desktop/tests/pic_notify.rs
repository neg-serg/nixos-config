//! Hermetic tests for the `pic-notify` port.

mod support;

use std::path::PathBuf;

use local_bin_desktop::helptext::PIC_NOTIFY_USAGE;
use support::*;

const BIN: &str = env!("CARGO_BIN_EXE_pic-notify");

fn image(sandbox: &Sandbox, name: &str) -> PathBuf {
    let path = sandbox.case.join(name);
    sandbox.write(&path, b"PNGDATA");
    sandbox.set_mtime(&path, 1_767_000_000);
    path
}

fn event_paths(sandbox: &Sandbox) -> (PathBuf, PathBuf) {
    (
        sandbox.home.join(".cache/pleamar/screenshot-event.json"),
        sandbox.home.join(".cache/quickshell/screenshot-event.json"),
    )
}

#[test]
fn usage_keeps_exit_1_even_for_help() {
    let sandbox = Sandbox::new("pn-usage");
    sandbox.install_default_fakes();
    for arguments in [vec![], vec!["-h"], vec!["--help"]] {
        let outcome = sandbox.run(BIN, &arguments);
        assert_eq!(outcome.code, 1, "arguments {arguments:?}");
        assert_eq!(outcome.stdout, PIC_NOTIFY_USAGE.as_bytes());
        assert_eq!(outcome.stderr, b"");
        assert!(sandbox.log().is_empty());
    }
}

#[test]
fn normal_flow_writes_both_events_and_the_clipboard() {
    let sandbox = Sandbox::new("pn-normal");
    sandbox.install_default_fakes();
    let path = image(&sandbox, "shot.png");
    let outcome = sandbox.run_env(
        BIN,
        &[path.to_str().unwrap()],
        &[
            ("FAKE_IDENTIFY_OUT", "1920 1080 8 srgba 4.0"),
            ("FAKE_DATE_OUT", "2026-01-02 03:04:05"),
        ],
    );
    assert_eq!(outcome.code, 0);
    assert_eq!(outcome.stdout, b"");
    assert_eq!(outcome.stderr, b"");

    assert_eq!(
        sandbox.calls("wl-copy"),
        vec![call("wl-copy", &[])],
        "the clipboard only carries the path"
    );
    assert_eq!(
        sandbox.last_clip(),
        format!("{}\n", path.display()).into_bytes()
    );

    let expected = format!(
        "{{\n  \"path\": \"{}\",\n  \"w\": 1920,\n  \"h\": 1080,\n  \"sizeHr\": \"0 KB\",\n  \"depth\": \"8-bit RGBA\",\n  \"ts\": \"2026-01-02 03:04:05\"\n}}\n",
        path.display()
    );
    let (pleamar, quickshell) = event_paths(&sandbox);
    assert_eq!(sandbox.read(&pleamar), expected.as_bytes());
    assert_eq!(sandbox.read(&quickshell), expected.as_bytes());
    assert!(sandbox
        .home
        .join(".cache/quickshell/screenshot-event")
        .exists());

    let notifications = sandbox.notifications();
    assert_eq!(notifications.len(), 1);
    let expected_body = format!(
        "1920×1080  ·  0 KB  ·  8-bit RGBA\\n{}\\n2026-01-02 03:04:05",
        path.display()
    );
    assert_eq!(
        notifications[0],
        vec![
            b"-h".to_vec(),
            b"string:fgcolor:#6C7E96".to_vec(),
            b"-a".to_vec(),
            b"screenshot".to_vec(),
            b"-i".to_vec(),
            path.display().to_string().into_bytes(),
            "📸 Screenshot".as_bytes().to_vec(),
            expected_body.into_bytes(),
        ]
    );
    assert_eq!(
        sandbox.calls("identify"),
        vec![call(
            "identify",
            &[
                "-ping",
                "-format",
                "%w %h %z %[channels]",
                path.to_str().unwrap()
            ]
        )]
    );
    assert_eq!(
        sandbox.calls("date"),
        vec![call("date", &["-d", "@1767000000", "+%F %T"])],
        "the filename carries no timestamp, so the mtime is formatted"
    );
}

#[test]
fn answering_ipc_suppresses_notify_send() {
    let sandbox = Sandbox::new("pn-ipc");
    sandbox.install_default_fakes();
    let path = image(&sandbox, "shot.png");
    let outcome = sandbox.run_env(
        BIN,
        &[path.to_str().unwrap()],
        &[("FAKE_PLEAMAR_EXIT", "0"), ("FAKE_DATE_OUT", "x")],
    );
    assert_eq!(outcome.code, 0);
    assert!(sandbox.notifications().is_empty());
    assert_eq!(
        sandbox.calls("timeout"),
        vec![call(
            "timeout",
            &["2", "pleamar", "--say", "toast", "describe"]
        )]
    );
}

#[test]
fn quickshell_alone_can_keep_the_toast() {
    let sandbox = Sandbox::new("pn-ipc2");
    sandbox.install_default_fakes();
    let path = image(&sandbox, "shot.png");
    let outcome = sandbox.run_env(
        BIN,
        &[path.to_str().unwrap()],
        &[
            ("FAKE_PLEAMAR_EXIT", "1"),
            ("FAKE_QUICKSHELL_EXIT", "0"),
            ("FAKE_DATE_OUT", "x"),
        ],
    );
    assert_eq!(outcome.code, 0);
    assert!(sandbox.notifications().is_empty());
    assert_eq!(sandbox.calls("timeout").len(), 2);
}

#[test]
fn no_identify_leaves_the_metadata_empty() {
    let sandbox = Sandbox::new("pn-noidentify");
    sandbox.install_default_fakes();
    std::fs::remove_file(sandbox.bin.join("identify")).expect("drop identify");
    let path = image(&sandbox, "shot.png");
    let outcome = sandbox.run_env(
        BIN,
        &[path.to_str().unwrap()],
        &[("FAKE_PLEAMAR_EXIT", "0"), ("FAKE_DATE_OUT", "x")],
    );
    assert_eq!(outcome.code, 0);
    let (pleamar, _) = event_paths(&sandbox);
    let event = str_of(&sandbox.read(&pleamar));
    assert!(event.contains("\"w\": 0"), "{event}");
    assert!(event.contains("\"h\": 0"), "{event}");
    assert!(event.contains("\"depth\": \"\""), "{event}");
}

#[test]
fn channel_labels_match_the_imagemagick_spellings() {
    let sandbox = Sandbox::new("pn-channels");
    for (identify, depth) in [
        ("1 1 8 1", "8-bit Gray"),
        ("1 1 8 2", "8-bit Gray+Alpha"),
        ("1 1 8 3", "8-bit RGB"),
        ("1 1 8 4", "8-bit RGBA"),
        ("1 1 8 srgba 4.0", "8-bit RGBA"),
        ("1 1 8 graya 2.0", "8-bit Gray+Alpha"),
        ("1 1 8 gray", "8-bit Gray"),
        ("1 1 8 srgb", "8-bit RGB"),
        ("1 1 8 5", "8-bit 5ch"),
    ] {
        sandbox.reset();
        sandbox.install_default_fakes();
        let path = image(&sandbox, "shot.png");
        let outcome = sandbox.run_env(
            BIN,
            &[path.to_str().unwrap()],
            &[
                ("FAKE_IDENTIFY_OUT", identify),
                ("FAKE_PLEAMAR_EXIT", "0"),
                ("FAKE_DATE_OUT", "x"),
            ],
        );
        assert_eq!(outcome.code, 0, "identify {identify}");
        let (pleamar, _) = event_paths(&sandbox);
        let event = str_of(&sandbox.read(&pleamar));
        assert!(
            event.contains(&format!("\"depth\": \"{depth}\"")),
            "{identify}: {event}"
        );
    }
}

#[test]
fn bmp_paths_are_copied_as_png() {
    let sandbox = Sandbox::new("pn-bmp");
    sandbox.install_default_fakes();
    let path = image(&sandbox, "shot.bmp");
    let outcome = sandbox.run_env(
        BIN,
        &[path.to_str().unwrap()],
        &[("FAKE_PLEAMAR_EXIT", "0"), ("FAKE_DATE_OUT", "x")],
    );
    assert_eq!(outcome.code, 0);
    assert_eq!(
        sandbox.last_clip(),
        format!("{}\n", path.with_extension("png").display()).into_bytes()
    );
}

#[test]
fn timestamp_comes_from_the_file_name_first() {
    let sandbox = Sandbox::new("pn-ts");
    sandbox.install_default_fakes();
    let path = image(&sandbox, "shot-20260102-03.04.05.png");
    let outcome = sandbox.run_env(
        BIN,
        &[path.to_str().unwrap()],
        &[("FAKE_PLEAMAR_EXIT", "0")],
    );
    assert_eq!(outcome.code, 0);
    let (pleamar, _) = event_paths(&sandbox);
    assert!(str_of(&sandbox.read(&pleamar)).contains("\"ts\": \"2026-01-02 03:04:05\""));
    assert!(sandbox.calls("date").is_empty(), "no date call needed");
}

#[test]
fn failing_date_leaves_the_timestamp_empty() {
    let sandbox = Sandbox::new("pn-datefail");
    sandbox.install_default_fakes();
    sandbox.fake("date", "exit 1\n");
    let path = image(&sandbox, "shot.png");
    let outcome = sandbox.run_env(
        BIN,
        &[path.to_str().unwrap()],
        &[("FAKE_PLEAMAR_EXIT", "0")],
    );
    assert_eq!(outcome.code, 0);
    let (pleamar, _) = event_paths(&sandbox);
    assert!(str_of(&sandbox.read(&pleamar)).contains("\"ts\": \"\""));
}

#[test]
fn fallback_body_uses_the_home_tilde_and_literal_newlines() {
    let sandbox = Sandbox::new("pn-body");
    sandbox.install_default_fakes();
    let path = sandbox.home.join("shot.png");
    sandbox.write(&path, b"PNGDATA");
    sandbox.set_mtime(&path, 1_767_000_000);
    let outcome = sandbox.run_env(
        BIN,
        &[path.to_str().unwrap()],
        &[
            ("FAKE_IDENTIFY_OUT", "640 480 8 RGB"),
            ("FAKE_DATE_OUT", "2026-01-02 03:04:05"),
        ],
    );
    assert_eq!(outcome.code, 0);
    let notifications = sandbox.notifications();
    let body = str_of(&notifications[0][7]);
    assert!(body.contains("640×480"), "{body}");
    assert!(body.contains("\\n~/shot.png\\n"), "{body}");
}

#[test]
fn xdg_cache_home_overrides_the_pleamar_directory() {
    let sandbox = Sandbox::new("pn-cache");
    sandbox.install_default_fakes();
    let path = image(&sandbox, "shot.png");
    let cache = sandbox.case.join("cache");
    let outcome = sandbox.run_env(
        BIN,
        &[path.to_str().unwrap()],
        &[
            ("FAKE_PLEAMAR_EXIT", "0"),
            ("FAKE_DATE_OUT", "x"),
            ("XDG_CACHE_HOME", cache.to_str().unwrap()),
        ],
    );
    assert_eq!(outcome.code, 0);
    assert!(cache.join("pleamar/screenshot-event.json").exists());
    assert!(!sandbox
        .home
        .join(".cache/pleamar/screenshot-event.json")
        .exists());
}

#[test]
fn human_sizes_match_awk_printf() {
    let sandbox = Sandbox::new("pn-sizes");
    for (size, expected) in [
        (1024u64, "1 KB"),
        (1536, "2 KB"),
        (1_048_576, "1.00 MB"),
        (1_572_864, "1.50 MB"),
        (1_073_741_824, "1.0 GB"),
        (2_147_483_648, "2.0 GB"),
    ] {
        sandbox.reset();
        sandbox.install_default_fakes();
        let path = image(&sandbox, "shot.png");
        let file = std::fs::File::options()
            .write(true)
            .open(&path)
            .expect("open image");
        file.set_len(size).expect("sparse file");
        drop(file);
        let outcome = sandbox.run_env(
            BIN,
            &[path.to_str().unwrap()],
            &[
                ("FAKE_IDENTIFY_OUT", "1 1 8 RGB"),
                ("FAKE_PLEAMAR_EXIT", "0"),
                ("FAKE_DATE_OUT", "x"),
            ],
        );
        assert_eq!(outcome.code, 0);
        let (pleamar, _) = event_paths(&sandbox);
        let event = str_of(&sandbox.read(&pleamar));
        assert!(
            event.contains(&format!("\"sizeHr\": \"{expected}\"")),
            "size {size}: {event}"
        );
    }
}

#[test]
fn notify_send_status_is_the_exit_status() {
    let sandbox = Sandbox::new("pn-notifystatus");
    sandbox.install_default_fakes();
    let path = image(&sandbox, "shot.png");
    let outcome = sandbox.run_env(
        BIN,
        &[path.to_str().unwrap()],
        &[("FAKE_DATE_OUT", "x"), ("FAKE_NOTIFY_EXIT", "7")],
    );
    assert_eq!(outcome.code, 7);
}
