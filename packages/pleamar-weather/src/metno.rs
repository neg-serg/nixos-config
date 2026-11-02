//! MET Norway: the daily forecast when Open-Meteo's `daily` is out of reach.
//!
//! The shell fetched `$METNO_BASE/compact?lat=$LAT&lon=$LON` and ran this jq
//! program, whose behaviour this module reproduces:
//!
//! ```text
//! def wmo:
//!   (gsub("_(day|night|polartwilight)$"; "")) as $k
//!   | if ($k | test("thunder")) then 95
//!     elif ($k | test("heavysnow")) then 75
//!     ...
//! [ .properties.timeseries[]?
//!   | { date: (.time[0:10]), hour: (.time[11:13]), temp: …air_temperature,
//!       code: (…symbol_code // … // "cloudy" | wmo) } ]
//! | map(select(.date != null and .temp != null))
//! | group_by(.date)
//! | map({ date: .[0].date, tmax_c: (map(.temp) | max), tmin_c: (map(.temp) | min),
//!         weather_code: ((map(select(.hour == "12")) | .[0].code)
//!                        // (.[((length / 2) | floor)].code) // 2) })
//! | .[0:$n]
//! ```
//!
//! Two jq details matter for the bytes: number literals are preserved
//! (`RawValue`), and `max`/`min` over equal values pick the last/first entry
//! of jq's (stable) ordering, which the tie handling below repeats.

use std::cmp::Ordering;
use std::collections::BTreeMap;

use serde_json::value::RawValue;

use crate::failure::Failure;
use crate::geo::Coords;
use crate::http::Http;
use crate::json;
use crate::payload::Entry;

pub const NO_DAYS: &str = "met.no answer has no days";

type JsonObject = BTreeMap<String, Box<RawValue>>;

fn as_object(text: &str) -> Option<JsonObject> {
    serde_json::from_str(text).ok()
}

fn is_null(raw: &RawValue) -> bool {
    raw.get() == "null"
}

/// Walk `path` from `text`, re-parsing one object level at a time. `Ok(None)`
/// is jq's null (`null.foo` stays null); `Err(())` is jq's "cannot index …",
/// which made the whole program fail and produced `met.no answer has no days`.
fn lookup(text: &str, path: &[&str]) -> Result<Option<String>, ()> {
    let mut current = text.to_string();
    for (index, key) in path.iter().enumerate() {
        let object: JsonObject = serde_json::from_str(&current).map_err(|_| ())?;
        let Some(raw) = object.get(*key) else {
            return Ok(None);
        };
        if is_null(raw) {
            return Ok(None);
        }
        current = raw.get().to_string();
        if index + 1 == path.len() {
            return Ok(Some(current));
        }
    }
    Ok(None)
}

fn string_member(object: &JsonObject, key: &str) -> Result<Option<String>, ()> {
    let Some(raw) = object.get(key) else {
        return Ok(None);
    };
    if is_null(raw) {
        return Ok(None);
    }
    serde_json::from_str::<String>(raw.get())
        .map(Some)
        .map_err(|_| ())
}

/// `gsub("_(day|night|polartwilight)$"; "")`.
fn strip_period(symbol: &str) -> &str {
    for suffix in ["_day", "_night", "_polartwilight"] {
        if let Some(stripped) = symbol.strip_suffix(suffix) {
            return stripped;
        }
    }
    symbol
}

/// The ladder from the jq program; order is the contract (thunder first,
/// `partlycloudy` before `cloudy`, heavy/light before the generic terms).
pub fn wmo(symbol: &str) -> u8 {
    let key = strip_period(symbol);
    if key.contains("thunder") {
        95
    } else if key.contains("heavysnow") {
        75
    } else if key.contains("lightsnow") {
        71
    } else if key.contains("snow") || key.contains("sleet") {
        73
    } else if key.contains("heavyrain") {
        65
    } else if key.contains("lightrain")
        || key.contains("lightrainshowers")
        || key.contains("lightdrizzle")
    {
        61
    } else if key.contains("rain") || key.contains("drizzle") {
        63
    } else if key.contains("fog") {
        45
    } else if key.contains("partlycloudy") {
        2
    } else if key.contains("cloudy") {
        3
    } else if key.contains("fair") {
        1
    } else if key.contains("clearsky") {
        0
    } else {
        2
    }
}

struct Observation {
    date: String,
    hour: String,
    /// Raw JSON text of `air_temperature` (literal preserved).
    temp: String,
    code: u8,
}

