//! The data pipeline: payload cache, khal, holidays, workdays and the sample.
//!
//! The shell's `build_payload` is transcribed here:
//!
//! 1. `NOW=$(date +%s)`;
//! 2. a `calendar-YYYY-MM.json` whose `month` matches and whose `fetched_at`
//!    is younger than 120 s is served with `cached:true` and the age
//!    recomputed — khal and both HTTP APIs are skipped;
//! 3. otherwise khal lists the month (holidays/workdays are not fetched when
//!    khal fails);
//! 4. the holiday and production-calendar caches are consulted for 24 h, then
//!    the local APIs;
//! 5. the fresh document is written to the cache (`cached:true`) and the
//!    sample carries `pills`/`streak`, which are read from the pill tracker's
//!    file on every sample and never cached.

use std::fs;
use std::io::{self, Write};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use crate::cache;
use crate::cli::Options;
use crate::date::Month;
use crate::failure::Failure;
use crate::holidays;
use crate::http::Http;
use crate::khal;
use crate::payload::{self, Payload};
use crate::pills;
use crate::protocol;
use crate::workdays;

/// `calendar-YYYY-MM.json` is served for two minutes.
const CALENDAR_TTL_SECS: i64 = 120;

pub enum Outcome {
    Continue,
    /// SIGTERM/SIGINT arrived while a request was in flight.
    Interrupted,
}

pub struct Worker {
    options: Options,
    http: Http,
    interrupt: Arc<AtomicBool>,
}

impl Worker {
    pub fn new(options: Options, interrupt: Arc<AtomicBool>) -> Self {
        let http = Http::new(crate::cli::USER_AGENT, Arc::clone(&interrupt));
        Self {
            options,
            http,
            interrupt,
        }
    }

    /// Capture `t`, build the payload and write one sample (or error) line.
    pub fn emit_sample<W: Write>(&self, month: &Month, out: &mut W) -> io::Result<Outcome> {
        // The shell took `t` before the fetch, so a slow khal/HTTP answer shows
        // in the sample's age, not in `t`.
        let t = crate::now_ms();
        match self.build_payload(month, crate::now_secs()) {
            Ok(payload) => {
                // Fresh on every sample and never cached: the tracker writes
                // the file while the drawer is open.
                let pills = pills::read(&self.options.pill_state);
                let data = payload::with_pills(&payload, &pills.list, pills.streak);
                protocol::write_sample(out, t, &data)?;
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

    fn build_payload(&self, month: &Month, now: i64) -> Result<String, Failure> {
        if self.interrupt.load(Ordering::Relaxed) {
            return Err(Failure::Interrupted);
        }
        let cache_file = calendar_cache_file(&self.options.cache_dir, month);
        if let Some(text) = fs::read_to_string(&cache_file).ok() {
            if let Ok(document) = serde_json::from_str::<serde_json::Value>(&text) {
                if self.cache_hit(&document, month, now) {
                    if let Some(payload) = payload::from_cache(&document, now) {
                        return Ok(payload);
                    }
                }
            }
        }

        let text = khal::list_month(month).map_err(Failure::Message)?;
        if self.interrupt.load(Ordering::Relaxed) {
            return Err(Failure::Interrupted);
        }
        let events = khal::parse_events(&text);

        let holidays = holidays::resolve(
            &self.options.country,
            month,
            &self.options.cache_dir,
            &self.options.holidays_base,
            &self.http,
            now,
        )?;
        let workdays = workdays::resolve(
            &self.options.country,
            month,
            &self.options.cache_dir,
            &self.options.workdays_base,
            &self.http,
            now,
        )?;

        let payload = Payload {
            month: month.name(),
            first: month.first.clone(),
            last: month.last.clone(),
            events: payload::events_json(&events),
            holidays: holidays.holidays,
            holidays_error: holidays.error,
            workdays: workdays.workdays,
            workdays_error: workdays.error,
            fetched_at: now,
        };

        let document = format!("{}\n", payload.document());
        if let Err(error) = cache::write_atomic(&cache_file, document.as_bytes(), "calendar") {
            // stderr is for humans and never part of the protocol.
            eprintln!("calendar: cache write failed: {error}");
        }

        Ok(payload.to_json(false, 0))
    }

    /// `[ "$c_month" = "$MONTH" ] && [ "$age" -lt 120 ]`.
    fn cache_hit(&self, document: &serde_json::Value, month: &Month, now: i64) -> bool {
        let document_month = document
            .get("month")
            .and_then(serde_json::Value::as_str)
            .unwrap_or("");
        if document_month != month.name() {
            return false;
        }
        let fetched_at = document
            .get("fetched_at")
            .and_then(serde_json::Value::as_i64)
            .unwrap_or(0);
        now.saturating_sub(fetched_at) < CALENDAR_TTL_SECS
    }
}

pub fn calendar_cache_file(cache_dir: &std::path::Path, month: &Month) -> std::path::PathBuf {
    cache_dir.join(format!("calendar-{}.json", month.name()))
}
