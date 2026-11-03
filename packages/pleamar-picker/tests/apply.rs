//! End-to-end tests for `pleamar-wallpaper-apply`.
//!
//! The binary runs from `helpers/` with a real `pleamar-wallpaper-still`
//! beside it, so the sibling lookup is exercised exactly as in `~/.local/bin`.
//! The external tools are fakes with argv logging; matugen is present only in
//! the tests that install it, which keeps the host's matugen out.

mod support;

use std::fs;
use std::path::Path;

use pleamar_picker::quote;
use support::PipeThrough as _;
use support::{link_target, mode, read, stderr, stdout, Case, MATUGEN, NICE, SETSID};

fn media(case: &Case, name: &str) -> String {
    case.media_file(name, b"PNGDATA")
        .to_str()
        .expect("UTF-8 fixture path")
        .to_string()
}

fn quoted(bytes: &[u8]) -> String {
    String::from_utf8(quote::quote(bytes)).expect("ASCII path quotes as UTF-8")
}

#[test]
fn no_file_is_usage_and_a_missing_file_is_an_error() {
    let case = Case::apply("bad-args");

    let without = case.run(&[]);
    assert_eq!(without.status.code(), Some(2));
    assert_eq!(stdout(&without), "");
    assert_eq!(stderr(&without), "wallpaper-apply: no FILE\n");

    let empty = case.run(&[""]);
    assert_eq!(empty.status.code(), Some(2));
    assert_eq!(stderr(&empty), "wallpaper-apply: no FILE\n");

    let absent = case.run(&["media/nope.png"]);
    assert_eq!(absent.status.code(), Some(1));
    assert_eq!(stdout(&absent), "");
    assert_eq!(
        stderr(&absent),
        "wallpaper-apply: 'media/nope.png' not found\n"
    );

    let directory = case.dir.join("media");
    let as_directory = case.run(&[directory.to_str().expect("UTF-8 path")]);
    assert_eq!(as_directory.status.code(), Some(1));
    assert_eq!(
        stderr(&as_directory),
        format!("wallpaper-apply: '{}' not found\n", directory.display())
    );
    assert_eq!(case.log(), "");
}

#[test]
fn an_image_without_a_still_helper_caches_itself() {
    let case = Case::apply("image-no-helper");
    case.remove_still_helper();
    let image = media(&case, "pic.png");

    let output = case.run(&[&image]);
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(stdout(&output), "");
    assert_eq!(stderr(&output), "");

    let source_link = case.cache.join("current_wallpaper_source");
    let current_link = case.cache.join("current_wallpaper");
    assert!(fs::symlink_metadata(&source_link)
        .expect("source symlink")
        .file_type()
        .is_symlink());
    assert_eq!(link_target(&source_link), image);
    assert_eq!(link_target(&current_link), image);

    assert_eq!(read(&case.cache_path()), format!("{image}\n"));
    assert_eq!(
        read(&case.home.join(".local/state/wl/last-good")),
        format!("{image}\n")
    );
    // The legacy `quickshell-wallpaper-path` is not written any more: the shell it
    // was kept for is gone.
    assert!(!case.cache.join("quickshell-wallpaper-path").exists());

    // The text caches are ordinary files with the process umask's mode,
    // never executable; the reference file is created by this same test.
    let reference = case.reference_file();
    assert_eq!(mode(&case.cache_path()), mode(&reference));
    assert_eq!(
        mode(&case.home.join(".local/state/wl/last-good")),
        mode(&reference)
    );
    assert_eq!(mode(&case.cache_path()) & 0o111, 0);
    assert_eq!(case.log(), "");
}

#[test]
fn the_still_helper_beside_the_binary_supplies_the_still() {
    let case = Case::apply("helper-still");
    case.remove_still_helper();
    case.fake_still("#!/bin/sh\nprintf '%s-frame\\n' \"$1\"\n");
    let image = media(&case, "pic.png");

    let output = case.run(&[&image]);
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(stdout(&output), "");
    let still = format!("{image}-frame");
    assert_eq!(read(&case.cache_path()), format!("{still}\n"));
    assert_eq!(link_target(&case.cache.join("current_wallpaper")), still);
    assert_eq!(
        link_target(&case.cache.join("current_wallpaper_source")),
        image
    );
}

