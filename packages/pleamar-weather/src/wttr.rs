//! wttr.in: the final fallback, one-line text format only.
//!
//! The shell deliberately used wttr's `format=` text instead of its JSON
//! stream (the JSON arrives truncated from this host) and parsed it with
//! `read -r _ temp hum wind cond _ pres _` plus awk's first numeric match. The
//! forecast in a wttr payload is MET Norway's; wttr itself only contributes
//! `current`.
//!
//! Field order in the URL is the contract:
//! `%c|%t|%h|%w|%C|%p|%P|%u` → condition, temperature, humidity, wind,
//! condition text, pressure, pressure, UV. The shell read field 1 as the
//! temperature, 2 humidity, 3 wind, 4 the condition text and 6 the pressure.

use crate::failure::Failure;
use crate::geo::Coords;
use crate::http::Http;
use crate::metno;
use crate::number;
use crate::payload::{field, Current, Entry, Payload};

pub const NO_TEMPERATURE: &str = "wttr.in response has no temperature";

const FORMAT: &str = "%c|%t|%h|%w|%C|%p|%P|%u";

/// The fields the shell extracted from wttr's one line, already in the text
/// form it passed to `jq --argjson`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct WttrCurrent {
    pub temperature: String,
    pub humidity: String,
    pub wind_ms: String,
    pub wind_direction: u16,
    pub weather_code: u16,
    pub pressure: String,
}

/// awk's `match(s, /[-+]?[0-9]+(\.[0-9]+)?/)` (leftmost match, digits after the
/// dot required). `signed` is the temperature's regex; `fraction` covers wind
/// and pressure, `[0-9]+(\.[0-9]+)?` without a sign for humidity.
fn find_number(text: &str, signed: bool, fraction: bool) -> Option<&str> {
    let bytes = text.as_bytes();
    let mut index = 0;
    while index < bytes.len() {
        let signed_start = signed
            && (bytes[index] == b'+' || bytes[index] == b'-')
            && bytes
                .get(index + 1)
                .is_some_and(|next| next.is_ascii_digit());
        let start = if signed_start || bytes[index].is_ascii_digit() {
            index
        } else {
            index += 1;
            continue;
        };
        let mut end = start;
        if signed_start {
            end += 1;
        }
        while end < bytes.len() && bytes[end].is_ascii_digit() {
            end += 1;
        }
        if fraction
            && bytes.get(end) == Some(&b'.')
            && bytes.get(end + 1).is_some_and(|next| next.is_ascii_digit())
        {
            end += 1;
            while end < bytes.len() && bytes[end].is_ascii_digit() {
                end += 1;
            }
        }
        return Some(&text[start..end]);
    }
    None
}

/// `case "$wind" in "↑"*) 0; …` — the arrow at the start of the wind field.
fn wind_direction(wind: &str) -> u16 {
    match wind.chars().next() {
        Some('↑') => 0,
        Some('↗') => 45,
        Some('→') => 90,
        Some('↘') => 135,
        Some('↓') => 180,
        Some('↙') => 225,
        Some('←') => 270,
        Some('↖') => 315,
        _ => 0,
    }
}

/// The shell's `case "$cond"` ladder, in order and case-sensitive.
fn weather_code(condition: &str) -> u16 {
    if condition.contains("Thunder") {
        95
    } else if condition.contains("Snow")
        || condition.contains("Sleet")
        || condition.contains("Blizzard")
    {
        71
    } else if condition.contains("Rain")
        || condition.contains("Drizzle")
        || condition.contains("Shower")
    {
        61
    } else if condition.contains("Fog") || condition.contains("Mist") || condition.contains("Haze")
    {
        45
    } else if condition.contains("Overcast") {
        3
    } else if condition.contains("Cloud") {
        2
    } else if condition.contains("Sun") || condition.contains("Clear") {
        0
    } else {
        2
    }
}

/// Parse wttr's one-line answer. Only the first line is used (`read` stopped
/// at the newline), and every missing field is empty.
pub fn parse_text(body: &str) -> Option<WttrCurrent> {
    let line = body.split('\n').next().unwrap_or("");
    let fields: Vec<&str> = line.split('|').collect();
    let field_at = |index: usize| fields.get(index).copied().unwrap_or("");
    let temperature = find_number(field_at(1), true, true)?;
    let humidity = find_number(field_at(2), false, false).unwrap_or("0");
    let wind_text = field_at(3);
    let wind_ms = match find_number(wind_text, false, true) {
        Some(matched) => {
            let speed: f64 = matched.parse().unwrap_or(0.0);
            // awk: `printf "%.1f", <match> / 3.6`.
            format!("{:.1}", speed / 3.6)
        }
        None => "0".to_string(),
    };
    let pressure = find_number(field_at(6), false, true).unwrap_or("0");
    Some(WttrCurrent {
        temperature: temperature.to_string(),
        humidity: humidity.to_string(),
        wind_ms,
        wind_direction: wind_direction(wind_text),
        weather_code: weather_code(field_at(4)),
        pressure: pressure.to_string(),
    })
}

