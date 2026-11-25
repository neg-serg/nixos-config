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
