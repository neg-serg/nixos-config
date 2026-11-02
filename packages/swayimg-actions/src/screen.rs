//! `screen_wh` from the shell: `swaymsg -t get_outputs -r | jq -r ...`, with a
//! hard-coded `1920x1080` fallback.
//!
//! The jq filter was:
//! `[.[] | select(.active and .current_mode != null) | {...}] |
//!  if length>0 then (max_by(.a) | "\(.w)x\(.h)") else empty end`
//!
//! The port parses the JSON with serde_json and reproduces the jq semantics
//! that are observable: jq truthiness for `active` (only false/null are false),
//! the whole selector failing when a selected output has a non-numeric
//! width/height, and `max_by` choosing the *last* maximal element on ties.
//! jq itself is no longer required or spawned.

use serde_json::Value;

use crate::tools::{Call, Outcome};

const FALLBACK: &[u8] = b"1920x1080";

pub fn screen_size() -> Vec<u8> {
    if !crate::tools::program_exists("swaymsg") {
        return FALLBACK.to_vec();
    }
    // The shell ignored swaymsg's exit status (`... || true` ended the
    // pipeline); jq parsed whatever arrived on stdout.
    let outcome: Outcome = Call::new("swaymsg")
        .argument("-t")
        .argument("get_outputs")
        .argument("-r")
        .capture_stdout()
        .quiet_stderr()
        .run();
    match parse(&outcome.stdout) {
        Some(size) => size.into_bytes(),
        None => FALLBACK.to_vec(),
    }
}

fn parse(stdout: &[u8]) -> Option<String> {
    let value: Value = serde_json::from_slice(stdout).ok()?;
    let items: Vec<&Value> = match &value {
        // jq's `.[]` iterates array elements and object values; anything else
        // is an error in the filter and therefore falls back.
        Value::Array(items) => items.iter().collect(),
        Value::Object(map) => map.values().collect(),
        _ => return None,
    };

    let mut best: Option<(f64, f64, f64)> = None;
    for item in items {
        let output = item.as_object()?;
        if !output.get("active").map(truthy).unwrap_or(false) {
            continue;
        }
        let current_mode = match output.get("current_mode") {
            None | Some(Value::Null) => continue,
            Some(value) => value.as_object()?,
        };
        let width = number(current_mode.get("width")?)?;
        let height = number(current_mode.get("height")?)?;
        let area = width * height;
        // `max_by` in jq returns the last element with the maximal key when
        // several compare equal (verified against jq 1.7 on this host).
        if best.is_none_or(|(_, _, best_area)| area >= best_area) {
            best = Some((width, height, area));
        }
    }

    let (width, height, _) = best?;
    Some(format!("{}x{}", jq_number(width), jq_number(height)))
}

/// jq truthiness: false and null are false, everything else (including 0 and
/// "") is true.
fn truthy(value: &Value) -> bool {
    !matches!(value, Value::Bool(false) | Value::Null)
}

/// jq's `tonumber`: numbers pass through, numeric strings are parsed; every
/// other type makes the whole filter fail (which is why it returns None here).
fn number(value: &Value) -> Option<f64> {
    match value {
        Value::Number(number) => number.as_f64(),
        Value::String(text) => text.trim().parse::<f64>().ok(),
        _ => None,
    }
}

/// jq prints integral numbers without a decimal part (`1920`, not `1920.0`);
/// real mode dimensions are integers, so this keeps the `WxH` string stable.
fn jq_number(value: f64) -> String {
    if !value.is_finite() {
        return value.to_string();
    }
    if value.fract() == 0.0 && value.abs() <= i64::MAX as f64 {
        format!("{}", value as i64)
    } else {
        format!("{value}")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn picks_the_largest_active_output() {
        let input = br#"[
          {"active": true, "current_mode": {"width": 1920, "height": 1080}},
          {"active": true, "current_mode": {"width": 2560, "height": 1440}},
          {"active": false, "current_mode": {"width": 3840, "height": 2160}},
          {"active": true, "current_mode": null},
          {"active": true}
        ]"#;
        assert_eq!(parse(input), Some("2560x1440".to_string()));
    }

    #[test]
    fn jq_truthiness_and_tie_break() {
        // active:0 is truthy in jq; ties keep the last maximum.
        let input = br#"[
          {"active": 0, "current_mode": {"width": 100, "height": 200}},
          {"active": true, "current_mode": {"width": 200, "height": 100}},
          {"active": "yes", "current_mode": {"width": 200, "height": 100}},
          {"active": false, "current_mode": {"width": 900, "height": 900}}
        ]"#;
        assert_eq!(parse(input), Some("200x100".to_string()));
    }

    #[test]
    fn non_numeric_dimension_fails_the_whole_filter() {
        let input = br#"[
          {"active": true, "current_mode": {"width": 1920, "height": 1080}},
          {"active": true, "current_mode": {"width": null, "height": 1080}}
        ]"#;
        assert_eq!(parse(input), None);
    }

    #[test]
    fn no_active_outputs_falls_back() {
        assert_eq!(parse(br#"[]"#), None);
        assert_eq!(parse(br#"{"active": true}"#), None);
        assert_eq!(parse(b"not json"), None);
    }

    #[test]
    fn numeric_strings_are_accepted_like_tonumber() {
        let input = br#"[{"active": true, "current_mode": {"width": "1920", "height": "1080"}}]"#;
        assert_eq!(parse(input), Some("1920x1080".to_string()));
    }
}
