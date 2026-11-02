//! glm5d — the one process that owns the GLM adapter.
//!
//! GLM's own model is a host that never stops talking: it probes for unleased
//! monitors, polls each leased one and the adapter's status about twice a second, and
//! a monitor drops its lease ~2.5 s after the last answer it gave (protocol.md,
//! "When a monitor loses its lease"). A CLI that runs once cannot hold that state, so
//! this daemon keeps the cycle and serves the state over a Unix socket.
//!
//! Socket protocol: one command per line, one reply line each (`ok …` / `error …`).
//! ```text
//! status            -> JSON: leases, per-session telemetry, volume, cycle count
//! volume -30.5      -> set the system volume (broadcast 1F)
//! mute on|off       -> mute-all / unmute-all through the adapter (01 2B 01/00)
//! lease             -> force a probe cycle now
//! quit              -> stop the daemon
//! ```

use anyhow::{Context, Result};
use genlc::plan::{parse_plan, plan_frames};
use genlc::protocol;
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::sync::mpsc::{self, Receiver, Sender, TryRecvError};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

/// GLM's idle cycle: probe + volume + one poll per monitor, about every 0.57 s
/// (measured on this host: 0.552-0.568 s).
const CYCLE: Duration = Duration::from_millis(560);
/// A lease lapses ~2.5 s after the monitor's last answer, so a cycle must never be
/// skipped by more than that.
const LEASE_GRACE: Duration = Duration::from_millis(1500);

#[derive(Default)]
struct State {
    leases: Vec<protocol::Lease>,
    /// Last telemetry frame per session, as raw bytes — the tag layout is not settled
    /// enough to decode into fields (see the plan, telemetry section).
    telemetry: std::collections::BTreeMap<u8, Vec<u8>>,
    volume_db: Option<f64>,
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
            "{{\"cycles\":{},\"volume_db\":{},\"leases\":[{}],\"telemetry\":{{{}}}}}",
            self.cycles,
            self.volume_db
                .map(|v| format!("{v:.1}"))
                .unwrap_or_else(|| "null".into()),
            leases.join(","),
            telemetry.join(",")
        )
    }
}

enum Cmd {
    Volume(f64),
    Mute(bool),
    LeaseNow,
    /// Apply a plan file; the daemon answers through the channel once the block is on
    /// the bus, because only the loop thread owns the transport.
    Apply(std::path::PathBuf, Sender<String>),
    Quit,
}

fn main() -> Result<()> {
    let socket = std::env::args()
        .nth(1)
        .unwrap_or_else(|| format!("{}/glm5d.sock", runtime_dir()));

    let transport = protocol::HidTransport::open()?;
    let group = protocol::SamGroup::new(transport);
    let state = Arc::new(Mutex::new(State::default()));

    // Remove a socket left behind by a previous run; the daemon owns this path.
    let _ = std::fs::remove_file(&socket);
    if let Some(dir) = std::path::Path::new(&socket).parent() {
        std::fs::create_dir_all(dir).ok();
    }
    let listener = UnixListener::bind(&socket)
        .with_context(|| format!("binding the control socket {socket}"))?;
    eprintln!("glm5d listening on {socket}");

    let (tx, rx) = mpsc::channel::<Cmd>();
    {
        let tx = tx.clone();
        let state = Arc::clone(&state);
        std::thread::spawn(move || accept_loop(listener, tx, state));
    }

    let mut last_lease = Instant::now();
    loop {
        while let Ok(cmd) = rx.try_recv() {
            match cmd {
                Cmd::Quit => {
                    eprintln!("glm5d: quit");
                    let _ = std::fs::remove_file(&socket);
                    return Ok(());
                }
                Cmd::Volume(db) => match group.set_volume(db) {
                    Ok(()) => {
                        state.lock().unwrap().volume_db = Some(db);
                        eprintln!("glm5d: volume {db:.1} dB");
                    }
                    Err(e) => eprintln!("glm5d: volume failed: {e}"),
                },
                Cmd::Mute(on) => match if on { group.mute() } else { group.unmute() } {
                    Ok(()) => eprintln!("glm5d: mute {on}"),
                    Err(e) => eprintln!("glm5d: mute failed: {e}"),
                },
                Cmd::LeaseNow => last_lease = Instant::now() - LEASE_GRACE,
                Cmd::Apply(path, reply) => {
                    let summary = apply_plan(&group, &state, &path);
                    let _ = reply.send(summary);
                }
            }
        }

        // Re-lease when the previous leases are about to lapse; the probes are cheap and
        // a monitor that already holds our lease simply does not answer them.
        if last_lease.elapsed() >= LEASE_GRACE || state.lock().unwrap().leases.is_empty() {
            match group.take_leases() {
                Ok(leases) => {
                    let mut st = state.lock().unwrap();
                    if !leases.is_empty() {
                        st.leases = leases;
                    }
                    drop(st);
                    last_lease = Instant::now();
                }
                Err(e) => eprintln!("glm5d: lease cycle failed: {e}"),
            }
        }

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
            // Strict one reply per request: a poll left unanswered would be consumed by
            // the next request and shift every answer by one (seen in the 2026-11-02
            // capture: a probe answered by the adapter's status frame).
            match group.send_and_receive(&protocol::GNetMessage::new(session, 0x08)) {
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
        // The adapter answers its own status poll; read that reply here so it cannot be
        // mistaken for the next cycle's first monitor report (it arrives as `32 34 DE …`,
        // the mic/knob tags, and used to be filed under a monitor's session).
        // The adapter answers its own status poll; read that reply here so it cannot be
        // mistaken for the next cycle's first monitor report.
        let _ = group.send_and_receive(&protocol::GNetMessage::new(0x01, 0x08));

        {
            let mut st = state.lock().unwrap();
            st.cycles += 1;
            st.last_cycle = Some(Instant::now());
        }
        std::thread::sleep(CYCLE);
    }
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
                "error session {:02X} is not leased by glm5d (held: {:02X?})",
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
                eprintln!("glm5d: client error: {e}");
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
                tx.send(Cmd::Volume(db))?;
                writeln!(out, "ok queued")?;
            }
            "mute" => {
                let on = matches!(parts.next(), Some("on") | Some("1") | Some("true"));
                tx.send(Cmd::Mute(on))?;
                writeln!(out, "ok queued")?;
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
