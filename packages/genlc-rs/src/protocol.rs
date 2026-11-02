// GNet protocol and HID transport — matching Python genlc USB transport
use anyhow::{Context, Result};
use hidapi::{HidApi, HidDevice};

const VID: u16 = 0x1781;
const PID: u16 = 0x0E39;
const GNET_BROADCAST: u8 = 0xFF;
const CID_VOLUME_GLM: u8 = 0x1F;
const CID_START_VOLUME: u8 = 0x21;
const CID_VOLUME_IF: u8 = 0x1D;
const CID_WAKEUP: u8 = 0x3A;
const CID_SOFTWARE: u8 = 0x39;
const CID_HARDWARE: u8 = 0x22;
const CID_BAR_CODE: u8 = 0x19;
const GNET_TERM: u8 = 0x7E;

pub struct HidTransport {
    device: HidDevice,
}

impl HidTransport {
    pub fn open() -> Result<Self> {
        let api = HidApi::new().context("Failed to initialize HID API")?;
        let device = api
            .open(VID, PID)
            .context("GLM USB adapter not found (VID:0x1781 PID:0x0E39)")?;
        Ok(Self { device })
    }

    /// Apply PPP byte stuffing (escape 0x7D and 0x7E)
    fn ppp_escape(data: &[u8]) -> Vec<u8> {
        // Stuff everything except the terminator
        let body = &data[..data.len() - 1];
        let term = data[data.len() - 1];
        let mut out = Vec::with_capacity(data.len() + 4);
        for &b in body {
            match b {
                0x7D => out.extend_from_slice(&[0x7D, 0x5D]),
                0x7E => out.extend_from_slice(&[0x7D, 0x5E]),
                _ => out.push(b),
            }
        }
        out.push(term);
        out
    }

    /// Send a GNet message. Matches Python USBTransport.send().
    /// Format: [0x00] [0x80+len] [PPP-stuffed message]
    pub fn send(&self, msg: &GNetMessage) -> Result<()> {
        if let Some(why) = forbidden_reason(msg.address, &msg.payload()) {
            anyhow::bail!("refusing to send {why} ({:#04X})", msg.command);
        }
        let raw = msg.encode();
        let stuffed = Self::ppp_escape(&raw);

        let mut payload = vec![0x00, 0x80 + stuffed.len() as u8];
        payload.extend_from_slice(&stuffed);

        self.device.write(&payload)?;
        Ok(())
    }

    /// Read one or more 64-byte HID reports, reassemble, PPP-destuff.
    /// Matches Python USBTransport._read().
    pub fn receive(&self) -> Result<Vec<u8>> {
        let mut segments: Vec<Vec<u8>> = Vec::new();
        loop {
            if segments.len() >= 3 {
                anyhow::bail!("Max response segments (3) exceeded");
            }
            let mut buf = vec![0u8; 64];
            let n = self.device.read_timeout(&mut buf, 500)?;
            if n != 64 {
                anyhow::bail!("Short HID read: {} bytes (expected 64)", n);
            }
            // First byte = remaining payload len in this packet (always 63)
            if buf[0] != 63 {
                anyhow::bail!("Unexpected segment header: {} (expected 63)", buf[0]);
            }
            // Join segments (skip first byte of each)
            let mut joined = Vec::new();
            for seg in &segments {
                joined.extend_from_slice(&seg[1..]);
            }
            joined.extend_from_slice(&buf[1..]);
            // Strip trailing nulls
            while joined.last() == Some(&0) {
                joined.pop();
            }
            // Check for terminator
            if joined.last() == Some(&GNET_TERM) {
                // PPP destuff
                let mut destuffed = Vec::new();
                let mut i = 0;
                while i < joined.len() {
                    if joined[i] == 0x7D && i + 1 < joined.len() {
                        match joined[i + 1] {
                            0x5E => destuffed.push(0x7E),
                            0x5D => destuffed.push(0x7D),
                            _ => anyhow::bail!("Invalid PPP escape: 0x7D 0x{:02X}", joined[i + 1]),
                        }
                        i += 2;
                    } else {
                        destuffed.push(joined[i]);
                        i += 1;
                    }
                }
                return Ok(destuffed);
            }
            segments.push(buf);
        }
    }
}

pub struct GNetMessage {
    address: u8,
    command: u8,
    data: Vec<u8>,
}

impl GNetMessage {
    pub fn new(address: u8, command: u8) -> Self {
        Self {
            address,
            command,
            data: vec![],
        }
    }

    pub fn with_data(mut self, data: Vec<u8>) -> Self {
        self.data = data;
        self
    }

    pub fn set_sint24(&mut self, value: i32) {
        let bytes = value.to_be_bytes();
        self.data = bytes[1..].to_vec();
    }

    /// Opcode plus data: what the bus calls the payload, and what the CRC covers
    /// (together with the address).
    fn payload(&self) -> Vec<u8> {
        let mut payload = vec![self.command];
        payload.extend(&self.data);
        payload
    }

    pub fn encode(&self) -> Vec<u8> {
        let mut msg = vec![self.address, self.command];
        msg.extend(&self.data);
        let crc = gsm16(&msg);
        msg.extend_from_slice(&crc.to_be_bytes());
        msg.push(GNET_TERM);
        msg
    }
}

