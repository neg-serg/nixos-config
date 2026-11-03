//! Hermetic tests for the `sw` port: both API URLs byte-for-byte (values are
//! not encoded, only the query is `@uri`-escaped), the color `#` stripping,
//! the downloaded destination/print contract, key resolution and the error
//! paths. `curl` is a fake that records argv and writes the download payload.

mod support;

use support::{exited, stderr, stdout, Case};

const BIN: &str = env!("CARGO_BIN_EXE_sw");

const CURL: &str = r#"#!/bin/sh
printf 'cmd curl\n' >> "$FAKE_ARGV_LOG"
for argument in "$@"; do printf '  %s\n' "$argument" >> "$FAKE_ARGV_LOG"; done
destination=""
previous=""
for argument in "$@"; do
  if [ "$previous" = "-o" ]; then destination=$argument; fi
  previous=$argument
done
if [ -n "$destination" ]; then
  if [ "${FAKE_CURL_FAIL_DOWNLOAD:-0}" = 1 ]; then exit 7; fi
  printf 'image-bytes' > "$destination"
else
  if [ "${FAKE_CURL_FAIL_API:-0}" = 1 ]; then exit 3; fi
  printf '%s' "${FAKE_JSON:-}"
fi
"#;

fn fixture(label: &str) -> Case {
    let case = Case::new(label, BIN);
    case.write_fake("curl", CURL);
    // The port parses JSON itself; jq only has to exist for the original's
    // dependency gate.
    case.write_fake("jq", "#!/bin/sh\nexit 0\n");
    case
}

fn args_log(case: &Case) -> Vec<String> {
    case.argv_log().lines().map(str::to_string).collect()
}

fn wallhaven_json(path: &str) -> String {
    format!("{{\"data\":[{{\"path\":\"{path}\"}}]}}")
}

#[test]
fn help_prints_the_heredoc() {
    let case = fixture("help");
    let output = case.run(&["--help"]);
    assert_eq!(exited(&output), 0);
    assert_eq!(stderr(&output), "");
    let text = stdout(&output);
    assert!(text.starts_with("sw: unified wallpaper downloader\nUsage: sw [options]\n"));
    assert!(text.contains("  -C, --colors HEX          Dominant colors (e.g. 424153)\n"));
    assert!(text.ends_with("  -f, --featured            Limit to featured photos\n"));
}

#[test]
fn dependencies_are_checked_before_help() {
    let case = fixture("missing-curl");
    case.remove_fake("curl");
    let output = case.run(&["--help"]);
    assert_eq!(exited(&output), 1);
    assert_eq!(stderr(&output), "sw: missing dependency: curl\n");

    let no_jq = fixture("missing-jq");
    no_jq.remove_fake("jq");
    let output = no_jq.run(&["--help"]);
    assert_eq!(exited(&output), 1);
    assert_eq!(stderr(&output), "sw: missing dependency: jq\n");
}

#[test]
fn unknown_option_and_source_are_fatal() {
    let case = fixture("unknown");
    let option = case.run(&["--nope"]);
    assert_eq!(exited(&option), 1);
    assert_eq!(stderr(&option), "sw: unknown option: --nope\n");

    let source = case.run(&["-S", "other"]);
    assert_eq!(exited(&source), 1);
    assert_eq!(stderr(&source), "sw: Unknown source: other\n");
}

#[test]
fn wallhaven_builds_the_api_url_and_downloads() {
    let case = fixture("wallhaven");
    let image = "https://w.wallhaven.cc/full/aa/wallpaper-aa.jpg";
    let output = case.run_env(
        &["-q", "a b", "-C", "#112233#445566"],
        &[("FAKE_JSON", &wallhaven_json(image))],
    );
    assert_eq!(exited(&output), 0);
    assert_eq!(stderr(&output), "");
    let destination = stdout(&output);
    assert_eq!(
        destination,
        format!("{}/pic/wl/wallpaper-aa.jpg\n", case.home.to_string_lossy())
    );
    assert_eq!(
        case.read_at(std::path::Path::new(destination.trim_end())),
        "image-bytes"
    );

    let log = args_log(&case);
    let url = log
        .iter()
        .find(|line| line.contains("wallhaven.cc/api/v1/search"))
        .expect("api url logged")
        .trim()
        .to_string();
    assert!(url.starts_with(
        "https://wallhaven.cc/api/v1/search?q=a%20b&categories=100&purity=100&order=desc&colors=112233445566&ratios=16x9&atleast=3840x2160&sorting=random"
    ), "{url}");
    let page: u32 = url
        .rsplit_once("page=")
        .map(|(_, page)| page.parse().expect("page number"))
        .expect("page parameter");
    assert!((1..=10).contains(&page), "{url}");
    assert!(log.contains(&format!("  {image}")), "{log:?}");
    assert!(log.contains(&"  -o".to_string()), "{log:?}");
}

