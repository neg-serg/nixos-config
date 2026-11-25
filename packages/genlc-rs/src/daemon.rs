//! `genlc daemon` — the one process that owns the GLM adapter.
//!
//! GLM's own model is a host that never stops talking: it probes for unleased
//! monitors, polls each leased one and the adapter's status about twice a second, and
//! a monitor drops its lease ~2.5 s after the last answer it gave (protocol.md,
//! "When a monitor loses its lease"). A CLI that runs once cannot hold that state, so
//! the daemon keeps the cycle and serves it over a Unix socket. It is a subcommand of
//! `genlc` rather than a binary of its own: the adapter has one owner and one name.
//!
//! Socket protocol: one command per line, one reply line each (`ok …` / `error …`).
//! ```text
//! status            -> JSON: adapter state, leases, telemetry, volume, cycle count
//! volume -30.5      -> apply the system volume (broadcast 1F), then answer
//!                      `ok volume -30.5 dB` or `error …`
//! mute on|off       -> mute-all / unmute-all through the adapter (01 2B 01/00), then
//!                      answer `ok mute on` or `error …`
//! lease             -> force a probe cycle now
//! apply PATH        -> write a plan file through the daemon's own leases
//! quit              -> stop the daemon
//! ```
//!
//! The adapter is opened once and owned for the daemon's lifetime; a USB reset (the
//! GLM adapter re-enumerates on its own) leaves that handle dead, so `Link` drops it,
//! reopens on a one-second retry and clears the leases that belonged to the old
//! handle. Without that, every frame failed with `hidapi error: No such device` until
//! the service was restarted by hand (2026-11-23: 4.7k identical journal lines, and
//! the volume CLI wrote its state file while the write to the dead handle failed).

use crate::plan::{parse_plan, plan_frames};
use crate::protocol;
use anyhow::{Context, Result};
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::PathBuf;
use std::sync::mpsc::{self, Sender};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

/// GLM's idle cycle: probe + volume + one poll per monitor, about every 0.57 s
/// (measured on this host: 0.552-0.568 s).
const CYCLE: Duration = Duration::from_millis(560);
/// A lease lapses ~2.5 s after the monitor's last answer, so a cycle must never be
/// skipped by more than that.
const LEASE_GRACE: Duration = Duration::from_millis(1500);
/// Retry interval for reopening the adapter after a transport error. The handle is
/// cheap to open and the lease window is longer than this, so a re-enumerating device
/// is picked up inside one monitor lease period.
const REOPEN_DELAY: Duration = Duration::from_millis(1000);
/// While the adapter stays away, repeat the reason once a minute instead of on every
/// 0.56 s cycle: the first version wrote 4.7k identical lines into the journal in
/// forty-five minutes and buried everything else.
const LOST_LOG_EVERY: Duration = Duration::from_secs(60);

#[derive(Default)]
struct State {
    leases: Vec<protocol::Lease>,
    /// Last telemetry frame per session, as raw bytes — the tag layout is not settled
    /// enough to decode into fields (see the plan, telemetry section).
    telemetry: std::collections::BTreeMap<u8, Vec<u8>>,
    volume_db: Option<f64>,
    /// Whether the last mute round the daemon sent was `on`; `None` until one was
    /// sent this run. `genlc mute toggle` reads it back from `status`.
    muted: Option<bool>,
    /// Whether the adapter handle is missing right now. `status` reports it so the
    /// bar and a person can tell "the monitors are quiet" from "the daemon is blind".
    adapter_lost: bool,
    cycles: u64,
    last_cycle: Option<Instant>,
}

impl State {
    fn to_json(&self) -> String {
        let leases: Vec<String> = self
            .leases
            .iter()
            .map(|l| {
                format!(
                    "{{\"hardware_id\":\"{:02X}{:02X}{:02X}\",\"session\":{}}}",
                    l.hardware_id[0], l.hardware_id[1], l.hardware_id[2], l.session
                )
            })
            .collect();
        let telemetry: Vec<String> = self
            .telemetry
            .iter()
            .map(|(s, d)| {
                let hex: Vec<String> = d.iter().map(|b| format!("{b:02X}")).collect();
                format!("\"{s:02X}\":\"{}\"", hex.join(" "))
            })
            .collect();
        format!(
            "{{\"cycles\":{},\"adapter\":\"{}\",\"volume_db\":{},\"muted\":{},\"leases\":[{}],\"telemetry\":{{{}}}}}",
            self.cycles,
            if self.adapter_lost { "lost" } else { "ok" },
            self.volume_db
                .map(|v| format!("{v:.1}"))
                .unwrap_or_else(|| "null".into()),
            self.muted
                .map(|m| m.to_string())
                .unwrap_or_else(|| "null".into()),
            leases.join(","),
            telemetry.join(",")
        )
    }
}

