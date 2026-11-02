//! The apply plan: a line format that names one monitor's settings, plus the frames a
//! block for that monitor consists of.
//!
//! Kept in the library rather than the CLI because both `genlc apply` (one shot) and
//! `glm5d` (a socket method) have to turn the same file into the same frames.

use anyhow::{Context, Result};

use crate::protocol;

/// One monitor's settings in an apply plan.
#[derive(Debug, Clone, PartialEq)]
pub struct MonitorPlan {
    pub session: u8,
    pub delay_samples: u32,
    pub level_word: i32,
    pub crossover_hz: u16,
    pub routing: Option<[u8; 4]>,
    pub peq: Vec<(u8, [f32; 5])>,
}

/// Parse a plan file. Deliberately a line format, not JSON: it needs no dependency,
/// it diffs well in git, and every field is one token.
///
/// ```text
/// # session <hex> <delay_samples> <level_word> <crossover_hz> [r1,r2,r3,r4]
/// session 02 288 0x7fffff 85 0,2,0,1
/// # peq <hex session> <slot> <b0,b1,b2,-a1,-a2>
/// peq 02 3 0.828,-0.775,0.717,1.884,-1.106
/// ```
pub fn parse_plan(text: &str) -> Result<Vec<MonitorPlan>> {
    let mut plans: Vec<MonitorPlan> = Vec::new();
    for (lineno, raw) in text.lines().enumerate() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let mut parts = line.split_whitespace();
        let kind = parts.next().unwrap_or_default();
        let ctx = |e: anyhow::Error| e.context(format!("plan line {}", lineno + 1));
        match kind {
            "session" => {
                let session =
                    parse_session(parts.next().context("session id").unwrap()).map_err(&ctx)?;
                let delay_samples = parts
                    .next()
                    .context("delay samples")
                    .and_then(|v| v.parse::<u32>().context("delay samples"))
                    .map_err(&ctx)?;
                let level_word = parts
                    .next()
                    .context("level word")
                    .and_then(|v| {
                        let v = v.trim_start_matches("0x");
                        i32::from_str_radix(v, 16).context("level word (hex)")
                    })
                    .map_err(&ctx)?;
                let crossover_hz = parts
                    .next()
                    .context("crossover Hz")
                    .and_then(|v| v.parse::<u16>().context("crossover Hz"))
                    .map_err(&ctx)?;
                let routing = match parts.next() {
                    None => None,
                    Some(v) => {
                        let n: Vec<u8> = v
                            .split(',')
                            .map(|x| x.parse::<u8>().context("routing byte"))
                            .collect::<Result<_>>()
                            .map_err(&ctx)?;
                        if n.len() != 4 {
                            anyhow::bail!("routing needs 4 bytes on plan line {}", lineno + 1);
                        }
                        Some([n[0], n[1], n[2], n[3]])
                    }
                };
                if plans.iter().any(|p| p.session == session) {
                    anyhow::bail!(
                        "session {session:02X} appears twice (plan line {})",
                        lineno + 1
                    );
                }
                plans.push(MonitorPlan {
                    session,
                    delay_samples,
                    level_word,
                    crossover_hz,
                    routing,
                    peq: Vec::new(),
                });
            }
            "peq" => {
                let session =
                    parse_session(parts.next().context("session id").unwrap()).map_err(&ctx)?;
                let slot = parts
                    .next()
                    .context("slot")
                    .and_then(|v| v.parse::<u8>().context("slot 0-19"))
                    .map_err(&ctx)?;
                let coeffs: Vec<f32> = parts
                    .next()
                    .context("coefficients")
                    .and_then(|v| {
                        v.split(',')
                            .map(|x| x.parse::<f32>().context("coefficient"))
                            .collect::<Result<_>>()
                    })
                    .map_err(&ctx)?;
                if coeffs.len() != 5 {
                    anyhow::bail!("PEQ needs 5 coefficients on plan line {}", lineno + 1);
                }
                if slot > 0x13 {
                    anyhow::bail!(
                        "PEQ slot must be 0x00-0x13, got {slot} (plan line {})",
                        lineno + 1
                    );
                }
                let plan = plans
                    .iter_mut()
                    .find(|p| p.session == session)
                    .with_context(|| {
                        format!("peq for session {session:02X} before its session line")
                    })?;
                plan.peq.push((
                    slot,
                    [coeffs[0], coeffs[1], coeffs[2], coeffs[3], coeffs[4]],
                ));
            }
            other => anyhow::bail!("unknown plan keyword {other:?} on line {}", lineno + 1),
        }
    }
    if plans.is_empty() {
        anyhow::bail!("plan is empty");
    }
    Ok(plans)
}

/// A session id must be a real per-monitor address: never the broadcast, never the
/// adapter, never the lease multicast. Writing settings to `FF` would hit every
/// speaker on the bus at once, which no plan should be able to express.
fn parse_session(token: &str) -> Result<u8> {
    let session =
        u8::from_str_radix(token.trim_start_matches("0x"), 16).context("session id (hex)")?;
    match session {
        0x00 | 0x01 => anyhow::bail!("{session:02X} is the adapter, not a monitor"),
        0xFF => anyhow::bail!("FF is the broadcast address; a plan targets one monitor at a time"),
        0xF0 => anyhow::bail!("F0 is the adapter's lease multicast"),
        _ => Ok(session),
    }
}

/// Build the frames of one monitor's block, in the order GLM sends them.
pub fn plan_frames(plan: &MonitorPlan) -> Vec<protocol::GNetMessage> {
    let mut frames = vec![
        protocol::block_opener(plan.session),
        protocol::delay_message(plan.session, plan.delay_samples),
        protocol::level_message(plan.session, plan.level_word),
        protocol::level_companion(plan.session),
    ];
    for slot in 0x00..=0x13u8 {
        let coeffs = plan
            .peq
            .iter()
            .find(|(s, _)| *s == slot)
            .map(|(_, c)| *c)
            .unwrap_or([1.0, 0.0, 0.0, 0.0, 0.0]);
        frames.push(protocol::peq_message(plan.session, slot, coeffs));
    }
    frames.push(protocol::crossover_message(plan.session, plan.crossover_hz));
    frames.push(protocol::block_middle(plan.session));
    if let Some(routing) = plan.routing {
        frames.push(protocol::routing_message(
            plan.session,
            routing[0],
            routing[1],
            routing[2],
            routing[3],
        ));
    }
    frames
}
