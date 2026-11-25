//! Public holidays from date.nager.at.
//!
//! `holidays_json` in the shell:
//!
//! - no `--country` means no holidays, no request and no cache;
//! - `holidays-YYYY-CC.json` caches the provider's raw answer for 24 h
//!   (mtime), written with `jq -c` (compact, trailing newline) and an atomic
//!   rename;
//! - the month's entries are `{date, name, name_en}` from the provider's
//!   `date`, `localName` and `name`, the month filtered with
//!   `(.date // "") | startswith($month)`;
//! - a failed request is `holidays request failed: <curl's last stderr line>`
//!   and does not fail the events.

use std::path::{Path, PathBuf};

use serde_json::{Map, Value};

use crate::cache;
use crate::date::Month;
use crate::failure::Failure;
use crate::http::Http;

/// Holidays are static per year: the shell kept the raw answer for a day.
const TTL_SECS: i64 = 86_400;

pub struct Resolved {
    pub holidays: Value,
    pub error: Option<String>,
}

pub fn resolve(
    country: &str,
    month: &Month,
    cache_dir: &Path,
    base: &str,
    http: &Http,
    now: i64,
) -> Result<Resolved, Failure> {
    if country.is_empty() {
        return Ok(empty());
    }
    let path = cache_file(cache_dir, month, country);

    if cache::fresh(&path, now, TTL_SECS) {
        if let Some(text) = cache::read_text(&path) {
            if let Ok(document) = serde_json::from_str::<Value>(&text) {
                if let Some(holidays) = filter(&document, &month.name()) {
                    return Ok(Resolved {
                        holidays,
                        error: None,
                    });
                }
            }
            // A fresh file that is not a usable holiday list is refetched
            // rather than served: the shell would have failed its jq filter
            // and left the worker without a sample.
        }
    }

    let url = format!("{base}/PublicHolidays/{}/{}", month.year_text(), country);
    // A failed request is an error field, not a failed sample: the shell set
    // HOLIDAY_ERROR and kept the events.
    let body = match http.get(&url) {
        Ok(body) => body,
        Err(crate::http::FetchError::Interrupted) => return Err(Failure::Interrupted),
        Err(crate::http::FetchError::Message(text)) => {
            return Ok(Resolved {
                holidays: Value::Array(Vec::new()),
                error: Some(format!("holidays request failed: {text}")),
            });
        }
    };

    let document = match serde_json::from_str::<Value>(&body) {
        Ok(document) => document,
        Err(_) => {
            return Ok(Resolved {
                holidays: Value::Array(Vec::new()),
                error: Some("holidays request failed: invalid JSON answer".to_string()),
            });
        }
    };
    let Some(holidays) = filter(&document, &month.name()) else {
        return Ok(Resolved {
            holidays: Value::Array(Vec::new()),
            error: Some("holidays request failed: answer is not a list".to_string()),
        });
    };

    // The shell cached the provider document before filtering; an unusable
    // answer was never cached.
    let compact = serde_json::to_string(&document).unwrap_or_default();
    let cache_text = format!("{compact}\n");
    if let Err(error) = cache::write_atomic(&path, cache_text.as_bytes(), "holidays") {
        // stderr is for humans and never part of the protocol.
        eprintln!("calendar: holidays cache write failed: {error}");
    }

    Ok(Resolved {
        holidays,
        error: None,
    })
}

pub fn cache_file(cache_dir: &Path, month: &Month, country: &str) -> PathBuf {
    cache_dir.join(format!("holidays-{}-{}.json", month.year_text(), country))
}

/// `[ .[] | select((.date // "") | startswith($m)) |
///    {date: .date, name: .localName, name_en: .name} ]`.
///
/// `None` means the document is not an array (jq's `.[]` failed) — the caller
/// treats it as an unusable answer. Entries whose `date` is not a string are
/// skipped instead of aborting the worker; a real nager document always has
/// string dates.
fn filter(document: &Value, month: &str) -> Option<Value> {
    let items = document.as_array()?;
    let mut holidays = Vec::new();
    for entry in items {
        let Some(date) = entry.get("date").and_then(Value::as_str) else {
            continue;
        };
        if !date.starts_with(month) {
            continue;
        }
        let mut map = Map::new();
        map.insert(
            "date".to_string(),
            entry.get("date").cloned().unwrap_or(Value::Null),
        );
        map.insert(
            "name".to_string(),
            entry.get("localName").cloned().unwrap_or(Value::Null),
        );
        map.insert(
            "name_en".to_string(),
            entry.get("name").cloned().unwrap_or(Value::Null),
        );
        holidays.push(Value::Object(map));
    }
    Some(Value::Array(holidays))
}

fn empty() -> Resolved {
    Resolved {
        holidays: Value::Array(Vec::new()),
        error: None,
    }
}