/// Frames the GLM bus must never carry. Each one appears in no GLM capture, and
/// the ones qlm ever considered are refused by its own allowlist; `05 04` is the
/// generator stop and `15` the flash commit, so a wrong payload there is not a
/// cosmetic mistake. `HidTransport::send` is the only place a frame leaves this
/// crate, so one call to this function there cannot be bypassed by a new caller. Source: qlm docs/protocol.md, "Opcodes" (see
/// .agent/plans/2026-11-02-glm5-linux-port.md and /tmp/glm5-port/spec/cid-map.json).
fn forbidden_reason(address: u8, payload: &[u8]) -> Option<&'static str> {
    match payload {
        [0x05, 0x04, ..] => Some("05 04 is the generator stop"),
        [0x15, ..] => Some("15 is the flash commit"),
        [0x3A, 0x01, ..] | [0x3A, 0x02, ..] | [0x3A, 0x06, ..] => {
            Some("3A 01/02/06 are standalone settings")
        }
        [0x10, 0x01, 0x05, ..] => Some("10 01 05 belongs to hlm's store sequence"),
        [0x03, ..] if address == GNET_BROADCAST => {
            Some("a broadcast 03 drops every monitor's lease")
        }
        _ => None,
    }
}

/// `17 01`: the frame GLM sends first in every settings block. Its meaning is
/// unknown (qlm lists it as unconfirmed); it is reproduced only because a faithful
/// block replay needs the same opener.
pub fn block_opener(address: u8) -> GNetMessage {
    GNetMessage::new(address, 0x17).with_data(vec![0x01])
}

/// `10 01 09 00 00 00`: the fixed companion GLM sends right after a level write.
pub fn level_companion(address: u8) -> GNetMessage {
    GNetMessage::new(address, 0x10).with_data(vec![0x01, 0x09, 0x00, 0x00, 0x00])
}

/// `3D 00 00`: an unknown frame GLM sends after the crossover in every block.
pub fn block_middle(address: u8) -> GNetMessage {
    GNetMessage::new(address, 0x3D).with_data(vec![0x00, 0x00])
}

/// `10 0E`: one parametric-EQ band. The five coefficients are little-endian f32 in
/// the order b0, b1, b2, a1, a2, with a1/a2 already divided by a0 and sign-inverted;
/// the trailing byte is `00` for a custom filter. Slots run 0x00-0x13: a two-way
/// monitor keeps 0x00-0x01 for its low shelf and 0x02-0x03 for the high shelf, a
/// subwoofer uses all twenty as peaking bands. A bypassed band is the shortcut
/// b0 = 1.0 with four zeros (hlm protocol.md §5), not an omitted frame: GLM sends
/// every slot of every monitor in each block whether it is flat or not.
pub fn peq_message(address: u8, slot: u8, coeffs: [f32; 5]) -> GNetMessage {
    let mut data = Vec::with_capacity(22);
    data.push(0x0E);
    data.push(slot);
    for c in coeffs {
        data.extend_from_slice(&c.to_le_bytes());
    }
    data.push(0x00);
    GNetMessage::new(address, 0x10).with_data(data)
}

/// The flat/bypass band: b0 = 1.0, everything else zero.
pub fn peq_flat(address: u8, slot: u8) -> GNetMessage {
    peq_message(address, slot, [1.0, 0.0, 0.0, 0.0, 0.0])
}

/// `10 02`: alignment delay, a 32-bit count of 48 kHz samples on every device class
/// (`00 00 01 1A` = 282 samples as captured on a subwoofer).
pub fn delay_message(address: u8, samples: u32) -> GNetMessage {
    let mut data = vec![0x02];
    data.extend_from_slice(&samples.to_be_bytes());
    GNetMessage::new(address, 0x10).with_data(data)
}

/// `10 01 00`: a monitor's level, the same 24-bit linear gain as `1F` but per
/// speaker (`00 6A B6 0F` as captured).
pub fn level_message(address: u8, gain: i32) -> GNetMessage {
    let mut msg = GNetMessage::new(address, 0x10).with_data(vec![0x01, 0x00]);
    let bytes = gain.to_be_bytes();
    msg.data.extend_from_slice(&bytes[1..]);
    msg
}

/// `3B`: bass-management crossover in Hz, big-endian (`00 55` = 85 Hz as captured).
pub fn crossover_message(address: u8, hz: u16) -> GNetMessage {
    GNetMessage::new(address, 0x3B).with_data(hz.to_be_bytes().to_vec())
}

/// `40`: input routing — input index, source, pair selector, AES3 channel
/// (`01` = A, `02` = B, `03` = both). `40 00 02 00 01` and `40 01 02 00 00` both
/// appear in the captured group switch.
pub fn routing_message(address: u8, input: u8, source: u8, pair: u8, channel: u8) -> GNetMessage {
    GNetMessage::new(address, 0x40).with_data(vec![input, source, pair, channel])
}

/// A session this host has leased to a monitor.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Lease {
    pub hardware_id: [u8; 3],
    pub session: u8,
}

