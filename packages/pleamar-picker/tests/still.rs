//! End-to-end tests for `pleamar-wallpaper-still`.
//!
//! Every case is the real binary in its own temporary tree: fake ffmpeg on a
//! private PATH that logs its argv, HOME/XDG_CACHE_HOME/TMPDIR pointing at the
//! case. Nothing reads the host cache or a real video.

mod support;

use std::fs;
use std::os::unix::ffi::OsStrExt;
use std::path::PathBuf;

use pleamar_picker::md5;
use support::PipeThrough as _;
use support::{stderr, stdout, Case, FFMPEG};

fn frame_for(case: &Case, video: &std::path::Path) -> PathBuf {
    let key = md5::hex16(video.as_os_str().as_bytes());
    case.frame_dir().join(format!("{key}.jpg"))
}

fn fake_ffmpeg(log: &str, script: &str) -> String {
    format!(
        r#"#!/bin/sh
printf 'ffmpeg' >> "{log}"
for arg; do printf ' [%s]' "$arg" >> "{log}"; done
printf '\n' >> "{log}"
{script}
"#
    )
}

#[test]
fn image_prints_its_own_path() {
    let case = Case::still("image");
    let image = case.media_file("pic.png", b"PNGDATA");
    let output = case.run(&[image.to_str().expect("UTF-8 fixture path")]);
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(
        stdout(&output),
        format!("{}\n", image.to_str().expect("UTF-8 fixture path"))
    );
    assert_eq!(stderr(&output), "");
    assert_eq!(case.log(), "");
}

#[test]
fn gif_is_its_own_still_and_a_relative_path_stays_relative() {
    let case = Case::still("gif-relative");
    case.media_file("anim.gif", b"GIF89a");
    let output = case.run(&["media/anim.gif"]);
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(stdout(&output), "media/anim.gif\n");
}

#[test]
fn missing_argument_and_missing_file_exit_1_silently() {
    let case = Case::still("missing");

    let without = case.run(&[]);
    assert_eq!(without.status.code(), Some(1));
    assert_eq!(stdout(&without), "");
    assert_eq!(stderr(&without), "");

    let absent = case.run(&["media/nope.png"]);
    assert_eq!(absent.status.code(), Some(1));
    assert_eq!(stdout(&absent), "");
    assert_eq!(stderr(&absent), "");

    let directory = case.media_file("not-a-file", b"x");
    let directory = directory.parent().expect("media dir").to_path_buf();
    let as_dir = case.run(&[directory.to_str().expect("UTF-8 path")]);
    assert_eq!(as_dir.status.code(), Some(1));
    assert_eq!(stdout(&as_dir), "");
}

#[test]
fn video_frame_is_grabbed_with_the_shell_argv_and_cached() {
    let case = Case::still("video-fresh");
    case.fake("ffmpeg", FFMPEG);
    let video = case.media_file("clip.mp4", b"VIDEO");
    let output = case.run(&[video.to_str().expect("UTF-8 path")]);
    let frame = frame_for(&case, &video);

    assert_eq!(output.status.code(), Some(0));
    assert_eq!(stdout(&output), format!("{}\n", frame.display()));
    assert_eq!(stderr(&output), "");
    assert_eq!(fs::read(&frame).expect("cached frame"), b"JPEG");

    let log = case.log();
    let lines: Vec<&str> = log.lines().collect();
    assert_eq!(lines.len(), 1, "one successful ffmpeg call: {log}");
    let prefix = format!(
        "ffmpeg [-nostdin] [-loglevel] [error] [-y] [-ss] [1] [-i] [{}] [-frames:v] [1] [-pix_fmt] [yuvj420p] [-q:v] [2] [",
        video.display()
    );
    assert!(lines[0].starts_with(&prefix), "{}", lines[0]);
    let temporary = lines[0]
        .rsplit('[')
        .next()
        .expect("temporary path")
        .trim_end_matches(']');
    assert!(temporary.starts_with(&format!("{}.", frame.display())));
    assert!(temporary.ends_with(".jpg"));
    assert!(
        !std::path::Path::new(temporary).exists(),
        "temp file is moved"
    );

    // A second run reads the cache and runs no ffmpeg.
    case.reset_log();
    let cached = case.run(&[video.to_str().expect("UTF-8 path")]);
    assert_eq!(cached.status.code(), Some(0));
    assert_eq!(stdout(&cached), format!("{}\n", frame.display()));
    assert_eq!(case.log(), "");
}

