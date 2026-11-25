//! The pill tracker's history and streak.
//!
//! The shell read `$XDG_DATA_HOME/pleamar/Pill/state.json` (the tracker's own
//! file) with the `PILL_FILTER` jq program: one `{date, taken}` record for
//! today and for every history record (today first), and the run of taken
//! days that ends at today. A missing or unreadable file is no error — the
//! fields are then empty and 0. The jq program is reproduced here, including
//! its laziness: a history date is parsed only when the record before it was
//! the previous day, and any value that made jq fail yields the empty result.

use std::fs;
use std::path::Path;

use serde_json::{Map, Value};

use crate::date;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Pills {
    pub list: Value,
    pub streak: i64,
}

impl Default for Pills {
    fn default() -> Self {
        Self {
            list: Value::Array(Vec::new()),
            streak: 0,
        }
    }
}

/// `pill_fields`: never an error, always a JSON-ready value.
pub fn read(path: &Path) -> Pills {
    let Ok(text) = fs::read_to_string(path) else {
        return Pills::default();
    };
    let Ok(value) = serde_json::from_str::<Value>(&text) else {
        return Pills::default();
    };
    from_value(&value).unwrap_or_default()
}

fn from_value(value: &Value) -> Option<Pills> {
    match value {
        // jq: `null` indexes as empty, so this is the object-less case.
        Value::Null => Some(Pills {
            list: Value::Array(vec![record(None, false)]),
            streak: 0,
        }),
        Value::Object(map) => from_object(map),
        // `.taken` on a string, number, array or boolean is a jq error.
        _ => None,
    }
}

fn from_object(state: &Map<String, Value>) -> Option<Pills> {
    let taken = matches!(state.get("taken"), Some(Value::Bool(true)));
    let history: &[Value] = match state.get("history") {
        // `($s.history // [])[]`: null and false are "empty".
        None | Some(Value::Null) | Some(Value::Bool(false)) => &[],
        Some(Value::Array(items)) => items,
        Some(_) => return None,
    };
    // The reduce indexes `.taken`/`.date` on every record it has not stopped
    // at, and the pills map indexes every record, so only objects and null are
    // acceptable.
    for entry in history {
        match entry {
            Value::Object(_) | Value::Null => {}
            _ => return None,
        }
    }

    let mut streak = if taken { 1 } else { 0 };
    if taken {
        let mut current = state.get("today").cloned().unwrap_or(Value::Null);
        let mut stopped = false;
        for entry in history {
            if stopped {
                continue;
            }
            // jq's `and` short-circuits: prevday runs only for a taken record.
            let entry_taken = matches!(entry.get("taken"), Some(Value::Bool(true)));
            if !entry_taken {
                stopped = true;
                continue;
            }
            let day = current.as_str()?;
            let expected = date::previous_day(day)?;
            if entry.get("date") == Some(&Value::String(expected)) {
                streak += 1;
                current = entry.get("date")?.clone();
            } else {
                stopped = true;
            }
        }
    }

    let mut list = Vec::with_capacity(history.len() + 1);
    list.push(record(state.get("today"), taken));
    for entry in history {
        match entry {
            Value::Null => list.push(record(None, false)),
            Value::Object(_) => list.push(record(
                entry.get("date"),
                matches!(entry.get("taken"), Some(Value::Bool(true))),
            )),
            _ => return None,
        }
    }
    Some(Pills {
        list: Value::Array(list),
        streak,
    })
}

fn record(date: Option<&Value>, taken: bool) -> Value {
    let mut map = Map::new();
    map.insert("date".to_string(), date.cloned().unwrap_or(Value::Null));
    map.insert("taken".to_string(), Value::Bool(taken));
    Value::Object(map)
}