/// Session ids run from `02` upward; `7D`, `7E` and `F0` are never leasable (they are
/// the escape byte, the frame flag and the adapter's multicast).
pub fn next_session(current: u8) -> Result<u8> {
    let mut next = current.checked_add(1).unwrap_or(0x02);
    loop {
        match next {
            0x7D | 0x7E | 0xF0 => next += 1,
            0x00 | 0x01 | 0xFF => next = 0x02,
            _ => return Ok(next),
        }
    }
}

/// The probe: a broadcast `FE`, the frame GLM sends twice a second to find monitors
/// that hold no lease. Safe to send at any time — it changes nothing, it only asks
/// who is out there.
pub fn probe_message() -> GNetMessage {
    GNetMessage::new(GNET_BROADCAST, 0xFE)
}

/// A lease offer: the adapter's multicast address `F0`, opcode `02`, the monitor's
/// 3-byte hardware id, then the session it should answer on. Not wired into the CLI
/// yet — writing leases takes sessions away from whichever host holds them, and the
/// spec's lease trap makes that a deliberate operation, not a side effect.
pub fn lease_message(hardware_id: [u8; 3], session: u8) -> GNetMessage {
    let mut data = hardware_id.to_vec();
    data.push(session);
    GNetMessage::new(0xF0, 0x02).with_data(data)
}

/// Read a probe answer: `09` followed by the monitor's 3-byte hardware id. The
/// adapter itself answers `01 7E` when no unleased monitor replied, which is `None`
/// here — that is the "everyone is leased" case, not an error.
pub fn parse_probe_answer(frame: &Frame) -> Result<Option<[u8; 3]>> {
    if frame.address != 0x01 {
        anyhow::bail!(
            "probe answers come from the adapter (01), got {:02X}",
            frame.address
        );
    }
    if frame.opcode == 0x7E {
        return Ok(None);
    }
    if frame.opcode != 0x09 {
        anyhow::bail!("expected 09 or 7E, got {:02X}", frame.opcode);
    }
    match frame.data.len() {
        0 => Ok(None),
        3 => Ok(Some([frame.data[0], frame.data[1], frame.data[2]])),
        other => anyhow::bail!("a probe answer carries 3 hardware-id bytes, got {other}"),
    }
}

/// One field of a `09` reply: a tag and its value (0, 1, 2 or 4 bytes, big-endian).
/// The adapter's status and a monitor's telemetry share this encoding — after `09`
/// come tag-value fields with no length byte, and the top two bits of the tag give
/// the value's length: `00` none, `01` one byte, `10` two, `11` four. That rule is
/// qlm's inference over 73k replies (adapter-status.md, telemetry.md) and it fits
/// every frame this host captured too.
pub fn parse_tags(payload: &[u8]) -> Result<Vec<(u8, u32)>> {
    let mut out = Vec::new();
    let mut i = 0;
    while i < payload.len() {
        let tag = payload[i];
        let len = match tag >> 6 {
            0b00 => 0,
            0b01 => 1,
            0b10 => 2,
            _ => 4,
        };
        i += 1;
        if i + len > payload.len() {
            anyhow::bail!(
                "tag {tag:02X} wants {len} value bytes, {} left",
                payload.len() - i
            );
        }
        let mut value = 0u32;
        for &b in &payload[i..i + len] {
            value = (value << 8) | u32::from(b);
        }
        out.push((tag, value));
        i += len;
    }
    Ok(out)
}

/// A signed 32-bit view of a tag's value — `DF` (the knob) is the one field that
/// needs it: tenths of a dB, negative below the top stop.
pub fn tag_value_signed(value: u32) -> i32 {
    value as i32
}

/// The ASCII payload of a reply: after destuffing a reply has the shape
/// `[address][opcode][data ...][crc:2][0x7E]`. Returns an error instead of
/// slicing out of bounds when a reply is too short to carry a payload — the
/// adapter's "no monitor answered" frame `01 7E` is exactly such a reply, and
/// discovering monitors used to panic on it.
fn reply_text(raw: &[u8]) -> Result<String> {
    const HEADER: usize = 2; // address + opcode
    const TRAILER: usize = 3; // CRC (2 bytes, big-endian) + the 0x7E flag
    if raw.len() < HEADER + TRAILER {
        anyhow::bail!("reply too short for a payload: {} bytes", raw.len());
    }
    Ok(String::from_utf8_lossy(&raw[HEADER..raw.len() - TRAILER])
        .trim_end_matches('\0')
        .to_string())
}

/// Undo the PPP byte stuffing that the adapter and the host apply to payloads and
/// CRCs (0x7E -> 0x7D 0x5E, 0x7D -> 0x7D 0x5D). The 0x7E flag itself is never escaped.
pub fn destuff(bytes: &[u8]) -> Result<Vec<u8>> {
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == 0x7D {
            let next = *bytes
                .get(i + 1)
                .ok_or_else(|| anyhow::anyhow!("truncated escape at the end of a frame"))?;
            out.push(match next {
                0x5E => 0x7E,
                0x5D => 0x7D,
                other => anyhow::bail!("invalid PPP escape 0x7D 0x{:02X}", other),
            });
            i += 2;
        } else {
            out.push(bytes[i]);
            i += 1;
        }
    }
    Ok(out)
}

/// One frame off the wire, as the decoder sees it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Frame {
    pub address: u8,
    pub opcode: u8,
    pub data: Vec<u8>,
}

