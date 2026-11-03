//! End-to-end tests of the worker binary.
//!
//! Each test starts a local mock for every provider, points the worker's
//! `--*-base` flags at it, and checks the lines, the cache file and the
//! exit status. Nothing here can reach the network.

mod support;

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::time::{Duration, Instant};

use serde_json::Value;
use support::*;

const HANDSHAKE: &str =
    "{\"ok\":true,\"worker\":\"weather\",\"version\":1,\"topics\":[\"weather\"]}";

fn once_args(cache: &std::path::Path, base: &str, extra: &[&str]) -> Vec<String> {
    let mut args = arguments(cache, base);
    args.push("--once".to_string());
    args.extend(extra.iter().map(|value| value.to_string()));
    args
}

fn lines(output: &std::process::Output) -> Vec<String> {
    String::from_utf8_lossy(&output.stdout)
        .lines()
        .map(|line| line.to_string())
        .collect()
}

fn now_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_millis() as u64)
        .unwrap_or(0)
}

fn assert_recent(value: &Value, field: &str, tolerance_ms: u64) {
    let observed = value[field]
        .as_u64()
        .unwrap_or_else(|| panic!("{field} is not a number"));
    let now = now_ms();
    assert!(
        observed.abs_diff(now) <= tolerance_ms,
        "{field}={observed} is not near {now}"
    );
}

