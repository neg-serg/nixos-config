//! Hermetic tests for the `sx` port.
//!
//! swayimg is a fake that records its argv and the list read from the `-f`
//! file. The test tree is a temporary directory; no real gallery window is
//! opened.

mod support;

use std::os::unix::fs::symlink;
use std::path::Path;
use std::thread::sleep;
use std::time::Duration;

use support::{exited, expected_argv, stderr, stdout, Case};

const BIN: &str = env!("CARGO_BIN_EXE_sx");

const SWAYIMG: &str = r#"#!/bin/sh
{ printf 'swayimg\n'; for a in "$@"; do printf 'ARG %s\n' "$a"; done; } >> "$FAKE_LOG_DIR/swayimg.argv"
file=""
previous=""
for a in "$@"; do
  if [ "$previous" = "-f" ]; then file=$a; fi
  previous=$a
done
: > "$FAKE_LOG_DIR/swayimg.stdin"
# Like swayimg, read the list from the path named by -f; "-" is a literal
# filename there, so a `-f -` regression leaves the log empty.
if [ -n "$file" ] && [ -r "$file" ]; then
  while IFS= read -r line || [ -n "$line" ]; do printf '%s\n' "$line" >> "$FAKE_LOG_DIR/swayimg.stdin"; done < "$file"
fi
exit "${FAKE_SWAYIMG_CODE:-0}"
"#;

const HOME_SWAYIMG: &str = r#"#!/bin/sh
{ printf 'swayimg-home\n'; for a in "$@"; do printf 'ARG %s\n' "$a"; done; } >> "$FAKE_LOG_DIR/swayimg-home.argv"
: > "$FAKE_LOG_DIR/swayimg-home.stdin"
while IFS= read -r line || [ -n "$line" ]; do printf '%s\n' "$line" >> "$FAKE_LOG_DIR/swayimg-home.stdin"; done
exit "${FAKE_SWAYIMG_CODE:-0}"
"#;

const PATH_SWAYIMG: &str = r#"#!/bin/sh
{ printf 'swayimg-path\n'; for a in "$@"; do printf 'ARG %s\n' "$a"; done; } >> "$FAKE_LOG_DIR/swayimg-path.argv"
exit 0
"#;

fn case(label: &str) -> Case {
    let case = Case::new(label, BIN);
    case.write_fake("swayimg", SWAYIMG);
    case
}

fn touch(path: &Path) {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).expect("create image directory");
    }
    std::fs::write(path, b"x").expect("write image fixture");
}

fn expected_list(case: &Case, lines: &[&str]) -> String {
    let _ = case;
    let mut text = String::new();
    for line in lines {
        text.push_str(line);
        text.push('\n');
    }
    text
}

#[test]
fn help_is_written_to_stderr_and_does_not_launch() {
    let case = case("sx-help");
    for argument in ["-h", "--help"] {
        let output = case.run(&[argument]);
        assert_eq!(exited(&output), 0, "{argument}");
        assert_eq!(stderr(&output), "Usage: sx [DIR...]\n", "{argument}");
        assert_eq!(stdout(&output), "", "{argument}");
        assert_eq!(case.argv("swayimg"), "", "{argument}");
    }
}

#[test]
fn a_missing_swayimg_is_an_error() {
    let case = Case::new("sx-missing", BIN);
    let pictures = case.path("pictures");
    std::fs::create_dir_all(&pictures).expect("pictures");
    let output = case.run_in(&pictures, &[]);
    assert_eq!(exited(&output), 1);
    assert_eq!(
        stderr(&output),
        "sx: swayimg not found in PATH or ~/.local/bin\n"
    );
}

#[test]
fn no_arguments_defaults_to_the_current_directory() {
    let case = case("sx-default-dot");
    let pictures = case.path("pictures");
    touch(&pictures.join("a.png"));
    let output = case.run_in(&pictures, &[]);
    assert_eq!(exited(&output), 0);
    assert_eq!(case.stdin("swayimg"), expected_list(&case, &["./a.png"]));
    let config = case.path("xdg/config/swayimg/init.lua");
    assert_eq!(
        case.argv("swayimg"),
        expected_argv(
            "swayimg",
            &[
                "-c",
                &config.to_string_lossy(),
                "-g",
                "-f",
                "/proc/self/fd/0"
            ]
        )
    );
}