impl Frame {
    /// The opcode plus its data — what the bus calls the payload.
    pub fn payload(&self) -> Vec<u8> {
        let mut payload = vec![self.opcode];
        payload.extend(&self.data);
        payload
    }
}

/// Parse and verify one frame: `[address][opcode][data...][crc:2][0x7E]`, with the
/// CRC still stuffed. Rejects a frame whose flag is missing or whose CRC does not
/// match, so a decoder can trust what it prints.
pub fn decode_frame(stuffed: &[u8]) -> Result<Frame> {
    let frame = destuff(stuffed)?;
    if frame.len() < 5 {
        anyhow::bail!("frame too short: {} bytes", frame.len());
    }
    if frame.last() != Some(&GNET_TERM) {
        anyhow::bail!("frame does not end with the 0x7E flag");
    }
    let body = &frame[..frame.len() - 3];
    let crc = u16::from_be_bytes([frame[frame.len() - 3], frame[frame.len() - 2]]);
    let expected = gsm16(body);
    if crc != expected {
        anyhow::bail!("CRC mismatch: frame says 0x{crc:04X}, computed 0x{expected:04X}");
    }
    Ok(Frame {
        address: body[0],
        opcode: body[1],
        data: body[2..].to_vec(),
    })
}

/// Human-readable name for an opcode, from the confirmed part of the CID map
/// (/tmp/glm5-port/spec/cid-map.json, built from qlm's protocol document). Unknown
/// opcodes come back as "unknown" — the decoder prints the bytes either way.
pub fn opcode_name(address: u8, opcode: u8, data: &[u8]) -> &'static str {
    match (opcode, data.first().copied()) {
        (0xFE, _) => "probe",
        (0x7E, _) if address == 0x01 => "no-answer",
        (0x02, _) => "lease",
        (0x03, _) if address == GNET_BROADCAST => "drop-all-leases",
        (0x04, _) => "keep-alive",
        (0x05, Some(0x04)) => "generator-stop FORBIDDEN",
        (0x08, _) if address == 0x01 => "adapter-status-poll",
        (0x08, _) => "poll",
        (0x10, Some(0x01)) => "level",
        (0x10, Some(0x02)) => "delay",
        (0x10, Some(0x0E)) => "peq-band",
        (0x15, _) => "flash-commit FORBIDDEN",
        (0x19, _) => "serial",
        (0x1F, _) => "volume",
        (0x22, _) => "adapter-identity",
        (0x2B, _) if address == 0x01 => "mute-all",
        (0x2B, _) => "mute-led",
        (0x39, _) => "system-info",
        (0x3A, Some(0x03)) => "power",
        (0x3B, _) => "crossover",
        (0x40, _) => "routing",
        _ => "unknown",
    }
}

fn gsm16(data: &[u8]) -> u16 {
    let mut crc: u16 = 0;
    for &byte in data {
        crc ^= (byte as u16) << 8;
        for _ in 0..8 {
            if crc & 0x8000 != 0 {
                crc = (crc << 1) ^ 0x1021;
            } else {
                crc <<= 1;
            }
        }
    }
    crc ^ 0xFFFF
}

/// dB -> the 24-bit linear gain GLM puts on the bus.
///
/// Truncation is right, and this was checked against GLM itself: a capture of GLM 5.2
/// (2026-11-02, usbmon bus 5 device 2) holds -57 dB as `00 2E 49`, -56 dB as
/// `00 33 EF` and -53 dB as `00 49 5B`. Scaling to 2^23-1 and truncating reproduces
/// all three (11849.222, 13295.046 and 18779.752 floored); rounding reproduces only
/// the first two. qlm's doc still warns that `floor(10^(dB/20) x 7FFFFF)` misses four
/// of GLM's 200 steps by one count, so equality is not global — a full sweep capture
/// would be needed to pin the exceptions, and until then this stays within a count.
fn db_to_sint24(db: f64) -> i32 {
    let ratio = 10_f64.powf(db / 20.0);
    (ratio * 8_388_607.0) as i32
}

pub struct SamGroup {
    transport: HidTransport,
}

impl SamGroup {
    pub fn new(transport: HidTransport) -> Self {
        Self { transport }
    }

    /// Read one reply if one is already waiting, without failing when it is not.
    /// Used while pacing a settings block: a monitor answers within ~7 ms, so a short
    /// timeout between frames is enough to collect the acknowledgements.
    pub fn try_receive(&self) -> Option<Vec<u8>> {
        self.transport.receive().ok()
    }

    /// Send one frame and read exactly one reply.
    ///
    /// The adapter answers every probe and every unicast with exactly one frame, so a
    /// strict one-in-one-out discipline keeps the stream aligned. `try_receive` used to
    /// be used for both sides of the cycle, and when a reply arrived late the next
    /// request consumed it: the 2026-11-02 capture shows a probe answered by the
    /// adapter's status frame and a status poll answered by a monitor's hardware id —
    /// every reply one request behind.
    pub fn send_and_receive(&self, msg: &GNetMessage) -> Result<Frame> {
        self.transport.send(msg)?;
        let raw = self.transport.receive()?;
        decode_frame(&raw)
    }

