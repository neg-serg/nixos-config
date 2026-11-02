//! Open-Meteo: the primary provider.
//!
//! Request, in the shell's exact order:
//!
//! ```text
//! $API_BASE/forecast?latitude=$LAT&longitude=$LON
//!   &current=temperature_2m,weather_code,wind_speed_10m,wind_direction_10m,
//!            is_day,relative_humidity_2m,surface_pressure
//!   &daily=temperature_2m_max,temperature_2m_min,weathercode
//!   &wind_speed_unit=ms&timezone=auto&forecast_days=$FORECAST_DAYS
//! ```
//!
//! The shell first checked `.current.temperature_2m // empty` (so a body that
//! does not parse is `no current weather`, not `could not be normalized`) and
//! only then ran the normalisation program, which copies the seven `current`
//! fields and zips the three `daily` arrays over `.daily.time`. Number
//! literals are preserved (`RawValue`), missing fields become `null`.

use std::collections::BTreeMap;

use serde_json::value::RawValue;

use crate::failure::Failure;
use crate::geo::Coords;
use crate::http::Http;
use crate::json;
use crate::payload::{field, Current, Entry, Payload};

pub const NO_CURRENT: &str = "open-meteo response has no current weather";
pub const NO_NORMALIZE: &str = "open-meteo response could not be normalized";

type JsonObject = BTreeMap<String, Box<RawValue>>;

fn as_object(text: &str) -> Option<JsonObject> {
    serde_json::from_str(text).ok()
}

fn value_of(object: &JsonObject, key: &str) -> String {
    object
        .get(key)
        .map(|raw| raw.get().to_string())
        .unwrap_or_else(|| "null".to_string())
}

pub fn parse(body: &str, city: &str, coords: &Coords, fetched_at: i64) -> Result<Payload, String> {
    // `.current.temperature_2m // empty`: an unparsable document, a non-object
    // `current`, and a null/false temperature all fail the jq expression that
    // the shell checked first.
    let document = as_object(body).ok_or_else(|| NO_CURRENT.to_string())?;
    let current_raw = document
        .get("current")
        .ok_or_else(|| NO_CURRENT.to_string())?;
    let current_object = as_object(current_raw.get()).ok_or_else(|| NO_CURRENT.to_string())?;
    let temperature = value_of(&current_object, "temperature_2m");
    if temperature == "null" || temperature == "false" {
        return Err(NO_CURRENT.to_string());
    }

    let current = Current {
        temp_c: field(&temperature),
        weather_code: field(&value_of(&current_object, "weather_code")),
        wind_ms: field(&value_of(&current_object, "wind_speed_10m")),
        wind_dir_deg: field(&value_of(&current_object, "wind_direction_10m")),
        is_day: field(&value_of(&current_object, "is_day")),
        humidity_pct: field(&value_of(&current_object, "relative_humidity_2m")),
        pressure_hpa: field(&value_of(&current_object, "surface_pressure")),
    };

    let daily = daily(&document)?;
    Ok(Payload::new(
        city,
        coords,
        "open-meteo",
        fetched_at,
        current,
        daily,
    ))
}

/// `[ (.daily.time // []) as $t | range(0; ($t | length)) as $i | {…} ]`.
fn daily(document: &JsonObject) -> Result<Vec<Entry>, String> {
    let Some(daily_raw) = document.get("daily") else {
        return Ok(Vec::new());
    };
    if daily_raw.get() == "null" {
        return Ok(Vec::new());
    }
    let daily_object = as_object(daily_raw.get()).ok_or_else(|| NO_NORMALIZE.to_string())?;
    let Some(time_raw) = daily_object.get("time") else {
        return Ok(Vec::new());
    };
    if time_raw.get() == "null" {
        return Ok(Vec::new());
    }
    let times: Vec<Box<RawValue>> =
        serde_json::from_str(time_raw.get()).map_err(|_| NO_NORMALIZE.to_string())?;

    let mut entries = Vec::with_capacity(times.len());
    for index in 0..times.len() {
        entries.push(Entry {
            // `$t[$i]` is the value as it came in (the card expects a string).
            date: Some(json::raw(times[index].get())),
            tmax_c: series(&daily_object, "temperature_2m_max", index)?,
            tmin_c: series(&daily_object, "temperature_2m_min", index)?,
            weather_code: series(&daily_object, "weathercode", index)?,
        });
    }
    Ok(entries)
}

/// `.daily.<key>[$i]`: an array yields its element (or null past the end), a
/// null/missing key yields null, and anything else makes jq fail the whole
/// program (`could not be normalized`).
fn series(daily: &JsonObject, key: &str, index: usize) -> Result<Option<Box<RawValue>>, String> {
    let Some(raw) = daily.get(key) else {
        return Ok(None);
    };
    if raw.get() == "null" {
        return Ok(None);
    }
    let values: Vec<Box<RawValue>> =
        serde_json::from_str(raw.get()).map_err(|_| NO_NORMALIZE.to_string())?;
    Ok(values.get(index).map(|value| json::raw(value.get())))
}

