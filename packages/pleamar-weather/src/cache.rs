//! The payload cache and the geocoding memory it carries.
//!
//! One document per file, exactly the shell's shape (jq -c, keys in this
//! order):
//!
//! ```json
//! {"city":"Saint Petersburg","latitude":59.93863,"longitude":30.31413,
//!  "geocoded_at":1793570880,"fetched_at":1793641408,"payload":{…}}
//! ```
//!
//! `geocoded_at` lets `resolve_coords` reuse coordinates for a day without
//! calling the geocoder again; `fetched_at` is the payload's age reference.
//!
//! Writes are atomic the way the shell's were: `mkdir -p`, a private temp file
//! (`.weather.XXXXXX`, mode 0600, as `mktemp` made it), then `mv -f`. A cache
//! read that does not carry a payload with a `daily` array is ignored — the
//! shell's `select(.payload.daily != null)`, which keeps a pre-`daily` payload
//! from being served for a whole TTL.

use std::fs;
use std::io::{self, Write};
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use serde::Deserialize;
use serde_json::value::RawValue;

use crate::json;
use crate::payload::Payload;

static ATTEMPT: AtomicU64 = AtomicU64::new(0);

#[derive(Clone, Debug, Deserialize)]
struct Document {
    #[serde(default)]
    city: Option<Box<RawValue>>,
    #[serde(default)]
    latitude: Option<Box<RawValue>>,
    #[serde(default)]
    longitude: Option<Box<RawValue>>,
    #[serde(default)]
    geocoded_at: Option<i64>,
    #[serde(default)]
    fetched_at: Option<i64>,
    payload: Payload,
}

#[derive(Clone, Debug)]
pub struct Cache {
    /// `jq -r`.city // ""` — what the cache-hit comparison needs.
    pub city: String,
    /// `jq -r '.latitude // empty'`, the text the shell compared with `$LAT`.
    pub latitude: Option<String>,
    pub longitude: Option<String>,
    pub geocoded_at: i64,
    pub fetched_at: i64,
    pub payload: Payload,
}

/// `jq -r` of a cached value: a number prints as its literal, a string prints
/// unquoted, anything else prints its compact JSON text.
fn render(raw: &RawValue) -> Option<String> {
    match serde_json::from_str::<serde_json::Value>(raw.get()).ok()? {
        serde_json::Value::String(text) => Some(text),
        _ => Some(raw.get().to_string()),
    }
}

impl Cache {
    /// Read the cache; `None` covers missing, unreadable, invalid and
    /// `daily`-less documents (the shell's `jq -c 'select(.payload.daily !=
    /// null)'` with the error swallowed).
    pub fn load(path: &Path) -> Option<Cache> {
        let text = fs::read_to_string(path).ok()?;
        let document: Document = serde_json::from_str(&text).ok()?;
        Some(Cache {
            city: document
                .city
                .as_deref()
                .and_then(render)
                .unwrap_or_default(),
            latitude: document.latitude.as_deref().and_then(render),
            longitude: document.longitude.as_deref().and_then(render),
            geocoded_at: document.geocoded_at.unwrap_or(0),
            fetched_at: document.fetched_at.unwrap_or(0),
            payload: document.payload,
        })
    }

    /// The cache-hit payload: the stored payload with `cached` true and the age
    /// recomputed against its own `fetched_at`, exactly the shell's
    /// `.payload + {cached:true, age_s: ($now - (.fetched_at // $now))}`.
    pub fn cached_payload(&self, now: i64) -> String {
        self.payload.to_json(true, now - self.payload.fetched_at)
    }

    /// The wrapper document with a fresh payload, in the shell's key order.
    pub fn document(
        city: &str,
        latitude_json: &str,
        longitude_json: &str,
        geocoded_at: i64,
        fetched_at: i64,
        payload: &Payload,
    ) -> String {
        format!(
            "{{\"city\":{},\"latitude\":{},\"longitude\":{},\"geocoded_at\":{},\"fetched_at\":{},\"payload\":{}}}",
            json::string(city),
            latitude_json,
            longitude_json,
            geocoded_at,
            fetched_at,
            payload.to_json(false, 0),
        )
    }
}

/// Write `document` atomically: `mkdir -p` the parent, create a private temp
/// file next to the target, write, then rename over it.
pub fn write(path: &Path, document: &str) -> io::Result<()> {
    let directory = path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty());
    if let Some(directory) = directory {
        fs::create_dir_all(directory)?;
    }
    let mut attempt = 0;
    loop {
        let target = directory.unwrap_or_else(|| Path::new("."));
        let temp = temp_path(target);
        let mut file = match fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&temp)
        {
            Ok(file) => file,
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists && attempt < 128 => {
                attempt += 1;
                continue;
            }
            Err(error) => return Err(error),
        };
        let result = file
            .write_all(document.as_bytes())
            .and_then(|()| file.write_all(b"\n"))
            .and_then(|()| file.flush())
            .and_then(|()| {
                drop(file);
                fs::rename(&temp, path)
            });
        if result.is_err() {
            let _ = fs::remove_file(&temp);
        }
        return result;
    }
}

fn temp_path(directory: &Path) -> PathBuf {
    directory.join(format!(".weather.{}", random_suffix()))
}