    /// Send one frame and read until a reply of the expected shape arrives.
    ///
    /// Positional pairing is not enough on this bus: while a host is connected the
    /// adapter also broadcasts `F0 1F 00 00 00` about every 610 ms on its own, and a late
    /// answer is otherwise consumed by the next request (measured 2026-11-02: a probe
    /// read the adapter's 13-byte status frame, then the stream desynced into a bogus
    /// PPP escape). So match by content, bounded by a deadline, and drop what does not fit.
    pub fn send_and_match(
        &self,
        msg: &GNetMessage,
        deadline: std::time::Duration,
        mut accept: impl FnMut(&Frame) -> bool,
    ) -> Result<Frame> {
        self.transport.send(msg)?;
        let start = std::time::Instant::now();
        loop {
            let raw = self.transport.receive()?;
            if let Ok(frame) = decode_frame(&raw) {
                if accept(&frame) {
                    return Ok(frame);
                }
            }
            if start.elapsed() > deadline {
                anyhow::bail!("no matching reply within {deadline:?}");
            }
        }
    }

    /// Send one already-built frame. The single way `genlc apply` puts a plan on the
    /// bus; it goes through `HidTransport::send`, so the forbidden-frame guard still
    /// applies.
    pub fn send(&self, msg: &GNetMessage) -> Result<()> {
        self.transport.send(msg)
    }

    pub fn set_volume(&self, db: f64) -> Result<()> {
        let sint24 = db_to_sint24(db);
        let mut msg = GNetMessage::new(GNET_BROADCAST, CID_VOLUME_GLM);
        msg.set_sint24(sint24);
        self.transport.send(&msg)?;
        Ok(())
    }

    /// Mute the whole system the way GLM does it: `2B` to the adapter, `01` muted
    /// and `00` unmuted, answered by `09`.
    ///
    /// This used to send `FF 08 01/00` — the poll opcode on the broadcast address.
    /// A capture of GLM 5.2 idling (2026-11-02, usbmon bus 5 device 2) holds no
    /// broadcast `08` at all: GLM's broadcasts are only `FE` probes and `1F` volumes,
    /// and its `08` polls go to the adapter (`01`) or to a leased session. So the old
    /// frame was almost certainly a no-op, and every mute that appeared to work came
    /// from GLM in the Windows VM. **Not yet confirmed on hardware**: the next capture
    /// taken while toggling mute settles it (a `01 2B 01` and a `09` reply should
    /// appear).
    fn set_muted(&self, muted: bool) -> Result<()> {
        let msg = GNetMessage::new(0x01, 0x2B).with_data(vec![u8::from(muted)]);
        self.transport.send(&msg)?;
        Ok(())
    }

    pub fn mute(&self) -> Result<()> {
        self.set_muted(true)
    }

    pub fn unmute(&self) -> Result<()> {
        self.set_muted(false)
    }

    pub fn toggle_mute(&self) -> Result<()> {
        self.mute()
    }

    pub fn wakeup(&self) -> Result<()> {
        for data in [vec![3, 0x7F], vec![3, 1]] {
            let msg = GNetMessage::new(GNET_BROADCAST, CID_WAKEUP).with_data(data.clone());
            self.transport.send(&msg)?;
            self.transport.send(&msg)?;
        }
        Ok(())
    }

    pub fn shutdown(&self) -> Result<()> {
        for data in [vec![3, 2], vec![3, 0]] {
            let msg = GNetMessage::new(GNET_BROADCAST, CID_WAKEUP).with_data(data.clone());
            self.transport.send(&msg)?;
            self.transport.send(&msg)?;
        }
        Ok(())
    }

    /// Lease every monitor that holds no lease, one at a time, and report the result.
    ///
    /// This is safe by construction: a monitor that still holds a lease from another
    /// host does not answer the probe, so a running GLM never loses its monitors to
    /// this call — it only picks up speakers nobody is controlling. It does change
    /// bus state (the monitors answer on the new sessions from now on), which is why
    /// the CLI requires an explicit `--take`.
    pub fn take_leases(&self) -> Result<Vec<Lease>> {
        let mut leased: Vec<Lease> = Vec::new();
        let mut session = 0x02u8;
        // Only the socket-owning daemon runs this, and it keeps the stream aligned with
        // one reply per request, so the buffer should be empty. Anything left over means
        // an earlier request went unanswered; clear it once here rather than letting it
        // be read as a probe answer (a 10-byte telemetry frame used to be).
        for _ in 0..4 {
            if self.transport.receive().is_err() {
                break;
            }
        }
        // A bus holds at most a few dozen monitors; more probes than that means the
        // adapter keeps answering with hardware ids we cannot lease (a stuck monitor),
        // and looping forever would be worse than reporting it.
        for _ in 0..64 {
            // A probe answer is the adapter echoing a monitor's hardware id (`09` + 3
            // bytes) or its own "nobody unleased" frame; anything else on the bus is
            // skipped rather than mistaken for the answer.
            let frame = self.send_and_match(
                &probe_message(),
                std::time::Duration::from_millis(400),
                |f| {
                    f.address == 0x01
                        && (f.opcode == 0x7E || (f.opcode == 0x09 && f.data.len() == 3))
                },
            )?;
            let Some(hardware_id) = parse_probe_answer(&frame)? else {
                return Ok(leased); // nobody unleased is left
            };
            // Skip a session this host already handed out (a monitor may answer twice
            // if its ack was lost).
            if leased.iter().any(|l| l.hardware_id == hardware_id) {
                anyhow::bail!(
                    "monitor {:02X?} answered the probe after being leased — the ack was lost",
                    hardware_id
                );
            }
            session = next_session(session)?;
            let ack = self.send_and_match(
                &lease_message(hardware_id, session),
                std::time::Duration::from_millis(400),
                // The ack carries the session, not the hardware id — accepting any `09`
                // here matched a second probe answer and looked like a failed lease.
                |f| f.address == 0x01 && f.opcode == 0x09 && f.data == [session],
            )?;
            let ok = ack.opcode == 0x09 && ack.data.first() == Some(&session);
            if !ok {
                anyhow::bail!(
                    "lease of {:02X?} on session {session:02X} not acknowledged ({:02X} {:02X?})",
                    hardware_id,
                    ack.opcode,
                    ack.data
                );
            }
            leased.push(Lease {
                hardware_id,
                session,
            });
        }
        anyhow::bail!("lease loop did not settle after 64 probes")
    }

