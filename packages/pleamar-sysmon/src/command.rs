//! The worker protocol: the handshake, the stdin command loop and the sample
//! lines. The wire format, acks and error strings are those of `sysmon.sh`.

use std::io::{self, Write};

use crate::llm::LlmProbe;
use crate::sample::{self, ProcPaths, Sample};
use crate::state::StateFile;

pub const WORKER: &str = "sysmon";

pub const HANDSHAKE: &str =
    "{\"ok\":true,\"worker\":\"sysmon\",\"version\":1,\"topics\":[\"sysmon\",\"cpu\",\"mem\",\"swap\",\"disk\",\"gpu\",\"temp\",\"llm\"]}";

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Topic {
    Sysmon,
    Cpu,
    Mem,
    Swap,
    Disk,
    Gpu,
    Temp,
    Llm,
}

impl Topic {
    pub const ALL: [Topic; 8] = [
        Topic::Sysmon,
        Topic::Cpu,
        Topic::Mem,
        Topic::Swap,
        Topic::Disk,
        Topic::Gpu,
        Topic::Temp,
        Topic::Llm,
    ];

    pub fn name(self) -> &'static str {
        match self {
            Topic::Sysmon => "sysmon",
            Topic::Cpu => "cpu",
            Topic::Mem => "mem",
            Topic::Swap => "swap",
            Topic::Disk => "disk",
            Topic::Gpu => "gpu",
            Topic::Temp => "temp",
            Topic::Llm => "llm",
        }
    }

    pub fn from_name(name: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|topic| topic.name() == name)
    }
}

#[derive(Clone, Debug)]
pub struct Config {
    pub interval_ms: u64,
    pub io_max_kibps: u64,
    pub gpu_path: Option<String>,
    pub temp_path: Option<String>,
    pub proc_paths: ProcPaths,
    /// `llama-swap`'s `/running` endpoint, when the caller wants the local
    /// model in the sample (the bar does; a plain sysmon does not).
    pub llm_url: Option<String>,
}

#[derive(Clone, Debug)]
struct Subscription {
    topic: Topic,
    interval_ms: u64,
    next_ms: u64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Control {
    Continue,
    Stop,
}

pub struct Session {
    config: Config,
    state: StateFile,
    subscriptions: Vec<Subscription>,
    last_sample_ms: u64,
    llm: Option<LlmProbe>,
}

impl Session {
    pub fn new(config: Config, state: StateFile, start_ms: u64) -> Self {
        let llm = config.llm_url.as_deref().and_then(LlmProbe::new);
        Self {
            config,
            state,
            subscriptions: Vec::new(),
            last_sample_ms: start_ms,
            llm,
        }
    }

    #[cfg(test)]
    pub fn state_path(&self) -> &std::path::Path {
        self.state.path()
    }

    /// The shell's auto-subscription: one full `sysmon` sample per
    /// `--interval-ms`, first due one interval after start-up.
    pub fn auto_subscribe(&mut self, start_ms: u64) {
        self.subscriptions.push(Subscription {
            topic: Topic::Sysmon,
            interval_ms: self.config.interval_ms,
            next_ms: start_ms.saturating_add(self.config.interval_ms),
        });
    }

    /// One event-loop pass: handle a line (when one arrived) and then emit
    /// every topic that is due. The shell ran `handle_command` and
    /// `emit_samples` in this order on every read, timeout or not.
    pub fn step<W: Write>(
        &mut self,
        line: Option<&str>,
        now_ms: u64,
        out: &mut W,
    ) -> io::Result<Control> {
        if let Some(line) = line {
            if !line.is_empty() {
                if self.handle_line(line, now_ms, out)? == Control::Stop {
                    return Ok(Control::Stop);
                }
            }
        }
        self.emit_due(now_ms, out)?;
        Ok(Control::Continue)
    }