enum Cmd {
    /// Set the level. The reply carries the outcome once the frame is on the bus —
    /// the socket must not answer `ok` for a write that failed.
    Volume(f64, Sender<String>),
    /// Mute or unmute, with the same reply contract as `Volume`.
    Mute(bool, Sender<String>),
    LeaseNow,
    /// Apply a plan file; the daemon answers through the channel once the block is on
    /// the bus, because only the loop thread owns the transport.
    Apply(std::path::PathBuf, Sender<String>),
    Quit,
}

pub fn run(socket: Option<PathBuf>) -> Result<()> {
    let socket = socket.unwrap_or_else(|| PathBuf::from(format!("{}/genlc.sock", runtime_dir())));

    let state = Arc::new(Mutex::new(State::default()));
    let mut link = Link::new(&state);

    // Remove a socket left behind by a previous run; the daemon owns this path.
    let _ = std::fs::remove_file(&socket);
    if let Some(dir) = socket.parent() {
        std::fs::create_dir_all(dir).ok();
    }
    let listener = UnixListener::bind(&socket)
        .with_context(|| format!("binding the control socket {}", socket.display()))?;
    eprintln!("genlc daemon listening on {}", socket.display());

    let (tx, rx) = mpsc::channel::<Cmd>();
    {
        let tx = tx.clone();
        let state = Arc::clone(&state);
        std::thread::spawn(move || accept_loop(listener, tx, state));
    }

    let mut last_lease = Instant::now();
    let mut next_cycle = Instant::now();
    loop {
        // Commands first, and at once: this thread owns the transport, so a volume or
        // mute waits only for its write, not for the 0.56 s cycle. The CLI writes the
        // state file the bar follows after this reply, so the cycle must not sit
        // between a keystroke and its ack.
        while let Ok(cmd) = rx.try_recv() {
            if !handle_command(cmd, &mut link, &state, &mut last_lease, &socket) {
                return Ok(());
            }
        }

        // Bus work at GLM's idle rate. While the adapter is away the socket stays up
        // and `status` reports `adapter: lost`; the retry clock lives in `Link`, so a
        // device that is away for an hour costs one journal line a minute.
        if Instant::now() >= next_cycle {
            if !link.reconnect(&state) {
                state.lock().unwrap().cycles += 1;
            } else {
                let mut dead: Option<anyhow::Error> = None;
                if let Some(group) = link.group() {
                    // Re-lease when the previous leases are about to lapse; the probes are cheap
                    // and a monitor that already holds our lease simply does not answer them.
                    if last_lease.elapsed() >= LEASE_GRACE
                        || state.lock().unwrap().leases.is_empty()
                    {
                        match group.take_leases() {
                            Ok(leases) => {
                                let mut st = state.lock().unwrap();
                                if !leases.is_empty() {
                                    st.leases = leases;
                                }
                                drop(st);
                                last_lease = Instant::now();
                            }
                            Err(error) => {
                                // A protocol surprise on a live bus is one log line; a stream that
                                // stopped answering means the handle is gone and must be replaced.
                                if transport_dead(&error) {
                                    dead = Some(error.context("lease cycle failed"));
                                } else {
                                    eprintln!("genlc daemon: lease cycle failed: {error}");
                                }
                            }
                        }
                    }

                    if dead.is_none() {
                        // Poll every session we hold, and the adapter's own status, so both keep
                        // answering — this is the traffic GLM generates, and it is what keeps the
                        // monitors from dropping their leases.
                        let sessions: Vec<u8> = state
                            .lock()
                            .unwrap()
                            .leases
                            .iter()
                            .map(|l| l.session)
                            .collect();
                        for session in sessions {
                            // Strict one reply per request: a poll left unanswered would be consumed
                            // by the next request and shift every answer by one (seen in the
                            // 2026-11-02 capture: a probe answered by the adapter's status frame).
                            // A single slow monitor is not a dead bus — the lease cycle is the probe
                            // that decides that — so these errors stay ignored.
                            match group.send_and_receive(&protocol::GNetMessage::new(session, 0x08))
                            {
                                Ok(frame) if frame.opcode == 0x09 && !frame.data.is_empty() => {
                                    state
                                        .lock()
                                        .unwrap()
                                        .telemetry
                                        .insert(session, frame.data.clone());
                                }
                                _ => {}
                            }
                        }
                        // The adapter answers its own status poll; read that reply here so it
                        // cannot be mistaken for the next cycle's first monitor report (it arrives
                        // as `32 34 DE …`, the mic/knob tags, and used to be filed under a
                        // monitor's session).
                        let _ = group.send_and_receive(&protocol::GNetMessage::new(0x01, 0x08));
                    }
                }
                if let Some(error) = dead {
                    link.lose(&error, &state);
                }

                {
                    let mut st = state.lock().unwrap();
                    st.cycles += 1;
                    st.last_cycle = Some(Instant::now());
                }
            }
            next_cycle = Instant::now() + CYCLE;
        }

        // Sleep out the cycle, but wake for a command: a notch handled above lands in
        // milliseconds instead of after the sleep.
        let wait = next_cycle.saturating_duration_since(Instant::now());
        if wait.is_zero() {
            continue;
        }
        if let Ok(cmd) = rx.recv_timeout(wait) {
            if !handle_command(cmd, &mut link, &state, &mut last_lease, &socket) {
                return Ok(());
            }
        }
    }
}