#[test]
fn images_are_recursive_sorted_by_ctime_and_filtered_by_extension() {
    let case = case("sx-sort");
    let pictures = case.path("pictures");
    touch(&pictures.join("a.png"));
    sleep(Duration::from_millis(30));
    touch(&pictures.join("b.jpg"));
    sleep(Duration::from_millis(30));
    touch(&pictures.join("sub/c.jpeg"));
    sleep(Duration::from_millis(30));
    touch(&pictures.join("sub/deep/d.GIF"));
    // Non-images and near-misses stay out.
    touch(&pictures.join("notes.txt"));
    touch(&pictures.join("noext"));
    touch(&pictures.join("x.png.bak"));
    touch(&pictures.join("upper.PNG"));

    let output = case.run_in(&case.root, &["pictures"]);
    assert_eq!(exited(&output), 0);
    let list = case.stdin("swayimg");
    assert_eq!(
        list,
        expected_list(
            &case,
            &[
                "pictures/upper.PNG",
                "pictures/sub/deep/d.GIF",
                "pictures/sub/c.jpeg",
                "pictures/b.jpg",
                "pictures/a.png",
            ]
        )
    );
}

#[test]
fn multiple_directories_are_walked_in_argument_order() {
    let case = case("sx-multiple");
    let first = case.path("first");
    let second = case.path("second");
    touch(&first.join("one.png"));
    sleep(Duration::from_millis(30));
    touch(&second.join("two.png"));
    let output = case.run_in(&case.root, &["first", "second"]);
    assert_eq!(exited(&output), 0);
    assert_eq!(
        case.stdin("swayimg"),
        expected_list(&case, &["second/two.png", "first/one.png"])
    );
}

#[test]
fn symlinks_to_files_and_directories_are_followed() {
    let case = case("sx-symlink");
    let real = case.path("real");
    touch(&real.join("inside.png"));
    let pictures = case.path("pictures");
    std::fs::create_dir_all(&pictures).expect("pictures");
    symlink(real.join("inside.png"), pictures.join("link.png")).expect("file symlink");
    symlink(&real, pictures.join("dirlink")).expect("directory symlink");
    let output = case.run_in(&case.root, &["pictures"]);
    assert_eq!(exited(&output), 0);
    let list = case.stdin("swayimg");
    let lines: Vec<&str> = list.lines().collect();
    assert!(lines.contains(&"pictures/link.png"), "{list}");
    assert!(lines.contains(&"pictures/dirlink/inside.png"), "{list}");
    assert_eq!(lines.len(), 2, "{list}");
}

#[test]
fn a_missing_directory_gets_the_find_diagnostic_and_an_empty_list() {
    let case = case("sx-missing-dir");
    let output = case.run_in(&case.root, &["does-not-exist"]);
    assert_eq!(exited(&output), 0);
    assert_eq!(
        stderr(&output),
        "find: 'does-not-exist': No such file or directory\n"
    );
    assert_eq!(case.stdin("swayimg"), "");
}

#[test]
fn swayimg_status_is_the_script_status() {
    let case = case("sx-status");
    let pictures = case.path("pictures");
    touch(&pictures.join("a.png"));
    let output = case
        .command_in(&case.root)
        .env("FAKE_SWAYIMG_CODE", "7")
        .arg("pictures")
        .output()
        .expect("run sx");
    assert_eq!(exited(&output), 7);
}

#[test]
fn a_local_swayimg_wins_over_path() {
    let case = Case::new("sx-local", BIN);
    case.write_fake("swayimg", PATH_SWAYIMG);
    case.write_executable(&case.home.join(".local/bin/swayimg"), HOME_SWAYIMG);
    let pictures = case.path("pictures");
    touch(&pictures.join("a.png"));
    let output = case.run_in(&case.root, &["pictures"]);
    assert_eq!(exited(&output), 0);
    assert!(case.log_path("swayimg-home").exists());
    assert!(!case.log_path("swayimg-path").exists());
    assert!(!case.log_path("swayimg").exists());
}

#[test]
fn an_empty_directory_still_launches_with_an_empty_list() {
    let case = case("sx-empty");
    let pictures = case.path("empty");
    std::fs::create_dir_all(&pictures).expect("empty directory");
    let output = case.run_in(&case.root, &["empty"]);
    assert_eq!(exited(&output), 0);
    assert_eq!(case.stdin("swayimg"), "");
    assert_eq!(
        case.argv("swayimg"),
        expected_argv(
            "swayimg",
            &[
                "-c",
                &case.path("xdg/config/swayimg/init.lua").to_string_lossy(),
                "-g",
                "-f",
                "/proc/self/fd/0"
            ]
        )
    );
}

#[test]
fn a_directory_that_is_not_readable_or_a_regular_file_is_skipped() {
    let case = case("sx-non-image");
    let pictures = case.path("pictures");
    std::fs::create_dir_all(&pictures).expect("pictures");
    std::fs::write(pictures.join("readme"), b"x").expect("plain file");
    let output = case.run_in(&case.root, &["pictures"]);
    assert_eq!(exited(&output), 0);
    assert_eq!(case.stdin("swayimg"), "");
}
