//! The snapshot itself: the three `journalctl` calls, the `systemctl` call,
//! the jq-shaped entry conversion and the one compact JSON line.
//!
//! The shell ran the four commands unconditionally, in this order, and its
//! failure handling is reproduced exactly:
//!
//! - a failed count command set that count to 0 and the snapshot still ran
//!   (`logs=$(… | wc -l) || logs=0` under `set -o pipefail`);
//! - a failed entries command left jq with an empty stream, so `jq -s` printed
//!   `[]`, `|| echo '[]'` appended a second `[]`, and the final
//!   `jq --argjson entries` rejected the result: no snapshot, exit 2. The
//!   stderr text below is jq 1.8's, preserved byte for byte because that is
//!   what the shell printed;
//! - if the entries stream did not parse at all, jq printed nothing, the
//!   fallback wrote the only `[]`, and the snapshot succeeded with no entries —
//!   also when journalctl had exited non-zero.

use std::ffi::OsStr;

use serde_json::{Map, Value};

use crate::process::{self, Signals};
use crate::{cli, jq, timefmt};

/// What `jq -n --argjson entries "$entries"` wrote when the entries pipeline
/// had produced two arrays (jq 1.8.2). The port keeps it: the pipeline is part
/// of the frozen behaviour, and the panels scene sees the same non-zero exit.
pub const ENTRIES_FAILURE_STDERR: &str = "\
jq: invalid JSON text passed to --argjson
Use jq --help for help with command-line options,
or see the jq manpage, or online docs at https://jqlang.org
";

const ENTRY_FIELDS: &str =
    "--output-fields=__REALTIME_TIMESTAMP,_SYSTEMD_UNIT,SYSLOG_IDENTIFIER,MESSAGE";

pub enum Failure {
    /// `command -v journalctl` failed: `journal: journalctl not found`, exit 1.
    JournalctlNotFound,
    /// The shell's entries pipeline died in the final jq call; exit 2.
    EntriesPipeline,
    Interrupted(i32),
}

pub struct Entry {
    pub time: String,
    /// A JSON value, not text: jq copied `_SYSTEMD_UNIT` as it was, and only
    /// real journals make it a string. The panels model reads it as text.
    pub service: Value,
    pub msg: String,
}

pub struct Snapshot {
    pub logs: u64,
    pub errors: u64,
    pub services: u64,
    pub entries: Vec<Entry>,
}

pub fn build(options: &cli::Options, signals: &Signals) -> Result<String, Failure> {
    // The shell checked `journalctl` once, before any command.
    if !process::on_path("journalctl") {
        return Err(Failure::JournalctlNotFound);
    }

    let since = options.since.as_os_str();
    let logs = journalctl_count(
        &[
            OsStr::new("--user"),
            OsStr::new("--since"),
            since,
            OsStr::new("--no-pager"),
            OsStr::new("-o"),
            OsStr::new("cat"),
        ],
        signals,
    )?;
    interrupted(signals)?;

    let errors = journalctl_count(
        &[
            OsStr::new("--user"),
            OsStr::new("--since"),
            since,
            OsStr::new("-p"),
            OsStr::new("err"),
            OsStr::new("--no-pager"),
            OsStr::new("-o"),
            OsStr::new("cat"),
        ],
        signals,
    )?;
    interrupted(signals)?;

    let services = match process::count(
        "systemctl",
        &[
            OsStr::new("--user"),
            OsStr::new("list-units"),
            OsStr::new("--type=service"),
            OsStr::new("--state=running"),
            OsStr::new("--no-legend"),
        ],
        signals,
    ) {
        Ok(counted) if counted.status.success() => counted.newlines,
        Ok(_) => 0,
        Err(process::Failure::Interrupted(signal)) => return Err(Failure::Interrupted(signal)),
        Err(_) => 0,
    };
    interrupted(signals)?;

    let entries = match process::capture(
        "journalctl",
        &[
            OsStr::new("--user"),
            OsStr::new("--since"),
            since,
            OsStr::new("-p"),
            OsStr::new("warning"),
            OsStr::new("--no-pager"),
            OsStr::new("-o"),
            OsStr::new("json"),
            OsStr::new(ENTRY_FIELDS),
            OsStr::new("-n"),
            options.entries.as_os_str(),
        ],
        signals,
    ) {
        Ok(captured) => match parse_entries(&captured.stdout) {
            Some(entries) if captured.status.success() => entries,
            // Parsed, but the command failed: the shell's duplicated `[]`.
            Some(_) => return Err(Failure::EntriesPipeline),
            // jq itself failed; the shell's `|| echo '[]'` was the only output.
            None => Vec::new(),
        },
        Err(process::Failure::Interrupted(signal)) => return Err(Failure::Interrupted(signal)),
        // The executable vanished between the run and this call: with jq as the
        // last pipeline stage the stream is empty, so this is the same failure.
        Err(_) => return Err(Failure::EntriesPipeline),
    };
    interrupted(signals)?;

    Ok(render(&Snapshot {
        logs,
        errors,
        services,
        entries,
    }))
}