#[test]
fn uppercase_video_extension_takes_the_frame_path() {
    let case = Case::still("video-uppercase");
    case.fake("ffmpeg", FFMPEG);
    let video = case.media_file("CLIP.MoV", b"VIDEO");
    let output = case.run(&[video.to_str().expect("UTF-8 path")]);
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(
        stdout(&output),
        format!("{}\n", frame_for(&case, &video).display())
    );
}

#[test]
fn cached_frame_newer_than_the_video_is_reused() {
    let case = Case::still("video-cached-newer");
    case.fake("ffmpeg", FFMPEG);
    let video = case.media_file("clip.mkv", b"VIDEO");
    let frame = frame_for(&case, &video);
    case.write(&frame, b"OLD");
    case.set_mtime(&video, 1_700_000_000);
    case.set_mtime(&frame, 1_700_000_010);

    let output = case.run(&[video.to_str().expect("UTF-8 path")]);
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(stdout(&output), format!("{}\n", frame.display()));
    assert_eq!(case.log(), "");
    assert_eq!(fs::read(&frame).expect("cached frame"), b"OLD");
}

#[test]
fn newer_video_regrabs_the_frame() {
    let case = Case::still("video-newer");
    case.fake("ffmpeg", FFMPEG);
    let video = case.media_file("clip.mkv", b"VIDEO");
    let frame = frame_for(&case, &video);
    case.write(&frame, b"OLD");
    case.set_mtime(&frame, 1_700_000_000);
    case.set_mtime(&video, 1_700_000_010);

    let output = case.run(&[video.to_str().expect("UTF-8 path")]);
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(stdout(&output), format!("{}\n", frame.display()));
    assert_eq!(fs::read(&frame).expect("cached frame"), b"JPEG");
    assert_eq!(case.log().lines().count(), 1);
}

#[test]
fn empty_cached_frame_is_regrabbed_even_when_newer() {
    let case = Case::still("video-empty-cache");
    case.fake("ffmpeg", FFMPEG);
    let video = case.media_file("clip.webm", b"VIDEO");
    let frame = frame_for(&case, &video);
    case.write(&frame, b"");
    case.set_mtime(&video, 1_700_000_000);
    case.set_mtime(&frame, 1_700_000_010);

    let output = case.run(&[video.to_str().expect("UTF-8 path")]);
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(fs::read(&frame).expect("cached frame"), b"JPEG");
    assert_eq!(case.log().lines().count(), 1);
}

#[test]
fn a_failed_first_attempt_falls_back_to_the_first_frame() {
    let case = Case::still("video-second-attempt");
    let script = fake_ffmpeg(
        case.log.to_str().expect("UTF-8 path"),
        r#"case " $* " in
  *" -ss 1 "*)
    exit 1
    ;;
esac
for last; do :; done
printf 'SECOND' > "$last"
exit 0"#,
    );
    case.fake("ffmpeg", &script);

    let video = case.media_file("clip.mp4", b"VIDEO");
    let output = case.run(&[video.to_str().expect("UTF-8 path")]);
    let frame = frame_for(&case, &video);
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(fs::read(&frame).expect("cached frame"), b"SECOND");
    let log = case.log();
    assert_eq!(log.lines().count(), 2);
    assert!(log.lines().next().expect("first").contains("[-ss] [1]"));
    assert!(log.lines().nth(1).expect("second").contains("[-ss] [0]"));
}

#[test]
fn a_success_with_an_empty_file_falls_back_to_the_first_frame() {
    let case = Case::still("video-empty-first");
    let script = fake_ffmpeg(
        case.log.to_str().expect("UTF-8 path"),
        r#"for last; do :; done
case " $* " in
  *" -ss 1 "*)
    : > "$last"
    ;;
  *)
    printf 'SECOND' > "$last"
    ;;
