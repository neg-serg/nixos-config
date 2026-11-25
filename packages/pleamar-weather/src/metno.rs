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
