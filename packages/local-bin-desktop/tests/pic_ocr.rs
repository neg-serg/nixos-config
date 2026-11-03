//! Hermetic tests for the `pic-ocr` port.

mod support;

use std::path::PathBuf;

use local_bin_desktop::helptext::PIC_OCR_HELP;
use support::*;

const BIN: &str = env!("CARGO_BIN_EXE_pic-ocr");
const PROMPT: &str = "Transcribe all text from this image, preserving line breaks. Output only the recognized text, no commentary.";

fn picture(sandbox: &Sandbox) -> PathBuf {
    let path = sandbox.case.join("i.png");
    sandbox.write(&path, b"imagebytes");
    path
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
    let outcome = sandbox.run(BIN, &["--engine=nope", path.to_str().unwrap()]);
    assert_eq!(outcome.code, 1);
    let expected = format!("pic-ocr: unknown engine: nope\n{PIC_OCR_HELP}");
    assert_eq!(outcome.stderr, expected.into_bytes());
}

#[test]
fn tesseract_result_reaches_the_clipboard_and_the_toast() {
    let sandbox = Sandbox::new("po-tesseract");
    sandbox.install_default_fakes();
    let path = picture(&sandbox);
    let outcome = sandbox.run_env(
        BIN,
        &[path.to_str().unwrap()],
        &[("FAKE_TESSERACT_OUT", "line one\nline two")],
    );
    assert_eq!(outcome.code, 0);
    assert_eq!(outcome.stdout, b"");
    assert_eq!(sandbox.last_clip(), b"line one\nline two\n");
    assert_eq!(
        sandbox.calls("tesseract"),
        vec![call(
            "tesseract",
            &[
                path.to_str().unwrap(),
                "stdout",
                "-l",
                "eng+rus",
                "--psm",
                "3"
            ]
        )]
    );
    assert_eq!(
        sandbox.notifications(),
        vec![vec![
            b"-a".to_vec(),
            b"pic-ocr".to_vec(),
            b"OCR (tesseract)".to_vec(),
            b"line one line two".to_vec(),
        ]]
    );
}

#[test]
fn empty_result_is_reported_as_critical() {
    let sandbox = Sandbox::new("po-empty");
    sandbox.install_default_fakes();
    let path = picture(&sandbox);
    let outcome = sandbox.run_env(
        BIN,
        &[path.to_str().unwrap()],
        &[("FAKE_TESSERACT_OUT", "")],
    );
    assert_eq!(outcome.code, 1);
    assert!(sandbox.clipped().is_empty());
    assert_eq!(
        sandbox.notifications(),
        vec![vec![
            b"-a".to_vec(),
            b"pic-ocr".to_vec(),
            b"-u".to_vec(),
            b"critical".to_vec(),
            b"OCR".to_vec(),
            b"No text recognized (tesseract)".to_vec(),
        ]]
    );
}

#[test]
fn neural_engine_builds_the_exact_ollama_payload() {
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
                r#"{"choices":[{"message":{"content":"net text"}}]}"#,
            ),
        ],
    );
    assert_eq!(outcome.code, 0);
    assert_eq!(sandbox.last_clip(), b"net text\n");
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
    let payload = format!(
        "{{\n  \"model\": \"qwen3-vl:8b\",\n  \"messages\": [\n    {{\n      \"role\": \"user\",\n      \"content\": [\n        {{\n          \"type\": \"image_url\",\n          \"image_url\": {{\n            \"url\": \"data:image/jpeg;base64,anBnZGF0YQ==\"\n          }}\n        }},\n        {{\n          \"type\": \"text\",\n          \"text\": \"{PROMPT}\"\n        }}\n      ]\n    }}\n  ],\n  \"stream\": false\n}}"
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
    assert!(str_of(&sandbox.notifications()[0][2]).contains("qwen3-vl:8b (local)"));
}

#[test]
fn neural_failure_falls_back_to_tesseract() {
    let sandbox = Sandbox::new("po-fallback");
    sandbox.install_default_fakes();
    let path = picture(&sandbox);
    let outcome = sandbox.run_env(
        BIN,
        &["-n", path.to_str().unwrap()],
        &[
            ("FAKE_MAGICK_OUT", ""),
            ("FAKE_TESSERACT_OUT", "fallback text"),
        ],
    );
    assert_eq!(outcome.code, 0);
    assert_eq!(sandbox.last_clip(), b"fallback text\n");
    assert_eq!(
        sandbox.notifications()[0][2],
        b"OCR (tesseract (nn fallback))".to_vec()
    );
}

#[test]
fn menu_pick_selects_the_engine() {
    let sandbox = Sandbox::new("po-menu");
    sandbox.install_default_fakes();
    let path = picture(&sandbox);
    let outcome = sandbox.run_env(
        BIN,
        &["--menu", path.to_str().unwrap()],
        &[
            ("FAKE_VICINAE_OUT", "Tesseract (classic)"),
            ("FAKE_TESSERACT_OUT", "menu text"),
        ],
    );
    assert_eq!(outcome.code, 0);
    assert_eq!(sandbox.last_clip(), b"menu text\n");
    assert_eq!(
        sandbox.calls("vicinae"),
        vec![call("vicinae", &["dmenu", "-p", "⟬OCR⟭ ❯>"])]
    );
    let listing = str_of(&sandbox.read(&sandbox.vicinae_in));
    assert_eq!(listing, "Tesseract (classic)\nQwen3-VL 8B (neural)\n");
}

#[test]
fn cancelled_menu_exits_0() {
    let sandbox = Sandbox::new("po-menucancel");
    sandbox.install_default_fakes();
    let path = picture(&sandbox);
    let outcome = sandbox.run_env(
        BIN,
        &["--menu", path.to_str().unwrap()],
        &[("FAKE_VICINAE_OUT", "")],
    );
    assert_eq!(outcome.code, 0);
    assert!(sandbox.clipped().is_empty());
    assert!(sandbox.calls("tesseract").is_empty());
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
            ("FAKE_TESSERACT_OUT", "region text"),
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
        &[("FAKE_TESSERACT_OUT", &text)],
    );
    assert_eq!(outcome.code, 0);
    assert_eq!(sandbox.notifications()[0][3], "a".repeat(140).into_bytes());
}

#[test]
fn preview_follows_the_effective_character_locale() {
    let sandbox = Sandbox::new("po-preview-c");
    sandbox.install_default_fakes();
    let path = picture(&sandbox);
    let text = "аб".repeat(100); // 200 characters, 400 bytes
    let utf8 = sandbox.run_env(
        BIN,
        &[path.to_str().unwrap()],
        &[("FAKE_TESSERACT_OUT", &text)],
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
            ("FAKE_TESSERACT_OUT", &text),
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
        &[("FAKE_TESSERACT_OUT", "text"), ("FAKE_NOTIFY_EXIT", "3")],
    );
    assert_eq!(outcome.code, 3);
}