#[test]
fn once_prints_the_handshake_and_a_fresh_payload() {
    let directory = TempDir::new("once");
    let cache = directory.cache_file();
    let mock = Mock::start(provider_response);
    let args = once_args(&cache, mock.base(), &["--city", "Saint Petersburg"]);
    let output = run(&args, &[]);
    assert!(output.status.success(), "exit {:?}", output.status);
    assert_eq!(output.status.code(), Some(0));

    let lines = lines(&output);
    assert_eq!(lines.len(), 2, "handshake + one sample: {lines:?}");
    assert_eq!(lines[0], HANDSHAKE);
    assert!(
        lines[1].starts_with("{\"ok\":true,\"worker\":\"weather\",\"topic\":\"weather\",\"t\":"),
        "{}",
        lines[1]
    );
    let sample = parse_line(&lines[1]);
    assert_eq!(sample["ok"], true);
    assert_eq!(sample["worker"], "weather");
    assert_eq!(sample["topic"], "weather");
    assert_recent(&sample, "t", 10_000);

    let data = &sample["data"];
    assert_eq!(data["city"], "Saint Petersburg");
    assert_eq!(data["provider"], "open-meteo");
    assert_eq!(data["age_s"], 0);
    assert_eq!(data["cached"], false);
    assert!((data["fetched_at"].as_i64().unwrap() - now_secs()).abs() <= 5);
    // jq preserved the provider's number literals; so must the port.
    let raw = &lines[1];
    for literal in [
        "\"latitude\":59.93863",
        "\"longitude\":30.31413",
        "\"temp_c\":6.3",
        "\"wind_ms\":3.40",
        "\"is_day\":0",
        "\"humidity_pct\":81",
        "\"pressure_hpa\":1027.4",
        "\"tmax_c\":7.9",
        "\"tmin_c\":5.6",
        "\"tmax_c\":7.0",
        "\"tmin_c\":4.0",
    ] {
        assert!(raw.contains(literal), "missing {literal} in {raw}");
    }
    // The field order is the shell's jq object order.
    assert!(raw.contains(
        "\"data\":{\"city\":\"Saint Petersburg\",\"latitude\":59.93863,\"longitude\":30.31413,\"provider\":\"open-meteo\",\"fetched_at\":"
    ));
    assert!(raw.contains(
        "\"current\":{\"temp_c\":6.3,\"weather_code\":3,\"wind_ms\":3.40,\"wind_dir_deg\":231,\"is_day\":0,\"humidity_pct\":81,\"pressure_hpa\":1027.4}"
    ));
    assert!(
        lines[1].ends_with(
            "\"daily\":[{\"date\":\"2026-11-02\",\"tmax_c\":7.9,\"tmin_c\":5.6,\"weather_code\":3},{\"date\":\"2026-11-03\",\"tmax_c\":7.0,\"tmin_c\":4.0,\"weather_code\":53}]}}"
        ),
        "{}",
        lines[1]
    );

    // The request bytes: the geocoding query and the forecast query. The
    // providers are raced, so the forecast is found by its prefix — the
    // fallback's requests may sit in front of it in the log.
    let paths = mock.paths();
    let geocoding = paths
        .iter()
        .position(|path| path.starts_with("/geo/v1/search?"))
        .expect("geocoding request");
    assert_eq!(
        paths[geocoding],
        "/geo/v1/search?name=Saint%20Petersburg&count=1&language=en&format=json"
    );
    let forecast_index = paths
        .iter()
        .position(|path| path.starts_with("/v1/forecast?"))
        .expect("forecast request");
    assert_eq!(
        paths[forecast_index],
        "/v1/forecast?latitude=59.93863&longitude=30.31413&current=temperature_2m,weather_code,wind_speed_10m,wind_direction_10m,is_day,relative_humidity_2m,surface_pressure&daily=temperature_2m_max,temperature_2m_min,weathercode&wind_speed_unit=ms&timezone=auto&forecast_days=5"
    );
    assert_eq!(
        mock.count("/v1/forecast?"),
        1,
        "one attempt at the primary: {paths:?}"
    );
    let forecast = mock
        .requests()
        .into_iter()
        .find(|request| request.path().starts_with("/v1/forecast?"))
        .expect("forecast request");
    assert_eq!(forecast.method, "GET");
    assert_eq!(forecast.header("user-agent"), Some("pleamar-weather/1.0"));
    assert_eq!(forecast.header("accept"), Some("*/*"));

    // The cache file: shape, mode and the payload inside it.
    let cache_text = fs::read_to_string(&cache).expect("cache file");
    assert!(cache_text.ends_with("}\n"));
    assert!(cache_text.starts_with(
        "{\"city\":\"Saint Petersburg\",\"latitude\":59.93863,\"longitude\":30.31413,\"geocoded_at\":"
    ));
    assert!(cache_text.contains(",\"fetched_at\":"));
    assert!(cache_text.contains("\"payload\":{\"city\":\"Saint Petersburg\","));
    let mode = fs::metadata(&cache)
        .expect("cache metadata")
        .permissions()
        .mode();
    assert_eq!(mode & 0o777, 0o600, "mktemp-style private cache file");
    let document: Value = serde_json::from_str(&cache_text).expect("cache JSON");
    assert!(document["payload"]["daily"].is_array());
    assert_eq!(document["payload"]["provider"], "open-meteo");
    // No temp file left next to the cache.
    let leftovers: Vec<_> = fs::read_dir(cache.parent().expect("cache parent"))
        .expect("cache dir")
        .filter_map(|entry| entry.ok())
        .filter(|entry| entry.file_name().to_string_lossy().starts_with(".weather."))
        .collect();
    assert!(leftovers.is_empty(), "temp cache file left behind");
}

#[test]
fn explicit_coordinates_skip_geocoding() {
    let directory = TempDir::new("coords");
    let cache = directory.cache_file();
    let mock = Mock::start(provider_response);
    let args = once_args(&cache, mock.base(), &["--lat", "59.9", "--lon", "30.7"]);
    let output = run(&args, &[]);
    assert_eq!(output.status.code(), Some(0));
    let lines = lines(&output);
    let data = &parse_line(&lines[1])["data"];
    assert_eq!(data["latitude"].as_f64(), Some(59.9));
    assert_eq!(data["longitude"].as_f64(), Some(30.7));
    assert_eq!(mock.count("/geo/"), 0, "geocoding must be skipped");
    assert_eq!(mock.count("/v1/forecast?"), 1);
    assert!(
        mock.paths()
            .iter()
            .any(|path| path.starts_with("/v1/forecast?latitude=59.9&longitude=30.7&")),
        "{:?}",
        mock.paths()
    );
}