#[test]
fn wallhaven_omits_the_query_when_none_was_given() {
    let case = fixture("wallhaven-no-query");
    let _ = case.run_env(
        &["--colors", "##ff0000"],
        &[(
            "FAKE_JSON",
            &wallhaven_json("https://w.wallhaven.cc/full/aa/a.jpg"),
        )],
    );
    let url = case
        .argv_log()
        .lines()
        .find(|line| line.contains("wallhaven.cc"))
        .expect("api url")
        .trim()
        .to_string();
    // The original appends every later parameter with `&`, so the empty query
    // leaves a dangling `?&`.
    assert!(
        url.starts_with("https://wallhaven.cc/api/v1/search?&categories=100&purity=100"),
        "{url}"
    );
    assert!(url.contains("&colors=ff0000"), "{url}");
}

#[test]
fn wallhaven_uses_the_environment_key() {
    let case = fixture("wallhaven-key");
    let _ = case.run_env(
        &[],
        &[
            ("WALLHAVEN_API_KEY", "secret"),
            (
                "FAKE_JSON",
                &wallhaven_json("https://w.wallhaven.cc/full/aa/a.jpg"),
            ),
        ],
    );
    assert!(
        case.argv_log().contains("&apikey=secret"),
        "{}",
        case.argv_log()
    );
}

#[test]
fn wallhaven_without_results_dies() {
    let case = fixture("wallhaven-empty");
    let output = case.run_env(&[], &[("FAKE_JSON", "{\"data\":[]}")]);
    assert_eq!(exited(&output), 1);
    assert_eq!(stderr(&output), "sw: No wallpapers found on Wallhaven.\n");
    assert!(!case.argv_log().contains("-o"));
}

#[test]
fn wallhaven_api_failure_is_fatal() {
    let case = fixture("wallhaven-fail");
    let output = case.run_env(&[], &[("FAKE_CURL_FAIL_API", "1")]);
    assert_eq!(exited(&output), 1);
    assert_eq!(stderr(&output), "sw: Wallhaven API failed\n");
}

#[test]
fn a_failed_download_still_prints_the_destination_and_exits_zero() {
    let case = fixture("download-fail");
    let output = case.run_env(
        &[],
        &[
            ("FAKE_CURL_FAIL_DOWNLOAD", "1"),
            (
                "FAKE_JSON",
                &wallhaven_json("https://w.wallhaven.cc/full/aa/a.jpg"),
            ),
        ],
    );
    assert_eq!(exited(&output), 0);
    assert_eq!(
        stdout(&output),
        format!("{}/pic/wl/a.jpg\n", case.home.to_string_lossy())
    );
}

#[test]
fn location_defaults_and_overrides() {
    let case = fixture("location");
    let custom = case.path("custom/dir");
    let custom_text = custom.to_string_lossy().into_owned();
    assert_eq!(
        stdout(&case.run_env(
            &["-l", &custom_text],
            &[(
                "FAKE_JSON",
                &wallhaven_json("https://w.wallhaven.cc/full/aa/a.jpg"),
            )],
        )),
        format!("{custom_text}/a.jpg\n")
    );

    let pictures = fixture("pictures");
    let _ = pictures.run_env(
        &[],
        &[
            ("XDG_PICTURES_DIR", "/pictures"),
            (
                "FAKE_JSON",
                &wallhaven_json("https://w.wallhaven.cc/full/aa/a.jpg"),
            ),
        ],
    );
    assert_eq!(
        stdout(&pictures.run_env(
            &[],
            &[
                ("XDG_PICTURES_DIR", "/pictures"),
                (
                    "FAKE_JSON",
                    &wallhaven_json("https://w.wallhaven.cc/full/aa/a.jpg"),
                ),
            ]
        ),),
        "/pictures/wl/a.jpg\n"
    );
}

