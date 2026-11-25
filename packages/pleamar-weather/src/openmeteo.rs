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
