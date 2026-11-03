//! The data pipeline: cache decision, coordinate resolution, provider order
//! and the sample line.
//!
//! The shell's `build_payload` is transcribed here:
//!
//! 1. `NOW=$(date +%s)`;
//! 2. without `--force`, a cache whose city matches, whose coordinates match
//!    (when `--lat/--lon` were given), and whose age is below `--ttl` is served
//!    with `cached:true` and the age recomputed;
//! 3. coordinates come from `--lat/--lon`, the cache's `geocoded_at` (reused
//!    for 24 hours), or the geocoding API;
//! 4. Open-Meteo and the wttr.in current conditions (whose `daily` is MET
//!    Norway's) are dialled at once and the first payload wins; with
//!    `--no-fallback` only Open-Meteo is asked, as the shell did;
//! 5. a successful payload is written to the cache and `FORCE` is cleared; a
//!    failed one leaves the last good cache in place and returns the error
//!    text (the two provider errors joined with `"; "`, Open-Meteo first, when
//!    both failed).

use std::io::{self, Write};
use std::sync::atomic::AtomicBool;
use std::sync::mpsc::{self, RecvTimeoutError};
use std::sync::Arc;
use std::thread;

use crate::cache::{self, Cache};
use crate::cli::Options;
use crate::failure::Failure;
use crate::geo::{self, Coords};
use crate::http::{Http, INTERRUPT_POLL};
use crate::openmeteo;
use crate::payload::Payload;
use crate::protocol;
use crate::wttr;

/// A cache's geocoding memory is reused for a day.
const GEOCODING_TTL_SECS: i64 = 86_400;

pub enum Outcome {
    Continue,
    /// SIGTERM/SIGINT arrived while a request was in flight.
    Interrupted,
}

/// Which attempt of the provider race an arrival belongs to. It is what keeps
/// the joined error text in the shell's order (`open-meteo; fallback`) instead
/// of the order the two happened to fail in.
#[derive(Clone, Copy)]
enum Slot {
    Primary,
    Fallback,
}

pub struct Worker {
    options: Options,
    cache: Option<Cache>,
    http: Http,
    /// The shell's `FORCE`: cleared by a successful fetch.
    force: bool,
    geocoded_at: i64,
    coords: Option<Coords>,
}

impl Worker {
    pub fn new(options: Options, interrupt: Arc<AtomicBool>) -> Self {
        let cache = Cache::load(&options.cache_file);
        let http = Http::new(options.timeout, &options.user_agent, interrupt);
        let force = options.force;
        Self {
            options,
            cache,
            http,
            force,
            geocoded_at: 0,
            coords: None,
        }
    }

    /// Capture `t`, build the payload and write one sample (or error) line.
    pub fn emit_sample<W: Write>(&mut self, out: &mut W) -> io::Result<Outcome> {
        // The shell took `t` before the fetch, so a slow provider shows in the
        // line's age, not in `t`.
        let t = crate::now_ms();
        match self.build_payload(crate::now_secs()) {
            Ok(payload) => {
                protocol::write_sample(out, t, &payload)?;
                Ok(Outcome::Continue)
            }
            Err(Failure::Message(message)) => {
                // `sample_error` measured the clock after the failure.
                protocol::write_sample_error(out, crate::now_ms(), &message)?;
                Ok(Outcome::Continue)
            }
            Err(Failure::Interrupted) => Ok(Outcome::Interrupted),
        }
    }

    fn build_payload(&mut self, now: i64) -> Result<String, Failure> {
        if !self.force && self.cache_hit(now) {
            if let Some(cache) = &self.cache {
                return Ok(cache.cached_payload(now));
            }
        }

        self.resolve_coords(now)?;
        let coords = self
            .coords
            .clone()
            .expect("resolve_coords sets coordinates");

        let payload = self.fetch_providers(&coords, now)?;
        self.store(&payload, now);
        Ok(payload.to_json(false, 0))
    }