#[test]
fn openmeteo_failure_falls_back_to_wttr_current_and_metno_daily() {
    let directory = TempDir::new("fallback");
    let cache = directory.cache_file();
    let mock = Mock::start(|request| {
        let path = request.path();
        if path.starts_with("/v1/forecast?") {
            Response::error(503)
        } else if path.starts_with("/metno/compact?") {
            Response::json(METNO)
        } else if path.starts_with("/wttr/") {
            Response::text(WTTR)
        } else {
            Response::error(404)
        }
    });
    let args = once_args(&cache, mock.base(), &["--lat", "59.9", "--lon", "30.7"]);
    let output = run(&args, &[]);
    assert_eq!(output.status.code(), Some(0));
    let lines = lines(&output);
    assert_eq!(lines.len(), 2, "{lines:?}");
    let sample = parse_line(&lines[1]);
    let data = &sample["data"];
    assert_eq!(data["provider"], "wttr.in");
    assert_eq!(data["cached"], false);
    // wttr's current conditions, with jq's literal handling: "+3" becomes 3,
    // "8km/h" becomes 2.2 m/s, and is_day is null.
    assert_eq!(data["current"]["temp_c"], 3);
    assert_eq!(data["current"]["weather_code"], 2);
    assert_eq!(data["current"]["wind_ms"], 2.2);
    assert_eq!(data["current"]["wind_dir_deg"], 0);
    assert_eq!(data["current"]["is_day"], Value::Null);
    assert_eq!(data["current"]["humidity_pct"], 81);
    // Pressure is field 6 (%P), exactly the shell's `pres`.
    assert!(lines[1].contains("\"pressure_hpa\":29.80"));
    // The daily forecast is MET Norway's, converted to WMO codes.
    assert_eq!(
        data["daily"],
        serde_json::json!([
            {"date": "2026-11-02", "tmax_c": 7.9, "tmin_c": 5.6, "weather_code": 2},
            {"date": "2026-11-03", "tmax_c": 7.0, "tmin_c": 7.0, "weather_code": 3},
        ])
    );
    // The cache holds the fallback payload.
    let document: Value =
        serde_json::from_str(&fs::read_to_string(&cache).expect("cache")).expect("cache JSON");
    assert_eq!(document["payload"]["provider"], "wttr.in");
    assert_eq!(mock.count("/v1/forecast?"), 1);
    assert_eq!(mock.count("/wttr/"), 1);
    assert_eq!(mock.count("/metno/compact?"), 1);
    // The wttr request carries the raw `|` format, like curl sent it.
    let wttr = mock
        .requests()
        .into_iter()
        .find(|request| request.path().starts_with("/wttr/"))
        .expect("wttr request");
    assert_eq!(
        wttr.path(),
        format!("/wttr/59.9,30.7?format={}", "%c|%t|%h|%w|%C|%p|%P|%u")
    );
}

#[test]
fn a_blackholed_primary_does_not_hold_the_card_for_its_deadline() {
    let directory = TempDir::new("race");
    let cache = directory.cache_file();
    let mock = Mock::start(|request| {
        let path = request.path();
        if path.starts_with("/v1/forecast?") {
            // What this host sees on api.open-meteo.com: the connection is
            // accepted and then nothing arrives, so only the worker's deadline
            // ends the request. Longer than --timeout on purpose.
            std::thread::sleep(Duration::from_secs(5));
            Response::json(FORECAST)
        } else if path.starts_with("/wttr/") {
            Response::text(WTTR)
        } else if path.starts_with("/metno/compact?") {
            Response::json(METNO)
        } else {
            Response::error(404)
        }
    });
    let started = Instant::now();
    let output = run(
        &once_args(&cache, mock.base(), &["--lat", "59.9", "--lon", "30.7"]),
        &[],
    );
    let elapsed = started.elapsed();
    assert_eq!(output.status.code(), Some(0));
    let data = &parse_line(&lines(&output)[1])["data"];
    assert_eq!(data["provider"], "wttr.in");
    assert_eq!(mock.count("/wttr/"), 1, "the fallback must be dialled");
    // The point of the race: the sample lands on the fallback's time, not after
    // the primary's deadline.
    assert!(
        elapsed < Duration::from_millis(1_500),
        "the dead primary held the sample for {elapsed:?}"
    );
}

