//! End-to-end tests of the worker binary.
//!
//! Each test runs the worker against a temporary fake `khal` on PATH and a
//! local HTTP mock for both APIs, with private HOME/TMPDIR/XDG dirs. Nothing
//! here can reach the network or the user's real cache.

mod support;

use std::fs;
use std::time::{Duration, Instant};

use serde_json::Value;
use support::*;

fn once_args(cache: &std::path::Path, base: &str, extra: &[&str]) -> Vec<String> {
    let mut args = arguments(cache, base);
    args.push("--once".to_string());
    args.extend(extra.iter().map(|value| value.to_string()));
    args
}

fn sample_of(output: &std::process::Output) -> Value {
    let lines = lines(output);
    assert_eq!(lines.len(), 2, "handshake + one sample: {lines:?}");
    assert_eq!(lines[0], HANDSHAKE);
    parse_line(&lines[1])
}

#[test]
fn once_prints_the_handshake_and_a_fresh_payload() {
    let sandbox = Sandbox::new("once");
    let mock = Mock::start(provider_response);
    let args = once_args(
        &sandbox.cache,
        mock.base(),
        &["--month", "2026-11", "--country", "RU"],
    );
    let output = sandbox.run(&args, &[]);
    assert_eq!(output.status.code(), Some(0), "{}", stderr(&output));
    assert!(stderr(&output).is_empty(), "{}", stderr(&output));
    let lines = lines(&output);
    assert_eq!(lines[0], HANDSHAKE);
    let sample = parse_line(&lines[1]);
    assert_eq!(sample["ok"], true);
    assert_eq!(sample["worker"], "calendar");
    assert_eq!(sample["topic"], "calendar");
    assert_recent_ms(&sample, "t", 10_000);

    let data = &sample["data"];
    assert_eq!(data["month"], "2026-11");
    assert_eq!(data["first"], "2026-11-01");
    assert_eq!(data["last"], "2026-11-30");
    assert_eq!(data["cached"], false);
    assert_eq!(data["age_s"], 0);
    let fetched_at = data["fetched_at"].as_i64().expect("fetched_at");
    assert!((fetched_at - now_secs()).abs() <= 5);
    assert_eq!(data["holidays_error"], Value::Null);
    assert_eq!(data["workdays_error"], Value::Null);
    assert_eq!(data["pills"], serde_json::json!([]));
    assert_eq!(data["streak"], 0);

    // khal's header and non-event line are skipped, the EU date and the ANSI
    // colour are normalised, and the pipes inside a title stay there.
    assert_eq!(
        data["events"],
        serde_json::json!([
            {"date": "2026-11-05", "time": "09:00", "title": "Standup", "calendar": "Work"},
            {"date": "2026-11-06", "time": "18:30", "title": "Concert|a|b", "calendar": "Personal"},
            {"date": "2026-11-05", "time": "10:00", "title": "Coloured", "calendar": "Cal"},
            {"date": "2026-11-07", "time": "11:00", "title": "Only three", "calendar": "pipes"}
        ])
    );
    assert_eq!(
        data["holidays"],
        serde_json::json!([
            {"date": "2026-11-04", "name": "Den narodnogo edinstva", "name_en": "Unity Day"}
        ])
    );
    assert_eq!(
        data["workdays"],
        serde_json::json!([{"date": "2026-11-05", "code": 1}])
    );

    // The jq object order: month … age_s, then pills and streak.
    assert!(lines[1].contains(concat!(
        "\"data\":{\"month\":\"2026-11\",\"first\":\"2026-11-01\",\"last\":\"2026-11-30\",",
        "\"events\":["
    )));
    assert!(lines[1].contains(concat!(
        "\"holidays_error\":null,\"workdays\":[{\"date\":\"2026-11-05\",\"code\":1}],",
        "\"workdays_error\":null,\"fetched_at\":"
    )));
    assert!(lines[1].ends_with("\"pills\":[],\"streak\":0}}"));

    // khal: one call, ISO range, exact argv.
    assert_eq!(
        sandbox.khal_calls(),
        vec![
            "list --format {start-date}|{start-time}|{title}|{calendar} 2026-11-01 2026-11-30"
                .to_string()
        ]
    );

    // Both APIs: the exact URLs curl requested, the shell's User-Agent and
    // curl's `Accept: */*`.
    let requests = mock.requests();
    assert_eq!(
        mock.paths(),
        vec![
            "/v3/PublicHolidays/2026/RU".to_string(),
            "/getdata?year=2026&month=11&cc=RU".to_string()
        ]
    );
    for request in &requests {
        assert_eq!(request.method, "GET");
        assert_eq!(request.header("user-agent"), Some("pleamar-calendar/1.0"));
        assert_eq!(request.header("accept"), Some("*/*"));
    }

    // The cache documents and their bytes.
    let calendar_path = cache_file(&sandbox.cache, "2026-11");
    let calendar_text = fs::read_to_string(&calendar_path).expect("calendar cache");
    assert!(calendar_text.ends_with('\n'));
    let document = parse_line(calendar_text.trim_end());
    assert_eq!(document["month"], "2026-11");
    assert_eq!(document["cached"], true);
    assert!(document.get("age_s").is_none(), "cache has no age_s");
    assert_eq!(document["fetched_at"], data["fetched_at"]);
    assert_eq!(
        document
            .as_object()
            .expect("object")
            .keys()
            .map(String::as_str)
            .collect::<Vec<_>>(),
        vec![
            "month",
            "first",
            "last",
            "events",
            "holidays",
            "holidays_error",
            "workdays",
            "workdays_error",
            "fetched_at",
            "cached"
        ]
    );
    assert_eq!(
        fs::read_to_string(holidays_cache_file(&sandbox.cache, "2026", "RU")).expect("holidays"),
        format!("{HOLIDAYS}\n")
    );
    assert_eq!(
        fs::read_to_string(workdays_cache_file(&sandbox.cache, "2026", "2026-11", "RU"))
            .expect("workdays"),
        WORKDAYS,
        "the workdays cache has no trailing newline"
    );
    for path in [
        &calendar_path,
        &holidays_cache_file(&sandbox.cache, "2026", "RU"),
        &workdays_cache_file(&sandbox.cache, "2026", "2026-11", "RU"),
    ] {
        assert_eq!(file_mode(path), expected_file_mode(), "{}", path.display());
    }
    // No temp files survive the writes.
    let leftovers: Vec<_> = fs::read_dir(&sandbox.cache)
        .expect("cache dir")
        .filter_map(|entry| entry.ok())
        .filter(|entry| entry.file_name().to_string_lossy().starts_with('.'))
        .collect();
    assert!(leftovers.is_empty(), "{leftovers:?}");
}