#[test]
fn the_legacy_wallpaper_still_name_is_tried_second() {
    let case = Case::apply("legacy-still");
    case.remove_still_helper();
    // The helper has to sit beside the apply binary, not on PATH.
    case.fake_helper("wallpaper-still", "#!/bin/sh\nprintf 'LEGACY\\n'\nexit 0\n");

    let image = media(&case, "pic.png");
    let output = case.run(&[&image]);
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(read(&case.cache_path()), "LEGACY\n");
    assert_eq!(link_target(&case.cache.join("current_wallpaper")), "LEGACY");
}

#[test]
fn a_failing_still_helper_stops_before_the_caches() {
    let case = Case::apply("failing-still");
    case.fake_still("#!/bin/sh\necho 'helper broke' >&2\nexit 3\n");
    let image = media(&case, "pic.png");

    let output = case.run(&[&image]);
    assert_eq!(output.status.code(), Some(1));
    assert_eq!(stdout(&output), "");
    assert_eq!(
        stderr(&output),
        format!("helper broke\nwallpaper-apply: no still image for '{image}'\n")
    );
    assert!(!case.cache.join("pleamar").exists());
    assert!(!case.home.join(".local").exists());
}

#[test]
fn an_empty_still_output_falls_back_to_the_file() {
    let case = Case::apply("empty-still");
    case.fake_still("#!/bin/sh\nexit 0\n");
    let image = media(&case, "pic.png");

    let output = case.run(&[&image]);
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(read(&case.cache_path()), format!("{image}\n"));
    assert_eq!(link_target(&case.cache.join("current_wallpaper")), image);
}

#[test]
fn a_video_is_cached_through_the_still_helper_frame() {
    let case = Case::apply("video");
    case.fake("ffmpeg", support::FFMPEG);
    let video = media(&case, "clip.mp4");

    let output = case.run(&[&video]);
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(stdout(&output), "");
    assert_eq!(stderr(&output), "");

    let key = pleamar_picker::md5::hex16(video.as_bytes());
    let frame = case.frame_dir().join(format!("{key}.jpg"));
    assert_eq!(read(&case.cache_path()), format!("{}\n", frame.display()));
    assert_eq!(
        link_target(&case.cache.join("current_wallpaper")),
        frame.display().to_string()
    );
    assert_eq!(
        link_target(&case.cache.join("current_wallpaper_source")),
        video
    );
    assert_eq!(fs::read(&frame).expect("frame"), b"JPEG");
    assert_eq!(case.log().lines().count(), 1);
}

#[test]
fn existing_cache_entries_are_replaced() {
    let case = Case::apply("replace");
    case.remove_still_helper();
    let image = media(&case, "pic.png");
    let source_link = case.cache.join("current_wallpaper_source");
    let current_link = case.cache.join("current_wallpaper");
    case.write(&source_link, b"old regular file");
    case.new_symlink(Path::new("/tmp/wrong-still"), &current_link);
    case.write(&case.cache_path(), b"/tmp/old\n");

    let output = case.run(&[&image]);
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(link_target(&source_link), image);
    assert_eq!(link_target(&current_link), image);
    assert_eq!(read(&case.cache_path()), format!("{image}\n"));
}

#[test]
fn a_template_with_braces_gets_the_quoted_path() {
    let case = Case::apply("command-braces");
    case.fake("setsid", SETSID);
    let image = case
        .media_file("a b'c.png", b"PNG")
        .to_str()
        .expect("UTF-8 path")
        .to_string();

    let output = case.run(&[&image, "wl img {} --scale 1"]);
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(stderr(&output), "");
    let expected = format!(
        "setsid [-f] [sh] [-c] [wl img {} --scale 1]\n",
        quoted(image.as_bytes())
    );
    assert_eq!(case.log(), expected);
}

#[test]
fn a_template_without_braces_appends_the_path() {
    let case = Case::apply("command-append");
    case.fake("setsid", SETSID);
    let image = media(&case, "pic.png");

    let output = case.run(&[&image, "swaybg -i"]);
    assert_eq!(output.status.code(), Some(0));
    let expected = format!(
        "setsid [-f] [sh] [-c] [swaybg -i {}]\n",
        quoted(image.as_bytes())
    );
    assert_eq!(case.log(), expected);
}