#[test]
fn no_fallback_reports_the_primary_error_and_writes_no_cache() {
    let directory = TempDir::new("no-fallback");
    let cache = directory.cache_file();
    let mock = Mock::start(|request| {
        if request.path().starts_with("/v1/forecast?") {
            Response::error(500)
        } else {
            Response::error(404)
        }
    });
    let args = once_args(
        &cache,
        mock.base(),
        &["--lat", "59.9", "--lon", "30.7", "--no-fallback"],
    );
    let output = run(&args, &[]);
    assert_eq!(output.status.code(), Some(0));
    let lines = lines(&output);
    assert_eq!(lines.len(), 2, "{lines:?}");
    assert_eq!(lines[0], HANDSHAKE);
    let error = parse_line(&lines[1]);
    assert_eq!(error["ok"], false);
    assert_eq!(error["worker"], "weather");
    assert_eq!(
        error["err"],
        "open-meteo request failed: curl: (22) The requested URL returned error: 500"
    );
    assert_recent(&error, "t", 10_000);
    assert_eq!(mock.count("/wttr/"), 0, "fallback disabled");
    assert!(!cache.exists(), "a failed fetch must not write a cache");
}

#[test]
fn a_fresh_cache_is_served_without_the_network() {
    let directory = TempDir::new("cache-hit");
    let cache = directory.cache_file();
    let now = now_secs();
    write_cache(
        &cache,
        &cache_document("Oslo", "59.9", "10.7", now, now, "open-meteo"),
    );
    let mock = Mock::start(provider_response);
    let args = once_args(&cache, mock.base(), &["--city", "Oslo"]);
    let output = run(&args, &[]);
    assert_eq!(output.status.code(), Some(0));
    let lines = lines(&output);
    let data = &parse_line(&lines[1])["data"];
    assert_eq!(data["cached"], true);
    assert_eq!(data["fetched_at"].as_i64(), Some(now));
    let age = data["age_s"].as_i64().expect("age");
    assert!((0..=5).contains(&age), "age_s={age}");
    assert_eq!(data["provider"], "open-meteo");
    assert_eq!(data["city"], "Oslo");
    assert_eq!(mock.requests().len(), 0, "no request on a cache hit");
}

#[test]
fn force_ignores_a_fresh_cache() {
    let directory = TempDir::new("force");
    let cache = directory.cache_file();
    let now = now_secs();
    write_cache(
        &cache,
        &cache_document("Oslo", "59.9", "10.7", now, now, "wttr.in"),
    );
    let mock = Mock::start(provider_response);
    let args = once_args(&cache, mock.base(), &["--city", "Oslo", "--force"]);
    let output = run(&args, &[]);
    assert_eq!(output.status.code(), Some(0));
    let lines = lines(&output);
    let data = &parse_line(&lines[1])["data"];
    assert_eq!(data["cached"], false);
    assert_eq!(data["provider"], "open-meteo");
    assert_eq!(mock.count("/v1/forecast?"), 1);
    // The cache was rewritten with the new payload.
    let document: Value =
        serde_json::from_str(&fs::read_to_string(&cache).expect("cache")).expect("cache JSON");
    assert_eq!(document["payload"]["provider"], "open-meteo");
}

#[test]
fn a_stale_cache_is_refetched() {
    let directory = TempDir::new("stale");
    let cache = directory.cache_file();
    let now = now_secs();
    write_cache(
        &cache,
        &cache_document("Oslo", "59.9", "10.7", now, now - 1_000, "wttr.in"),
    );
    let mock = Mock::start(provider_response);
    let args = once_args(&cache, mock.base(), &["--city", "Oslo"]);
    let output = run(&args, &[]);
    assert_eq!(output.status.code(), Some(0));
    let data = &parse_line(&lines(&output)[1])["data"];
    assert_eq!(data["cached"], false);
    assert_eq!(data["provider"], "open-meteo");
    assert_eq!(mock.count("/v1/forecast?"), 1);
}

