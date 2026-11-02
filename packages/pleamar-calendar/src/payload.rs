//! The `data` object: one month of events, holidays and workday codes.
//!
//! The shell built every payload with jq in this key order
//! (`{month, first, last, events, holidays, holidays_error, workdays,
//! workdays_error, fetched_at, cached, age_s}`), then `emit_sample` appended
//! `pills` and `streak`; the cache file is the same document with
//! `cached:true` and no `age_s`. The strings here reproduce that order; the
//! cache-hit projection keeps the key order of the document it reads back,
//! which is why `serde_json` is built with `preserve_order`.

use serde_json::{Map, Value};

use crate::json;
use crate::khal::Event;

/// `jq -c` of the events array.
pub fn events_json(events: &[Event]) -> String {
    let mut out = String::from("[");
    for (index, event) in events.iter().enumerate() {
        if index > 0 {
            out.push(',');
        }
        out.push_str(&event.to_json());
    }
    out.push(']');
    out
}

pub struct Payload {
    pub month: String,
    pub first: String,
    pub last: String,
    pub events: String,
    pub holidays: Value,
    pub holidays_error: Option<String>,
    pub workdays: Value,
    pub workdays_error: Option<String>,
    pub fetched_at: i64,
}

impl Payload {
    /// The sample's `data` (the shell's first jq object).
    pub fn to_json(&self, cached: bool, age_s: i64) -> String {
        format!(
            concat!(
                "{{\"month\":{},\"first\":{},\"last\":{},\"events\":{},\"holidays\":{},",
                "\"holidays_error\":{},\"workdays\":{},\"workdays_error\":{},",
                "\"fetched_at\":{},\"cached\":{},\"age_s\":{}}}"
            ),
            json::string(&self.month),
            json::string(&self.first),
            json::string(&self.last),
            self.events,
            value(&self.holidays),
            error_field(&self.holidays_error),
            value(&self.workdays),
            error_field(&self.workdays_error),
            self.fetched_at,
            cached,
            age_s,
        )
    }

    /// The cache document: `jq`'s second object, `cached:true`, no `age_s`.
    pub fn document(&self) -> String {
        format!(
            concat!(
                "{{\"month\":{},\"first\":{},\"last\":{},\"events\":{},\"holidays\":{},",
                "\"holidays_error\":{},\"workdays\":{},\"workdays_error\":{},",
                "\"fetched_at\":{},\"cached\":true}}"
            ),
            json::string(&self.month),
            json::string(&self.first),
            json::string(&self.last),
            self.events,
            value(&self.holidays),
            error_field(&self.holidays_error),
            value(&self.workdays),
            error_field(&self.workdays_error),
            self.fetched_at,
        )
    }
}

/// The shell's cache-hit projection:
/// `jq -c '{month, first, last, events, holidays, holidays_error, workdays,
/// workdays_error, fetched_at, cached: true, age_s: ($now - .fetched_at)}'`.
///
/// A key missing from the document becomes `null` in jq, so every projected
/// field is present here too, and nested objects keep the order the cache file
/// had.
pub fn from_cache(document: &Value, now: i64) -> Option<String> {
    document.as_object()?;
    let fetched_at = document.get("fetched_at").and_then(Value::as_i64);
    let age = fetched_at.map_or(0, |fetched| now.saturating_sub(fetched));
    let mut map = Map::new();
    for key in [
        "month",
        "first",
        "last",
        "events",
        "holidays",
        "holidays_error",
        "workdays",
        "workdays_error",
        "fetched_at",
    ] {
        map.insert(
            key.to_string(),
            document.get(key).cloned().unwrap_or(Value::Null),
        );
    }
    map.insert("cached".to_string(), Value::Bool(true));
    map.insert("age_s".to_string(), Value::from(age));
    serde_json::to_string(&Value::Object(map)).ok()
}

/// `PAYLOAD | jq -c '. + {pills: $pf.pills, streak: $pf.streak}'`: the two
/// fields are appended after `age_s`, in that order.
pub fn with_pills(payload: &str, pills: &Value, streak: i64) -> String {
    let mut out = String::with_capacity(payload.len() + 64);
    out.push_str(payload.strip_suffix('}').unwrap_or(payload));
    out.push_str(",\"pills\":");
    out.push_str(&value(pills));
    out.push_str(",\"streak\":");
    out.push_str(&streak.to_string());
    out.push('}');
    out
}

fn value(value: &Value) -> String {
    serde_json::to_string(value).unwrap_or_else(|_| "null".to_string())
}