pub fn fetch(
    http: &Http,
    api_base: &str,
    coords: &Coords,
    forecast_days: u64,
    city: &str,
    fetched_at: i64,
) -> Result<Payload, Failure> {
    let url = format!(
        "{api_base}/forecast?latitude={}&longitude={}&current=temperature_2m,weather_code,wind_speed_10m,wind_direction_10m,is_day,relative_humidity_2m,surface_pressure&daily=temperature_2m_max,temperature_2m_min,weathercode&wind_speed_unit=ms&timezone=auto&forecast_days={forecast_days}",
        coords.lat_url, coords.lon_url
    );
    let body = http
        .get(&url)
        .map_err(|error| Failure::fetch(error, "open-meteo request failed: "))?;
    parse(&body, city, coords, fetched_at).map_err(Failure::Message)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn coords() -> Coords {
        Coords::from_cli("59.9", "30.3")
    }

    fn body() -> String {
        r#"{"latitude":59.9,"longitude":30.3,"current_units":{"temperature_2m":"°C"},
            "current":{"time":"2026-11-02T12:00","temperature_2m":6.3,"weather_code":3,
                       "wind_speed_10m":3.40,"wind_direction_10m":231,"is_day":0,
                       "relative_humidity_2m":81,"surface_pressure":1027.4},
            "daily":{"time":["2026-11-02","2026-11-03"],
                     "temperature_2m_max":[7.9,7.0],"temperature_2m_min":[5.6,4.0],
                     "weathercode":[3,53]}}"#
            .to_string()
    }

    #[test]
    fn payload_keeps_the_provider_literals() {
        let payload =
            parse(&body(), "Saint Petersburg", &coords(), 1_793_641_408).expect("payload");
        assert_eq!(
            payload.to_json(false, 0),
            concat!(
                r#"{"city":"Saint Petersburg","latitude":59.9,"longitude":30.3,"#,
                r#""provider":"open-meteo","fetched_at":1793641408,"age_s":0,"cached":false,"#,
                r#""current":{"temp_c":6.3,"weather_code":3,"wind_ms":3.40,"wind_dir_deg":231,"#,
                r#""is_day":0,"humidity_pct":81,"pressure_hpa":1027.4},"#,
                r#""daily":[{"date":"2026-11-02","tmax_c":7.9,"tmin_c":5.6,"weather_code":3},"#,
                r#"{"date":"2026-11-03","tmax_c":7.0,"tmin_c":4.0,"weather_code":53}]}"#,
            )
        );
    }

    #[test]
    fn a_body_without_current_is_no_current_weather() {
        for body in [
            "",
            "not json",
            "[]",
            "5",
            r#"{}"#,
            r#"{"current":null}"#,
            r#"{"current":[]}"#,
            r#"{"current":{"temperature_2m":null}}"#,
            r#"{"current":{"temperature_2m":false}}"#,
            r#"{"current":{}}"#,
        ] {
            assert_eq!(
                parse(body, "x", &coords(), 0).err(),
                Some(NO_CURRENT.to_string()),
                "{body}"
            );
        }
    }

    #[test]
    fn a_numeric_string_temperature_is_copied_like_jq() {
        let body = r#"{"current":{"temperature_2m":"5"},"daily":null}"#;
        let payload = parse(body, "x", &coords(), 1).expect("payload");
        assert!(payload.to_json(false, 0).contains("\"temp_c\":\"5\""));
    }

    #[test]
    fn missing_daily_is_an_empty_array() {
        for body in [
            r#"{"current":{"temperature_2m":5}}"#,
            r#"{"current":{"temperature_2m":5},"daily":null}"#,
            r#"{"current":{"temperature_2m":5},"daily":{}}"#,
            r#"{"current":{"temperature_2m":5},"daily":{"time":null}}"#,
            r#"{"current":{"temperature_2m":5},"daily":{"time":[]}}"#,
        ] {
            let payload = parse(body, "x", &coords(), 1).expect("payload");
            assert!(
                payload.to_json(false, 0).ends_with("\"daily\":[]}"),
                "{body}"
            );
        }
    }

    #[test]
    fn short_daily_arrays_pad_with_null() {
        let body = r#"{"current":{"temperature_2m":5},"daily":{"time":["a","b"],"temperature_2m_max":[1.5]}}"#;
        let payload = parse(body, "x", &coords(), 1).expect("payload");
        assert!(payload
            .to_json(false, 0)
            .contains(r#"{"date":"a","tmax_c":1.5,"tmin_c":null,"weather_code":null}"#));
        assert!(payload
            .to_json(false, 0)
            .contains(r#"{"date":"b","tmax_c":null,"tmin_c":null,"weather_code":null}"#));
    }

    #[test]
    fn a_malformed_daily_shape_could_not_be_normalized() {
        for body in [
            r#"{"current":{"temperature_2m":5},"daily":5}"#,
            r#"{"current":{"temperature_2m":5},"daily":"x"}"#,
            r#"{"current":{"temperature_2m":5},"daily":{"time":"ab"}}"#,
            r#"{"current":{"temperature_2m":5},"daily":{"time":5}}"#,
            r#"{"current":{"temperature_2m":5},"daily":{"time":{"a":1}}}"#,
            r#"{"current":{"temperature_2m":5},"daily":{"time":["a"],"temperature_2m_max":"x"}}"#,
            r#"{"current":{"temperature_2m":5},"daily":{"time":["a"],"temperature_2m_min":5}}"#,
            r#"{"current":{"temperature_2m":5},"daily":{"time":["a"],"weathercode":false}}"#,
        ] {
            assert_eq!(
                parse(body, "x", &coords(), 0).err(),
                Some(NO_NORMALIZE.to_string()),
                "{body}"
            );
        }
    }

    #[test]
    fn daily_values_that_are_not_numbers_are_copied_verbatim() {
        let body = r#"{"current":{"temperature_2m":5},"daily":{"time":["a"],"temperature_2m_max":["hot"],"temperature_2m_min":[null],"weathercode":[true]}}"#;
        let payload = parse(body, "x", &coords(), 1).expect("payload");
        assert!(payload
            .to_json(false, 0)
            .contains(r#"{"date":"a","tmax_c":"hot","tmin_c":null,"weather_code":true}"#));
    }
}