/// jq's total ordering over JSON values: null < false < true < numbers <
/// strings < arrays < objects.
fn jq_compare(left: &serde_json::Value, right: &serde_json::Value) -> Ordering {
    fn rank(value: &serde_json::Value) -> u8 {
        match value {
            serde_json::Value::Null => 0,
            serde_json::Value::Bool(false) => 1,
            serde_json::Value::Bool(true) => 2,
            serde_json::Value::Number(_) => 3,
            serde_json::Value::String(_) => 4,
            serde_json::Value::Array(_) => 5,
            serde_json::Value::Object(_) => 6,
        }
    }
    let (left_rank, right_rank) = (rank(left), rank(right));
    if left_rank != right_rank {
        return left_rank.cmp(&right_rank);
    }
    match (left, right) {
        (serde_json::Value::Number(a), serde_json::Value::Number(b)) => a
            .as_f64()
            .partial_cmp(&b.as_f64())
            .unwrap_or(Ordering::Equal),
        (serde_json::Value::String(a), serde_json::Value::String(b)) => a.cmp(b),
        (serde_json::Value::Array(a), serde_json::Value::Array(b)) => {
            for (left, right) in a.iter().zip(b.iter()) {
                let ordering = jq_compare(left, right);
                if ordering != Ordering::Equal {
                    return ordering;
                }
            }
            a.len().cmp(&b.len())
        }
        (serde_json::Value::Object(a), serde_json::Value::Object(b)) => {
            // jq compares objects as sorted key/value lists.
            let mut left: Vec<(&String, &serde_json::Value)> = a.iter().collect();
            let mut right: Vec<(&String, &serde_json::Value)> = b.iter().collect();
            left.sort_by(|a, b| a.0.cmp(b.0));
            right.sort_by(|a, b| a.0.cmp(b.0));
            for ((left_key, left_value), (right_key, right_value)) in left.iter().zip(right.iter())
            {
                let ordering = left_key.cmp(right_key);
                if ordering != Ordering::Equal {
                    return ordering;
                }
                let ordering = jq_compare(left_value, right_value);
                if ordering != Ordering::Equal {
                    return ordering;
                }
            }
            left.len().cmp(&right.len())
        }
        _ => Ordering::Equal,
    }
}

fn parse_temp(raw: &str) -> serde_json::Value {
    serde_json::from_str(raw).unwrap_or(serde_json::Value::Null)
}

/// jq's `max`: the last value of the stable sort (ties keep the later entry).
fn max_temp(group: &[Observation]) -> String {
    let mut best: Option<(&str, serde_json::Value)> = None;
    for observation in group {
        let value = parse_temp(&observation.temp);
        match &best {
            None => best = Some((&observation.temp, value)),
            Some((_, current)) => {
                if jq_compare(&value, current) != Ordering::Less {
                    best = Some((&observation.temp, value));
                }
            }
        }
    }
    best.map(|(raw, _)| raw.to_string())
        .unwrap_or_else(|| "null".to_string())
}

/// jq's `min`: the first value of the stable sort (ties keep the earlier one).
fn min_temp(group: &[Observation]) -> String {
    let mut best: Option<(&str, serde_json::Value)> = None;
    for observation in group {
        let value = parse_temp(&observation.temp);
        match &best {
            None => best = Some((&observation.temp, value)),
            Some((_, current)) => {
                if jq_compare(&value, current) == Ordering::Less {
                    best = Some((&observation.temp, value));
                }
            }
        }
    }
    best.map(|(raw, _)| raw.to_string())
        .unwrap_or_else(|| "null".to_string())
}

fn weather_code(group: &[Observation]) -> u8 {
    if let Some(noon) = group.iter().find(|observation| observation.hour == "12") {
        return noon.code;
    }
    let middle = group.len() / 2;
    group.get(middle).map_or(2, |observation| observation.code)
}