#[test]
fn khal_failure_is_a_sample_error_and_writes_no_cache() {
    let sandbox = Sandbox::new("khal-fail");
    let mock = Mock::start(provider_response);
    let args = once_args(&sandbox.cache, mock.base(), &["--month", "2026-11"]);
    let output = sandbox.run(
        &args,
        &[
            ("FAKE_KHAL_MODE", "fail"),
            ("FAKE_KHAL_STDERR", "khal: bad config"),
            ("FAKE_KHAL_CODE", "3"),
        ],
    );
    assert_eq!(output.status.code(), Some(0), "{}", stderr(&output));
    let lines = lines(&output);
    assert_eq!(lines[0], HANDSHAKE);
    let error = parse_line(&lines[1]);
    assert_eq!(error["ok"], false);
    assert_eq!(error["worker"], "calendar");
    assert_eq!(error["err"], "khal list failed: khal: bad config");
    assert_recent_ms(&error, "t", 10_000);
    assert!(mock.paths().is_empty(), "no HTTP API is touched");
    assert_eq!(
        fs::read_dir(&sandbox.cache).expect("cache dir").count(),
        0,
        "a failed khal writes no cache"
    );
    assert_eq!(sandbox.khal_calls().len(), 2, "ISO then dd.mm.yyyy");
}

#[test]
fn khal_failure_without_stderr_uses_the_exit_code() {
    let sandbox = Sandbox::new("khal-exit");
    let mock = Mock::start(provider_response);
    let args = once_args(&sandbox.cache, mock.base(), &["--month", "2026-11"]);
    let output = sandbox.run(
        &args,
        &[
            ("FAKE_KHAL_MODE", "fail"),
            ("FAKE_KHAL_STDERR", ""),
            ("FAKE_KHAL_CODE", "7"),
        ],
    );
    let error = parse_line(&lines(&output)[1]);
    assert_eq!(error["err"], "khal list failed: khal exited 7");
}