/// Handle one socket command in the loop thread, the only owner of the transport.
/// Returns false when the daemon has to stop.
fn handle_command(
    cmd: Cmd,
    link: &mut Link,
    state: &Arc<Mutex<State>>,
    last_lease: &mut Instant,
    socket: &std::path::Path,
) -> bool {
    match cmd {
        Cmd::Quit => {
            eprintln!("genlc daemon: quit");
            let _ = std::fs::remove_file(socket);
            return false;
        }
        Cmd::Volume(db, reply) => {
            let _ = reply.send(link.volume(db, state));
        }
        Cmd::Mute(on, reply) => {
            let _ = reply.send(link.mute(on, state));
        }
        Cmd::LeaseNow => *last_lease = Instant::now() - LEASE_GRACE,
        Cmd::Apply(path, reply) => {
            let summary = match link.group() {
                Some(group) => apply_plan(group, state, &path),
                None => "error adapter is not available (reconnecting); plan not sent".into(),
            };
            let _ = reply.send(summary);
        }
    }
    true
}

/// The adapter handle, plus the retry clock for getting it back.
///
/// `HidTransport::open` used to run once per daemon start, but the GLM adapter
/// re-enumerates on its own (2026-11-23: twice in twenty minutes, the USB node went
/// away and came back on a new device number). A handle from before the reset answers
/// every frame with `hidapi error: No such device` forever, so a transport error drops
/// it here and the loop reopens on a one-second retry. Leases and telemetry belong to
/// the old handle and go with it; the next cycle probes from scratch.
struct Link {
    group: Option<protocol::SamGroup>,
    /// Earliest moment for the next open attempt after a loss.
    retry_at: Instant,
    /// When the "adapter is away" line last went to the journal (log throttle).
    last_log: Instant,
}

impl Link {
    fn new(state: &Arc<Mutex<State>>) -> Self {
        let mut link = Self {
            group: None,
            retry_at: Instant::now(),
            last_log: Instant::now(),
        };
        // Starting without the adapter is not fatal: the socket still answers `status`
        // with `adapter: lost` and the retry loop picks the device up whenever it
        // appears, instead of systemd restarting a process that can do nothing yet.
        link.attempt(state, true);
        link
    }

    fn group(&self) -> Option<&protocol::SamGroup> {
        self.group.as_ref()
    }

    /// One open attempt, logging at most once per `LOST_LOG_EVERY` unless `startup`
    /// (the first attempt must leave its reason in the journal).
    fn attempt(&mut self, state: &Arc<Mutex<State>>, startup: bool) -> bool {
        self.retry_at = Instant::now() + REOPEN_DELAY;
        match protocol::HidTransport::open() {
            Ok(transport) => {
                self.group = Some(protocol::SamGroup::new(transport));
                let was_lost = {
                    let mut st = state.lock().unwrap();
                    let was_lost = st.adapter_lost;
                    st.adapter_lost = false;
                    was_lost
                };
                if was_lost {
                    eprintln!("genlc daemon: adapter back");
                }
                true
            }
            Err(error) => {
                if startup || self.last_log.elapsed() >= LOST_LOG_EVERY {
                    eprintln!(
                        "genlc daemon: adapter not available: {error}; retrying every {} ms",
                        REOPEN_DELAY.as_millis()
                    );
                    self.last_log = Instant::now();
                }
                let mut st = state.lock().unwrap();
                st.adapter_lost = true;
                st.leases.clear();
                st.telemetry.clear();
                false
            }
        }
    }