fn entries(body: &str, forecast_days: u64) -> Result<Vec<Entry>, String> {
    let document = as_object(body).ok_or_else(|| NO_DAYS.to_string())?;

    let mut observations: Vec<Observation> = Vec::new();
    let properties = match document.get("properties") {
        None => None,
        Some(raw) if is_null(raw) => None,
        Some(raw) => Some(as_object(raw.get()).ok_or_else(|| NO_DAYS.to_string())?),
    };
    if let Some(properties) = properties {
        let series = match properties.get("timeseries") {
            None => None,
            Some(raw) if is_null(raw) => None,
            // `.[]` on an object would iterate its values in jq; treating a
            // non-array as "nothing to say" only changes a malformed answer.
            Some(raw) => Some(
                serde_json::from_str::<Vec<Box<RawValue>>>(raw.get())
                    .map_err(|_| NO_DAYS.to_string())?,
            ),
        };
        for element in series.into_iter().flatten() {
            let object = as_object(element.get()).ok_or_else(|| NO_DAYS.to_string())?;
            // `.time[0:10]` / `[11:13]`: jq slices codepoints; a missing time
            // is null and the entry is filtered out below.
            let Some(time) = string_member(&object, "time").map_err(|_| NO_DAYS.to_string())?
            else {
                continue;
            };
            let date: String = time.chars().take(10).collect();
            let hour: String = time.chars().skip(11).take(2).collect();
            let Some(temp) = lookup(
                element.get(),
                &["data", "instant", "details", "air_temperature"],
            )
            .map_err(|_| NO_DAYS.to_string())?
            else {
                continue;
            };
            let mut symbol: Option<String> = None;
            for key in ["next_1_hours", "next_6_hours", "next_12_hours"] {
                let Some(raw) = lookup(element.get(), &["data", key, "summary", "symbol_code"])
                    .map_err(|_| NO_DAYS.to_string())?
                else {
                    continue;
                };
                // jq's `//` skips false as well as null.
                if raw == "false" {
                    continue;
                }
                let text: String = serde_json::from_str(&raw).map_err(|_| NO_DAYS.to_string())?;
                symbol = Some(text);
                break;
            }
            let code = wmo(symbol.as_deref().unwrap_or("cloudy"));
            observations.push(Observation {
                date,
                hour,
                temp,
                code,
            });
        }
    }

    let mut groups: BTreeMap<String, Vec<Observation>> = BTreeMap::new();
    for observation in observations {
        groups
            .entry(observation.date.clone())
            .or_default()
            .push(observation);
    }

    let mut result: Vec<Entry> = groups
        .into_iter()
        .map(|(date, group)| Entry {
            date: Some(json::raw(&json::string(&date))),
            tmax_c: Some(json::raw(&max_temp(&group))),
            tmin_c: Some(json::raw(&min_temp(&group))),
            weather_code: Some(json::raw(&weather_code(&group).to_string())),
        })
        .collect();
    result.truncate(forecast_days as usize);
    Ok(result)
}

pub fn parse(body: &str, forecast_days: u64) -> Result<Vec<Entry>, String> {
    entries(body, forecast_days)
}