#[test]
fn khal_is_retried_in_the_european_format() {
    let sandbox = Sandbox::new("khal-retry");
    let mock = Mock::start(provider_response);
    let args = once_args(&sandbox.cache, mock.base(), &["--month", "2026-11"]);
    let output = sandbox.run(
        &args,
        &[
            ("FAKE_KHAL_MODE", "retry"),
            ("FAKE_KHAL_TEXT", "05.11.2026|09:00|EU event|Work"),
        ],
    );
    let sample = sample_of(&output);
    assert_eq!(
        sample["data"]["events"],
        serde_json::json!([
            {"date": "2026-11-05", "time": "09:00", "title": "EU event", "calendar": "Work"}
        ])
    );
    let calls = sandbox.khal_calls();
    assert_eq!(calls.len(), 2);
    assert!(calls[0].ends_with("2026-11-01 2026-11-30"), "{}", calls[0]);
    assert!(calls[1].ends_with("01.11.2026 30.11.2026"), "{}", calls[1]);
}

#[test]
fn critical_stderr_retries_even_when_khal_exits_zero() {
    let sandbox = Sandbox::new("khal-critical");
    let mock = Mock::start(provider_response);
    let args = once_args(&sandbox.cache, mock.base(), &["--month", "2026-11"]);
    let output = sandbox.run(
        &args,
        &[
            ("FAKE_KHAL_MODE", "critical-first"),
            ("FAKE_KHAL_TEXT", "2026-11-05|09:00|Second try|Work"),
        ],
    );
    let sample = sample_of(&output);
    assert_eq!(sample["data"]["events"][0]["title"], "Second try");
    assert_eq!(sandbox.khal_calls().len(), 2);
}

#[test]
fn http_failures_become_error_fields_not_sample_errors() {
    let sandbox = Sandbox::new("http-fail");
    let mock = Mock::start(|_| Response::error(500));
    let args = once_args(
        &sandbox.cache,
        mock.base(),
        &["--month", "2026-11", "--country", "RU"],
    );
    let output = sandbox.run(&args, &[]);
    assert_eq!(output.status.code(), Some(0), "{}", stderr(&output));
    let sample = sample_of(&output);
    let data = &sample["data"];
    assert_eq!(data["events"].as_array().expect("events").len(), 4);
    assert_eq!(data["holidays"], serde_json::json!([]));
    assert_eq!(data["workdays"], serde_json::json!([]));
    assert_eq!(
        data["holidays_error"],
        "holidays request failed: curl: (22) The requested URL returned error: 500"
    );
    assert_eq!(
        data["workdays_error"],
        "work calendar request failed: curl: (22) The requested URL returned error: 500"
    );
    assert_eq!(mock.paths().len(), 2);
    assert!(!holidays_cache_file(&sandbox.cache, "2026", "RU").exists());
    assert!(!workdays_cache_file(&sandbox.cache, "2026", "2026-11", "RU").exists());
    // The month cache still records the failed fetch.
    let document = parse_line(
        fs::read_to_string(cache_file(&sandbox.cache, "2026-11"))
            .expect("calendar cache")
            .trim_end(),
    );
    assert_eq!(document["holidays_error"], data["holidays_error"]);
    assert_eq!(document["workdays_error"], data["workdays_error"]);
    assert_eq!(document["cached"], true);
}

#[test]
fn a_failed_workday_fetch_does_not_hide_the_holidays() {
    let sandbox = Sandbox::new("http-half");
    let mock = Mock::start(|request| {
        if request.path().starts_with("/v3/") {
            Response::json(HOLIDAYS)
        } else {
            Response::error(503)
        }
    });
    let args = once_args(
        &sandbox.cache,
        mock.base(),
        &["--month", "2026-11", "--country", "RU"],
    );
    let sample = sample_of(&sandbox.run(&args, &[]));
    assert_eq!(
        sample["data"]["holidays"]
            .as_array()
            .expect("holidays")
            .len(),
        1
    );
    assert_eq!(
        sample["data"]["workdays_error"],
        "work calendar request failed: curl: (22) The requested URL returned error: 503"
    );
}

#[test]
fn no_country_means_no_http_and_empty_fields() {
    let sandbox = Sandbox::new("no-country");
    let mock = Mock::start(provider_response);
    let args = once_args(&sandbox.cache, mock.base(), &["--month", "2026-11"]);
    let sample = sample_of(&sandbox.run(&args, &[]));
    assert!(mock.paths().is_empty());
    assert_eq!(sample["data"]["holidays"], serde_json::json!([]));
    assert_eq!(sample["data"]["workdays"], serde_json::json!([]));
    assert_eq!(sample["data"]["holidays_error"], Value::Null);
    assert_eq!(sample["data"]["workdays_error"], Value::Null);
    assert!(!holidays_cache_file(&sandbox.cache, "2026", "RU").exists());
}