#[test]
fn every_placeholder_is_replaced() {
    let case = Case::apply("command-multiple");
    case.fake("setsid", SETSID);
    let image = media(&case, "pic.png");

    let output = case.run(&[&image, "tool {} --also {}"]);
    assert_eq!(output.status.code(), Some(0));
    let expected = format!(
        "setsid [-f] [sh] [-c] [tool {} --also {}]\n",
        quoted(image.as_bytes()),
        quoted(image.as_bytes())
    );
    assert_eq!(case.log(), expected);
}

#[test]
fn a_failing_wallpaper_command_is_reported_and_the_exit_stays_clean() {
    let case = Case::apply("command-fails");
    case.fake("setsid", SETSID);
    let image = media(&case, "pic.png");

    let output = case.run_with(&[("FAKE_SETSID_CODE", "3")], &[&image, "wl img {}"]);
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(
        stderr(&output),
        "wallpaper-apply: the wallpaper command failed: wl img {}\n"
    );
    assert_eq!(read(&case.cache_path()), format!("{image}\n"));
}

#[test]
fn matugen_runs_through_nice_on_the_still_and_its_status_is_the_exit() {
    let case = Case::apply("matugen");
    case.remove_still_helper();
    case.fake("matugen", MATUGEN);
    case.fake("nice", NICE);
    let image = media(&case, "pic.png");

    let output = case.run_with(&[("FAKE_NICE_CODE", "7")], &[&image]);
    assert_eq!(output.status.code(), Some(7));
    assert_eq!(stderr(&output), "");
    assert_eq!(
        case.log(),
        format!("nice [-n] [19] [matugen] [image] [{image}] [--source-color-index] [0]\n")
    );
    assert_eq!(read(&case.cache_path()), format!("{image}\n"));
}

#[test]
fn matugen_runs_after_the_wallpaper_command() {
    let case = Case::apply("matugen-order");
    case.fake("setsid", SETSID);
    case.fake("matugen", MATUGEN);
    case.fake("nice", NICE);
    let image = media(&case, "pic.png");

    let output = case.run(&[&image, "wl img {}"]);
    assert_eq!(output.status.code(), Some(0));
    let log = case.log();
    let lines: Vec<&str> = log.lines().collect();
    assert_eq!(lines.len(), 2, "{log}");
    assert!(lines[0].starts_with("setsid "));
    assert!(lines[1].starts_with("nice [-n] [19] [matugen] "));
}

#[test]
fn matugen_absent_is_a_clean_zero_without_nice() {
    let case = Case::apply("matugen-absent");
    case.remove_still_helper();
    let image = media(&case, "pic.png");

    let output = case.run(&[&image]);
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(stderr(&output), "");
    assert_eq!(case.log(), "");
}

#[test]
fn the_home_cache_default_is_used_without_xdg_cache_home() {
    let case = Case::apply("home-cache");
    case.remove_still_helper();
    let image = media(&case, "pic.png");

    let output = case
        .command()
        .env_remove("XDG_CACHE_HOME")
        .args([&image])
        .pipe_through(support::output);
    assert_eq!(output.status.code(), Some(0));
    let home_cache = case.home.join(".cache");
    assert_eq!(
        read(&home_cache.join("pleamar/wallpaper-path")),
        format!("{image}\n")
    );
    assert_eq!(link_target(&home_cache.join("current_wallpaper")), image);
    assert!(!case.cache.join("pleamar").exists());
}

#[test]
fn a_missing_home_is_an_error_before_any_cache_write() {
    let case = Case::apply("no-home");
    case.remove_still_helper();
    let image = media(&case, "pic.png");

    let output = case
        .command()
        .env_remove("HOME")
        .args([&image])
        .output()
        .expect("run without HOME");
    assert_eq!(output.status.code(), Some(1));
    assert_eq!(stdout(&output), "");
    assert_eq!(stderr(&output), "wallpaper-apply: HOME is not set\n");
    assert!(!case.cache.join("pleamar").exists());
}
