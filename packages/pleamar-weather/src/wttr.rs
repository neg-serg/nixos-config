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