pub fn build(
    current: &WttrCurrent,
    city: &str,
    coords: &Coords,
    fetched_at: i64,
    daily: Vec<Entry>,
) -> Payload {
    Payload::new(
        city,
        coords,
        "wttr.in",
        fetched_at,
        Current {
            temp_c: field(&number::json_literal(&current.temperature)),
            weather_code: field(&current.weather_code.to_string()),
            wind_ms: field(&number::json_literal(&current.wind_ms)),
            wind_dir_deg: field(&current.wind_direction.to_string()),
            // wttr's one-line format has no day/night flag.
            is_day: None,
            humidity_pct: field(&number::json_literal(&current.humidity)),
            pressure_hpa: field(&number::json_literal(&current.pressure)),
        },
        daily,
    )
}

pub fn fetch(
    http: &Http,
    wttr_base: &str,
    metno_base: &str,
    coords: &Coords,
    city: &str,
    fetched_at: i64,
    forecast_days: u64,
) -> Result<Payload, Failure> {
    let url = format!(
        "{wttr_base}/{},{}?format={FORMAT}",
        coords.lat_url, coords.lon_url
    );
    let body = http
        .get(&url)
        .map_err(|error| Failure::fetch(error, "wttr.in request failed: "))?;
    let current = parse_text(&body).ok_or_else(|| Failure::Message(NO_TEMPERATURE.to_string()))?;
    // `daily_from_metno || true`: a failed forecast leaves `daily` empty and
    // does not fail this provider.
    let daily = match metno::fetch(http, metno_base, coords, forecast_days) {
        Ok(daily) => daily,
        Err(Failure::Interrupted) => return Err(Failure::Interrupted),
        Err(Failure::Message(_)) => Vec::new(),
    };
    Ok(build(&current, city, coords, fetched_at, daily))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn coords() -> Coords {
        Coords::from_cli("59.9", "30.3")
    }

    #[test]
    fn reads_the_fields_the_shell_read() {
        let current = parse_text("Partly cloudy|+3°C|81%|↑8km/h|Partly cloudy|1009|29.80|0")
            .expect("current");
        assert_eq!(current.temperature, "+3");
        assert_eq!(current.humidity, "81");
        // 8 / 3.6 = 2.22… -> "%.1f"
        assert_eq!(current.wind_ms, "2.2");
        assert_eq!(current.wind_direction, 0);
        assert_eq!(current.weather_code, 2);
        // Field 6 (%P), the shell's `pres`.
        assert_eq!(current.pressure, "29.80");
    }

    #[test]
    fn only_the_first_line_counts() {
        let current =
            parse_text("Sunny|+21°C|40%|→4km/h|Sunny|1000|29.5|1\nsecond line").expect("current");
        assert_eq!(current.temperature, "+21");
        assert_eq!(current.wind_direction, 90);
        assert_eq!(current.weather_code, 0);
    }

    #[test]
    fn wind_arrows_map_to_degrees() {
        for (arrow, degrees) in [
            ("↑", 0),
            ("↗", 45),
            ("→", 90),
            ("↘", 135),
            ("↓", 180),
            ("↙", 225),
            ("←", 270),
            ("↖", 315),
            ("?", 0),
        ] {
            let line = format!("Clear|5°C|50%|{arrow}7km/h|Clear|1000|29|0");
            assert_eq!(
                parse_text(&line).expect("current").wind_direction,
                degrees,
                "{arrow}"
            );
        }
    }

    #[test]
    fn condition_ladder_matches_the_shell_case() {
        for (condition, code) in [
            ("Thunderstorm", 95),
            ("Sleet", 71),
            ("Blizzard", 71),
            ("Drizzle", 61),
            ("Shower", 61),
            ("Rain", 61),
            ("Fog", 45),
            ("Mist", 45),
            ("Haze", 45),
            ("Overcast", 3),
            ("Cloudy", 2),
            ("Partly cloudy", 2),
            ("Sunny", 0),
            ("Clear", 0),
            ("", 2),
            // Case-sensitive, like the shell's globs.
            ("rain", 2),
        ] {
            assert_eq!(weather_code(condition), code, "{condition}");
        }
    }

    #[test]
    fn missing_temperature_is_an_error() {
        for line in ["", "Cloudy", "Cloudy|n/a|50%|↑1km/h|Cloudy|1|1|0"] {
            assert!(parse_text(line).is_none(), "{line}");
        }
    }

    #[test]
    fn missing_numeric_fields_default_to_zero_like_awk() {
        let current = parse_text("Cloudy|5°C|||Cloudy|||").expect("current");
        assert_eq!(current.humidity, "0");
        assert_eq!(current.wind_ms, "0");
        assert_eq!(current.pressure, "0");
        assert_eq!(current.temperature, "5");
    }

    #[test]
    fn payload_uses_the_literals_and_nulls_is_day() {
        let current = parse_text("Partly cloudy|+3.50°C|81%|↖12.6km/h|Partly cloudy|1009|29.80|0")
            .expect("current");
        let payload = build(&current, "Oslo", &coords(), 42, Vec::new());
        assert_eq!(
            payload.to_json(false, 0),
            r#"{"city":"Oslo","latitude":59.9,"longitude":30.3,"provider":"wttr.in","fetched_at":42,"age_s":0,"cached":false,"current":{"temp_c":3.50,"weather_code":2,"wind_ms":3.5,"wind_dir_deg":315,"is_day":null,"humidity_pct":81,"pressure_hpa":29.80},"daily":[]}"#
        );
    }
}