    /// True once the bus is usable; opens the adapter when the retry timer is due.
    fn reconnect(&mut self, state: &Arc<Mutex<State>>) -> bool {
        if self.group.is_some() {
            return true;
        }
        if Instant::now() < self.retry_at {
            return false;
        }
        self.attempt(state, false)
    }

    /// Drop a handle that stopped answering and schedule the next open attempt.
    fn lose(&mut self, reason: &anyhow::Error, state: &Arc<Mutex<State>>) {
        let had_handle = self.group.take().is_some();
        if had_handle || self.last_log.elapsed() >= LOST_LOG_EVERY {
            eprintln!(
                "genlc daemon: adapter lost: {reason:#}; reopening every {} ms",
                REOPEN_DELAY.as_millis()
            );
            self.last_log = Instant::now();
        }
        self.retry_at = Instant::now();
        let mut st = state.lock().unwrap();
        st.adapter_lost = true;
        // Leases are sessions on the old handle: the monitors may have re-enumerated
        // under new ones, so the next cycle has to probe rather than poll ghosts.
        st.leases.clear();
        st.telemetry.clear();
    }

    /// Apply a level and answer the socket with what actually happened. The old
    /// `ok queued` reply let the CLI write its state file and move the bar while the
    /// write to a dead handle failed in the loop thread.
    fn volume(&mut self, db: f64, state: &Arc<Mutex<State>>) -> String {
        let result = match self.group() {
            Some(group) => group.set_volume(db),
            None => return "error adapter is not available (reconnecting); volume not sent".into(),
        };
        match result {
            Ok(()) => {
                state.lock().unwrap().volume_db = Some(db);
                eprintln!("genlc daemon: volume {db:.1} dB");
                format!("ok volume {db:.1} dB")
            }
            Err(error) => {
                if transport_dead(&error) {
                    self.lose(&error, state);
                }
                eprintln!("genlc daemon: volume failed: {error}");
                format!("error volume failed: {error}")
            }
        }
    }

    /// Mute or unmute and answer the socket with the outcome.
    fn mute(&mut self, on: bool, state: &Arc<Mutex<State>>) -> String {
        let result = match self.group() {
            Some(group) => {
                if on {
                    group.mute()
                } else {
                    group.unmute()
                }
            }
            None => return "error adapter is not available (reconnecting); mute not sent".into(),
        };
        if let Err(error) = result {
            if transport_dead(&error) {
                self.lose(&error, state);
            }
            eprintln!("genlc daemon: mute failed: {error}");
            return format!("error mute failed: {error}");
        }
        // The state `status` reports (and `genlc mute toggle` reads): only what this
        // daemon actually sent this run.
        state.lock().unwrap().muted = Some(on);
        // GLM follows the adapter frame with a round to every leased session: the
        // session's `2B` carries bit 0 (mute) plus the LED colour, and that is the
        // frame the monitors act on (capture 2026-11-02: `2B 03` muted, `2B 04`
        // unmuted, sent after `01 2B 01` / `01 2B 00` to the adapter).
        let sessions: Vec<u8> = state
            .lock()
            .unwrap()
            .leases
            .iter()
            .map(|lease| lease.session)
            .collect();
        let value = if on { 0x03u8 } else { 0x04u8 };
        if let Some(group) = self.group() {
            for session in sessions {
                let msg = protocol::GNetMessage::new(session, 0x2B).with_data(vec![value]);
                if let Err(error) = group.send(&msg) {
                    eprintln!("genlc daemon: mute round to session {session:02} failed: {error}");
                }
            }
        }
        eprintln!("genlc daemon: mute {on}");
        format!("ok mute {}", if on { "on" } else { "off" })
    }
}

/// Whether an error means the HID stream is gone (dead handle, silent device) rather
/// than a protocol-level surprise on a live bus. Only the former justifies dropping
/// and reopening the handle: a monitor whose ack was lost must not cost the whole bus.
fn transport_dead(error: &anyhow::Error) -> bool {
    if error.downcast_ref::<hidapi::HidError>().is_some() {
        return true;
    }
    // `receive()` reports a silent device with its own messages (no bytes, or a report
    // short of the 64-byte frame); both mean the stream is not healthy.
    let text = format!("{error:#}");
    text.contains("Short HID read") || text.contains("Unexpected segment header")
}