    fn handle_line<W: Write>(
        &mut self,
        line: &str,
        now_ms: u64,
        out: &mut W,
    ) -> io::Result<Control> {
        let fields = match parse_fields(line) {
            Ok(fields) => fields,
            Err(()) => {
                write_error(out, "bad command line")?;
                return Ok(Control::Continue);
            }
        };

        match fields.cmd.as_str() {
            "subscribe" => {
                let Some(topic) = Topic::from_name(&fields.topic) else {
                    write_error(out, &format!("unknown topic: {}", fields.topic))?;
                    return Ok(Control::Continue);
                };
                let interval_text = if fields.interval.is_empty() {
                    self.subscription_interval(topic)
                        .unwrap_or(self.config.interval_ms)
                        .to_string()
                } else {
                    fields.interval.clone()
                };
                if interval_text.is_empty() || !is_digits(&interval_text) {
                    write_error(out, "interval_ms must be an integer")?;
                    return Ok(Control::Continue);
                }
                let Ok(interval_ms) = interval_text.parse::<u64>() else {
                    write_error(out, "interval_ms must be 100..60000")?;
                    return Ok(Control::Continue);
                };
                if !(100..=60000).contains(&interval_ms) {
                    write_error(out, "interval_ms must be 100..60000")?;
                    return Ok(Control::Continue);
                }
                self.set_subscription(topic, interval_ms);
                write_ack(out, "subscribe")?;
            }
            "unsubscribe" => {
                let Some(topic) = Topic::from_name(&fields.topic) else {
                    write_error(out, &format!("unknown topic: {}", fields.topic))?;
                    return Ok(Control::Continue);
                };
                self.subscriptions
                    .retain(|subscription| subscription.topic != topic);
                write_ack(out, "unsubscribe")?;
            }
            "set" => {
                if fields.interval.is_empty() {
                    write_error(out, "set needs interval_ms")?;
                    return Ok(Control::Continue);
                }
                if !is_digits(&fields.interval) {
                    write_error(out, "interval_ms must be an integer")?;
                    return Ok(Control::Continue);
                }
                let Ok(interval_ms) = fields.interval.parse::<u64>() else {
                    write_error(out, "interval_ms must be 100..60000")?;
                    return Ok(Control::Continue);
                };
                if !(100..=60000).contains(&interval_ms) {
                    write_error(out, "interval_ms must be 100..60000")?;
                    return Ok(Control::Continue);
                }
                for subscription in &mut self.subscriptions {
                    subscription.interval_ms = interval_ms;
                }
                write_ack(out, "set")?;
            }
            "sample" => {
                for subscription in &mut self.subscriptions {
                    subscription.next_ms = 0;
                }
                write_ack(out, "sample")?;
                self.emit_due(now_ms, out)?;
            }
            "stop" => {
                write_ack(out, "stop")?;
                return Ok(Control::Stop);
            }
            _ => {
                write_error(out, &format!("unknown cmd: {}", fields.cmd))?;
            }
        }
        Ok(Control::Continue)
    }

    fn subscription_interval(&self, topic: Topic) -> Option<u64> {
        self.subscriptions
            .iter()
            .find(|subscription| subscription.topic == topic)
            .map(|subscription| subscription.interval_ms)
    }

    fn set_subscription(&mut self, topic: Topic, interval_ms: u64) {
        if let Some(subscription) = self
            .subscriptions
            .iter_mut()
            .find(|subscription| subscription.topic == topic)
        {
            subscription.interval_ms = interval_ms;
            subscription.next_ms = 0;
        } else {
            self.subscriptions.push(Subscription {
                topic,
                interval_ms,
                next_ms: 0,
            });
        }
    }