fn error_field(error: &Option<String>) -> String {
    match error {
        Some(text) => json::string(text),
        None => "null".to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn payload() -> Payload {
        Payload {
            month: "2026-11".into(),
            first: "2026-11-01".into(),
            last: "2026-11-30".into(),
            events: events_json(&[Event {
                date: "2026-11-05".into(),
                time: "09:00".into(),
                title: "Standup".into(),
                calendar: "Work".into(),
            }]),
            holidays: serde_json::json!([
                {"date": "2026-11-04", "name": "Unity Day", "name_en": "Unity Day"}
            ]),
            holidays_error: None,
            workdays: serde_json::json!([{"date": "2026-11-05", "code": 1}]),
            workdays_error: None,
            fetched_at: 1_793_654_924,
        }
    }

    #[test]
    fn sample_object_has_the_shell_key_order() {
        assert_eq!(
            payload().to_json(false, 0),
            concat!(
                r#"{"month":"2026-11","first":"2026-11-01","last":"2026-11-30","#,
                r#""events":[{"date":"2026-11-05","time":"09:00","title":"Standup","calendar":"Work"}],"#,
                r#""holidays":[{"date":"2026-11-04","name":"Unity Day","name_en":"Unity Day"}],"#,
                r#""holidays_error":null,"workdays":[{"date":"2026-11-05","code":1}],"#,
                r#""workdays_error":null,"fetched_at":1793654924,"cached":false,"age_s":0}"#
            )
        );
    }

    #[test]
    fn cache_document_drops_age_s_and_sets_cached() {
        let payload = payload();
        assert_eq!(
            payload.document(),
            concat!(
                r#"{"month":"2026-11","first":"2026-11-01","last":"2026-11-30","#,
                r#""events":[{"date":"2026-11-05","time":"09:00","title":"Standup","calendar":"Work"}],"#,
                r#""holidays":[{"date":"2026-11-04","name":"Unity Day","name_en":"Unity Day"}],"#,
                r#""holidays_error":null,"workdays":[{"date":"2026-11-05","code":1}],"#,
                r#""workdays_error":null,"fetched_at":1793654924,"cached":true}"#
            )
        );
    }

    #[test]
    fn error_fields_are_null_or_text() {
        let mut payload = payload();
        payload.holidays_error = Some("holidays request failed: curl: (22)".into());
        payload.workdays_error = Some("work calendar gave no day codes".into());
        let text = payload.to_json(false, 0);
        assert!(text.contains(r#""holidays_error":"holidays request failed: curl: (22)""#));
        assert!(text.contains(r#""workdays_error":"work calendar gave no day codes""#));
    }

    #[test]
    fn cache_projection_keeps_order_and_recomputes_age() {
        let document: Value = serde_json::from_str(concat!(
            r#"{"month":"2026-11","first":"F","last":"L","#,
            r#""events":[{"calendar":"C","date":"D"}],"holidays":[],"holidays_error":null,"#,
            r#""workdays":[],"workdays_error":"we","fetched_at":1000,"cached":false,"extra":1}"#
        ))
        .expect("document");
        let text = from_cache(&document, 1042).expect("projection");
        assert_eq!(
            text,
            concat!(
                r#"{"month":"2026-11","first":"F","last":"L","events":[{"calendar":"C","date":"D"}],"#,
                r#""holidays":[],"holidays_error":null,"workdays":[],"workdays_error":"we","#,
                r#""fetched_at":1000,"cached":true,"age_s":42}"#
            )
        );
    }

    #[test]
    fn a_missing_cache_field_becomes_null_like_jq() {
        let document: Value =
            serde_json::from_str(r#"{"month":"2026-11","fetched_at":1000}"#).expect("document");
        let text = from_cache(&document, 1001).expect("projection");
        assert_eq!(
            text,
            concat!(
                r#"{"month":"2026-11","first":null,"last":null,"events":null,"holidays":null,"#,
                r#""holidays_error":null,"workdays":null,"workdays_error":null,"#,
                r#""fetched_at":1000,"cached":true,"age_s":1}"#
            )
        );
    }

    #[test]
    fn pills_are_appended_last() {
        let payload = payload().to_json(false, 0);
        let pills = serde_json::json!([{"date": "2026-11-03", "taken": true}]);
        let text = with_pills(&payload, &pills, 3);
        assert_eq!(
            text,
            format!(
                "{},\"pills\":[{{\"date\":\"2026-11-03\",\"taken\":true}}],\"streak\":3}}",
                payload.strip_suffix('}').expect("object")
            )
        );
    }
}