#[test]
fn the_second_sample_is_served_from_the_payload_cache() {
    let sandbox = Sandbox::new("cache-hit");
    let first = Mock::start(provider_response);
    let args = once_args(
        &sandbox.cache,
        first.base(),
        &["--month", "2026-11", "--country", "RU"],
    );
    assert_eq!(sandbox.run(&args, &[]).status.code(), Some(0));
    let first_fetched = parse_line(
        fs::read_to_string(cache_file(&sandbox.cache, "2026-11"))
            .expect("cache")
            .trim_end(),
    )["fetched_at"]
        .as_i64()
        .expect("fetched_at");

    // The pill tracker's file changes while the cache stays fresh; pills are
    // read on every sample and must show the new state.
    sandbox.write_state(
        r#"{"today":"2026-11-03","taken":true,"history":[{"date":"2026-11-02","taken":true}]}"#,
    );
    sandbox.clear_khal_log();
    let second = Mock::start(provider_response);
    let args = once_args(
        &sandbox.cache,
        second.base(),
        &["--month", "2026-11", "--country", "RU"],
    );
    let sample = sample_of(&sandbox.run(&args, &[]));
    assert_eq!(sample["data"]["cached"], true);
    assert!(sample["data"]["age_s"].as_i64().expect("age") >= 0);
    assert!(sample["data"]["age_s"].as_i64().expect("age") < 5);
    assert_eq!(sample["data"]["fetched_at"], first_fetched);
    assert_eq!(
        sample["data"]["pills"],
        serde_json::json!([
            {"date": "2026-11-03", "taken": true},
            {"date": "2026-11-02", "taken": true}
        ])
    );
    assert_eq!(sample["data"]["streak"], 2);
    assert!(sandbox.khal_calls().is_empty(), "a cache hit runs no khal");
    assert!(second.paths().is_empty(), "a cache hit touches no API");
}

#[test]
fn a_stale_payload_cache_is_refetched() {
    let sandbox = Sandbox::new("cache-stale");
    let fetched_at = now_secs() - 121;
    write_file(
        &cache_file(&sandbox.cache, "2026-11"),
        &format!(
            concat!(
                r#"{{"month":"2026-11","first":"F","last":"L","events":[],"#,
                r#""holidays":[],"holidays_error":null,"workdays":[],"workdays_error":null,"#,
                r#""fetched_at":{fetched_at},"cached":true}}"#
            ),
            fetched_at = fetched_at
        ),
    );
    let mock = Mock::start(provider_response);
    let args = once_args(
        &sandbox.cache,
        mock.base(),
        &["--month", "2026-11", "--country", "RU"],
    );
    let sample = sample_of(&sandbox.run(&args, &[]));
    assert_eq!(sample["data"]["cached"], false);
    assert_eq!(sample["data"]["first"], "2026-11-01");
    assert_eq!(sandbox.khal_calls().len(), 1);
    assert_eq!(mock.paths().len(), 2);
}

#[test]
fn a_cache_for_another_month_or_broken_json_is_refetched() {
    let sandbox = Sandbox::new("cache-wrong");
    let now = now_secs();
    for document in [
        format!(
            r#"{{"month":"2026-10","first":"F","last":"L","events":[],"holidays":[],"holidays_error":null,"workdays":[],"workdays_error":null,"fetched_at":{now},"cached":true}}"#
        ),
        "not json\n".to_string(),
        format!("{{\"month\":\"2026-11\"}}"),
    ] {
        write_file(&cache_file(&sandbox.cache, "2026-11"), &document);
        sandbox.clear_khal_log();
        let mock = Mock::start(provider_response);
        let args = once_args(&sandbox.cache, mock.base(), &["--month", "2026-11"]);
        let sample = sample_of(&sandbox.run(&args, &[]));
        assert_eq!(sample["data"]["cached"], false, "{document}");
        assert_eq!(sandbox.khal_calls().len(), 1, "{document}");
    }
}