pub fn fetch(
    http: &Http,
    base: &str,
    coords: &Coords,
    forecast_days: u64,
) -> Result<Vec<Entry>, Failure> {
    let url = format!(
        "{base}/compact?lat={}&lon={}",
        coords.lat_url, coords.lon_url
    );
    let body = http
        .get(&url)
        .map_err(|error| Failure::fetch(error, "met.no request failed: "))?;
    parse(&body, forecast_days).map_err(Failure::Message)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn timeseries(entries: &[(&str, &str, &str)]) -> String {
        let items: Vec<String> = entries
            .iter()
            .map(|(time, temperature, symbol)| {
                format!(
                    r#"{{"time":"{time}","data":{{"instant":{{"details":{{"air_temperature":{temperature}}}}},"next_1_hours":{{"summary":{{"symbol_code":"{symbol}"}}}}}}}}"#
                )
            })
            .collect();
        format!(
            r#"{{"type":"Feature","properties":{{"timeseries":[{}]}}}}"#,
            items.join(",")
        )
    }

    #[test]
    fn symbol_ladder_matches_the_jq_program() {
        for (symbol, code) in [
            ("thunderstorm_day", 95),
            ("heavyrainandthunder", 95),
            ("heavysnow_day", 75),
            ("lightsnow_night", 71),
            ("snow", 73),
            ("sleet_polartwilight", 73),
            ("heavyrain_day", 65),
            ("lightrain_night", 61),
            ("lightrainshowers_day", 61),
            ("lightdrizzle", 61),
            ("rain_day", 63),
            ("rainshowers_night", 63),
            ("drizzle", 63),
            ("fog", 45),
            ("partlycloudy_day", 2),
            ("cloudy", 3),
            ("fair_day", 1),
            ("clearsky_night", 0),
            ("unknown_symbol", 2),
            ("cloudy_day_extra", 3),
        ] {
            assert_eq!(wmo(symbol), code, "{symbol}");
        }
    }

    #[test]
    fn groups_days_and_uses_noon_for_the_code() {
        let body = timeseries(&[
            ("2026-11-02T06:00:00Z", "3.5", "cloudy_day"),
            ("2026-11-02T12:00:00Z", "7.9", "partlycloudy_day"),
            ("2026-11-02T18:00:00Z", "1.0", "rain"),
            ("2026-11-03T12:00:00Z", "4.0", "snow"),
        ]);
        let days = parse(&body, 5).expect("days");
        assert_eq!(days.len(), 2);
        assert_eq!(
            days[0].to_json(),
            r#"{"date":"2026-11-02","tmax_c":7.9,"tmin_c":1.0,"weather_code":2}"#
        );
        assert_eq!(
            days[1].to_json(),
            r#"{"date":"2026-11-03","tmax_c":4.0,"tmin_c":4.0,"weather_code":73}"#
        );
    }

    #[test]
    fn no_noon_falls_back_to_the_middle_entry() {
        let body = timeseries(&[
            ("2026-11-02T03:00:00Z", "1.0", "clearsky_day"),
            ("2026-11-02T06:00:00Z", "2.0", "cloudy"),
            ("2026-11-02T09:00:00Z", "3.0", "rain"),
        ]);
        // length 3, floor(3/2) = 1 -> "cloudy" -> 3.
        assert_eq!(
            parse(&body, 5).expect("days")[0]
                .weather_code
                .as_ref()
                .expect("code")
                .get(),
            "3"
        );
    }

    #[test]
    fn literals_survive_and_forecast_days_truncates() {
        let body = timeseries(&[
            ("2026-11-01T12:00:00Z", "7.0", "fair_day"),
            ("2026-11-02T12:00:00Z", "3.50", "fair_day"),
            ("2026-11-03T12:00:00Z", "-0.0", "fair_day"),
        ]);
        let days = parse(&body, 2).expect("days");
        assert_eq!(days.len(), 2);
        assert!(days[0].to_json().contains("\"tmax_c\":7.0"));
        assert!(days[1].to_json().contains("\"tmax_c\":3.50"));
        assert_eq!(
            days[1].to_json(),
            r#"{"date":"2026-11-02","tmax_c":3.50,"tmin_c":3.50,"weather_code":1}"#
        );
    }

    #[test]
    fn entry_without_time_or_temperature_is_dropped() {
        let body = r#"{"properties":{"timeseries":[
            {"data":{"instant":{"details":{"air_temperature":5.0}}}},
            {"time":"2026-11-02T12:00:00Z","data":{"instant":{"details":{}}}},
            {"time":"2026-11-02T12:00:00Z","data":{"instant":{"details":{"air_temperature":5.0}}}}
        ]}}"#;
        let days = parse(body, 5).expect("days");
        assert_eq!(days.len(), 1);
        // No symbol_code at all takes the jq program's "cloudy" fallback.
        assert_eq!(
            days[0].to_json(),
            r#"{"date":"2026-11-02","tmax_c":5.0,"tmin_c":5.0,"weather_code":3}"#
        );
    }

    #[test]
    fn empty_or_missing_timeseries_is_an_empty_array() {
        for body in [
            r#"{"properties":{"timeseries":[]}}"#,
            r#"{"properties":{}}"#,
            r#"{}"#,
            r#"{"properties":{"timeseries":null}}"#,
        ] {
            assert!(parse(body, 5).expect("days").is_empty(), "{body}");
        }
    }

    #[test]
    fn malformed_answers_have_no_days() {
        for body in [
            "",
            "not json",
            "[]",
            r#"{"properties":5}"#,
            r#"{"properties":{"timeseries":{}}}"#,
            r#"{"properties":{"timeseries":[5]}}"#,
            r#"{"properties":{"timeseries":[{"time":5}]}}"#,
            r#"{"properties":{"timeseries":[{"time":"2026-11-02T12:00:00Z","data":5}]}}"#,
            r#"{"properties":{"timeseries":[{"time":"2026-11-02T12:00:00Z","data":{"instant":{"details":{"air_temperature":5}},"next_1_hours":{"summary":{"symbol_code":5}}}}]}}"#,
        ] {
            assert_eq!(parse(body, 5).err(), Some(NO_DAYS.to_string()), "{body}");
        }
    }

    #[test]
    fn max_and_min_ties_follow_jq() {
        let group = |values: &[&str]| -> Vec<Observation> {
            values
                .iter()
                .map(|temp| Observation {
                    date: "2026-11-02".to_string(),
                    hour: "12".to_string(),
                    temp: temp.to_string(),
                    code: 2,
                })
                .collect()
        };
        assert_eq!(max_temp(&group(&["3.0", "3.00"])), "3.00");
        assert_eq!(min_temp(&group(&["3.0", "3.00"])), "3.0");
        assert_eq!(max_temp(&group(&["1", "1.0"])), "1.0");
        assert_eq!(min_temp(&group(&["1", "1.0"])), "1");
        assert_eq!(max_temp(&group(&["-5.0", "2.5", "2.50"])), "2.50");
        assert_eq!(min_temp(&group(&["-5.0", "-5.00", "2.5"])), "-5.0");
    }

    #[test]
    fn missing_symbol_falls_back_to_cloudy() {
        let body = r#"{"properties":{"timeseries":[{"time":"2026-11-02T12:00:00Z","data":{"instant":{"details":{"air_temperature":5.0}}}}]}}"#;
        let days = parse(body, 5).expect("days");
        assert!(days[0].to_json().ends_with("\"weather_code\":3}"));
    }
}
