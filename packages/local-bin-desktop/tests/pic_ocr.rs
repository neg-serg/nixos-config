//! Hermetic tests for the `pic-ocr` port.

mod support;

use std::path::PathBuf;

use local_bin_desktop::helptext::PIC_OCR_HELP;
use support::*;

const BIN: &str = env!("CARGO_BIN_EXE_pic-ocr");
const PROMPT: &str = "Transcribe all text from this image, preserving line breaks. Output only the recognized text, no commentary.";
const DEFAULT_MODEL: &str = "qwen3-vl-abliterated:8b";

fn picture(sandbox: &Sandbox) -> PathBuf {
    let path = sandbox.case.join("i.png");
    sandbox.write(&path, b"imagebytes");
    path
}

fn reply(content: &str) -> String {
    format!(r#"{{"choices":[{{"message":{{"content":"{content}"}}}}]}}"#)
}

#[test]
fn help_prints_the_header_and_exits_0() {
    let sandbox = Sandbox::new("po-help");
    sandbox.install_default_fakes();
    for arguments in [vec!["-h"], vec!["--help"]] {
        let outcome = sandbox.run(BIN, &arguments);
        assert_eq!(outcome.code, 0);
        assert_eq!(outcome.stdout, PIC_OCR_HELP.as_bytes());
        assert_eq!(outcome.stderr, b"");
        assert!(sandbox.log().is_empty());
    }
}

#[test]
fn unknown_option_prints_the_help_on_stderr() {
    let sandbox = Sandbox::new("po-option");
    sandbox.install_default_fakes();
    let outcome = sandbox.run(BIN, &["--bogus"]);
    assert_eq!(outcome.code, 1);
    assert_eq!(outcome.stdout, b"");
    let expected = format!("pic-ocr: unknown option: --bogus\n{PIC_OCR_HELP}");
    assert_eq!(outcome.stderr, expected.into_bytes());
}

#[test]
fn unknown_engine_prints_the_help_on_stderr() {
    let sandbox = Sandbox::new("po-engine");
    sandbox.install_default_fakes();
    let path = picture(&sandbox);
    // The removed classic engines are unknown now, like any other value.
    for engine in ["nope", "tesseract", "classic"] {
        let flag = format!("--engine={engine}");
        let outcome = sandbox.run(BIN, &[&flag, path.to_str().unwrap()]);
        assert_eq!(outcome.code, 1);
        let expected = format!("pic-ocr: unknown engine: {engine}\n{PIC_OCR_HELP}");
        assert_eq!(outcome.stderr, expected.into_bytes());
        assert!(sandbox.clipped().is_empty());
        assert!(sandbox.notifications().is_empty());
    }
}

#[test]
fn default_engine_is_nn() {
    let sandbox = Sandbox::new("po-default");
    sandbox.install_default_fakes();
    let path = picture(&sandbox);
    let outcome = sandbox.run_env(
        BIN,
        &[path.to_str().unwrap()],
        &[
            ("FAKE_MAGICK_OUT", "jpgdata"),
            ("FAKE_CURL_OUT", &reply("default text")),
        ],
    );
    assert_eq!(outcome.code, 0);
    assert_eq!(outcome.stdout, b"");
    assert_eq!(sandbox.last_clip(), b"default text\n");
    assert_eq!(sandbox.calls("magick").len(), 1);
    assert_eq!(sandbox.calls("curl").len(), 1);
    assert!(sandbox.calls("vicinae").is_empty());
}

#[test]
fn neural_result_reaches_the_clipboard_and_the_toast() {
    let sandbox = Sandbox::new("po-nn");
    sandbox.install_default_fakes();
    let path = picture(&sandbox);
    let outcome = sandbox.run_env(
        BIN,
        &["--engine=nn", path.to_str().unwrap()],
        &[
            ("FAKE_MAGICK_OUT", "jpgdata"),
            (
                "FAKE_CURL_OUT",
                r#"{"choices":[{"message":{"content":"line one\nline two"}}]}"#,
            ),
        ],
    );
    assert_eq!(outcome.code, 0);
    assert_eq!(outcome.stdout, b"");
    assert_eq!(sandbox.last_clip(), b"line one\nline two\n");
    assert_eq!(
        sandbox.calls("magick"),
        vec![call(
            "magick",
            &[
                path.to_str().unwrap(),
                "-resize",
                "1600x1600>",
                "-quality",
                "85",
                "jpg:-"
            ]
        )]
    );
    assert_eq!(
        sandbox.notifications(),
        vec![vec![
            b"-a".to_vec(),
            b"pic-ocr".to_vec(),
            format!("OCR ({DEFAULT_MODEL} (local))").into_bytes(),
            b"line one line two".to_vec(),
        ]]
    );
    assert!(sandbox.calls("vicinae").is_empty());
}

#[test]
fn empty_neural_result_is_reported_as_critical() {
    // Empty output, invalid JSON and an empty content field all yield an empty
    // result; there is no tesseract fallback any more.
    for (case, reply) in [
        ("empty", ""),
        ("invalid", "not json"),
        ("missing", r#"{"choices":[{"message":{"content":""}}]}"#),
    ] {
        let sandbox = Sandbox::new(&format!("po-empty-{case}"));
        sandbox.install_default_fakes();
        let path = picture(&sandbox);
        let outcome = sandbox.run_env(
            BIN,
            &[path.to_str().unwrap()],
            &[("FAKE_MAGICK_OUT", "jpgdata"), ("FAKE_CURL_OUT", reply)],
        );
        assert_eq!(outcome.code, 1, "{case}: no recognized text is a failure");
        assert!(sandbox.clipped().is_empty(), "{case}: nothing is copied");
        assert_eq!(
            sandbox.notifications(),
            vec![vec![
                b"-a".to_vec(),
                b"pic-ocr".to_vec(),
                b"-u".to_vec(),
                b"critical".to_vec(),
                b"OCR".to_vec(),
                format!("No text recognized ({DEFAULT_MODEL} (local))").into_bytes(),
            ]],
            "{case}"
        );
        assert!(
            sandbox.calls("magick").len() == 1 && sandbox.calls("curl").len() == 1,
            "{case}: no fallback attempt"
        );
    }
}

#[test]
fn neural_engine_builds_the_exact_ollama_payload() {
    let sandbox = Sandbox::new("po-payload");
    sandbox.install_default_fakes();
    let path = picture(&sandbox);
    let outcome = sandbox.run_env(
        BIN,
        &["--engine=nn", path.to_str().unwrap()],
        &[
            ("FAKE_MAGICK_OUT", "jpgdata"),
            (
                "FAKE_CURL_OUT",
                r#"{"choices":[{"message":{"content":"net text"}}]}"#,
            ),
        ],
    );
    assert_eq!(outcome.code, 0);
    assert_eq!(sandbox.last_clip(), b"net text\n");
    let payload = format!(
        "{{\n  \"model\": \"{DEFAULT_MODEL}\",\n  \"messages\": [\n    {{\n      \"role\": \"user\",\n      \"content\": [\n        {{\n          \"type\": \"image_url\",\n          \"image_url\": {{\n            \"url\": \"data:image/jpeg;base64,anBnZGF0YQ==\"\n          }}\n        }},\n        {{\n          \"type\": \"text\",\n          \"text\": \"{PROMPT}\"\n        }}\n      ]\n    }}\n  ],\n  \"stream\": false\n}}"
    );
    assert_eq!(
        sandbox.calls("curl"),
        vec![call(
            "curl",
            &[
                "-s",
                "--max-time",
                "120",
                "http://localhost:11434/v1/chat/completions",
                "-H",
                "Content-Type: application/json",
                "-d",
                &payload
            ]
        )]
    );
    assert_eq!(
        sandbox.notifications()[0][2],
        format!("OCR ({DEFAULT_MODEL} (local))").into_bytes()
    );
}

#[test]
fn menu_alias_runs_the_neural_engine() {
    // `-m`/`--menu` used to call vicinae; it is now an alias for `--engine=nn`.
    let mut reference = None;
    for flag in ["--engine=nn", "--menu", "-m"] {
        let sandbox = Sandbox::new(&format!("po-menu-{}", flag.trim_start_matches('-')));
        sandbox.install_default_fakes();
        let path = picture(&sandbox);
        let outcome = sandbox.run_env(
            BIN,
            &[flag, path.to_str().unwrap()],
            &[
                ("FAKE_MAGICK_OUT", "jpgdata"),
                ("FAKE_CURL_OUT", &reply("menu text")),
            ],
        );
        assert!(sandbox.calls("vicinae").is_empty(), "{flag}");
        let observed = (
            outcome.code,
            outcome.stdout,
            outcome.stderr,
            sandbox.last_clip(),
            sandbox.notifications(),
        );
        match &reference {
            Some(reference) => assert_eq!(&observed, reference, "{flag} differs"),
            None => {
                assert_eq!(observed.0, 0);
                assert_eq!(observed.3, b"menu text\n");
                reference = Some(observed);
            }
        }
    }
}

#[test]
fn slurp_region_is_captured_and_removed() {
    let sandbox = Sandbox::new("po-slurp");
    sandbox.install_default_fakes();
    let outcome = sandbox.run_env(
        BIN,
        &[],
        &[
            ("FAKE_SLURP_OUT", "10,10 20x20"),
            ("FAKE_MAGICK_OUT", "jpgdata"),
            ("FAKE_CURL_OUT", &reply("region text")),
        ],
    );
    assert_eq!(outcome.code, 0);
    assert_eq!(sandbox.last_clip(), b"region text\n");
    assert_eq!(sandbox.calls("slurp"), vec![call("slurp", &[])]);
    assert_eq!(
        sandbox.calls("mktemp"),
        vec![call("mktemp", &["--suffix=.png"])]
    );
    assert_eq!(
        sandbox.calls("grim"),
        vec![call(
            "grim",
            &["-g", "10,10 20x20", sandbox.mktemp_out.to_str().unwrap()]
        )]
    );
    assert!(
        !sandbox.mktemp_out.exists(),
        "the temporary capture is removed on exit"
    );
}

#[test]
fn cancelled_slurp_exits_1() {
    let sandbox = Sandbox::new("po-slurpcancel");
    sandbox.install_default_fakes();
    let outcome = sandbox.run_env(BIN, &[], &[("FAKE_SLURP_EXIT", "1")]);
    assert_eq!(outcome.code, 1);
    assert_eq!(outcome.stderr, b"pic-ocr: no region selected\n");
    assert!(sandbox.calls("grim").is_empty());
}

#[test]
fn missing_image_exits_1() {
    let sandbox = Sandbox::new("po-missing");
    sandbox.install_default_fakes();
    let path = sandbox.case.join("gone.png");
    let outcome = sandbox.run(BIN, &[path.to_str().unwrap()]);
    assert_eq!(outcome.code, 1);
    assert_eq!(
        outcome.stderr,
        format!("pic-ocr: no such file: {}\n", path.display()).into_bytes()
    );
}

#[test]
fn preview_is_cut_to_140_characters() {
    let sandbox = Sandbox::new("po-preview");
    sandbox.install_default_fakes();
    let path = picture(&sandbox);
    let text = "a".repeat(200);
    let outcome = sandbox.run_env(
        BIN,
        &[path.to_str().unwrap()],
        &[
            ("FAKE_MAGICK_OUT", "jpgdata"),
            ("FAKE_CURL_OUT", &reply(&text)),
        ],
    );
    assert_eq!(outcome.code, 0);
    assert_eq!(sandbox.notifications()[0][3], "a".repeat(140).into_bytes());
}

#[test]
fn preview_is_cut_to_140_bytes_in_the_c_locale() {
    let sandbox = Sandbox::new("po-preview-c");
    sandbox.install_default_fakes();
    let path = picture(&sandbox);
    let text = "аб".repeat(100); // 200 characters, 400 bytes
    let utf8 = sandbox.run_env(
        BIN,
        &[path.to_str().unwrap()],
        &[
            ("FAKE_MAGICK_OUT", "jpgdata"),
            ("FAKE_CURL_OUT", &reply(&text)),
        ],
    );
    assert_eq!(utf8.code, 0);
    assert_eq!(
        sandbox.notifications()[0][3].len(),
        280,
        "140 characters in a UTF-8 locale"
    );

    sandbox.reset();
    sandbox.install_default_fakes();
    let path = picture(&sandbox);
    let c_locale = sandbox.run_env(
        BIN,
        &[path.to_str().unwrap()],
        &[
            ("FAKE_MAGICK_OUT", "jpgdata"),
            ("FAKE_CURL_OUT", &reply(&text)),
            ("LANG", "C"),
            ("LC_ALL", "C"),
        ],
    );
    assert_eq!(c_locale.code, 0);
    assert_eq!(
        sandbox.notifications()[0][3].len(),
        140,
        "140 bytes in the C locale, like coreutils cut"
    );
}

#[test]
fn notify_send_status_is_the_exit_status() {
    let sandbox = Sandbox::new("po-notifystatus");
    sandbox.install_default_fakes();
    let path = picture(&sandbox);
    let outcome = sandbox.run_env(
        BIN,
        &[path.to_str().unwrap()],
        &[
            ("FAKE_MAGICK_OUT", "jpgdata"),
            ("FAKE_CURL_OUT", &reply("text")),
            ("FAKE_NOTIFY_EXIT", "3"),
        ],
    );
    assert_eq!(outcome.code, 3);
}
