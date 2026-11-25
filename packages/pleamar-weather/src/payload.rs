//! The payload model and its JSON rendering.
//!
//! The shell never built a typed value: `jq` assembled a compact object from
//! the provider document and kept every number literal as written (`3.40`
//! stayed `3.40`, `7.0` stayed `7.0`). `serde_json::value::RawValue` gives the
//! port the same fidelity: a field holds the exact JSON text that came in, and
//! the renderer concatenates those texts in the frozen key order. Values that
//! the shell computed (`fetched_at`, `age_s`, `cached`, MET Norway's WMO codes)
//! are emitted from their Rust values.
//!
//! The cache reader deserialises the same structs, so serving a cached payload
//! and serving a fresh one take the same code path.

use serde::Deserialize;
use serde_json::value::RawValue;

use crate::json;

/// `data` of a weather sample: `city`, `latitude`, `longitude`, `provider`,
/// `fetched_at`, `age_s`, `cached`, `current`, `daily`.
#[derive(Clone, Debug, Deserialize)]
pub struct Payload {
    #[serde(default)]
    pub city: Option<Box<RawValue>>,
    #[serde(default)]
    pub latitude: Option<Box<RawValue>>,
    #[serde(default)]
    pub longitude: Option<Box<RawValue>>,
    #[serde(default)]
    pub provider: Option<Box<RawValue>>,
    /// The shell read this as an integer (`--argjson now`, arithmetic on it),
    /// so a float or a string here is not a payload this port can serve.
    pub fetched_at: i64,
    pub current: Current,
    pub daily: Vec<Entry>,
}

#[derive(Clone, Debug, Deserialize)]
pub struct Current {
    #[serde(default)]
    pub temp_c: Option<Box<RawValue>>,
    #[serde(default)]
    pub weather_code: Option<Box<RawValue>>,
    #[serde(default)]
    pub wind_ms: Option<Box<RawValue>>,
    #[serde(default)]
    pub wind_dir_deg: Option<Box<RawValue>>,
    #[serde(default)]
    pub is_day: Option<Box<RawValue>>,
    #[serde(default)]
    pub humidity_pct: Option<Box<RawValue>>,
    #[serde(default)]
    pub pressure_hpa: Option<Box<RawValue>>,
}

#[derive(Clone, Debug, Deserialize)]
pub struct Entry {
    #[serde(default)]
    pub date: Option<Box<RawValue>>,
    #[serde(default)]
    pub tmax_c: Option<Box<RawValue>>,
    #[serde(default)]
    pub tmin_c: Option<Box<RawValue>>,
    #[serde(default)]
    pub weather_code: Option<Box<RawValue>>,
}

/// A provider value as a raw JSON fragment; the text `null` means "absent"
/// (jq wrote null for a missing provider field, so it is the same output).
pub fn field(fragment: &str) -> Option<Box<RawValue>> {
    if fragment == "null" {
        None
    } else {
        Some(json::raw(fragment))
    }
}

impl Payload {
    pub fn new(
        city: &str,
        coords: &crate::geo::Coords,
        provider: &str,
        fetched_at: i64,
        current: Current,
        daily: Vec<Entry>,
    ) -> Self {
        Self {
            city: Some(json::raw(&json::string(city))),
            latitude: Some(json::raw(&coords.lat_json)),
            longitude: Some(json::raw(&coords.lon_json)),
            provider: Some(json::raw(&json::string(provider))),
            fetched_at,
            current,
            daily,
        }
    }

    /// The compact `data` object, in the order the shell's jq program wrote.
    pub fn to_json(&self, cached: bool, age_s: i64) -> String {
        let daily: Vec<String> = self.daily.iter().map(Entry::to_json).collect();
        format!(
            "{{\"city\":{},\"latitude\":{},\"longitude\":{},\"provider\":{},\"fetched_at\":{},\"age_s\":{},\"cached\":{},\"current\":{},\"daily\":[{}]}}",
            json::raw_or_null(&self.city),
            json::raw_or_null(&self.latitude),
            json::raw_or_null(&self.longitude),
            json::raw_or_null(&self.provider),
            self.fetched_at,
            age_s,
            if cached { "true" } else { "false" },
            self.current.to_json(),
            daily.join(","),
        )
    }
}

impl Current {
    pub fn to_json(&self) -> String {
        format!(
            "{{\"temp_c\":{},\"weather_code\":{},\"wind_ms\":{},\"wind_dir_deg\":{},\"is_day\":{},\"humidity_pct\":{},\"pressure_hpa\":{}}}",
            json::raw_or_null(&self.temp_c),
            json::raw_or_null(&self.weather_code),
            json::raw_or_null(&self.wind_ms),
            json::raw_or_null(&self.wind_dir_deg),
            json::raw_or_null(&self.is_day),
            json::raw_or_null(&self.humidity_pct),
            json::raw_or_null(&self.pressure_hpa),
        )
    }
}

impl Entry {
    pub fn to_json(&self) -> String {
        format!(
            "{{\"date\":{},\"tmax_c\":{},\"tmin_c\":{},\"weather_code\":{}}}",
            json::raw_or_null(&self.date),
            json::raw_or_null(&self.tmax_c),
            json::raw_or_null(&self.tmin_c),
            json::raw_or_null(&self.weather_code),
        )
    }
}