    fn emit_due<W: Write>(&mut self, now_ms: u64, out: &mut W) -> io::Result<()> {
        let due: Vec<usize> = self
            .subscriptions
            .iter()
            .enumerate()
            .filter(|(_, subscription)| subscription.next_ms <= now_ms)
            .map(|(index, _)| index)
            .collect();
        if due.is_empty() {
            return Ok(());
        }

        let dt_ms = if self.last_sample_ms > 0 {
            now_ms as i64 - self.last_sample_ms as i64
        } else {
            1000
        };
        let ts_secs = crate::now_secs();

        match sample::sample(
            &self.config.proc_paths,
            self.state.path(),
            self.config.io_max_kibps,
            self.config.gpu_path.as_deref(),
            self.config.temp_path.as_deref(),
            dt_ms,
            self.config.interval_ms,
            ts_secs,
        ) {
            Ok(data) => {
                self.last_sample_ms = now_ms;
                let llm = self.llm.as_mut().map(|probe| probe.object(ts_secs));
                for index in due {
                    let interval_ms = self.subscriptions[index].interval_ms;
                    let topic = self.subscriptions[index].topic;
                    self.subscriptions[index].next_ms = now_ms.saturating_add(interval_ms);
                    write_sample(out, topic, now_ms, &data, llm.as_deref())?;
                }
            }
            Err(()) => write_sample_error(out, now_ms)?,
        }
        Ok(())
    }
}

struct Fields {
    cmd: String,
    topic: String,
    interval: String,
}

/// Reproduce the shell's jq round trip: it built
/// `[.cmd // "", .topic // "", ((.interval_ms // "") | tostring)] | join("|")`
/// and then let `IFS='|' read -r cmd topic interval` split the result. The
/// join/split is kept because a value containing `|` shifted the fields in the
/// shell too, and every reply must stay byte-identical.
fn parse_fields(line: &str) -> Result<Fields, ()> {
    let Some(value) = parse_first_value(line)? else {
        // jq reads a whitespace-only input as no value at all (exit 0, empty
        // output); the shell then answered with an empty command name.
        return Ok(Fields {
            cmd: String::new(),
            topic: String::new(),
            interval: String::new(),
        });
    };
    let map = match &value {
        serde_json::Value::Object(map) => Some(map),
        serde_json::Value::Null => None,
        _ => return Err(()),
    };
    let (cmd, topic, interval) = match map {
        Some(map) => (
            scalar_field(map.get("cmd"))?,
            scalar_field(map.get("topic"))?,
            interval_field(map.get("interval_ms")),
        ),
        None => (String::new(), String::new(), String::new()),
    };
    let joined = format!("{cmd}|{topic}|{interval}");
    let mut parts = joined.splitn(3, '|');
    let cmd = parts.next().unwrap_or_default().to_string();
    let topic = parts.next().unwrap_or_default().to_string();
    let interval = parts.next().unwrap_or_default().to_string();
    Ok(Fields {
        cmd,
        topic,
        interval,
    })
}

/// jq processes a *stream* of JSON values and stops at the first bad one; the
/// shell's `read` then used only the first output line. Parsing the whole
/// stream keeps both behaviours: valid multiple values are accepted, the first
/// one is used, and anything malformed is a bad command line.
fn parse_first_value(line: &str) -> Result<Option<serde_json::Value>, ()> {
    let mut stream = serde_json::Deserializer::from_str(line).into_iter::<serde_json::Value>();
    let Some(first) = stream.next() else {
        return Ok(None);
    };
    let first = first.map_err(|_| ())?;
    for value in stream {
        value.map_err(|_| ())?;
    }
    Ok(Some(first))
}

/// jq's `// ""` treats null and false as missing; a JSON object or array as
/// `cmd`/`topic` made the shell's `join` fail, which was a bad command line.
fn scalar_field(value: Option<&serde_json::Value>) -> Result<String, ()> {
    match value {
        None | Some(serde_json::Value::Null) | Some(serde_json::Value::Bool(false)) => {
            Ok(String::new())
        }
        Some(serde_json::Value::Bool(true)) => Ok("true".to_string()),
        Some(serde_json::Value::String(string)) => Ok(string.clone()),
        Some(serde_json::Value::Number(number)) => Ok(number_text(number)),
        Some(_) => Err(()),
    }
}

/// `(.interval_ms // "" | tostring)`: any JSON value became text, so an object
/// or array became its compact JSON form and then failed the digit check.
fn interval_field(value: Option<&serde_json::Value>) -> String {
    match value {
        None | Some(serde_json::Value::Null) | Some(serde_json::Value::Bool(false)) => {
            String::new()
        }
        Some(serde_json::Value::Bool(true)) => "true".to_string(),
        Some(serde_json::Value::String(string)) => string.clone(),
        Some(serde_json::Value::Number(number)) => number_text(number),
        Some(other) => serde_json::to_string(other).unwrap_or_default(),
    }
}

/// jq renders integers without a fraction and keeps a decimal point for floats
/// (`100.0` stays `100.0`), which makes a float fail the shell's digit check.
fn number_text(number: &serde_json::Number) -> String {
    if let Some(integer) = number.as_i64() {
        integer.to_string()
    } else if let Some(unsigned) = number.as_u64() {
        unsigned.to_string()
    } else {
        number.to_string()
    }
}

fn is_digits(value: &str) -> bool {
    !value.is_empty() && value.bytes().all(|byte| byte.is_ascii_digit())
}

fn write_ack<W: Write>(out: &mut W, ack: &str) -> io::Result<()> {
    writeln!(out, "{{\"ok\":true,\"ack\":\"{ack}\"}}")
}

fn write_error<W: Write>(out: &mut W, message: &str) -> io::Result<()> {
    writeln!(
        out,
        "{{\"ok\":false,\"err\":{}}}",
        sample::json_string(message)
    )
}

fn write_sample<W: Write>(
    out: &mut W,
    topic: Topic,
    t: u64,
    data: &Sample,
    llm: Option<&str>,
) -> io::Result<()> {
    let payload = match topic {
        // The full sample is pre-rendered; the LLM object rides beside the
        // other sections so a client that never asked for it pays nothing but
        // the bytes. `llm` as its own topic is the same object alone.
        Topic::Sysmon => match llm {
            Some(object) if data.full.ends_with('}') => {
                let mut full = data.full[..data.full.len() - 1].to_string();
                full.push_str(",\"llm\":");
                full.push_str(object);
                full.push('}');
                full
            }
            _ => data.full.clone(),
        },
        Topic::Llm => llm.unwrap_or("{\"active\":false}").to_string(),
        _ => data.data_for(topic.name()).to_string(),
    };
    writeln!(
        out,
        "{{\"ok\":true,\"worker\":\"{WORKER}\",\"topic\":\"{}\",\"t\":{},\"data\":{}}}",
        topic.name(),
        t,
        payload
    )
}

fn write_sample_error<W: Write>(out: &mut W, t: u64) -> io::Result<()> {
    writeln!(
        out,
        "{{\"ok\":false,\"worker\":\"{WORKER}\",\"err\":\"cannot read /proc/stat or /proc/meminfo\",\"t\":{t}}}"
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testutil::{write_file, TempDir};
    use std::fs;

    struct Fixture {
        _directory: TempDir,
        config: Config,
    }

    fn fixture(label: &str) -> Fixture {
        let directory = TempDir::new(label);
        let stat = write_file(
            directory.path(),
            "stat",
            "cpu  100 20 30 400 50 10 5 5 0 0\n",
        );
        let meminfo = write_file(
            directory.path(),
            "meminfo",
            "MemTotal: 8000000 kB\nMemAvailable: 2000000 kB\n",
        );
        let swaps = write_file(
            directory.path(),
            "swaps",
            "Filename Type Size Used Priority\n/swapfile file 1000000 250000 -2\n",
        );
        let diskstats = write_file(
            directory.path(),
            "diskstats",
            "8 0 sda 10 0 1000 0 10 0 2000 0 0 0 0\n",
        );
        let gpu = write_file(directory.path(), "gpu", "37\n");
        let temp = write_file(directory.path(), "temp", "45000\n");
        Fixture {
            config: Config {
                interval_ms: 60000,
                io_max_kibps: 512000,
                gpu_path: Some(gpu.to_string_lossy().into_owned()),
                temp_path: Some(temp.to_string_lossy().into_owned()),
                proc_paths: ProcPaths {
                    stat,
                    meminfo,
                    swaps,
                    diskstats,
                },
                llm_url: None,
            },
            _directory: directory,
        }
    }

    fn session(fixture: &Fixture) -> Session {
        let state = StateFile::create_in(fixture._directory.path()).expect("state");
        Session::new(fixture.config.clone(), state, 0)
    }

    fn run(session: &mut Session, lines: &[&str], first_now: u64) -> (Vec<String>, Control) {
        let mut output = Vec::new();
        let mut control = Control::Continue;
        let mut now = first_now;
        for line in lines {
            control = session
                .step(Some(line), now, &mut output)
                .expect("write to vec");
            now += 10;
            if control == Control::Stop {
                break;
            }
        }
        let text = String::from_utf8(output).expect("utf8");
        (text.lines().map(|line| line.to_string()).collect(), control)
    }

    #[test]
    fn handshake_is_the_frozen_line() {
        assert_eq!(
            HANDSHAKE,
            "{\"ok\":true,\"worker\":\"sysmon\",\"version\":1,\"topics\":[\"sysmon\",\"cpu\",\"mem\",\"swap\",\"disk\",\"gpu\",\"temp\",\"llm\"]}"
        );
    }

    #[test]
    fn bad_lines_and_unknown_commands_are_answered() {
        let fixture = fixture("command-bad");
        let mut session = session(&fixture);
        let (lines, control) = run(
            &mut session,
            &[
                "not json",
                "   ",
                "{}",
                "{} {}",
                "{",
                "null",
                "[]",
                "123",
                "\"text\"",
                "{\"cmd\":\"bogus\"}",
                "{\"cmd\":0}",
                "{\"cmd\":false}",
            ],
            1000,
        );
        assert_eq!(control, Control::Continue);
        assert_eq!(
            lines,
            vec![
                r#"{"ok":false,"err":"bad command line"}"#,
                r#"{"ok":false,"err":"unknown cmd: "}"#,
                r#"{"ok":false,"err":"unknown cmd: "}"#,
                r#"{"ok":false,"err":"unknown cmd: "}"#,
                r#"{"ok":false,"err":"bad command line"}"#,
                r#"{"ok":false,"err":"unknown cmd: "}"#,
                r#"{"ok":false,"err":"bad command line"}"#,
                r#"{"ok":false,"err":"bad command line"}"#,
                r#"{"ok":false,"err":"bad command line"}"#,
                r#"{"ok":false,"err":"unknown cmd: bogus"}"#,
                r#"{"ok":false,"err":"unknown cmd: 0"}"#,
                r#"{"ok":false,"err":"unknown cmd: "}"#,
            ]
        );
    }

    #[test]
    fn subscribe_unsubscribe_and_set_acknowledge_like_the_shell() {
        let fixture = fixture("command-acks");
        let mut session = session(&fixture);
        let (lines, control) = run(
            &mut session,
            &[
                r#"{"cmd":"subscribe","topic":"cpu","interval_ms":1000}"#,
                r#"{"cmd":"set","interval_ms":250}"#,
                r#"{"cmd":"unsubscribe","topic":"cpu"}"#,
                r#"{"cmd":"unsubscribe","topic":"sysmon"}"#,
                r#"{"cmd":"set","interval_ms":100}"#,
            ],
            1000,
        );
        assert_eq!(control, Control::Continue);
        // The first step emits the cpu sample because subscribe set next=0;
        // every other ack is plain. The cpu sample is the only non-ack line.
        let acks: Vec<&String> = lines
            .iter()
            .filter(|line| !line.contains("\"topic\""))
            .collect();
        assert_eq!(
            acks,
            vec![
                r#"{"ok":true,"ack":"subscribe"}"#,
                r#"{"ok":true,"ack":"set"}"#,
                r#"{"ok":true,"ack":"unsubscribe"}"#,
                r#"{"ok":true,"ack":"unsubscribe"}"#,
                r#"{"ok":true,"ack":"set"}"#,
            ]
        );
        assert_eq!(
            lines
                .iter()
                .filter(|line| line.contains("\"topic\":\"cpu\""))
                .count(),
            1
        );
    }

    #[test]
    fn errors_match_the_shell_exactly() {
        let fixture = fixture("command-errors");
        let mut session = session(&fixture);
        let (lines, _) = run(
            &mut session,
            &[
                r#"{"cmd":"subscribe","topic":"nope"}"#,
                r#"{"cmd":"unsubscribe","topic":"nope"}"#,
                r#"{"cmd":"subscribe","topic":"cpu","interval_ms":50}"#,
                r#"{"cmd":"subscribe","topic":"cpu","interval_ms":60001}"#,
                r#"{"cmd":"subscribe","topic":"cpu","interval_ms":"x"}"#,
                r#"{"cmd":"subscribe","topic":"cpu","interval_ms":100.0}"#,
                r#"{"cmd":"set"}"#,
                r#"{"cmd":"set","interval_ms":"x"}"#,
                r#"{"cmd":"set","interval_ms":50}"#,
            ],
            1000,
        );
        assert_eq!(
            lines,
            vec![
                r#"{"ok":false,"err":"unknown topic: nope"}"#,
                r#"{"ok":false,"err":"unknown topic: nope"}"#,
                r#"{"ok":false,"err":"interval_ms must be 100..60000"}"#,
                r#"{"ok":false,"err":"interval_ms must be 100..60000"}"#,
                r#"{"ok":false,"err":"interval_ms must be an integer"}"#,
                r#"{"ok":false,"err":"interval_ms must be an integer"}"#,
                r#"{"ok":false,"err":"set needs interval_ms"}"#,
                r#"{"ok":false,"err":"interval_ms must be an integer"}"#,
                r#"{"ok":false,"err":"interval_ms must be 100..60000"}"#,
            ]
        );
    }

    #[test]
    fn subscribe_without_interval_uses_the_current_or_default_cadence() {
        let fixture = fixture("command-default-interval");
        let mut session = session(&fixture);
        let (lines, _) = run(
            &mut session,
            &[
                r#"{"cmd":"subscribe","topic":"cpu"}"#,
                r#"{"cmd":"subscribe","topic":"cpu","interval_ms":250}"#,
                r#"{"cmd":"subscribe","topic":"cpu"}"#,
            ],
            1000,
        );
        assert!(lines[0].contains("\"ack\":\"subscribe\""));
        assert!(lines.iter().any(|line| line.contains("\"topic\":\"cpu\"")));
        // The second subscribe without an interval re-used the 250 config?
        // No: `--interval-ms` is the config default; the shell's
        // `${SUB_INTERVAL[$topic]:-...}` uses the topic's current cadence.
        assert_eq!(
            session
                .subscription_interval(Topic::Cpu)
                .expect("subscribed"),
            250
        );
    }

    #[test]
    fn sample_acks_then_emits_the_full_sysmon_object() {
        let fixture = fixture("command-sample");
        let mut session = session(&fixture);
        session.auto_subscribe(1000);
        let mut output = Vec::new();
        session
            .step(Some(r#"{"cmd":"sample"}"#), 2000, &mut output)
            .expect("write");
        let text = String::from_utf8(output).expect("utf8");
        let lines: Vec<&str> = text.lines().collect();
        assert_eq!(lines[0], r#"{"ok":true,"ack":"sample"}"#);
        assert!(lines[1].starts_with(
            "{\"ok\":true,\"worker\":\"sysmon\",\"topic\":\"sysmon\",\"t\":2000,\"data\":{\"ts\":"
        ));
        assert!(lines[1].contains(
            "\"cpu\":{\"percent\":0.0}, \"mem\":{\"used_gib\":5.72,\"total_gib\":7.63,\"percent\":75.0}"
        ));
    }

    #[test]
    fn auto_subscription_emits_after_one_interval() {
        let fixture = fixture("command-auto");
        let mut session = session(&fixture);
        session.auto_subscribe(1000);
        let mut output = Vec::new();
        session.step(None, 60_999, &mut output).expect("write");
        assert!(output.is_empty(), "not due before interval elapsed");
        session.step(None, 61_000, &mut output).expect("write");
        let text = String::from_utf8(output).expect("utf8");
        assert!(text.contains("\"topic\":\"sysmon\""));
    }

    #[test]
    fn subtopics_carry_only_their_object() {
        let fixture = fixture("command-subtopics");
        let mut session = session(&fixture);
        let mut output = Vec::new();
        session
            .step(
                Some(r#"{"cmd":"subscribe","topic":"temp","interval_ms":1000}"#),
                1000,
                &mut output,
            )
            .expect("write");
        let text = String::from_utf8(output).expect("utf8");
        let sample_line = text
            .lines()
            .find(|line| line.contains("\"topic\":\"temp\""))
            .expect("temp sample");
        assert!(sample_line.ends_with("\"t\":1000,\"data\":{\"celsius\":45.0,\"percent\":21.4}}"));
    }

    #[test]
    fn stop_acks_and_stops() {
        let fixture = fixture("command-stop");
        let mut session = session(&fixture);
        let (lines, control) = run(
            &mut session,
            &[r#"{"cmd":"stop"}"#, r#"{"cmd":"sample"}"#],
            1000,
        );
        assert_eq!(control, Control::Stop);
        assert_eq!(lines, vec![r#"{"ok":true,"ack":"stop"}"#]);
    }

    #[test]
    fn empty_lines_are_ignored_but_still_poll() {
        let fixture = fixture("command-empty");
        let mut session = session(&fixture);
        session.auto_subscribe(0);
        let (lines, _) = run(&mut session, &["", ""], 60_000);
        assert_eq!(lines.len(), 1);
        assert!(lines[0].contains("\"topic\":\"sysmon\""));
    }

    #[test]
    fn closed_stdin_is_the_callers_concern_but_state_is_removed_on_drop() {
        let fixture = fixture("command-cleanup");
        let state_path;
        {
            let session = session(&fixture);
            state_path = session.state_path().to_path_buf();
            assert!(state_path.exists());
        }
        assert!(!state_path.exists());
        assert!(fs::metadata(&state_path).is_err());
    }

    #[test]
    fn failed_sample_keeps_the_topic_due() {
        let fixture = fixture("command-retry");
        let mut session = session(&fixture);
        fs::remove_file(&fixture.config.proc_paths.stat).expect("remove stat");
        session.auto_subscribe(0);
        let mut output = Vec::new();
        session.step(None, 60_000, &mut output).expect("write");
        let text = String::from_utf8(output).expect("utf8");
        assert!(text.contains(
            "{\"ok\":false,\"worker\":\"sysmon\",\"err\":\"cannot read /proc/stat or /proc/meminfo\",\"t\":60000}"
        ));
    }

    #[test]
    fn pipe_in_a_field_shifts_the_shell_fields() {
        // The shell joined with "|" and split again: a topic containing "|"
        // becomes the interval. Keep the same (strange) reply.
        let fixture = fixture("command-pipe");
        let mut session = session(&fixture);
        let (lines, _) = run(
            &mut session,
            &[r#"{"cmd":"subscribe","topic":"cpu|x"}"#],
            1000,
        );
        assert_eq!(
            lines,
            vec![r#"{"ok":false,"err":"interval_ms must be an integer"}"#]
        );
    }
}