#[test]
fn unsplash_key_resolution_via_flag_environment_and_file() {
    let with_flag = fixture("unsplash-flag");
    let _ = with_flag.run_env(
        &["-S", "unsplash", "-k", "FLAG"],
        &[(
            "FAKE_JSON",
            r#"[{"id":"id1","urls":{"raw":"https://images.unsplash.com/p"}}]"#,
        )],
    );
    assert!(with_flag.argv_log().contains("client_id=FLAG"));
    assert_eq!(
        stdout(&with_flag.run_env(
            &["-S", "unsplash", "-k", "FLAG"],
            &[(
                "FAKE_JSON",
                r#"[{"id":"id1","urls":{"raw":"https://images.unsplash.com/p"}}]"#,
            )],
        )),
        format!(
            "{}/pic/wl/unsplash-id1.jpg\n",
            with_flag.home.to_string_lossy()
        )
    );

    let with_env = fixture("unsplash-env");
    let _ = with_env.run_env(
        &["-S", "unsplash"],
        &[
            ("UNSPLASH_ACCESS_KEY", "ENVKEY"),
            (
                "FAKE_JSON",
                r#"{"id":"id2","urls":{"raw":"https://images.unsplash.com/q"}}"#,
            ),
        ],
    );
    assert!(with_env.argv_log().contains("client_id=ENVKEY"));

    let with_file = fixture("unsplash-file");
    case_write_key(&with_file, "FILEKEY\n");
    let _ = with_file.run_env(
        &["-S", "unsplash"],
        &[(
            "FAKE_JSON",
            r#"{"id":"id3","urls":{"raw":"https://images.unsplash.com/r"}}"#,
        )],
    );
    assert!(with_file.argv_log().contains("client_id=FILEKEY"));
}

fn case_write_key(case: &Case, content: &str) {
    case.write(&case.home.join(".gemini/unsplash.key"), content);
}

#[test]
fn unsplash_without_a_key_dies() {
    let case = fixture("unsplash-nokey");
    let output = case.run(&["-S", "unsplash"]);
    assert_eq!(exited(&output), 1);
    assert_eq!(
        stderr(&output),
        "sw: Unsplash requires API Key (use -k, export UNSPLASH_ACCESS_KEY, or save to ~/.gemini/unsplash.key)\n"
    );
    assert_eq!(case.argv_log(), "");
}

#[test]
fn unsplash_handles_both_response_shapes_and_optionals() {
    let case = fixture("unsplash-object");
    let _ = case.run_env(
        &[
            "-S", "unsplash", "-k", "K", "-q", "sea sky", "-f", "-o", "portrait",
        ],
        &[(
            "FAKE_JSON",
            r#"{"id":"obj","urls":{"raw":"https://images.unsplash.com/obj"}}"#,
        )],
    );
    let log = case.argv_log();
    assert!(
        log.contains(
            "https://api.unsplash.com/photos/random?client_id=K&count=1&query=sea%20sky&orientation=portrait&featured=true"
        ),
        "{log}"
    );
    assert!(stdout(&case.run_env(
        &["-S", "unsplash", "-k", "K"],
        &[(
            "FAKE_JSON",
            r#"{"id":"obj","urls":{"raw":"https://images.unsplash.com/obj"}}"#,
        )],
    ))
    .ends_with("/unsplash-obj.jpg\n"));
}

#[test]
fn unsplash_missing_image_is_fatal() {
    let for_null = fixture("unsplash-null");
    let output = for_null.run_env(
        &["-S", "unsplash", "-k", "K"],
        &[("FAKE_JSON", r#"{"id":"x"}"#)],
    );
    assert_eq!(exited(&output), 1);
    assert_eq!(stderr(&output), "sw: No image found on Unsplash.\n");

    let for_empty = fixture("unsplash-empty-array");
    let output = for_empty.run_env(&["-S", "unsplash", "-k", "K"], &[("FAKE_JSON", "[]")]);
    assert_eq!(exited(&output), 1);
    assert_eq!(stderr(&output), "sw: No image found on Unsplash.\n");
}

#[test]
fn unsplash_api_failure_is_fatal() {
    let case = fixture("unsplash-fail");
    let output = case.run_env(
        &["-S", "unsplash", "-k", "K"],
        &[("FAKE_CURL_FAIL_API", "1")],
    );
    assert_eq!(exited(&output), 1);
    assert_eq!(stderr(&output), "sw: Unsplash API failed\n");
}

#[test]
fn a_value_less_option_degrades_to_empty_instead_of_hanging() {
    let case = fixture("missing-value");
    let output = case.run_env(
        &["-q"],
        &[(
            "FAKE_JSON",
            &wallhaven_json("https://w.wallhaven.cc/full/aa/a.jpg"),
        )],
    );
    assert_eq!(exited(&output), 0);
    let url = case
        .argv_log()
        .lines()
        .find(|line| line.contains("wallhaven.cc"))
        .expect("api url")
        .trim()
        .to_string();
    assert!(!url.contains("q="), "{url}");
}

#[test]
fn help_is_reachable_after_other_values() {
    let case = fixture("help-late");
    let output = case.run(&["-q", "x", "--help"]);
    assert_eq!(exited(&output), 0);
    assert!(stdout(&output).starts_with("sw: unified wallpaper downloader"));
    assert_eq!(case.argv_log(), "");
}