fn interrupted(signals: &Signals) -> Result<(), Failure> {
    match signals.pending() {
        Some(signal) => Err(Failure::Interrupted(signal)),
        None => Ok(()),
    }
}

fn journalctl_count(arguments: &[&OsStr], signals: &Signals) -> Result<u64, Failure> {
    match process::count("journalctl", arguments, signals) {
        Ok(counted) if counted.status.success() => Ok(counted.newlines),
        Ok(_) => Ok(0),
        Err(process::Failure::Interrupted(signal)) => Err(Failure::Interrupted(signal)),
        // A failed pipeline wrote that count as 0 in the shell.
        Err(_) => Ok(0),
    }
}

/// Run the shell's entry filter over a parsed stream. `None` means the filter
/// failed and jq wrote nothing (the `|| echo '[]'` path).
fn parse_entries(bytes: &[u8]) -> Option<Vec<Entry>> {
    jq::parse_stream(bytes)?
        .iter()
        .map(convert_entry)
        .collect::<Option<Vec<_>>>()
}

fn convert_entry(value: &Value) -> Option<Entry> {
    let object = match value {
        Value::Null => None,
        Value::Object(map) => Some(map),
        // jq's `.field` on a number, boolean, string or array is an error, so
        // the whole filter fails.
        _ => return None,
    };

    let micros = jq::timestamp_seconds(field(object, "__REALTIME_TIMESTAMP"));
    let time = timefmt::hh_mm_from_micros(micros)?;

    let service = jq::either(
        field(object, "_SYSTEMD_UNIT"),
        field(object, "SYSLOG_IDENTIFIER"),
    )
    .cloned()
    .unwrap_or_else(|| Value::String("journal".to_string()));

    let message = field(object, "MESSAGE").filter(|value| jq::truthy(value));
    let msg = match message {
        Some(Value::Array(items)) => jq::join_space(items)?,
        Some(value) => jq::tostring(value),
        None => String::new(),
    };
    let msg = jq::slice_codepoints(&msg, 120);

    Some(Entry { time, service, msg })
}

fn field<'a>(object: Option<&'a Map<String, Value>>, name: &str) -> Option<&'a Value> {
    object.and_then(|map| map.get(name))
}

/// The final `jq -n -c` object: insertion order of the keys, no spaces.
fn render(snapshot: &Snapshot) -> String {
    let mut formatted =
        String::from("{\"ok\":true,\"worker\":\"journal\",\"version\":1,\"data\":{\"logs\":");
    formatted.push_str(&snapshot.logs.to_string());
    formatted.push_str(",\"errors\":");
    formatted.push_str(&snapshot.errors.to_string());
    formatted.push_str(",\"services\":");
    formatted.push_str(&snapshot.services.to_string());
    formatted.push_str(",\"entries\":[");
    for (index, entry) in snapshot.entries.iter().enumerate() {
        if index > 0 {
            formatted.push(',');
        }
        formatted.push_str("{\"time\":");
        formatted.push_str(&jq::string_literal(&entry.time));
        formatted.push_str(",\"service\":");
        formatted.push_str(&jq::render_value(&entry.service));
        formatted.push_str(",\"msg\":");
        formatted.push_str(&jq::string_literal(&entry.msg));
        formatted.push('}');
    }
    formatted.push_str("]}}");
    formatted
}