#[test]
fn holiday_and_workday_caches_are_used_for_a_day() {
    let sandbox = Sandbox::new("source-cache");
    write_file(
        &holidays_cache_file(&sandbox.cache, "2026", "RU"),
        r#"[{"date":"2026-11-02","localName":"From cache","name":"Cached"}]"#,
    );
    write_file(
        &workdays_cache_file(&sandbox.cache, "2026", "2026-11", "RU"),
        "100000000000000000000000000000",
    );
    let mock = Mock::start(provider_response);
    let args = once_args(
        &sandbox.cache,
        mock.base(),
        &["--month", "2026-11", "--country", "RU"],
    );
    let sample = sample_of(&sandbox.run(&args, &[]));
    assert!(
        mock.paths().is_empty(),
        "fresh 24 h caches avoid the network"
    );
    assert_eq!(
        sample["data"]["holidays"],
        serde_json::json!([{"date": "2026-11-02", "name": "From cache", "name_en": "Cached"}])
    );
    assert_eq!(
        sample["data"]["workdays"],
        serde_json::json!([{"date": "2026-11-01", "code": 1}])
    );

    // A day later both files are stale and the APIs are asked again.
    set_mtime(
        &holidays_cache_file(&sandbox.cache, "2026", "RU"),
        now_secs() - 86_500,
    );
    set_mtime(
        &workdays_cache_file(&sandbox.cache, "2026", "2026-11", "RU"),
        now_secs() - 86_500,
    );
    let _ = fs::remove_file(cache_file(&sandbox.cache, "2026-11"));
    let mock = Mock::start(provider_response);
    let args = once_args(
        &sandbox.cache,
        mock.base(),
        &["--month", "2026-11", "--country", "RU"],
    );
    let refreshed = sample_of(&sandbox.run(&args, &[]));
    assert_eq!(mock.paths().len(), 2);
    assert_eq!(
        refreshed["data"]["holidays"],
        serde_json::json!([
            {"date": "2026-11-04", "name": "Den narodnogo edinstva", "name_en": "Unity Day"}
        ])
    );
    assert_eq!(
        refreshed["data"]["workdays"],
        serde_json::json!([{"date": "2026-11-05", "code": 1}])
    );
}

#[test]
fn month_arguments_cover_iso_and_day_forms() {
    let sandbox = Sandbox::new("months");
    let mock = Mock::start(provider_response);
    for (argument, month, first, last) in [
        ("2026-11", "2026-11", "2026-11-01", "2026-11-30"),
        ("2026-11-15", "2026-11", "2026-11-01", "2026-11-30"),
        ("2024-02", "2024-02", "2024-02-01", "2024-02-29"),
        ("2026-12", "2026-12", "2026-12-01", "2026-12-31"),
    ] {
        let args = once_args(&sandbox.cache, mock.base(), &["--month", argument]);
        let sample = sample_of(&sandbox.run(&args, &[]));
        assert_eq!(sample["data"]["month"], month);
        assert_eq!(sample["data"]["first"], first);
        assert_eq!(sample["data"]["last"], last);
    }

    for value in ["2026-13", "2026-1", "202611"] {
        let args = vec!["--month".to_string(), value.to_string()];
        let output = sandbox.run(&args, &[]);
        assert_eq!(output.status.code(), Some(2), "{value}");
        assert!(lines(&output).is_empty());
        assert_eq!(
            stderr(&output),
            format!("calendar: error: --month must be YYYY-MM or YYYY-MM-DD (got '{value}')\n")
        );
    }

    // No --month and an empty --month both mean "the current month".
    let args = once_args(&sandbox.cache, mock.base(), &[]);
    let current = sample_of(&sandbox.run(&args, &[]))["data"]["month"]
        .as_str()
        .expect("month")
        .to_string();
    assert_eq!(current.len(), 7, "{current}");
    assert_eq!(&current[4..5], "-");
    assert!(current[..4].bytes().all(|byte| byte.is_ascii_digit()));
    assert!(current[5..].bytes().all(|byte| byte.is_ascii_digit()));
}