#[test]
fn a_payloadless_cache_is_ignored() {
    let directory = TempDir::new("daily-less");
    let cache = directory.cache_file();
    write_cache(
        &cache,
        r#"{"city":"Oslo","latitude":59.9,"longitude":10.7,"geocoded_at":1,"fetched_at":1,"payload":{"city":"Oslo","latitude":59.9,"longitude":10.7,"provider":"open-meteo","fetched_at":1,"age_s":0,"cached":false,"current":{},"daily":null}}"#,
    );
    let mock = Mock::start(provider_response);
    let args = once_args(&cache, mock.base(), &["--city", "Oslo"]);
    let output = run(&args, &[]);
    assert_eq!(output.status.code(), Some(0));
    let data = &parse_line(&lines(&output)[1])["data"];
    assert_eq!(data["cached"], false);
    assert_eq!(mock.count("/v1/forecast?"), 1);
}

#[test]
fn geocoding_is_reused_for_a_day() {
    let directory = TempDir::new("geo-reuse");
    let cache = directory.cache_file();
    let now = now_secs();
    // A stale payload (so the cache is not served) with coordinates guessed
    // an hour ago: resolve_coords must reuse them without a geocoder request.
    write_cache(
        &cache,
        &cache_document(
            "Oslo",
            "59.9",
            "10.7",
            now - 3_600,
            now - 1_000,
            "open-meteo",
        ),
    );
    let mock = Mock::start(provider_response);
    let output = run(&once_args(&cache, mock.base(), &["--city", "Oslo"]), &[]);
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(mock.count("/geo/"), 0, "coordinates reused");
    assert!(
        mock.paths()
            .iter()
            .any(|path| path.starts_with("/v1/forecast?latitude=59.9&longitude=10.7&")),
        "{:?}",
        mock.paths()
    );

    // Older than a day: the geocoder is asked again.
    write_cache(
        &cache,
        &cache_document(
            "Oslo",
            "59.9",
            "10.7",
            now - 90_000,
            now - 1_000,
            "open-meteo",
        ),
    );
    let mock = Mock::start(provider_response);
    let output = run(&once_args(&cache, mock.base(), &["--city", "Oslo"]), &[]);
    assert_eq!(output.status.code(), Some(0));
    assert_eq!(mock.count("/geo/"), 1, "geocoding memory expired");
    let data = &parse_line(&lines(&output)[1])["data"];
    assert_eq!(data["latitude"].as_f64(), Some(59.93863));
}

#[test]
fn malformed_openmeteo_falls_back_and_reports_without_it() {
    let directory = TempDir::new("malformed");
    let cache = directory.cache_file();
    let mock = Mock::start(|request| {
        let path = request.path();
        if path.starts_with("/v1/forecast?") {
            Response::json("{\"current\": \"truncated")
        } else if path.starts_with("/wttr/") {
            Response::text(WTTR)
        } else if path.starts_with("/metno/compact?") {
            Response::json(METNO)
        } else {
            Response::error(404)
        }
    });
    let output = run(
        &once_args(&cache, mock.base(), &["--lat", "59.9", "--lon", "30.7"]),
        &[],
    );
    assert_eq!(output.status.code(), Some(0));
    let data = &parse_line(&lines(&output)[1])["data"];
    assert_eq!(data["provider"], "wttr.in");

    let output = run(
        &once_args(
            &cache,
            mock.base(),
            &["--lat", "59.9", "--lon", "30.7", "--no-fallback", "--force"],
        ),
        &[],
    );
    let error = parse_line(&lines(&output)[1]);
    assert_eq!(error["err"], "open-meteo response has no current weather");
}

#[test]
fn a_broken_metno_leaves_daily_empty_and_the_wttr_reading_intact() {
    let directory = TempDir::new("broken-metno");
    let cache = directory.cache_file();
    let mock = Mock::start(|request| {
        let path = request.path();
        if path.starts_with("/v1/forecast?") {
            Response::error(503)
        } else if path.starts_with("/wttr/") {
            Response::text(WTTR)
        } else if path.starts_with("/metno/compact?") {
            Response::text("<html>service unavailable</html>")
        } else {
            Response::error(404)
        }
    });
    let output = run(
        &once_args(&cache, mock.base(), &["--lat", "59.9", "--lon", "30.7"]),
        &[],
    );
    assert_eq!(output.status.code(), Some(0));
    let lines = lines(&output);
    let data = &parse_line(&lines[1])["data"];
    assert_eq!(data["provider"], "wttr.in");
    assert_eq!(data["daily"], serde_json::json!([]));
    assert!(lines[1].ends_with("\"daily\":[]}}"), "{}", lines[1]);
}