/// Six characters from the `mktemp` alphabet; only uniqueness matters.
fn random_suffix() -> String {
    const ALPHABET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .unwrap_or(0);
    let mut state = nanos
        ^ ((std::process::id() as u128) << 32)
        ^ (ATTEMPT.fetch_add(1, Ordering::Relaxed) as u128);
    let mut suffix = String::with_capacity(6);
    for _ in 0..6 {
        state ^= state << 13;
        state ^= state >> 7;
        state ^= state << 17;
        suffix.push(ALPHABET[(state % ALPHABET.len() as u128) as usize] as char);
    }
    suffix
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testutil::TempDir;
    use std::os::unix::fs::PermissionsExt;

    const PAYLOAD: &str = concat!(
        r#"{"city":"Saint Petersburg","latitude":59.93863,"longitude":30.31413,"#,
        r#""provider":"open-meteo","fetched_at":1793641408,"age_s":0,"cached":false,"#,
        r#""current":{"temp_c":6.3,"weather_code":3,"wind_ms":3.40,"wind_dir_deg":231,"#,
        r#""is_day":0,"humidity_pct":81,"pressure_hpa":1027.4},"#,
        r#""daily":[{"date":"2026-11-02","tmax_c":7.9,"tmin_c":5.6,"weather_code":3}]}"#
    );

    fn payload() -> Payload {
        serde_json::from_str(PAYLOAD).expect("payload")
    }

    #[test]
    fn document_matches_the_shell_shape() {
        let document = Cache::document(
            "Saint Petersburg",
            "59.93863",
            "30.31413",
            1_793_570_880,
            1_793_641_408,
            &payload(),
        );
        assert_eq!(
            document,
            format!(
                r#"{{"city":"Saint Petersburg","latitude":59.93863,"longitude":30.31413,"geocoded_at":1793570880,"fetched_at":1793641408,"payload":{PAYLOAD}}}"#
            )
        );
        assert!(document.contains(r#""payload":{"city":"Saint Petersburg""#));
    }

    #[test]
    fn write_then_load_round_trips_and_sets_a_private_mode() {
        let directory = TempDir::new("cache-round-trip");
        let path = directory.path().join("nested/pleamar/weather.json");
        let document = Cache::document("x", "1", "2", 10, 20, &payload());
        write(&path, &document).expect("write");
        let text = fs::read_to_string(&path).expect("cache");
        assert_eq!(text, format!("{document}\n"));
        let mode = fs::metadata(&path).expect("metadata").permissions().mode();
        assert_eq!(mode & 0o777, 0o600);
        // No temp files survive a successful write.
        let leftovers: Vec<_> = fs::read_dir(path.parent().expect("parent"))
            .expect("dir")
            .filter_map(|entry| entry.ok())
            .filter(|entry| entry.file_name().to_string_lossy().starts_with(".weather."))
            .collect();
        assert!(leftovers.is_empty(), "temp file left behind");

        let cache = Cache::load(&path).expect("cache loads");
        assert_eq!(cache.city, "x");
        assert_eq!(cache.latitude.as_deref(), Some("1"));
        assert_eq!(cache.longitude.as_deref(), Some("2"));
        assert_eq!(cache.geocoded_at, 10);
        assert_eq!(cache.fetched_at, 20);
        assert_eq!(cache.payload.to_json(false, 0), PAYLOAD);
    }

    #[test]
    fn cached_payload_recomputes_the_age() {
        let directory = TempDir::new("cache-hit");
        let path = directory.path().join("weather.json");
        let mut cached = payload();
        cached.fetched_at = 1_000;
        write(&path, &Cache::document("x", "1", "2", 10, 1_000, &cached)).expect("write");
        let cache = Cache::load(&path).expect("cache");
        let served = cache.cached_payload(1_042);
        assert!(served.contains("\"cached\":true"));
        assert!(served.contains("\"age_s\":42"));
        // The payload's own fetched_at is kept and so is the literal format.
        assert!(served.contains("\"fetched_at\":1000"));
        assert!(served.contains("\"wind_ms\":3.40"));
    }

    #[test]
    fn a_document_without_daily_is_not_a_cache() {
        let directory = TempDir::new("cache-no-daily");
        for document in [
            "",
            "not json",
            "[]",
            "{}",
            r#"{"payload":null}"#,
            r#"{"payload":{}}"#,
            r#"{"payload":{"daily":null}}"#,
            r#"{"payload":{"daily":5}}"#,
            r#"{"city":"x","latitude":1,"longitude":2,"geocoded_at":3,"fetched_at":4,"payload":{"city":"x"}}"#,
        ] {
            let path = directory.path().join("weather.json");
            fs::write(&path, document).expect("cache");
            assert!(Cache::load(&path).is_none(), "{document}");
        }
    }

    #[test]
    fn a_missing_cache_is_not_an_error() {
        let directory = TempDir::new("cache-missing");
        assert!(Cache::load(&directory.path().join("nope.json")).is_none());
    }

    #[test]
    fn number_literals_from_the_wrapper_are_rendered_like_jq_r() {
        let directory = TempDir::new("cache-literal");
        let path = directory.path().join("weather.json");
        let document = format!(
            r#"{{"city":"x","latitude":59.938630,"longitude":"30.30","geocoded_at":7,"fetched_at":9,"payload":{PAYLOAD}}}"#
        );
        write(&path, &document).expect("write");
        let cache = Cache::load(&path).expect("cache");
        assert_eq!(cache.latitude.as_deref(), Some("59.938630"));
        assert_eq!(cache.longitude.as_deref(), Some("30.30"));
    }
}
