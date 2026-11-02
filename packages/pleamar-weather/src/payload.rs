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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::geo::Coords;

    fn payload() -> Payload {
        Payload::new(
            "Saint Petersburg",
            &Coords::from_cli("59.93863", "30.31413"),
            "open-meteo",
            1_793_641_408,
            Current {
                temp_c: field("6.3"),
                weather_code: field("3"),
                wind_ms: field("3.40"),
                wind_dir_deg: field("231"),
                is_day: field("0"),
                humidity_pct: field("81"),
                pressure_hpa: field("1027.4"),
            },
            vec![Entry {
                date: field("\"2026-11-02\""),
                tmax_c: field("7.9"),
                tmin_c: field("5.6"),
                weather_code: field("3"),
            }],
        )
    }

    #[test]
    fn fresh_payload_matches_the_shell_bytes() {
        assert_eq!(
            payload().to_json(false, 0),
            concat!(
                r#"{"city":"Saint Petersburg","latitude":59.93863,"longitude":30.31413,"#,
                r#""provider":"open-meteo","fetched_at":1793641408,"age_s":0,"cached":false,"#,
                r#""current":{"temp_c":6.3,"weather_code":3,"wind_ms":3.40,"wind_dir_deg":231,"#,
                r#""is_day":0,"humidity_pct":81,"pressure_hpa":1027.4},"#,
                r#""daily":[{"date":"2026-11-02","tmax_c":7.9,"tmin_c":5.6,"weather_code":3}]}"#
            )
        );
    }

    #[test]
    fn cached_payload_recomputes_age_and_flips_cached() {
        let cached = payload().to_json(true, 42);
        assert!(cached.contains("\"fetched_at\":1793641408,\"age_s\":42,\"cached\":true,"));
    }

    #[test]
    fn a_cached_document_round_trips_through_the_model() {
        let text = payload().to_json(false, 0);
        let parsed: Payload = serde_json::from_str(&text).expect("payload parses");
        assert_eq!(parsed.to_json(true, 7), payload().to_json(true, 7));
        // Literal preservation survives the round trip.
        assert!(parsed.to_json(false, 0).contains("\"wind_ms\":3.40"));
    }

    #[test]
    fn missing_fields_render_as_null() {
        let mut value = payload();
        value.current = Current {
            temp_c: None,
            weather_code: None,
            wind_ms: None,
            wind_dir_deg: None,
            is_day: None,
            humidity_pct: None,
            pressure_hpa: None,
        };
        assert!(value
            .to_json(false, 0)
            .contains("\"current\":{\"temp_c\":null,\"weather_code\":null"));
    }

    #[test]
    fn a_wttr_payload_has_null_is_day_and_empty_daily() {
        let value = Payload::new(
            "",
            &Coords::from_cli("59.9", "30.3"),
            "wttr.in",
            10,
            Current {
                temp_c: field("3"),
                weather_code: field("2"),
                wind_ms: field("2.2"),
                wind_dir_deg: field("90"),
                is_day: None,
                humidity_pct: field("64"),
                pressure_hpa: field("1013"),
            },
            Vec::new(),
        );
        let text = value.to_json(false, 0);
        assert!(text.contains("\"is_day\":null"));
        assert!(text.ends_with("\"daily\":[]}"));
    }
}
