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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encode_uri_matches_jq() {
        assert_eq!(encode_uri("Saint Petersburg"), "Saint%20Petersburg");
        assert_eq!(encode_uri("a/b?c=d e~f"), "a%2Fb%3Fc%3Dd%20e~f");
        assert_eq!(encode_uri("Zürich"), "Z%C3%BCrich");
        assert_eq!(encode_uri("A-Z.a_z~0"), "A-Z.a_z~0");
    }

    #[test]
    fn geocode_keeps_the_provider_literals() {
        let body = r#"{"results":[{"latitude":59.938630,"longitude":30.31413,"name":"Saint Petersburg"}]}"#;
        let coords = parse_geocode(body).expect("coords");
        assert_eq!(coords.lat_url, "59.938630");
        assert_eq!(coords.lat_json, "59.938630");
        assert_eq!(coords.lon_url, "30.31413");
    }

    #[test]
    fn geocode_accepts_a_numeric_string_like_jq_r() {
        let body = r#"{"results":[{"latitude":"59.9","longitude":"+30.31"}]}"#;
        let coords = parse_geocode(body).expect("coords");
        assert_eq!(coords.lat_url, "59.9");
        assert_eq!(coords.lon_url, "+30.31");
        assert_eq!(coords.lon_json, "30.31");
    }

    #[test]
    fn missing_or_malformed_results_are_not_found() {
        for body in [
            "",
            "not json",
            "[]",
            "{}",
            r#"{"results":[]}"#,
            r#"{"results":[{}]}"#,
            r#"{"results":[{"latitude":null,"longitude":30}]}"#,
            r#"{"results":[{"latitude":59.9}]}"#,
            r#"{"results":{"0":{"latitude":1,"longitude":2}}}"#,
            r#"{"results":[{"latitude":"north","longitude":30}]}"#,
            r#"{"results":[7]}"#,
        ] {
            assert!(parse_geocode(body).is_none(), "should not parse: {body}");
        }
    }

    #[test]
    fn cli_coords_keep_the_url_text_and_normalise_the_literal() {
        let coords = Coords::from_cli("+59.90", "-010.70");
        assert_eq!(coords.lat_url, "+59.90");
        assert_eq!(coords.lat_json, "59.90");
        assert_eq!(coords.lon_url, "-010.70");
        assert_eq!(coords.lon_json, "-10.70");
    }
}