    /// Probe the bus once and report which monitor answered. Only the monitors that
    /// hold no lease answer, so `None` means "every monitor is leased by some host"
    /// (GLM in the Windows VM, usually) — not that the bus is empty.
    pub fn probe(&self) -> Result<Option<[u8; 3]>> {
        self.transport.send(&probe_message())?;
        let raw = self.transport.receive()?;
        let frame = decode_frame(&raw)?;
        parse_probe_answer(&frame)
    }

    pub fn discover(&self) -> Result<()> {
        // Query adapter
        println!("[1] GLM Adapter");
        for (cid, label) in [
            (CID_HARDWARE, "hardware"),
            (CID_SOFTWARE, "software"),
            (CID_BAR_CODE, "bar code"),
        ] {
            let msg = GNetMessage::new(1, cid).with_data(if cid == CID_BAR_CODE {
                vec![0x01]
            } else {
                vec![]
            });
            self.transport.send(&msg)?;
            match self.transport.receive().and_then(|raw| reply_text(&raw)) {
                Ok(text) => println!("	{}: {}", label, text),
                Err(e) => eprintln!("	{}: error ({})", label, e),
            }
        }
        Ok(())
    }

    pub fn poll(&self, addr: u8) -> Result<()> {
        let msg = GNetMessage::new(addr, 0x08);
        self.transport.send(&msg)?;
        match self.transport.receive() {
            Ok(raw) => {
                if raw.len() < 2 {
                    anyhow::bail!("Short response");
                }
                println!("[{}] {} bytes: {:02x?}", raw[0], raw.len(), &raw);
            }
            Err(e) => eprintln!("no response: {e}"),
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_a_reply_payload_and_refuses_a_too_short_one() {
        // address 01, opcode 22, "Gne", CRC, flag
        let reply = [0x01, 0x22, b'G', b'n', b'e', 0x12, 0x34, GNET_TERM];
        assert_eq!(reply_text(&reply).unwrap(), "Gne");
        // the adapter's "no monitor answered" frame: header + flag only
        let no_answer = [0x01, 0x7E];
        assert!(reply_text(&no_answer).is_err());
    }

    /// The three volume words a real GLM 5.2 capture holds, with the dB they mean.
    /// This is the check that keeps `set_volume` byte-compatible with GLM itself.
    /// Mute is `01 2B 01` and unmute `01 2B 00`, per the spec's opcode table. Locked
    /// in as golden bytes so a future refactor cannot quietly go back to the old
    /// broadcast poll frame GLM never sends.
    /// The host's own capture, 2026-11-02: the adapter reporting "mic in, no knob"
    /// with two mic readings. If the tag-length rule ever drifts, this fails.
    /// Every encoder checked against the bytes GLM itself put on the bus during the
    /// 2026-11-02 group switch (capture `capture-20261102-125310.pcap`). These are
    /// the frames a preset write has to reproduce, so they are pinned exactly.
    #[test]
    fn session_ids_skip_the_reserved_bytes() {
        assert_eq!(next_session(0x02).unwrap(), 0x03);
        assert_eq!(next_session(0x7C).unwrap(), 0x7F); // skips 7D and 7E
        assert_eq!(next_session(0xEF).unwrap(), 0xF1); // skips F0
        assert_eq!(next_session(0xFA).unwrap(), 0xFB);
    }

    #[test]
    fn encodes_the_settings_frames_glm_actually_sent() {
        // subwoofer (session 03) in that block
        assert_eq!(
            delay_message(0x03, 282).encode()[..6],
            [0x03, 0x10, 0x02, 0x00, 0x00, 0x01]
        );
        assert_eq!(
            delay_message(0x03, 282).data,
            vec![0x02, 0x00, 0x00, 0x01, 0x1A]
        );
        assert_eq!(
            level_message(0x03, 0x6A_B6_0F).data,
            vec![0x01, 0x00, 0x6A, 0xB6, 0x0F]
        );
        assert_eq!(
            crossover_message(0x03, 85).encode()[..3],
            [0x03, 0x3B, 0x00]
        );
        assert_eq!(crossover_message(0x03, 85).data, vec![0x00, 0x55]);
        assert_eq!(
            routing_message(0x03, 0x00, 0x02, 0x00, 0x03).data,
            vec![0x00, 0x02, 0x00, 0x03]
        );
        assert_eq!(
            routing_message(0x03, 0x01, 0x02, 0x00, 0x00).data,
            vec![0x01, 0x02, 0x00, 0x00]
        );

        // the flat slot GLM sends for every unused band
        let flat = peq_flat(0x02, 0x00);
        assert_eq!(
            flat.data,
            vec![
                0x0E, 0x00, 0x00, 0x00, 0x80, 0x3F, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                0x00
            ]
        );

        // a real, non-flat band: slot 3 of session 02, coefficient bytes straight out
        // of the capture, re-encoded through the same f32 little-endian path
        let captured = vec![
            0x0E, 0x03, 0x23, 0xFD, 0x53, 0x3F, 0x35, 0x79, 0xC6, 0xBF, 0x0D, 0x48, 0x39, 0x3F,
            0xCB, 0x1E, 0xF1, 0x3F, 0x59, 0x90, 0x62, 0xBF, 0x00,
        ];
        let c: [f32; 5] = [
            f32::from_le_bytes([0x23, 0xFD, 0x53, 0x3F]),
            f32::from_le_bytes([0x35, 0x79, 0xC6, 0xBF]),
            f32::from_le_bytes([0x0D, 0x48, 0x39, 0x3F]),
            f32::from_le_bytes([0xCB, 0x1E, 0xF1, 0x3F]),
            f32::from_le_bytes([0x59, 0x90, 0x62, 0xBF]),
        ];
        assert_eq!(peq_message(0x02, 0x03, c).data, captured);
    }

    #[test]
    fn parses_the_adapters_status_reply_from_a_real_capture() {
        let payload = [
            0x32, 0x34, 0xDE, 0x00, 0x66, 0xA4, 0x26, 0xDD, 0x00, 0x4E, 0x1C, 0xB0, 0x31,
        ];
        let tags = parse_tags(&payload).unwrap();
        assert_eq!(
            tags,
            vec![
                (0x32, 0),          // the mic is plugged in
                (0x34, 0),          // opens the mic's readings
                (0xDE, 0x0066A426), // mic reading
                (0xDD, 0x004E1CB0), // second mic reading
                (0x31, 0),          // no knob
            ]
        );
    }

    /// A monitor's telemetry frame (8351B) from the same capture: tag 0x81/0x82/0x83
    /// carry two bytes each, 0x42-0x47 one, 0x88/0x89 two.
    #[test]
    fn parses_monitor_telemetry_from_a_real_capture() {
        let payload = [
            0x41, 0x32, 0x81, 0x00, 0x32, 0x82, 0x00, 0x32, 0x83, 0x00, 0x32, 0x42, 0x80, 0x43,
            0x80, 0x45, 0x80, 0x44, 0x80, 0x47, 0x01, 0x88, 0x00, 0x51, 0x89, 0x00, 0x43, 0x84,
            0x02, 0xD9,
        ];
        let tags = parse_tags(&payload).unwrap();
        assert_eq!(tags.first(), Some(&(0x41, 0x32)));
        assert!(tags.iter().any(|&(t, v)| t == 0x81 && v == 0x0032));
        assert!(tags.iter().any(|&(t, v)| t == 0x47 && v == 0x01));
        assert!(tags.iter().any(|&(t, v)| t == 0x84));
        assert_eq!(tags.iter().map(|(_, _)| 1).sum::<i32>(), tags.len() as i32);
    }

    #[test]
    fn refuses_a_tag_whose_value_runs_past_the_end() {
        assert!(parse_tags(&[0xDE, 0x00, 0x01]).is_err());
        assert_eq!(parse_tags(&[]).unwrap(), vec![]);
    }

    #[test]
    fn encodes_the_probe_and_reads_both_answers() {
        let probe = probe_message();
        assert_eq!(probe.encode(), vec![0xFF, 0xFE, 0xF2, 0xD1, GNET_TERM]);

        // a monitor answered with its hardware id
        let frame = Frame {
            address: 0x01,
            opcode: 0x09,
            data: vec![0xAA, 0xBB, 0xCC],
        };
        assert_eq!(
            parse_probe_answer(&frame).unwrap(),
            Some([0xAA, 0xBB, 0xCC])
        );

        // the adapter answered for itself: every monitor already holds a lease
        let idle = Frame {
            address: 0x01,
            opcode: 0x7E,
            data: vec![],
        };
        assert_eq!(parse_probe_answer(&idle).unwrap(), None);

        // a malformed answer is an error, not a silent None
        let bad = Frame {
            address: 0x01,
            opcode: 0x09,
            data: vec![0xAA],
        };
        assert!(parse_probe_answer(&bad).is_err());
    }

    #[test]
    fn encodes_a_lease_to_the_adapter_multicast() {
        let lease = lease_message([0xAA, 0xBB, 0xCC], 0x05);
        assert_eq!(
            lease.encode(),
            vec![0xF0, 0x02, 0xAA, 0xBB, 0xCC, 0x05, 0xA5, 0x8F, GNET_TERM]
        );
    }

    #[test]
    fn encodes_the_mute_frames_the_spec_documents() {
        for (muted, expected) in [
            (true, vec![0x01, 0x2B, 0x01, 0x02, 0xF2, GNET_TERM]),
            (false, vec![0x01, 0x2B, 0x00, 0x12, 0xD3, GNET_TERM]),
        ] {
            let msg = GNetMessage::new(0x01, 0x2B).with_data(vec![u8::from(muted)]);
            assert_eq!(msg.encode(), expected);
        }
    }

    #[test]
    fn encodes_the_volume_words_glm_actually_sent() {
        for (db, word) in [(-57.0, 0x002E49), (-56.0, 0x0033EF), (-53.0, 0x00495B)] {
            assert_eq!(
                db_to_sint24(db),
                word,
                "{db} dB must encode as 0x{word:06X}"
            );
        }
        assert_eq!(db_to_sint24(0.0), 0x7FFFFF);
    }

    #[test]
    fn decodes_glms_volume_frame_and_reports_its_crc() {
        let raw = [0xFF, 0x1F, 0x00, 0x31, 0x07, 0x2C, 0x5A, 0x7E];
        let frame = decode_frame(&raw).unwrap();
        assert_eq!(frame.address, GNET_BROADCAST);
        assert_eq!(frame.opcode, CID_VOLUME_GLM);
        assert_eq!(frame.data, vec![0x00, 0x31, 0x07]);
        assert_eq!(
            opcode_name(frame.address, frame.opcode, &frame.data),
            "volume"
        );
    }

    #[test]
    fn decodes_an_escaped_frame() {
        // the adapter's escaped no-answer frame: 01 7D 5E 53 97 7E
        let raw = [0x01, 0x7D, 0x5E, 0x53, 0x97, 0x7E];
        let frame = decode_frame(&raw).unwrap();
        assert_eq!(frame.address, 0x01);
        assert_eq!(frame.opcode, 0x7E);
        assert!(frame.data.is_empty());
    }

    #[test]
    fn rejects_a_bad_crc_and_a_missing_flag() {
        let bad_crc = [0xFF, 0x1F, 0x00, 0x31, 0x07, 0x2C, 0x5B, 0x7E];
        assert!(decode_frame(&bad_crc).is_err());
        let no_flag = [0xFF, 0x1F, 0x00, 0x31, 0x07, 0x2C, 0x5A, 0x00];
        assert!(decode_frame(&no_flag).is_err());
    }

    #[test]
    fn rejects_a_truncated_escape() {
        assert!(destuff(&[0x01, 0x7D]).is_err());
        assert!(destuff(&[0x01, 0x7D, 0x11]).is_err());
    }

    #[test]
    fn refuses_every_documented_forbidden_frame() {
        let cases: [(u8, Vec<u8>); 7] = [
            (0x02, vec![0x05, 0x04, 0x00, 0x00, 0x00]),
            (0x02, vec![0x15]),
            (0x01, vec![0x3A, 0x01]),
            (0x01, vec![0x3A, 0x02]),
            (0x01, vec![0x3A, 0x06]),
            (0x02, vec![0x10, 0x01, 0x05, 0x00]),
            (GNET_BROADCAST, vec![0x03]),
        ];
        for (addr, payload) in cases {
            let msg = GNetMessage::new(addr, payload[0]).with_data(payload[1..].to_vec());
            assert!(
                forbidden_reason(addr, &msg.payload()).is_some(),
                "expected {payload:02X?} to be refused"
            );
        }
    }

    /// Byte-exact check against an independent capture: qlm's protocol doc
    /// ("A worked example") shows GLM's own volume frame at -56.5 dB as
    /// FF 1F 00 31 07 2C 5A 7E. If our CRC or byte order ever drifts, this fails.
    #[test]
    fn encodes_glms_volume_frame_byte_for_byte() {
        let msg =
            GNetMessage::new(GNET_BROADCAST, CID_VOLUME_GLM).with_data(vec![0x00, 0x31, 0x07]);
        assert_eq!(
            msg.encode(),
            vec![0xFF, 0x1F, 0x00, 0x31, 0x07, 0x2C, 0x5A, 0x7E]
        );
    }

    /// The same doc shows the adapter's "no monitor answered" frame escaping its
    /// own 0x7E payload: 01 7E 53 97 on the bus becomes 01 7D 5E 53 97 7E on USB.
    #[test]
    fn escapes_a_flag_byte_inside_the_payload() {
        let msg = GNetMessage::new(0x01, 0x7E);
        assert_eq!(msg.encode(), vec![0x01, 0x7E, 0x53, 0x97, 0x7E]);
        assert_eq!(
            HidTransport::ppp_escape(&msg.encode()),
            vec![0x01, 0x7D, 0x5E, 0x53, 0x97, 0x7E]
        );
    }

    #[test]
    fn allows_the_frames_we_actually_send() {
        let volume =
            GNetMessage::new(GNET_BROADCAST, CID_VOLUME_GLM).with_data(vec![0x00, 0x31, 0x07]);
        let wake = GNetMessage::new(GNET_BROADCAST, CID_WAKEUP).with_data(vec![0x03, 0x7F]);
        let probe = GNetMessage::new(GNET_BROADCAST, 0xFE);
        for msg in [volume, wake, probe] {
            assert_eq!(forbidden_reason(msg.address, &msg.payload()), None);
        }
    }
}