    /// One payload from whichever provider answers first.
    ///
    /// The two providers are independent services, and one of them can be
    /// unreachable without the other noticing: `api.open-meteo.com` accepts no
    /// TCP connection from this host at all, so a serial attempt spends its
    /// whole deadline before the fallback is even dialled — 3.0 s of a 3.4 s
    /// cold card, measured 2026-11-04, and the card draws nothing until the
    /// sample lands. Both are therefore dialled together and the first payload
    /// wins.
    ///
    /// The price is one fallback attempt per sample even when Open-Meteo
    /// answers: the loser is abandoned, not cancelled. The gain is that a
    /// blackholed provider cannot hold the card for its whole `--timeout`.
    ///
    /// A failure is still reported as `open-meteo; fallback`, in that order,
    /// whatever order the two gave up in: the text a user reads must not depend
    /// on which provider was slower to fail.
    fn fetch_providers(&self, coords: &Coords, now: i64) -> Result<Payload, Failure> {
        if !self.options.fallback {
            return openmeteo::fetch(
                &self.http,
                &self.options.api_base,
                coords,
                self.options.forecast_days,
                &self.options.city,
                now,
            );
        }

        let (sender, receiver) = mpsc::channel();
        {
            let sender = sender.clone();
            let http = self.http.clone();
            let api_base = self.options.api_base.clone();
            let city = self.options.city.clone();
            let forecast_days = self.options.forecast_days;
            let coords = coords.clone();
            thread::spawn(move || {
                let result = openmeteo::fetch(&http, &api_base, &coords, forecast_days, &city, now);
                let _ = sender.send((Slot::Primary, result));
            });
        }
        {
            let sender = sender.clone();
            let http = self.http.clone();
            let wttr_base = self.options.wttr_base.clone();
            let metno_base = self.options.metno_base.clone();
            let city = self.options.city.clone();
            let forecast_days = self.options.forecast_days;
            let coords = coords.clone();
            thread::spawn(move || {
                let result = wttr::fetch(
                    &http,
                    &wttr_base,
                    &metno_base,
                    &coords,
                    &city,
                    now,
                    forecast_days,
                );
                let _ = sender.send((Slot::Fallback, result));
            });
        }
        drop(sender);

        let mut primary_error: Option<String> = None;
        let mut fallback_error: Option<String> = None;
        // Two answers are expected. A poll timeout is not one of them, so it
        // does not move the loop on — only a signal may cut the wait short.
        while primary_error.is_none() || fallback_error.is_none() {
            let (slot, result) = match receiver.recv_timeout(INTERRUPT_POLL) {
                Ok(arrival) => arrival,
                Err(RecvTimeoutError::Timeout) => {
                    if self.http.interrupted() {
                        return Err(Failure::Interrupted);
                    }
                    continue;
                }
                // Both attempts ended without sending: a helper thread that
                // cannot report a provider failure. Nothing to quote, so the
                // sample says that much instead of inventing a provider error.
                Err(RecvTimeoutError::Disconnected) => break,
            };
            match result {
                Ok(payload) => return Ok(payload),
                Err(Failure::Interrupted) => return Err(Failure::Interrupted),
                Err(Failure::Message(message)) => match slot {
                    Slot::Primary => primary_error = Some(message),
                    Slot::Fallback => fallback_error = Some(message),
                },
            }
        }

        Err(Failure::Message(match (primary_error, fallback_error) {
            (Some(primary), Some(fallback)) => format!("{primary}; {fallback}"),
            (Some(primary), None) => primary,
            (None, Some(fallback)) => fallback,
            (None, None) => "no weather provider answered".to_string(),
        }))
    }

    fn cache_hit(&self, now: i64) -> bool {
        let Some(cache) = &self.cache else {
            return false;
        };
        if cache.city != self.options.city {
            return false;
        }
        if !self.options.latitude.is_empty() && !self.options.longitude.is_empty() {
            if cache.latitude.as_deref() != Some(self.options.latitude.as_str()) {
                return false;
            }
            if cache.longitude.as_deref() != Some(self.options.longitude.as_str()) {
                return false;
            }
        }
        let ttl = i64::try_from(self.options.ttl).unwrap_or(i64::MAX);
        now.saturating_sub(cache.fetched_at) < ttl
    }