esac
exit 0"#,
    );
    case.fake("ffmpeg", &script);

    let video = case.media_file("clip.mp4", b"VIDEO");
    let output = case.run(&[video.to_str().expect("UTF-8 path")]);
    let frame = frame_for(&case, &video);
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(fs::read(&frame).expect("cached frame"), b"SECOND");
    assert_eq!(case.log().lines().count(), 2);
}

#[test]
fn both_attempts_failing_leave_no_frame_and_exit_1() {
    let case = Case::still("video-both-fail");
    let script = fake_ffmpeg(case.log.to_str().expect("UTF-8 path"), "exit 1");
    case.fake("ffmpeg", &script);

    let video = case.media_file("clip.mp4", b"VIDEO");
    let output = case.run(&[video.to_str().expect("UTF-8 path")]);
    assert_eq!(output.status.code(), Some(1));
    assert_eq!(stdout(&output), "");
    assert_eq!(stderr(&output), "");
    let frame = frame_for(&case, &video);
    assert!(!frame.exists());
    assert_eq!(case.log().lines().count(), 2);
    let leftovers: Vec<_> = fs::read_dir(case.frame_dir())
        .expect("frame directory exists")
        .collect();
    assert!(leftovers.is_empty());
}

#[test]
fn a_failed_attempt_that_left_bytes_is_still_cached() {
    // The shell's post-loop `[ -s "$tmp" ]` only looks at the file, not at
    // ffmpeg's status: a non-empty partial frame from a failed attempt wins.
    let case = Case::still("video-partial");
    let script = fake_ffmpeg(
        case.log.to_str().expect("UTF-8 path"),
        r#"for last; do :; done
printf 'PARTIAL' > "$last"
exit 1"#,
    );
    case.fake("ffmpeg", &script);

    let video = case.media_file("clip.mp4", b"VIDEO");
    let output = case.run(&[video.to_str().expect("UTF-8 path")]);
    let frame = frame_for(&case, &video);
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(stdout(&output), format!("{}\n", frame.display()));
    assert_eq!(fs::read(&frame).expect("cached frame"), b"PARTIAL");
    assert_eq!(case.log().lines().count(), 2);
}

#[test]
fn missing_ffmpeg_exits_1_silently() {
    let case = Case::still("video-no-ffmpeg");
    let video = case.media_file("clip.mp4", b"VIDEO");
    let output = case.run_isolated(&[video.to_str().expect("UTF-8 path")]);
    assert_eq!(output.status.code(), Some(1));
    assert_eq!(stdout(&output), "");
    assert!(!frame_for(&case, &video).exists());
}

#[test]
fn xdg_cache_home_is_honoured_and_home_default_is_used_without_it() {
    let case = Case::still("cache-env");
    case.fake("ffmpeg", FFMPEG);
    let video = case.media_file("clip.mp4", b"VIDEO");

    let with_xdg = case.run(&[video.to_str().expect("UTF-8 path")]);
    assert_eq!(with_xdg.status.code(), Some(0));
    assert!(frame_for(&case, &video).exists());

    let home_cache = case
        .home
        .join(".cache")
        .join("pleamar")
        .join("wallpaper-frames");
    let without_xdg = case
        .command()
        .env_remove("XDG_CACHE_HOME")
        .args([video.to_str().expect("UTF-8 path")])
        .pipe_through(support::output);
    assert_eq!(without_xdg.status.code(), Some(0));
    let key = md5::hex16(video.as_os_str().as_bytes());
    let home_frame = home_cache.join(format!("{key}.jpg"));
    assert_eq!(stdout(&without_xdg), format!("{}\n", home_frame.display()));
    assert!(home_frame.exists());
}

#[test]
fn extra_arguments_are_ignored() {
    let case = Case::still("extra-args");
    let image = case.media_file("pic.jpg", b"JPEG");
    let output = case.run(&[
        image.to_str().expect("UTF-8 path"),
        "ignored",
        "also-ignored",
    ]);
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(stdout(&output), format!("{}\n", image.display()));
    assert_eq!(case.log(), "");
}