#[test]
fn both_providers_failing_joins_the_two_errors() {
    let directory = TempDir::new("both-fail");
    let cache = directory.cache_file();
    let mock = Mock::start(|request| {
        let path = request.path();
        if path.starts_with("/v1/forecast?") {
            Response::error(503)
        } else if path.starts_with("/wttr/") {
            Response::text("no weather here")
        } else {
            Response::error(404)
        }
    });
    let output = run(
        &once_args(&cache, mock.base(), &["--lat", "59.9", "--lon", "30.7"]),
        &[],
    );
    assert_eq!(output.status.code(), Some(0));
    let error = parse_line(&lines(&output)[1]);
    assert_eq!(
        error["err"],
        concat!(
            "open-meteo request failed: curl: (22) The requested URL returned error: 503; ",
            "wttr.in response has no temperature",
        )
    );
    assert!(!cache.exists());
}

#[test]
fn a_city_is_percent_encoded_like_jq_uri() {
    let directory = TempDir::new("uri");
    let cache = directory.cache_file();
    let mock = Mock::start(provider_response);
    let output = run(&once_args(&cache, mock.base(), &["--city", "Zürich"]), &[]);
    assert_eq!(output.status.code(), Some(0));
    let paths = mock.paths();
    assert!(
        paths[0].starts_with("/geo/v1/search?name=Z%C3%BCrich&count=1&language=en&format=json"),
        "{}",
        paths[0]
    );
}

#[test]
fn environment_defaults_are_honoured() {
    let directory = TempDir::new("env");
    let cache = directory.cache_file();
    let mock = Mock::start(provider_response);
    let base = mock.base().to_string();
    let api = format!("{base}/v1");
    let geo = format!("{base}/geo/v1");
    let wttr = format!("{base}/wttr");
    let metno = format!("{base}/metno");
    let env = [
        ("PLEAMAR_WEATHER_CITY", "Oslo"),
        ("PLEAMAR_WEATHER_API_BASE", api.as_str()),
        ("PLEAMAR_WEATHER_GEOCODING_BASE", geo.as_str()),
        ("PLEAMAR_WEATHER_WTTR_BASE", wttr.as_str()),
        ("PLEAMAR_WEATHER_METNO_BASE", metno.as_str()),
        ("PLEAMAR_WEATHER_USER_AGENT", "agent/9"),
    ];
    let args = vec![
        "--cache-file".to_string(),
        cache.to_string_lossy().into_owned(),
        "--once".to_string(),
    ];
    let output = run(&args, &env);
    assert_eq!(output.status.code(), Some(0));
    let lines = lines(&output);
    let data = &parse_line(&lines[1])["data"];
    assert_eq!(data["city"], "Oslo");
    assert_eq!(data["provider"], "open-meteo");
    let forecast = mock
        .requests()
        .into_iter()
        .find(|request| request.path().starts_with("/v1/forecast?"))
        .expect("forecast request");
    assert_eq!(forecast.header("user-agent"), Some("agent/9"));
    assert_eq!(mock.count("/geo/"), 1);
}

#[test]
fn a_worker_without_city_or_coordinates_reports_an_error_sample() {
    let directory = TempDir::new("no-city");
    let cache = directory.cache_file();
    let mock = Mock::start(provider_response);
    let output = run(&once_args(&cache, mock.base(), &[]), &[]);
    assert_eq!(output.status.code(), Some(0));
    let lines = lines(&output);
    assert_eq!(lines.len(), 2);
    let error = parse_line(&lines[1]);
    assert_eq!(error["ok"], false);
    assert_eq!(
        error["err"],
        "no city configured (use --city, --lat/--lon or PLEAMAR_WEATHER_CITY)"
    );
    assert_eq!(mock.requests().len(), 0);
}