/// Write one plan file to the monitors this daemon holds leases on.
///
/// Refuses any session the daemon does not hold: those frames would land on whatever
/// monitor currently owns it. Frames are paced because the bus allows one request in
/// flight and a monitor answers in ~7 ms — blasting a block lost most of the
/// acknowledgements in the 2026-11-02 hardware test.
fn apply_plan(
    group: &protocol::SamGroup,
    state: &Arc<Mutex<State>>,
    path: &std::path::Path,
) -> String {
    let text = match std::fs::read_to_string(path) {
        Ok(text) => text,
        Err(e) => return format!("error reading plan {}: {e}", path.display()),
    };
    let plans = match parse_plan(&text) {
        Ok(plans) => plans,
        Err(e) => return format!("error in plan: {e}"),
    };
    let leased: Vec<u8> = state
        .lock()
        .unwrap()
        .leases
        .iter()
        .map(|l| l.session)
        .collect();
    let mut out = Vec::new();
    for monitor_plan in &plans {
        if !leased.contains(&monitor_plan.session) {
            out.push(format!(
                "error session {:02X} is not leased by genlc daemon (held: {:02X?})",
                monitor_plan.session, leased
            ));
            continue;
        }
        let frames = plan_frames(monitor_plan);
        let mut acks = 0usize;
        let mut failed = None;
        for frame in &frames {
            if let Err(e) = group.send(frame) {
                failed = Some(format!("error send failed: {e}"));
                break;
            }
            std::thread::sleep(std::time::Duration::from_millis(12));
            if let Some(reply) = group.try_receive() {
                if reply.get(1) == Some(&0x09) {
                    acks += 1;
                }
            }
        }
        match failed {
            Some(e) => out.push(e),
            None => out.push(format!(
                "ok applied {} frames to session {:02X} ({acks} acknowledged)",
                frames.len(),
                monitor_plan.session
            )),
        }
    }
    out.join("; ")
}

fn runtime_dir() -> String {
    std::env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/run/user/1000".into())
}

fn accept_loop(listener: UnixListener, tx: Sender<Cmd>, state: Arc<Mutex<State>>) {
    for stream in listener.incoming().flatten() {
        let tx = tx.clone();
        let state = Arc::clone(&state);
        std::thread::spawn(move || {
            if let Err(e) = serve(stream, tx, state) {
                eprintln!("genlc daemon: client error: {e}");
            }
        });
    }
}

fn serve(stream: UnixStream, tx: Sender<Cmd>, state: Arc<Mutex<State>>) -> Result<()> {
    let mut out = stream.try_clone()?;
    for line in BufReader::new(stream).lines() {
        let line = line?;
        let mut parts = line.split_whitespace();
        match parts.next().unwrap_or_default() {
            "status" => {
                writeln!(out, "{}", state.lock().unwrap().to_json())?;
            }
            "volume" => {
                let db: f64 = parts.next().context("volume needs dB")?.parse()?;
                let (reply_tx, reply_rx) = mpsc::channel::<String>();
                tx.send(Cmd::Volume(db, reply_tx))?;
                // The loop thread applies the level before answering, so the reply is
                // the outcome, not a queue confirmation. The timeout only guards a
                // wedged bus: the loop checks the channel once per 0.56 s cycle.
                match reply_rx.recv_timeout(Duration::from_secs(10)) {
                    Ok(summary) => writeln!(out, "{summary}")?,
                    Err(_) => writeln!(out, "error volume timed out waiting for the adapter")?,
                }
            }
            "mute" => {
                let on = matches!(parts.next(), Some("on") | Some("1") | Some("true"));
                let (reply_tx, reply_rx) = mpsc::channel::<String>();
                tx.send(Cmd::Mute(on, reply_tx))?;
                match reply_rx.recv_timeout(Duration::from_secs(10)) {
                    Ok(summary) => writeln!(out, "{summary}")?,
                    Err(_) => writeln!(out, "error mute timed out waiting for the adapter")?,
                }
            }
            "lease" => {
                tx.send(Cmd::LeaseNow)?;
                writeln!(out, "ok queued")?;
            }
            "apply" => {
                let path =
                    std::path::PathBuf::from(parts.next().context("apply needs a plan path")?);
                let (reply_tx, reply_rx) = mpsc::channel::<String>();
                tx.send(Cmd::Apply(path, reply_tx))?;
                match reply_rx.recv_timeout(Duration::from_secs(60)) {
                    Ok(summary) => writeln!(out, "{summary}")?,
                    Err(_) => writeln!(out, "error apply timed out")?,
                }
            }
            "quit" => {
                tx.send(Cmd::Quit)?;
                writeln!(out, "ok bye")?;
                return Ok(());
            }
            other => writeln!(out, "error unknown command {other:?}")?,
        }
        out.flush().ok();
    }
    Ok(())
}