#[test]
fn protocol_dialogue_is_acknowledged_in_order() {
    let sandbox = Sandbox::new("dialogue");
    let mock = Mock::start(provider_response);
    let mut args = arguments(&sandbox.cache, mock.base());
    args.extend([
        "--month".to_string(),
        "2026-11".to_string(),
        "--country".to_string(),
        "RU".to_string(),
    ]);
    let mut worker = sandbox.interactive(&args, &[]);

    assert_eq!(worker.next_line(), HANDSHAKE);

    // A long interval keeps periodic samples out of the dialogue.
    worker.send(r#"{"cmd":"subscribe","topic":"calendar","interval_ms":3600000}"#);
    assert_eq!(worker.next_line(), r#"{"ok":true,"ack":"subscribe"}"#);
    let first = parse_line(&worker.next_line());
    assert_eq!(first["data"]["month"], "2026-11");

    worker.send(r#"{"cmd":"sample","month":"2026-12"}"#);
    assert_eq!(worker.next_line(), r#"{"ok":true,"ack":"sample"}"#);
    let december = parse_line(&worker.next_line());
    assert_eq!(december["data"]["month"], "2026-12");
    assert_eq!(december["data"]["first"], "2026-12-01");
    // The December sample keeps the December holiday from the shared cache.
    assert_eq!(
        december["data"]["holidays"],
        serde_json::json!([{"date": "2026-12-31", "name": "New Year", "name_en": "New Year"}])
    );

    worker.send(r#"{"cmd":"set","interval_ms":250}"#);
    assert_eq!(worker.next_line(), r#"{"ok":true,"ack":"set"}"#);

    for (line, expected) in [
        (
            r#"{"cmd":"bogus"}"#,
            r#"{"ok":false,"err":"unknown cmd: bogus"}"#,
        ),
        ("not json", r#"{"ok":false,"err":"bad command line"}"#),
        ("null", r#"{"ok":false,"err":"unknown cmd: "}"#),
        (
            r#"{"cmd":"sample","month":"2026-13"}"#,
            r#"{"ok":false,"err":"bad month: 2026-13"}"#,
        ),
        (
            r#"{"cmd":"set"}"#,
            r#"{"ok":false,"err":"set needs interval_ms or month"}"#,
        ),
        (
            r#"{"cmd":"subscribe","topic":"calendar2"}"#,
            r#"{"ok":false,"err":"unknown topic: calendar2"}"#,
        ),
    ] {
        worker.send(line);
        assert_eq!(worker.next_line(), expected, "{line}");
    }

    // Unsubscribing stops the emission; `sample` then only acks.
    worker.send(r#"{"cmd":"unsubscribe","topic":"calendar"}"#);
    assert_eq!(worker.next_line(), r#"{"ok":true,"ack":"unsubscribe"}"#);
    worker.send(r#"{"cmd":"sample"}"#);
    assert_eq!(worker.next_line(), r#"{"ok":true,"ack":"sample"}"#);
    assert!(
        worker
            .next_line_within(Duration::from_millis(300))
            .is_none(),
        "unsubscribed samples are not emitted"
    );

    // A new subscription (default cadence) is due immediately again.
    worker.send(r#"{"cmd":"subscribe","topic":"calendar"}"#);
    assert_eq!(worker.next_line(), r#"{"ok":true,"ack":"subscribe"}"#);
    let again = parse_line(&worker.next_line());
    assert_eq!(again["data"]["month"], "2026-12");

    worker.send(r#"{"cmd":"stop"}"#);
    assert_eq!(worker.next_line(), r#"{"ok":true,"ack":"stop"}"#);
    let status = worker.wait_timeout(TIMEOUT).expect("worker exits");
    assert_eq!(status.code(), Some(0));
    assert!(worker.stderr().is_empty());
    assert!(worker
        .next_line_within(Duration::from_millis(200))
        .is_none());
}

#[test]
fn closed_stdin_prints_only_the_handshake() {
    let sandbox = Sandbox::new("closed");
    let mock = Mock::start(provider_response);
    let args = arguments(&sandbox.cache, mock.base());
    let args = args
        .into_iter()
        .chain(["--month".to_string(), "2026-11".to_string()])
        .collect::<Vec<_>>();
    let output = sandbox.run(&args, &[]);
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(
        String::from_utf8_lossy(&output.stdout),
        format!("{HANDSHAKE}\n")
    );
    assert!(sandbox.khal_calls().is_empty());
}

#[test]
fn sigterm_and_sigint_while_idle_exit_zero() {
    for signal in ["TERM", "INT"] {
        let sandbox = Sandbox::new(&format!("signal-idle-{signal}"));
        let mock = Mock::start(provider_response);
        let mut args = arguments(&sandbox.cache, mock.base());
        args.extend(["--month".to_string(), "2026-11".to_string()]);
        let mut worker = sandbox.interactive(&args, &[]);
        assert_eq!(worker.next_line(), HANDSHAKE);
        worker.signal(signal);
        let status = worker.wait_timeout(TIMEOUT).expect("worker exits");
        assert_eq!(status.code(), Some(0), "{signal}");
    }
}

#[test]
fn sigterm_aborts_an_in_flight_request() {
    let sandbox = Sandbox::new("signal-request");
    let mock = Mock::start(|request| {
        if request.path().starts_with("/v3/") {
            std::thread::sleep(Duration::from_secs(5));
            Response::json(HOLIDAYS)
        } else {
            Response::text(WORKDAYS)
        }
    });
    let mut args = arguments(&sandbox.cache, mock.base());
    args.extend([
        "--month".to_string(),
        "2026-11".to_string(),
        "--country".to_string(),
        "RU".to_string(),
    ]);
    let mut worker = sandbox.interactive(&args, &[]);
    assert_eq!(worker.next_line(), HANDSHAKE);
    assert!(
        mock.wait_for("/v3/PublicHolidays", 1, TIMEOUT),
        "the worker never started its request"
    );
    let started = Instant::now();
    worker.signal("TERM");
    let status = worker
        .wait_timeout(Duration::from_secs(2))
        .expect("worker exits");
    assert_eq!(status.code(), Some(0));
    assert!(started.elapsed() < Duration::from_secs(2));
    assert!(
        worker.drain().is_empty(),
        "no sample is written after the signal"
    );
}

#[test]
fn option_errors_match_the_shell() {
    let sandbox = Sandbox::new("options");
    for (args, message) in [
        (vec!["--month"], "--month needs a value"),
        (vec!["--country"], "--country needs a value"),
        (vec!["--cache-dir"], "--cache-dir needs a value"),
        (vec!["--interval-ms"], "--interval-ms needs a value"),
        (vec!["--workdays-base"], "--workdays-base needs a value"),
        (vec!["--holidays-base"], "--holidays-base needs a value"),
        (vec!["--bogus"], "unknown option '--bogus' (see --help)"),
        (
            vec!["--country", "RUS"],
            "--country must be a two-letter code (got 'RUS')",
        ),
        (
            vec!["--interval-ms", "x"],
            "--interval-ms must be an integer (got 'x')",
        ),
        (
            vec!["--interval-ms", "99"],
            "--interval-ms must be 100..3600000",
        ),
        (
            vec!["--month", "2026-13"],
            "--month must be YYYY-MM or YYYY-MM-DD (got '2026-13')",
        ),
    ] {
        let output = sandbox.run(
            &args
                .iter()
                .map(|value| value.to_string())
                .collect::<Vec<_>>(),
            &[],
        );
        assert_eq!(output.status.code(), Some(2), "{args:?}");
        assert!(lines(&output).is_empty(), "{args:?}");
        assert_eq!(stderr(&output), format!("calendar: error: {message}\n"));
    }
}

#[test]
fn help_prints_the_shell_usage_and_exits_zero() {
    let sandbox = Sandbox::new("help");
    let output = sandbox.run(&["--help".to_string()], &[]);
    assert_eq!(output.status.code(), Some(0));
    assert!(stderr(&output).is_empty());
    let text = String::from_utf8_lossy(&output.stdout);
    assert!(text.starts_with("calendar.sh - calendar worker (JSON lines, INTERFACES.md §7)\n"));
    assert!(text.contains("\n  --workdays-base URL  production calendar base (default: https://isdayoff.ru/api/getdata)\n"));
    assert!(text.contains("Exit status: 0 normal finish (stdin closed or stop); 1 cannot start.\n"));
    assert_eq!(text.lines().count(), 22);
}

#[test]
fn a_missing_khal_is_the_start_error() {
    let sandbox = Sandbox::new("no-khal");
    fs::remove_file(sandbox.bin.join("khal")).expect("remove fake khal");
    let output = sandbox.run(&["--once".to_string()], &[]);
    assert_eq!(output.status.code(), Some(1));
    assert_eq!(
        String::from_utf8_lossy(&output.stdout),
        "{\"ok\":false,\"worker\":\"calendar\",\"err\":\"khal not installed\"}\n"
    );
    assert!(stderr(&output).is_empty());
}

#[test]
fn pills_are_read_fresh_on_every_sample() {
    let sandbox = Sandbox::new("pills");
    let mock = Mock::start(provider_response);
    let args = once_args(&sandbox.cache, mock.base(), &["--month", "2026-11"]);
    assert_eq!(sandbox.run(&args, &[]).status.code(), Some(0));

    sandbox.write_state(
        r#"{"today":"2026-11-03","taken":true,"history":[{"date":"2026-11-02","taken":true},{"date":"2026-11-01","taken":false}]}"#,
    );
    let sample = sample_of(&sandbox.run(&args, &[]));
    assert_eq!(
        sample["data"]["pills"],
        serde_json::json!([
            {"date": "2026-11-03", "taken": true},
            {"date": "2026-11-02", "taken": true},
            {"date": "2026-11-01", "taken": false}
        ])
    );
    assert_eq!(sample["data"]["streak"], 2);

    // A broken file is no error: empty pills and no streak.
    sandbox.write_state("not json");
    let after_broken = sample_of(&sandbox.run(&args, &[]));
    assert_eq!(after_broken["data"]["pills"], serde_json::json!([]));
    assert_eq!(after_broken["data"]["streak"], 0);
}

#[test]
fn environment_defaults_are_honoured() {
    let sandbox = Sandbox::new("env");
    let mock = Mock::start(provider_response);
    let holidays = format!("{}/v3", mock.base());
    let workdays = format!("{}/getdata", mock.base());
    let args = vec![
        "--once".to_string(),
        "--month".to_string(),
        "2026-11".to_string(),
        "--country".to_string(),
        "RU".to_string(),
    ];
    let output = sandbox.run(
        &args,
        &[
            ("PLEAMAR_HOLIDAYS_BASE", holidays.as_str()),
            ("PLEAMAR_WORKDAYS_BASE", workdays.as_str()),
        ],
    );
    let sample = sample_of(&output);
    assert_eq!(
        sample["data"]["holidays"]
            .as_array()
            .expect("holidays")
            .len(),
        1
    );
    assert_eq!(mock.paths().len(), 2);
    // XDG_CACHE_HOME was in the sandbox environment: the default cache dir.
    assert!(sandbox
        .cache
        .join("pleamar/helpers/calendar-2026-11.json")
        .exists());

    // An empty XDG_CACHE_HOME falls back to $HOME/.cache.
    let args = vec![
        "--once".to_string(),
        "--month".to_string(),
        "2026-10".to_string(),
    ];
    let output = sandbox.run(
        &args,
        &[
            ("PLEAMAR_HOLIDAYS_BASE", holidays.as_str()),
            ("PLEAMAR_WORKDAYS_BASE", workdays.as_str()),
            ("XDG_CACHE_HOME", ""),
        ],
    );
    assert_eq!(output.status.code(), Some(0));
    assert!(sandbox
        .home
        .join(".cache/pleamar/helpers/calendar-2026-10.json")
        .exists());
}

#[test]
fn an_all_zero_workday_month_is_an_empty_array() {
    // The shell's awk/sed pipeline left WORKDAYS_JSON empty here, so its jq
    // call failed and the worker printed a truncated `"data":}` line; the port
    // writes the empty list the pipeline meant.
    let sandbox = Sandbox::new("workdays-zero");
    let mock = Mock::start(|request| {
        if request.path().starts_with("/v3/") {
            Response::json("[]")
        } else {
            Response::text("0".repeat(30))
        }
    });
    let args = once_args(
        &sandbox.cache,
        mock.base(),
        &["--month", "2026-11", "--country", "RU"],
    );
    let output = sandbox.run(&args, &[]);
    assert_eq!(output.status.code(), Some(0));
    let sample = sample_of(&output);
    assert_eq!(sample["data"]["workdays"], serde_json::json!([]));
    assert_eq!(sample["data"]["workdays_error"], Value::Null);
    assert!(workdays_cache_file(&sandbox.cache, "2026", "2026-11", "RU").exists());
}

#[test]
fn a_malformed_holiday_answer_is_an_error_not_a_broken_line() {
    let sandbox = Sandbox::new("holidays-bad");
    let mock = Mock::start(|request| {
        if request.path().starts_with("/v3/") {
            Response::json(r#"{"message":"nope"}"#)
        } else {
            Response::text(WORKDAYS)
        }
    });
    let args = once_args(
        &sandbox.cache,
        mock.base(),
        &["--month", "2026-11", "--country", "RU"],
    );
    let output = sandbox.run(&args, &[]);
    assert_eq!(output.status.code(), Some(0));
    let sample = sample_of(&output);
    assert_eq!(sample["data"]["holidays"], serde_json::json!([]));
    assert_eq!(
        sample["data"]["holidays_error"],
        "holidays request failed: answer is not a list"
    );
    assert!(!holidays_cache_file(&sandbox.cache, "2026", "RU").exists());
}

#[test]
fn events_keep_the_shell_parsing_quirks() {
    let sandbox = Sandbox::new("events");
    let mock = Mock::start(provider_response);
    let args = once_args(&sandbox.cache, mock.base(), &["--month", "2026-11"]);
    let output = sandbox.run(
        &args,
        &[(
            "FAKE_KHAL_TEXT",
            "next week|09:00|Unknown date|Cal\n2026-11-05|09:00||Empty title|\n",
        )],
    );
    let sample = sample_of(&output);
    assert_eq!(
        sample["data"]["events"],
        serde_json::json!([
            {"date": "next week", "time": "09:00", "title": "Unknown date", "calendar": "Cal"},
            // `${rest%|*}` strips the shortest `|…` suffix, so a leading pipe
            // stays in a title whose title field is empty.
            {"date": "2026-11-05", "time": "09:00", "title": "|Empty title", "calendar": ""}
        ])
    );
}