    fn resolve_coords(&mut self, now: i64) -> Result<(), Failure> {
        if !self.options.latitude.is_empty() && !self.options.longitude.is_empty() {
            self.geocoded_at = now;
            self.coords = Some(Coords::from_cli(
                &self.options.latitude,
                &self.options.longitude,
            ));
            return Ok(());
        }
        if let Some(cache) = &self.cache {
            if cache.city == self.options.city {
                if let (Some(latitude), Some(longitude)) = (&cache.latitude, &cache.longitude) {
                    if now.saturating_sub(cache.geocoded_at) < GEOCODING_TTL_SECS {
                        self.coords = Some(Coords::from_cache(latitude, longitude));
                        self.geocoded_at = cache.geocoded_at;
                        return Ok(());
                    }
                }
            }
        }
        if self.options.city.is_empty() {
            return Err(Failure::Message(
                "no city configured (use --city, --lat/--lon or PLEAMAR_WEATHER_CITY)".to_string(),
            ));
        }
        let coords = geo::geocode(&self.http, &self.options.geocoding_base, &self.options.city)?;
        self.coords = Some(coords);
        self.geocoded_at = now;
        Ok(())
    }

    /// Write the cache and make its document the in-memory one, as the shell's
    /// `cache_write` did by re-reading the file. A failed write leaves the
    /// previous cache in place and does not fail the sample.
    fn store(&mut self, payload: &Payload, now: i64) {
        if let Some(coords) = self.coords.clone() {
            let document = Cache::document(
                &self.options.city,
                &coords.lat_json,
                &coords.lon_json,
                self.geocoded_at,
                now,
                payload,
            );
            match cache::write(&self.options.cache_file, &document) {
                Ok(()) => {
                    self.cache = Some(Cache {
                        city: self.options.city.clone(),
                        latitude: Some(coords.lat_json),
                        longitude: Some(coords.lon_json),
                        geocoded_at: self.geocoded_at,
                        fetched_at: now,
                        payload: payload.clone(),
                    });
                }
                Err(error) => {
                    // stderr is for humans and never part of the protocol.
                    eprintln!("weather: cache write failed: {error}");
                }
            }
        }
        self.force = false;
    }

    #[cfg(test)]
    pub fn cache(&self) -> Option<&Cache> {
        self.cache.as_ref()
    }

    #[cfg(test)]
    pub fn force(&self) -> bool {
        self.force
    }