#[test]
fn protocol_dialogue_is_acknowledged_in_order() {
    let directory = TempDir::new("dialogue");
    let cache = directory.cache_file();
    let mock = Mock::start(provider_response);
    let mut args = arguments(&cache, mock.base());
    args.extend(["--city", "Oslo"].map(String::from));
    let mut worker = Interactive::start(&args, &[]);

    assert_eq!(worker.next_line(), HANDSHAKE);
    // The auto-subscription has next=0, so the first loop pass emits a sample
    // without any command.
    let first = worker.next_line();
    assert!(first.starts_with("{\"ok\":true,\"worker\":\"weather\",\"topic\":\"weather\",\"t\":"));
    assert_eq!(parse_line(&first)["data"]["city"], "Oslo");

    worker.send(r#"{"cmd":"subscribe","topic":"weather","interval_ms":600000}"#);
    assert_eq!(worker.next_line(), r#"{"ok":true,"ack":"subscribe"}"#);
    let sample = parse_line(&worker.next_line());
    assert_eq!(sample["topic"], "weather");

    worker.send(r#"{"cmd":"set","interval_ms":250}"#);
    assert_eq!(worker.next_line(), r#"{"ok":true,"ack":"set"}"#);

    worker.send(r#"{"cmd":"unsubscribe","topic":"weather"}"#);
    assert_eq!(worker.next_line(), r#"{"ok":true,"ack":"unsubscribe"}"#);

    // Unsubscribed: `sample` is only acknowledged.
    worker.send(r#"{"cmd":"sample"}"#);
    assert_eq!(worker.next_line(), r#"{"ok":true,"ack":"sample"}"#);
    worker.send(r#"{"cmd":"bogus"}"#);
    assert_eq!(
        worker.next_line(),
        r#"{"ok":false,"err":"unknown cmd: bogus"}"#
    );

    // Re-subscribe without an interval: back to --interval-ms (600000).
    worker.send(r#"{"cmd":"subscribe","topic":"weather"}"#);
    assert_eq!(worker.next_line(), r#"{"ok":true,"ack":"subscribe"}"#);
    assert_eq!(
        parse_line(&worker.next_line())["topic"],
        Value::String("weather".to_string())
    );

    worker.send(r#"{"cmd":"subscribe","topic":"weather2"}"#);
    assert_eq!(
        worker.next_line(),
        r#"{"ok":false,"err":"unknown topic: weather2"}"#
    );
    worker.send(r#"{"cmd":"subscribe","topic":"weather","interval_ms":50}"#);
    assert_eq!(
        worker.next_line(),
        r#"{"ok":false,"err":"interval_ms must be 100..3600000"}"#
    );
    worker.send(r#"{"cmd":"subscribe","topic":"weather","interval_ms":"x"}"#);
    assert_eq!(
        worker.next_line(),
        r#"{"ok":false,"err":"interval_ms must be an integer"}"#
    );
    worker.send_raw("{not json\n");
    assert_eq!(
        worker.next_line(),
        r#"{"ok":false,"err":"bad command line"}"#
    );

    worker.send(r#"{"cmd":"stop"}"#);
    assert_eq!(worker.next_line(), r#"{"ok":true,"ack":"stop"}"#);
    let status = worker.wait_timeout(TIMEOUT).expect("stop exits");
    assert_eq!(status.code(), Some(0));
}

#[test]
fn closed_stdin_finishes_with_exit_zero() {
    let directory = TempDir::new("stdin-closed");
    let cache = directory.cache_file();
    let args = arguments(&cache, "http://127.0.0.1:1");
    let mut worker = Interactive::start(&args, &[]);
    assert_eq!(worker.next_line(), HANDSHAKE);
    worker.close_stdin();
    let status = worker
        .wait_timeout(TIMEOUT)
        .expect("exit after stdin closes");
    assert_eq!(status.code(), Some(0));
}

#[test]
fn sigterm_while_idle_exits_zero() {
    let directory = TempDir::new("sigterm-idle");
    let cache = directory.cache_file();
    let mock = Mock::start(provider_response);
    let mut args = arguments(&cache, mock.base());
    args.extend(["--city", "Oslo"].map(String::from));
    let mut worker = Interactive::start(&args, &[]);
    assert_eq!(worker.next_line(), HANDSHAKE);
    worker.signal_term();
    let status = worker
        .wait_timeout(Duration::from_secs(5))
        .expect("exit on SIGTERM");
    assert_eq!(status.code(), Some(0));
    let leftovers: Vec<_> = fs::read_dir(cache.parent().unwrap_or(directory.path()))
        .map(|entries| {
            entries
                .filter_map(|entry| entry.ok())
                .filter(|entry| entry.file_name().to_string_lossy().starts_with(".weather."))
                .collect()
        })
        .unwrap_or_default();
    assert!(leftovers.is_empty(), "temp file left after SIGTERM");
}

#[test]
fn sigterm_aborts_an_in_flight_request() {
    let directory = TempDir::new("sigterm-flight");
    let cache = directory.cache_file();
    let mock = Mock::start(|request| {
        if request.path().starts_with("/v1/forecast?") {
            // Longer than any timeout in this test: only the signal can end it.
            std::thread::sleep(Duration::from_secs(30));
            Response::json(FORECAST)
        } else {
            Response::error(404)
        }
    });
    let mut args = arguments(&cache, mock.base());
    args.extend(
        [
            "--lat",
            "59.9",
            "--lon",
            "30.7",
            "--timeout",
            "60",
            "--no-fallback",
        ]
        .map(String::from),
    );
    let mut worker = Interactive::start(&args, &[]);
    assert_eq!(worker.next_line(), HANDSHAKE);
    assert!(
        mock.wait_for("/v1/forecast?", 1, Duration::from_secs(5)),
        "the request never started"
    );
    let started = Instant::now();
    worker.signal_term();
    let status = worker
        .wait_timeout(Duration::from_secs(5))
        .expect("exit while the request is in flight");
    assert_eq!(status.code(), Some(0));
    assert!(
        started.elapsed() < Duration::from_secs(3),
        "the in-flight request was not aborted: {:?}",
        started.elapsed()
    );
    assert!(!cache.exists(), "no cache from an interrupted fetch");
}

#[test]
fn option_errors_match_the_shell() {
    for (args, message) in [
        (
            vec!["--lat", "59.9"],
            "--lat and --lon must be given together",
        ),
        (
            vec!["--lon", "30.7"],
            "--lat and --lon must be given together",
        ),
        (
            vec!["--lat", "x", "--lon", "1"],
            "--lat must be a number (got 'x')",
        ),
        (
            vec!["--lon", "x", "--lat", "1"],
            "--lon must be a number (got 'x')",
        ),
        (
            vec!["--ttl", "-1"],
            "--ttl must be a non-negative integer (got '-1')",
        ),
        (
            vec!["--interval-ms", "99"],
            "--interval-ms must be 100..3600000",
        ),
        (
            vec!["--interval-ms", "x"],
            "--interval-ms must be an integer (got 'x')",
        ),
        (
            vec!["--forecast-days", "17"],
            "--forecast-days must be 1..16",
        ),
        (vec!["--timeout", "0"], "--timeout must be 1..120"),
        (vec!["--city"], "--city needs a value"),
        (vec!["--bogus"], "unknown option '--bogus' (see --help)"),
    ] {
        let output = run(
            &args
                .iter()
                .map(|value| value.to_string())
                .collect::<Vec<_>>(),
            &[],
        );
        assert_eq!(output.status.code(), Some(2), "{args:?}");
        assert!(output.stdout.is_empty(), "{args:?} wrote to stdout");
        assert_eq!(
            String::from_utf8_lossy(&output.stderr),
            format!("weather: error: {message}\n"),
            "{args:?}"
        );
    }
}

#[test]
fn help_prints_the_shell_usage_and_exits_zero() {
    for option in ["--help", "-h"] {
        let output = run(&[option.to_string()], &[]);
        assert_eq!(output.status.code(), Some(0));
        let stdout = String::from_utf8_lossy(&output.stdout);
        assert!(stdout.starts_with("weather.sh - weather worker (JSON lines, INTERFACES.md §7)\n"));
        assert!(stdout.contains("  --metno-base URL     MET Norway forecast base (default:\n"));
        assert!(stdout
            .ends_with("Exit status: 0 normal finish (stdin closed or stop); 1 cannot start.\n"));
        assert!(output.stderr.is_empty());
    }
}
