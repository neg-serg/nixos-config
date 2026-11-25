//! Geocoding: `CITY` → coordinates through the Open-Meteo geocoding API.
//!
//! The shell's URL was
//! `$GEO_BASE/search?name=<jq @uri>&count=1&language=en&format=json` and it
//! read `.results[0].latitude` / `.longitude` with `jq -r`. jq 1.8 preserves
//! the number literal, so a value the API wrote as `59.938630` reached the
//! forecast URL and the payload unchanged; `RawValue` keeps that here.
//!
//! Everything that is not a readable numeric pair is `city not found` — the
//! same `jq -r … // empty` outcome, because the shell swallowed jq's error and
//! compared the empty string.

use std::collections::BTreeMap;

use serde_json::value::RawValue;

use crate::failure::Failure;
use crate::http::Http;
use crate::number;

/// Resolved coordinates in the two spellings the shell used: the text that
/// went into the request URLs (`$LAT`/`$LON`) and the number literal jq wrote
/// into the payload (`--argjson lat "$LAT"`).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Coords {
    pub lat_url: String,
    pub lon_url: String,
    pub lat_json: String,
    pub lon_json: String,
}

impl Coords {
    pub fn from_cli(latitude: &str, longitude: &str) -> Self {
        Self {
            lat_url: latitude.to_string(),
            lon_url: longitude.to_string(),
            lat_json: number::json_literal(latitude),
            lon_json: number::json_literal(longitude),
        }
    }

    fn from_provider(latitude: &str, longitude: &str) -> Self {
        Self {
            lat_url: latitude.to_string(),
            lon_url: longitude.to_string(),
            lat_json: number::json_literal(latitude),
            lon_json: number::json_literal(longitude),
        }
    }

    /// Reuse coordinates from the cache: `jq -r` rendering in, `--argjson`
    /// literal out.
    pub fn from_cache(latitude: &str, longitude: &str) -> Self {
        Self::from_provider(latitude, longitude)
    }
}

/// jq's `@uri`: everything outside the RFC 3986 unreserved set is
/// percent-encoded byte by byte, spaces included (`%20`, never `+`).
pub fn encode_uri(value: &str) -> String {
    const HEX: &[u8; 16] = b"0123456789ABCDEF";
    let mut encoded = String::with_capacity(value.len());
    for byte in value.bytes() {
        let unreserved = byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'.' | b'_' | b'~');
        if unreserved {
            encoded.push(byte as char);
        } else {
            encoded.push('%');
            encoded.push(HEX[(byte >> 4) as usize] as char);
            encoded.push(HEX[(byte & 0x0f) as usize] as char);
        }
    }
    encoded
}

type JsonObject = BTreeMap<String, Box<RawValue>>;

fn as_object(text: &str) -> Option<JsonObject> {
    serde_json::from_str(text).ok()
}

/// `.results[0].latitude` / `.longitude`, or `None` (the shell's `city not
/// found`).
pub fn parse_geocode(body: &str) -> Option<Coords> {
    let document = as_object(body)?;
    let results = document.get("results")?;
    let results: Vec<JsonObject> = serde_json::from_str(results.get()).ok()?;
    let first = results.first()?;
    let latitude = coordinate(first.get("latitude")?)?;
    let longitude = coordinate(first.get("longitude")?)?;
    Some(Coords::from_provider(&latitude, &longitude))
}

/// `jq -r` of a JSON value: a number prints as its literal, a string prints
/// unquoted. Only a numeric pair is usable; anything else made the shell's
/// later `--argjson` fail, so the port refuses it here.
fn coordinate(raw: &RawValue) -> Option<String> {
    let text = raw.get();
    match serde_json::from_str::<serde_json::Value>(text).ok()? {
        serde_json::Value::Number(_) => {
            if number::is_json_number(text) {
                Some(text.to_string())
            } else {
                None
            }
        }
        serde_json::Value::String(content) => {
            if number::is_number(&content) {
                Some(content)
            } else {
                None
            }
        }
        _ => None,
    }
}

pub fn geocode(http: &Http, base: &str, city: &str) -> Result<Coords, Failure> {
    let url = format!(
        "{base}/search?name={}&count=1&language=en&format=json",
        encode_uri(city)
    );
    let body = http
        .get(&url)
        .map_err(|error| Failure::fetch(error, "geocoding failed: "))?;
    parse_geocode(&body).ok_or_else(|| Failure::Message(format!("city not found: {city}")))
}