    #[cfg(test)]
    pub fn cache_hit_at(&self, now: i64) -> bool {
        self.cache_hit(now)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cli::{Env, ParseResult};

    fn options(directory: &std::path::Path, extra: &[&str]) -> Options {
        let mut values = vec![
            "--cache-file".to_string(),
            directory
                .join("weather.json")
                .to_string_lossy()
                .into_owned(),
            // Every base is unreachable on purpose: a unit test must never
            // reach a real provider. The integration tests use local mocks.
            "--api-base".to_string(),
            "http://127.0.0.1:1/v1".to_string(),
            "--geocoding-base".to_string(),
            "http://127.0.0.1:1/geo/v1".to_string(),
            "--wttr-base".to_string(),
            "http://127.0.0.1:1/wttr".to_string(),
            "--metno-base".to_string(),
            "http://127.0.0.1:1/metno".to_string(),
            "--timeout".to_string(),
            "1".to_string(),
        ];
        values.extend(extra.iter().map(|value| value.to_string()));
        let arguments: Vec<std::ffi::OsString> =
            values.into_iter().map(std::ffi::OsString::from).collect();
        match crate::cli::parse(arguments, &Env::default()) {
            ParseResult::Run(options) => options,
            other => panic!("expected Run, got {other:?}"),
        }
    }

    fn interrupt() -> Arc<AtomicBool> {
        Arc::new(AtomicBool::new(false))
    }

    const PAYLOAD: &str = concat!(
        r#"{"city":"Oslo","latitude":59.9,"longitude":10.7,"provider":"open-meteo","#,
        r#""fetched_at":1000,"age_s":0,"cached":false,"current":{"temp_c":5,"#,
        r#""weather_code":3,"wind_ms":1.0,"wind_dir_deg":90,"is_day":1,"#,
        r#""humidity_pct":80,"pressure_hpa":1013},"daily":[]}"#
    );

    fn write_cache(
        path: &std::path::Path,
        city: &str,
        latitude: &str,
        longitude: &str,
        geocoded_at: i64,
        fetched_at: i64,
    ) {
        let payload: Payload = serde_json::from_str(PAYLOAD).expect("payload");
        let document =
            Cache::document(city, latitude, longitude, geocoded_at, fetched_at, &payload);
        cache::write(path, &document).expect("cache");
    }

    #[test]
    fn a_fresh_cache_is_served_with_its_age() {
        let directory = crate::testutil::TempDir::new("worker-hit");
        write_cache(
            &directory.path().join("weather.json"),
            "Oslo",
            "59.9",
            "10.7",
            900,
            1_000,
        );
        let worker = Worker::new(options(directory.path(), &["--city", "Oslo"]), interrupt());
        assert!(worker.cache_hit_at(1_042));
        assert!(!worker.cache_hit_at(1_301), "past the 300 s TTL");
        let served = worker.cache().expect("cache").cached_payload(1_042);
        assert!(served.contains("\"cached\":true"));
        assert!(served.contains("\"age_s\":42"));
    }

    #[test]
    fn force_skips_the_cache() {
        let directory = crate::testutil::TempDir::new("worker-force");
        write_cache(
            &directory.path().join("weather.json"),
            "Oslo",
            "59.9",
            "10.7",
            900,
            1_000,
        );
        let worker = Worker::new(
            options(directory.path(), &["--city", "Oslo", "--force"]),
            interrupt(),
        );
        assert!(worker.force());
    }

    #[test]
    fn the_city_and_the_coordinates_have_to_match() {
        let directory = crate::testutil::TempDir::new("worker-match");
        write_cache(
            &directory.path().join("weather.json"),
            "Oslo",
            "59.9",
            "10.7",
            900,
            1_000,
        );
        assert!(
            Worker::new(options(directory.path(), &["--city", "Oslo"]), interrupt())
                .cache_hit_at(1_042),
            "city matches"
        );
        assert!(
            !Worker::new(
                options(
                    directory.path(),
                    &["--city", "Oslo", "--lat", "59.9", "--lon", "10.8"],
                ),
                interrupt(),
            )
            .cache_hit_at(1_042),
            "different longitude"
        );
        assert!(
            !Worker::new(
                options(
                    directory.path(),
                    &["--city", "Bergen", "--lat", "59.9", "--lon", "10.7"],
                ),
                interrupt(),
            )
            .cache_hit_at(1_042),
            "different city"
        );
    }

    #[test]
    fn geocoding_memory_is_reused_for_a_day() {
        let directory = crate::testutil::TempDir::new("worker-geo");
        write_cache(
            &directory.path().join("weather.json"),
            "Oslo",
            "59.9",
            "10.7",
            10_000,
            10_000,
        );
        let mut worker = Worker::new(options(directory.path(), &["--city", "Oslo"]), interrupt());
        assert!(!worker.cache_hit_at(10_400), "the payload cache is stale");
        worker
            .resolve_coords(10_000 + 23 * 3_600)
            .expect("coordinates are reused inside 24 h");
        assert_eq!(worker.geocoded_at, 10_000);
        assert_eq!(
            worker.coords.as_ref().expect("coords").lat_url,
            "59.9",
            "no geocoding request was made"
        );
    }

    #[test]
    fn a_missing_city_is_the_shells_error() {
        let directory = crate::testutil::TempDir::new("worker-nocity");
        let mut worker = Worker::new(options(directory.path(), &[]), interrupt());
        assert_eq!(
            worker.build_payload(1_000),
            Err(Failure::Message(
                "no city configured (use --city, --lat/--lon or PLEAMAR_WEATHER_CITY)".to_string()
            ))
        );
    }
}
