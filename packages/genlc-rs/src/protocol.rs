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
        Self { address, command, data: vec![] }
    }

    pub fn with_data(mut self, data: Vec<u8>) -> Self {
        self.data = data;
        self
    }

    pub fn set_sint24(&mut self, value: i32) {
        let bytes = value.to_be_bytes();
        self.data = bytes[1..].to_vec();
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

    pub fn set_volume(&self, db: f64) -> Result<()> {
        let sint24 = db_to_sint24(db);
        let mut msg = GNetMessage::new(GNET_BROADCAST, CID_VOLUME_GLM);
        msg.set_sint24(sint24);
        self.transport.send(&msg)?;
        Ok(())
    }

    pub fn mute(&self) -> Result<()> {
        let msg = GNetMessage::new(GNET_BROADCAST, 0x08).with_data(vec![0x01]);
        self.transport.send(&msg)?;
        Ok(())
    }

    pub fn unmute(&self) -> Result<()> {
        let msg = GNetMessage::new(GNET_BROADCAST, 0x08).with_data(vec![0x00]);
        self.transport.send(&msg)?;
        Ok(())
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

    pub fn discover(&self) -> Result<()> {
        let msg = GNetMessage::new(GNET_BROADCAST, 0xFE);
        self.transport.send(&msg)?;
        for _ in 0..10 {
            match self.transport.receive() {
                Ok(raw) => {
                    if raw.len() < 5 { continue; }
                    let addr = raw[0];
                    let cmd = raw[1];
                    let data = &raw[2..raw.len() - 3];
                    println!("[{addr}] 0x{cmd:02X}: {}", String::from_utf8_lossy(data));
                }
                Err(_) => break,
            }
        }
        Ok(())
    }

    pub fn poll(&self, addr: u8) -> Result<()> {
        let msg = GNetMessage::new(addr, 0x08);
        self.transport.send(&msg)?;
        match self.transport.receive() {
            Ok(raw) => {
                if raw.len() < 2 { anyhow::bail!("Short response"); }
                println!("[{}] {} bytes: {:02x?}", raw[0], raw.len(), &raw);
            }
            Err(e) => eprintln!("no response: {e}"),
        }
        Ok(())
    }
}
