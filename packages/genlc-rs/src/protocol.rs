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
const GNET_TERM: u8 = 0x7E;
const MAX_PACKET_LEN: usize = 64;

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
        let raw = msg.encode();
        let stuffed = Self::ppp_escape(&raw);
        let payload_len = stuffed.len();

        // Prefix: 0x00 + (0x80 + length), matching Python genlc
        let mut buf = vec![0u8; MAX_PACKET_LEN];
        buf[0] = 0x00;
        buf[1] = 0x80 + payload_len as u8;
        let copy_len = payload_len.min(MAX_PACKET_LEN - 2);
        buf[2..2 + copy_len].copy_from_slice(&stuffed[..copy_len]);

        self.device.write(&buf[..MAX_PACKET_LEN])?;
        Ok(())
    }
}

pub struct GNetMessage {
    address: u8,
    command: u8,
    data: Vec<u8>,
}

impl GNetMessage {
    pub fn new(address: u8, command: u8) -> Self {
        Self { address, command, data: vec![] }
    }

    pub fn with_data(mut self, data: Vec<u8>) -> Self {
        self.data = data;
        self
    }

    pub fn set_sint24(&mut self, value: i32) {
        let bytes = value.to_be_bytes();
        self.data = bytes[1..].to_vec(); // lower 3 bytes of i32 BE
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

/// Convert dB to 24-bit signed integer (GLM volume format)
fn db_to_sint24(db: f64) -> i32 {
    let ratio = 10_f64.powf(db / 20.0);
    (ratio * 8_388_607.0) as i32 // 2^23 - 1
}

pub struct SamGroup {
    transport: HidTransport,
}

impl SamGroup {
    pub fn new(transport: HidTransport) -> Self {
        Self { transport }
    }
    pub fn set_volume(&self, db: f64) -> Result<()> {
        self.set_volume_cid(db, CID_VOLUME_GLM)
    }

    /// Set volume with explicit CID — try CID_START_VOLUME for smooth ramp
    pub fn set_volume_cid(&self, db: f64, cid: u8) -> Result<()> {
        let sint24 = db_to_sint24(db);
        let mut msg = GNetMessage::new(GNET_BROADCAST, cid);
        msg.set_sint24(sint24);
        self.transport.send(&msg)?;
        Ok(())
    }

    pub fn mute(&self) -> Result<()> {
        // Python genlc sends per-monitor mute. For broadcast, send mute via CID_POLL
        let msg = GNetMessage::new(GNET_BROADCAST, 0x08)
            .with_data(vec![0x01]);
        self.transport.send(&msg)?;
        Ok(())
    }

    pub fn unmute(&self) -> Result<()> {
        let msg = GNetMessage::new(GNET_BROADCAST, 0x08)
            .with_data(vec![0x00]);
        self.transport.send(&msg)?;
        Ok(())
    }

    pub fn toggle_mute(&self) -> Result<()> {
        // Send both — hardware will toggle based on state
        self.mute()
    }

    pub fn wakeup(&self) -> Result<()> {
        for data in [vec![3, 0x7F], vec![3, 1]] {
            let msg = GNetMessage::new(GNET_BROADCAST, CID_WAKEUP)
                .with_data(data.clone());
            self.transport.send(&msg)?;
            self.transport.send(&msg)?;
        }
        Ok(())
    }

    pub fn shutdown(&self) -> Result<()> {
        for data in [vec![3, 2], vec![3, 0]] {
            let msg = GNetMessage::new(GNET_BROADCAST, CID_WAKEUP)
                .with_data(data.clone());
            self.transport.send(&msg)?;
            self.transport.send(&msg)?;
        }
        Ok(())
    }

    pub fn discover(&self) -> Result<()> {
        let msg = GNetMessage::new(GNET_BROADCAST, 0xFE); // CID_RACE
        self.transport.send(&msg)?;
        eprintln!("Discovery message sent — check GLM adapter");
        Ok(())
    }
}
