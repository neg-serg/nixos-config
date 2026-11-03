//! Hermetic tests for the `pngoptim` port: argument checks, `_localbin.sh` help
//! dispatch and the oxipng invocation.

mod support;

use std::path::PathBuf;

use local_bin_desktop::helptext::PNGOPTIM_USAGE;
use support::*;

const BIN: &str = env!("CARGO_BIN_EXE_pngoptim");

fn png(sandbox: &Sandbox) -> PathBuf {
    let path = sandbox.case.join("image.png");
    sandbox.write(&path, b"PNGDATA");
    path
}

#[test]
fn help_variants_print_the_usage_on_stderr_and_exit_1() {
    let sandbox = Sandbox::new("pngoptim-help");
    sandbox.install_default_fakes();
    for arguments in [vec!["-h"], vec!["--help"], vec!["help"], vec!["?"]] {
        let outcome = sandbox.run(BIN, &arguments);
        assert_eq!(outcome.code, 1, "arguments {arguments:?}");
        assert_eq!(outcome.stdout, b"");
        assert_eq!(outcome.stderr, PNGOPTIM_USAGE.as_bytes());
    }
}

#[test]
fn missing_argument_prints_the_usage() {
    let sandbox = Sandbox::new("pngoptim-noarg");
    sandbox.install_default_fakes();
    for arguments in [vec![], vec![""]] {
        let outcome = sandbox.run(BIN, &arguments);
        assert_eq!(outcome.code, 1);
        assert_eq!(outcome.stderr, PNGOPTIM_USAGE.as_bytes());
        assert!(sandbox.log().is_empty());
    }
}

#[test]
fn missing_file_is_reported() {
    let sandbox = Sandbox::new("pngoptim-missing");
    sandbox.install_default_fakes();
    let path = sandbox.case.join("gone.png");
    let outcome = sandbox.run(BIN, &[path.to_str().unwrap()]);
    assert_eq!(outcome.code, 1);
    assert_eq!(
        str_of(&outcome.stderr),
        format!("pngoptim: no such file: {}\n", path.display())
    );
}

#[test]
fn non_png_file_is_rejected() {
    let sandbox = Sandbox::new("pngoptim-notpng");
    sandbox.install_default_fakes();
    let path = sandbox.case.join("image.txt");
    sandbox.write(&path, b"TEXT");
    let outcome = sandbox.run(BIN, &[path.to_str().unwrap()]);
    assert_eq!(outcome.code, 1);
    assert_eq!(
        str_of(&outcome.stderr),
        format!("pngoptim: not a PNG: {}\n", path.display())
    );
}

#[test]
fn oxipng_receives_the_original_argv() {
    let sandbox = Sandbox::new("pngoptim-run");
    sandbox.install_default_fakes();
    let path = png(&sandbox);
    let outcome = sandbox.run(BIN, &[path.to_str().unwrap()]);
    assert_eq!(outcome.code, 0);
    assert_eq!(outcome.stdout, b"");
    assert_eq!(outcome.stderr, b"");
    assert_eq!(
        sandbox.log(),
        vec![call(
            "oxipng",
            &[
                "-o",
                "max",
                "-z",
                "--strip",
                "safe",
                "--",
                path.to_str().unwrap()
            ]
        )]
    );
}

#[test]
fn uppercase_extension_is_accepted() {
    let sandbox = Sandbox::new("pngoptim-upper");
    sandbox.install_default_fakes();
    let path = sandbox.case.join("IMAGE.PNG");
    sandbox.write(&path, b"PNGDATA");
    let outcome = sandbox.run(BIN, &[path.to_str().unwrap()]);
    assert_eq!(outcome.code, 0);
}

#[test]
fn missing_oxipng_warns_and_the_dispatch_fails_like_the_shell() {
    let sandbox = Sandbox::new("pngoptim-nooxipng");
    sandbox.install_default_fakes();
    std::fs::remove_file(sandbox.bin.join("oxipng")).expect("drop fake oxipng");
    let path = png(&sandbox);
    let outcome = sandbox.run(BIN, &[path.to_str().unwrap()]);
    assert_eq!(outcome.code, 127);
    let stderr = str_of(&outcome.stderr);
    assert!(
        stderr.starts_with("pngoptim: missing oxipng\n"),
        "stderr: {stderr:?}"
    );
    assert!(
        stderr.contains(": line 26: oxipng: command not found\n"),
        "stderr: {stderr:?}"
    );
}

#[test]
fn oxipng_status_is_propagated() {
    let sandbox = Sandbox::new("pngoptim-status");
    sandbox.install_default_fakes();
    let path = png(&sandbox);
    let outcome = sandbox.run_env(BIN, &[path.to_str().unwrap()], &[("FAKE_OXIPNG_EXIT", "2")]);
    assert_eq!(outcome.code, 2);
}
